#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SENSITIVE_TABLES_FILE="$DB_ROOT/scripts/db/sensitive_tables.txt"
DEFAULT_HOSTED_MAX_ROWS=200

contains_transaction_control() {
  tr '\r\n\t' '   ' |
    grep -Eiq \
      '(^|;)[[:space:]]*(begin([[:space:]]+(work|transaction))?|commit([[:space:]]+(work|transaction))?|rollback([[:space:]]+(work|transaction))?|end([[:space:]]+(work|transaction))?|set[[:space:]]+transaction)([[:space:];]|$)'
}

# True when the statement projects every column (select *, select alias.*).
# count(*) and other star arguments inside a function call do not match.
projects_every_column() {
  tr '\r\n\t' '   ' |
    grep -Eiq '(^|[(,[:space:]])select[[:space:]]+(distinct[[:space:]]+)?([a-z_][a-z_0-9]*\.)?\*'
}

# Names of listed sensitive tables that the statement reads FROM or JOINs.
# A table named only inside a predicate or string literal does not match.
sensitive_tables_read() {
  local statement="$1" table hits=""
  [[ -f "$SENSITIVE_TABLES_FILE" ]] || return 0
  local flattened
  flattened="$(printf '%s' "$statement" | tr '\r\n\t' '   ')"
  while read -r table; do
    table="${table%%#*}"
    table="$(printf '%s' "$table" | tr -d '[:space:]')"
    [[ -n "$table" ]] || continue
    if printf '%s' "$flattened" |
      grep -Eiq "(from|join)[[:space:]]+(public\.)?\"?${table}\"?([[:space:]]|;|\(|\)|$)"; then
      hits="${hits:+$hits, }$table"
    fi
  done <"$SENSITIVE_TABLES_FILE"
  printf '%s' "$hits"
}

# A single SELECT/WITH statement can be safely wrapped in a row cap.
is_cappable_statement() {
  local statement="$1"
  [[ "$statement" != *";"* ]] || return 1
  printf '%s' "$statement" | tr '\r\n\t' '   ' | grep -Eiq '^[[:space:]]*(select|with)[[:space:]]'
}

usage() {
  cat >&2 <<'USAGE'
Usage: query.sh <local|staging|production> (--sql SQL | --file PATH)
                [--format table|csv|json] [--max-rows N] [--allow-pii] [--write]

The canonical SQL path for every agent and every environment. The Supabase CLI
and the hosted SQL Editor are not SQL paths: they bypass the guards below.
For hosted schema changes, do not call --write directly: use
scripts/db/deploy_migration.sh so read-back and the remote migration stamp
cannot be skipped. core_schema.sql is never a hosted input.

  --format    table (default), csv, or json.
  --max-rows  Hosted read cap for a single SELECT/WITH statement.
              Default 200; 0 disables the cap. Ignored on local and on --file.
  --allow-pii Permit a star projection over a table listed in
              scripts/db/sensitive_tables.txt. Recorded in the journal.
  --write     Mutating hosted statement. Requires VINABIKE_DB_WRITE_CONFIRM
              and, per policy, the owner's authorization in the task.

Hosted reads run in BEGIN READ ONLY with a 30s statement timeout and are rolled
back. Production and staging connections are rejected unless the connected
project identity matches the approved ref. Staging is policy-dormant and also
requires VINABIKE_STAGING_REACTIVATION_CONFIRM.

Every invocation appends one audit line to .tmp/db/journal.jsonl: identity and
outcome only, never SQL text, values, or credentials.

Policy: docs/runbooks/STAGING_SUPABASE.md
Commands: docs/development/SUPABASE_WORKFLOW.md
Agent contract: docs/development/AGENT_DATABASE_CONTRACT.md
USAGE
  exit 64
}

environment="${1:-}"
[[ -n "$environment" ]] || usage
case "$environment" in
  -h | --help | help) usage ;;
esac
shift

sql=""
file=""
format=table
write=false
allow_pii=false
max_rows=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --sql)
      sql="${2:-}"
      shift 2
      ;;
    --file)
      file="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    --max-rows)
      max_rows="${2:-}"
      shift 2
      ;;
    --allow-pii)
      allow_pii=true
      shift
      ;;
    --write)
      write=true
      shift
      ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done
[[ -n "$sql" || -n "$file" ]] || usage
[[ -z "$sql" || -z "$file" ]] || die "Use either --sql or --file, not both"
[[ "$format" =~ ^(table|csv|json)$ ]] || die "Format must be table, csv or json"
[[ -z "$max_rows" || "$max_rows" =~ ^[0-9]+$ ]] || die "--max-rows must be a non-negative integer"

