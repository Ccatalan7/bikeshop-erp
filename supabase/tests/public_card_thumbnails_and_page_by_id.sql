begin;

select no_plan();

-- 20261005130000: the record of card thumbnails is read only through its
-- function, per store and per photo asked about; the product page reads by
-- SKU or by id, and v1 is the same read by SKU.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('c4a90000-0000-4000-8000-000000000001', 'Tienda de las fotos',
   'fotos@example.invalid', 'America/Santiago', true),
  ('c4a90000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value) values
  ('c4a90000-0000-4000-8000-000000000001', 'product_visibility_stock_policy',
   'all');

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, image_url
) values
  ('c4a90000-0000-4000-8000-000000000101',
   'c4a90000-0000-4000-8000-000000000001', 'Rueda con SKU', 'RUE-1',
   90000, 40000, 'product', false, 'inventory', true, 2, 2, true, true, true,
   'https://example.invalid/rueda.jpg'),
  ('c4a90000-0000-4000-8000-000000000102',
   'c4a90000-0000-4000-8000-000000000001', 'Rueda sin SKU', null,
   80000, 40000, 'product', false, 'inventory', true, 1, 1, true, true, true,
   'https://example.invalid/rueda-sin-sku.jpg'),
  ('c4a90000-0000-4000-8000-000000000103',
   'c4a90000-0000-4000-8000-000000000001', 'Rueda en borrador', null,
   70000, 40000, 'product', false, 'inventory', true, 1, 1, true, false,
   false, 'https://example.invalid/borrador.jpg'),
  ('c4a90000-0000-4000-8000-000000000104',
   'c4a90000-0000-4000-8000-000000000002', 'Rueda de la otra tienda', null,
   1000, 500, 'product', false, 'inventory', true, 5, 5, true, true, true,
   'https://example.invalid/otra.jpg');

insert into public.public_image_thumbnails
  (tenant_id, source_url, source_signature, source_width, source_height,
   variants)
values
  ('c4a90000-0000-4000-8000-000000000001',
   'https://example.invalid/rueda.jpg', '"etag-1"', 1200, 900,
   '[{"width": 400, "height": 300, "url": "https://example.invalid/t/r-400.jpg"},
     {"width": 800, "height": 600, "url": "https://example.invalid/t/r-800.jpg"}]'),
  ('c4a90000-0000-4000-8000-000000000002',
   'https://example.invalid/rueda.jpg', '"etag-2"', 600, 600,
   '[{"width": 400, "height": 400, "url": "https://example.invalid/t/otra-400.jpg"}]');

set local session_replication_role = origin;

select is(
  (select p.prosecdef from pg_proc p
    where p.oid = to_regprocedure('public.get_public_product_page_v2(uuid,text,uuid)')),
  false,
  'la ficha v2 corre como quien la pide (security invoker)');
select is(
  (select p.proconfig from pg_proc p
    where p.oid = to_regprocedure('public.get_public_image_thumbnails_v1(uuid,text[])')),
  array['search_path=public, pg_temp'],
  'las miniaturas se leen con search_path fijo');
select throws_ok(
  $$insert into public.public_image_thumbnails
      (tenant_id, source_url, source_signature, source_width, source_height)
    values ('c4a90000-0000-4000-8000-000000000001', 'ftp://x/y.jpg', 'x', 1, 1)$$,
  '23514',
  null,
  'sólo fotos http(s)');

set local role anon;

select throws_ok(
  'select count(*) from public.public_image_thumbnails',
  '42501',
  null,
  'el registro no se lee directo');
select is(
  (select variants -> 1 ->> 'url'
     from public.get_public_image_thumbnails_v1(
       'c4a90000-0000-4000-8000-000000000001',
       array['https://example.invalid/rueda.jpg',
             'https://example.invalid/sin-miniatura.jpg'])),
  'https://example.invalid/t/r-800.jpg',
  'la foto pedida trae sus copias de su tienda');
select is(
  (select count(*)::int
     from public.get_public_image_thumbnails_v1(
       'c4a90000-0000-4000-8000-000000000001',
       array['https://example.invalid/rueda.jpg',
             'https://example.invalid/sin-miniatura.jpg'])),
  1,
  'una foto sin copias no aparece: su tarjeta usa la grande');
select is(
  (select source_width
     from public.get_public_image_thumbnails_v1(
       'c4a90000-0000-4000-8000-000000000002',
       array['https://example.invalid/rueda.jpg'])),
  600,
  'la misma URL en otra tienda es otro registro');
select is(
  (select count(*)::int
     from public.get_public_image_thumbnails_v1(
       'c4a90000-0000-4000-8000-000000000001',
       array_cat(array_fill('https://example.invalid/x.jpg'::text, array[200]),
                 array['https://example.invalid/rueda.jpg']))),
  0,
  'a lo más 200 fotos por pedido');

select is(
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001', 'RUE-1') #>> '{product,name}',
  'Rueda con SKU',
  'v2 lee por SKU');
select is(
  public.get_public_product_page_v1(
    'c4a90000-0000-4000-8000-000000000001', 'RUE-1'),
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001', 'RUE-1'),
  'v1 es la misma lectura por SKU');
select is(
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001',
    p_product_id := 'c4a90000-0000-4000-8000-000000000102') #>> '{product,name}',
  'Rueda sin SKU',
  'un producto sin SKU se lee por id');
select ok(
  not (public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001',
    p_product_id := 'c4a90000-0000-4000-8000-000000000102') -> 'product') ? 'cost',
  'sin el costo');
select is(
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001',
    p_product_id := 'c4a90000-0000-4000-8000-000000000103'),
  null,
  'un borrador no se lee por id');
select is(
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001',
    p_product_id := 'c4a90000-0000-4000-8000-000000000104'),
  null,
  'el producto de otra tienda no se lee por id pidiendo con esta');
select is(
  public.get_public_product_page_v2('c4a90000-0000-4000-8000-000000000001'),
  null,
  'sin SKU ni id no hay ficha (no la primera que aparezca)');
select is(
  public.get_public_product_page_v2(
    'c4a90000-0000-4000-8000-000000000001', '  '),
  null,
  'un SKU en blanco tampoco');

reset role;

select * from finish();
rollback;
