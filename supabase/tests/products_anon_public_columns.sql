begin;

select no_plan();

-- Anónimo lee el catálogo con las mismas consultas que la tienda, y nada más:
-- ni costo ni proveedor (20260923180000).

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1790000-0000-4000-8000-000000000001', 'Tienda anónima A',
   'anon-a@example.invalid', 'America/Santiago'),
  ('a1790000-0000-4000-8000-000000000002', 'Tienda anónima B',
   'anon-b@example.invalid', 'America/Santiago');

-- Sin stock controlado: el disparador de stock anota un ajuste con auth.uid().
insert into public.products (
  id, tenant_id, name, sku, price, cost, supplier_name, inventory_qty,
  stock_quantity, track_stock, is_service, purchase_treatment, is_active,
  is_published, show_on_website
) values
  ('a1790000-0000-4000-8000-000000000101',
   'a1790000-0000-4000-8000-000000000001', 'Cadena publicada', 'ANON-PUB',
   15000, 6000, 'Proveedor secreto', 0, 0, false, false, 'inventory', true,
   true, true),
  ('a1790000-0000-4000-8000-000000000102',
   'a1790000-0000-4000-8000-000000000001', 'Cadena en borrador', 'ANON-DRAFT',
   15000, 6000, 'Proveedor secreto', 0, 0, false, false, 'inventory', true,
   false, false),
  ('a1790000-0000-4000-8000-000000000201',
   'a1790000-0000-4000-8000-000000000002', 'Cadena de otra tienda', 'ANON-B',
   9000, 4000, 'Otro proveedor', 0, 0, false, false, 'inventory', true,
   true, true);

set local role anon;

select lives_ok($$
  select id,name,sku,barcode,price,inventory_qty,stock_quantity,image_url,
         image_url_optimized,image_urls,description,website_description,
         website_name,website_price,website_image_url,
         website_image_url_optimized,website_image_urls,website_seo_title,
         website_seo_description,website_search_terms,website_merchant_title,
         website_merchant_description,website_merchant_brand,
         website_merchant_gtin,website_merchant_mpn,
         website_google_product_category,category,category_id,category_name,
         brand_id,brand,model,manufacturer,manufacturer_sku,gtin,color,size,
         material,weight,specifications,product_type,track_stock,tax_rate,
         is_set,set_type,parent_set_id,component_label,component_position,
         is_active,is_published,show_on_website,created_at,updated_at
    from public.products
   where tenant_id = 'a1790000-0000-4000-8000-000000000001'
     and is_active and is_published and show_on_website
     and (product_type = 'service' or track_stock = false or stock_quantity > 0)
     and (name ilike '%cadena%' or sku ilike '%cadena%' or description ilike '%cadena%')
     and price >= 0 and price <= 100000
   order by name
$$, 'anónimo corre la consulta del catálogo de la tienda');

select lives_ok($$
  select id,is_set,set_type,parent_set_id,component_label,component_position,
         website_name,website_price,website_description,website_seo_title,
         website_seo_description,website_merchant_title,
         website_merchant_description,website_merchant_brand,
         website_merchant_gtin,website_merchant_mpn,
         website_google_product_category,price_currency
    from public.products
   where tenant_id = 'a1790000-0000-4000-8000-000000000001'
     and id in ('a1790000-0000-4000-8000-000000000101')
$$, 'anónimo corre la lectura de identidad pública');

select results_eq($$
  select sku from public.products
   where tenant_id = 'a1790000-0000-4000-8000-000000000001'
   order by sku
$$, array['ANON-PUB'::text],
  'el RLS sigue mostrando sólo lo publicado de la tienda pedida');

select throws_ok($$ select cost from public.products limit 1 $$, '42501',
  null, 'anónimo no lee el costo');
select throws_ok($$ select supplier_name from public.products limit 1 $$,
  '42501', null, 'anónimo no lee el proveedor');
select throws_ok($$ select * from public.products limit 1 $$, '42501', null,
  'anónimo no puede pedir todas las columnas');
select throws_ok($$ select id from public.products where cost > 0 $$, '42501',
  null, 'anónimo no puede filtrar por costo');
select throws_ok($$
  update public.products set price = 1
   where id = 'a1790000-0000-4000-8000-000000000101'
$$, '42501', null, 'anónimo no modifica productos');
select throws_ok($$
  delete from public.products
   where id = 'a1790000-0000-4000-8000-000000000101'
$$, '42501', null, 'anónimo no borra productos');

select lives_ok($$
  select * from public.search_public_products(
    'cadena', 'a1790000-0000-4000-8000-000000000001', 5)
$$, 'la búsqueda pública sigue respondiendo a anónimo');
select lives_ok($$
  select * from public.get_public_products_faceted_v2(
    'a1790000-0000-4000-8000-000000000001', null, null, null, false, null,
    null, null, null, null, 10, 0)
$$, 'el catálogo público por RPC sigue respondiendo a anónimo');

reset role;

select ok(has_column_privilege('authenticated', 'public.products', 'cost',
    'SELECT'),
  'el rol con sesión conserva el costo (lo usa el staff; se cierra aparte)');

select * from finish();
rollback;
