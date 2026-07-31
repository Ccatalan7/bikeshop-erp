#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

readonly PRODUCTION_VALIDATION_PROJECT_REF="xzdvtzdqjeyqxnkqprtf"
readonly PRODUCTION_VALIDATION_DIRECT_HOST="db.${PRODUCTION_VALIDATION_PROJECT_REF}.supabase.co"
readonly PRODUCTION_VALIDATION_DIRECT_PORT="5432"
readonly PRODUCTION_VALIDATION_CONNECT_TIMEOUT_SECONDS="10"
readonly PRODUCTION_VALIDATION_CACHE_FORMAT="3-direct-ipv6-public-acl"
readonly PRODUCTION_VALIDATION_CATALOG_SQL="$DB_ROOT/scripts/db/production_validation_catalog.sql"
readonly PRODUCTION_VALIDATION_ACL_ROLES_SQL="$DB_ROOT/scripts/db/production_validation_acl_roles.sql"
readonly PRODUCTION_VALIDATION_ROOT="${VINABIKE_PROD_VALIDATION_ROOT:-$DB_CACHE_DIR/production-validation}"
readonly PRODUCTION_VALIDATION_BASELINES="$PRODUCTION_VALIDATION_ROOT/baselines"
readonly PRODUCTION_VALIDATION_TASKS="$PRODUCTION_VALIDATION_ROOT/tasks"
readonly PRODUCTION_VALIDATION_LOCKS="$PRODUCTION_VALIDATION_ROOT/locks"
readonly PRODUCTION_VALIDATION_LOGS="$PRODUCTION_VALIDATION_ROOT/logs"
readonly PRODUCTION_VALIDATION_LOCK_TIMEOUT="${VINABIKE_PROD_VALIDATION_LOCK_TIMEOUT_SECONDS:-180}"
readonly PRODUCTION_VALIDATION_ACL_ROLE_COMMENT="vinabike production validation compatibility role"

PRODUCTION_VALIDATION_HELD_LOCKS=()
PRODUCTION_VALIDATION_ACTIVE_BUILD_DB=""
PRODUCTION_VALIDATION_ACTIVE_CAPTURE_DIR=""
PRODUCTION_VALIDATION_ACTIVE_IDENTITY_DIR=""
PRODUCTION_VALIDATION_LOCAL_DB_URL=""

mkdir -p \
  "$PRODUCTION_VALIDATION_BASELINES" \
  "$PRODUCTION_VALIDATION_TASKS" \
  "$PRODUCTION_VALIDATION_LOCKS" \
  "$PRODUCTION_VALIDATION_LOGS"

production_validation_usage() {
  cat <<'USAGE'
Usage:
  scripts/db/production_validation.sh prepare --task TASK [--migration FILE ...]
  scripts/db/production_validation.sh reuse --task TASK [--migration FILE ...]
  scripts/db/production_validation.sh refresh --task TASK [--migration FILE ...]
  scripts/db/production_validation.sh test --task TASK [--migration FILE ...] [--test SELECTOR ...]
  scripts/db/production_validation.sh status [--task TASK]
  scripts/db/production_validation.sh cleanup (--task TASK | --all) [--include-templates]

Commands:
  prepare   Read the exact live production catalog identity. Reuse its cached
            immutable template, or take one schema-only dump when no matching
            template exists. Create/reuse a cheap task scratch database.
  reuse     Make no production/network call. Reuse the last cached immutable
            template and create/reuse the task scratch database.
  refresh   Read production and force one new schema-only capture/template,
            even when the exact catalog identity is already cached.
  test      Make no production/network call. Apply only production-absent
            migration files to the task scratch database, then run focused
            pgTAP files there. Repeated tests reuse the same scratch database.
  status    Report cached evidence and local database state without contacting
            production or starting the local Supabase stack.
  cleanup   Delete guarded local scratch databases. Templates/captures are
            retained unless --include-templates is explicitly supplied with
            --all.

Selectors are matched against supabase/tests/*SELECTOR*.sql. With no --test,
all pgTAP files run. Migration files must live under supabase/migrations/.
USAGE
}

production_validation_hash_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

production_validation_hash_text() {
  printf '%s' "$1" | production_validation_hash_stream
}

production_validation_cache_key() {
  local server_version_num="$1"
  local migration_head="$2"
  local catalog_fingerprint="$3"

  printf '%s\n%s\n%s\n%s\n%s\n' \
    "$PRODUCTION_VALIDATION_CACHE_FORMAT" \
    "$PRODUCTION_VALIDATION_PROJECT_REF" \
    "$server_version_num" \
    "$migration_head" \
    "$catalog_fingerprint" |
    production_validation_hash_stream
}

production_validation_validate_task() {
  local task="$1"
  [[ "$task" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] ||
    die "Task must use 1-64 letters, numbers, dots, underscores or hyphens"
}

production_validation_task_hash() {
  production_validation_hash_text "$1" | cut -c1-16
}

production_validation_task_lock_name() {
  printf 'task-%s\n' "$(production_validation_task_hash "$1")"
}

production_validation_release_lock() {
  local lock_dir="$1"
  local retained=()
  local held

  [[ -n "$lock_dir" ]] || return 0
  if [[ -d "$lock_dir" ]]; then
    rm -f "$lock_dir/owner"
    rmdir "$lock_dir" 2>/dev/null || true
  fi

  if ((${#PRODUCTION_VALIDATION_HELD_LOCKS[@]} > 0)); then
    for held in "${PRODUCTION_VALIDATION_HELD_LOCKS[@]}"; do
      [[ "$held" == "$lock_dir" ]] || retained+=("$held")
    done
  fi
  PRODUCTION_VALIDATION_HELD_LOCKS=()
  if ((${#retained[@]} > 0)); then
    PRODUCTION_VALIDATION_HELD_LOCKS=("${retained[@]}")
  fi
}

production_validation_release_all_locks() {
  local index
  for ((index = ${#PRODUCTION_VALIDATION_HELD_LOCKS[@]} - 1; index >= 0; index--)); do
    production_validation_release_lock \
      "${PRODUCTION_VALIDATION_HELD_LOCKS[$index]}"
  done
}

production_validation_lock_is_stale() {
  local lock_dir="$1"
  local owner_file="$lock_dir/owner"
  local owner_pid=""
  local owner_host=""
  local current_host

  [[ -f "$owner_file" ]] || return 1
  owner_pid="$(awk -F= '$1 == "pid" { print $2; exit }' "$owner_file")"
  owner_host="$(awk -F= '$1 == "host" { print $2; exit }' "$owner_file")"
  current_host="$(hostname)"

  [[ "$owner_pid" =~ ^[0-9]+$ ]] || return 1
  [[ "$owner_host" == "$current_host" ]] || return 1
  ! kill -0 "$owner_pid" 2>/dev/null
}

production_validation_acquire_lock() {
  local name="$1"
  local lock_dir="$PRODUCTION_VALIDATION_LOCKS/$name"
  local waited=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    if production_validation_lock_is_stale "$lock_dir"; then
      rm -f "$lock_dir/owner"
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi
    if ((waited >= PRODUCTION_VALIDATION_LOCK_TIMEOUT)); then
      die "Timed out waiting for production validation lock '$name'"
    fi
    sleep 1
    waited=$((waited + 1))
  done

  printf 'pid=%s\nhost=%s\nstarted_utc=%s\n' \
    "$$" \
    "$(hostname)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"$lock_dir/owner"
  PRODUCTION_VALIDATION_HELD_LOCKS+=("$lock_dir")
}

production_validation_local_url_for() {
  local database_name="$1"
  local base_url="${PRODUCTION_VALIDATION_LOCAL_DB_URL%/*}"
  printf '%s/%s\n' "$base_url" "$database_name"
}

production_validation_local_admin_url_for() {
  local database_name="$1"
  local local_url

  local_url="$(production_validation_local_url_for "$database_name")"
  case "$local_url" in
    postgresql://postgres:*@127.0.0.1:*/*)
      printf 'postgresql://supabase_admin:%s\n' \
        "${local_url#postgresql://postgres:}"
      ;;
    postgres://postgres:*@127.0.0.1:*/*)
      printf 'postgres://supabase_admin:%s\n' \
        "${local_url#postgres://postgres:}"
      ;;
    *)
      die "Local Supabase admin URL is not an approved loopback connection"
      ;;
  esac
}

