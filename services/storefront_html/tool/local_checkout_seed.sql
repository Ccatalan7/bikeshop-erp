-- A store for trying the HTML checkout end to end on the LOCAL database only
-- (services/storefront_html/tool/run_local_checkout.sh): one tenant, three
-- products with stock and IVA, the four shipping tiers the store uses, both
-- payment methods configured with fake values, and one customer account.
-- Every value is a test value; nothing here exists in production.
--
-- Test customer: comprador.prueba@example.invalid / Prueba-Local-2026
-- (local GoTrue only).
--
-- Idempotent: it removes its own rows first (orders included) and adds them
-- again, so each run starts from the same state.

begin;

-- Orders leave reservations, events, tokens and outbox rows behind, some
-- append-only: on this local database only, triggers and foreign keys are
-- set aside while every row of the test store is removed.
set local session_replication_role = replica;
do $$
declare
  test_tenant constant uuid := '7e570000-0000-4000-8000-000000000001';
  target record;
begin
  for target in
    select distinct child.conrelid::regclass as rel
    from pg_constraint child
    where child.contype = 'f'
      and child.confrelid in (
        'public.online_orders'::regclass, 'public.online_order_items'::regclass,
        'public.products'::regclass, 'public.customers'::regclass
      )
      and exists (
        select 1 from pg_attribute att
        where att.attrelid = child.conrelid and att.attname = 'tenant_id'
          and not att.attisdropped
      )
  loop
    execute format('delete from %s where tenant_id = $1', target.rel) using test_tenant;
  end loop;
  delete from public.online_orders where tenant_id = test_tenant;
  delete from public.customer_addresses where tenant_id = test_tenant;
  delete from public.customers where tenant_id = test_tenant;
  delete from public.online_shipping_rate_tiers where tenant_id = test_tenant;
  delete from public.website_settings where tenant_id = test_tenant;
  delete from public.products where tenant_id = test_tenant;
end;
$$;
set local session_replication_role = origin;

-- The test customer: an e-mail-confirmed local GoTrue user.
delete from auth.identities where user_id = '7e570000-0000-4000-8000-000000000099';
delete from auth.users where id = '7e570000-0000-4000-8000-000000000099';
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
values (
  '00000000-0000-0000-0000-000000000000',
  '7e570000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'comprador.prueba@example.invalid',
  extensions.crypt('Prueba-Local-2026', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"account_type":"public_store_customer","name":"Comprador de Prueba","phone":"+56 9 1111 2222"}'::jsonb,
  now(), now(), '', '', '', ''
);
insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, last_sign_in_at,
  created_at, updated_at
)
values (
  gen_random_uuid(), '7e570000-0000-4000-8000-000000000099',
  '7e570000-0000-4000-8000-000000000099', 'email',
  jsonb_build_object(
    'sub', '7e570000-0000-4000-8000-000000000099',
    'email', 'comprador.prueba@example.invalid',
    'email_verified', true
  ),
  now(), now(), now()
);


insert into public.tenants (id, shop_name, is_active)
values ('7e570000-0000-4000-8000-000000000001', 'Tienda de prueba', true)
on conflict (id) do update set shop_name = excluded.shop_name, is_active = true;

-- A product's IVA classification records who set it: the test customer.
-- After the tenant: inserting one leaves its id as the request's subject.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e570000-0000-4000-8000-000000000099","role":"authenticated"}',
  true
);
select set_config('request.jwt.claim.sub', '7e570000-0000-4000-8000-000000000099', true);



insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values
  ('7e570000-0000-4000-8000-000000000011', '7e570000-0000-4000-8000-000000000001',
   'CASSETTE DE PRUEBA 8 VELOCIDADES 11-42T', 'PRB-001', 35000, 35000, 15000, 19,
   'product', false, 'inventory', true, 10, 10, 0, 100, true, true, true),
  ('7e570000-0000-4000-8000-000000000012', '7e570000-0000-4000-8000-000000000001',
   'Maza trasera de prueba MTB, aluminio, 36H, negra', 'PRB-002', 24000, 24000, 9000, 19,
   'product', false, 'inventory', true, 1, 1, 0, 100, true, true, true),
  ('7e570000-0000-4000-8000-000000000013', '7e570000-0000-4000-8000-000000000001',
   'CANDADO DE PRUEBA U-LOCK', 'PRB-003', 15000, 15000, 6000, 19,
   'product', false, 'inventory', true, 5, 5, 0, 100, true, true, true);

insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross, shipping_gross,
  tax_rate, estimated_min_business_days, estimated_max_business_days
)
values
  ('7e570000-0000-4000-8000-000000000001', 'CL', 0, 30000, 6990, 19, 3, 12),
  ('7e570000-0000-4000-8000-000000000001', 'CL', 30000, 80000, 8990, 19, 3, 12),
  ('7e570000-0000-4000-8000-000000000001', 'CL', 80000, 150000, 11990, 19, 3, 12),
  ('7e570000-0000-4000-8000-000000000001', 'CL', 150000, null, 14990, 19, 3, 12);

insert into public.website_settings (tenant_id, key, value)
select '7e570000-0000-4000-8000-000000000001', key, value
from (values
  ('store_name', 'Tienda de prueba'),
  ('site_title', 'Tienda de prueba'),
  ('site_published', 'true'),
  ('store_url', 'https://tienda-prueba.example'),
  ('contact_address', 'Calle de Prueba 123, Viña del Mar, Chile'),
  ('contact_phone', '+56 9 0000 0000'),
  ('contact_email', 'contacto@example.invalid'),
  ('mercadopago_access_token', 'TEST-local-only'),
  ('payment_transfer_bank_name', 'Banco de Prueba'),
  ('payment_transfer_account_type', 'Cuenta corriente'),
  ('payment_transfer_account_number', '000000000'),
  ('payment_transfer_account_holder', 'Tienda de prueba SpA'),
  ('payment_transfer_rut', '11.111.111-1'),
  -- The store's look, so the page measures like vinabike.cl.
  ('theme_accent_color', '4294930176'),
  ('theme_background_color', '4294967295'),
  ('theme_body_font', 'Barlow'),
  ('theme_body_size', '16'),
  ('theme_container_padding', '24'),
  ('theme_heading_font', 'Oswald'),
  ('theme_heading_size', '48'),
  ('theme_primary_color', '4279385960'),
  ('theme_section_spacing', '64'),
  ('theme_text_color', '3707764736')
) as setting(key, value)
-- A new tenant comes with default settings: these replace them.
on conflict (tenant_id, key) do update set value = excluded.value;

commit;
