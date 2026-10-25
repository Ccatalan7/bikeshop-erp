begin;

select no_plan();

-- Una búsqueda puede incluir lo agotado cuando la tienda lo ofrece
-- (20261024050000). El 2026-10-24 «camara fv» mostraba 3 de las 41 cámaras
-- francesas que la tienda publica: las otras 38 estaban en cero y la regla
-- de stock las saca de todo listado.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('a6070000-0000-4000-8000-000000000001', 'Tienda de los agotados',
  'agotados@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values ('a6070000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy', 'available_only');

insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, website_price_mode, category_name
) values
  ('a6070000-0000-4000-8000-000000000101', 'a6070000-0000-4000-8000-000000000001',
   'Cámara aro 26 válvula francesa 48 mm', 'A607-101', 5000, 1000, 19, 'product',
   false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras'),
  ('a6070000-0000-4000-8000-000000000102', 'a6070000-0000-4000-8000-000000000001',
   'Cámara aro 29 válvula francesa 48 mm', 'A607-102', 6000, 1000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact', 'Cámaras'),
  ('a6070000-0000-4000-8000-000000000103', 'a6070000-0000-4000-8000-000000000001',
   'Cámara aro 20 válvula francesa 48 mm', 'A607-103', 4000, 1000, 19, 'product',
   false, 'inventory', true, 0, 0, true, true, true, 'exact', 'Cámaras');

create function pg_temp.listed(p_term text, p_include boolean)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku), '{}')
  from public.get_public_products_faceted_v2(
    p_tenant_id := 'a6070000-0000-4000-8000-000000000001',
    p_search_term := p_term,
    p_only_in_stock := false,
    p_limit := 100,
    p_include_out_of_stock := p_include
  ) r
$$;

select is(
  pg_temp.listed('camara fv', false),
  array['A607-101'],
  'a search keeps the store''s rule: what is out of stock is not listed'
);
select is(
  pg_temp.listed('camara fv', true),
  array['A607-101', 'A607-102', 'A607-103'],
  '«Incluir agotados» lists the tubes at zero too'
);
-- 20261024060000: what can be bought first, though «aro 20» sorts before it.
select is(
  (select array_agg(r.sku)
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'a6070000-0000-4000-8000-000000000001',
       p_search_term := 'camara fv',
       p_only_in_stock := false,
       p_limit := 100,
       p_include_out_of_stock := true
     ) r),
  array['A607-101', 'A607-103', 'A607-102'],
  'what is in stock comes first, what is out of stock after it'
);
select is(
  pg_temp.listed(null, true),
  array['A607-101'],
  'without a term the rule is the same: only a search widens'
);
select is(
  (select r.item_count::integer
     from public.get_public_product_facets_v2(
       p_tenant_id := 'a6070000-0000-4000-8000-000000000001',
       p_search_term := 'camara fv',
       p_only_in_stock := false,
       p_include_out_of_stock := true
     ) r
    where r.facet_key = 'summary'),
  3,
  'the facets count what the widened search lists'
);
select is(
  (select coalesce(array_agg(r.sku order by r.sku), '{}')
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'a6070000-0000-4000-8000-000000000001',
       p_search_term := 'camara fv',
       p_only_in_stock := true,
       p_limit := 100,
       p_include_out_of_stock := true
     ) r),
  array['A607-101'],
  '«Sólo disponibles» still narrows a widened search'
);

insert into public.website_settings (tenant_id, key, value)
values ('a6070000-0000-4000-8000-000000000001',
  'product_visibility_search_out_of_stock', 'hide');

select is(
  pg_temp.listed('camara fv', true),
  array['A607-101'],
  'a store that does not offer it keeps them out even when asked'
);

select is(
  (select count(*)::integer
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'a6070000-0000-4000-8000-000000000001',
       p_search_term := 'camara fv',
       p_limit := 100
     )),
  1,
  'a caller that does not send the new parameter reads as before'
);

select ok(
  has_function_privilege('anon',
    'public.get_public_products_faceted_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text, integer, integer, boolean)',
    'execute')
  and has_function_privilege('anon',
    'public.get_public_product_facets_v2(uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean)',
    'execute'),
  'the public key can still read the catalog and its facets'
);

select * from finish();
rollback;
