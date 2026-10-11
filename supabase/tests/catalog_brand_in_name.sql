begin;

select no_plan();

-- «La marca está en el nombre» (20261011010000). El 2026-10-11 dos llantas
-- Vision tenían de marca al distribuidor «Andes Industrial» y Google las
-- marcó sin identificador.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('b4a00000-0000-4000-8000-000000000001', 'Tienda de las marcas',
  'marcas@example.invalid', 'America/Santiago', true),
       ('b4a00000-0000-4000-8000-000000000002', 'Otra tienda',
  'otra@example.invalid', 'America/Santiago', true);

insert into public.product_brands (id, tenant_id, name, is_active) values
  ('b4a00000-0000-4000-8000-000000000201', null, 'Rinvision', true),
  ('b4a00000-0000-4000-8000-000000000202', null, 'Frenox', true),
  ('b4a00000-0000-4000-8000-000000000203', 'b4a00000-0000-4000-8000-000000000001', 'Tubotech', true),
  ('b4a00000-0000-4000-8000-000000000204', null, 'Brükner', true),
  ('b4a00000-0000-4000-8000-000000000205', null, 'Solitaria', true),
  ('b4a00000-0000-4000-8000-000000000206', 'b4a00000-0000-4000-8000-000000000002', 'Ajenatech', true)
