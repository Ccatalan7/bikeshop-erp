begin;

select no_plan();

-- Una sola regla decide qué se vende en la web (20261010010000). El
-- 2026-10-09 la tienda listaba consumibles del taller con «En stock»: la
-- política de stock dejaba pasar todo lo que no lleva stock.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Fixtures sin disparadores: el consumible marcado para la web es una fila
-- antigua, como las 130 que había antes de la guardia.
set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('ca7a0000-0000-4000-8000-000000000001', 'Tienda de la regla única',
  'regla@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values ('ca7a0000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy', 'available_only');

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, web_clearance_until,
  website_price_mode
) values
  ('ca7a0000-0000-4000-8000-000000000101', 'ca7a0000-0000-4000-8000-000000000001',
   'CADENA KMC', 'Cadena KMC', 'CA7A-101', 15000, 5000, 19, 'product', false,
   'inventory', true, 3, 3, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000102', 'ca7a0000-0000-4000-8000-000000000001',
   'Capuchón piola', 'Capuchón piola', 'CA7A-102', 4700, 2330, 19, 'product', false,
   'workshop_consumable', false, 0, 0, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000103', 'ca7a0000-0000-4000-8000-000000000001',
   'Mantención Básica', null, 'CA7A-103', 24990, 0, 19, 'service', true,
   'inventory', false, 0, 0, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000104', 'ca7a0000-0000-4000-8000-000000000001',
   'Extractor', 'Extractor de cono', 'CA7A-104', 29990, 26990, 19, 'product', false,
   'inventory', true, 1, 1, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000105', 'ca7a0000-0000-4000-8000-000000000001',
   'Liquidación', 'Pedales en liquidación', 'CA7A-105', 5000, 5000, 19, 'product', false,
   'inventory', true, 1, 1, true, true, true, current_date, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000106', 'ca7a0000-0000-4000-8000-000000000001',
   'CAMARA CST 26', null, 'CA7A-106', 9000, 1000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000107', 'ca7a0000-0000-4000-8000-000000000001',
   'Rodamiento sin stock', 'Rodamiento de dirección', 'CA7A-107', 3000, 300, 19, 'product', false,
   'inventory', true, 0, 0, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000108', 'ca7a0000-0000-4000-8000-000000000001',
   'Restauración a cotizar', null, 'CA7A-108', 0, 0, 19, 'service', true,
   'inventory', false, 0, 0, true, true, true, null, 'quote'),
  ('ca7a0000-0000-4000-8000-000000000109', 'ca7a0000-0000-4000-8000-000000000001',
   'Inflado de rueda', null, 'CA7A-109', 0, 0, 19, 'service', true,
   'inventory', false, 0, 0, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000110', 'ca7a0000-0000-4000-8000-000000000001',
   'Candado OnGuard', 'Candado OnGuard', '7290001283905', 14000, 5850, 19, 'product', false,
   'inventory', true, 1, 1, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000111', 'ca7a0000-0000-4000-8000-000000000001',
   'BETTABIKES', null, 'CA7A-111', 0, 0, null, 'product', false,
   'inventory', true, 0, 0, true, false, false, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000112', 'ca7a0000-0000-4000-8000-000000000001',
   'Bomba sin IVA', 'Bombín sin clasificar', 'CA7A-112', 9000, 1000, null, 'product', false,
   'inventory', true, 2, 2, true, true, true, null, 'exact'),
  ('ca7a0000-0000-4000-8000-000000000113', 'ca7a0000-0000-4000-8000-000000000001',
   'Diagnóstico', null, 'CA7A-113', 5000, 0, null, 'service', true,
   'inventory', false, 0, 0, true, false, false, null, 'exact');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ca7a0000-0000-4000-8000-000000000090', 'authenticated', 'authenticated',
  'regla-admin@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'ca7a0000-0000-4000-8000-000000000001'),
  now(), now()
), (
  'ca7a0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'regla-mecanico@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'ca7a0000-0000-4000-8000-000000000001'),
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values ('ca7a0000-0000-4000-8000-000000000090',
  'ca7a0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
       ('ca7a0000-0000-4000-8000-000000000091',
  'ca7a0000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb, true);

set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- La tienda
-- ---------------------------------------------------------------------------

set local role anon;

select results_eq($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_only_in_stock := true,
      p_limit := 100)
   order by sku
$$, $$ values
  ('7290001283905'::text), ('CA7A-101'), ('CA7A-103'), ('CA7A-105'),
  ('CA7A-106'), ('CA7A-108')
$$, 'la tienda lista lo vendible: ni el consumible, ni bajo el costo, ni sin IVA, ni el servicio a $0');

select is_empty($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_product_ids := array['ca7a0000-0000-4000-8000-000000000102']::uuid[],
      p_only_in_stock := false)
$$, 'un consumible del taller no tiene ficha aunque esté marcado para la web');

