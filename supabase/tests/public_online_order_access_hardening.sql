begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(29);

create temp table public_order_access_results (
  name text primary key,
  value jsonb not null
) on commit drop;

insert into public.tenants (id, shop_name)
values ('9e170000-0000-4000-8000-000000000001', 'Public Access Test Shop');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '9e170000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'public-access-test@example.invalid', '',
  now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', '9e170000-0000-4000-8000-000000000001'),
  now(), now()
);

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Seed the actor profile explicitly and deterministically.
delete from public.user_profiles
where user_id = '9e170000-0000-4000-8000-000000000099';

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values (
  '9e170000-0000-4000-8000-000000000099',
  '9e170000-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e170000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e170000-0000-4000-8000-000000000099',
  true
);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values (
  '9e170000-0000-4000-8000-000000000010',
  '9e170000-0000-4000-8000-000000000001',
  'Secure checkout product', 'SECURE-CHECKOUT-001', 1190, 990, 400, 19,
  'product', false, 'inventory', true, 10, 10, 0, 100,
  true, true, true
);

insert into public.website_settings (tenant_id, key, value)
values
  (
    '9e170000-0000-4000-8000-000000000001',
    'mercadopago_access_token',
    'TEST-server-secret-never-returned'
  ),
  (
    '9e170000-0000-4000-8000-000000000001',
    'store_url',
    'https://checkout.example'
  );

select ok(
  not has_function_privilege(
    'anon',
    'public.get_public_online_order(uuid,uuid)',
    'execute'
  ),
  'anon cannot execute the UUID-only full-row reader'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_public_online_order(uuid,uuid)',
    'execute'
  ),
  'authenticated cannot execute the UUID-only full-row reader'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_public_online_order(jsonb,jsonb)',
    'execute'
  ),
  'anon cannot create an order without receiving an access token'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_public_online_order(jsonb,jsonb)',
    'execute'
  ),
  'authenticated cannot create an order without receiving an access token'
);

select ok(
  has_function_privilege(
    'anon',
    'public.create_public_online_order_with_access(jsonb,jsonb)',
    'execute'
  ),
  'anon can execute the atomic checkout-with-access RPC'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_public_online_order_with_access(jsonb,jsonb)',
    'execute'
  ),
  'authenticated can execute the atomic checkout-with-access RPC'
);

select ok(
  has_function_privilege(
    'anon',
    'public.get_public_online_order_by_access_token(text)',
    'execute'
  ),
  'anon can execute only the token-authorized redacted reader'
);

select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9e170000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', 'predictable-checkout-key',
        'customer_email', 'private@example.invalid',
        'customer_name', 'Private Customer',
        'delivery_type', 'pickup',
        'payment_method', 'mercadopago'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e170000-0000-4000-8000-000000000010',
        'quantity', 1
      ))
    )
  $$,
  '22023',
  'A random checkout idempotency key is required',
  'checkout refuses predictable replay keys'
);

insert into public_order_access_results (name, value)
select 'created', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', '9e170000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '11111111-1111-4111-8111-111111111111',
    'customer_email', 'private@example.invalid',
    'customer_name', 'Private Customer',
    'customer_phone', '+56912345678',
    'customer_address', 'Private Street 123',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago',
    'customer_notes', 'Private customer note'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e170000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select ok(
  (select (value->>'order_id')::uuid is not null
     from public_order_access_results where name = 'created'),
  'checkout returns an order id'
);

select ok(
  (select value->>'access_token' ~ '^[A-Za-z0-9_-]{43}$'
     from public_order_access_results where name = 'created'),
  'checkout returns one 256-bit base64url access token'
);

select ok(
  (select (value->>'expires_at')::timestamptz
     between clock_timestamp() + interval '29 days'
         and clock_timestamp() + interval '31 days'
     from public_order_access_results where name = 'created'),
  'checkout token expires in approximately 30 days'
);

select is(
  (select value->>'replay' from public_order_access_results where name = 'created'),
  'false',
  'first checkout response is not a replay'
);

select is(
  (select count(*)::integer from public.online_orders
    where tenant_id = '9e170000-0000-4000-8000-000000000001'),
  1,
  'atomic checkout creates exactly one order'
);

select ok(
  not exists (
    select 1
      from public.online_order_access_tokens access
     where access.token_sha256 = (
       select value->>'access_token'
         from public_order_access_results where name = 'created'
     )
  ),
  'raw access token is never persisted'
);

select ok(
  exists (
    select 1
      from public.online_order_access_tokens access
     where access.token_sha256 = encode(
       extensions.digest(convert_to((
         select value->>'access_token'
           from public_order_access_results where name = 'created'
       ), 'UTF8'), 'sha256'),
       'hex'
     )
       and access.scopes = array['view_order']::text[]
       and access.revoked_at is null
  ),
  'only the scoped token hash and lifecycle metadata are persisted'
);

