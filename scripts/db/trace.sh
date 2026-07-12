#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
environment="${1:-}"
kind="${2:-}"
identifier="${3:-}"

uuid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
[[ "$identifier" =~ $uuid_pattern ]] || {
  echo "Usage: $0 <local|staging|production> <operation|product|tenant> <uuid>" >&2
  exit 64
}

case "$kind" in
  operation)
    sql="select * from public.inventory_accounting_operation_trace_view where operation_id = '$identifier'::uuid"
    ;;
  product)
    sql="select id, product_id, product_name, product_sku, transaction_date, movement_type, source, reference_id, reference_number, reconciled_quantity, stock_before, stock_after, actual_stock_delta, balance_provenance, integrity_status, operation_id, source_document_type, source_document_id from public.stock_movements_audit_view where product_id = '$identifier'::uuid order by transaction_date desc, created_at desc, id desc limit 250"
    ;;
  tenant)
    sql="select * from public.inventory_accounting_inconsistencies_view where tenant_id = '$identifier'::uuid order by occurred_at desc limit 250"
    ;;
  *)
    echo "Trace kind must be operation, product or tenant" >&2
    exit 64
    ;;
esac

exec bash "$ROOT_DIR/scripts/db/query.sh" "$environment" --sql "$sql" --format json
