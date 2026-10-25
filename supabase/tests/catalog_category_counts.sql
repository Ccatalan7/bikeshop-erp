begin;

select no_plan();

-- «Categorías» del catálogo cuenta en una pasada (20261025030000). El
-- 2026-10-25 la cuenta por categoría tardaba 8,1 s en producción y la
-- pantalla no abría: mismos números, ahora agrupados una vez.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('cc0a0000-0000-4000-8000-000000000001', 'Tienda de las cuentas',
  'cuentas@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values ('cc0a0000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy', 'available_only');

-- Componentes > Transmisión > Cadenas, y Accesorios suelto.
insert into public.product_categories
  (id, tenant_id, name, full_path, parent_id, level, is_active, show_on_website)
values
  ('cc0a0000-0000-4000-8000-000000000201', 'cc0a0000-0000-4000-8000-000000000001',
   'Componentes', 'Componentes', null, 0, true, true),
  ('cc0a0000-0000-4000-8000-000000000202', 'cc0a0000-0000-4000-8000-000000000001',
   'Transmisión', 'Componentes / Transmisión',
   'cc0a0000-0000-4000-8000-000000000201', 1, true, true),
  ('cc0a0000-0000-4000-8000-000000000203', 'cc0a0000-0000-4000-8000-000000000001',
   'Cadenas', 'Componentes / Transmisión / Cadenas',
   'cc0a0000-0000-4000-8000-000000000202', 2, true, false),
  ('cc0a0000-0000-4000-8000-000000000204', 'cc0a0000-0000-4000-8000-000000000001',
   'Accesorios', 'Accesorios', null, 0, true, true);

insert into public.products (
  id, tenant_id, category_id, name, website_name, sku, price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock, inventory_qty,
  stock_quantity, is_active, is_published, show_on_website,
  web_clearance_until, website_price_mode
) values
  ('cc0a0000-0000-4000-8000-000000000101', 'cc0a0000-0000-4000-8000-000000000001',
   'cc0a0000-0000-4000-8000-000000000203', 'Cadena KMC', 'Cadena KMC',
   'CC0A-101', 15000, 5000, 19, 'product', false, 'inventory', true, 3, 3,
   true, true, true, null, 'exact'),
  ('cc0a0000-0000-4000-8000-000000000102', 'cc0a0000-0000-4000-8000-000000000001',
   'cc0a0000-0000-4000-8000-000000000203', 'Cadena sin stock', 'Cadena 12v',
   'CC0A-102', 30000, 10000, 19, 'product', false, 'inventory', true, 0, 0,
   true, true, true, null, 'exact'),
  ('cc0a0000-0000-4000-8000-000000000103', 'cc0a0000-0000-4000-8000-000000000001',
   'cc0a0000-0000-4000-8000-000000000202', 'Cassette', 'Cassette 11v',
   'CC0A-103', 40000, 20000, 19, 'product', false, 'inventory', true, 2, 2,
   true, true, true, null, 'exact'),
  ('cc0a0000-0000-4000-8000-000000000104', 'cc0a0000-0000-4000-8000-000000000001',
   'cc0a0000-0000-4000-8000-000000000202', 'Bomba sin IVA', 'Bombín',
   'CC0A-104', 9000, 1000, null, 'product', false, 'inventory', true, 2, 2,
   true, true, true, null, 'exact'),
  ('cc0a0000-0000-4000-8000-000000000105', 'cc0a0000-0000-4000-8000-000000000001',
   'cc0a0000-0000-4000-8000-000000000204', 'Candado', 'Candado',
   'CC0A-105', 14000, 5850, 19, 'product', false, 'inventory', true, 1, 1,
   true, true, true, null, 'exact');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'cc0a0000-0000-4000-8000-000000000090', 'authenticated', 'authenticated',
  'cuentas-admin@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'cc0a0000-0000-4000-8000-000000000001'),
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values ('cc0a0000-0000-4000-8000-000000000090',
  'cc0a0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'cc0a0000-0000-4000-8000-000000000090', true);
select set_config('request.jwt.claims',
  '{"sub":"cc0a0000-0000-4000-8000-000000000090","role":"authenticated"}', true);
set local role authenticated;

select results_eq($$
  select name, subcategories
    from public.catalog_category_counts_v1('cc0a0000-0000-4000-8000-000000000001')
$$, $$ values
  ('Accesorios'::text, 0), ('Componentes', 2), ('Transmisión', 1), ('Cadenas', 0)
$$, 'cada categoría cuenta sus subcategorías, en el orden de su ruta');

-- The same numbers the per-category recount gave: every item of the
-- subtree by state, and the category's own items for sale.
select results_eq($$
  select category_id, selling, out_of_stock, needs_attention, selling_direct
    from public.catalog_category_counts_v1('cc0a0000-0000-4000-8000-000000000001')
   order by category_id
$$, $$
  with recursive cat as (
    select c.id, c.parent_id
      from public.product_categories c
     where c.tenant_id = 'cc0a0000-0000-4000-8000-000000000001'
       and c.is_active
  ), tree(root, id, depth) as (
    select cat.id, cat.id, 0 from cat
    union all
    select tree.root, child.id, tree.depth + 1
      from tree join cat child on child.parent_id = tree.id
  ), items as (
    select i.category_id, i.state
      from public.catalog_web_items_v1('cc0a0000-0000-4000-8000-000000000001') i
     where i.kind in ('product', 'kit')
  )
  select cat.id,
         (select count(*)::integer from tree t join items i on i.category_id = t.id
           where t.root = cat.id and i.state = 'venta'),
         (select count(*)::integer from tree t join items i on i.category_id = t.id
           where t.root = cat.id and i.state = 'agotado'),
         (select count(*)::integer from tree t join items i on i.category_id = t.id
           where t.root = cat.id and i.state = 'falta'),
         (select count(*)::integer from items i
           where i.category_id = cat.id and i.state = 'venta')
    from cat
   order by cat.id
$$, 'los estados del subárbol y lo propio a la venta, como la cuenta por categoría');

select ok(
  (select selling from public.catalog_category_counts_v1('cc0a0000-0000-4000-8000-000000000001')
    where name = 'Componentes') >= 1
  and (select selling_direct from public.catalog_category_counts_v1('cc0a0000-0000-4000-8000-000000000001')
    where name = 'Componentes') = 0,
  'la raíz suma lo que venden sus hijas y no tiene productos propios');

reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);

select throws_ok($$
  select * from public.catalog_category_counts_v1('cc0a0000-0000-4000-8000-000000000001')
$$, '42501', 'catalog_tenant_forbidden', 'sin sesión de la tienda no se lee');

select * from finish();

rollback;