insert into public_order_access_results (name, value)
select 'read', public.get_public_online_order_by_access_token(
  (select value->>'access_token'
     from public_order_access_results where name = 'created')
);

select is(
  (select value #>> '{order,id}' from public_order_access_results where name = 'read'),
  (select value->>'order_id' from public_order_access_results where name = 'created'),
  'token reader returns only its bound order'
);

select is(
  (select value #>> '{order,paymentMethod}'
     from public_order_access_results where name = 'read'),
  'mercadopago',
  'redacted projection retains the payment method needed by the confirmation flow'
);

select is(
  (select (value #>> '{order,taxAmount}')::numeric
     from public_order_access_results where name = 'read'),
  158::numeric,
  'redacted projection retains the authoritative tax total'
);

select ok(
  (select not ((value->'order') ?| array[
      'tenantId', 'tenant_id', 'customerId', 'customer_id',
      'customerEmail', 'customer_email', 'customerPhone', 'customer_phone',
      'customerAddress', 'customer_address', 'paymentReference',
      'salesInvoiceId', 'customerNotes', 'internalNotes', 'notes'
    ]) from public_order_access_results where name = 'read'),
  'redacted order projection excludes tenant, customer, notes, invoice and payment-reference fields'
);

select ok(
  (select (value #> '{items,0}') ?& array[
      'name', 'sku', 'quantity', 'unitPrice', 'subtotal', 'taxRate'
    ] and not ((value #> '{items,0}') ?| array[
      'tenant_id', 'order_id', 'product_id', 'cost', 'unit_cost'
    ]) from public_order_access_results where name = 'read'),
  'public item projection exposes presentation and tax-snapshot fields but no internal identifiers or cost'
);

select is(
  (select use_count from public.online_order_access_tokens
    where token_sha256 = encode(extensions.digest(convert_to((
      select value->>'access_token'
        from public_order_access_results where name = 'created'
    ), 'UTF8'), 'sha256'), 'hex')),
  1::bigint,
  'token use is auditable'
);

insert into public_order_access_results (name, value)
select 'replay', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', '9e170000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '11111111-1111-4111-8111-111111111111',
    'customer_email', 'private@example.invalid',
    'customer_name', 'Private Customer',
    'customer_phone', '+56912345678',
    'customer_address', 'Private Street 123',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago',
    'customer_notes', 'Private customer note'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e170000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (select value->>'order_id' from public_order_access_results where name = 'replay'),
  (select value->>'order_id' from public_order_access_results where name = 'created'),
  'checkout replay returns the original order'
);

select is(
  (select value->>'replay' from public_order_access_results where name = 'replay'),
  'true',
  'checkout reports a replay explicitly'
);

select isnt(
  (select value->>'access_token' from public_order_access_results where name = 'replay'),
  (select value->>'access_token' from public_order_access_results where name = 'created'),
  'a replay receives fresh raw token material instead of requiring raw-token storage'
);

select is(
  (select count(*)::integer from public.online_orders
    where tenant_id = '9e170000-0000-4000-8000-000000000001'),
  1,
  'checkout replay does not duplicate the order'
);

select is(
  (select count(*)::integer from public.online_order_access_tokens
    where tenant_id = '9e170000-0000-4000-8000-000000000001'),
  2,
  'each acknowledged checkout/replay token is independently hashed and expiring'
);

select ok(
  public.get_public_online_order_by_access_token(
    (select value->>'access_token'
       from public_order_access_results where name = 'replay')
  ) #>> '{order,id}' = (
    select value->>'order_id'
      from public_order_access_results where name = 'created'
  ),
  'fresh replay token authorizes the original order'
);

select throws_ok(
  $$
    select public.create_public_online_order_with_access(
      jsonb_build_object(
        'tenant_id', '9e170000-0000-4000-8000-000000000001',
        'checkout_idempotency_key', '11111111-1111-4111-8111-111111111111',
        'customer_email', 'private@example.invalid',
        'customer_name', 'Private Customer',
        'customer_phone', '+56912345678',
        'customer_address', 'Private Street 123',
        'delivery_type', 'pickup',
        'payment_method', 'mercadopago',
        'customer_notes', 'Private customer note'
      ),
      jsonb_build_array(jsonb_build_object(
        'product_id', '9e170000-0000-4000-8000-000000000010',
        'quantity', 2
      ))
    )
  $$,
  '23000',
  'Checkout key was already used with different order content',
  'checkout replay refuses changed order content'
);

select is(
  public.get_public_online_order_by_access_token(repeat('x', 43)),
  null::jsonb,
  'unknown token reveals no order'
);

select * from finish();
rollback;