on conflict (name) do nothing;
insert into public.product_brands (tenant_id, name, is_active)
values (null, 'Andes Industrial', true), (null, 'Doble', true)
on conflict (name) do nothing;

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, brand_id, brand, image_url
) values
  ('b4a00000-0000-4000-8000-000000000101', 'b4a00000-0000-4000-8000-000000000001',
   'LLANTA RINVISION 26', 'Llanta Rinvision aro 26 doble pared', 'B4A-101', 20000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true,
   (select id from public.product_brands where name = 'Andes Industrial'), 'Andes Industrial',
   'https://example.invalid/101.jpg'),
  ('b4a00000-0000-4000-8000-000000000102', 'b4a00000-0000-4000-8000-000000000001',
   'OLIVA', 'Oliva y pin para manguera Frenox BH59', 'B4A-102', 3000, 500, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, null,
   'https://example.invalid/102.jpg'),
  ('b4a00000-0000-4000-8000-000000000103', 'b4a00000-0000-4000-8000-000000000001',
   'LLANTA 29', 'Llanta aro 29 doble pared negra', 'B4A-103', 20000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, 'Genérico',
   'https://example.invalid/103.jpg'),
  ('b4a00000-0000-4000-8000-000000000104', 'b4a00000-0000-4000-8000-000000000001',
   'KIT', 'Kit Rinvision con frenos Frenox', 'B4A-104', 30000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, 'Taiwan',
   'https://example.invalid/104.jpg'),
  ('b4a00000-0000-4000-8000-000000000105', 'b4a00000-0000-4000-8000-000000000001',
   'CAMARA', 'Cámara Tubotech aro 26', 'B4A-105', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true,
   'b4a00000-0000-4000-8000-000000000203', 'Tubotech',
   'https://example.invalid/105.jpg'),
  ('b4a00000-0000-4000-8000-000000000106', 'b4a00000-0000-4000-8000-000000000001',
   'LLANTA RINVISION 700', 'Llanta Rinvision 700', 'B4A-106', 20000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, false, false, null, null,
   'https://example.invalid/106.jpg'),
  -- La marca escrita a mano y sin enlazar (20261011030000).
  ('b4a00000-0000-4000-8000-000000000107', 'b4a00000-0000-4000-8000-000000000001',
   'DISCO FRENOX', 'Disco de freno Frenox 160 mm', 'B4A-107', 9000, 2000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, 'Frenox',
   'https://example.invalid/107.jpg'),
  -- Una nota en el nombre del ERP no es la marca de la ficha.
  ('b4a00000-0000-4000-8000-000000000108', 'b4a00000-0000-4000-8000-000000000001',
   'CAMARA 26 (NO ES LA MISMA: TUBOTECH)', 'Cámara aro 26', 'B4A-108', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, null,
   'https://example.invalid/108.jpg'),
  -- Una marca escrita que dice otra cosa no se pisa.
  ('b4a00000-0000-4000-8000-000000000109', 'b4a00000-0000-4000-8000-000000000001',
   'LLANTA', 'Llanta Rinvision aro 27.5', 'B4A-109', 20000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, 'Tubotech',
   'https://example.invalid/109.jpg'),
  -- Sólo se sugiere una marca que la tienda ya usa (20261011040000): estas
  -- fichas, fuera de la web, son las que usan Rinvision, Frenox y Brükner.
  ('b4a00000-0000-4000-8000-000000000110', 'b4a00000-0000-4000-8000-000000000001',
   'LLANTA 29', 'Llanta Rinvision 29', 'B4A-110', 20000, 8000, 19,
   'product', false, 'inventory', true, 3, 3, true, false, false,
   'b4a00000-0000-4000-8000-000000000201', 'Rinvision', 'https://example.invalid/110.jpg'),
  ('b4a00000-0000-4000-8000-000000000111', 'b4a00000-0000-4000-8000-000000000001',
   'PASTILLAS', 'Pastillas Frenox', 'B4A-111', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, false, false,
   'b4a00000-0000-4000-8000-000000000202', 'Frenox', 'https://example.invalid/111.jpg'),
  ('b4a00000-0000-4000-8000-000000000113', 'b4a00000-0000-4000-8000-000000000001',
   'DISCO', 'Disco Brükner', 'B4A-113', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, false, false,
   'b4a00000-0000-4000-8000-000000000204', 'Brükner', 'https://example.invalid/113.jpg'),
  -- Sin acento en el nombre, con acento en la marca.
  ('b4a00000-0000-4000-8000-000000000112', 'b4a00000-0000-4000-8000-000000000001',
   'AMORTIGUADOR', 'Amortiguador Brukner 190 mm', 'B4A-112', 90000, 30000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, null,
   'https://example.invalid/112.jpg'),
  -- Una marca que ningún producto de la tienda usa no se sugiere.
  ('b4a00000-0000-4000-8000-000000000114', 'b4a00000-0000-4000-8000-000000000001',
   'CAMARA', 'Cámara Solitaria aro 26', 'B4A-114', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, null,
   'https://example.invalid/114.jpg'),
  -- «compatible con:» con puntuación sigue siendo compatibilidad.
  ('b4a00000-0000-4000-8000-000000000115', 'b4a00000-0000-4000-8000-000000000001',
   'ADAPTADOR', 'Adaptador compatible con: Frenox', 'B4A-115', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, null, null,
   'https://example.invalid/115.jpg');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'b4a00000-0000-4000-8000-000000000090', 'authenticated', 'authenticated',
  'marcas-admin@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'b4a00000-0000-4000-8000-000000000001'),
  now(), now()
), (
  'b4a00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'marcas-mecanico@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object('tenant_id', 'b4a00000-0000-4000-8000-000000000001'),
  now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values ('b4a00000-0000-4000-8000-000000000090',
  'b4a00000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
       ('b4a00000-0000-4000-8000-000000000091',
  'b4a00000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb, true);

set local session_replication_role = origin;

-- La lista de marcas que no son marca, la misma del núcleo público.
select ok(not public.catalog_is_public_brand_v1('Genérico'), 'Genérico no es marca');
select ok(not public.catalog_is_public_brand_v1(' andes industrial '), 'el distribuidor no es marca');
select ok(not public.catalog_is_public_brand_v1(null), 'nada no es marca');
select ok(public.catalog_is_public_brand_v1('Tubotech'), 'una marca sí');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'b4a00000-0000-4000-8000-000000000090', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'b4a00000-0000-4000-8000-000000000090', true);
set local role authenticated;

select results_eq($$
  select sku, coalesce(suggested_brand, ''),
         'brand_in_name' = any(issues), 'no_brand' = any(issues)
    from public.catalog_web_items_v1('b4a00000-0000-4000-8000-000000000001')
   order by sku
$$, $$ values
  ('B4A-101'::text, 'Rinvision'::text, true, false),
  ('B4A-102', '', false, true),
  ('B4A-103', '', false, true),
  ('B4A-104', '', false, true),
  ('B4A-105', '', false, false),
  ('B4A-106', '', false, false),
  ('B4A-107', 'Frenox', true, false),
  ('B4A-108', '', false, true),
  ('B4A-109', '', false, true),
  ('B4A-110', '', false, false),
  ('B4A-111', '', false, false),
  ('B4A-112', 'Brükner', true, false),
  ('B4A-113', '', false, false),
  ('B4A-114', '', false, true),
  ('B4A-115', '', false, true)
$$, 'sugiere sólo la marca real del nombre que se ve: no la de «para», ni «doble», ni una entre dos, ni lo que no se vende, ni contra una marca escrita');

create temporary table applied on commit drop as
select public.catalog_apply_brand_from_name_v1(
  'b4a00000-0000-4000-8000-000000000001',
  array['b4a00000-0000-4000-8000-000000000101',
        'b4a00000-0000-4000-8000-000000000102',
        'b4a00000-0000-4000-8000-000000000105']::uuid[]) -> 'changed' as changed;

select is(jsonb_array_length((select changed from applied)), 1,
  'usar la marca del nombre cambia sólo el que la tiene');

select is(
  (public.catalog_apply_brand_from_name_v1('b4a00000-0000-4000-8000-000000000001',
     array['b4a00000-0000-4000-8000-000000000107',
           'b4a00000-0000-4000-8000-000000000109']::uuid[]) -> 'changed' -> 0 ->> 'id'),
  'b4a00000-0000-4000-8000-000000000107',
  'enlaza la marca escrita a mano, y no pisa la que dice otra');

select is(
  (select brand_id from public.products where id = 'b4a00000-0000-4000-8000-000000000107'),
  'b4a00000-0000-4000-8000-000000000202'::uuid, 'el disco queda enlazado a Frenox');

select is(
  jsonb_array_length(public.catalog_apply_brand_from_name_v1(
    'b4a00000-0000-4000-8000-000000000001',
    array['b4a00000-0000-4000-8000-000000000106']::uuid[]) -> 'changed'),
  0, 'el comando no cambia lo que la lista no ofrece (fuera de la web)');

-- Un recibo armado a mano no enlaza la marca de otro tenant.
select is(
  (public.catalog_restore_brands_v1('b4a00000-0000-4000-8000-000000000001',
     jsonb_build_array(jsonb_build_object(
       'id', 'b4a00000-0000-4000-8000-000000000105',
       'brand_id', 'b4a00000-0000-4000-8000-000000000203',
       'brand', 'Tubotech',
       'previous_brand_id', 'b4a00000-0000-4000-8000-000000000206',
       'previous_brand', 'Ajenatech'))) ->> 'restored')::integer,
  0, 'deshacer no enlaza una marca de otro tenant');

create temporary table shock on commit drop as
select public.catalog_apply_brand_from_name_v1(
  'b4a00000-0000-4000-8000-000000000001',
  array['b4a00000-0000-4000-8000-000000000112']::uuid[]) -> 'changed' as changed;
reset role;
update public.products set brand = 'Brükner Pro'
 where id = 'b4a00000-0000-4000-8000-000000000112';
set local role authenticated;
select is(
  (public.catalog_restore_brands_v1('b4a00000-0000-4000-8000-000000000001',
     (select changed from shock)) ->> 'restored')::integer,
  0, 'deshacer no pisa un texto de marca corregido después');

select is(
  (select brand from public.products where id = 'b4a00000-0000-4000-8000-000000000101'),
  'Rinvision', 'y la llanta queda con su marca');

select is(
  (select changed -> 0 ->> 'previous_brand' from applied),
  'Andes Industrial', 'y guarda la anterior para deshacer');

select is(
  (public.catalog_restore_brands_v1('b4a00000-0000-4000-8000-000000000001',
     (select changed from applied)) ->> 'restored')::integer,
  1, 'deshacer la devuelve');

select is(
  (select brand from public.products where id = 'b4a00000-0000-4000-8000-000000000101'),
  'Andes Industrial', 'a la de antes');

-- Si alguien la cambió después, deshacer no la pisa.
update applied set changed = public.catalog_apply_brand_from_name_v1(
  'b4a00000-0000-4000-8000-000000000001',
  array['b4a00000-0000-4000-8000-000000000101']::uuid[]) -> 'changed';
reset role;
update public.products
   set brand_id = 'b4a00000-0000-4000-8000-000000000203', brand = 'Tubotech'
 where id = 'b4a00000-0000-4000-8000-000000000101';
set local role authenticated;
select is(
  (public.catalog_restore_brands_v1('b4a00000-0000-4000-8000-000000000001',
     (select changed from applied)) ->> 'restored')::integer,
  0, 'deshacer no pisa una marca puesta después');

select is(
  (public.catalog_dismiss_issue_v1('b4a00000-0000-4000-8000-000000000001',
     'b4a00000-0000-4000-8000-000000000104', 'brand_in_name', true) ->> 'dismissed')::boolean,
  true, 'el aviso se puede dejar como está');

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'b4a00000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'b4a00000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_ok($$
  select public.catalog_apply_brand_from_name_v1(
    'b4a00000-0000-4000-8000-000000000001',
    array['b4a00000-0000-4000-8000-000000000106']::uuid[])
$$, '42501', 'catalog_edit_forbidden', 'un mecánico no cambia marcas');
select throws_ok($$
  select public.catalog_restore_brands_v1('b4a00000-0000-4000-8000-000000000001', '[]'::jsonb)
$$, '42501', 'catalog_edit_forbidden', 'ni las deshace');
reset role;

select * from finish();
rollback;
