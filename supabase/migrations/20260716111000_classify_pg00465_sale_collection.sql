-- Deployment status: PENDING.
--
-- Purpose:
--   Apply the one explicitly confirmed historical classification for
--   PG-00465: a delivered product sale collected in installments, with no
--   bicycle or loose component received by the workshop.
--
-- Safety:
--   This is an identity-bound, one-row repair. It locks FV-00882 before the
--   job, accepts only the exact reviewed production snapshot, changes only
--   workflow_kind/intake_kind/mode_needs_review/mode_review_reason, preserves
--   the original review event, and appends one deterministic classification
--   event. Invoice, payment, item, product, stock, journal, trace, and all
--   non-mode job fields must have identical row counts and SHA-256 hashes
--   before and after the update or the transaction aborts.
--
-- Recovery:
--   Do not delete the append-only classification event or rewrite the
--   financial history. An older client may be rolled back while the canonical
--   sale/none classification remains. Any later business correction requires
--   a separately audited forward event.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- A temporary read model lets the DO block capture the exact same graph before
-- and after the only authorized row update. It leaves no persistent object.
create or replace temporary view pg00465_sale_collection_current_fingerprint as
with target_job as (
  select job.*
  from public.mechanic_jobs job
  where job.id = 'f9e4ed4e-0ba7-4157-8cba-f8ce8432877e'::uuid
    and job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
),
target_invoice as (
  select invoice.*
  from public.sales_invoices invoice
  join target_job job on job.invoice_id = invoice.id
  where invoice.tenant_id = job.tenant_id
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
components(component) as (
  values
    ('tenant'::text),
    ('job_preserved'),
    ('job_items'),
    ('job_bikes'),
    ('invoice'),
    ('payments'),
    ('payment_receipts'),
    ('products'),
    ('stock_movements'),
    ('journals'),
    ('journal_lines'),
    ('inventory_operations'),
    ('inventory_checkpoints'),
    ('review_event')
),
fingerprint_rows(component, sort_key, payload) as (
  select
    'tenant',
    tenant.id::text,
    to_jsonb(tenant)
  from public.tenants tenant
  where tenant.id = '5443b130-cc28-45af-a420-cd500b288890'::uuid

  union all

  -- updated_at is maintained by the generic timestamp trigger. The four mode
  -- columns are the intended repair. Every other job field must be identical.
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
  join target_product_ids target on target.id = product.id

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
  join target_job job
    on job.id = event.job_id
   and job.tenant_id = event.tenant_id
  where event.operation_key =
    'mode-backfill:review:f9e4ed4e-0ba7-4157-8cba-f8ce8432877e'
),
fingerprints as (
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
)
select
  component.component,
  coalesce(fingerprint.row_count, 0)::bigint as row_count,
  coalesce(
    fingerprint.sha256,
    encode(extensions.digest('', 'sha256'), 'hex')
  ) as sha256
from components component
left join fingerprints fingerprint using (component);

do $repair$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_job_id constant uuid := 'f9e4ed4e-0ba7-4157-8cba-f8ce8432877e';
  v_invoice_id constant uuid := 'fee00ca7-f710-451d-9744-23c3661ddc14';
  v_job_item_id constant uuid := 'abcf3c92-7f44-40a4-8aea-aadac99717af';
  v_product_id constant uuid := 'fc082196-ffcc-4000-b112-fae51a3e26e7';
  v_payment_id constant uuid := 'bec94995-be52-43cb-8ac7-33e9449f1f05';
  v_movement_id constant uuid := 'de0702fd-d107-45b4-8f68-93f823f986cb';
  v_invoice_journal_id constant uuid := '2e994c49-9dca-479e-9b8c-91c1c759350f';
  v_payment_journal_id constant uuid := '39f29e91-022b-4707-97a2-59237d2c0f6c';
  v_review_event_id constant uuid := '5c75d643-eeac-4850-927d-e8f84cd7e487';
  v_classified_event_id constant uuid := '00465000-0000-4000-8000-000000000111';
  v_operation_key constant text := 'sale-classification-repair:pg00465:v1';
  v_reason constant text :=
    'Clasificación histórica confirmada: venta en cuotas sin bicicleta ni componente recibido.';
  v_metadata constant jsonb := jsonb_build_object(
    'classification_source', 'manual-sale-confirmation-v1',
    'financial_effects_created', false,
    'invoice_preserved', true,
    'historical_review_event_id', v_review_event_id,
    'repair_migration', '20260716111000_classify_pg00465_sale_collection'
  );
  v_expected_fingerprint constant jsonb :=
    '{
      "tenant":{"row_count":1,"sha256":"ba94e58e4f9c1b7973223a0104ed8c744b7e4db0e9d01b1ad6224ab77b50a1a3"},
      "job_preserved":{"row_count":1,"sha256":"d011c697457364dca7de712ad3c913fb78d6683a34a10b2539656d6f62aa115e"},
      "job_items":{"row_count":1,"sha256":"f56053d6703dd6fa7cba3ed0edf7e03879a05f480287c1383097300ad6bcb1b7"},
      "job_bikes":{"row_count":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
      "invoice":{"row_count":1,"sha256":"61adf6abc607615702e26361512407cc0c73897dbdb804b81825fcdd146b3806"},
      "payments":{"row_count":1,"sha256":"68d2f5e305d7b9a70edce1f4505abad685b40afbe48b64d041d2721e346781e7"},
      "payment_receipts":{"row_count":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
      "products":{"row_count":1,"sha256":"ecb0b3d4acf2c15703e26f355b1b65447c889f8eb966fd19e6a6b77b9d1991d5"},
      "stock_movements":{"row_count":1,"sha256":"8b9b71474dbcb017a6d32bf7dd718f3640fe5d345153c6b351c96af7a462b0bd"},
      "journals":{"row_count":2,"sha256":"9207b977056c10c8387894219efb8fc0a757bc14fc499faa8c58dc6b4b7453b1"},
      "journal_lines":{"row_count":4,"sha256":"11429ffe24b92dfad0aa5e6673fdf6546ed5e4921b91319f9ff244d09c1e670f"},
      "inventory_operations":{"row_count":5,"sha256":"a7529dacf6dde97b81579777584846925dfba421e2cd4de2d74134e0700c61ca"},
      "inventory_checkpoints":{"row_count":30,"sha256":"7e25585d8d04b5b6e4f8ff6c18791471d2285f9ef33e2c8ae19926131ccb0b78"},
      "review_event":{"row_count":1,"sha256":"c959b08e788691116cdf34d475577b52b4d4a697e55db9b78be0693c47a4abd3"}
    }'::jsonb;
  v_expected_source_job_sha constant text :=
    '589d4fafeb7eda110374e01219a0f8c014c331212d7d4c4427bc3631533eccb2';
  v_invoice public.sales_invoices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_source_job_sha text;
  v_source_state boolean;
  v_final_state boolean;
  v_mode_event_count_before integer;
  v_rows integer;
begin
  -- Canonical lock order: invoice first, then linked job. Payment creation and
  -- invoice posting must wait until the metadata-only repair commits.
  select * into v_invoice
  from public.sales_invoices invoice
  where invoice.id = v_invoice_id
  for update;

  if not found then
    if exists (
      select 1 from public.mechanic_jobs job where job.id = v_job_id
    ) then
      raise exception 'PG-00465 repair found the job ID without its exact invoice ID.'
        using errcode = '23514';
    end if;
    -- Clean/local data replicas legitimately contain no production row.
    return;
  end if;

  if v_invoice.tenant_id is distinct from v_tenant_id then
    raise exception 'PG-00465 invoice ID belongs to an unexpected tenant.'
      using errcode = '23514';
  end if;

  select * into v_job
  from public.mechanic_jobs job
  where job.id = v_job_id
  for update;

  if not found
     or v_job.tenant_id is distinct from v_tenant_id
     or v_job.job_number is distinct from 'PG-00465'
     or v_job.invoice_id is distinct from v_invoice_id then
    raise exception 'PG-00465 job/invoice identity no longer matches the reviewed pair.'
      using errcode = '23514';
  end if;

  -- Freeze every existing child row after the invoice/job pair. The invoice
  -- lock already serializes payment commands; these locks also make the
  -- before/after evidence explicit for administrative execution.
  perform 1
  from public.mechanic_job_items item
  where item.job_id = v_job_id and item.tenant_id = v_tenant_id
  order by item.id
  for update;

  perform 1
  from public.sales_payments payment
  where payment.invoice_id = v_invoice_id and payment.tenant_id = v_tenant_id
  order by payment.id
  for update;

  perform 1
  from public.products product
  where product.id = v_product_id and product.tenant_id = v_tenant_id
  for update;

  perform 1
  from public.stock_movements movement
  where movement.tenant_id = v_tenant_id
    and (
      movement.source_document_id = v_invoice_id
      or movement.reference = 'sales_invoice:' || v_invoice_id::text
    )
  order by movement.id
  for update;

  perform 1
  from public.journal_entries entry
  where entry.tenant_id = v_tenant_id
    and entry.id in (v_invoice_journal_id, v_payment_journal_id)
  order by entry.id
  for update;

  perform 1
  from public.journal_lines line
  where line.tenant_id = v_tenant_id
    and line.entry_id in (v_invoice_journal_id, v_payment_journal_id)
  order by line.id
  for update;

  perform 1
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_tenant_id
    and event.job_id = v_job_id
  order by event.id
  for update;

  v_source_state :=
    v_job.job_type = 'service'
    and v_job.workflow_kind = 'service'
    and v_job.intake_kind = 'unspecified'
    and v_job.mode_needs_review
    and v_job.mode_review_reason =
      'backfill: servicio sin bicicleta o componente verificable'
    and v_job.bike_id is null
    and v_job.subject_id is null;

  v_final_state :=
    v_job.job_type = 'service'
    and v_job.workflow_kind = 'sale'
    and v_job.intake_kind = 'none'
    and not v_job.mode_needs_review
    and v_job.mode_review_reason is null
    and v_job.bike_id is null
    and v_job.subject_id is null;

  if v_final_state then
    if exists (
      select 1
      from public.mechanic_job_bikes job_bike
      where job_bike.tenant_id = v_tenant_id
        and job_bike.job_id = v_job_id
    ) or not exists (
      select 1
      from public.mechanic_job_mode_events event
      where event.id = v_classified_event_id
        and event.tenant_id = v_tenant_id
        and event.job_id = v_job_id
        and event.event_type = 'classified'
        and event.from_job_type = 'service'
        and event.to_job_type = 'service'
        and event.from_workflow_kind = 'service'
        and event.to_workflow_kind = 'sale'
        and event.from_intake_kind = 'unspecified'
        and event.to_intake_kind = 'none'
        and event.invoice_id = v_invoice_id
        and event.reason = v_reason
        and event.actor_id is null
        and event.operation_key = v_operation_key
        and event.metadata = v_metadata
    ) then
      raise exception 'PG-00465 has final mode fields without the exact audited final graph.'
        using errcode = '23514';
    end if;
    -- Idempotent replay after a successful repair. Future installment payments
    -- do not invalidate the already-completed classification.
    return;
  end if;

  if not v_source_state then
    raise exception 'PG-00465 is present but its source/final classification does not match this repair.'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.mechanic_job_mode_events event
    where event.id = v_classified_event_id
       or (event.tenant_id = v_tenant_id and event.operation_key = v_operation_key)
  ) then
    raise exception 'PG-00465 target classification event identity is already occupied.'
      using errcode = '23505';
  end if;

  select encode(extensions.digest(to_jsonb(v_job)::text, 'sha256'), 'hex')
  into v_source_job_sha;
  if v_source_job_sha is distinct from v_expected_source_job_sha then
    raise exception 'PG-00465 source job fingerprint changed: %', v_source_job_sha
      using errcode = '23514';
  end if;

  select jsonb_object_agg(
    fingerprint.component,
    jsonb_build_object(
      'row_count', fingerprint.row_count,
      'sha256', fingerprint.sha256
    )
  )
  into v_before
  from pg_temp.pg00465_sale_collection_current_fingerprint fingerprint;

  if v_before is distinct from v_expected_fingerprint then
    raise exception 'PG-00465 reviewed graph fingerprint changed. Actual: %', v_before
      using errcode = '23514';
  end if;

  -- Human-readable invariants complement the non-reversible row hashes.
  if v_invoice.invoice_number is distinct from 'FV-00882'
     or v_invoice.status is distinct from 'confirmed'
     or v_invoice.source is distinct from 'mechanic_job'
     or v_invoice.tax_treatment is distinct from 'no_tax'
     or v_invoice.total is distinct from 40000::numeric
     or v_invoice.paid_amount is distinct from 10000::numeric
     or v_invoice.balance is distinct from 30000::numeric
     or v_invoice.credited_amount is distinct from 0::numeric
     or v_invoice.refunded_amount is distinct from 0::numeric
     or v_invoice.customer_credit_balance is distinct from 0::numeric then
    raise exception 'FV-00882 financial summary changed; refusing classification.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.mechanic_job_items item
    where item.id = v_job_item_id
      and item.job_id = v_job_id
      and item.tenant_id = v_tenant_id
      and item.item_type = 'product'
      and item.product_id = v_product_id
      and item.job_bike_id is null
      and item.quantity = 1
      and item.unit_price = 40000
      and item.total_price = 40000
  ) or exists (
    select 1
    from public.mechanic_job_bikes job_bike
    where job_bike.job_id = v_job_id
      and job_bike.tenant_id = v_tenant_id
  ) then
    raise exception 'PG-00465 product/no-object evidence changed; refusing classification.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.sales_payments payment
    where payment.id = v_payment_id
      and payment.invoice_id = v_invoice_id
      and payment.tenant_id = v_tenant_id
      and payment.deleted_at is null
      and payment.amount = 10000
  ) or not exists (
    select 1
    from public.stock_movements movement
    where movement.id = v_movement_id
      and movement.tenant_id = v_tenant_id
      and movement.product_id = v_product_id
      and movement.source_document_type = 'sales_invoice'
      and movement.source_document_id = v_invoice_id
      and movement.type = 'OUT'
      and movement.quantity = -1
      and movement.stock_before = 1
      and movement.stock_after = 0
  ) or not exists (
    select 1
    from public.products product
    where product.id = v_product_id
      and product.tenant_id = v_tenant_id
      and product.track_stock
      and not coalesce(product.is_service, false)
      and product.inventory_qty = 0
      and product.stock_quantity = 0
  ) then
    raise exception 'PG-00465 payment or inventory evidence changed; refusing classification.'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.journal_entries entry
    where entry.id = v_invoice_journal_id
      and entry.tenant_id = v_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_document_id = v_invoice_id
      and entry.total_debit = 40000
      and entry.total_credit = 40000
  ) or not exists (
    select 1
    from public.journal_entries entry
    where entry.id = v_payment_journal_id
      and entry.tenant_id = v_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_document_id = v_payment_id
      and entry.total_debit = 10000
      and entry.total_credit = 10000
  ) or exists (
    select 1
    from public.stock_movements movement
    where movement.tenant_id = v_tenant_id
      and movement.reference in (
        'mechanic_job:' || v_job_id::text,
        'mechanic_job:' || v_job_id::text || ':reversed'
      )
  ) or exists (
    select 1
    from public.journal_entries entry
    where entry.tenant_id = v_tenant_id
      and entry.source_module = 'mechanic_jobs'
      and entry.source_reference in (v_job_id::text, 'PG-00465')
  ) then
    raise exception 'PG-00465 accounting ownership evidence changed; refusing classification.'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into v_mode_event_count_before
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_tenant_id
    and event.job_id = v_job_id;

  if v_mode_event_count_before <> 1
     or not exists (
       select 1
       from public.mechanic_job_mode_events event
       where event.id = v_review_event_id
         and event.tenant_id = v_tenant_id
         and event.job_id = v_job_id
         and event.event_type = 'review_flagged'
         and event.operation_key =
           'mode-backfill:review:f9e4ed4e-0ba7-4157-8cba-f8ce8432877e'
     ) then
    raise exception 'PG-00465 prior review evidence changed; refusing classification.'
      using errcode = '23514';
  end if;

  -- 20260716110000 authorizes exactly this paid historical transition. The
  -- generic mode flag suppresses the compatibility audit trigger so only the
  -- deterministic event below is appended.
  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  perform set_config('app.mechanic_job_sale_classification_rpc', 'true', true);

  update public.mechanic_jobs job
  set workflow_kind = 'sale',
      intake_kind = 'none',
      mode_needs_review = false,
      mode_review_reason = null
  where job.id = v_job_id
    and job.tenant_id = v_tenant_id
    and job.job_type = 'service'
    and job.workflow_kind = 'service'
    and job.intake_kind = 'unspecified'
    and job.mode_needs_review
    and job.mode_review_reason =
      'backfill: servicio sin bicicleta o componente verificable';

  get diagnostics v_rows = row_count;
  perform set_config('app.mechanic_job_sale_classification_rpc', '', true);
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  if v_rows <> 1 then
    raise exception 'PG-00465 repair updated % rows instead of exactly one.', v_rows
      using errcode = '23514';
  end if;

  insert into public.mechanic_job_mode_events (
    id,
    tenant_id,
    job_id,
    event_type,
    from_job_type,
    to_job_type,
    from_workflow_kind,
    to_workflow_kind,
    from_intake_kind,
    to_intake_kind,
    from_quotation_status,
    to_quotation_status,
    invoice_id,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_classified_event_id,
    v_tenant_id,
    v_job_id,
    'classified',
    'service',
    'service',
    'service',
    'sale',
    'unspecified',
    'none',
    v_job.quotation_status,
    v_job.quotation_status,
    v_invoice_id,
    v_reason,
    null,
    v_operation_key,
    v_metadata
  );

  select jsonb_object_agg(
    fingerprint.component,
    jsonb_build_object(
      'row_count', fingerprint.row_count,
      'sha256', fingerprint.sha256
    )
  )
  into v_after
  from pg_temp.pg00465_sale_collection_current_fingerprint fingerprint;

  if v_after is distinct from v_before then
    raise exception 'PG-00465 repair changed protected financial/inventory rows. Before %, after %',
      v_before, v_after
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.mechanic_jobs job
    where job.id = v_job_id
      and job.tenant_id = v_tenant_id
      and job.job_type = 'service'
      and job.workflow_kind = 'sale'
      and job.intake_kind = 'none'
      and not job.mode_needs_review
      and job.mode_review_reason is null
      and job.bike_id is null
      and job.subject_id is null
      and job.invoice_id = v_invoice_id
  ) or (
    select count(*)
    from public.mechanic_job_mode_events event
    where event.tenant_id = v_tenant_id
      and event.job_id = v_job_id
  ) <> v_mode_event_count_before + 1 or not exists (
    select 1
    from public.mechanic_job_mode_events event
    where event.id = v_classified_event_id
      and event.tenant_id = v_tenant_id
      and event.job_id = v_job_id
      and event.event_type = 'classified'
      and event.from_job_type = 'service'
      and event.to_job_type = 'service'
      and event.from_workflow_kind = 'service'
      and event.to_workflow_kind = 'sale'
      and event.from_intake_kind = 'unspecified'
      and event.to_intake_kind = 'none'
      and event.invoice_id = v_invoice_id
      and event.reason = v_reason
      and event.actor_id is null
      and event.operation_key = v_operation_key
      and event.metadata = v_metadata
  ) then
    raise exception 'PG-00465 final classification/event invariant failed.'
      using errcode = '23514';
  end if;
end;
$repair$;

drop view pg_temp.pg00465_sale_collection_current_fingerprint;

commit;
