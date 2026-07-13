#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment="${1:-local}"
[[ "$environment" =~ ^(local|staging|production)$ ]] || {
  echo "Environment must be local, staging or production" >&2
  exit 64
}

sql_file="$ROOT_DIR/supabase/manual_checks/diagnostics/erp_integrity_health.sql"
output="$(bash "$ROOT_DIR/scripts/db/query.sh" "$environment" --file "$sql_file" --format csv)"
printf '%s\n' "$output"

if printf '%s\n' "$output" | rg '^critical,[^,]+,[1-9][0-9]*,f,' >/dev/null; then
  echo "$environment ERP integrity health failed" >&2
  exit 2
fi
echo "$environment ERP integrity health passed (warnings may still require operational review)"
