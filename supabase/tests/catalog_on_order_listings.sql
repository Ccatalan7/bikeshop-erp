begin;

select no_plan();

-- Lo que se vende a pedido entra a los listados de la tienda
-- (20261104091500). Hasta ese día un agotado con «Se vende a pedido» sólo se
-- veía en su ficha: la regla de stock (available_only) lo sacaba de la
-- categoría como a cualquier agotado, y la etapa 6 de cotizaciones necesitaba
-- que los Maxxis que TeknoBike trae se vieran al recorrer «Neumáticos».

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('a6080000-0000-4000-8000-000000000001', 'Tienda a pedido',
   'a-pedido@example.invalid', 'America/Santiago', true),
  ('a6080000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values
  ('a6080000-0000-4000-8000-000000000001', 'product_visibility_stock_policy', 'available_only'),
  ('a6080000-0000-4000-8000-000000000002', 'product_visibility_stock_policy', 'available_only');

insert into public.product_categories
  (id, tenant_id, name, full_path, parent_id, level, is_active, show_on_website)
values
  ('a6080000-0000-4000-8000-000000000201', 'a6080000-0000-4000-8000-000000000001',
   'Neumáticos', 'Neumáticos', null, 0, true, true),
  ('a6080000-0000-4000-8000-000000000202', 'a6080000-0000-4000-8000-000000000002',
   'Neumáticos', 'Neumáticos', null, 0, true, true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, website_price_mode, category_id, category_name
) values
  -- En stock, sin condiciones a pedido.
  ('a6080000-0000-4000-8000-000000000101', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 29 Alfa', 'A608-101', 30000, 10000, 19, 'product',
   false, 'inventory', true, 2, 2, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- Agotado y a pedido: entra después de lo que hay.
  ('a6080000-0000-4000-8000-000000000102', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 29 Beta', 'A608-102', 31000, 10000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- Agotado, sin condiciones: sigue fuera.
  ('a6080000-0000-4000-8000-000000000103', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 29 Gama', 'A608-103', 32000, 10000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- Agotado, con condiciones apagadas: sigue fuera.
  ('a6080000-0000-4000-8000-000000000104', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 29 Delta', 'A608-104', 33000, 10000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- En stock y a pedido: se lista una sola vez, con lo que hay.
  ('a6080000-0000-4000-8000-000000000105', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 27.5 Épsilon', 'A608-105', 34000, 10000, 19, 'product',
   false, 'inventory', true, 3, 3, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- A pedido pero fuera de la tienda: la regla única de venta online manda.
  ('a6080000-0000-4000-8000-000000000106', 'a6080000-0000-4000-8000-000000000001',
   'Neumático aro 29 Zeta', 'A608-106', 35000, 10000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, false, 'exact',
   'a6080000-0000-4000-8000-000000000201', 'Neumáticos'),
  -- De otra tienda, a pedido: nunca cruza.
  ('a6080000-0000-4000-8000-000000000107', 'a6080000-0000-4000-8000-000000000002',
   'Neumático aro 29 Ajeno', 'A608-107', 36000, 10000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact',
   'a6080000-0000-4000-8000-000000000202', 'Neumáticos');

create function pg_temp.listed(
  p_tenant uuid,
  p_term text,
  p_only boolean,
  p_include boolean,
  p_categories uuid[] default null
)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_faceted_v2(
    p_tenant_id := p_tenant,
    p_category_ids := p_categories,
    p_search_term := p_term,
    p_only_in_stock := p_only,
    p_limit := 100,
    p_include_out_of_stock := p_include
  ) r
$$;

-- Antes de marcar nada a pedido, la tienda lista sólo lo que hay.
select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', null, false, false),
  array['A608-105', 'A608-101'],
  'without anything on order the listing is what it was'
);
select is(
  public.catalog_on_order_product_ids_internal_v1('a6080000-0000-4000-8000-000000000001'),
  array[]::uuid[],
  'with no terms the helper answers an empty array'
);

insert into public.product_on_order_terms
  (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max, is_active)
values
  ('a6080000-0000-4000-8000-000000000102', 'a6080000-0000-4000-8000-000000000001', null, 3, 5, true),
  ('a6080000-0000-4000-8000-000000000104', 'a6080000-0000-4000-8000-000000000001', null, 3, 5, false),
  ('a6080000-0000-4000-8000-000000000105', 'a6080000-0000-4000-8000-000000000001', null, 3, 5, true),
  ('a6080000-0000-4000-8000-000000000106', 'a6080000-0000-4000-8000-000000000001', null, 3, 5, true),
  ('a6080000-0000-4000-8000-000000000107', 'a6080000-0000-4000-8000-000000000002', null, 3, 5, true);

select is(
  public.catalog_on_order_product_ids_internal_v1('a6080000-0000-4000-8000-000000000001'),
  array[
    'a6080000-0000-4000-8000-000000000102',
    'a6080000-0000-4000-8000-000000000105',
    'a6080000-0000-4000-8000-000000000106'
  ]::uuid[],
  'the helper answers the active terms of this shop only'
);

select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', null, false, false),
  array['A608-105', 'A608-101', 'A608-102'],
  'what is on order enters the listing, after what is in stock'
);
select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', null, false, false,
    array['a6080000-0000-4000-8000-000000000201']::uuid[]),
  array['A608-105', 'A608-101', 'A608-102'],
  'a category page lists it too'
);
select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', null, true, false),
  array['A608-105', 'A608-101'],
  '«Disponibles» still shows only what can be bought now'
);
select is(
  (select max(r.total_count)::integer
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := false,
       p_limit := 1
     ) r),
  3,
  'the page total counts what is on order'
);
select is(
  (select array_agg(r.sku)
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := false,
       p_limit := 1,
       p_offset := 2
     ) r),
  array['A608-102'],
  'paging reaches what is on order on the last page'
);
select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', 'neumatico', false, false),
  array['A608-105', 'A608-101', 'A608-102'],
  'a plain search lists what is on order too'
);

