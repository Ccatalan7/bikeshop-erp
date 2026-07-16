begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.inventory_operation_id', '', true);
select set_config('app.inventory_source_document_type', '', true);
select set_config('app.inventory_source_document_id', '', true);
select set_config('app.inventory_source_channel', '', true);
select set_config('app.inventory_trace_context_stack', '[]', true);

select plan(15);

insert into public.tenants (id, shop_name)
values (
  '99719000-0000-4000-8000-000000000001',
  'Mechanic Job Nested Invoice Trace Test'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.customers (id, tenant_id, name)
values (
  '99719000-0000-4000-8000-000000000010',
  '99719000-0000-4000-8000-000000000001',
  'Nested Job Trace Customer'
);

insert into public.bikes (id, tenant_id, customer_id, brand, model)
values (
  '99719000-0000-4000-8000-000000000020',
  '99719000-0000-4000-8000-000000000001',
  '99719000-0000-4000-8000-000000000010',
  'Codex',
  'Nested Trace Bike'
);

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_id,
  customer_name,
  source,
  status,
  subtotal,
  net_amount,
  iva_amount,
  total,
  paid_amount,
  balance,
  tax_treatment,
  items
)
values
  (
    '99719000-0000-4000-8000-000000000030',
    '99719000-0000-4000-8000-000000000001',
    'FV-NESTED-JOB-SERVICE',
    '99719000-0000-4000-8000-000000000010',
    'Nested Job Trace Customer',
    'mechanic_job',
    'draft',
    0, 0, 0, 0, 0, 0,
    'no_tax',
    '[]'::jsonb
  ),
  (
    '99719000-0000-4000-8000-000000000031',
    '99719000-0000-4000-8000-000000000001',
    'FV-NESTED-JOB-COMPONENT',
    '99719000-0000-4000-8000-000000000010',
    'Nested Job Trace Customer',
    'mechanic_job',
    'draft',
    0, 0, 0, 0, 0, 0,
    'no_tax',
    '[]'::jsonb
  ),
  (
    '99719000-0000-4000-8000-000000000032',
    '99719000-0000-4000-8000-000000000001',
    'FV-NESTED-COVERED-NON-LIFECYCLE',
    '99719000-0000-4000-8000-000000000010',
    'Nested Job Trace Customer',
    'mechanic_job',
    'draft',
    0, 0, 0, 0, 0, 0,
    'no_tax',
    '[]'::jsonb
  );

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  bike_id,
  job_number,
  job_type,
  workflow_kind,
  intake_kind,
  mode_needs_review,
  status,
  invoice_id,
  is_invoiced
)
values (
  '99719000-0000-4000-8000-000000000040',
  '99719000-0000-4000-8000-000000000001',
  '99719000-0000-4000-8000-000000000010',
  '99719000-0000-4000-8000-000000000020',
  'NESTED-JOB-SERVICE',
  'service',
  'service',
  'bike',
  false,
  'PENDIENTE',
  '99719000-0000-4000-8000-000000000030',
  true
);

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  bike_id,
  job_number,
  job_type,
  workflow_kind,
  intake_kind,
  mode_needs_review,
  warranty_outcome,
  status,
  invoice_id,
  is_invoiced
)
values (
  '99719000-0000-4000-8000-000000000042',
  '99719000-0000-4000-8000-000000000001',
  '99719000-0000-4000-8000-000000000010',
  '99719000-0000-4000-8000-000000000020',
  'NESTED-COVERED-NON-LIFECYCLE',
  'warranty',
  'warranty',
  'bike',
  false,
  'covered',
  'PENDIENTE',
  '99719000-0000-4000-8000-000000000032',
  true
);

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  job_number,
  job_type,
  workflow_kind,
  intake_kind,
  subject_notes,
  mode_needs_review,
  status,
  invoice_id,
  is_invoiced
)
values (
  '99719000-0000-4000-8000-000000000041',
  '99719000-0000-4000-8000-000000000001',
  '99719000-0000-4000-8000-000000000010',
  'NESTED-JOB-COMPONENT',
  'item_service',
  'service',
  'component',
  'Rueda suelta recibida',
  false,
  'PENDIENTE',
  '99719000-0000-4000-8000-000000000031',
  true
);

create temporary table nested_job_trace_baseline on commit drop as
select id
from public.inventory_accounting_operations
where tenant_id = '99719000-0000-4000-8000-000000000001';

update public.mechanic_jobs
set status = 'ENTREGADO'
where id in (
  '99719000-0000-4000-8000-000000000040',
  '99719000-0000-4000-8000-000000000041'
);

create temporary table nested_job_invoice_operations on commit drop as
select operation.*
from public.inventory_accounting_operations operation
where operation.tenant_id = '99719000-0000-4000-8000-000000000001'
  and operation.document_type = 'sales_invoice'
  and operation.document_id in (
    '99719000-0000-4000-8000-000000000030',
    '99719000-0000-4000-8000-000000000031'
  )
  and not exists (
    select 1
    from nested_job_trace_baseline baseline
    where baseline.id = operation.id
  );