select is_empty($$
  select id
    from public.get_public_product_tax_classifications(
      'ca7a0000-0000-4000-8000-000000000001',
      array['ca7a0000-0000-4000-8000-000000000102',
            'ca7a0000-0000-4000-8000-000000000104']::uuid[])
$$, 'ni su clasificación pública, ni la del producto bajo el costo');

select results_eq($$
  select sku
    from public.get_public_products_faceted_v2(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_product_type := 'product',
      p_only_in_stock := true,
      p_limit := 100)
   order by sku
$$, $$ values ('7290001283905'::text), ('CA7A-101'), ('CA7A-105'), ('CA7A-106') $$,
  'el catálogo con filtros sigue la misma regla');

select is(
  public.get_public_product_page_v2(
    'ca7a0000-0000-4000-8000-000000000001', 'CA7A-108') -> 'product'
    ->> 'website_price_mode',
  'quote',
  'la ficha pública dice que el servicio se cotiza (20261010030000)');
select results_eq($$
  select website_price_mode
    from public.products
   where tenant_id = 'ca7a0000-0000-4000-8000-000000000001'
     and id = 'ca7a0000-0000-4000-8000-000000000103'
$$, $$ values ('exact'::text) $$,
  'anónimo lee el modo de precio con la identidad web');

reset role;

select throws_ok($$
  select public.create_public_online_order_unkeyed(
    jsonb_build_object(
      'tenant_id', 'ca7a0000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'ca7a0000-0000-4000-8000-0000000000aa',
      'customer_email', 'cliente@example.invalid',
      'customer_name', 'Cliente de prueba',
      'delivery_type', 'pickup',
      'payment_method', 'transfer'),
    jsonb_build_array(jsonb_build_object(
      'product_id', 'ca7a0000-0000-4000-8000-000000000102',
      'quantity', 1)))
$$, 'P0001', 'Product is unavailable: ca7a0000-0000-4000-8000-000000000102',
  'el checkout rechaza un consumible aunque llegue su id');

-- Con «nombre para la tienda» exigido, el que no lo tiene deja de salir.
insert into public.website_settings (tenant_id, key, value)
values ('ca7a0000-0000-4000-8000-000000000001',
  'product_visibility_require_web_name', 'true');

set local role anon;
select is_empty($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_sku := 'CA7A-106',
      p_only_in_stock := false)
$$, 'sin nombre para la tienda no sale cuando el ajuste lo pide');
select results_eq($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_sku := 'CA7A-103',
      p_only_in_stock := false)
$$, $$ values ('CA7A-103'::text) $$,
  'un servicio no necesita nombre web aparte');
reset role;

-- Con foto exigida, un producto sin foto deja de salir; un servicio no
-- (20261010040000: /servicios no muestra fotos).
insert into public.website_settings (tenant_id, key, value)
values ('ca7a0000-0000-4000-8000-000000000001',
  'product_visibility_require_image', 'true');

