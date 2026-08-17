#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$DB_ROOT"
require_command supabase
require_command psql
ensure_docker

mode="${1:-reuse}"
schema="$DB_ROOT/supabase/sql/core_schema.sql"
hash_file="$DB_CACHE_DIR/core-schema.sha256"
schema_inputs_manifest="$DB_CACHE_DIR/core-schema-inputs.sha256"
ensure_local_lock_dir="$DB_CACHE_DIR/ensure-local.lock"
ensure_local_lock_owner="$ensure_local_lock_dir/owner"
ensure_local_lock_held=false

ensure_local_release_lock() {
  if [[ "$ensure_local_lock_held" == true &&
    -f "$ensure_local_lock_owner" &&
    "$(<"$ensure_local_lock_owner")" == "$$" ]]; then
    rm -f "$ensure_local_lock_owner"
    rmdir "$ensure_local_lock_dir" 2>/dev/null || true
  fi
  ensure_local_lock_held=false
}

ensure_local_acquire_lock() {
  local deadline=$((SECONDS + 120))
  local owner_pid=""

  while ! mkdir "$ensure_local_lock_dir" 2>/dev/null; do
    if [[ -f "$ensure_local_lock_owner" ]]; then
      owner_pid="$(<"$ensure_local_lock_owner")"
      if [[ "$owner_pid" =~ ^[0-9]+$ ]] &&
        ! kill -0 "$owner_pid" 2>/dev/null; then
        rm -f "$ensure_local_lock_owner"
        rmdir "$ensure_local_lock_dir" 2>/dev/null || true
        continue
      fi
    fi
    ((SECONDS < deadline)) ||
      die "Timed out waiting for the local schema rebuild lock"
    sleep 0.2
  done

  printf '%s\n' "$$" >"$ensure_local_lock_owner"
  ensure_local_lock_held=true
}

mkdir -p "$DB_CACHE_DIR"
ensure_local_acquire_lock
trap ensure_local_release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

{
  printf '%s  %s\n' "$(sha256_file "$schema")" "${schema#"$DB_ROOT/"}"
  while IFS= read -r relative_path; do
    included_path="$(dirname "$schema")/$relative_path"
    [[ -f "$included_path" ]] || die "Canonical schema include is missing: $relative_path"
    printf '%s  %s\n' \
      "$(sha256_file "$included_path")" \
      "${included_path#"$DB_ROOT/"}"
  done < <(sed -n 's/^[[:space:]]*\\ir[[:space:]]\{1,\}\(.*\)$/\1/p' "$schema")
} >"$schema_inputs_manifest"

current_hash="$(sha256_file "$schema_inputs_manifest")"

run_supabase_cli status >/dev/null 2>&1 || run_supabase_cli db start >/dev/null
db_url="$(local_db_url)"

sentinels_ready() {
  [[ "$(psql "$db_url" -XAtqc "select count(*) from (values (to_regclass('public.sales_invoices')),(to_regclass('public.purchase_invoices')),(to_regclass('public.stock_movements')),(to_regclass('public.journal_entries'))) s(v) where v is not null" 2>/dev/null)" == "4" ]]
}

if [[ "$mode" != "--reset" ]] && sentinels_ready; then
  if [[ ! -f "$hash_file" && "$mode" == "--adopt-existing" ]]; then
    printf '%s\n' "$current_hash" >"$hash_file"
    echo "Local database adopted: historical-fixture sentinel objects are present."
    exit 0
  fi
  if [[ -f "$hash_file" && "$(<"$hash_file")" == "$current_hash" ]]; then
    echo "Local database ready: historical fixture hash unchanged."
    exit 0
  fi
fi

echo "Rebuilding disposable local public schema from the incomplete historical fixture..."
psql "$db_url" -X -v ON_ERROR_STOP=1 >"$DB_CACHE_DIR/schema-reset.log" 2>&1 <<'SQL'
drop schema if exists public cascade;
create schema public;
grant all on schema public to postgres;
grant all on schema public to public;
grant usage on schema public to anon, authenticated, service_role;

-- Match the standard Supabase public-schema defaults before applying the
-- historical fixture. Applying these up front lets later object-specific
-- REVOKE statements remain authoritative while keeping a fresh local rebuild
-- behaviorally equivalent to the hosted project for PostgREST clients.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

create extension if not exists pgcrypto with schema public;
create extension if not exists pg_trgm with schema public;
create extension if not exists unaccent with schema public;
create extension if not exists vector with schema public;
create extension if not exists pgtap with schema public;
SQL

if ! psql "$db_url" -X -v ON_ERROR_STOP=1 -f "$schema" >"$DB_CACHE_DIR/core-schema-apply.log" 2>&1; then
  tail -40 "$DB_CACHE_DIR/core-schema-apply.log" >&2
  die "Historical local fixture application failed; full log: $DB_CACHE_DIR/core-schema-apply.log"
fi

printf '%s\n' "$current_hash" >"$hash_file"
echo "Local database rebuilt successfully. Detailed SQL output: $DB_CACHE_DIR/core-schema-apply.log"
