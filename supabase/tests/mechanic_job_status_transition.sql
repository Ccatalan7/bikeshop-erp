begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(22);

select has_table(
  'public', 'mechanic_job_status_transition_events',
  'status transitions have a dedicated receipt ledger'
);
select has_trigger(
  'public', 'mechanic_job_status_transition_events',
  'trg_mechanic_job_status_transition_events_immutable',
  'status receipts are append-only'
);
select has_function(
  'public', 'transition_mechanic_job_status',
  array['uuid', 'uuid', 'text'],
  'jobs expose one canonical status transition command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.transition_mechanic_job_status(uuid,uuid,text)',
    'execute'
  ),
  'authenticated workers can transition job status'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.transition_mechanic_job_status(uuid,uuid,text)',
    'execute'
  ),
  'anonymous callers cannot transition job status'
);
select ok(
  position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
    )
  ) < position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
    )
  ),
  'the command locks invoice before job'
);
select ok(
  position('paid_amount' in pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
  )) > 0
  and position('from public.sales_payments payment' in pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure
  )) > 0,
  'covered-warranty guard checks invoice mirrors and active payment rows'
);

insert into public.tenants(id, shop_name) values
  ('99616800-0000-4000-8000-000000000001', 'Status Tenant A'),
  ('99616800-0000-4000-8000-000000000002', 'Status Tenant B');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99616800-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'status-command@example.invalid', '',
  now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99616800-0000-4000-8000-000000000001'
  ),
  now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role) values (
  '99616800-0000-4000-8000-000000000099',
  '99616800-0000-4000-8000-000000000001',
  'admin'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616800-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616800-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values
  ('99616800-0000-4000-8000-000000000011', '99616800-0000-4000-8000-000000000001', 'Status Customer A'),
  ('99616800-0000-4000-8000-000000000021', '99616800-0000-4000-8000-000000000002', 'Status Customer B');

insert into public.job_statuses(
  id, tenant_id, name, code, color, phase, sort_order,
  triggers_completion, triggers_delivery
) values
  ('99616800-0000-4000-8000-000000000031', '99616800-0000-4000-8000-000000000001', 'QA Pendiente', 'QA_PENDING', '#64748B', 'todo', 90, false, false),
  ('99616800-0000-4000-8000-000000000032', '99616800-0000-4000-8000-000000000001', 'QA Terminado', 'QA_DONE', '#059669', 'complete', 91, true, false),
  ('99616800-0000-4000-8000-000000000033', '99616800-0000-4000-8000-000000000001', 'Listo retiro', 'READY_FOR_PICKUP', '#0891B2', 'complete', 92, true, true),
  ('99616800-0000-4000-8000-000000000034', '99616800-0000-4000-8000-000000000002', 'Estado ajeno', 'FOREIGN', '#DC2626', 'todo', 90, false, false);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, status,
  subtotal, net_amount, total, paid_amount, balance, items
) values
  ('99616800-0000-4000-8000-000000000041', '99616800-0000-4000-8000-000000000001', 'STATUS-WARRANTY', '99616800-0000-4000-8000-000000000011', 'draft', 100, 100, 100, 0, 100, '[]'::jsonb),
  ('99616800-0000-4000-8000-000000000042', '99616800-0000-4000-8000-000000000001', 'STATUS-SERVICE', '99616800-0000-4000-8000-000000000011', 'draft', 100, 100, 100, 0, 100, '[]'::jsonb);

-- Create real settlement evidence before linking the invoices to jobs. The
-- payment guard correctly allows an unlinked invoice and the later job insert
-- exercises the paid-invoice no-op compatibility path.
insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  fixture.payment_id,
  invoice.tenant_id,
  invoice.id,
  payment_method.id,
  10,
  'no_tax',
  10,
  0,
  fixture.operation_key,
  fixture.operation_key,
  now()
from (
  values
    ('99616800-0000-4000-8000-000000000041'::uuid, '99616800-0000-4000-8000-000000000061'::uuid, 'status-warranty-payment'),
    ('99616800-0000-4000-8000-000000000042'::uuid, '99616800-0000-4000-8000-000000000062'::uuid, 'status-service-payment')
) fixture(invoice_id, payment_id, operation_key)
join public.sales_invoices invoice on invoice.id = fixture.invoice_id
cross join lateral (
  select method.id
  from public.payment_methods method
  where method.tenant_id = invoice.tenant_id
  order by method.created_at, method.id
  limit 1
) payment_method;

select set_config('app.warranty_claim_rpc', 'true', true);
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, status_id, warranty_outcome, is_warranty_job,
  invoice_id, is_invoiced
) values
  ('99616800-0000-4000-8000-000000000051', '99616800-0000-4000-8000-000000000001', '99616800-0000-4000-8000-000000000011', 'STATUS-WARRANTY-JOB', 'warranty', 'warranty', 'component', 'QA_PENDING', '99616800-0000-4000-8000-000000000031', 'covered', true, '99616800-0000-4000-8000-000000000041', true),
  ('99616800-0000-4000-8000-000000000052', '99616800-0000-4000-8000-000000000001', '99616800-0000-4000-8000-000000000011', 'STATUS-SERVICE-JOB', 'item_service', 'service', 'component', 'QA_PENDING', '99616800-0000-4000-8000-000000000031', null, false, '99616800-0000-4000-8000-000000000042', true),
  ('99616800-0000-4000-8000-000000000053', '99616800-0000-4000-8000-000000000001', '99616800-0000-4000-8000-000000000011', 'STATUS-PLAIN-JOB', 'item_service', 'service', 'component', 'QA_PENDING', '99616800-0000-4000-8000-000000000031', null, false, null, false);
