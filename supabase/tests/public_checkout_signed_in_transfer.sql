-- A signed-in store customer (not staff) pays by bank transfer: the public
-- checkout must create and process the order (20261006090000). Before that
-- migration process_online_order's staff-tenant guard rejected the customer
-- and the whole order rolled back; guests passed because auth.uid() is null.
begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table signed_in_transfer_results (
  name text primary key,
  value jsonb not null
) on commit drop;

insert into public.tenants (id, shop_name, is_active)
values ('9e290000-0000-4000-8000-000000000001', 'Signed-in Transfer Shop', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '9e290000-0000-4000-8000-000000000099',
    'authenticated', 'authenticated',
    'signed-in-buyer@example.invalid', '', now(),
    '{}'::jsonb,
    '{"account_type":"public_store_customer"}'::jsonb,
    now(), now()
  ),
  (
    '9e290000-0000-4000-8000-000000000098',
    'authenticated', 'authenticated',
    'staff-actor@example.invalid', '', now(),
    '{}'::jsonb, '{}'::jsonb, now(), now()
  );

-- Product tax events record an actor; inserting a tenant leaves its id as
-- the request subject, so the actor is set after it.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e290000-0000-4000-8000-000000000098', 'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '9e290000-0000-4000-8000-000000000098', true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values (
  '9e290000-0000-4000-8000-000000000011',
  '9e290000-0000-4000-8000-000000000001',
  'Signed-in transfer product', 'SIT-001', 11900, 11900, 5000, 19,
  'product', false, 'inventory', true, 5, 5, 0, 100,
  true, true, true
);

insert into public.website_settings (tenant_id, key, value)
values
  ('9e290000-0000-4000-8000-000000000001', 'store_name', 'Signed-in Store'),
  ('9e290000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco'),
  ('9e290000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('9e290000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '123'),
  ('9e290000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Signed-in SpA'),
  ('9e290000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.123.456-7')
on conflict (tenant_id, key) do update set value = excluded.value;

insert into public.customers (id, tenant_id, auth_user_id, name, email, is_active)
values (
  '9e290000-0000-4000-8000-000000000021',
  '9e290000-0000-4000-8000-000000000001',
  '9e290000-0000-4000-8000-000000000099',
  'Signed-in Buyer', 'signed-in-buyer@example.invalid', true
);

-- From here on the request is the customer's own session.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e290000-0000-4000-8000-000000000099', 'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '9e290000-0000-4000-8000-000000000099', true
);

select is(
  public.user_tenant_id(),
  null::uuid,
  'the buyer is a store customer, not staff of any tenant'
);

select lives_ok(
  $$
    insert into signed_in_transfer_results (name, value)
    select 'created', public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9e290000-0000-4000-8000-000000000001',
        'customer_id', '9e290000-0000-4000-8000-000000000021',
        'checkout_idempotency_key', '33333333-3333-4333-8333-333333333333',
        'customer_email', 'signed-in-buyer@example.invalid',
        'customer_name', 'Signed-in Buyer',
        'customer_address', 'Retiro en tienda',
        'delivery_type', 'pickup',
        'payment_method', 'transfer'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e290000-0000-4000-8000-000000000011',
        'quantity', 1
      ))
    )
  $$,
  'a signed-in customer places a transfer order'
);

select is(
  (
    select customer_order.customer_id
    from public.online_orders customer_order
    where customer_order.id = (
      select (value->>'order_id')::uuid
      from signed_in_transfer_results where name = 'created'
    )
  ),
  '9e290000-0000-4000-8000-000000000021'::uuid,
  'the order belongs to the customer''s account'
);

select is(
  (
    select customer_order.status
    from public.online_orders customer_order
    where customer_order.id = (
      select (value->>'order_id')::uuid
      from signed_in_transfer_results where name = 'created'
    )
  ),
  'confirmed',
  'the transfer order is processed like a guest''s'
);

select throws_ok(
  format(
    'select public.process_online_order(%L::uuid)',
    (
      select value->>'order_id'
      from signed_in_transfer_results where name = 'created'
    )
  ),
  '42501',
  null,
  'the customer still cannot process an order through the ERP entry point'
);

select ok(
  not has_function_privilege(
    'anon', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'service_role', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE'
  ),
  'no API role can call the checkout''s internal processor'
);

select * from finish();
rollback;
