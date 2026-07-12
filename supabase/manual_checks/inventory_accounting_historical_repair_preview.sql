-- READ-ONLY: production-shaped historical repair preview.
-- This file only classifies evidence and computes proposed compensating quantities.
-- It intentionally does not delete legacy rows or mutate stock/accounting data.

with tenant as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id
), phantom_pairs as (
  select distinct on (adjustment.id)
    invoice.id as invoice_id,
    invoice.invoice_number,
    movement.id as reversal_movement_id,
    movement.product_id,
    adjustment.id as phantom_adjustment_id,
    adjustment.quantity as phantom_quantity,
    adjustment.stock_before,
    adjustment.stock_after,
    adjustment.created_at
  from tenant
  join public.purchase_invoices invoice
    on invoice.tenant_id = tenant.tenant_id
  join public.stock_movements movement
    on movement.tenant_id = invoice.tenant_id
   and movement.reference = 'purchase_invoice:' || invoice.id::text
   and movement.movement_type = 'purchase_invoice_reversal'
  join public.stock_adjustments adjustment
    on adjustment.tenant_id = movement.tenant_id
   and adjustment.product_id = movement.product_id
   and adjustment.created_at = movement.created_at
   and adjustment.adjustment_type = 'manual'
  order by adjustment.id, movement.id
), product_corrections as (
  select
    pair.product_id,
    product.sku,
    product.name,
    product.inventory_qty as current_inventory_qty,
    product.stock_quantity as current_stock_quantity,
    count(*) as evidence_rows,
    sum(pair.phantom_quantity) as historical_phantom_net,
    -sum(pair.phantom_quantity) as proposed_compensating_quantity,
    product.inventory_qty - sum(pair.phantom_quantity) as projected_inventory_qty
  from phantom_pairs pair
  join public.products product
    on product.id = pair.product_id
  group by pair.product_id, product.sku, product.name,
           product.inventory_qty, product.stock_quantity
), invoice_corrections as (
  select
    pair.invoice_id,
    pair.invoice_number,
    count(*) as evidence_rows,
    sum(pair.phantom_quantity) as historical_phantom_net,
    -sum(pair.phantom_quantity) as proposed_compensating_quantity,
    min(pair.created_at) as first_seen_at,
    max(pair.created_at) as last_seen_at
  from phantom_pairs pair
  group by pair.invoice_id, pair.invoice_number
), active_purchase_payments as (
  select payment.*, invoice.invoice_number
  from tenant
  join public.purchase_payments payment
    on payment.tenant_id = tenant.tenant_id
   and payment.deleted_at is null
  join public.purchase_invoices invoice
    on invoice.id = payment.invoice_id
   and invoice.tenant_id = payment.tenant_id
), payment_journal_findings as (
  select
    payment.id as payment_id,
    payment.invoice_id,
    payment.invoice_number,
    payment.amount,
    count(entry.id) as recognized_journal_count,
    coalesce(sum(entry.total_debit), 0) as recognized_journal_total,
    case
      when count(entry.id) = 0 then 'missing_journal'
      when count(entry.id) > 1 then 'duplicate_journal'
      when round(coalesce(sum(entry.total_debit), 0), 2) <> round(payment.amount, 2)
        then 'journal_amount_mismatch'
    end as finding
  from active_purchase_payments payment
  left join public.journal_entries entry
    on entry.tenant_id = payment.tenant_id
   and entry.source_module = 'purchase_payments'
   and entry.source_reference in (payment.id::text, payment.invoice_number)
  group by payment.id, payment.invoice_id, payment.invoice_number, payment.amount
  having count(entry.id) <> 1
      or round(coalesce(sum(entry.total_debit), 0), 2) <> round(payment.amount, 2)
), linked_jobs as (
  select job.id as job_id, job.invoice_id, job.job_number
  from tenant
  join public.mechanic_jobs job on job.tenant_id = tenant.tenant_id
  where job.invoice_id is not null
), job_effects as (
  select
    job.job_id,
    job.invoice_id,
    job.job_number,
    movement.product_id,
    sum(case when movement.type = 'OUT' then abs(movement.quantity) else 0 end) as job_out
  from linked_jobs job
  join public.stock_movements movement
    on movement.reference = 'mechanic_job:' || job.job_id::text
  group by job.job_id, job.invoice_id, job.job_number, movement.product_id
), invoice_effects as (
  select
    job.job_id,
    job.invoice_id,
    movement.product_id,
    sum(case when movement.type = 'OUT' then abs(movement.quantity) else 0 end) as invoice_out
  from linked_jobs job
  join public.stock_movements movement
    on movement.reference = 'sales_invoice:' || job.invoice_id::text
  group by job.job_id, job.invoice_id, movement.product_id
), dual_owner_findings as (
  select
    job.job_number,
    job.job_id,
    job.invoice_id,
    job.product_id,
    job.job_out,
    invoice.invoice_out,
    least(job.job_out, invoice.invoice_out) as possible_duplicate_out
  from job_effects job
  join invoice_effects invoice using (job_id, invoice_id, product_id)
  where job.job_out > 0 and invoice.invoice_out > 0
)
select jsonb_build_object(
  'generated_at', now(),
  'mode', 'read_only_preview',
  'phantom_purchase_adjustments', jsonb_build_object(
    'evidence_rows', (select count(*) from phantom_pairs),
    'affected_invoices', (select count(*) from invoice_corrections),
    'affected_products', (select count(*) from product_corrections),
    'proposed_total_compensating_quantity',
      (select coalesce(sum(proposed_compensating_quantity), 0) from product_corrections),
    'by_invoice', (select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_number), '[]'::jsonb) from invoice_corrections x),
    'by_product', (select coalesce(jsonb_agg(to_jsonb(x) order by x.sku, x.product_id), '[]'::jsonb) from product_corrections x)
  ),
  'purchase_payment_journal_findings', jsonb_build_object(
    'count', (select count(*) from payment_journal_findings),
    'rows', (select coalesce(jsonb_agg(to_jsonb(x) order by x.invoice_number, x.payment_id), '[]'::jsonb) from payment_journal_findings x)
  ),
  'workshop_invoice_dual_stock_owner_findings', jsonb_build_object(
    'count', (select count(*) from dual_owner_findings),
    'rows', (select coalesce(jsonb_agg(to_jsonb(x) order by x.job_number, x.product_id), '[]'::jsonb) from dual_owner_findings x)
  )
) as repair_preview;