hosted=false
[[ "$environment" == production || "$environment" == staging ]] && hosted=true
if [[ "$hosted" == true && "$write" == false ]]; then
  max_rows="${max_rows:-$DEFAULT_HOSTED_MAX_ROWS}"
else
  max_rows="${max_rows:-0}"
fi

# From this point onward every guarded exit is journaled, including policy and
# identity rejections. Argument/usage errors above are not database attempts.
journal_mode="read"
[[ "$write" == true ]] && journal_mode="write"
journal_started=$SECONDS
journal_source="${file:---sql}"
journal_sha=""
if [[ -n "$sql" ]]; then
  journal_sha="$(sha256_text "${sql%;}")"
elif [[ -n "$file" && -f "$file" ]]; then
  journal_sha="$(sha256_file "$file")"
fi

finish() {
  local status="$1" sha="$2" source="$3"
  journal_append "$environment" "$journal_mode" "$sha" "$source" "$format" \
    "$max_rows" "$allow_pii" "$((SECONDS - journal_started))" "$status"
  exit "$status"
}

# Override the shared helper only inside this command so repository policy
# rejections use the same audited exit path as psql failures.
die() {
  echo "ERROR: $*" >&2
  finish 1 "$journal_sha" "$journal_source"
}

# core_schema.sql is an incomplete historical/local reference, never a hosted
# deployment or query input. Keep this executable boundary next to the hosted
# guard so stale documentation cannot accidentally turn it into a remote path.
if [[ "$hosted" == true && -n "$file" && "$(basename "$file")" == "core_schema.sql" ]]; then
  die "core_schema.sql is a historical local reference and can never be run against a hosted environment. Use one reviewed file from supabase/migrations/."
fi

