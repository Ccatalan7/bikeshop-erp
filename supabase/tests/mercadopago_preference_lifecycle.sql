begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(28);

select has_table(
  'public', 'online_order_payment_preferences',
  'durable payment preference lifecycle table exists'
);
select has_function(
  'public', 'begin_mercadopago_preference_creation',
  array['uuid', 'text', 'uuid', 'text', 'integer'],
  'service-only preference begin/replay command exists'
);
select has_function(
  'public', 'finalize_mercadopago_preference_creation',
  array['uuid', 'uuid', 'text', 'text', 'text',
    'timestamp with time zone', 'timestamp with time zone'],
  'provider preference finalizer exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.begin_mercadopago_preference_creation(uuid,text,uuid,text,integer)',
    'EXECUTE'
  ) and not has_function_privilege(
    'authenticated',
    'public.begin_mercadopago_preference_creation(uuid,text,uuid,text,integer)',
    'EXECUTE'
  ),
  'only service role can begin a provider preference'
);
select ok(
  not has_table_privilege(
    'service_role', 'public.online_order_payment_preferences', 'INSERT'
  ) and not has_table_privilege(
    'authenticated', 'public.online_order_payment_preferences', 'UPDATE'
  ),
  'provider workers and staff cannot bypass canonical preference commands'
);

insert into public.tenants(id, shop_name, currency, timezone)
values (
  '9e310000-0000-4000-8000-000000000001',
  'Mercado Pago Preference Test', 'CLP', 'America/Santiago'
);
insert into public.website_settings(tenant_id, key, value)
values (
  '9e310000-0000-4000-8000-000000000001',
  'online_order_reservation_minutes_mercadopago', '30'
)
on conflict (tenant_id, key) do update set value = excluded.value;

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9e310000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'mp-preference@example.invalid', '', now(),
  '{}'::jsonb,
  '{}'::jsonb,
  now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role)
values (
  '9e310000-0000-4000-8000-000000000099',
  '9e310000-0000-4000-8000-000000000001',
  'admin'
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e310000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e310000-0000-4000-8000-000000000099',
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '9e310000-0000-4000-8000-000000000010',
  '9e310000-0000-4000-8000-000000000001',
  'Preference lifecycle product', 'MP-PREF-001',
  45000, 45000, 20000, 19,
  'product', false, 'inventory', true,
  3, 3, 0, 100, true, true, true
);

create temp table mp_preference_ids(
  name text primary key,
  order_id uuid not null,
  item_id uuid not null,
  begin_receipt jsonb,
  finalize_receipt jsonb
) on commit drop;

insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, tax_amount, total, delivery_type, status, payment_status,
  payment_method
) values
  (
    '9e310000-0000-4000-8000-000000000101',
    '9e310000-0000-4000-8000-000000000001',
    'WEB-TEST-PREF-1', 'one@example.invalid', 'Preference One',
    45000, 0, 45000, 'pickup', 'pending', 'pending', 'mercadopago'
  ),
  (
    '9e310000-0000-4000-8000-000000000102',
    '9e310000-0000-4000-8000-000000000001',
    'WEB-TEST-PREF-2', 'two@example.invalid', 'Preference Two',
    45000, 0, 45000, 'pickup', 'pending', 'pending', 'mercadopago'
  ),
  (
    '9e310000-0000-4000-8000-000000000103',
    '9e310000-0000-4000-8000-000000000001',
    'WEB-TEST-PREF-3', 'three@example.invalid', 'Preference Three',
    45000, 0, 45000, 'pickup', 'pending', 'pending', 'mercadopago'
  );

insert into public.online_order_items(
  id, tenant_id, order_id, product_id, product_name, product_sku,
  quantity, unit_price, subtotal, unit_cost, tax_rate, is_service,
  purchase_treatment, product_type
) values
  (
    '9e310000-0000-4000-8000-000000000201',
    '9e310000-0000-4000-8000-000000000001',
    '9e310000-0000-4000-8000-000000000101',
    '9e310000-0000-4000-8000-000000000010',
    'Preference lifecycle product', 'MP-PREF-001',
    1, 45000, 45000, 20000, 19, false, 'inventory', 'product'
  ),
  (
    '9e310000-0000-4000-8000-000000000202',
    '9e310000-0000-4000-8000-000000000001',
    '9e310000-0000-4000-8000-000000000102',
    '9e310000-0000-4000-8000-000000000010',
    'Preference lifecycle product', 'MP-PREF-001',
    1, 45000, 45000, 20000, 19, false, 'inventory', 'product'
  ),
  (
    '9e310000-0000-4000-8000-000000000203',
    '9e310000-0000-4000-8000-000000000001',
    '9e310000-0000-4000-8000-000000000103',
    '9e310000-0000-4000-8000-000000000010',
    'Preference lifecycle product', 'MP-PREF-001',
    1, 45000, 45000, 20000, 19, false, 'inventory', 'product'
  );

