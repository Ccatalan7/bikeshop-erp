begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(24);

create temp table sales_channel_test_results (
  name text primary key,
  passed boolean not null,
  message text
) on commit drop;

insert into public.tenants (id, shop_name)
values ('96000000-0000-4000-8000-000000000001', 'Sales Channel Guard Test');

insert into public.tenants (id, shop_name)
values ('96000000-0000-4000-8000-000000000003', 'Other Tenant Guard Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '96000000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'other-tenant@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '96000000-0000-4000-8000-000000000003'),
  now(), now()
);

update public.user_profiles
   set tenant_id = '96000000-0000-4000-8000-000000000003'
 where user_id = '96000000-0000-4000-8000-000000000099';

select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values (
  '96000000-0000-4000-8000-000000000002',
  '96000000-0000-4000-8000-000000000001',
  'Online Guard Product', 'ONLINE-GUARD-001', 1190, 500,
  'product', false, true, 10, 10, 0, 100, true, true, true
);

create temp table sales_channel_ids (name text primary key, id uuid not null)
on commit drop;

insert into sales_channel_ids
select 'first_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'checkout-guard-001',
    'customer_email', 'guard@example.com',
    'customer_name', 'Guard Customer',
    'customer_phone', '+56911111111',
    'customer_address', 'Guard Street 123',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Guard Street 123',
    'payment_method', 'mercadopago',
    'total', 999999,
    'order_number', 'CLIENT-CONTROLLED'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '96000000-0000-4000-8000-000000000002',
    'quantity', 1,
    'unit_price', 999999
  ))
);

insert into sales_channel_ids
select 'replayed_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'checkout-guard-001',
    'customer_email', 'guard@example.com',
    'customer_name', 'Guard Customer',
    'customer_phone', '+56911111111',
    'customer_address', 'Guard Street 123',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Guard Street 123',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '96000000-0000-4000-8000-000000000002',
    'quantity', 1
  ))
);

select is(
  (select id from sales_channel_ids where name = 'replayed_order'),
  (select id from sales_channel_ids where name = 'first_order'),
  'same checkout key and payload returns the original order'
);

select is(
  (select count(*)::integer from public.online_orders
    where tenant_id = '96000000-0000-4000-8000-000000000001'),
  1,
  'checkout replay creates only one order row'
);

select is(
  (select total from public.online_orders
    where id = (select id from sales_channel_ids where name = 'first_order')),
  1190::numeric,
  'server product price overrides client monetary values'
);

select isnt(
  (select order_number from public.online_orders
    where id = (select id from sales_channel_ids where name = 'first_order')),
  'CLIENT-CONTROLLED',
  'server generates the order number'
);

select ok(
  (select checkout_payload_hash is not null from public.online_orders
    where id = (select id from sales_channel_ids where name = 'first_order')),
  'checkout stores its server fingerprint'
);

do $$
begin
  perform public.create_public_online_order(
    jsonb_build_object(
      'tenant_id', '96000000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'checkout-guard-001',
      'customer_email', 'changed@example.com',
      'customer_name', 'Guard Customer',
      'customer_address', 'Guard Street 123',
      'delivery_type', 'shipping',
      'shipping_address_line1', 'Guard Street 123',
      'payment_method', 'mercadopago'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '96000000-0000-4000-8000-000000000002',
      'quantity', 1
    ))
  );
  insert into sales_channel_test_results values ('key_mismatch', false, 'unexpected success');
exception when others then
  insert into sales_channel_test_results values (
    'key_mismatch',
    sqlerrm like 'Checkout key was already used with different order content%',
    sqlerrm
  );
end $$;

select ok(
  (select passed from sales_channel_test_results where name = 'key_mismatch'),
  'same checkout key cannot be reused with different content'
);

select ok(
  not has_function_privilege('anon', 'public.process_online_order(uuid)', 'EXECUTE'),
  'anonymous role cannot process an online order'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.confirm_online_order_payment(uuid,text,timestamp with time zone)',
    'EXECUTE'
  ),
  'anonymous role cannot confirm an online payment'
);

select ok(
  not has_function_privilege('anon', 'public.cancel_online_order(uuid,text,numeric)', 'EXECUTE'),
  'anonymous role cannot cancel an online order'
);

select ok(
  has_function_privilege(
    'anon', 'public.create_public_online_order(jsonb,jsonb)', 'EXECUTE'
  ),
  'anonymous checkout retains access to the hardened order RPC'
);

select ok(
  not has_function_privilege(
    'authenticated', 'public.create_public_online_order_unkeyed(jsonb,jsonb)', 'EXECUTE'
  ),
  'clients cannot bypass the idempotent checkout wrapper'
);

