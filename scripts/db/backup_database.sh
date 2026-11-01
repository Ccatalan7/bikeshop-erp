#!/usr/bin/env bash
# Own backup of the ERP database, encrypted for the owner's key.
#
# Usage: backup_database.sh <production|local> <output-dir>
#
# Writes base-<UTC stamp>.dump.cms (a pg_dump custom archive encrypted to
# scripts/db/backup/recipient.pem) and its .sha256. The plain dump only ever
# exists in the pipe. Supabase's daily backups come with the Pro plan; this
# is what keeps a copy outside Supabase on any plan. `local` dumps the local
# Supabase database and exists to test the pipeline and the restore drill.
#
# What it reads, and why not everything: each production run is database
# egress (it counts against the 5 GB of the free plan), so the dump takes the
# schemas that hold the ERP (BACKUP_SCHEMAS) and leaves out the data of a log
# nobody restores, auth.audit_log_entries. The schemas Supabase manages
# (MANAGED_SCHEMAS: pg_cron's run history, pg_net's answers, realtime, vault,
# extensions) come back with a new project and the migrations. A schema in
# neither list stops the backup: the first drill found `private`, whose
# functions the access policies call, missing from the dump.
#
# pg_dump must have the server's major version: an older one refuses, and a
# newer one writes an archive the server's own pg_restore cannot read. On this
# Mac the local Supabase container has the right one and is used when the
# PATH's is wrong; CI installs postgresql-client-17.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly BACKUP_PROJECT_REF="xzdvtzdqjeyqxnkqprtf"
# A restore drill may encrypt to a throwaway certificate instead.
readonly BACKUP_CERT="${BACKUP_RECIPIENT_CERT:-$DB_ROOT/scripts/db/backup/recipient.pem}"

environment="${1:-}"
output_dir="${2:-}"
[[ "$environment" =~ ^(production|local)$ && -n "$output_dir" ]] ||
  die "Usage: backup_database.sh <production|local> <output-dir>"
[[ -f "$BACKUP_CERT" ]] || die "Missing ${BACKUP_CERT#"$DB_ROOT/"}; run scripts/db/backup_create_key.sh once"
require_command openssl

readonly BACKUP_SCHEMAS=(public private assistant_runtime auth storage supabase_migrations)
readonly MANAGED_SCHEMAS=(cron extensions graphql graphql_public net pgbouncer realtime supabase_functions vault
  _realtime _analytics pgsodium pgsodium_masks pgtle)

dump_args=(--format=custom --compress=9 --no-owner --no-privileges
  --exclude-table-data=auth.audit_log_entries)
for schema in "${BACKUP_SCHEMAS[@]}"; do dump_args+=("--schema=$schema"); done

pg_dump_major() { "$@" --version | sed -E 's/[^0-9]*([0-9]+).*/\1/'; }
local_container() { docker ps --format '{{.Names}}' 2>/dev/null | grep -m1 '^supabase_db_' || true; }
schemas_sql="select nspname from pg_namespace where nspname !~ '^pg_' and nspname <> 'information_schema' order by 1"

if [[ "$environment" == local ]]; then
  container="$(local_container)"
  [[ -n "$container" ]] || die "The local Supabase database is not running (scripts/db/ensure_local.sh)"
  run_sql() { docker exec "$container" psql -U postgres -d postgres -XAtq -c "$1"; }
  run_dump() { docker exec "$container" pg_dump -U postgres -d postgres "${dump_args[@]}"; }
else
  require_command psql
  configure_remote_pg production
  [[ "$PGUSER" == "postgres.$BACKUP_PROJECT_REF" ]] ||
    die "The linked project is not the approved production project"
  export PGCONNECT_TIMEOUT=20 PGAPPNAME=vinabike_backup
  run_sql() { psql -XAtq -c "$1"; }

  server_major="$(run_sql 'show server_version_num')"
  server_major="${server_major:0:2}"

  if command -v pg_dump >/dev/null 2>&1 && [[ "$(pg_dump_major pg_dump)" == "$server_major" ]]; then
    run_dump() { pg_dump "${dump_args[@]}"; }
  else
    container="$(local_container)"
    [[ -n "$container" && "$(pg_dump_major docker exec "$container" pg_dump)" == "$server_major" ]] ||
      die "No pg_dump $server_major found (PATH or the local Supabase container)"
    run_dump() {
      docker exec -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE \
        -e PGCONNECT_TIMEOUT -e PGAPPNAME "$container" pg_dump "${dump_args[@]}"
    }
  fi
fi

unknown=()
while IFS= read -r schema; do
  [[ " ${BACKUP_SCHEMAS[*]} ${MANAGED_SCHEMAS[*]} " == *" $schema "* ]] || unknown+=("$schema")
done < <(run_sql "$schemas_sql")
((${#unknown[@]} == 0)) ||
  die "Schemas neither backed up nor managed by Supabase: ${unknown[*]}; add each to BACKUP_SCHEMAS or MANAGED_SCHEMAS"

mkdir -p "$output_dir"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$output_dir/base-$stamp.dump.cms"
started="$(date +%s)"

run_dump |
  openssl cms -encrypt -binary -stream -aes-256-gcm -outform DER \
    -out "$archive" "$BACKUP_CERT"

[[ -s "$archive" ]] || die "The encrypted archive is empty"
sha256="$(sha256_file "$archive")"
printf '%s  %s\n' "$sha256" "$(basename "$archive")" >"$archive.sha256"

bytes="$(wc -c <"$archive" | tr -d ' ')"
echo "Backup $(basename "$archive") ($environment): $((bytes / 1024)) KiB encrypted, $(($(date +%s) - started)) s, sha256 $sha256"