select results_eq(
  $$
    select id, status
    from public.sales_invoices
    where id in (
      '99719000-0000-4000-8000-000000000030',
      '99719000-0000-4000-8000-000000000031'
    )
    order by id
  $$,
  $$
    values
      ('99719000-0000-4000-8000-000000000030'::uuid, 'enviado'::text),
      ('99719000-0000-4000-8000-000000000031'::uuid, 'enviado'::text)
  $$,
  'service and component delivery still synchronize their invoice status'
);

select is(
  (select count(*)::integer from nested_job_invoice_operations),
  2,
  'each job status transition creates exactly one nested invoice trace root'
);

select results_eq(
  $$
    select document_id, source_channel, action
    from nested_job_invoice_operations
    order by document_id
  $$,
  $$
    values
      (
        '99719000-0000-4000-8000-000000000030'::uuid,
        'mechanic_job'::text,
        'update'::text
      ),
      (
        '99719000-0000-4000-8000-000000000031'::uuid,
        'mechanic_job'::text,
        'update'::text
      )
  $$,
  'both roots retain their exact invoice and mechanic-job identities'
);

select is(
  (
    select count(*)::integer
    from nested_job_invoice_operations
    where coalesce((context->>'trigger_depth')::integer, 0) > 1
  ),
  2,
  'both invoice roots are proven nested trigger operations'
);

select is(
  (
    select count(*)::integer
    from nested_job_invoice_operations
    where outcome = 'completed' and completed_at is not null
  ),
  2,
  'service and component nested roots both complete in the same transaction'
);

select is(
  (
    select count(*)::integer
    from nested_job_invoice_operations operation
    where (
      select count(distinct checkpoint.phase)
      from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = operation.id
        and checkpoint.phase in (
          'accepted',
          'source_snapshotted',
          'invariants_verified',
          'completed'
        )
    ) = 4
  ),
  2,
  'each nested root owns a complete canonical checkpoint lifecycle'
);

select is(
  (
    select count(*)::integer
    from nested_job_invoice_operations operation
    where exists (
      select 1
      from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = operation.id
        and checkpoint.phase = 'completed'
        and checkpoint.payload->>'nested_trace_completed_by'
              = 'restore_inventory_accounting_trace_context_frame'
    )
  ),
  2,
  'completion receipts identify the canonical nested-frame owner'
);

select is(
  (
    select count(*)::integer
    from public.stock_movements movement
    where movement.operation_id in (
      select id from nested_job_invoice_operations
    )
  ),
  0,
  'zero-line service/component delivery invents no stock movement'
);

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.operation_id in (
      select id from nested_job_invoice_operations
    )
  ),
  0,
  'zero-line service/component delivery invents no journal posting'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations
    where tenant_id = '99719000-0000-4000-8000-000000000001'
      and outcome = 'started'
  ),
  0,
  'the complete job fixture leaves no latent started trace'
);

select is(
  nullif(current_setting('app.inventory_operation_id', true), ''),
  null::text,
  'the active operation context is empty after both job rows finish'
);

select is(
  coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ),
  '[]'::jsonb,
  'the nested trace context stack is empty after both job rows finish'
);

-- A covered-warranty invoice is deferred only while the exact lifecycle
-- function marker is active. This unrelated nested trigger update deliberately
-- targets an invoice linked to a covered warranty without invoking that job
-- lifecycle; it must therefore complete at frame restoration like any other
-- nested invoice update.
create temporary table unrelated_covered_invoice_update_source (
  id integer primary key,
  invoice_id uuid not null
) on commit drop;

insert into unrelated_covered_invoice_update_source (id, invoice_id)
values (
  1,
  '99719000-0000-4000-8000-000000000032'
);

create function pg_temp.update_covered_invoice_outside_warranty_lifecycle()
returns trigger
language plpgsql
as $$
begin
  update public.sales_invoices
  set status = 'enviado', updated_at = clock_timestamp()
  where id = NEW.invoice_id;
  return NEW;
end;
$$;

create trigger trg_unrelated_covered_invoice_nested_update
after update on unrelated_covered_invoice_update_source
for each row execute function
  pg_temp.update_covered_invoice_outside_warranty_lifecycle();

update unrelated_covered_invoice_update_source
set id = 2
where id = 1;

select is(
  (select status
   from public.sales_invoices
   where id = '99719000-0000-4000-8000-000000000032'),
  'enviado',
  'the unrelated nested update reaches the covered-warranty invoice'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99719000-0000-4000-8000-000000000001'
      and operation.document_type = 'sales_invoice'
      and operation.document_id = '99719000-0000-4000-8000-000000000032'
      and operation.action = 'update'
      and coalesce((operation.context->>'trigger_depth')::integer, 0) > 1
      and operation.outcome = 'completed'
      and exists (
        select 1
        from public.inventory_accounting_checkpoints checkpoint
        where checkpoint.operation_id = operation.id
          and checkpoint.phase = 'completed'
          and checkpoint.payload->>'nested_trace_completed_by'
                = 'restore_inventory_accounting_trace_context_frame'
      )
  ),
  1,
  'covered invoice nesting outside its lifecycle is completed, not deferred'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99719000-0000-4000-8000-000000000001'
      and operation.outcome = 'started'
  ),
  0,
  'even a covered invoice has no latent root outside its exact lifecycle marker'
);

select * from finish();

rollback;
