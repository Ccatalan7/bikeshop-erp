-- La vuelta desde Mercado Pago en una pestaña sin el acceso del checkout
-- (20261116001300): el id del pedido más la preferencia que el servidor creó
-- para ese pedido entregan un acceso nuevo de sólo lectura; cualquier otra
-- combinación responde null.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(17);

select has_function(
  'public', 'issue_public_online_order_return_access_v1',
  array['uuid', 'text'],
  'the return-access function exists'
);
select ok(
  (
    select p.prosecdef
       and array_to_string(p.proconfig, ',')
           like '%search_path=pg_catalog, public, extensions, pg_temp%'
      from pg_catalog.pg_proc p
     where p.oid = 'public.issue_public_online_order_return_access_v1(uuid,text)'::regprocedure
  ),
  'it runs as its owner with a fixed search path'
);
select ok(
  has_function_privilege(
    'anon', 'public.issue_public_online_order_return_access_v1(uuid,text)', 'EXECUTE'
  ) and has_function_privilege(
    'authenticated', 'public.issue_public_online_order_return_access_v1(uuid,text)', 'EXECUTE'
  ),
  'the order page calls it without a session'
);

-- Una tienda con un producto y tres pedidos con Mercado Pago, como en
-- mercadopago_preference_lifecycle.sql.
insert into public.tenants(id, shop_name, currency, timezone)
values (
  '9e320000-0000-4000-8000-000000000001',
  'Mercado Pago Return Test', 'CLP', 'America/Santiago'
);
insert into public.website_settings(tenant_id, key, value)
values (
  '9e320000-0000-4000-8000-000000000001',
  'online_order_reservation_minutes_mercadopago', '30'
)
on conflict (tenant_id, key) do update set value = excluded.value;

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9e320000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'mp-return@example.invalid', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role)
values (
  '9e320000-0000-4000-8000-000000000099',
  '9e320000-0000-4000-8000-000000000001',
  'admin'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e320000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', '9e320000-0000-4000-8000-000000000099', true
);

insert into public.products(
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '9e320000-0000-4000-8000-000000000010',
  '9e320000-0000-4000-8000-000000000001',
  'Return access product', 'MP-RET-001',
  23490, 23490, 10000, 19,
  'product', false, 'inventory', true,
  5, 5, 0, 100, true, true, true
);

insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, tax_amount, total, delivery_type, status, payment_status,
  payment_method
) values
  (
    '9e320000-0000-4000-8000-000000000101',
    '9e320000-0000-4000-8000-000000000001',
    'WEB-TEST-RET-1', 'one@example.invalid', 'Return One',
    23490, 0, 23490, 'pickup', 'pending', 'pending', 'mercadopago'
  ),
  (
    '9e320000-0000-4000-8000-000000000102',
    '9e320000-0000-4000-8000-000000000001',
    'WEB-TEST-RET-2', 'two@example.invalid', 'Return Two',
    23490, 0, 23490, 'pickup', 'pending', 'pending', 'mercadopago'
  ),
  (
    '9e320000-0000-4000-8000-000000000103',
    '9e320000-0000-4000-8000-000000000001',
    'WEB-TEST-RET-3', 'three@example.invalid', 'Return Three',
    23490, 0, 23490, 'pickup', 'pending', 'pending', 'mercadopago'
  );

insert into public.online_order_items(
  id, tenant_id, order_id, product_id, product_name, product_sku,
  quantity, unit_price, subtotal, unit_cost, tax_rate, is_service,
  purchase_treatment, product_type
)
select
  ('9e320000-0000-4000-8000-00000000020' || n)::uuid,
  '9e320000-0000-4000-8000-000000000001',
  ('9e320000-0000-4000-8000-00000000010' || n)::uuid,
  '9e320000-0000-4000-8000-000000000010',
  'Return access product', 'MP-RET-001',
  1, 23490, 23490, 10000, 19, false, 'inventory', 'product'
from generate_series(1, 3) as n;

-- Cada pedido recibe su preferencia por el camino canónico, con un id con la
-- forma real de Mercado Pago (`<collector>-<uuid>`).
select set_config(
  'request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true
);
create temp table return_preferences(
  n integer primary key,
  order_id uuid not null,
  lease uuid not null,
  provider_id text not null,
  begun jsonb
) on commit drop;
insert into return_preferences(n, order_id, lease, provider_id)
select
  n,
  ('9e320000-0000-4000-8000-00000000010' || n)::uuid,
  ('9e320000-0000-4000-8000-00000000030' || n)::uuid,
  '1234567890-' || repeat(chr(96 + n), 8) || '-0000-4000-8000-00000000000' || n
from generate_series(1, 3) as n;