insert into mp_preference_ids(name, order_id, item_id) values
  ('first', '9e310000-0000-4000-8000-000000000101',
    '9e310000-0000-4000-8000-000000000201'),
  ('second', '9e310000-0000-4000-8000-000000000102',
    '9e310000-0000-4000-8000-000000000202'),
  ('third', '9e310000-0000-4000-8000-000000000103',
    '9e310000-0000-4000-8000-000000000203');

select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'service_role')::text,
  true
);

update mp_preference_ids set begin_receipt =
  public.begin_mercadopago_preference_creation(
    order_id,
    repeat(case name when 'first' then 'a' when 'second' then 'b' else 'c' end, 64),
    case name
      when 'first' then '9e310000-0000-4000-8000-000000000301'::uuid
      when 'second' then '9e310000-0000-4000-8000-000000000302'::uuid
      else '9e310000-0000-4000-8000-000000000303'::uuid
    end,
    'pgtap-preference-worker',
    45
  );

select is(
  (select begin_receipt->>'action' from mp_preference_ids where name = 'first'),
  'recover_or_create',
  'first call reserves one recoverable provider preference generation'
);
select is(
  (select begin_receipt->>'external_reference' from mp_preference_ids where name = 'first'),
  'vb1:9e310000-0000-4000-8000-000000000001:9e310000-0000-4000-8000-000000000101:1',
  'external reference binds tenant order and generation'
);
select is(
  (
    select date_trunc('second', (ids.begin_receipt->>'expires_at')::timestamptz)
    from mp_preference_ids ids where ids.name = 'first'
  ),
  (
    select date_trunc('second', min(reservation.expires_at))
    from public.online_order_inventory_reservations reservation
    where reservation.order_id = '9e310000-0000-4000-8000-000000000101'
      and reservation.state = 'active'
  ),
  'provider expiry equals the authoritative inventory reservation deadline'
);
select is(
  (select count(*)::integer from public.online_order_payment_preferences),
  3,
  'each distinct payable order owns exactly one preference generation'
);

select is(
  (
    public.begin_mercadopago_preference_creation(
      '9e310000-0000-4000-8000-000000000101', repeat('a', 64),
      '9e310000-0000-4000-8000-000000000399', 'concurrent-worker', 45
    )->>'action'
  ),
  'busy',
  'a live creation lease blocks a duplicate provider POST'
);

update mp_preference_ids ids
set finalize_receipt = public.finalize_mercadopago_preference_creation(
  (ids.begin_receipt->>'id')::uuid,
  case ids.name
    when 'first' then '9e310000-0000-4000-8000-000000000301'::uuid
    when 'second' then '9e310000-0000-4000-8000-000000000302'::uuid
    else '9e310000-0000-4000-8000-000000000303'::uuid
  end,
  'provider-' || ids.name,
  'https://www.mercadopago.cl/checkout/v1/redirect?pref_id=' || ids.name,
  'https://sandbox.mercadopago.com/checkout/pay?pref_id=' || ids.name,
  clock_timestamp(),
  (ids.begin_receipt->>'expires_at')::timestamptz
);

select is(
  (select finalize_receipt->>'state' from mp_preference_ids where name = 'first'),
  'active',
  'exact provider result activates the preference'
);
select is(
  (
    public.begin_mercadopago_preference_creation(
      '9e310000-0000-4000-8000-000000000101', repeat('a', 64),
      '9e310000-0000-4000-8000-000000000398', 'replay-worker', 45
    )->>'action'
  ),
  'replay',
  'same order snapshot replays the durable active preference'
);
select is(
  (select count(*)::integer from public.online_order_payment_preferences
    where order_id = '9e310000-0000-4000-8000-000000000101'),
  1,
  'active replay never creates another preference generation'
);

update public.online_orders
set status = 'cancelled', cancelled_at = clock_timestamp(),
    cancelled_reason = 'pgTAP cancellation'
