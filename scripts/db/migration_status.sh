#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/db/migration_status.sh MIGRATION.sql [MIGRATION.sql ...]

Reads the authoritative production migration history and reports whether each
exact standalone forward migration is APPLIED or NOT_APPLIED. File comments,
Git state and core_schema.sql are never deployment stamps.
USAGE
  exit 64
}

[[ "$#" -gt 0 ]] || usage
cd "$DB_ROOT"

rows=""
for requested in "$@"; do
  resolve_forward_migration "$requested"
  row="('${MIGRATION_VERSION}', '${MIGRATION_FILENAME}')"
  rows="${rows:+$rows, }$row"
done

sql="with requested(version, filename) as (
  values $rows
), applied as (
  select version::text
  from supabase_migrations.schema_migrations
)
select
  requested.filename,
  requested.version,
  case when applied.version is null then 'NOT_APPLIED' else 'APPLIED' end as production_status
from requested
left join applied using (version)
order by requested.version"

exec bash "$DB_ROOT/scripts/db/query.sh" production \
  --format table \
  --max-rows 0 \
  --sql "$sql"