production_validation_database_exists() {
  local database_name="$1"
  [[ -n "$PRODUCTION_VALIDATION_LOCAL_DB_URL" ]] || return 1
  production_validation_validate_database_name "$database_name"
  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -XAtqc "select 1 from pg_database where datname = '$database_name'" \
    2>/dev/null |
    grep -qx 1
}

production_validation_database_template_state() {
  local database_name="$1"
  production_validation_validate_database_name "$database_name"
  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -XAtqc \
    "select datistemplate::integer || '|' || datallowconn::integer
       from pg_database
      where datname = '$database_name'" \
    2>/dev/null
}

production_validation_validate_database_name() {
  local database_name="$1"
  [[ "$database_name" =~ ^vpv_[stb]_[a-z0-9_]{1,52}$ ]] ||
    die "Refusing unrecognized disposable database name '$database_name'"
}

production_validation_drop_database() {
  local database_name="$1"
  local template_state

  [[ -n "$database_name" ]] || return 0
  production_validation_validate_database_name "$database_name"
  production_validation_database_exists "$database_name" || return 0

  template_state="$(production_validation_database_template_state "$database_name")"
  if [[ "$template_state" == "1|0" ]]; then
    PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
      -X -v ON_ERROR_STOP=1 \
      -c "alter database \"$database_name\" with is_template false allow_connections true" \
      >/dev/null
  fi

  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -XAtq -v ON_ERROR_STOP=1 \
    -c "select pg_terminate_backend(pid)
          from pg_stat_activity
         where datname = '$database_name'
           and pid <> pg_backend_pid()" \
    >/dev/null
  PGOPTIONS='' dropdb \
    --maintenance-db="$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    --if-exists \
    "$database_name"
}

production_validation_cleanup_on_exit() {
  local status=$?

  if [[ -n "$PRODUCTION_VALIDATION_ACTIVE_BUILD_DB" ]] &&
    [[ -n "$PRODUCTION_VALIDATION_LOCAL_DB_URL" ]]; then
    production_validation_drop_database \
      "$PRODUCTION_VALIDATION_ACTIVE_BUILD_DB" >/dev/null 2>&1 || true
  fi
  case "$PRODUCTION_VALIDATION_ACTIVE_CAPTURE_DIR" in
    "$PRODUCTION_VALIDATION_ROOT"/capture.*)
      rm -rf "$PRODUCTION_VALIDATION_ACTIVE_CAPTURE_DIR"
      ;;
  esac
  case "$PRODUCTION_VALIDATION_ACTIVE_IDENTITY_DIR" in
    "$PRODUCTION_VALIDATION_ROOT"/identity.*)
      rm -rf "$PRODUCTION_VALIDATION_ACTIVE_IDENTITY_DIR"
      ;;
  esac
  production_validation_release_all_locks
  unset \
    PGPASSWORD \
    PGHOST \
    PGPORT \
    PGDATABASE \
    PGUSER \
    PGOPTIONS \
    PGCONNECT_TIMEOUT
  return "$status"
}

production_validation_ensure_local_runtime() {
  require_command psql
  require_command pg_dump
  require_command pg_restore
  require_command createdb
  require_command dropdb
  ensure_docker

  run_supabase_cli status >/dev/null 2>&1 ||
    run_supabase_cli db start >/dev/null
  PRODUCTION_VALIDATION_LOCAL_DB_URL="$(local_db_url)"
  [[ "$PRODUCTION_VALIDATION_LOCAL_DB_URL" == postgresql://* ]] ||
    die "Local Supabase did not report a PostgreSQL database URL"
}

production_validation_try_local_runtime() {
  [[ -x "$SUPABASE_CLI_WRAPPER" ]] || return 1
  run_supabase_cli status >/dev/null 2>&1 || return 1
  PRODUCTION_VALIDATION_LOCAL_DB_URL="$(local_db_url)"
  [[ -n "$PRODUCTION_VALIDATION_LOCAL_DB_URL" ]]
}

production_validation_guard_production_connection() {
  local linked_ref

  [[ -f "$DB_ROOT/supabase/.temp/project-ref" ]] ||
    die "Linked Supabase project identity is unavailable"
  linked_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  [[ "$linked_ref" == "$PRODUCTION_VALIDATION_PROJECT_REF" ]] ||
    die "Linked project is not the approved production project"

  PGHOST="$PRODUCTION_VALIDATION_DIRECT_HOST"
  PGPORT="$PRODUCTION_VALIDATION_DIRECT_PORT"
  PGDATABASE="postgres"
  PGUSER="postgres"
  PGPASSWORD="$(
    credential_value \
      'Vinabike ERP Supabase database password' \
      postgres \
      SUPABASE_DB_PASSWORD
  )"
  PGCONNECT_TIMEOUT="$PRODUCTION_VALIDATION_CONNECT_TIMEOUT_SECONDS"
  export \
    PGHOST \
    PGPORT \
    PGDATABASE \
    PGUSER \
    PGPASSWORD \
    PGCONNECT_TIMEOUT

  [[ "$PGHOST" == "db.${linked_ref}.supabase.co" ]] ||
    die "Production validation direct host does not match the approved project"
  [[ "$PGPORT" == "5432" && "$PGDATABASE" == "postgres" &&
    "$PGUSER" == "postgres" ]] ||
    die "Production validation direct connection parameters are invalid"

  export PGOPTIONS
  PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=120000 -c search_path=public,extensions,pg_catalog"

  production_validation_verify_direct_connection
}

production_validation_verify_direct_connection() {
  local connection_identity
  local server_address
  local server_port
  local database_user
  local database_name

  connection_identity="$(
    psql "dbname=postgres" \
      -XAtq \
      -F $'\t' \
      -v ON_ERROR_STOP=1 \
      -c "select inet_server_addr()::text,
                 inet_server_port(),
                 current_user,
                 current_database()"
  )"
  [[ "$(printf '%s\n' "$connection_identity" | wc -l | tr -d '[:space:]')" == "1" ]] ||
    die "Production direct-connection preflight returned an unexpected result"
  IFS=$'\t' read -r \
    server_address \
    server_port \
    database_user \
    database_name \
    <<<"$connection_identity"

  [[ "$server_address" == *:* ]] ||
    die "Production direct endpoint did not establish the required IPv6 connection"
  [[ "$server_port" == "$PRODUCTION_VALIDATION_DIRECT_PORT" ]] ||
    die "Production direct endpoint reported an unexpected server port"
  [[ "$database_user" == "postgres" && "$database_name" == "postgres" ]] ||
    die "Production direct endpoint identity is not the approved database"
}

production_validation_clear_remote_connection() {
  unset \
    PGPASSWORD \
    PGHOST \
    PGPORT \
    PGDATABASE \
    PGUSER \
    PGOPTIONS \
    PGCONNECT_TIMEOUT
}

production_validation_fetch_live_identity() {
  local output_file="$1"
  local versions_file="$2"
  local acl_roles_file="$3"

  production_validation_guard_production_connection
  psql "dbname=postgres" \
    -XAtq \
    -F $'\t' \
    -v ON_ERROR_STOP=1 \
    -f "$PRODUCTION_VALIDATION_CATALOG_SQL" \
    >"$output_file"
  [[ "$(wc -l <"$output_file" | tr -d '[:space:]')" == "1" ]] ||
    die "Production catalog identity query did not return exactly one row"

  psql "dbname=postgres" \
    -XAtq \
    -v ON_ERROR_STOP=1 \
    -c "select version
          from supabase_migrations.schema_migrations
         order by version" \
    >"$versions_file"
  if [[ -s "$versions_file" ]] &&
    ! awk '/^[0-9]+$/ { next } { exit 1 }' "$versions_file"; then
    die "Production migration history contained an unexpected version value"
  fi

  psql "dbname=postgres" \
    -XAtq \
    -v ON_ERROR_STOP=1 \
    -f "$PRODUCTION_VALIDATION_ACL_ROLES_SQL" \
    >"$acl_roles_file"
  if [[ -s "$acl_roles_file" ]] &&
    ! awk '
      !/^[0-9a-f]+$/ || length($0) % 2 != 0 { exit 1 }
    ' \
      "$acl_roles_file"; then
    die "Production ACL role manifest contained an invalid encoded role"
  fi
}

