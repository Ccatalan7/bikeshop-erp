#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cd "$DB_ROOT"
expected_staging_ref="bczzjhjrpmtpgwdvlbut"
[[ "${VINABIKE_STAGING_REACTIVATION_CONFIRM:-}" == "$expected_staging_ref" ]] ||
  die "Staging is policy-dormant; explicit owner reactivation is required"
[[ "${VINABIKE_STAGING_SCHEMA_CONFIRM:-}" == "staging" ]] || die "Set VINABIKE_STAGING_SCHEMA_CONFIRM=staging to run the hosted staging schema gate"
require_command psql
configure_remote_pg staging

staging_ref="${PGUSER#postgres.}"
production_ref="$(tr -d '[:space:]' <supabase/.temp/project-ref)"
[[ "$staging_ref" == "$expected_staging_ref" ]] ||
  die "Staging connection identity does not match the approved dormant project"
[[ "$staging_ref" != "$production_ref" ]] || die "Staging ref matches production; refusing schema application"

timestamp="$(date +%Y%m%d-%H%M%S)"
log_file="$DB_CACHE_DIR/staging-schema-$timestamp.log"
before_file="$DB_CACHE_DIR/staging-counts-before-$timestamp.json"
after_file="$DB_CACHE_DIR/staging-counts-after-$timestamp.json"

business_counts_sql="select jsonb_build_object(
  'tenants', (select count(*) from public.tenants),
  'products', (select count(*) from public.products),
  'sales_invoices', (select count(*) from public.sales_invoices),
  'purchase_invoices', (select count(*) from public.purchase_invoices),
  'stock_movements', (select count(*) from public.stock_movements),
  'journal_entries', (select count(*) from public.journal_entries)
)"

psql "dbname=postgres" -XAt -v ON_ERROR_STOP=1 -c "$business_counts_sql" >"$before_file"
echo "Applying canonical schema to staging $staging_ref; detailed output is captured outside Git."
if ! psql "dbname=postgres" -X -v ON_ERROR_STOP=1 -f supabase/sql/core_schema.sql >"$log_file" 2>&1; then
  tail -60 "$log_file" >&2
  die "Staging schema application failed; full log: $log_file"
fi
psql "dbname=postgres" -XAt -v ON_ERROR_STOP=1 -c "$business_counts_sql" >"$after_file"

if ! cmp -s "$before_file" "$after_file"; then
  echo "Business row counts changed unexpectedly:" >&2
  diff -u "$before_file" "$after_file" >&2 || true
  die "Staging schema gate failed its before/after invariant"
fi

echo "Staging schema gate passed; business row counts were unchanged."
echo "Apply log: $log_file"