set local role anon;
select is_empty($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_sku := 'CA7A-101',
      p_only_in_stock := false)
$$, 'sin foto un producto no sale cuando el ajuste la pide');
select results_eq($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'ca7a0000-0000-4000-8000-000000000001',
      p_sku := 'CA7A-103',
      p_only_in_stock := false)
$$, $$ values ('CA7A-103'::text) $$,
  'un servicio sin foto sigue en /servicios');
reset role;

delete from public.website_settings
 where tenant_id = 'ca7a0000-0000-4000-8000-000000000001'
   and key = 'product_visibility_require_image';

-- ---------------------------------------------------------------------------
-- La guardia de los consumibles
-- ---------------------------------------------------------------------------

update public.products
   set show_on_website = false, is_published = false
 where id = 'ca7a0000-0000-4000-8000-000000000102';

select throws_ok($$
  update public.products
     set is_published = true, show_on_website = true
   where id = 'ca7a0000-0000-4000-8000-000000000102'
$$, '23514',
  'Es consumible del taller: conviértelo en producto de venta antes de venderlo en la web.',
  'un consumible no se marca para la web');

update public.products
   set purchase_treatment = 'workshop_consumable'
 where id = 'ca7a0000-0000-4000-8000-000000000107';

select ok(
  (select not is_published and not show_on_website
     from public.products where id = 'ca7a0000-0000-4000-8000-000000000107'),
  'al volverse consumible sale de la web');

update public.products
   set purchase_treatment = 'inventory', track_stock = true
 where id = 'ca7a0000-0000-4000-8000-000000000107';

-- ---------------------------------------------------------------------------
-- La pantalla del ERP
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'ca7a0000-0000-4000-8000-000000000090', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'ca7a0000-0000-4000-8000-000000000090', true);
set local role authenticated;

select results_eq($$
  select sku, kind, state, coalesce(block, '')
    from public.catalog_web_items_v1('ca7a0000-0000-4000-8000-000000000001')
   order by sku
$$, $$ values
  ('7290001283905'::text, 'product'::text, 'venta'::text, ''::text),
  ('CA7A-101', 'product', 'venta', ''),
  ('CA7A-102', 'consumable', 'taller', 'workshop_consumable'),
  ('CA7A-103', 'service', 'venta', ''),
  ('CA7A-104', 'product', 'falta', 'below_cost'),
  ('CA7A-105', 'product', 'venta', ''),
  ('CA7A-106', 'product', 'falta', 'missing_web_name'),
  ('CA7A-107', 'product', 'oculto', 'web_off'),
  ('CA7A-108', 'service', 'venta', ''),
  ('CA7A-109', 'service', 'falta', 'missing_price'),
  ('CA7A-111', 'product', 'oculto', 'web_off'),
  ('CA7A-112', 'product', 'falta', 'missing_tax'),
  ('CA7A-113', 'service', 'oculto', 'web_off')
$$, 'cada ítem con el estado y el motivo que usa la tienda');

select ok(
  (select 'gtin_in_sku' = any(issues)
     from public.catalog_web_items_v1('ca7a0000-0000-4000-8000-000000000001')
    where sku = '7290001283905'),
  'el código de barras guardado como SKU es un aviso');

select ok(
  (select 'empty_record' = any(issues)
     from public.catalog_web_items_v1('ca7a0000-0000-4000-8000-000000000001')
    where sku = 'CA7A-111'),
  'una ficha que no es producto es un aviso');

select is(
  (public.catalog_copy_sku_to_gtin_v1('ca7a0000-0000-4000-8000-000000000001') ->> 'copied')::integer,
  1, 'copiar el código de barras al GTIN toca sólo los válidos');

select is(
  (public.catalog_set_web_sale_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000102',
          'ca7a0000-0000-4000-8000-000000000106']::uuid[],
    true) ->> 'skipped_consumables')::integer,
  1, 'encender la venta salta al consumible y lo dice');