production_validation_read_identity() {
  local identity_file="$1"
  local line

  line="$(<"$identity_file")"
  IFS=$'\t' read -r \
    PRODUCTION_VALIDATION_SERVER_VERSION_NUM \
    PRODUCTION_VALIDATION_SERVER_VERSION \
    PRODUCTION_VALIDATION_MIGRATION_HEAD \
    PRODUCTION_VALIDATION_MIGRATION_HISTORY_FINGERPRINT \
    PRODUCTION_VALIDATION_CATALOG_FINGERPRINT \
    <<<"$line"

  [[ "$PRODUCTION_VALIDATION_SERVER_VERSION_NUM" =~ ^[0-9]+$ ]] ||
    die "Invalid production PostgreSQL version identity"
  [[ "$PRODUCTION_VALIDATION_MIGRATION_HEAD" == "none" ||
    "$PRODUCTION_VALIDATION_MIGRATION_HEAD" =~ ^[0-9]+$ ]] ||
    die "Invalid production migration head"
  [[ "$PRODUCTION_VALIDATION_MIGRATION_HISTORY_FINGERPRINT" =~ ^[0-9a-f]{32}$ ]] ||
    die "Invalid production migration-history fingerprint"
  [[ "$PRODUCTION_VALIDATION_CATALOG_FINGERPRINT" =~ ^[0-9a-f]{32}$ ]] ||
    die "Invalid production catalog fingerprint"

  PRODUCTION_VALIDATION_KEY="$(
    production_validation_cache_key \
      "$PRODUCTION_VALIDATION_SERVER_VERSION_NUM" \
      "$PRODUCTION_VALIDATION_MIGRATION_HEAD" \
      "$PRODUCTION_VALIDATION_CATALOG_FINGERPRINT"
  )"
}

production_validation_atomic_pointer() {
  local destination="$1"
  local value="$2"
  local temporary="$destination.tmp.$$"

  printf '%s\n' "$value" >"$temporary"
  mv "$temporary" "$destination"
}

production_validation_metadata_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

production_validation_record_observation() {
  local baseline_dir="$1"
  local identity_file="$2"
  local versions_file="$3"
  local acl_roles_file="$4"
  local observation_id
  local observation_dir

  observation_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  observation_dir="$baseline_dir/observations/$observation_id"
  mkdir -p "$observation_dir"
  cp "$versions_file" "$observation_dir/production-migrations.txt"
  cp "$acl_roles_file" "$observation_dir/production-acl-roles.txt"
  printf '%s\n' \
    "cache_format=$PRODUCTION_VALIDATION_CACHE_FORMAT" \
    "project_ref=$PRODUCTION_VALIDATION_PROJECT_REF" \
    "observed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "server_version_num=$PRODUCTION_VALIDATION_SERVER_VERSION_NUM" \
    "server_version=$PRODUCTION_VALIDATION_SERVER_VERSION" \
    "migration_head=$PRODUCTION_VALIDATION_MIGRATION_HEAD" \
    "migration_history_fingerprint=$PRODUCTION_VALIDATION_MIGRATION_HISTORY_FINGERPRINT" \
    "catalog_fingerprint=$PRODUCTION_VALIDATION_CATALOG_FINGERPRINT" \
    "cache_key=$PRODUCTION_VALIDATION_KEY" \
    >"$observation_dir/metadata"
  cp "$identity_file" "$observation_dir/catalog-identity.tsv"
  chmod 0444 \
    "$observation_dir/metadata" \
    "$observation_dir/catalog-identity.tsv" \
    "$observation_dir/production-migrations.txt" \
    "$observation_dir/production-acl-roles.txt"
  production_validation_atomic_pointer \
    "$baseline_dir/current-observation" \
    "$observation_id"
  PRODUCTION_VALIDATION_OBSERVATION_ID="$observation_id"
}

production_validation_verify_schema_only_toc() {
  local toc_file="$1"
  if grep -Eq \
    '[[:space:]](TABLE DATA|BLOB|BLOBS|LARGE OBJECT DATA)[[:space:]]' \
    "$toc_file"; then
    die "Production archive unexpectedly contains row/blob data"
  fi
}

production_validation_verify_acl_toc() {
  local toc_file="$1"
  grep -Eq '[[:space:]](ACL|DEFAULT ACL)[[:space:]]' "$toc_file" ||
    die "Production archive contains no public-schema ACL entries"
}