# A hosted forward migration must enter through the apply -> verify -> stamp
# coordinator. Direct query.sh execution can commit schema while silently
# leaving migration history unregistered, which is precisely the ambiguity the
# governed workflow eliminates. Data/application writes outside the migration
# directory retain their existing task-specific paths.
if [[ "$hosted" == true && "$write" == true && -n "$file" && -f "$file" ]]; then
  file_directory="$(cd "$(dirname "$file")" && pwd -P)"
  file_absolute="$file_directory/$(basename "$file")"
  migration_directory="$(cd "$DB_ROOT/supabase/migrations" && pwd -P)"
  case "$file_absolute" in
    "$migration_directory"/*)
      migration_basename="$(basename "$file_absolute")"
      if [[ "$migration_basename" =~ ^([0-9]{14})_[a-z0-9_]+\.sql$ ]]; then
        migration_version="${BASH_REMATCH[1]}"
      else
        die "Hosted migration files require YYYYMMDDHHMMSS_slug.sql"
      fi
      expected_workflow="apply-verify-stamp:$migration_version"
      [[ "${VINABIKE_DB_DEPLOY_WORKFLOW:-}" == "$expected_workflow" ]] ||
        die "Direct hosted migration execution is forbidden. Use scripts/db/deploy_migration.sh so $migration_version is verified and stamped."
      ;;
  esac
fi

if [[ "$environment" == staging ]]; then
  expected_staging_ref="bczzjhjrpmtpgwdvlbut"
  [[ "${VINABIKE_STAGING_REACTIVATION_CONFIRM:-}" == "$expected_staging_ref" ]] ||
    die "Staging is policy-dormant. Owner reactivation requires VINABIKE_STAGING_REACTIVATION_CONFIRM=$expected_staging_ref"
fi

# Disclosure guard. Hosted reads only: local holds synthetic data, and a write
# is already gated by explicit confirmation and task-level authorization.
if [[ "$hosted" == true && "$write" == false && "$allow_pii" == false ]]; then
  guard_subject=""
  if [[ -n "$file" ]]; then
    [[ -f "$file" ]] || die "SQL file not found: $file"
    guard_subject="$(<"$file")"
  else
    guard_subject="$sql"
  fi
  if printf '%s' "$guard_subject" | projects_every_column; then
    sensitive_hits="$(sensitive_tables_read "$guard_subject")"
    if [[ -n "$sensitive_hits" ]]; then
      die "Star projection over sensitive table(s): $sensitive_hits.
Name the columns this task actually needs, or pass --allow-pii when the full
row is genuinely required. See scripts/db/sensitive_tables.txt."
    fi
  fi
fi

require_command psql
psql_args=(-X -v ON_ERROR_STOP=1 -P pager=off)
if [[ "$environment" == local ]]; then
  bash "$DB_ROOT/scripts/db/ensure_local.sh" >/dev/null
  connection=("$(local_db_url)")
elif [[ "$hosted" == true ]]; then
  configure_remote_pg "$environment"
  connection=("dbname=postgres")
  export PGOPTIONS="-c statement_timeout=30000 -c search_path=public,extensions"
  if [[ "$write" == false ]]; then
    export PGOPTIONS="$PGOPTIONS -c default_transaction_read_only=on"
  fi
else
  usage
fi

if [[ "$environment" == staging ]]; then
  staging_ref="${PGUSER#postgres.}"
  [[ "$staging_ref" == "$expected_staging_ref" ]] ||
    die "Staging connection identity does not match the approved dormant project"
fi

if [[ "$environment" == production ]]; then
  expected_production_ref="xzdvtzdqjeyqxnkqprtf"
  [[ -f "$DB_ROOT/supabase/.temp/project-ref" ]] ||
    die "Linked production project identity is unavailable"
  linked_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  connection_ref="${PGUSER#postgres.}"
  [[ "$linked_ref" == "$expected_production_ref" ]] ||
    die "Linked project is not the approved production project"
  [[ "$connection_ref" == "$expected_production_ref" ]] ||
    die "Production connection identity does not match the approved project"
fi
if [[ "$environment" == production && "$write" == true ]]; then
  [[ "${VINABIKE_DB_WRITE_CONFIRM:-}" == production ]] ||
    die "Production writes require VINABIKE_DB_WRITE_CONFIRM=production"
fi
if [[ "$environment" == staging && "$write" == true && "${VINABIKE_DB_WRITE_CONFIRM:-}" != staging ]]; then
  die "Staging writes require VINABIKE_DB_WRITE_CONFIRM=staging"
fi
if [[ "$environment" == staging && "$write" == true ]]; then
  production_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  [[ -n "$production_ref" && -n "$staging_ref" ]] ||
    die "Cannot prove staging and production project identities"
  [[ "$staging_ref" != "$production_ref" ]] ||
    die "Staging project ref matches production; refusing write"
fi

if [[ -n "$file" ]]; then
  [[ -f "$file" ]] || die "SQL file not found: $file"
  file_sha="$(sha256_file "$file")"
  status=0
  if [[ "$format" != table ]]; then
    sql="$(<"$file")"
  elif [[ "$hosted" == true && "$write" == false ]]; then
    if contains_transaction_control <"$file"; then
      die "Remote read-only SQL files cannot manage transactions"
    fi
    pipeline_status=()
    if {
      printf '%s\n' "begin read only;" "set local statement_timeout = '30s';"
      cat "$file"
      printf '%s\n' "rollback;"
    } | psql "${connection[@]}" "${psql_args[@]}" -q; then
      pipeline_status=("${PIPESTATUS[@]}")
    else
      pipeline_status=("${PIPESTATUS[@]}")
    fi
    status="${pipeline_status[1]}"
    if [[ "$status" -eq 0 && "${pipeline_status[0]}" -ne 0 ]]; then
      status="${pipeline_status[0]}"
    fi
    finish "$status" "$file_sha" "$file"
  else
    psql "${connection[@]}" "${psql_args[@]}" -f "$file" || status=$?
    finish "$status" "$file_sha" "$file"
  fi
fi

sql="${sql%;}"
source_label="${file:---sql}"
sql_sha="$(sha256_text "$sql")"

if [[ "$hosted" == true && "$write" == false && "$max_rows" != 0 ]]; then
  if is_cappable_statement "$sql"; then
    sql="select * from ( $sql ) as guarded_row_cap limit $max_rows"
    echo "NOTICE: hosted read capped at $max_rows rows (--max-rows N to raise, --max-rows 0 to disable)" >&2
  else
    max_rows=0
  fi
fi

original_sql="$sql"
if [[ "$hosted" == true && "$write" == false ]]; then
  if printf '%s\n' "$sql" | contains_transaction_control; then
    die "Remote read-only SQL cannot manage transactions"
  fi
  sql="begin read only; set local statement_timeout = '30s'; $sql; rollback"
  psql_args+=(-q)
fi

status=0
case "$format" in
  table) psql "${connection[@]}" "${psql_args[@]}" -c "$sql" || status=$? ;;
  csv) psql "${connection[@]}" "${psql_args[@]}" --csv -c "$sql" || status=$? ;;
  json)
    if [[ "$hosted" == true && "$write" == false ]]; then
      psql "${connection[@]}" "${psql_args[@]}" -tA -c "begin read only; set local statement_timeout = '30s'; select coalesce(jsonb_pretty(jsonb_agg(to_jsonb(result))), '[]') from ($original_sql) result; rollback" || status=$?
    else
      psql "${connection[@]}" "${psql_args[@]}" -tA -c "select coalesce(jsonb_pretty(jsonb_agg(to_jsonb(result))), '[]') from ($sql) result" || status=$?
    fi
    ;;
esac
finish "$status" "$sql_sha" "$source_label"
