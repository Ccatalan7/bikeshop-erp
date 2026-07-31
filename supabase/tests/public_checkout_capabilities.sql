begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table checkout_capability_results (
  name text primary key,
  value jsonb not null
) on commit drop;

insert into public.tenants (id, shop_name, is_active)
values
  (
    '9e280000-0000-4000-8000-000000000001',
    'Capability Shop A',
    true
  ),
  (
    '9e280000-0000-4000-8000-000000000002',
    'Capability Shop B',
    true
  ),
  (
    '9e280000-0000-4000-8000-000000000003',
    'Inactive Capability Shop',
    false
  );

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '9e280000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'checkout-capability-test@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id',
    '9e280000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '9e280000-0000-4000-8000-000000000099';

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '9e280000-0000-4000-8000-000000000099',
  '9e280000-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e280000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e280000-0000-4000-8000-000000000099',
  true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values
  (
    '9e280000-0000-4000-8000-000000000011',
    '9e280000-0000-4000-8000-000000000001',
    'Capability product A', 'CAP-A-001', 1190, 990, 400, 19,
    'product', false, 'inventory', true, 10, 10, 0, 100,
    true, true, true
  ),
  (
    '9e280000-0000-4000-8000-000000000012',
    '9e280000-0000-4000-8000-000000000002',
    'Capability product B', 'CAP-B-001', 1190, 990, 400, 19,
    'product', false, 'inventory', true, 10, 10, 0, 100,
    true, true, true
  );

insert into public.website_settings (tenant_id, key, value)
values
  (
    '9e280000-0000-4000-8000-000000000001',
    'mercadopago_access_token',
    'TEST-super-secret-token'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'store_url',
    'http://insecure.example'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'payment_transfer_bank_name',
    'Banco Seguro'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'payment_transfer_account_type',
    'Cuenta corriente'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'payment_transfer_account_number',
    '123456789'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'payment_transfer_account_holder',
    'Capability Shop A SpA'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'store_name',
    'Snapshot Store'
  )
on conflict (tenant_id, key) do update
set value = excluded.value,
    updated_at = clock_timestamp();

select has_function(
  'public',
  'get_public_checkout_capabilities',
  array['uuid'],
  'storefront exposes a tenant-scoped effective payment capability reader'
);

select ok(
  has_function_privilege(
    'anon',
    'public.get_public_checkout_capabilities(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_public_checkout_capabilities(uuid)',
    'execute'
  ),
  'storefront roles can read only the safe capability facade'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.resolve_public_checkout_capabilities(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.resolve_public_checkout_capabilities(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'service_role',
    'public.resolve_public_checkout_capabilities(uuid)',
    'execute'
  ),
  'the settings resolver remains private'
);

insert into checkout_capability_results (name, value)
values (
  'incomplete_a',
  public.get_public_checkout_capabilities(
    '9e280000-0000-4000-8000-000000000001'
  )
);

select is(
  (
    select value #>> '{methods,0,reasonCode}'
    from checkout_capability_results
    where name = 'incomplete_a'
  ),
  'store_origin_invalid',
  'Mercado Pago stays unavailable without a clean HTTPS storefront origin'
);

select is(
  (
    select value #>> '{methods,1,reasonCode}'
    from checkout_capability_results
    where name = 'incomplete_a'
  ),
  'configuration_incomplete',
  'transfer stays unavailable until every required bank field exists'
);

select ok(
  (
    select value::text not like '%TEST-super-secret-token%'
      and value::text not like '%123456789%'
    from checkout_capability_results
    where name = 'incomplete_a'
  ),
  'the public facade never exposes payment credentials or bank details'
);

select ok(
  not (
    (public.get_public_checkout_capabilities(
      '9e280000-0000-4000-8000-000000000002'
    ) #>> '{methods,0,available}')::boolean
  )
  and not (
    (public.get_public_checkout_capabilities(
      '9e280000-0000-4000-8000-000000000002'
    ) #>> '{methods,1,available}')::boolean
  ),
  'another tenant cannot inherit payment availability'
);

select throws_ok(
  $$
    select public.get_public_checkout_capabilities(
      '9e280000-0000-4000-8000-000000000003'
    )
  $$,
  '42501',
  'Storefront tenant is invalid or inactive',
  'inactive tenants cannot expose a checkout capability surface'
);

select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9e280000-0000-4000-8000-000000000002',
        'checkout_idempotency_key',
          '22222222-2222-4222-8222-222222222222',
        'customer_email', 'blocked@example.invalid',
        'customer_name', 'Blocked Customer',
        'delivery_type', 'pickup',
        'payment_method', 'transfer'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e280000-0000-4000-8000-000000000012',
        'quantity', 1
      ))
    )
  $$,
  'P0001',
  'Checkout payment method unavailable: configuration_incomplete',
  'an unavailable method fails before public order insertion'
);

