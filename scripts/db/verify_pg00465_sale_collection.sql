-- Read-only post-deployment verification for
-- 20260716111000_classify_pg00465_sale_collection.sql.
--
-- Run through the guarded helper, which supplies BEGIN READ ONLY / ROLLBACK:
--   scripts/db/query.sh production \
--     --file scripts/db/verify_pg00465_sale_collection.sql
--
-- This query returns no customer identity or free-form notes. Every row must
-- report passed=true.

with target as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    'f9e4ed4e-0ba7-4157-8cba-f8ce8432877e'::uuid as job_id,
    'fee00ca7-f710-451d-9744-23c3661ddc14'::uuid as invoice_id,
    '00465000-0000-4000-8000-000000000111'::uuid as classified_event_id,
    'sale-classification-repair:pg00465:v1'::text as operation_key,
    'Clasificación histórica confirmada: venta en cuotas sin bicicleta ni componente recibido.'::text as reason,
    jsonb_build_object(
      'classification_source', 'manual-sale-confirmation-v1',
      'financial_effects_created', false,
      'invoice_preserved', true,
      'historical_review_event_id',
        '5c75d643-eeac-4850-927d-e8f84cd7e487'::uuid,
      'repair_migration',
        '20260716111000_classify_pg00465_sale_collection'
    ) as event_metadata
),
target_job as (
  select job.*
  from public.mechanic_jobs job
  join target on target.job_id = job.id and target.tenant_id = job.tenant_id
),
target_invoice as (
  select invoice.*
  from public.sales_invoices invoice
  join target
    on target.invoice_id = invoice.id
   and target.tenant_id = invoice.tenant_id
  join target_job job on job.invoice_id = invoice.id
),
target_payments as (
  select payment.*
  from public.sales_payments payment
  join target_invoice invoice on invoice.id = payment.invoice_id
  where payment.tenant_id = invoice.tenant_id
),
target_product_ids as (
  select distinct coalesce(item.product_id, item.service_product_id) as id
  from public.mechanic_job_items item
  join target_job job on job.id = item.job_id
  where item.tenant_id = job.tenant_id
    and coalesce(item.product_id, item.service_product_id) is not null

  union

  select distinct nullif(line.value->>'product_id', '')::uuid
  from target_invoice invoice
  cross join lateral jsonb_array_elements(
    coalesce(invoice.items, '[]'::jsonb)
  ) line(value)
  where nullif(line.value->>'product_id', '') is not null
),
target_movements as (
  select movement.*
  from public.stock_movements movement
  join target_invoice invoice on movement.tenant_id = invoice.tenant_id
  where movement.source_document_id = invoice.id
     or movement.reference = 'sales_invoice:' || invoice.id::text
     or (
       movement.reference_type = 'sales_invoice'
       and movement.reference_id = invoice.id::text
     )
),
target_journals as (
  select entry.*
  from public.journal_entries entry
  join target_invoice invoice on entry.tenant_id = invoice.tenant_id
  where (
    entry.source_module = 'sales_invoices'
    and (
      entry.source_document_id = invoice.id
      or entry.source_reference = invoice.invoice_number
    )
  ) or (
    entry.source_module = 'sales_payments'
    and exists (
      select 1
      from target_payments payment
      where entry.source_document_id = payment.id
         or entry.source_reference = payment.id::text
    )
  )
),
target_operations as (
  select operation.*
  from public.inventory_accounting_operations operation
  join target_invoice invoice on operation.tenant_id = invoice.tenant_id
  where operation.document_id = invoice.id
     or operation.document_id in (select payment.id from target_payments payment)
     or operation.id in (
       select movement.operation_id
       from target_movements movement
       where movement.operation_id is not null
     )
     or operation.id in (
       select entry.operation_id
       from target_journals entry
       where entry.operation_id is not null
     )
),
components(component, expected_count, expected_sha256) as (
  values
    ('tenant'::text, 1::bigint,
      'ba94e58e4f9c1b7973223a0104ed8c744b7e4db0e9d01b1ad6224ab77b50a1a3'::text),
    ('job_preserved', 1,
      'd011c697457364dca7de712ad3c913fb78d6683a34a10b2539656d6f62aa115e'),
    ('job_items', 1,
      'f56053d6703dd6fa7cba3ed0edf7e03879a05f480287c1383097300ad6bcb1b7'),
    ('job_bikes', 0,
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    ('invoice', 1,
      '61adf6abc607615702e26361512407cc0c73897dbdb804b81825fcdd146b3806'),
    ('payments', 1,
      '68d2f5e305d7b9a70edce1f4505abad685b40afbe48b64d041d2721e346781e7'),
    ('payment_receipts', 0,
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    ('products', 1,
      'ecb0b3d4acf2c15703e26f355b1b65447c889f8eb966fd19e6a6b77b9d1991d5'),
    ('stock_movements', 1,
      '8b9b71474dbcb017a6d32bf7dd718f3640fe5d345153c6b351c96af7a462b0bd'),
    ('journals', 2,
      '9207b977056c10c8387894219efb8fc0a757bc14fc499faa8c58dc6b4b7453b1'),
    ('journal_lines', 4,
      '11429ffe24b92dfad0aa5e6673fdf6546ed5e4921b91319f9ff244d09c1e670f'),
    ('inventory_operations', 5,
      'a7529dacf6dde97b81579777584846925dfba421e2cd4de2d74134e0700c61ca'),
    ('inventory_checkpoints', 30,
      '7e25585d8d04b5b6e4f8ff6c18791471d2285f9ef33e2c8ae19926131ccb0b78'),
    ('review_event', 1,
      'c959b08e788691116cdf34d475577b52b4d4a697e55db9b78be0693c47a4abd3')
),
fingerprint_rows(component, sort_key, payload) as (
  select 'tenant', tenant.id::text, to_jsonb(tenant)
  from public.tenants tenant
  join target on target.tenant_id = tenant.id

  union all

  select
    'job_preserved',
    job.id::text,
    to_jsonb(job) - array[
      'workflow_kind',
      'intake_kind',
      'mode_needs_review',
      'mode_review_reason',
      'updated_at'
    ]::text[]
  from target_job job

  union all

  select 'job_items', item.id::text, to_jsonb(item)
  from public.mechanic_job_items item
  join target_job job on job.id = item.job_id
  where item.tenant_id = job.tenant_id

  union all

  select 'job_bikes', job_bike.id::text, to_jsonb(job_bike)
  from public.mechanic_job_bikes job_bike
  join target_job job on job.id = job_bike.job_id
  where job_bike.tenant_id = job.tenant_id

  union all

  select 'invoice', invoice.id::text, to_jsonb(invoice)
  from target_invoice invoice

  union all

  select 'payments', payment.id::text, to_jsonb(payment)
  from target_payments payment

  union all

  select 'payment_receipts', receipt.id::text, to_jsonb(receipt)
  from public.sales_payment_command_receipts receipt
  join target_invoice invoice on invoice.id = receipt.invoice_id
  where receipt.tenant_id = invoice.tenant_id

  union all

  select 'products', product.id::text, to_jsonb(product)
  from public.products product
  join target_product_ids target_product on target_product.id = product.id

  union all

  select 'stock_movements', movement.id::text, to_jsonb(movement)
  from target_movements movement

  union all

  select 'journals', entry.id::text, to_jsonb(entry)
  from target_journals entry

  union all

  select 'journal_lines', line.id::text, to_jsonb(line)
  from public.journal_lines line
  join target_journals entry
    on entry.id = line.entry_id
   and entry.tenant_id = line.tenant_id

  union all

  select 'inventory_operations', operation.id::text, to_jsonb(operation)
  from target_operations operation

  union all

  select 'inventory_checkpoints', checkpoint.id::text, to_jsonb(checkpoint)
  from public.inventory_accounting_checkpoints checkpoint
  join target_operations operation
    on operation.id = checkpoint.operation_id
   and operation.tenant_id = checkpoint.tenant_id

  union all

  select 'review_event', event.id::text, to_jsonb(event)
  from public.mechanic_job_mode_events event
  join target
    on target.job_id = event.job_id
   and target.tenant_id = event.tenant_id
  where event.operation_key =
    'mode-backfill:review:f9e4ed4e-0ba7-4157-8cba-f8ce8432877e'
),
actual_fingerprints as (
  select
    row.component,
    count(*)::bigint as row_count,
    encode(
      extensions.digest(
        coalesce(
          string_agg(row.payload::text, '|' order by row.sort_key),
          ''
        ),
        'sha256'
      ),
      'hex'
    ) as sha256
  from fingerprint_rows row
  group by row.component
),
fingerprint_checks as (
  select
    'fingerprint_' || component.component as check_name,
    component.expected_count::text || ':' || component.expected_sha256 as expected,
    coalesce(actual.row_count, 0)::text || ':' || coalesce(
      actual.sha256,
      encode(extensions.digest('', 'sha256'), 'hex')
    ) as actual,
    coalesce(actual.row_count, 0) = component.expected_count
      and coalesce(
        actual.sha256,
        encode(extensions.digest('', 'sha256'), 'hex')
      ) = component.expected_sha256 as passed
  from components component
  left join actual_fingerprints actual using (component)
),
business_checks(check_name, expected, actual, passed) as (
  select
    'job_final_mode',
    '1',
    count(*)::text,
    count(*) = 1
  from target_job job
  join target on true
  where job.job_number = 'PG-00465'
    and job.job_type = 'service'
    and job.workflow_kind = 'sale'
    and job.intake_kind = 'none'
    and not job.mode_needs_review
    and job.mode_review_reason is null
    and job.bike_id is null
    and job.subject_id is null
    and job.invoice_id = target.invoice_id

  union all

  select
    'classification_event_exact',
    '1',
    count(*)::text,
    count(*) = 1
  from public.mechanic_job_mode_events event
  join target
    on target.classified_event_id = event.id
   and target.tenant_id = event.tenant_id
   and target.job_id = event.job_id
  where event.event_type = 'classified'
    and event.from_job_type = 'service'
    and event.to_job_type = 'service'
    and event.from_workflow_kind = 'service'
    and event.to_workflow_kind = 'sale'
    and event.from_intake_kind = 'unspecified'
    and event.to_intake_kind = 'none'
    and event.invoice_id = target.invoice_id
    and event.reason = target.reason
    and event.actor_id is null
    and event.operation_key = target.operation_key
    and event.metadata = target.event_metadata

  union all

  select
    'mode_event_count',
    '2',
    count(*)::text,
    count(*) = 2
  from public.mechanic_job_mode_events event
  join target
    on target.tenant_id = event.tenant_id
   and target.job_id = event.job_id

  union all

  select
    'invoice_payment_math',
    '40000:10000:30000:confirmed:no_tax',
    concat_ws(
      ':',
      invoice.total,
      invoice.paid_amount,
      invoice.balance,
      invoice.status,
      invoice.tax_treatment
    ),
    invoice.total = 40000
      and invoice.paid_amount = 10000
      and invoice.balance = 30000
      and invoice.status = 'confirmed'
      and invoice.tax_treatment = 'no_tax'
      and invoice.total = invoice.paid_amount + invoice.balance
  from target_invoice invoice

  union all

  select
    'active_installment_ledger',
    '1:10000',
    count(*)::text || ':' || coalesce(sum(payment.amount), 0)::text,
    count(*) = 1 and coalesce(sum(payment.amount), 0) = 10000
  from target_payments payment
  where payment.deleted_at is null

  union all

  select
    'delivered_unpaid_remains_active',
    'true',
    coalesce(bool_and(
      job.status = 'ENTREGADO'
      and job.delivered_at is not null
      and not job.is_paid
      and invoice.balance > 0
    ), false)::text,
    coalesce(bool_and(
      job.status = 'ENTREGADO'
      and job.delivered_at is not null
      and not job.is_paid
      and invoice.balance > 0
    ), false)
  from target_job job
  join target_invoice invoice on invoice.id = job.invoice_id

  union all

  select
    'invoice_owns_stock_job_owns_none',
    '1:0',
    (select count(*) from target_movements)::text || ':' ||
      (
        select count(*)
        from public.stock_movements movement
        join target on target.tenant_id = movement.tenant_id
        where movement.reference in (
          'mechanic_job:' || target.job_id::text,
          'mechanic_job:' || target.job_id::text || ':reversed'
        )
      )::text,
    (select count(*) from target_movements) = 1
      and not exists (
        select 1
        from public.stock_movements movement
        join target on target.tenant_id = movement.tenant_id
        where movement.reference in (
          'mechanic_job:' || target.job_id::text,
          'mechanic_job:' || target.job_id::text || ':reversed'
        )
      )

  union all

  select
    'journals_balanced_and_uuid_owned',
    '2',
    count(*) filter (
      where entry.total_debit = entry.total_credit
        and entry.source_document_id is not null
        and lines.debit = entry.total_debit
        and lines.credit = entry.total_credit
    )::text,
    count(*) = 2
      and count(*) filter (
        where entry.total_debit = entry.total_credit
          and entry.source_document_id is not null
          and lines.debit = entry.total_debit
          and lines.credit = entry.total_credit
      ) = 2
  from target_journals entry
  join lateral (
    select
      coalesce(sum(line.debit_amount), 0) as debit,
      coalesce(sum(line.credit_amount), 0) as credit
    from public.journal_lines line
    where line.entry_id = entry.id
      and line.tenant_id = entry.tenant_id
  ) lines on true

  union all

  select
    'payment_created_zero_stock',
    '0',
    count(*)::text,
    count(*) = 0
  from public.stock_movements movement
  join target_payments payment on movement.operation_id = (
    select operation.id
    from public.inventory_accounting_operations operation
    where operation.tenant_id = payment.tenant_id
      and operation.document_type = 'sales_payment'
      and operation.document_id = payment.id
    order by operation.started_at desc, operation.id desc
    limit 1
  )
)
select check_name, expected, actual, passed
from business_checks

union all

select check_name, expected, actual, passed
from fingerprint_checks
order by check_name;