production_validation_prepare_acl_roles() {
  local capture_dir="$1"
  local admin_url
  local role_hex
  local role_exists

  admin_url="$(production_validation_local_admin_url_for postgres)"
  [[ -f "$capture_dir/production-acl-roles.txt" ]] ||
    die "Production ACL role manifest is missing"
  while IFS= read -r role_hex; do
    [[ -n "$role_hex" ]] || continue
    if [[ ! "$role_hex" =~ ^[0-9a-f]+$ ]] ||
      ((${#role_hex} % 2 != 0)); then
      die "Production ACL role manifest contains invalid encoding"
    fi
    role_exists="$(
      PGOPTIONS='' psql "$admin_url" \
        -XAtq \
        -v ON_ERROR_STOP=1 \
        -v "role_hex=$role_hex" <<'SQL'
select 1
from pg_roles
where rolname = convert_from(decode(:'role_hex', 'hex'), 'UTF8');
SQL
    )"
    [[ "$role_exists" == "1" ]] && continue

    PGOPTIONS='' psql "$admin_url" \
      -Xq \
      -v ON_ERROR_STOP=1 \
      -v "role_hex=$role_hex" \
      -v "role_comment=$PRODUCTION_VALIDATION_ACL_ROLE_COMMENT" <<'SQL'
select format(
  'create role %I nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls',
  convert_from(decode(:'role_hex', 'hex'), 'UTF8')
)
\gexec
select format(
      'comment on role %I is %L',
      convert_from(decode(:'role_hex', 'hex'), 'UTF8'),
      :'role_comment'
    )
\gexec
SQL
  done <"$capture_dir/production-acl-roles.txt"
}

production_validation_split_managed_post_data() {
  local input_file="$1"
  local early_file="$2"
  local late_file="$3"

  : >"$early_file"
  : >"$late_file"
  awk \
    -v early_file="$early_file" \
    -v late_file="$late_file" '
      function flush_statement() {
        if (statement == "") {
          return
        }
        if (statement ~ /public\./) {
          printf "%s", statement >> late_file
        } else {
          printf "%s", statement >> early_file
        }
        statement = ""
      }

      {
        statement = statement $0 ORS
        if ($0 ~ /;[[:space:]]*$/) {
          flush_statement()
        }
      }

      END {
        flush_statement()
      }
    ' "$input_file"
}

production_validation_prepare_managed_schema_files() {
  local capture_dir="$1"

  PGOPTIONS='' pg_dump \
    --schema-only \
    --no-owner \
    --no-privileges \
    --section=pre-data \
    --schema=auth \
    --schema=storage \
    --file="$capture_dir/local-managed-pre.sql" \
    "$PRODUCTION_VALIDATION_LOCAL_DB_URL"

  PGOPTIONS='' pg_dump \
    --schema-only \
    --no-owner \
    --no-privileges \
    --section=post-data \
    --schema=auth \
    --schema=storage \
    --file="$capture_dir/local-managed-post.sql" \
    "$PRODUCTION_VALIDATION_LOCAL_DB_URL"

  production_validation_split_managed_post_data \
    "$capture_dir/local-managed-post.sql" \
    "$capture_dir/local-managed-post-early.sql" \
    "$capture_dir/local-managed-post-late.sql"
}

production_validation_build_template() {
  local capture_dir="$1"
  local template_db="$2"
  local build_hash
  local build_db
  local build_url
  local build_admin_url
  local template_state
  local restore_log
  restore_log="$PRODUCTION_VALIDATION_LOGS/template-${template_db}-$(date -u +%Y%m%dT%H%M%SZ).log"

  production_validation_validate_database_name "$template_db"
  if production_validation_database_exists "$template_db"; then
    template_state="$(production_validation_database_template_state "$template_db")"
    [[ "$template_state" == "1|0" ]] ||
      die "Existing template database '$template_db' is not immutable"
    return 0
  fi

  build_hash="$(production_validation_hash_text "$template_db-$$-$(date -u +%s)")"
  build_db="vpv_b_$(printf '%s' "$build_hash" | cut -c1-24)"
  production_validation_validate_database_name "$build_db"
  PRODUCTION_VALIDATION_ACTIVE_BUILD_DB="$build_db"

  production_validation_prepare_acl_roles "$capture_dir"
  PGOPTIONS='' createdb \
    --maintenance-db="$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    --template=template0 \
    "$build_db"
  build_url="$(production_validation_local_url_for "$build_db")"
  build_admin_url="$(production_validation_local_admin_url_for "$build_db")"

  PGOPTIONS='' psql "$build_url" -X -v ON_ERROR_STOP=1 -q <<'SQL'
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists vector with schema public;
create extension if not exists pg_trgm with schema public;
create extension if not exists unaccent with schema public;
create schema if not exists vault;
create extension if not exists supabase_vault with schema vault;
SQL

  if ! PGOPTIONS="-c check_function_bodies=off" \
    psql "$build_url" -X -v ON_ERROR_STOP=1 \
      -f "$capture_dir/local-managed-pre.sql" \
      >"$restore_log" 2>&1; then
    tail -60 "$restore_log" >&2
    die "Managed pre-data restore failed; full log: $restore_log"
  fi
  if ! PGOPTIONS="-c check_function_bodies=off" \
    psql "$build_url" -X -v ON_ERROR_STOP=1 \
      -f "$capture_dir/local-managed-post-early.sql" \
      >>"$restore_log" 2>&1; then
    tail -60 "$restore_log" >&2
    die "Managed early post-data restore failed; full log: $restore_log"
  fi
  if ! PGOPTIONS="-c check_function_bodies=off" \
    psql "$build_url" -X -v ON_ERROR_STOP=1 \
      -f "$capture_dir/production-public-restore.sql" \
      >>"$restore_log" 2>&1; then
    tail -60 "$restore_log" >&2
    die "Production public-schema restore failed; full log: $restore_log"
  fi
  if [[ -s "$capture_dir/production-public-admin-default-acl.sql" ]] &&
    ! PGOPTIONS="-c check_function_bodies=off" \
      psql "$build_admin_url" -X -v ON_ERROR_STOP=1 \
        -f "$capture_dir/production-public-admin-default-acl.sql" \
        >>"$restore_log" 2>&1; then
    tail -60 "$restore_log" >&2
    die "Production admin-owned default ACL restore failed; full log: $restore_log"
  fi
  if ! PGOPTIONS="-c check_function_bodies=off" \
    psql "$build_url" -X -v ON_ERROR_STOP=1 \
      -f "$capture_dir/local-managed-post-late.sql" \
      >>"$restore_log" 2>&1; then
    tail -60 "$restore_log" >&2
    die "Managed late post-data restore failed; full log: $restore_log"
  fi
  PGOPTIONS='' psql "$build_url" -X -v ON_ERROR_STOP=1 -q \
    -c 'create extension if not exists pgtap with schema public;'

  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -X -v ON_ERROR_STOP=1 \
    -c "alter database \"$build_db\" rename to \"$template_db\"" \
    >/dev/null
  PRODUCTION_VALIDATION_ACTIVE_BUILD_DB="$template_db"
  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -X -v ON_ERROR_STOP=1 \
    -c "alter database \"$template_db\" with is_template true allow_connections false" \
    >/dev/null
  PRODUCTION_VALIDATION_ACTIVE_BUILD_DB=""
}

production_validation_capture_template_name() {
  local key="$1"
  local archive_sha="$2"
  printf 'vpv_t_%s_%s\n' \
    "$(printf '%s' "$key" | cut -c1-12)" \
    "$(printf '%s' "$archive_sha" | cut -c1-12)"
}

production_validation_create_capture() {
  local baseline_dir="$1"
  local work_dir
  local dump_utc
  local archive_sha
  local archive_bytes
  local capture_id
  local capture_dir
  local template_db

  work_dir="$(mktemp -d "$PRODUCTION_VALIDATION_ROOT/capture.XXXXXX")"
  PRODUCTION_VALIDATION_ACTIVE_CAPTURE_DIR="$work_dir"
  dump_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  pg_dump \
    --format=custom \
    --schema-only \
    --no-owner \
    --schema=public \
    --file="$work_dir/production-public.dump" \
    "dbname=postgres"
  [[ -s "$work_dir/production-public.dump" ]] ||
    die "Production schema-only dump is empty"

  pg_restore --list "$work_dir/production-public.dump" \
    >"$work_dir/production-public.toc"
  production_validation_verify_schema_only_toc \
    "$work_dir/production-public.toc"
  production_validation_verify_acl_toc \
    "$work_dir/production-public.toc"
  pg_restore \
    --schema-only \
    --no-owner \
    --file="$work_dir/production-public.sql" \
    "$work_dir/production-public.dump"
  [[ -s "$work_dir/production-public.sql" ]] ||
    die "Production schema archive did not render to SQL"
  sed \
    's/^CREATE SCHEMA public;$/CREATE SCHEMA IF NOT EXISTS public;/' \
    "$work_dir/production-public.sql" \
    >"$work_dir/production-public-normalized.sql"
  grep -Ev \
    '^ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin ' \
    "$work_dir/production-public-normalized.sql" \
    >"$work_dir/production-public-restore.sql"
  grep -E \
    '^ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin ' \
    "$work_dir/production-public-normalized.sql" \
    >"$work_dir/production-public-admin-default-acl.sql" ||
    :

  archive_sha="$(sha256_file "$work_dir/production-public.dump")"
  archive_bytes="$(wc -c <"$work_dir/production-public.dump" | tr -d '[:space:]')"
  capture_id="$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%s' "$archive_sha" | cut -c1-12)-$$"
  capture_dir="$baseline_dir/captures/$capture_id"
  template_db="$(
    production_validation_capture_template_name \
      "$PRODUCTION_VALIDATION_KEY" \
      "$archive_sha"
  )"

  cp \
    "$baseline_dir/observations/$PRODUCTION_VALIDATION_OBSERVATION_ID/production-acl-roles.txt" \
    "$work_dir/production-acl-roles.txt"
  production_validation_clear_remote_connection
  production_validation_prepare_managed_schema_files "$work_dir"
  production_validation_build_template "$work_dir" "$template_db"

  printf '%s\n' \
    "cache_format=$PRODUCTION_VALIDATION_CACHE_FORMAT" \
    "project_ref=$PRODUCTION_VALIDATION_PROJECT_REF" \
    "dump_utc=$dump_utc" \
    "scope=schema-only-public-no-production-rows" \
    "acl_scope=production-public-acls-restored" \
    "default_acl_scope=postgres-and-supabase-admin-restored" \
    "owner_scope=object-owners-omitted" \
    "archive_sha256=$archive_sha" \
    "archive_bytes=$archive_bytes" \
    "server_version_num=$PRODUCTION_VALIDATION_SERVER_VERSION_NUM" \
    "server_version=$PRODUCTION_VALIDATION_SERVER_VERSION" \
    "migration_head=$PRODUCTION_VALIDATION_MIGRATION_HEAD" \
    "migration_history_fingerprint=$PRODUCTION_VALIDATION_MIGRATION_HISTORY_FINGERPRINT" \
    "catalog_fingerprint=$PRODUCTION_VALIDATION_CATALOG_FINGERPRINT" \
    "cache_key=$PRODUCTION_VALIDATION_KEY" \
    "template_database=$template_db" \
    >"$work_dir/metadata"

  mkdir -p "$baseline_dir/captures"
  mv "$work_dir" "$capture_dir"
  PRODUCTION_VALIDATION_ACTIVE_CAPTURE_DIR=""
  chmod 0444 "$capture_dir"/* 2>/dev/null || true
  production_validation_atomic_pointer \
    "$baseline_dir/current-capture" \
    "$capture_id"

  PRODUCTION_VALIDATION_CAPTURE_ID="$capture_id"
  PRODUCTION_VALIDATION_TEMPLATE_DB="$template_db"
}

production_validation_load_capture() {
  local baseline_dir="$1"
  local capture_pointer="$baseline_dir/current-capture"
  local capture_dir
  local archive_sha

  [[ -s "$capture_pointer" ]] ||
    die "Cached baseline has no current immutable capture; run refresh"
  PRODUCTION_VALIDATION_CAPTURE_ID="$(<"$capture_pointer")"
  capture_dir="$baseline_dir/captures/$PRODUCTION_VALIDATION_CAPTURE_ID"
  [[ -d "$capture_dir" && -f "$capture_dir/metadata" ]] ||
    die "Cached production capture is incomplete; run refresh"
  [[ "$(
    production_validation_metadata_value "$capture_dir/metadata" cache_format
  )" == "$PRODUCTION_VALIDATION_CACHE_FORMAT" ]] ||
    die "Cached production capture format is obsolete; run prepare"
  [[ "$(
    production_validation_metadata_value "$capture_dir/metadata" acl_scope
  )" == "production-public-acls-restored" ]] ||
    die "Cached production capture does not preserve public ACLs; run prepare"

  archive_sha="$(production_validation_metadata_value "$capture_dir/metadata" archive_sha256)"
  [[ "$archive_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die "Cached production archive metadata is invalid"
  [[ "$(sha256_file "$capture_dir/production-public.dump")" == "$archive_sha" ]] ||
    die "Cached production schema archive checksum changed; run refresh"
  production_validation_verify_schema_only_toc \
    "$capture_dir/production-public.toc"
  production_validation_verify_acl_toc \
    "$capture_dir/production-public.toc"

  PRODUCTION_VALIDATION_TEMPLATE_DB="$(
    production_validation_metadata_value \
      "$capture_dir/metadata" \
      template_database
  )"
  production_validation_validate_database_name \
    "$PRODUCTION_VALIDATION_TEMPLATE_DB"
  production_validation_build_template \
    "$capture_dir" \
    "$PRODUCTION_VALIDATION_TEMPLATE_DB"
}

production_validation_load_observation() {
  local baseline_dir="$1"
  local observation_pointer="$baseline_dir/current-observation"
  local observation_dir

  [[ -s "$observation_pointer" ]] ||
    die "Cached baseline has no production observation; run prepare"
  PRODUCTION_VALIDATION_OBSERVATION_ID="$(<"$observation_pointer")"
  observation_dir="$baseline_dir/observations/$PRODUCTION_VALIDATION_OBSERVATION_ID"
  [[ -f "$observation_dir/metadata" &&
    -f "$observation_dir/production-migrations.txt" &&
    -f "$observation_dir/production-acl-roles.txt" ]] ||
    die "Cached production observation is incomplete; run prepare"
  [[ "$(
    production_validation_metadata_value "$observation_dir/metadata" cache_format
  )" == "$PRODUCTION_VALIDATION_CACHE_FORMAT" ]] ||
    die "Cached production observation format is obsolete; run prepare"
}

production_validation_write_task_state() {
  local task="$1"
  local scratch_db="$2"
  local task_dir="$PRODUCTION_VALIDATION_TASKS/$task"
  local state_tmp="$task_dir/state.tmp.$$"

  mkdir -p "$task_dir"
  printf '%s\n' \
    "task=$task" \
    "cache_key=$PRODUCTION_VALIDATION_KEY" \
    "capture_id=$PRODUCTION_VALIDATION_CAPTURE_ID" \
    "observation_id=$PRODUCTION_VALIDATION_OBSERVATION_ID" \
    "template_database=$PRODUCTION_VALIDATION_TEMPLATE_DB" \
    "scratch_database=$scratch_db" \
    "updated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >"$state_tmp"
  mv "$state_tmp" "$task_dir/state"
  [[ -f "$task_dir/applied-migrations.tsv" ]] ||
    : >"$task_dir/applied-migrations.tsv"
}

production_validation_task_state_value() {
  local task="$1"
  local key="$2"
  production_validation_metadata_value \
    "$PRODUCTION_VALIDATION_TASKS/$task/state" \
    "$key"
}

production_validation_create_scratch() {
  local task="$1"
  local task_hash
  local capture_hash
  local scratch_db
  local scratch_url

  task_hash="$(production_validation_task_hash "$task")"
  capture_hash="$(production_validation_hash_text "$PRODUCTION_VALIDATION_CAPTURE_ID")"
  scratch_db="vpv_s_${task_hash}_$(printf '%s' "$capture_hash" | cut -c1-16)"
  production_validation_validate_database_name "$scratch_db"

  if production_validation_database_exists "$scratch_db"; then
    production_validation_drop_database "$scratch_db"
  fi
  PGOPTIONS='' createdb \
    --maintenance-db="$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    --template="$PRODUCTION_VALIDATION_TEMPLATE_DB" \
    "$scratch_db"
  scratch_url="$(production_validation_local_url_for "$scratch_db")"
  PGOPTIONS='' psql "$scratch_url" -XAtq -v ON_ERROR_STOP=1 \
    -c "select current_database()" |
    grep -qx "$scratch_db" ||
    die "Scratch database identity check failed"

  production_validation_write_task_state "$task" "$scratch_db"
  : >"$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv"
  PRODUCTION_VALIDATION_SCRATCH_DB="$scratch_db"
}

production_validation_ensure_task_scratch() {
  local task="$1"
  local state_file="$PRODUCTION_VALIDATION_TASKS/$task/state"
  local state_key=""
  local state_capture=""
  local state_scratch=""

  if [[ -f "$state_file" ]]; then
    state_key="$(production_validation_task_state_value "$task" cache_key)"
    state_capture="$(production_validation_task_state_value "$task" capture_id)"
    state_scratch="$(production_validation_task_state_value "$task" scratch_database)"
  fi

  if [[ "$state_key" == "$PRODUCTION_VALIDATION_KEY" &&
    "$state_capture" == "$PRODUCTION_VALIDATION_CAPTURE_ID" &&
    -n "$state_scratch" ]] &&
    production_validation_database_exists "$state_scratch"; then
    PRODUCTION_VALIDATION_SCRATCH_DB="$state_scratch"
    production_validation_write_task_state "$task" "$state_scratch"
    return 0
  fi

  if [[ -n "$state_scratch" ]]; then
    production_validation_drop_database "$state_scratch"
  fi
  production_validation_create_scratch "$task"
}

production_validation_resolve_migration() {
  local requested="$1"
  local directory
  local absolute

  [[ -f "$requested" ]] || die "Migration file not found: $requested"
  directory="$(cd "$(dirname "$requested")" && pwd -P)"
  absolute="$directory/$(basename "$requested")"
  case "$absolute" in
    "$DB_ROOT"/supabase/migrations/*.sql) ;;
    *) die "Migration must live under supabase/migrations/: $requested" ;;
  esac
  printf '%s\n' "$absolute"
}

production_validation_migration_version() {
  local migration_file="$1"
  local filename
  filename="$(basename "$migration_file")"
  if [[ "$filename" =~ ^([0-9]{8,})_.*\.sql$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    die "Migration filename must begin with a numeric version: $filename"
  fi
}

production_validation_production_versions_file() {
  local task="$1"
  local key
  local observation
  key="$(production_validation_task_state_value "$task" cache_key)"
  observation="$(production_validation_task_state_value "$task" observation_id)"
  printf '%s/baselines/%s/observations/%s/production-migrations.txt\n' \
    "$PRODUCTION_VALIDATION_ROOT" \
    "$key" \
    "$observation"
}

production_validation_rebuild_task_scratch() {
  local task="$1"
  local scratch_db

  scratch_db="$(production_validation_task_state_value "$task" scratch_database)"
  production_validation_drop_database "$scratch_db"
  production_validation_create_scratch "$task"
}

production_validation_apply_one_migration() {
  local task="$1"
  local migration_file="$2"
  local version="$3"
  local file_sha="$4"
  local scratch_url
  local log_file
  local use_single_transaction=true

  scratch_url="$(production_validation_local_url_for "$PRODUCTION_VALIDATION_SCRATCH_DB")"
  log_file="$PRODUCTION_VALIDATION_LOGS/${task}-migration-${version}-$(date -u +%Y%m%dT%H%M%SZ).log"

  if ! grep -Eiq '^[[:space:]]*(begin|start[[:space:]]+transaction)[[:space:]]*;' \
    "$migration_file"; then
    use_single_transaction=true
  else
    use_single_transaction=false
  fi

  if [[ "$use_single_transaction" == true ]]; then
    PGOPTIONS="-c statement_timeout=120000 -c lock_timeout=10000" \
      psql "$scratch_url" \
        -X \
        -v ON_ERROR_STOP=1 \
        --single-transaction \
        -f "$migration_file" \
        >"$log_file" 2>&1 ||
      {
        tail -100 "$log_file" >&2
        die "Migration $version failed on the task scratch database; full log: $log_file"
      }
  elif ! PGOPTIONS="-c statement_timeout=120000 -c lock_timeout=10000" \
    psql "$scratch_url" \
      -X \
      -v ON_ERROR_STOP=1 \
      -f "$migration_file" \
      >"$log_file" 2>&1; then
    tail -100 "$log_file" >&2
    die "Migration $version failed on the task scratch database; full log: $log_file"
  fi

  printf '%s\t%s\t%s\n' "$version" "$file_sha" "$migration_file" \
    >>"$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv"
}

production_validation_recorded_migrations_are_current() {
  local applied_file="$1"
  local version
  local recorded_sha
  local migration_file
  local previous_version=""

  [[ -f "$applied_file" ]] || return 0
  while IFS=$'\t' read -r version recorded_sha migration_file; do
    [[ -n "$version" ]] || continue
    [[ "$version" =~ ^[0-9]{14}$ ]] || return 1
    [[ "$recorded_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    [[ "$migration_file" == "$DB_ROOT"/supabase/migrations/*.sql ]] ||
      return 1
    [[ -f "$migration_file" ]] || return 1
    [[ "$(sha256_file "$migration_file")" == "$recorded_sha" ]] ||
      return 1
    [[ -z "$previous_version" || "$version" > "$previous_version" ]] ||
      return 1
    previous_version="$version"
  done <"$applied_file"
  return 0
}

production_validation_apply_migrations() {
  local task="$1"
  shift
  local applied_file="$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv"
  local versions_file
  local desired_file
  local sorted_file
  local migration_file
  local absolute
  local version
  local file_sha
  local existing_line
  local existing_sha
  local existing_path
  local rebuild=false
  local maximum_applied=""

  versions_file="$(production_validation_production_versions_file "$task")"
  [[ -f "$versions_file" ]] ||
    die "Task production migration evidence is missing; run prepare"
  [[ -f "$applied_file" ]] || : >"$applied_file"

  desired_file="$(mktemp "$PRODUCTION_VALIDATION_ROOT/desired.XXXXXX")"
  sorted_file="$(mktemp "$PRODUCTION_VALIDATION_ROOT/sorted.XXXXXX")"
  if ! production_validation_recorded_migrations_are_current "$applied_file"; then
    rebuild=true
  fi

  while IFS=$'\t' read -r version existing_sha existing_path; do
    [[ -n "$version" ]] || continue
    [[ "$version" =~ ^[0-9]{14}$ &&
      "$existing_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die "Recorded migration manifest is malformed; clean up the task scratch"
    [[ -f "$existing_path" ]] ||
      die "Previously applied migration file is missing: $existing_path"
    printf '%s\t%s\n' "$version" "$existing_path" >>"$desired_file"
    maximum_applied="$version"
  done <"$applied_file"

  for migration_file in "$@"; do
    absolute="$(production_validation_resolve_migration "$migration_file")"
    version="$(production_validation_migration_version "$absolute")"
    if grep -Fxq "$version" "$versions_file"; then
      die "Migration $version is already present in production; do not reapply it to this baseline"
    fi
    printf '%s\t%s\n' "$version" "$absolute" >>"$desired_file"
    if [[ -n "$maximum_applied" ]] &&
      [[ "$version" < "$maximum_applied" ]]; then
      rebuild=true
    fi
  done

  sort -t $'\t' -k1,1n -k2,2 "$desired_file" |
    awk -F $'\t' '
      previous_version == $1 {
        if (previous_path != $2) {
          print "duplicate migration version " $1 > "/dev/stderr"
          exit 1
        }
        next
      }
      {
        print
        previous_version = $1
        previous_path = $2
      }
    ' >"$sorted_file" ||
    die "Migration selection contains conflicting version files"

  while IFS=$'\t' read -r version migration_file; do
    [[ -n "$version" ]] || continue
    file_sha="$(sha256_file "$migration_file")"
    existing_line="$(awk -F $'\t' -v version="$version" '$1 == version { print; exit }' "$applied_file")"
    if [[ -n "$existing_line" ]]; then
      existing_sha="$(printf '%s\n' "$existing_line" | awk -F $'\t' '{print $2}')"
      existing_path="$(printf '%s\n' "$existing_line" | awk -F $'\t' '{print $3}')"
      if [[ "$existing_sha" != "$file_sha" ||
        "$existing_path" != "$migration_file" ]]; then
        rebuild=true
      fi
    fi
  done <"$sorted_file"

  if [[ "$rebuild" == true ]]; then
    echo "Migration input changed; rebuilding only the local task scratch from its immutable cached template."
    production_validation_rebuild_task_scratch "$task"
    applied_file="$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv"
  fi

  while IFS=$'\t' read -r version migration_file; do
    [[ -n "$version" ]] || continue
    file_sha="$(sha256_file "$migration_file")"
    existing_line="$(awk -F $'\t' -v version="$version" '$1 == version { print; exit }' "$applied_file")"
    [[ -z "$existing_line" ]] || continue
    production_validation_apply_one_migration \
      "$task" \
      "$migration_file" \
      "$version" \
      "$file_sha"
  done <"$sorted_file"

  rm -f "$desired_file" "$sorted_file"
}

production_validation_select_tests() {
  local output_file="$1"
  shift
  local selectors=("$@")
  local selector
  local match
  local matched

  : >"$output_file"
  if ((${#selectors[@]} == 0)); then
    for match in "$DB_ROOT"/supabase/tests/*.sql; do
      [[ -e "$match" ]] && printf '%s\n' "$match" >>"$output_file"
    done
  else
    for selector in "${selectors[@]}"; do
      selector="${selector%.sql}"
      matched=false
      for match in "$DB_ROOT"/supabase/tests/*"$selector"*.sql; do
        [[ -e "$match" ]] || continue
        printf '%s\n' "$match" >>"$output_file"
        matched=true
      done
      [[ "$matched" == true ]] ||
        die "No pgTAP test matches '$selector'"
    done
  fi
  sort -u "$output_file" -o "$output_file"
  [[ -s "$output_file" ]] || die "No pgTAP test files were selected"
}

production_validation_run_tests() {
  local task="$1"
  shift
  local selectors=("$@")
  local selected_file
  local files=()
  local file
  local scratch_url
  local log_file

  selected_file="$(mktemp "$PRODUCTION_VALIDATION_ROOT/tests.XXXXXX")"
  if ((${#selectors[@]} > 0)); then
    production_validation_select_tests "$selected_file" "${selectors[@]}"
  else
    production_validation_select_tests "$selected_file"
  fi
  while IFS= read -r file; do
    files+=("$file")
  done <"$selected_file"
  rm -f "$selected_file"

  scratch_url="$(production_validation_local_url_for "$PRODUCTION_VALIDATION_SCRATCH_DB")"
  log_file="$PRODUCTION_VALIDATION_LOGS/${task}-pgtap-$(date -u +%Y%m%dT%H%M%SZ).log"
  printf 'Running %d pgTAP file(s) on scratch database %s.\n' \
    "${#files[@]}" \
    "$PRODUCTION_VALIDATION_SCRATCH_DB"

  if [[ "${VINABIKE_DB_VERBOSE:-}" == "1" ]]; then
    run_supabase_cli test db --db-url "$scratch_url" "${files[@]}" 2>&1 |
      tee "$log_file"
    return "${PIPESTATUS[0]}"
  fi
  if run_supabase_cli test db --db-url "$scratch_url" "${files[@]}" \
    >"$log_file" 2>&1; then
    rg '(^.*\.sql \.\. ok$|All tests successful|^Files=|^Result:)' \
      "$log_file" ||
      tail -20 "$log_file"
    echo "Full pgTAP output: $log_file"
  else
    local status=$?
    echo "pgTAP failed; last 120 log lines:" >&2
    tail -120 "$log_file" >&2
    return "$status"
  fi
}

production_validation_prepare_command() {
  local task="$1"
  local force_refresh="$2"
  shift 2
  local migrations=("$@")
  local work_dir
  local identity_file
  local versions_file
  local acl_roles_file
  local baseline_dir
  local global_lock="$PRODUCTION_VALIDATION_LOCKS/global"

  production_validation_validate_task "$task"
  production_validation_ensure_local_runtime
  production_validation_acquire_lock global

  work_dir="$(mktemp -d "$PRODUCTION_VALIDATION_ROOT/identity.XXXXXX")"
  PRODUCTION_VALIDATION_ACTIVE_IDENTITY_DIR="$work_dir"
  identity_file="$work_dir/catalog-identity.tsv"
  versions_file="$work_dir/production-migrations.txt"
  acl_roles_file="$work_dir/production-acl-roles.txt"
  production_validation_fetch_live_identity \
    "$identity_file" \
    "$versions_file" \
    "$acl_roles_file"
  production_validation_read_identity "$identity_file"
  baseline_dir="$PRODUCTION_VALIDATION_BASELINES/$PRODUCTION_VALIDATION_KEY"
  mkdir -p "$baseline_dir/observations" "$baseline_dir/captures"
  production_validation_record_observation \
    "$baseline_dir" \
    "$identity_file" \
    "$versions_file" \
    "$acl_roles_file"

  if [[ "$force_refresh" == true ||
    ! -s "$baseline_dir/current-capture" ]]; then
    echo "Capturing the production public schema only; no production rows are requested."
    production_validation_create_capture "$baseline_dir"
  else
    production_validation_clear_remote_connection
    production_validation_load_capture "$baseline_dir"
    echo "Live catalog identity is unchanged; reusing immutable capture $PRODUCTION_VALIDATION_CAPTURE_ID."
  fi
  rm -rf "$work_dir"
  PRODUCTION_VALIDATION_ACTIVE_IDENTITY_DIR=""

  production_validation_atomic_pointer \
    "$PRODUCTION_VALIDATION_ROOT/latest-key" \
    "$PRODUCTION_VALIDATION_KEY"
  production_validation_acquire_lock \
    "$(production_validation_task_lock_name "$task")"
  production_validation_ensure_task_scratch "$task"
  production_validation_release_lock "$global_lock"

  if ((${#migrations[@]} > 0)); then
    production_validation_apply_migrations "$task" "${migrations[@]}"
  else
    production_validation_apply_migrations "$task"
  fi
  echo "Production-derived validation scratch ready."
  echo "  Task: $task"
  echo "  Cache key: $PRODUCTION_VALIDATION_KEY"
  echo "  Migration head: $PRODUCTION_VALIDATION_MIGRATION_HEAD"
  echo "  Catalog fingerprint: $PRODUCTION_VALIDATION_CATALOG_FINGERPRINT"
  echo "  Capture: $PRODUCTION_VALIDATION_CAPTURE_ID"
  echo "  Scratch database: $PRODUCTION_VALIDATION_SCRATCH_DB"
}

production_validation_reuse_command() {
  local task="$1"
  shift
  local migrations=("$@")
  local latest_file="$PRODUCTION_VALIDATION_ROOT/latest-key"
  local baseline_dir
  local observation_metadata
  local global_lock="$PRODUCTION_VALIDATION_LOCKS/global"

  production_validation_validate_task "$task"
  production_validation_ensure_local_runtime
  production_validation_acquire_lock global
  [[ -s "$latest_file" ]] ||
    die "No cached production-derived baseline exists; run prepare"
  PRODUCTION_VALIDATION_KEY="$(<"$latest_file")"
  [[ "$PRODUCTION_VALIDATION_KEY" =~ ^[0-9a-f]{64}$ ]] ||
    die "Cached production-validation key is invalid"
  baseline_dir="$PRODUCTION_VALIDATION_BASELINES/$PRODUCTION_VALIDATION_KEY"
  production_validation_load_observation "$baseline_dir"
  observation_metadata="$baseline_dir/observations/$PRODUCTION_VALIDATION_OBSERVATION_ID/metadata"
  PRODUCTION_VALIDATION_SERVER_VERSION_NUM="$(
    production_validation_metadata_value "$observation_metadata" server_version_num
  )"
  PRODUCTION_VALIDATION_SERVER_VERSION="$(
    production_validation_metadata_value "$observation_metadata" server_version
  )"
  PRODUCTION_VALIDATION_MIGRATION_HEAD="$(
    production_validation_metadata_value "$observation_metadata" migration_head
  )"
  PRODUCTION_VALIDATION_MIGRATION_HISTORY_FINGERPRINT="$(
    production_validation_metadata_value \
      "$observation_metadata" \
      migration_history_fingerprint
  )"
  PRODUCTION_VALIDATION_CATALOG_FINGERPRINT="$(
    production_validation_metadata_value "$observation_metadata" catalog_fingerprint
  )"
  production_validation_load_capture "$baseline_dir"
  production_validation_acquire_lock \
    "$(production_validation_task_lock_name "$task")"
  production_validation_ensure_task_scratch "$task"
  production_validation_release_lock "$global_lock"
  if ((${#migrations[@]} > 0)); then
    production_validation_apply_migrations "$task" "${migrations[@]}"
  else
    production_validation_apply_migrations "$task"
  fi

  echo "Reused cached production-derived validation scratch without a production call."
  echo "  Task: $task"
  echo "  Cache key: $PRODUCTION_VALIDATION_KEY"
  echo "  Capture: $PRODUCTION_VALIDATION_CAPTURE_ID"
  echo "  Scratch database: $PRODUCTION_VALIDATION_SCRATCH_DB"
}

production_validation_load_task_for_test() {
  local task="$1"
  local state_file="$PRODUCTION_VALIDATION_TASKS/$task/state"

  production_validation_validate_task "$task"
  [[ -f "$state_file" ]] ||
    die "Task '$task' has no prepared scratch; run prepare or reuse"
  PRODUCTION_VALIDATION_KEY="$(production_validation_task_state_value "$task" cache_key)"
  PRODUCTION_VALIDATION_CAPTURE_ID="$(production_validation_task_state_value "$task" capture_id)"
  PRODUCTION_VALIDATION_OBSERVATION_ID="$(production_validation_task_state_value "$task" observation_id)"
  PRODUCTION_VALIDATION_TEMPLATE_DB="$(production_validation_task_state_value "$task" template_database)"
  PRODUCTION_VALIDATION_SCRATCH_DB="$(production_validation_task_state_value "$task" scratch_database)"
  production_validation_validate_database_name "$PRODUCTION_VALIDATION_TEMPLATE_DB"
  production_validation_validate_database_name "$PRODUCTION_VALIDATION_SCRATCH_DB"
  production_validation_database_exists "$PRODUCTION_VALIDATION_SCRATCH_DB" ||
    die "Task scratch database is missing; run reuse"
}

production_validation_test_command() {
  local task="$1"
  shift
  local migration_count="$1"
  shift
  local migrations=()
  local selectors=()
  local index

  for ((index = 0; index < migration_count; index++)); do
    migrations+=("$1")
    shift
  done
  selectors=("$@")

  production_validation_ensure_local_runtime
  production_validation_acquire_lock \
    "$(production_validation_task_lock_name "$task")"
  production_validation_load_task_for_test "$task"
  if ((${#migrations[@]} > 0)); then
    production_validation_apply_migrations "$task" "${migrations[@]}"
  else
    production_validation_apply_migrations "$task"
  fi
  if ((${#selectors[@]} > 0)); then
    production_validation_run_tests "$task" "${selectors[@]}"
  else
    production_validation_run_tests "$task"
  fi
}

production_validation_status_task() {
  local task="$1"
  local state_file="$PRODUCTION_VALIDATION_TASKS/$task/state"
  local key
  local capture
  local observation
  local template_db
  local scratch_db
  local template_state="local-stack-stopped"
  local scratch_state="local-stack-stopped"
  local applied_count=0

  [[ -f "$state_file" ]] || {
    echo "Task '$task': not prepared"
    return 0
  }
  key="$(production_validation_task_state_value "$task" cache_key)"
  capture="$(production_validation_task_state_value "$task" capture_id)"
  observation="$(production_validation_task_state_value "$task" observation_id)"
  template_db="$(production_validation_task_state_value "$task" template_database)"
  scratch_db="$(production_validation_task_state_value "$task" scratch_database)"
  if production_validation_try_local_runtime; then
    if production_validation_database_exists "$template_db"; then
      template_state="$(production_validation_database_template_state "$template_db")"
    else
      template_state="missing"
    fi
    if production_validation_database_exists "$scratch_db"; then
      scratch_state="ready"
    else
      scratch_state="missing"
    fi
  fi
  if [[ -f "$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv" ]]; then
    applied_count="$(
      awk 'NF { count++ } END { print count + 0 }' \
        "$PRODUCTION_VALIDATION_TASKS/$task/applied-migrations.tsv"
    )"
  fi

  echo "Task: $task"
  echo "  Cache key: $key"
  echo "  Capture: $capture"
  echo "  Observation: $observation"
  echo "  Template database: $template_db ($template_state)"
  echo "  Scratch database: $scratch_db ($scratch_state)"
  echo "  Applied pending migrations: $applied_count"
}

production_validation_status_command() {
  local task="$1"
  local task_dir
  local count

  if [[ -n "$task" ]]; then
    production_validation_validate_task "$task"
    production_validation_status_task "$task"
    return 0
  fi

  count="$(find "$PRODUCTION_VALIDATION_BASELINES" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]')"
  echo "Cached exact production catalog identities: $count"
  if [[ -s "$PRODUCTION_VALIDATION_ROOT/latest-key" ]]; then
    echo "Latest cache key: $(<"$PRODUCTION_VALIDATION_ROOT/latest-key")"
  else
    echo "Latest cache key: none"
  fi
  for task_dir in "$PRODUCTION_VALIDATION_TASKS"/*; do
    [[ -d "$task_dir" ]] || continue
    production_validation_status_task "$(basename "$task_dir")"
  done
}

production_validation_cleanup_task() {
  local task="$1"
  local task_dir="$PRODUCTION_VALIDATION_TASKS/$task"
  local scratch_db=""

  production_validation_validate_task "$task"
  if [[ -f "$task_dir/state" ]]; then
    scratch_db="$(production_validation_task_state_value "$task" scratch_database)"
  fi
  [[ -z "$scratch_db" ]] ||
    production_validation_drop_database "$scratch_db"
  rm -rf "$task_dir"
  echo "Removed local validation scratch for task '$task'."
}

production_validation_cleanup_acl_roles() {
  PGOPTIONS='' psql "$PRODUCTION_VALIDATION_LOCAL_DB_URL" \
    -Xq \
    -v ON_ERROR_STOP=1 \
    -v "role_comment=$PRODUCTION_VALIDATION_ACL_ROLE_COMMENT" <<'SQL'
select format('drop role %I', role_row.rolname)
from pg_roles role_row
where shobj_description(role_row.oid, 'pg_authid') = :'role_comment'
order by role_row.rolname
\gexec
SQL
}

production_validation_cleanup_templates() {
  local baseline_dir
  local capture_dir
  local metadata
  local template_db

  for baseline_dir in "$PRODUCTION_VALIDATION_BASELINES"/*; do
    [[ -d "$baseline_dir" ]] || continue
    for capture_dir in "$baseline_dir"/captures/*; do
      [[ -d "$capture_dir" ]] || continue
      metadata="$capture_dir/metadata"
      [[ -f "$metadata" ]] || continue
      template_db="$(
        production_validation_metadata_value "$metadata" template_database
      )"
      [[ -z "$template_db" ]] ||
        production_validation_drop_database "$template_db"
    done
  done
  production_validation_cleanup_acl_roles
  rm -rf "$PRODUCTION_VALIDATION_BASELINES"
  mkdir -p "$PRODUCTION_VALIDATION_BASELINES"
  rm -f "$PRODUCTION_VALIDATION_ROOT/latest-key"
  echo "Removed immutable local templates and cached schema-only captures."
}

production_validation_cleanup_command() {
  local task="$1"
  local all="$2"
  local include_templates="$3"
  local task_dir

  production_validation_ensure_local_runtime
  production_validation_acquire_lock global
  if [[ -n "$task" ]]; then
    production_validation_acquire_lock \
      "$(production_validation_task_lock_name "$task")"
    production_validation_cleanup_task "$task"
    return 0
  fi
  [[ "$all" == true ]] ||
    die "cleanup requires --task TASK or --all"

  for task_dir in "$PRODUCTION_VALIDATION_TASKS"/*; do
    [[ -d "$task_dir" ]] || continue
    task="$(basename "$task_dir")"
    production_validation_acquire_lock \
      "$(production_validation_task_lock_name "$task")"
    production_validation_cleanup_task "$task"
  done
  if [[ "$include_templates" == true ]]; then
    production_validation_cleanup_templates
  else
    echo "Immutable templates retained; add --include-templates with --all to remove them."
  fi
}

production_validation_main() {
  local command_name="${1:-}"
  local task=""
  local all=false
  local include_templates=false
  local migrations=()
  local tests=()

  [[ -n "$command_name" ]] || {
    production_validation_usage
    exit 64
  }
  if [[ "$command_name" == "--help" || "$command_name" == "-h" ]]; then
    production_validation_usage
    exit 0
  fi
  shift

  while (($# > 0)); do
    case "$1" in
      --task)
        [[ $# -ge 2 ]] || die "--task requires a value"
        task="$2"
        shift 2
        ;;
      --migration)
        [[ $# -ge 2 ]] || die "--migration requires a file"
        migrations+=("$2")
        shift 2
        ;;
      --test)
        [[ $# -ge 2 ]] || die "--test requires a selector"
        tests+=("$2")
        shift 2
        ;;
      --all)
        all=true
        shift
        ;;
      --include-templates)
        include_templates=true
        shift
        ;;
      --help|-h)
        production_validation_usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  case "$command_name" in
    prepare)
      [[ -n "$task" ]] || die "prepare requires --task TASK"
      [[ "$all" == false && "$include_templates" == false ]] ||
        die "prepare does not accept cleanup options"
      ((${#tests[@]} == 0)) || die "prepare does not accept --test"
      if ((${#migrations[@]} > 0)); then
        production_validation_prepare_command \
          "$task" \
          false \
          "${migrations[@]}"
      else
        production_validation_prepare_command "$task" false
      fi
      ;;
    reuse)
      [[ -n "$task" ]] || die "reuse requires --task TASK"
      [[ "$all" == false && "$include_templates" == false ]] ||
        die "reuse does not accept cleanup options"
      ((${#tests[@]} == 0)) || die "reuse does not accept --test"
      if ((${#migrations[@]} > 0)); then
        production_validation_reuse_command "$task" "${migrations[@]}"
      else
        production_validation_reuse_command "$task"
      fi
      ;;
    refresh)
      [[ -n "$task" ]] || die "refresh requires --task TASK"
      [[ "$all" == false && "$include_templates" == false ]] ||
        die "refresh does not accept cleanup options"
      ((${#tests[@]} == 0)) || die "refresh does not accept --test"
      if ((${#migrations[@]} > 0)); then
        production_validation_prepare_command \
          "$task" \
          true \
          "${migrations[@]}"
      else
        production_validation_prepare_command "$task" true
      fi
      ;;
    test)
      [[ -n "$task" ]] || die "test requires --task TASK"
      [[ "$all" == false && "$include_templates" == false ]] ||
        die "test does not accept cleanup options"
      if ((${#migrations[@]} > 0 && ${#tests[@]} > 0)); then
        production_validation_test_command \
          "$task" \
          "${#migrations[@]}" \
          "${migrations[@]}" \
          "${tests[@]}"
      elif ((${#migrations[@]} > 0)); then
        production_validation_test_command \
          "$task" \
          "${#migrations[@]}" \
          "${migrations[@]}"
      elif ((${#tests[@]} > 0)); then
        production_validation_test_command \
          "$task" \
          0 \
          "${tests[@]}"
      else
        production_validation_test_command "$task" 0
      fi
      ;;
    status)
      ((${#migrations[@]} == 0 && ${#tests[@]} == 0)) ||
        die "status does not accept migration or test selectors"
      [[ "$all" == false && "$include_templates" == false ]] ||
        die "status does not accept cleanup options"
      production_validation_status_command "$task"
      ;;
    cleanup)
      ((${#migrations[@]} == 0 && ${#tests[@]} == 0)) ||
        die "cleanup does not accept migration or test selectors"
      [[ -z "$task" || "$all" == false ]] ||
        die "cleanup accepts either --task or --all, not both"
      [[ "$include_templates" == false || "$all" == true ]] ||
        die "--include-templates requires --all"
      production_validation_cleanup_command \
        "$task" \
        "$all" \
        "$include_templates"
      ;;
    *)
      production_validation_usage
      die "Unknown command: $command_name"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap production_validation_cleanup_on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  production_validation_main "$@"
fi
