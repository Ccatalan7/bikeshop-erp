begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(12);

insert into public.tenants(id, shop_name) values (
  '99616700-0000-4000-8000-000000000001',
  'Inactive Conversion Bike Tenant'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99616700-0000-4000-8000-000000000099',
  'authenticated', 'authenticated',
  'inactive-conversion-bike@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99616700-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99616700-0000-4000-8000-000000000099',
  '99616700-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616700-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616700-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values (
  '99616700-0000-4000-8000-000000000011',
  '99616700-0000-4000-8000-000000000001',
  'Inactive Conversion Bike Customer'
);

insert into public.bikes(
  id, tenant_id, customer_id, brand, model, is_active
) values (
  '99616700-0000-4000-8000-000000000031',
  '99616700-0000-4000-8000-000000000001',
  '99616700-0000-4000-8000-000000000011',
  'Codex', 'Archived Bike', false
);

-- Four independent approved quotations exercise every bicycle-resolution
-- route: explicit RPC argument, persisted primary bicycle, aggregate fallback,
-- and the temporary direct-write bridge kept for an older deployed client.
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id,
  quotation_status, quotation_valid_until, status
) values
  (
    '99616700-0000-4000-8000-000000000061',
    '99616700-0000-4000-8000-000000000001',
    '99616700-0000-4000-8000-000000000011',
    'INACTIVE-BIKE-EXPLICIT', 'quotation', null,
    'pending', clock_timestamp() + interval '7 days', 'PRESUPUESTO'
  ),
  (
    '99616700-0000-4000-8000-000000000062',
    '99616700-0000-4000-8000-000000000001',
    '99616700-0000-4000-8000-000000000011',
    'INACTIVE-BIKE-PERSISTED', 'quotation',
    '99616700-0000-4000-8000-000000000031',
    'pending', clock_timestamp() + interval '7 days', 'PRESUPUESTO'
  ),
  (
    '99616700-0000-4000-8000-000000000063',
    '99616700-0000-4000-8000-000000000001',
    '99616700-0000-4000-8000-000000000011',
    'INACTIVE-BIKE-FALLBACK', 'quotation', null,
    'pending', clock_timestamp() + interval '7 days', 'PRESUPUESTO'
  ),
  (
    '99616700-0000-4000-8000-000000000064',
    '99616700-0000-4000-8000-000000000001',
    '99616700-0000-4000-8000-000000000011',
    'INACTIVE-BIKE-LEGACY', 'quotation',
    '99616700-0000-4000-8000-000000000031',
    'pending', clock_timestamp() + interval '7 days', 'PRESUPUESTO'
  );

insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values (
  '99616700-0000-4000-8000-000000000091',
  '99616700-0000-4000-8000-000000000001',
  '99616700-0000-4000-8000-000000000063',
  '99616700-0000-4000-8000-000000000031',
  0
);

select public.transition_mechanic_job_quotation(
  '99616700-0000-4000-8000-000000000061', 'approved', null,
  '99616700-0000-4000-8000-000000000101'
);
select public.transition_mechanic_job_quotation(
  '99616700-0000-4000-8000-000000000062', 'approved', null,
  '99616700-0000-4000-8000-000000000102'
);
select public.transition_mechanic_job_quotation(
  '99616700-0000-4000-8000-000000000063', 'approved', null,
  '99616700-0000-4000-8000-000000000103'
);
select public.transition_mechanic_job_quotation(
  '99616700-0000-4000-8000-000000000064', 'approved', null,
  '99616700-0000-4000-8000-000000000104'
);

