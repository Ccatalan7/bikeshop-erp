-- READ-ONLY: workshop job -> sales invoice inventory/accounting ownership audit.
-- No statement in this file mutates production data.

with tenant as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id
), jobs as (
  select job.*
  from public.mechanic_jobs job, tenant
  where job.tenant_id = tenant.tenant_id
), job_item_totals as (
  select
    item.job_id,
    count(*) filter (where item.product_id is not null) as tracked_item_rows,
    coalesce(sum(item.quantity) filter (where item.product_id is not null), 0) as tracked_item_quantity,
    count(*) filter (where item.product_id is not null and item.job_bike_id is null) as unattributed_tracked_rows
  from public.mechanic_job_items item
  join jobs job on job.id = item.job_id
  group by item.job_id
), job_movement_totals as (
  select
    job.id as job_id,
    coalesce(sum(abs(movement.quantity)) filter (
      where movement.reference = 'mechanic_job:' || job.id::text
        and movement.type = 'OUT'
    ), 0) as job_out,
    coalesce(sum(abs(movement.quantity)) filter (
      where movement.reference = 'mechanic_job:' || job.id::text || ':reversed'
        and movement.type = 'IN'
    ), 0) as job_reversal_in
  from jobs job
  left join public.stock_movements movement
    on movement.tenant_id = job.tenant_id
   and movement.reference in (
     'mechanic_job:' || job.id::text,
     'mechanic_job:' || job.id::text || ':reversed'
   )
  group by job.id
), invoice_movement_totals as (
  select
    job.id as job_id,
    coalesce(sum(abs(movement.quantity)) filter (where movement.type = 'OUT'), 0) as invoice_out,
    coalesce(sum(abs(movement.quantity)) filter (where movement.type = 'IN'), 0) as invoice_reversal_in
  from jobs job
  left join public.stock_movements movement
    on job.invoice_id is not null
   and movement.tenant_id = job.tenant_id
   and movement.reference = 'sales_invoice:' || job.invoice_id::text
  group by job.id
), job_journals as (
  select
    job.id as job_id,
    count(entry.id) filter (
      where entry.source_module = 'mechanic_jobs'
        and entry.source_reference = job.job_number
    ) as job_number_journals,
    count(entry.id) filter (
      where entry.source_module = 'mechanic_jobs'
        and entry.source_reference = job.id::text
    ) as job_id_journals
  from jobs job
  left join public.journal_entries entry
    on entry.tenant_id = job.tenant_id
   and entry.source_module = 'mechanic_jobs'
   and entry.source_reference in (job.job_number, job.id::text)
  group by job.id
), invoice_journals as (
  select
    job.id as job_id,
    count(entry.id) as invoice_journals
  from jobs job
  left join public.sales_invoices invoice on invoice.id = job.invoice_id
  left join public.journal_entries entry
    on entry.tenant_id = job.tenant_id
   and entry.source_module = 'sales_invoices'
   and entry.source_reference in (invoice.invoice_number, invoice.id::text)
  group by job.id
), classified as (
  select
    job.id as job_id,
    job.job_number,
    job.status as job_status,
    job.invoice_id,
    invoice.invoice_number,
    invoice.status as invoice_status,
    job.is_invoiced,
    job.is_paid,
    coalesce(items.tracked_item_rows, 0) as tracked_item_rows,
    coalesce(items.tracked_item_quantity, 0) as tracked_item_quantity,
    coalesce(items.unattributed_tracked_rows, 0) as unattributed_tracked_rows,
    movement.job_out,
    movement.job_reversal_in,
    invoice_movement.invoice_out,
    invoice_movement.invoice_reversal_in,
    journals.job_number_journals,
    journals.job_id_journals,
    invoice_journal.invoice_journals,
    case
      when movement.job_out > 0 and invoice_movement.invoice_out > 0 then 'dual_inventory_owner'
      when movement.job_out > 0 then 'job_inventory_owner'
      when invoice_movement.invoice_out > 0 then 'invoice_inventory_owner'
      when movement.job_reversal_in > 0 and movement.job_out = 0 then 'job_original_out_deleted'
      when coalesce(items.tracked_item_rows, 0) > 0 then 'no_persisted_inventory_owner'
      else 'no_stock_items'
    end as inventory_classification,
    case
      when journals.job_number_journals > 0 and invoice_journal.invoice_journals > 0 then 'dual_revenue_journal'
      when journals.job_number_journals > 1 or journals.job_id_journals > 1 then 'duplicate_job_journal'
      when journals.job_number_journals > 0 then 'job_journal_only'
      when invoice_journal.invoice_journals > 0 then 'invoice_journal_only'
      else 'no_revenue_journal'
    end as accounting_classification
  from jobs job
  left join public.sales_invoices invoice on invoice.id = job.invoice_id
  left join job_item_totals items on items.job_id = job.id
  join job_movement_totals movement on movement.job_id = job.id
  join invoice_movement_totals invoice_movement on invoice_movement.job_id = job.id
  join job_journals journals on journals.job_id = job.id
  join invoice_journals invoice_journal on invoice_journal.job_id = job.id
)
select jsonb_build_object(
  'generated_at', now(),
  'mode', 'read_only',
  'job_count', (select count(*) from classified),
  'linked_job_count', (select count(*) from classified where invoice_id is not null),
  'inventory_classifications', (
    select jsonb_object_agg(inventory_classification, rows)
    from (
      select inventory_classification, count(*) as rows
      from classified group by inventory_classification
    ) counts
  ),
  'accounting_classifications', (
    select jsonb_object_agg(accounting_classification, rows)
    from (
      select accounting_classification, count(*) as rows
      from classified group by accounting_classification
    ) counts
  ),
  'critical_rows', (
    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.job_number), '[]'::jsonb)
    from classified row_data
    where row_data.inventory_classification in ('dual_inventory_owner', 'job_original_out_deleted')
       or row_data.accounting_classification in ('dual_revenue_journal', 'duplicate_job_journal')
  ),
  'linked_rows', (
    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.job_number), '[]'::jsonb)
    from classified row_data
    where row_data.invoice_id is not null
  )
) as workshop_invoice_ownership_audit;
