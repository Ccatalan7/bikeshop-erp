begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(31);

select has_function(
  'public',
  'classify_mechanic_job_as_sale',
  array['uuid', 'text', 'uuid'],
  'sale review has one canonical classification command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.classify_mechanic_job_as_sale(uuid,text,uuid)',
    'execute'
  ),
  'authenticated employees can classify a sale'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.classify_mechanic_job_as_sale(uuid,text,uuid)',
    'execute'
  ),
  'anonymous callers cannot classify a sale'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.classify_mechanic_job_as_sale(uuid,text,uuid)',
    'execute'
  ),
  'service role is not granted the employee-audited sale command'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.mechanic_jobs'::regclass
      and conname = 'mechanic_jobs_sale_intake_pair_check'
      and convalidated
  ),
  'sale and no-intake pairing is validated'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.mechanic_jobs'::regclass
      and conname = 'mechanic_jobs_sale_no_physical_anchor_check'
      and convalidated
  ),
  'sale physical-anchor constraint is validated'
);

insert into public.tenants(id, shop_name) values
  ('99611100-0000-4000-8000-000000000001', 'Sale Collection Tenant A'),
  ('99611100-0000-4000-8000-000000000002', 'Sale Collection Tenant B');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99611100-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'sale-mode@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99611100-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99611100-0000-4000-8000-000000000099',
  '99611100-0000-4000-8000-000000000001',
  'admin'
);

insert into public.customers(id, tenant_id, name) values
  (
    '99611100-0000-4000-8000-000000000011',
    '99611100-0000-4000-8000-000000000001',
    'Sale Customer A'
  ),
  (
    '99611100-0000-4000-8000-000000000021',
    '99611100-0000-4000-8000-000000000002',
    'Sale Customer B'
  );

insert into public.bikes(
  id, tenant_id, customer_id, brand, model, is_active
) values (
  '99611100-0000-4000-8000-000000000031',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  'Codex', 'Sale Guard Bike', true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  is_service, product_type, track_stock
) values
  (
    '99611100-0000-4000-8000-000000000041',
    '99611100-0000-4000-8000-000000000001',
    'Cassette de prueba', 'SALE-CASSETTE', 40000, 20000, 20, 20,
    false, 'product', true
  ),
  (
    '99611100-0000-4000-8000-000000000042',
    '99611100-0000-4000-8000-000000000002',
    'Cassette tenant B', 'SALE-CASSETTE-B', 30000, 15000, 20, 20,
    false, 'product', true
  );

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, status,
  subtotal, net_amount, total, paid_amount, balance, items
) values (
  '99611100-0000-4000-8000-000000000051',
  '99611100-0000-4000-8000-000000000001',
  'SALE-PARTIAL-INVOICE',
  '99611100-0000-4000-8000-000000000011',
  'draft', 40000, 40000, 40000, 10000, 30000, '[]'::jsonb
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, invoice_id, job_number, job_type, status
) values (
  '99611100-0000-4000-8000-000000000061',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  '99611100-0000-4000-8000-000000000051',
  'SALE-REVIEW-PARTIAL', 'service', 'PENDIENTE'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99611100-0000-4000-8000-000000000071',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000061',
  '99611100-0000-4000-8000-000000000041',
  'Cassette de prueba', 'SALE-CASSETTE', 'product', 1, 40000
);

create temporary table sale_before as
select
  md5(to_jsonb(invoice)::text) as invoice_hash,
  (
    select md5(jsonb_agg(to_jsonb(item) order by item.id)::text)
    from public.mechanic_job_items item
    where item.job_id = '99611100-0000-4000-8000-000000000061'
  ) as item_hash
from public.sales_invoices invoice
where invoice.id = '99611100-0000-4000-8000-000000000051';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99611100-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99611100-0000-4000-8000-000000000099',
  true
);

create temporary table sale_result as
select public.classify_mechanic_job_as_sale(
  '99611100-0000-4000-8000-000000000061',
  'Venta confirmada sin objeto recibido.',
  '99611100-0000-4000-8000-000000000101'
) as result;