create temporary table inactive_bike_effect_baseline as
select
  (select count(*) from public.sales_invoices
   where tenant_id = '99616700-0000-4000-8000-000000000001') as invoices,
  (select count(*) from public.sales_payments
   where tenant_id = '99616700-0000-4000-8000-000000000001') as payments,
  (select count(*) from public.stock_movements
   where tenant_id = '99616700-0000-4000-8000-000000000001') as movements,
  (select count(*) from public.journal_entries
   where tenant_id = '99616700-0000-4000-8000-000000000001') as journals,
  (select count(*) from public.mechanic_job_bikes
   where tenant_id = '99616700-0000-4000-8000-000000000001') as job_bikes;

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616700-0000-4000-8000-000000000061', 'service', null, true,
    '99616700-0000-4000-8000-000000000031', null,
    '99616700-0000-4000-8000-000000000111'
  )$$,
  '23514',
  'Selecciona una bicicleta activa del mismo cliente antes de convertir la cotización.',
  'an explicit inactive bicycle cannot convert an approved quotation'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616700-0000-4000-8000-000000000062', 'service', null, true,
    null, null, '99616700-0000-4000-8000-000000000112'
  )$$,
  '23514',
  'Selecciona una bicicleta activa del mismo cliente antes de convertir la cotización.',
  'a persisted inactive primary bicycle cannot convert an approved quotation'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616700-0000-4000-8000-000000000063', 'service', null, true,
    null, null, '99616700-0000-4000-8000-000000000113'
  )$$,
  '23514',
  'Selecciona una bicicleta activa del mismo cliente antes de convertir la cotización.',
  'an inactive aggregate bicycle cannot be selected by the fallback path'
);

select throws_ok(
  $$update public.mechanic_jobs
    set job_type = 'service',
        quotation_status = null,
        quotation_valid_until = null,
        is_warranty_job = false,
        converted_at = '2000-01-01T00:00:00Z'::timestamptz
    where id = '99616700-0000-4000-8000-000000000064'$$,
  '23514',
  'La bicicleta recibida debe estar activa y pertenecer al cliente y negocio del trabajo.',
  'the legacy conversion bridge cannot accept an inactive persisted bicycle'
);

select is(
  (select count(*)::integer
   from public.mechanic_jobs
   where tenant_id = '99616700-0000-4000-8000-000000000001'
     and id in (
       '99616700-0000-4000-8000-000000000061',
       '99616700-0000-4000-8000-000000000062',
       '99616700-0000-4000-8000-000000000063',
       '99616700-0000-4000-8000-000000000064'
     )
     and workflow_kind = 'quotation'
     and quotation_status = 'approved'
     and invoice_id is null
     and converted_at is null),
  4,
  'all rejected conversions leave their approved quotation rows unchanged'
);

select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where tenant_id = '99616700-0000-4000-8000-000000000001'
     and event_type = 'converted_to_billable'),
  0,
  'rejected inactive-bicycle conversions append no conversion receipts'
);

select is(
  (select count(*) from public.sales_invoices
   where tenant_id = '99616700-0000-4000-8000-000000000001'),
  (select invoices from inactive_bike_effect_baseline),
  'rejected inactive-bicycle conversions create no invoice'
);

select is(
  (select count(*) from public.sales_payments
   where tenant_id = '99616700-0000-4000-8000-000000000001'),
  (select payments from inactive_bike_effect_baseline),
  'rejected inactive-bicycle conversions create no payment'
);

select is(
  (select count(*) from public.stock_movements
   where tenant_id = '99616700-0000-4000-8000-000000000001'),
  (select movements from inactive_bike_effect_baseline),
  'rejected inactive-bicycle conversions create no stock movement'
);

select is(
  (select count(*) from public.journal_entries
   where tenant_id = '99616700-0000-4000-8000-000000000001'),
  (select journals from inactive_bike_effect_baseline),
  'rejected inactive-bicycle conversions create no journal entry'
);

select is(
  (select count(*) from public.mechanic_job_bikes
   where tenant_id = '99616700-0000-4000-8000-000000000001'),
  (select job_bikes from inactive_bike_effect_baseline),
  'rejected conversions create no additional job-bicycle association'
);

select is(
  (select is_active from public.bikes
   where id = '99616700-0000-4000-8000-000000000031'),
  false,
  'the rejected paths never reactivate the archived bicycle'
);

select * from finish();
rollback;
