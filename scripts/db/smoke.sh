#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment="${1:-staging}"
[[ "$environment" =~ ^(local|staging|production)$ ]] || {
  echo "Environment must be local, staging or production" >&2
  exit 64
}

sql_file="$ROOT_DIR/supabase/manual_checks/diagnostics/staging_schema_smoke.sql"
output="$(bash "$ROOT_DIR/scripts/db/query.sh" "$environment" --file "$sql_file" --format csv)"
printf '%s\n' "$output"

if printf '%s\n' "$output" | rg ',f,' >/dev/null; then
  echo "$environment schema smoke failed" >&2
  exit 2
fi
echo "$environment schema smoke passed"
