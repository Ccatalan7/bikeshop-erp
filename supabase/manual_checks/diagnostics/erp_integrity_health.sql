with health_checks(severity, check_name, violations, details) as (
  select
    'critical',
    'dual_stock_mismatch',
    count(*),
    'tracked products must keep inventory_qty equal to stock_quantity'
  from public.products
  where coalesce(track_stock, true)
    and coalesce(product_type, 'product') <> 'service'
    and inventory_qty is distinct from stock_quantity

  union all

  select
    'warning',
    'historical_negative_stock',
    count(*),
    'ledger-reconciled shortages require operational review, not automatic correction'
  from public.products
  where coalesce(track_stock, true)
    and coalesce(product_type, 'product') <> 'service'
    and greatest(coalesce(inventory_qty, 0), coalesce(stock_quantity, 0)) < 0

  union all

  select
    'critical',
    'new_negative_stock_after_guard',
    count(*),
    'no product may newly end negative after the professional negative-stock guard'
  from public.products product
  where coalesce(product.track_stock, true)
    and coalesce(product.product_type, 'product') <> 'service'
    and greatest(coalesce(product.inventory_qty, 0), coalesce(product.stock_quantity, 0)) < 0
    and exists (
      select 1 from public.stock_movements movement
      where movement.product_id = product.id
        and movement.created_at >= '2026-07-12 00:00:00+00'::timestamptz
    )

  union all

  select
    'critical',
    'unbalanced_journal_headers',
    count(*),
    'journal entry total debit must equal total credit'
  from public.journal_entries
  where coalesce(total_debit, 0) <> coalesce(total_credit, 0)

  union all

  select
    'critical',
    'journal_header_line_mismatch',
    count(*),
    'journal line sums must balance and equal their entry header'
  from (
    select entry.id
    from public.journal_entries entry
    left join public.journal_lines line on line.entry_id = entry.id
    group by entry.id, entry.total_debit, entry.total_credit
    having coalesce(sum(line.debit_amount), 0) <> coalesce(entry.total_debit, 0)
      or coalesce(sum(line.credit_amount), 0) <> coalesce(entry.total_credit, 0)
      or coalesce(sum(line.debit_amount), 0) <> coalesce(sum(line.credit_amount), 0)
  ) mismatch

  union all

  select
    'critical',
    'recent_stock_evidence_errors',
    count(*),
    'new traced movements must not have arithmetic or ledger/source balance errors'
  from public.stock_movements_audit_view
  where created_at >= '2026-07-10 00:00:00+00'::timestamptz
    and integrity_status in ('arithmetic_mismatch', 'ledger_source_balance_mismatch')

  union all

  select
    'critical',
    'recent_incomplete_operations',
    count(*),
    'trace operations may not remain started for more than five minutes'
  from public.inventory_accounting_operations
  where created_at >= '2026-07-10 00:00:00+00'::timestamptz
    and outcome = 'started'
    and created_at < now() - interval '5 minutes'

  union all

  select
    'critical',
    'sales_payment_math_mismatch',
    count(*),
    'sales invoice balance must equal whole-CLP total minus paid amount'
  from public.sales_invoices
  where public.clp_round(balance)
    <> greatest(public.clp_round(total) - public.clp_round(paid_amount), 0)

  union all

  select
    'critical',
    'purchase_payment_math_mismatch',
    count(*),
    'purchase invoice balance must equal whole-CLP total minus paid amount'
  from public.purchase_invoices
  where public.clp_round(balance)
    <> greatest(public.clp_round(total) - public.clp_round(paid_amount), 0)
)
select severity, check_name, violations, violations = 0 as passed, details
from health_checks
order by severity, check_name;