-- Una búsqueda ampliada: lo que hay, lo que llega a pedido, lo agotado.
select is(
  (select array_agg(r.sku order by r.sku)
     from (
       select r.sku, r.ordinality as pos
       from public.get_public_products_faceted_v2(
         p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
         p_search_term := 'neumatico',
         p_only_in_stock := false,
         p_limit := 100,
         p_include_out_of_stock := true
       ) with ordinality r
     ) r
    where r.pos <= 2),
  array['A608-101', 'A608-105'],
  'a widened search starts with what is in stock'
);
select is(
  (select r.sku
     from (
       select r.sku, r.ordinality as pos
       from public.get_public_products_faceted_v2(
         p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
         p_search_term := 'neumatico',
         p_only_in_stock := false,
         p_limit := 100,
         p_include_out_of_stock := true
       ) with ordinality r
     ) r
    where r.pos = 3),
  'A608-102',
  'then what is on order'
);
select is(
  (select array_agg(r.sku order by r.sku)
     from (
       select r.sku, r.ordinality as pos
       from public.get_public_products_faceted_v2(
         p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
         p_search_term := 'neumatico',
         p_only_in_stock := false,
         p_limit := 100,
         p_include_out_of_stock := true
       ) with ordinality r
     ) r
    where r.pos > 3),
  array['A608-103', 'A608-104'],
  'and what is out of stock last; the product off the store never appears'
);

-- Los filtros cuentan lo que el listado muestra.
select is(
  (select r.item_count::integer
     from public.get_public_product_facets_v2(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := false
     ) r
    where r.facet_key = 'summary'),
  3,
  'the facet summary counts what is on order'
);
select is(
  (select r.item_count::integer
     from public.get_public_product_facets_v2(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := false
     ) r
    where r.facet_key = 'category'
      and r.value_id = 'a6080000-0000-4000-8000-000000000201'),
  3,
  'the category option counts what is on order'
);
select is(
  (select r.item_count::integer
     from public.get_public_product_facets_v2(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := true
     ) r
    where r.facet_key = 'summary'),
  2,
  'with «Disponibles» the facets count only what is in stock'
);
select is(
  (select r.item_count::integer
     from public.get_public_search_category_counts_v1(
       'a6080000-0000-4000-8000-000000000001', 'neumatico', false) r
    where r.category_id = 'a6080000-0000-4000-8000-000000000201'),
  3,
  'the search category counts match the search listing'
);
select is(
  (select r.item_count::integer
     from public.get_public_search_category_counts_v1(
       'a6080000-0000-4000-8000-000000000001', 'neumatico', true) r
    where r.category_id = 'a6080000-0000-4000-8000-000000000201'),
  5,
  'a widened search counts each product once'
);

-- La otra tienda ve sólo lo suyo.
select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000002', null, false, false),
  array['A608-107'],
  'another shop lists its own product on order, and nothing of this one'
);

-- Lo que no cambia.
select is(
  (select count(*)::integer
     from public.get_public_products(
       p_tenant_id := 'a6080000-0000-4000-8000-000000000001',
       p_only_in_stock := true,
       p_limit := 100
     )),
  2,
  'get_public_products (cart, featured, Merchant) keeps its rule'
);

update public.product_on_order_terms
   set is_active = false
 where tenant_id = 'a6080000-0000-4000-8000-000000000001';

select is(
  pg_temp.listed('a6080000-0000-4000-8000-000000000001', null, false, false),
  array['A608-105', 'A608-101'],
  'turning the terms off takes it out again'
);

select ok(
  not has_function_privilege('anon',
    'public.catalog_on_order_product_ids_internal_v1(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.catalog_on_order_product_ids_internal_v1(uuid)', 'execute')
  and not has_function_privilege('service_role',
    'public.catalog_on_order_product_ids_internal_v1(uuid)', 'execute'),
  'the helper is private'
);
select ok(
  has_function_privilege('anon',
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)',
    'execute')
  and has_function_privilege('anon',
    'public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean)',
    'execute')
  and has_function_privilege('anon',
    'public.get_public_search_category_counts_v1(uuid, text, boolean)',
    'execute'),
  'the public key can still read the catalog, its facets and its counts'
);
select ok(
  not has_function_privilege('service_role',
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)',
    'execute'),
  'the listing stays a visitor read'
);

select * from finish();
rollback;
