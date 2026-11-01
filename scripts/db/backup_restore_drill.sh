#!/usr/bin/env bash
# Restore drill: proves that a backup opens and restores, away from production.
#
# Usage: backup_restore_drill.sh <base-...dump.cms> [production|local]
#
# Checks the archive's .sha256 when it is next to it, decrypts with the
# private key (the Keychain entry of backup_create_key.sh, or the PEM file in
# BACKUP_PRIVATE_KEY_FILE), restores into a disposable database of the local
# Supabase container, compares the rows of every restored public table with
# the database the backup came from (production by default), and drops the
# disposable database. It never writes to that source and never prints a row.
#
# Production keeps writing after the dump, so a few busy tables (notifications,
# webhook events) may show a small difference; a table missing or empty in the
# restore is the failure this drill exists to catch.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly BACKUP_KEY_SERVICE="Vinabike ERP respaldo de la base v1"

archive="${1:-}"
source_environment="${2:-production}"
# A folder means its newest backup.
if [[ -d "$archive" ]]; then
  archive="$(ls -1 "$archive"/base-*.dump.cms 2>/dev/null | sort | tail -1)"
fi
[[ -f "$archive" && "$source_environment" =~ ^(production|local)$ ]] ||
  die "Usage: backup_restore_drill.sh <base-...dump.cms or its folder> [production|local]"
require_command openssl
require_command docker

if [[ -f "$archive.sha256" ]]; then
  [[ "$(sha256_file "$archive")" == "$(awk '{print $1}' "$archive.sha256")" ]] ||
    die "The archive does not match its .sha256"
fi

container="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 '^supabase_db_' || true)"
[[ -n "$container" ]] || die "The local Supabase database is not running (scripts/db/ensure_local.sh)"

work="$(mktemp -d)"
chmod 700 "$work"
scratch="respaldo_prueba_$(date +%s)"
cleanup() {
  docker exec "$container" dropdb -U postgres --if-exists "$scratch" >/dev/null 2>&1 || true
  rm -f "$work/key.pem" "$work/restore.log" "$work/counts.sql" "$work/restored.csv" "$work/production.csv"
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT

if [[ -n "${BACKUP_PRIVATE_KEY_FILE:-}" ]]; then
  cp "$BACKUP_PRIVATE_KEY_FILE" "$work/key.pem"
else
  security find-generic-password -w -s "$BACKUP_KEY_SERVICE" -a "$USER" 2>/dev/null |
    base64 -D >"$work/key.pem" || die "No private key in the Keychain ('$BACKUP_KEY_SERVICE')"
fi
chmod 600 "$work/key.pem"

in_scratch() { docker exec -i "$container" psql -U postgres -d "$scratch" -XAtq -v ON_ERROR_STOP=1 "$@"; }

docker exec "$container" createdb -U postgres "$scratch"
# The extensions production has, in the schemas it has them; the dump brings
# only the schemas that hold the data.
in_scratch <<'SQL'
create schema if not exists extensions;
create extension if not exists vector schema public;
create extension if not exists pg_trgm schema public;
create extension if not exists unaccent schema public;
create extension if not exists fuzzystrmatch schema public;
create extension if not exists pgcrypto schema extensions;
create extension if not exists "uuid-ossp" schema extensions;
SQL

openssl cms -decrypt -binary -inform DER -in "$archive" -inkey "$work/key.pem" |
  docker exec -i "$container" pg_restore -U postgres -d "$scratch" --no-owner --no-privileges \
    >"$work/restore.log" 2>&1 || true
restore_errors="$(grep -c '^pg_restore: error' "$work/restore.log" || true)"

# Exact row counts of every public table, in one statement.
cat >"$work/counts.sql" <<'SQL'
select c.relname, (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text
  from pg_class c join pg_namespace s on s.oid = c.relnamespace
 where s.nspname = 'public' and c.relkind in ('r', 'p')
 order by 1;
SQL
in_scratch -F, <"$work/counts.sql" >"$work/restored.csv"
"$DB_ROOT/scripts/db/query.sh" "$source_environment" --file "$work/counts.sql" --format csv |
  tail -n +2 >"$work/production.csv"

awk -F, '
  NR == FNR { restored[$1] = $2; next }
  {
    tables++
    if (!($1 in restored)) { missing++; print "missing: " $1; next }
    if (restored[$1] == $2) { same++; next }
    diff = $2 - restored[$1]
    if ($2 > 0 && restored[$1] == 0) { empty++; print "empty in restore: " $1 " (production " $2 ")" }
    else { drift++; print "differs: " $1 " restore " restored[$1] ", production " $2 }
  }
  END {
    printf "public tables: %d, identical: %d, differ: %d, empty: %d, missing: %d\n", tables, same, drift, empty, missing
    exit (missing + empty > 0) ? 1 : 0
  }
' "$work/restored.csv" "$work/production.csv"
echo "pg_restore errors: $restore_errors (objects outside the dumped schemas; the data check above is the verdict)"
grep '^pg_restore: error' "$work/restore.log" | sed -E 's/^pg_restore: error: (could not execute query: )?//' |
  cut -c1-150 | sort | uniq -c | sort -rn | head -12 || true