select is(
  (select result->>'workflow_kind' from sale_result),
  'sale',
  'classification returns sale workflow'
);
select is(
  (select result->>'intake_kind' from sale_result),
  'none',
  'classification returns no physical intake'
);
select is(
  (select job_type from public.mechanic_jobs
   where id = '99611100-0000-4000-8000-000000000061'),
  'service',
  'sale persists the legacy service facade'
);
select is(
  (select mode_needs_review from public.mechanic_jobs
   where id = '99611100-0000-4000-8000-000000000061'),
  false,
  'confirmed sale clears review'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where operation_key = '99611100-0000-4000-8000-000000000101'),
  1,
  'classification appends one immutable event'
);
select is(
  (select metadata->>'classification_source'
   from public.mechanic_job_mode_events
   where operation_key = '99611100-0000-4000-8000-000000000101'),
  'manual-sale-confirmation-v1',
  'event records the explicit sale source'
);
select is(
  (select md5(to_jsonb(invoice)::text)
   from public.sales_invoices invoice
   where invoice.id = '99611100-0000-4000-8000-000000000051'),
  (select invoice_hash from sale_before),
  'classification does not rewrite the partially paid invoice'
);
select is(
  (select md5(jsonb_agg(to_jsonb(item) order by item.id)::text)
   from public.mechanic_job_items item
   where item.job_id = '99611100-0000-4000-8000-000000000061'),
  (select item_hash from sale_before),
  'classification does not rewrite product lines'
);
select is(
  (select count(*)::integer from public.mechanic_job_bikes
   where job_id = '99611100-0000-4000-8000-000000000061'),
  0,
  'classification creates no fictitious bicycle'
);
select is(
  public.classify_mechanic_job_as_sale(
    '99611100-0000-4000-8000-000000000061',
    'Venta confirmada sin objeto recibido.',
    '99611100-0000-4000-8000-000000000101'
  )->>'replayed',
  'true',
  'same operation key replays safely'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where operation_key = '99611100-0000-4000-8000-000000000101'),
  1,
  'replay does not duplicate the event'
);
select throws_ok(
  $$update public.mechanic_jobs
    set discount_amount = 1
    where id = '99611100-0000-4000-8000-000000000061'$$,
  '55000',
  'La factura del trabajo ya tiene pagos. Cliente, modalidad, objeto recibido y descuento quedan protegidos.',
  'paid snapshot remains protected after classification'
);

select throws_ok(
  $$insert into public.mechanic_jobs(
      id, tenant_id, customer_id, job_number, job_type,
      workflow_kind, intake_kind, status
    ) values (
      '99611100-0000-4000-8000-000000000062',
      '99611100-0000-4000-8000-000000000001',
      '99611100-0000-4000-8000-000000000011',
      'SALE-BAD-PAIR', 'service', 'service', 'none', 'PENDIENTE'
    )$$,
  '23514',
  'La venta debe usar recepción sin objeto.',
  'none intake cannot be attached to service workflow'
);
select throws_ok(
  $$insert into public.mechanic_jobs(
      id, tenant_id, customer_id, bike_id, job_number, job_type,
      workflow_kind, intake_kind, status
    ) values (
      '99611100-0000-4000-8000-000000000063',
      '99611100-0000-4000-8000-000000000001',
      '99611100-0000-4000-8000-000000000011',
      '99611100-0000-4000-8000-000000000031',
      'SALE-BAD-BIKE', 'service', 'sale', 'none', 'PENDIENTE'
    )$$,
  '23514',
  'Una venta sin recepción no puede asociar bicicleta ni componente.',
  'sale cannot persist a primary bicycle'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  workflow_kind, intake_kind, status
) values (
  '99611100-0000-4000-8000-000000000064',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  'SALE-DIRECT', 'service', 'sale', 'none', 'PENDIENTE'
);

select throws_ok(
  $$insert into public.mechanic_job_bikes(
      tenant_id, job_id, bike_id, order_index
    ) values (
      '99611100-0000-4000-8000-000000000001',
      '99611100-0000-4000-8000-000000000064',
      '99611100-0000-4000-8000-000000000031', 0
    )$$,
  '23514',
  'Una venta sin recepción no admite bicicletas del trabajo.',
  'child guard prevents a bicycle from being added later'
);
select throws_ok(
  $$select public.create_billable_invoice_from_mechanic_job(
      '99611100-0000-4000-8000-000000000064'
    )$$,
  '23514',
  'La venta necesita al menos un producto de catálogo.',
  'sale invoice builder rejects an empty product wrapper'
);

