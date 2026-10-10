begin;

select no_plan();

-- One read per public page for the HTML storefront (20261004180000): the
-- product page and the shell compose the existing public reads, run as the
-- caller, and never cross tenants or reach a draft.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('b4a90000-0000-4000-8000-000000000001', 'Tienda de la ficha',
   'ficha@example.invalid', 'America/Santiago', true),
  ('b4a90000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value) values
  ('b4a90000-0000-4000-8000-000000000001', 'store_name', 'Tienda de la ficha'),
  ('b4a90000-0000-4000-8000-000000000001', 'product_visibility_stock_policy',
   'all');

insert into public.product_categories
  (id, tenant_id, name, full_path, is_active, show_on_website, description,
   image_url, sort_order)
values
  ('b4a90000-0000-4000-8000-000000000201',
   'b4a90000-0000-4000-8000-000000000001', 'Horquillas', 'Horquillas',
   true, true, 'Suspensiones delanteras',
   'https://example.com/horquillas.webp', 3),
  ('b4a90000-0000-4000-8000-000000000202',
   'b4a90000-0000-4000-8000-000000000001', 'Archivada', 'Archivada',
   false, true, null, null, 0);

insert into public.product_brands (id, tenant_id, name, is_active) values
  ('b4a90000-0000-4000-8000-000000000301', null, 'Suntour', true),
  ('b4a90000-0000-4000-8000-000000000302',
   'b4a90000-0000-4000-8000-000000000002', 'Marca de la otra tienda', true);

insert into public.website_navigation
  (id, tenant_id, menu_location, label, link_type, link_value, order_index,
   is_visible, css_class)
values
  ('b4a90000-0000-4000-8000-000000000401',
   'b4a90000-0000-4000-8000-000000000001', 'header', 'Productos', 'url',
   '/productos', 1, true, 'megamenu'),
  ('b4a90000-0000-4000-8000-000000000402',
   'b4a90000-0000-4000-8000-000000000001', 'header', 'Oculto', 'url',
   '/oculto', 2, false, null);

insert into public.website_pages (id, tenant_id, slug, title, is_published)
values
  ('b4a90000-0000-4000-8000-000000000501',
   'b4a90000-0000-4000-8000-000000000001', 'contacto', 'Contacto', true),
  ('b4a90000-0000-4000-8000-000000000502',
   'b4a90000-0000-4000-8000-000000000001', 'borrador', 'Borrador', false);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, category_id, brand_id, image_url,
  website_seo_title
) values
  ('b4a90000-0000-4000-8000-000000000101',
   'b4a90000-0000-4000-8000-000000000001', 'Horquilla de la ficha', 'PAG-1',
   550000, 300000, 'product', false, 'inventory', true, 2, 2, true, true,
   true, 'b4a90000-0000-4000-8000-000000000201',
   'b4a90000-0000-4000-8000-000000000301',
   'https://example.invalid/pag-1.jpg', 'Título SEO de la ficha'),
  -- Points at a brand of the other store: the read must not hand it out.
  ('b4a90000-0000-4000-8000-000000000102',
   'b4a90000-0000-4000-8000-000000000001', 'Horquilla vecina', 'PAG-2',
   180000, 90000, 'product', false, 'inventory', true, 1, 1, true, true,
   true, 'b4a90000-0000-4000-8000-000000000201',
   'b4a90000-0000-4000-8000-000000000302',
   'https://example.invalid/pag-2.jpg', null),
  ('b4a90000-0000-4000-8000-000000000103',
   'b4a90000-0000-4000-8000-000000000001', 'Horquilla en borrador',
   'PAG-BORR', 99000, 50000, 'product', false, 'inventory', true, 1, 1, true,
   false, false, 'b4a90000-0000-4000-8000-000000000201', null,
   'https://example.invalid/pag-3.jpg', null),
  ('b4a90000-0000-4000-8000-000000000105',
   'b4a90000-0000-4000-8000-000000000001', 'Horquilla con marca ajena',
   'PAG-AJENA', 120000, 60000, 'product', false, 'inventory', true, 1, 1,
   true, true, true, null, 'b4a90000-0000-4000-8000-000000000302',
   'https://example.invalid/pag-4.jpg', null),
  ('b4a90000-0000-4000-8000-000000000104',
   'b4a90000-0000-4000-8000-000000000002', 'Horquilla de la otra tienda',
   'PAG-OTRA', 1000, 500, 'product', false, 'inventory', true, 5, 5, true, true,
   true, null, null, 'https://example.invalid/otra.jpg', null);

-- Clasificados con IVA: sin clasificación un producto no se vende en la
-- web desde la regla única (20261010010000).
update public.products set tax_rate = 19
 where tenant_id::text like 'b4a9%' and tax_rate is null
   and coalesce(product_type, 'product') <> 'service';

update public.products
   set website_merchant_title = 'Título comercial de la vecina'
 where id = 'b4a90000-0000-4000-8000-000000000102';

