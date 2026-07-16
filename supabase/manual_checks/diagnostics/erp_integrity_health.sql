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
    'negative_stock_without_completed_trace',
    count(distinct product.id),
    'staff sales may end negative, but every recent negative transition requires a completed trace operation'
  from public.products product
  where coalesce(product.track_stock, true)
    and coalesce(product.product_type, 'product') <> 'service'
    and greatest(coalesce(product.inventory_qty, 0), coalesce(product.stock_quantity, 0)) < 0
    and exists (
      select 1
      from public.stock_movements movement
      left join public.inventory_accounting_operations operation
        on operation.id = movement.operation_id
       and operation.tenant_id = movement.tenant_id
      where movement.product_id = product.id
        and movement.created_at >= '2026-07-12 00:00:00+00'::timestamptz
        and coalesce(movement.stock_after, 0) < 0
        and (
          movement.operation_id is null
          or operation.outcome is distinct from 'completed'
        )
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

  union all

  select
    'critical',
    'active_quotation_financial_effect',
    count(*),
    'active quotations must have no invoice and must remain no-tax previews whose total equals lines minus discount'
  from public.mechanic_jobs job
  left join lateral (
    select
      public.clp_round(coalesce(sum(coalesce(
        item.total_price,
        item.quantity * item.unit_price,
        0
      )), 0)) as gross,
      public.clp_round(coalesce(sum(coalesce(
        item.total_price,
        item.quantity * item.unit_price,
        0
      )) filter (
        where coalesce(item.item_type, 'product') <> 'service'
      ), 0)) as parts,
      public.clp_round(coalesce(sum(coalesce(
        item.total_price,
        item.quantity * item.unit_price,
        0
      )) filter (
        where coalesce(item.item_type, 'product') = 'service'
      ), 0)) as labor
    from public.mechanic_job_items item
    where item.job_id = job.id
      and item.tenant_id = job.tenant_id
  ) lines on true
  where job.deleted_at is null
    and job.workflow_kind = 'quotation'
    and (
      job.invoice_id is not null
      or job.requires_approval is distinct from true
      or job.is_invoiced is distinct from false
      or job.is_paid is distinct from false
      or job.tax_treatment is distinct from 'no_tax'
      or public.clp_round(job.tax_amount) <> 0
      or public.clp_round(job.parts_cost) <> lines.parts
      or public.clp_round(job.labor_cost) <> lines.labor
      or public.clp_round(job.total_cost)
           <> lines.gross - public.clp_round(coalesce(job.discount_amount, 0))
      or exists (
        select 1
        from public.stock_movements movement
        where movement.tenant_id = job.tenant_id
          and movement.source_document_id = job.id
      )
      or exists (
        select 1
        from public.journal_entries entry
        where entry.tenant_id = job.tenant_id
          and entry.source_document_id = job.id
      )
    )

  union all

  select
    'critical',
    'approved_quotation_without_snapshot',
    count(*),
    'every active approved quotation needs an immutable commercial snapshot before conversion'
  from public.mechanic_jobs job
  where job.deleted_at is null
    and job.workflow_kind = 'quotation'
    and job.quotation_status = 'approved'
    and not exists (
      select 1
      from public.mechanic_job_mode_events event
      where event.tenant_id = job.tenant_id
        and event.job_id = job.id
        and event.event_type = 'quotation_status_changed'
        and event.to_quotation_status = 'approved'
        and event.metadata ? 'quotation_snapshot'
        and nullif(event.metadata->>'quotation_snapshot_hash', '') is not null
    )
)
select severity, check_name, violations, violations = 0 as passed, details
from health_checks
order by severity, check_name;