insert into public.mechanic_job_items(
  tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000064',
  '99611100-0000-4000-8000-000000000041',
  'Cassette de prueba', 'SALE-CASSETTE', 'product', 1, 40000
);

select ok(
  public.create_billable_invoice_from_mechanic_job(
    '99611100-0000-4000-8000-000000000064'
  ) is not null,
  'product-only sale can create its invoice through the guarded builder'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  workflow_kind, intake_kind, status
) values (
  '99611100-0000-4000-8000-000000000065',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  'SALE-WITH-SERVICE', 'service', 'sale', 'none', 'PENDIENTE'
);
insert into public.mechanic_job_items(
  tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000065',
  '99611100-0000-4000-8000-000000000041',
  'Cassette de prueba', 'SALE-CASSETTE', 'product', 1, 40000
);
insert into public.mechanic_job_items(
  tenant_id, job_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000065',
  'Instalación', 'SALE-SERVICE', 'service', 1, 5000
);
select throws_ok(
  $$select public.create_billable_invoice_from_mechanic_job(
      '99611100-0000-4000-8000-000000000065'
    )$$,
  '23514',
  'Una venta sin recepción no puede contener líneas de servicio de taller.',
  'sale invoice builder rejects workshop service lines'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99611100-0000-4000-8000-000000000064';

select is(
  (select starts_warranty_window
   from public.mechanic_job_delivery_events
   where job_id = '99611100-0000-4000-8000-000000000064'
   order by occurred_at desc limit 1),
  false,
  'sale delivery does not open a service-warranty window'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_service_warranty_view
   where job_id = '99611100-0000-4000-8000-000000000064'),
  0,
  'sale is excluded from the service-warranty view'
);
select throws_ok(
  $$select public.extend_mechanic_job_service_warranty(
      '99611100-0000-4000-8000-000000000064',
      clock_timestamp() + interval '30 days',
      'No corresponde', 'sale-extension'
    )$$,
  '23514',
  'Una venta de producto no tiene garantía de servicio técnico.',
  'sale cannot extend a service warranty'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values (
  '99611100-0000-4000-8000-000000000066',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  '99611100-0000-4000-8000-000000000031',
  'SALE-WARRANTY-CLAIM', 'warranty', 'PENDIENTE'
);
select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
      '99611100-0000-4000-8000-000000000066',
      '99611100-0000-4000-8000-000000000064',
      'sale-warranty-registration'
    )$$,
  '23514',
  'Una venta de producto no puede originar una garantía de servicio técnico.',
  'sale cannot become a service-warranty source'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values (
  '99611100-0000-4000-8000-000000000067',
  '99611100-0000-4000-8000-000000000001',
  '99611100-0000-4000-8000-000000000011',
  '99611100-0000-4000-8000-000000000031',
  'SALE-NORMAL-SERVICE', 'service', 'PENDIENTE'
);
update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99611100-0000-4000-8000-000000000067';
select is(
  (select starts_warranty_window
   from public.mechanic_job_delivery_events
   where job_id = '99611100-0000-4000-8000-000000000067'
   order by occurred_at desc limit 1),
  true,
  'ordinary bicycle service still opens its warranty window'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_service_warranty_view
   where job_id = '99611100-0000-4000-8000-000000000067'),
  1,
  'ordinary service remains in the warranty view'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99611100-0000-4000-8000-000000000068',
  '99611100-0000-4000-8000-000000000002',
  '99611100-0000-4000-8000-000000000021',
  'SALE-CROSS-TENANT', 'service', 'PENDIENTE'
);
insert into public.mechanic_job_items(
  tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99611100-0000-4000-8000-000000000002',
  '99611100-0000-4000-8000-000000000068',
  '99611100-0000-4000-8000-000000000042',
  'Cassette tenant B', 'SALE-CASSETTE-B', 'product', 1, 30000
);
select throws_ok(
  $$select public.classify_mechanic_job_as_sale(
      '99611100-0000-4000-8000-000000000068', null,
      '99611100-0000-4000-8000-000000000102'
    )$$,
  '42501',
  'Workshop record does not belong to the active tenant',
  'sale classification rejects another tenant'
);

select * from finish();
rollback;
