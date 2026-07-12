-- READ-ONLY: Inventory/accounting traceability baseline.
-- Run one numbered query at a time. Replace the tenant/SKU parameters first.
-- No statement in this file mutates data.

-- 1. Combined tenant metrics.
with params as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id
), metrics as (
  select 'tracked_products' metric, count(*)::bigint value
  from public.products p, params x
  where p.tenant_id = x.tenant_id
    and coalesce(p.track_stock, true)
    and coalesce(p.product_type, 'product') <> 'service'
  union all
  select 'stock_column_drift', count(*)
  from public.products p, params x
  where p.tenant_id = x.tenant_id
    and coalesce(p.inventory_qty, 0) <> coalesce(p.stock_quantity, 0)
  union all
  select 'manual_adjustments_without_actor', count(*)
  from public.stock_adjustments sa, params x
  where sa.tenant_id = x.tenant_id
    and sa.adjustment_type = 'manual'
    and sa.created_by is null
  union all
  select 'unbalanced_journals', count(*)
  from (
    select je.id
    from public.journal_entries je
    join params x on x.tenant_id = je.tenant_id
    left join public.journal_lines jl
      on jl.entry_id = je.id and jl.tenant_id = je.tenant_id
    group by je.id
    having round(coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0), 2) <> 0
  ) broken
)
select * from metrics order by metric;

-- 2. One product: current balance versus signed movement net.
with params as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    '4715575883212'::text as sku
)
select
  p.id,
  p.name,
  p.sku,
  p.inventory_qty,
  p.stock_quantity,
  count(sm.id) as movement_count,
  coalesce(sum(
    case
      when sm.type in ('OUT', 'TRANSFER_OUT') then -abs(sm.quantity)
      when sm.type in ('IN', 'TRANSFER_IN') then abs(sm.quantity)
      else sm.quantity
    end
  ), 0) as signed_movement_net
from public.products p
join params x on x.tenant_id = p.tenant_id and x.sku = p.sku
left join public.stock_movements sm
  on sm.tenant_id = p.tenant_id and sm.product_id = p.id
group by p.id;

-- 3. Automatic purchase reversals that generated a same-time manual adjustment.
select
  sm.reference,
  sm.product_id,
  sm.created_at,
  sm.quantity as reversal_quantity,
  sa.id as adjustment_id,
  sa.quantity as manual_quantity,
  sa.stock_before,
  sa.stock_after,
  sa.created_by
from public.stock_movements sm
join public.stock_adjustments sa
  on sa.tenant_id = sm.tenant_id
 and sa.product_id = sm.product_id
 and sa.created_at = sm.created_at
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sm.movement_type = 'purchase_invoice_reversal'
  and sa.adjustment_type = 'manual'
order by sm.created_at desc;

-- 4. Live trigger/function fingerprints for drift comparison.
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  md5(pg_get_functiondef(p.oid)) as definition_md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'handle_sales_invoice_change',
    'consume_sales_invoice_inventory',
    'restore_sales_invoice_inventory',
    'handle_purchase_invoice_change',
    'consume_purchase_invoice_inventory',
    'restore_purchase_invoice_inventory',
    'consume_mechanic_job_inventory',
    'restore_mechanic_job_inventory',
    'process_online_order',
    'apply_inventory_stock_adjustment',
    'track_product_stock_changes'
  )
order by p.proname, arguments;

-- 5. POST-DEPLOY ONLY: trace-kernel inconsistencies for one tenant.
-- First confirm to_regclass('public.inventory_accounting_inconsistencies_view') is not null.
select
  inconsistency_type,
  severity,
  entity_type,
  entity_id,
  operation_id,
  expected_value,
  actual_value,
  occurred_at
from public.inventory_accounting_inconsistencies_view
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by occurred_at desc, severity, inconsistency_type;

-- 6. POST-DEPLOY ONLY: reconstruct one complete operation by operation UUID.
select *
from public.inventory_accounting_operation_trace_view
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and operation_id = '00000000-0000-0000-0000-000000000000';

