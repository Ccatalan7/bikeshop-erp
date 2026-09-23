begin;

select no_plan();

-- Un usuario con sesión sólo lee los productos de su empresa: una cuenta de
-- cliente no ve ninguno, y el staff ve los suyos, costo incluido
-- (20260923190000).

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Fixtures sin los disparadores de alta de empresa ni de stock.
set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('a17a0000-0000-4000-8000-000000000001', 'Tienda con sesión A',
   'sesion-a@example.invalid', 'America/Santiago', true),
  ('a17a0000-0000-4000-8000-000000000002', 'Tienda con sesión B',
   'sesion-b@example.invalid', 'America/Santiago', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a17a0000-0000-4000-8000-000000000081', 'authenticated', 'authenticated',
   'staff-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(),
   now()),
  ('a17a0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'cliente@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(),
   now());

insert into public.user_profiles (user_id, tenant_id, role, permissions,
  is_active)
values ('a17a0000-0000-4000-8000-000000000081',
  'a17a0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, supplier_name, inventory_qty,
  stock_quantity, track_stock, is_service, purchase_treatment, is_active,
  is_published, show_on_website
) values
  ('a17a0000-0000-4000-8000-000000000101',
   'a17a0000-0000-4000-8000-000000000001', 'Freno publicado A', 'SES-A-PUB',
   20000, 9000, 'Proveedor A', 0, 0, false, false, 'inventory', true, true,
   true),
  ('a17a0000-0000-4000-8000-000000000102',
   'a17a0000-0000-4000-8000-000000000001', 'Freno borrador A', 'SES-A-DRAFT',
   20000, 9000, 'Proveedor A', 0, 0, false, false, 'inventory', true, false,
   false),
  ('a17a0000-0000-4000-8000-000000000201',
   'a17a0000-0000-4000-8000-000000000002', 'Freno publicado B', 'SES-B-PUB',
   18000, 8000, 'Proveedor B', 0, 0, false, false, 'inventory', true, true,
   true);

set local session_replication_role = origin;

-- Cuenta de cliente: con sesión, sin perfil de staff.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a17a0000-0000-4000-8000-000000000091',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a17a0000-0000-4000-8000-000000000091', true);
set local role authenticated;

select is((select count(*)::int from public.products
  where sku like 'SES-%'), 0,
  'una cuenta de cliente no lee ningún producto de la tabla');
select is((select count(*)::int from public.products
  where sku like 'SES-%' and cost > 0), 0,
  'una cuenta de cliente no lee ningún costo');

reset role;

-- Staff de la empresa A.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a17a0000-0000-4000-8000-000000000081',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a17a0000-0000-4000-8000-000000000081', true);
set local role authenticated;

select results_eq($$
  select sku::text from public.products where sku like 'SES-%' order by sku
$$, array['SES-A-DRAFT', 'SES-A-PUB']::text[],
  'el staff lee sus productos, publicados o no, y no los publicados de otra empresa');
select is((select sum(cost)::int from public.products where sku like 'SES-A-%'),
  18000, 'el staff sigue leyendo el costo de sus productos');

reset role;

-- Anónimo sigue viendo el catálogo publicado.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

select results_eq($$
  select sku::text from public.products where sku like 'SES-%' order by sku
$$, array['SES-A-PUB', 'SES-B-PUB']::text[],
  'anónimo sigue leyendo lo publicado');

reset role;

select * from finish();
rollback;