update return_preferences
set begun = public.begin_mercadopago_preference_creation(
  order_id, repeat(chr(96 + n), 64), lease, 'pgtap-return-worker', 45
);
select public.finalize_mercadopago_preference_creation(
  (begun->>'id')::uuid, lease, provider_id,
  'https://www.mercadopago.cl/checkout/v1/redirect?pref_id=' || provider_id,
  'https://sandbox.mercadopago.com/checkout/pay?pref_id=' || provider_id,
  clock_timestamp(),
  (begun->>'expires_at')::timestamptz
)
from return_preferences;

-- El tercero tiene una preferencia de hace más de 30 días. Su fecha es
-- inmutable hasta para los comandos canónicos, así que la prueba (que se
-- deshace entera) apaga el guardia sólo para envejecerla.
alter table public.online_order_payment_preferences
  disable trigger trg_guard_online_order_payment_preferences;
update public.online_order_payment_preferences
set created_at = clock_timestamp() - interval '31 days'
where order_id = '9e320000-0000-4000-8000-000000000103';
alter table public.online_order_payment_preferences
  enable trigger trg_guard_online_order_payment_preferences;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

select is(
  (
    select jsonb_build_object(
      'order_id', receipt->>'order_id',
      'token_length', length(receipt->>'access_token'),
      'about_30_days',
        (receipt->>'expires_at')::timestamptz
          between clock_timestamp() + interval '29 days'
              and clock_timestamp() + interval '31 days',
      'replay', receipt->'replay'
    )
    from (
      select public.issue_public_online_order_return_access_v1(
        '9e320000-0000-4000-8000-000000000101',
        '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
      ) as receipt
    ) issued
  ),
  jsonb_build_object(
    'order_id', '9e320000-0000-4000-8000-000000000101',
    'token_length', 43,
    'about_30_days', true,
    'replay', false
  ),
  'the order plus its own preference issue a 30-day receipt shaped like the checkout one'
);

select is(
  public.get_public_online_order_by_access_token(
    public.issue_public_online_order_return_access_v1(
      '9e320000-0000-4000-8000-000000000101',
      '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
    )->>'access_token'
  )->'order'->>'number',
  'WEB-TEST-RET-1',
  'the new access opens the redacted order like the checkout one'
);

select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000102',
    '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
  ),
  null,
  'a preference of another order opens nothing'
);
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000101',
    '1234567890-bbbbbbbb-0000-4000-8000-000000000002'
  ),
  null,
  'an order with someone else''s preference opens nothing'
);
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000101',
    'provider-first'
  ),
  null,
  'something that is not a Mercado Pago preference id opens nothing'
);
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000199',
    '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
  ),
  null,
  'an order that does not exist opens nothing'
);
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000103',
    '1234567890-cccccccc-0000-4000-8000-000000000003'
  ),
  null,
  'a preference older than 30 days opens nothing'
);
select is(
  public.issue_public_online_order_return_access_v1(null, null),
  null,
  'nothing opens nothing'
);

reset role;
select is(
  (
    select array_agg(distinct scope order by scope)
      from public.online_order_access_tokens access,
           unnest(access.scopes) scope
     where access.order_id = '9e320000-0000-4000-8000-000000000101'
  ),
  array['view_order']::text[],
  'the issued accesses only view the order'
);

-- Un pedido que deja de ser de Mercado Pago no se abre por esta vía.
update public.online_orders
set payment_method = 'transfer'
where id = '9e320000-0000-4000-8000-000000000102';
set local role anon;
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000102',
    '1234567890-bbbbbbbb-0000-4000-8000-000000000002'
  ),
  null,
  'an order paid another way opens nothing through a payment return'
);

-- Hasta 20 accesos por pedido en una hora: van 2, se piden 18 más y el
-- siguiente responde null.
do $$
begin
  for i in 1..18 loop
    perform public.issue_public_online_order_return_access_v1(
      '9e320000-0000-4000-8000-000000000101',
      '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
    );
  end loop;
end;
$$;
select is(
  public.issue_public_online_order_return_access_v1(
    '9e320000-0000-4000-8000-000000000101',
    '1234567890-aaaaaaaa-0000-4000-8000-000000000001'
  ),
  null,
  'the 21st access of the hour is refused'
);

reset role;
select is(
  (
    select count(*)::integer
      from public.online_order_access_tokens access
     where access.order_id = '9e320000-0000-4000-8000-000000000101'
  ),
  20,
  'exactly 20 accesses were issued for the order'
);
select is(
  (
    select count(distinct access.token_sha256)::integer
      from public.online_order_access_tokens access
     where access.order_id = '9e320000-0000-4000-8000-000000000101'
  ),
  20,
  'every access is a different token'
);
select is(
  (
    select count(*)::integer
      from public.online_order_access_tokens access
     where access.order_id in (
       '9e320000-0000-4000-8000-000000000102',
       '9e320000-0000-4000-8000-000000000103'
     )
  ),
  0,
  'the refused returns issued nothing'
);

select * from finish();
rollback;