select set_config('app.warranty_claim_rpc', '', true);

create temporary table warranty_before as
select
  (select to_jsonb(invoice) from public.sales_invoices invoice where id = job.invoice_id) as invoice_row,
  coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id) from public.sales_payments payment where payment.tenant_id = job.tenant_id), '[]'::jsonb) as payment_rows,
  coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id) from public.stock_movements movement where movement.tenant_id = job.tenant_id), '[]'::jsonb) as stock_rows,
  coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id) from public.journal_entries entry where entry.tenant_id = job.tenant_id), '[]'::jsonb) as journal_rows
from public.mechanic_jobs job
where job.id = '99616800-0000-4000-8000-000000000051';

select throws_ok(
  $$select public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000051',
    '99616800-0000-4000-8000-000000000032',
    'status-paid-warranty-blocked'
  )$$,
  '55000',
  'La garantía cubierta tiene evidencia de pago. Corrige primero la factura desde el flujo financiero auditado.',
  'a paid covered warranty cannot post or reverse through status'
);
select is(
  (select status_id from public.mechanic_jobs where id = '99616800-0000-4000-8000-000000000051'),
  '99616800-0000-4000-8000-000000000031'::uuid,
  'rejected covered-warranty transition preserves status'
);
select is(
  (select to_jsonb(invoice) from public.sales_invoices invoice where id = '99616800-0000-4000-8000-000000000041'),
  (select invoice_row from warranty_before),
  'rejected covered-warranty transition preserves exact invoice row'
);
select ok(
  (select coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id) from public.sales_payments payment where payment.tenant_id = '99616800-0000-4000-8000-000000000001'), '[]'::jsonb) = payment_rows
     and coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id) from public.stock_movements movement where movement.tenant_id = '99616800-0000-4000-8000-000000000001'), '[]'::jsonb) = stock_rows
     and coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id) from public.journal_entries entry where entry.tenant_id = '99616800-0000-4000-8000-000000000001'), '[]'::jsonb) = journal_rows
   from warranty_before),
  'rejected covered-warranty transition preserves payments, stock and journals exactly'
);

create temporary table service_invoice_before as
select to_jsonb(invoice) as row
from public.sales_invoices invoice
where id = '99616800-0000-4000-8000-000000000042';
select lives_ok(
  $$select public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000052',
    '99616800-0000-4000-8000-000000000032',
    'status-paid-service-allowed'
  )$$,
  'a paid normal service can still advance operational status'
);
select is(
  (select status from public.mechanic_jobs where id = '99616800-0000-4000-8000-000000000052'),
  'QA_DONE',
  'legacy status is derived from the selected custom status code'
);
select is(
  (select to_jsonb(invoice) from public.sales_invoices invoice where id = '99616800-0000-4000-8000-000000000042'),
  (select row from service_invoice_before),
  'normal paid-service status transition preserves the exact invoice row'
);

create temporary table delivery_result as
select public.transition_mechanic_job_status(
  '99616800-0000-4000-8000-000000000053',
  '99616800-0000-4000-8000-000000000033',
  'status-custom-delivery'
) as receipt;
select ok(
  (select delivered_at is not null and completed_at is not null
   from public.mechanic_jobs
   where id = '99616800-0000-4000-8000-000000000053'),
  'custom triggers_delivery status owns delivered/completed timestamps'
);
select is(
  (select status from public.mechanic_jobs where id = '99616800-0000-4000-8000-000000000053'),
  'READY_FOR_PICKUP',
  'custom delivery code remains the derived legacy mirror'
);
select is(
  (public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000053',
    '99616800-0000-4000-8000-000000000033',
    'status-custom-delivery'
  )->>'replay')::boolean,
  true,
  'the exact operation key replays its immutable receipt'
);
select is(
  (select count(*)::integer from public.mechanic_job_status_transition_events where operation_key = 'status-custom-delivery'),
  1,
  'an exact replay appends no duplicate receipt'
);
select is(
  (public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000053',
    '99616800-0000-4000-8000-000000000033',
    'status-custom-delivery-noop'
  )->>'changed')::boolean,
  false,
  'a new exact same-state request is a trigger-free durable no-op'
);
select throws_ok(
  $$select public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000053',
    '99616800-0000-4000-8000-000000000032',
    'status-custom-delivery'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otro cambio de estado.',
  'an operation key cannot be reused for another target status'
);
select throws_ok(
  $$select public.transition_mechanic_job_status(
    '99616800-0000-4000-8000-000000000053',
    '99616800-0000-4000-8000-000000000034',
    'status-cross-tenant'
  )$$,
  '23514',
  'El estado no existe, está inactivo o pertenece a otro negocio.',
  'another tenant status is rejected'
);
select throws_ok(
  $$update public.mechanic_job_status_transition_events
    set changed = false
    where operation_key = 'status-custom-delivery'$$,
  '55000',
  'Mechanic job status transition events are append-only',
  'status transition receipts cannot be mutated'
);

select * from finish();
rollback;
