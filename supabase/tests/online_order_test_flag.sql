begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(11);

create temp table test_flag_values (
  name text primary key,
  value text not null
) on commit drop;

insert into public.tenants (id, shop_name)
values
  ('97100000-0000-4000-8000-000000000001', 'Test Flag Tenant'),
  ('97100000-0000-4000-8000-000000000002', 'Test Flag Other');

insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross, shipping_gross,
  tax_rate, estimated_min_business_days, estimated_max_business_days
) values
  ('97100000-0000-4000-8000-000000000001', 'CL', 0, null, 0, 0, 0, 0);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '97100000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated', 'test-flag@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '97100000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '97100000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated', 'test-flag-other@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '97100000-0000-4000-8000-000000000002'),
    now(), now()
  );

delete from public.user_profiles where user_id in (
  '97100000-0000-4000-8000-000000000099',
  '97100000-0000-4000-8000-000000000098'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values
  ('97100000-0000-4000-8000-000000000099',
   '97100000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('97100000-0000-4000-8000-000000000098',
   '97100000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97100000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '97100000-0000-4000-8000-000000000099', true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '97100000-0000-4000-8000-000000000010',
  '97100000-0000-4000-8000-000000000001',
  'Producto de prueba', 'TEST-FLAG-001', 1190, 990, 400, 19,
  'product', false, 'inventory', true, 10, 10, 0, 100,
  true, true, true
);

insert into test_flag_values
select 'order_id', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '97100000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'test-flag-order-001',
    'customer_email', 'cliente@example.invalid',
    'customer_name', 'Cliente de Prueba',
    'customer_address', 'Calle Sintética 1',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Calle Sintética 1',
    'payment_method', 'mercadopago',
    'total', 990
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '97100000-0000-4000-8000-000000000010',
    'quantity', 1,
    'unit_price', 990
  ))
)::text;

select is(
  (select is_test from public.online_orders
    where id = (select value::uuid from test_flag_values where name = 'order_id')),
  false,
  'a new order is not a test'
);

insert into test_flag_values
select 'mark', public.set_online_order_test_flag(
  (select value::uuid from test_flag_values where name = 'order_id'),
  true,
  (select version from public.online_orders
    where id = (select value::uuid from test_flag_values where name = 'order_id')),
  'test-flag-mark-001'
)::text;

select is(
  (select (value::jsonb)->>'changed' from test_flag_values where name = 'mark'),
  'true',
  'marking reports a real change'
);

select ok(
  (select is_test
       and updated_by = '97100000-0000-4000-8000-000000000099'::uuid
     from public.online_orders
    where id = (select value::uuid from test_flag_values where name = 'order_id')),
  'the order is marked by the acting user'
);

select is(
  (select event_type from public.online_order_events
    where operation_key = 'test-flag-mark-001'),
  'test_flag_changed',
  'marking appends an audited event'
);

select is(
  (select public.set_online_order_test_flag(
     (select value::uuid from test_flag_values where name = 'order_id'),
     true,
     (select expected_version from public.online_order_events
       where operation_key = 'test-flag-mark-001'),
     'test-flag-mark-001'
   )->>'replay'),
  'true',
  'the same operation replays its receipt'
);

select is(
  (select count(*)::integer from public.online_order_events
    where operation_key = 'test-flag-mark-001'),
  1,
  'a replay does not duplicate the event'
);

select throws_ok(
  $$select public.set_online_order_test_flag(
      (select value::uuid from test_flag_values where name = 'order_id'),
      false,
      1,
      'test-flag-stale-001'
    )$$,
  '40001',
  null,
  'a stale version is rejected'
);

select is(
  (select public.set_online_order_test_flag(
     (select value::uuid from test_flag_values where name = 'order_id'),
     false,
     null,
     'test-flag-unmark-001'
   )->>'is_test'),
  'false',
  'the mark can be removed'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '97100000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '97100000-0000-4000-8000-000000000098', true
);

select throws_ok(
  $$select public.set_online_order_test_flag(
      (select value::uuid from test_flag_values where name = 'order_id'),
      true,
      null,
      'test-flag-foreign-001'
    )$$,
  '42501',
  null,
  'another tenant cannot mark the order'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.set_online_order_test_flag(uuid,boolean,bigint,text)',
    'execute'
  ),
  'anonymous callers cannot mark orders'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.set_online_order_test_flag(uuid,boolean,bigint,text)',
    'execute'
  ),
  'signed-in staff can mark orders'
);

select * from finish();
rollback;
