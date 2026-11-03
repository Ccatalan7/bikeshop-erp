#!/usr/bin/env bash
# pgTAP against the shape of production, without its data.
#
# Usage: test_production_shape.sh [--apply <migration.sql>]... <test.sql>...
#
# The local database is not production: on 2026-11-02 it lacked 530 functions,
# 863 columns and 113 triggers that production has (`just db-drift`), so a
# pgTAP of the order, payment, purchase or inventory kernel run there proves
# the local bodies, not the live ones. This dumps production's structure only
# (`--schema-only`: no rows ever leave production), restores it into a
# disposable database of the local Supabase container, applies the candidate
# migrations in order, runs each test file there and drops the database.
# Nothing is written to production and the dump never touches the disk.
#
# The disposable database has no pg_net or vault: their functions are stubs
# that answer like an empty queue, so a trigger that posts a push or reads a
# secret runs instead of failing for a reason production does not have.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

applies=()
tests=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --apply)
      [[ -f "${2:-}" ]] || die "--apply needs an existing migration file"
      applies+=("$2")
      shift 2
      ;;
    -h | --help)
      sed -n 2,16p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      [[ -f "$1" ]] || die "No such test file: $1"
      tests+=("$1")
      shift
      ;;
  esac
done
[[ "${#tests[@]}" -gt 0 ]] || die "Usage: test_production_shape.sh [--apply <migration.sql>]... <test.sql>..."
require_command docker
require_command psql

container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 '^supabase_db_' || true)"
[[ -n "$container" ]] || die "The local Supabase database is not running (scripts/db/ensure_local.sh)"

readonly SHAPE_PROJECT_REF="xzdvtzdqjeyqxnkqprtf"
configure_remote_pg production
[[ "$PGUSER" == "postgres.$SHAPE_PROJECT_REF" ]] || die "The linked project is not the approved production project"
export PGCONNECT_TIMEOUT=20 PGAPPNAME=vinabike_shape_test

scratch="forma_prod_$(date +%s)"
mkdir -p "$DB_ROOT/.tmp/db"
log="$DB_ROOT/.tmp/db/production-shape-$(date +%Y%m%d-%H%M%S).log"
cleanup() {
  docker exec "$container" dropdb -U postgres --if-exists --force "$scratch" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_scratch() { docker exec -i "$container" psql -U postgres -d "$scratch" -X "$@"; }

docker exec "$container" createdb -U postgres "$scratch"
in_scratch -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
create schema if not exists extensions;
create extension if not exists vector schema public;
create extension if not exists pg_trgm schema public;
create extension if not exists unaccent schema public;
create extension if not exists fuzzystrmatch schema public;
create extension if not exists pgcrypto schema extensions;
create extension if not exists "uuid-ossp" schema extensions;
create extension if not exists pgtap schema extensions;
create schema if not exists net;
create table if not exists net.http_request_queue (id bigserial primary key, url text, body jsonb, headers jsonb);
create or replace function net.http_post(
  url text, body jsonb default '{}'::jsonb, params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb, timeout_milliseconds integer default 5000
) returns bigint language sql as $$
  insert into net.http_request_queue (url, body, headers) values (url, body, headers) returning id
$$;
create schema if not exists vault;
create table if not exists vault.decrypted_secrets (id uuid default gen_random_uuid(), name text, decrypted_secret text);
grant usage on schema net, vault to public;
grant all on all tables in schema net, vault to public;
grant all on all sequences in schema net to public;
SQL

echo "Dumping production structure (no rows)…"
docker exec -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE \
  -e PGCONNECT_TIMEOUT -e PGAPPNAME "$container" \
  pg_dump --schema-only --format=custom --no-owner \
    --schema=public --schema=private --schema=assistant_runtime --schema=auth --schema=storage |
  docker exec -i "$container" pg_restore -U postgres -d "$scratch" --no-owner \
    >"$log" 2>&1 || true
restore_errors="$(grep -c '^pg_restore: error' "$log" || true)"
echo "Restored production structure into $scratch (pg_restore errors: $restore_errors, see $log)"

# The rows of the global lookups that the structure points at (no tenant, no
# person): without them a foreign key fails for a reason production does not
# have — `purchase_invoices.source_document_kind` → `tax_invoice` did, the
# first day. Add a table here only if it is a fixed catalog.
readonly REFERENCE_TABLES=(public.purchase_source_document_kinds)
for table in "${REFERENCE_TABLES[@]}"; do
  docker exec -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE \
    -e PGCONNECT_TIMEOUT -e PGAPPNAME "$container" \
    pg_dump --data-only --format=custom --no-owner --table="$table" |
    docker exec -i "$container" pg_restore -U postgres -d "$scratch" --no-owner --disable-triggers \
      >>"$log" 2>&1 || true
done

# The grants come with the dump (the same roles exist in the local stack), so
# a test of who may call what answers as production does.
in_scratch -q -v ON_ERROR_STOP=1 >/dev/null <<SQL
alter database "$scratch" set search_path = public, extensions;
grant usage on schema extensions to anon, authenticated, service_role;
SQL

# macOS bash 3.2 treats an empty array as unbound under set -u.
for migration in ${applies[@]+"${applies[@]}"}; do
  echo "Applying ${migration#"$DB_ROOT/"}"
  in_scratch -q -v ON_ERROR_STOP=1 -f - <"$migration" >>"$log" 2>&1 ||
    { tail -20 "$log" >&2; die "Migration failed in the production-shaped database: $migration"; }
done

failed=0
for test_file in "${tests[@]}"; do
  output="$(in_scratch -q -At -v ON_ERROR_STOP=0 -f - <"$test_file" 2>&1 || true)"
  printf '%s\n' "$output" >>"$log"
  planned="$(printf '%s\n' "$output" | sed -nE 's/^1\.\.([0-9]+)$/\1/p' | head -1)"
  passed="$(printf '%s\n' "$output" | grep -cE '^ok [0-9]+' || true)"
  not_ok="$(printf '%s\n' "$output" | grep -cE '^not ok [0-9]+' || true)"
  errors="$(printf '%s\n' "$output" | grep -cE '^(psql:.*)?ERROR:' || true)"
  if [[ -n "$planned" && "$passed" == "$planned" && "$not_ok" == 0 && "$errors" == 0 ]]; then
    echo "${test_file#"$DB_ROOT/"} .. ok ($passed/$planned)"
  else
    failed=1
    echo "${test_file#"$DB_ROOT/"} .. FAILED (ok $passed, not ok $not_ok, errors $errors, plan ${planned:-?})"
    printf '%s\n' "$output" | grep -E '^(not ok|#|psql:|ERROR:|DETAIL:|CONTEXT:)' | head -40
  fi
done
echo "Full output: ${log#"$DB_ROOT/"}"
exit "$failed"