set local session_replication_role = origin;

select is(
  (select p.prosecdef from pg_proc p
    where p.oid = to_regprocedure('public.get_public_product_page_v1(uuid,text)')),
  false,
  'la ficha corre como quien la pide (security invoker)');
select is(
  (select p.prosecdef from pg_proc p
    where p.oid = to_regprocedure('public.get_public_storefront_shell_v1(uuid)')),
  false,
  'lo compartido también');

set local role anon;

select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-1') #>> '{product,sku}',
  'PAG-1',
  'la ficha publicada se lee por SKU');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-1') #>> '{product,website_seo_title}',
  'Título SEO de la ficha',
  'con sus campos del sitio en la misma lectura');
select ok(
  not (public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'product') ? 'cost',
  'sin el costo');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-1') #>> '{brand_rows,0,name}',
  'Suntour',
  'con la fila de su marca para la regla del cliente');
select is(
  (select array_agg(item ->> 'sku' order by item ->> 'sku')
     from jsonb_array_elements(public.get_public_product_page_v1(
       'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'related') item),
  array['PAG-2'],
  'relacionados: los publicados con stock de su categoría, sin ella misma ni el borrador');
select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_public_product_page_v1(
      'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'related') item
     where item ? 'cost'),
  'los relacionados tampoco llevan costo');
select is(
  (select item ->> 'website_merchant_title'
     from jsonb_array_elements(public.get_public_product_page_v1(
       'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'related') item
    where item ->> 'sku' = 'PAG-2'),
  'Título comercial de la vecina',
  'un relacionado trae sus campos del sitio, como lo enriquece Flutter');
select is(
  (select array_agg(brand ->> 'name' order by brand ->> 'name')
     from jsonb_array_elements(public.get_public_product_page_v1(
       'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'brand_rows') brand),
  array['Suntour'],
  'sólo marcas de esta tienda o globales, aunque un relacionado apunte a una ajena');
select is(
  jsonb_array_length(public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-AJENA') -> 'brand_rows'),
  0,
  'la marca de otra tienda no viaja ni siquiera para el producto que la usa');
select is(
  jsonb_typeof(public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-1') -> 'specs'),
  'array',
  'la ficha técnica viaja como lista aunque esté vacía');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-BORR'),
  null,
  'un borrador no tiene página');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'NO-EXISTE'),
  null,
  'un SKU desconocido tampoco');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000001', 'PAG-OTRA'),
  null,
  'el producto de otra tienda no se lee pidiendo con esta');
select is(
  public.get_public_product_page_v1(
    'b4a90000-0000-4000-8000-000000000002', 'PAG-OTRA') #>> '{product,name}',
  'Horquilla de la otra tienda',
  'y sí con la suya');

select is(
  public.get_public_storefront_shell_v1(
    'b4a90000-0000-4000-8000-000000000001') #>> '{settings,store_name}',
  'Tienda de la ficha',
  'lo compartido trae los ajustes públicos');
select is(
  (select array_agg(item ->> 'label')
     from jsonb_array_elements(public.get_public_storefront_shell_v1(
       'b4a90000-0000-4000-8000-000000000001') -> 'navigation') item),
  array['Productos'],
  'sólo los menús visibles');
select is(
  (select item ->> 'css_class'
     from jsonb_array_elements(public.get_public_storefront_shell_v1(
       'b4a90000-0000-4000-8000-000000000001') -> 'navigation') item),
  'megamenu',
  'cada menú trae su clase, la que elige el panel ancho (20261006120000)');
select is(
  (select array_agg(item ->> 'slug')
     from jsonb_array_elements(public.get_public_storefront_shell_v1(
       'b4a90000-0000-4000-8000-000000000001') -> 'pages') item),
  array['contacto'],
  'sólo las páginas publicadas');
select is(
  (select array_agg(item ->> 'name')
     from jsonb_array_elements(public.get_public_storefront_shell_v1(
       'b4a90000-0000-4000-8000-000000000001') -> 'categories') item),
  array['Horquillas'],
  'sólo las categorías activas');
select is(
  (select item - 'id' - 'parent_id'
     from jsonb_array_elements(public.get_public_storefront_shell_v1(
       'b4a90000-0000-4000-8000-000000000001') -> 'categories') item),
  jsonb_build_object(
    'name', 'Horquillas', 'full_path', 'Horquillas', 'show_on_website', true,
    'description', 'Suspensiones delanteras',
    'image_url', 'https://example.com/horquillas.webp', 'sort_order', 3),
  'cada categoría trae su descripción, su imagen y su orden');
select is(
  jsonb_array_length(public.get_public_storefront_shell_v1(
    'b4a90000-0000-4000-8000-000000000002') -> 'navigation'),
  0,
  'los menús de una tienda no aparecen en otra');

reset role;

select * from finish();
rollback;