select is(
  public.catalog_set_web_sale_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000113']::uuid[], true)
    - 'skipped_consumables' - 'skipped_inactive',
  '{"changed": 1, "skipped_untaxed": 0}'::jsonb,
  'un servicio sin IVA se enciende: la regla no se lo pide (20261010050000)');

select is(
  (public.catalog_dismiss_issue_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    'ca7a0000-0000-4000-8000-000000000111', 'empty_record', true) ->> 'dismissed')::boolean,
  true, 'un aviso se puede dejar como está');

select ok(
  (select not ('empty_record' = any(issues))
     from public.catalog_web_items_v1('ca7a0000-0000-4000-8000-000000000001')
    where sku = 'CA7A-111'),
  'y deja de salir en «Por resolver»');

-- Un destacado nuevo pasa por la regla de venta (20261010060000).
select throws_ok($$
  select public.catalog_replace_featured_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000101',
          'ca7a0000-0000-4000-8000-000000000102']::uuid[])
$$, 'P0001',
  'Ya no se vende en la web: «Capuchón piola» (es consumible del taller). No se agregó a destacados.',
  'un consumible no entra a destacados');

select throws_ok($$
  select public.catalog_replace_featured_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000101',
          'ca7a0000-0000-4000-8000-000000000104']::uuid[])
$$, 'P0001',
  'Ya no se vende en la web: «Extractor de cono» (el precio quedó bajo el costo). No se agregó a destacados.',
  'uno bajo el costo tampoco, y dice por qué');

select is(
  (public.catalog_replace_featured_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000101']::uuid[]) ->> 'featured')::integer,
  1, 'uno a la venta entra');

reset role;
update public.products
   set show_on_website = false
 where id = 'ca7a0000-0000-4000-8000-000000000101';
set local role authenticated;

select is(
  (public.catalog_replace_featured_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000105',
          'ca7a0000-0000-4000-8000-000000000101']::uuid[]) ->> 'featured')::integer,
  2, 'el que ya estaba se conserva aunque hoy no se venda: la portada lo salta y vuelve solo');

select results_eq($$
  select product_id::text
    from public.featured_products
   where tenant_id = 'ca7a0000-0000-4000-8000-000000000001'
   order by order_index
$$, $$ values
  ('ca7a0000-0000-4000-8000-000000000105'::text),
  ('ca7a0000-0000-4000-8000-000000000101')
$$, 'en el orden pedido');

reset role;

-- Quien no puede editar los ajustes lee el catálogo, pero no lo cambia.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'ca7a0000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'ca7a0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select ok(
  (select count(*) > 0 from public.catalog_web_items_v1('ca7a0000-0000-4000-8000-000000000001')),
  'un mecánico ve el catálogo');
select throws_ok($$
  select public.catalog_set_web_sale_v1(
    'ca7a0000-0000-4000-8000-000000000001',
    array['ca7a0000-0000-4000-8000-000000000101']::uuid[], false)
$$, '42501', 'catalog_edit_forbidden', 'pero no apaga la venta');
select throws_ok($$
  select public.catalog_copy_sku_to_gtin_v1('ca7a0000-0000-4000-8000-000000000001')
$$, '42501', 'catalog_edit_forbidden', 'ni copia códigos');
select throws_ok($$
  select public.catalog_replace_featured_v1(
    'ca7a0000-0000-4000-8000-000000000001', array[]::uuid[])
$$, '42501', 'catalog_edit_forbidden', 'ni cambia los destacados');
reset role;

-- Otro tenant no lee este catálogo.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'ca7a0000-0000-4000-8000-000000000090', 'role', 'authenticated')::text, true);
set local role authenticated;
select throws_ok($$
  select * from public.catalog_web_items_v1('7e570000-0000-4000-8000-000000000001')
$$, '42501', 'catalog_tenant_forbidden', 'el catálogo de otro tenant está cerrado');
reset role;

select * from finish();
rollback;