where id = '9e310000-0000-4000-8000-000000000101';

select is(
  (select state from public.online_order_payment_preferences
    where order_id = '9e310000-0000-4000-8000-000000000101'),
  'expiration_requested',
  'cancellation queues the live provider preference for expiration'
);
select throws_ok(
  $$select public.begin_mercadopago_preference_creation(
      '9e310000-0000-4000-8000-000000000101', repeat('a', 64),
      '9e310000-0000-4000-8000-000000000397', 'cancelled-retry', 45
    )$$,
  '23514', 'Online order is no longer payable',
  'cancelled order cannot create or replay a payable link'
);

select set_config('app.defer_online_order_payment_processing', 'true', true);
update public.online_orders
set payment_status = 'paid', paid_at = clock_timestamp(),
    payment_reference = 'provider-third'
where id = '9e310000-0000-4000-8000-000000000103';

select is(
  (select state from public.online_order_payment_preferences
    where order_id = '9e310000-0000-4000-8000-000000000103'),
  'expiration_requested',
  'paid order queues every remaining payment link for expiration'
);
select throws_ok(
  $$select public.begin_mercadopago_preference_creation(
      '9e310000-0000-4000-8000-000000000103', repeat('c', 64),
      '9e310000-0000-4000-8000-000000000396', 'paid-retry', 45
    )$$,
  '23514', 'Online order is no longer payable',
  'paid order cannot be charged through a fresh preference'
);

create temp table claimed_preference_expirations on commit drop as
select * from public.claim_mercadopago_preference_expirations(
  'pgtap-expiration-worker', 20, 90
);
select is(
  (select count(*)::integer from claimed_preference_expirations),
  2,
  'worker atomically claims cancellation and payment expirations'
);
select ok(
  (select bool_and(state = 'expiring' and lease_token is not null)
    from claimed_preference_expirations),
  'claimed expiration rows carry owned leases'
);

select public.complete_mercadopago_preference_expiration(
  claimed.id, claimed.lease_token, 'provider_absent',
  claimed.provider_preference_id, null, null, 404
)
from claimed_preference_expirations claimed;

select is(
  (select count(*)::integer from public.online_order_payment_preferences
    where state = 'expired'),
  2,
  'provider-absent completion closes both non-payable preference receipts'
);
select ok(
  (select bool_and(expired_at is not null)
    from public.online_order_payment_preferences where state = 'expired'),
  'terminal preference expiry preserves a server timestamp'
);

select is(
  public.release_online_order_inventory_reservations(
    '9e310000-0000-4000-8000-000000000102',
    'Simulate inventory loss after provider preference creation',
    'pgtap',
    'mp-preference-revalidation'
  ),
  1,
  'test setup releases the stock behind the remaining active preference'
);
update public.products
set inventory_qty = 1, stock_quantity = 1
where id = '9e310000-0000-4000-8000-000000000010';
select is(
  (
    public.begin_mercadopago_preference_creation(
      '9e310000-0000-4000-8000-000000000102', repeat('b', 64),
      '9e310000-0000-4000-8000-000000000395',
      'inventory-revalidation-worker', 45
    )->>'action'
  ),
  'unavailable',
  'an active provider link is never replayed after its inventory is lost'
);
select is(
  (select state from public.online_order_payment_preferences
    where order_id = '9e310000-0000-4000-8000-000000000102'),
  'expiration_requested',
  'inventory revalidation failure durably queues the stale provider link for closure'
);

select throws_ok(
  $$update public.online_order_payment_preferences
       set amount = amount + 1
     where order_id = '9e310000-0000-4000-8000-000000000102'$$,
  '55000', 'Payment preferences can only change through canonical commands',
  'direct mutation cannot rewrite the provider charge'
);
select throws_ok(
  $$delete from public.online_order_payment_preferences
     where order_id = '9e310000-0000-4000-8000-000000000102'$$,
  '55000', 'Payment preference evidence cannot be deleted',
  'preference evidence is undeletable'
);
select is(
  (select count(*)::integer from public.online_order_payment_preferences
    where provider_preference_id = 'provider-second'),
  1,
  'inventory invalidation preserves exactly one provider preference identity'
);
select is(
  (select enabled from public.mercadopago_preference_worker_runtime where singleton),
  false,
  'expiration scheduler starts fail-closed until its dedicated secret is configured'
);

select * from finish();

rollback;