select is(
  (
    select count(*)::integer
    from public.online_orders
    where tenant_id = '9e280000-0000-4000-8000-000000000002'
  ),
  0,
  'the rejected checkout leaves no order behind'
);

insert into public.website_settings (tenant_id, key, value)
values
  (
    '9e280000-0000-4000-8000-000000000001',
    'store_url',
    'https://checkout.example'
  ),
  (
    '9e280000-0000-4000-8000-000000000001',
    'payment_transfer_rut',
    '76.123.456-7'
  )
on conflict (tenant_id, key) do update
set value = excluded.value,
    updated_at = clock_timestamp();

select ok(
  (
    (public.get_public_checkout_capabilities(
      '9e280000-0000-4000-8000-000000000001'
    ) #>> '{methods,0,available}')::boolean
  )
  and (
    (public.get_public_checkout_capabilities(
      '9e280000-0000-4000-8000-000000000001'
    ) #>> '{methods,1,available}')::boolean
  ),
  'complete tenant settings expose both effective methods'
);

insert into checkout_capability_results (name, value)
select 'created', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', '9e280000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '11111111-1111-4111-8111-111111111111',
    'customer_email', 'snapshot@example.invalid',
    'customer_name', 'Snapshot Customer',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago',
    'storefront_identity', jsonb_build_object(
      'displayName', 'Browser Forgery'
    )
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e280000-0000-4000-8000-000000000011',
    'quantity', 1
  ))
);

select is(
  (
    select snapshot.identity_snapshot->>'displayName'
    from public.online_order_storefront_snapshots snapshot
    where snapshot.order_id = (
      select (value->>'order_id')::uuid
      from checkout_capability_results
      where name = 'created'
    )
  ),
  'Snapshot Store',
  'order identity is captured from server-owned tenant settings'
);

select is(
  (
    select count(*)::integer
    from public.online_order_storefront_snapshots snapshot
    where snapshot.order_id = (
      select (value->>'order_id')::uuid
      from checkout_capability_results
      where name = 'created'
    )
  ),
  1,
  'each new order receives exactly one storefront identity snapshot'
);

update public.website_settings
set value = 'Changed Store',
    updated_at = clock_timestamp()
where tenant_id = '9e280000-0000-4000-8000-000000000001'
  and key = 'store_name';

delete from public.website_settings
where tenant_id = '9e280000-0000-4000-8000-000000000001'
  and key = 'mercadopago_access_token';

insert into checkout_capability_results (name, value)
select 'replayed', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', '9e280000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '11111111-1111-4111-8111-111111111111',
    'customer_email', 'snapshot@example.invalid',
    'customer_name', 'Snapshot Customer',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago',
    'storefront_identity', jsonb_build_object(
      'displayName', 'Browser Forgery'
    )
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e280000-0000-4000-8000-000000000011',
    'quantity', 1
  ))
);

select is(
  (
    select value->>'order_id'
    from checkout_capability_results
    where name = 'replayed'
  ),
  (
    select value->>'order_id'
    from checkout_capability_results
    where name = 'created'
  ),
  'an exact replay recovers the original order after configuration changes'
);

select is(
  (
    select value->>'replay'
    from checkout_capability_results
    where name = 'replayed'
  ),
  'true',
  'the recovered response remains marked as an idempotent replay'
);

select is(
  (
    select snapshot.identity_snapshot->>'displayName'
    from public.online_order_storefront_snapshots snapshot
    where snapshot.order_id = (
      select (value->>'order_id')::uuid
      from checkout_capability_results
      where name = 'replayed'
    )
  ),
  'Snapshot Store',
  'later editor changes cannot rewrite the order identity'
);

insert into checkout_capability_results (name, value)
select 'read', public.get_public_online_order_by_access_token(
  (
    select value->>'access_token'
    from checkout_capability_results
    where name = 'replayed'
  )
);

select is(
  (
    select value #>> '{storefront,displayName}'
    from checkout_capability_results
    where name = 'read'
  ),
  'Snapshot Store',
  'the token reader returns the immutable server snapshot'
);

select ok(
  (
    select value::text not like '%Browser Forgery%'
      and value::text not like '%TEST-super-secret-token%'
      and value::text not like '%123456789%'
    from checkout_capability_results
    where name = 'read'
  ),
  'public order reads reject browser branding and omit payment secrets'
);

select throws_ok(
  format(
    'update public.online_order_storefront_snapshots
        set identity_snapshot = identity_snapshot ||
          %L::jsonb
      where order_id = %L::uuid',
    '{"displayName":"Mutated"}',
    (
      select value->>'order_id'
      from checkout_capability_results
      where name = 'created'
    )
  ),
  '55000',
  'Online order storefront snapshots are immutable',
  'storefront identity snapshots cannot be edited'
);

select * from finish();

rollback;