select set_config(
  'request.jwt.claim.sub',
  '96000000-0000-4000-8000-000000000099',
  true
);

do $$
begin
  perform public.process_online_order(
    (select id from sales_channel_ids where name = 'first_order')
  );
  insert into sales_channel_test_results values ('cross_tenant_process', false, 'unexpected success');
exception when insufficient_privilege then
  insert into sales_channel_test_results values ('cross_tenant_process', true, sqlerrm);
when others then
  insert into sales_channel_test_results values ('cross_tenant_process', false, sqlerrm);
end $$;

select ok(
  (select passed from sales_channel_test_results where name = 'cross_tenant_process'),
  'authenticated processing cannot cross tenant boundaries'
);

select set_config('request.jwt.claim.sub', '', true);

select is(
  (select tgenabled::text from pg_trigger
    where tgrelid = 'public.order_items'::regclass
      and tgname = 'trg_order_item_insert'),
  'D',
  'legacy direct-stock order trigger is disabled'
);

select is(
  (public.apply_mercadopago_payment_event(
    (select id from sales_channel_ids where name = 'first_order'),
    '96000000-0000-4000-8000-000000000001',
    'mp-wrong-amount', 'approved', 1189, 'CLP', now(), '{}'
  )->>'outcome'),
  'rejected_amount',
  'one-peso provider mismatch is rejected and recorded'
);

select is(
  (select payment_status from public.online_orders
    where id = (select id from sales_channel_ids where name = 'first_order')),
  'pending',
  'rejected amount does not mutate order payment state'
);

select is(
  (public.apply_mercadopago_payment_event(
    (select id from sales_channel_ids where name = 'first_order'),
    '96000000-0000-4000-8000-000000000001',
    'mp-wrong-currency', 'approved', 1190, 'USD', now(), '{}'
  )->>'outcome'),
  'rejected_currency',
  'non-CLP provider payment is rejected and recorded'
);

select is(
  (public.apply_mercadopago_payment_event(
    (select id from sales_channel_ids where name = 'first_order'),
    '96000000-0000-4000-8000-000000000001',
    'mp-approved-001', 'approved', 1190, 'CLP', now(),
    jsonb_build_object('status_detail', 'accredited')
  )->>'outcome'),
  'applied',
  'valid approved payment atomically processes the order'
);

select is(
  (select inventory_qty from public.products
    where id = '96000000-0000-4000-8000-000000000002'),
  9,
  'valid provider payment consumes inventory exactly once'
);

select ok(
  exists (
    select 1
    from public.online_orders orders
    join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
    join public.sales_payments payment on payment.invoice_id = invoice.id
    where orders.id = (select id from sales_channel_ids where name = 'first_order')
      and orders.payment_status = 'paid'
      and invoice.status = 'paid'
      and payment.idempotency_key = 'mercadopago:mp-approved-001'
      and payment.deleted_at is null
  ),
  'order, invoice, and provider-keyed payment are connected'
);

select ok(
  exists (
    select 1 from public.sales_channel_payment_events
    where tenant_id = '96000000-0000-4000-8000-000000000001'
      and external_payment_id = 'mp-approved-001'
      and outcome = 'applied'
      and invoice_id is not null
      and operation_id is not null
  ),
  'provider event connects to invoice and inventory/accounting operation'
);

select is(
  (public.apply_mercadopago_payment_event(
    (select id from sales_channel_ids where name = 'first_order'),
    '96000000-0000-4000-8000-000000000001',
    'mp-approved-001', 'approved', 1190, 'CLP', now(), '{}'
  )->>'replay'),
  'true',
  'provider event replay returns existing evidence'
);

select is(
  (select inventory_qty from public.products
    where id = '96000000-0000-4000-8000-000000000002'),
  9,
  'provider event replay does not consume inventory again'
);

select is(
  (public.apply_mercadopago_payment_event(
    (select id from sales_channel_ids where name = 'first_order'),
    '96000000-0000-4000-8000-000000000001',
    'mp-approved-conflict', 'approved', 1190, 'CLP', now(), '{}'
  )->>'outcome'),
  'rejected_conflicting_payment',
  'a second distinct approved payment is surfaced without reposting'
);

do $$
begin
  update public.sales_channel_payment_events
     set validation_error = 'tampered'
   where external_payment_id = 'mp-approved-001';
  insert into sales_channel_test_results values ('event_immutable', false, 'unexpected success');
exception when check_violation then
  insert into sales_channel_test_results values ('event_immutable', true, sqlerrm);
when others then
  insert into sales_channel_test_results values ('event_immutable', false, sqlerrm);
end $$;

select ok(
  (select passed from sales_channel_test_results where name = 'event_immutable'),
  'provider event evidence is append-only'
);

select * from finish();
rollback;