-- 7. Workshop jobs where both the job and its linked invoice posted stock.
with linked as (
  select job.id as job_id, job.invoice_id, job.job_number
  from public.mechanic_jobs job
  where job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and job.invoice_id is not null
), job_effects as (
  select
    linked.job_id,
    linked.invoice_id,
    linked.job_number,
    movement.product_id,
    sum(case when movement.type = 'OUT' then abs(movement.quantity) else 0 end) as job_out
  from linked
  join public.stock_movements movement
    on movement.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and movement.reference = 'mechanic_job:' || linked.job_id::text
  group by linked.job_id, linked.invoice_id, linked.job_number, movement.product_id
), invoice_effects as (
  select
    linked.job_id,
    linked.invoice_id,
    movement.product_id,
    sum(case when movement.type = 'OUT' then abs(movement.quantity) else 0 end) as invoice_out
  from linked
  join public.stock_movements movement
    on movement.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and movement.reference = 'sales_invoice:' || linked.invoice_id::text
  group by linked.job_id, linked.invoice_id, movement.product_id
)
select
  job_effects.job_number,
  job_effects.job_id,
  job_effects.invoice_id,
  job_effects.product_id,
  job_effects.job_out,
  invoice_effects.invoice_out,
  job_effects.job_out + invoice_effects.invoice_out as combined_out
from job_effects
join invoice_effects using (job_id, invoice_id, product_id)
where job_effects.job_out > 0
  and invoice_effects.invoice_out > 0
order by job_effects.job_number, job_effects.product_id;

-- 8. Active purchase payment ledger versus current/legacy payment journals.
with active as (
  select payment.*, invoice.invoice_number
  from public.purchase_payments payment
  join public.purchase_invoices invoice
    on invoice.id = payment.invoice_id
   and invoice.tenant_id = payment.tenant_id
  where payment.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and payment.deleted_at is null
)
select
  active.id as payment_id,
  active.invoice_id,
  active.invoice_number,
  active.amount,
  count(entry.id) as recognized_journal_count,
  coalesce(sum(entry.total_debit), 0) as journal_total
from active
left join public.journal_entries entry
  on entry.tenant_id = active.tenant_id
 and entry.source_module = 'purchase_payments'
 and entry.source_reference in (active.id::text, active.invoice_number)
group by active.id, active.invoice_id, active.invoice_number, active.amount
having count(entry.id) = 0
    or round(coalesce(sum(entry.total_debit), 0), 2) <> round(active.amount, 2)
order by active.invoice_number, active.id;

-- 9. Purchase reversals that produced same-time phantom manual adjustments.
select
  invoice.invoice_number,
  invoice.id as invoice_id,
  movement.product_id,
  movement.id as reversal_movement_id,
  adjustment.id as phantom_adjustment_id,
  adjustment.quantity,
  adjustment.stock_before,
  adjustment.stock_after,
  adjustment.created_by,
  adjustment.created_at
from public.purchase_invoices invoice
join public.stock_movements movement
  on movement.tenant_id = invoice.tenant_id
 and movement.reference = 'purchase_invoice:' || invoice.id::text
 and movement.movement_type = 'purchase_invoice_reversal'
join public.stock_adjustments adjustment
  on adjustment.tenant_id = movement.tenant_id
 and adjustment.product_id = movement.product_id
 and adjustment.created_at = movement.created_at
 and adjustment.adjustment_type = 'manual'
where invoice.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by adjustment.created_at, invoice.invoice_number, movement.product_id;

-- 10. Multi-bike linked invoice/payment consistency and attribution coverage.
with multi_bike_jobs as (
  select
    job.id,
    job.job_number,
    job.invoice_id,
    job.is_paid,
    count(job_bike.id) as bike_count
  from public.mechanic_jobs job
  join public.mechanic_job_bikes job_bike
    on job_bike.job_id = job.id
   and job_bike.tenant_id = job.tenant_id
  where job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  group by job.id
  having count(job_bike.id) >= 2
)
select
  job.job_number,
  job.id as job_id,
  job.bike_count,
  invoice.invoice_number,
  invoice.status,
  invoice.total,
  invoice.paid_amount,
  invoice.balance,
  job.is_paid,
  count(item.value) as invoice_item_count,
  count(item.value) filter (
    where nullif(item.value->>'job_bike_id', '') is null
  ) as items_without_bike_attribution
from multi_bike_jobs job
join public.sales_invoices invoice on invoice.id = job.invoice_id
left join lateral jsonb_array_elements(invoice.items) item(value) on true
group by job.id, job.job_number, job.bike_count, job.is_paid, invoice.id
order by job.job_number;
