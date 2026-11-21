begin;

select no_plan();

-- Modelos con tallas y colores (20261120230000). Un modelo junta productos
-- que son tallas o colores de lo mismo; la tienda lo pide con p_group_models
-- y, sin el parámetro, todo responde lo mismo que antes.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone, is_active) values
  ('c1a00000-0000-4000-8000-000000000001', 'Taller variantes', 'CLP', 'America/Santiago', true),
  ('c1a00000-0000-4000-8000-000000000002', 'Otro taller variantes', 'CLP', 'America/Santiago', true);

-- Crear una tienda deja su id en la sesión (lo siembra «como» ella): se
-- limpia después, como en customer_quote_sold_out_offer.sql.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c1a00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-variantes@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c1a00000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c1a00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'caja-variantes@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c1a00000-0000-4000-8000-000000000001"}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c1a00000-0000-4000-8000-000000000091', 'c1a00000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c1a00000-0000-4000-8000-000000000091', 'c1a00000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('c1a00000-0000-4000-8000-000000000092', 'c1a00000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true);

-- Crear la tienda siembra sus ajustes del sitio; la regla de stock queda
-- explícita.
insert into public.website_settings (tenant_id, key, value) values
  ('c1a00000-0000-4000-8000-000000000001', 'product_visibility_stock_policy', 'available_only')
on conflict (tenant_id, key) do update set value = excluded.value;

insert into public.product_categories
  (id, tenant_id, name, full_path, parent_id, level, is_active, show_on_website)
values
  ('c1a00000-0000-4000-8000-000000000201', 'c1a00000-0000-4000-8000-000000000001',
   'Protecciones', 'Protecciones', null, 0, true, true),
  ('c1a00000-0000-4000-8000-000000000202', 'c1a00000-0000-4000-8000-000000000002',
   'Protecciones', 'Protecciones', null, 0, true, true);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, is_active, is_published,
  show_on_website, website_price_mode, category_id, category_name
) values
  -- La rodillera: dos colores y tres tallas, cuatro variantes que existen.
  ('c1a00000-0000-4000-8000-000000000101', 'c1a00000-0000-4000-8000-000000000001',
   'Rodillera Varia 5.0 Blanco/Negro S/M', 'VAR-101', 65990, 30000, 19, 'product',
   false, true, 2, 2, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  ('c1a00000-0000-4000-8000-000000000102', 'c1a00000-0000-4000-8000-000000000001',
   'Rodillera Varia 5.0 Blanco/Negro L/XL', 'VAR-102', 65990, 30000, 19, 'product',
   false, true, 0, 0, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  ('c1a00000-0000-4000-8000-000000000103', 'c1a00000-0000-4000-8000-000000000001',
   'Rodillera Varia 5.0 Blanco/Negro XXL', 'VAR-103', 65990, 30000, 19, 'product',
   false, true, 1, 1, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  ('c1a00000-0000-4000-8000-000000000104', 'c1a00000-0000-4000-8000-000000000001',
   'Rodillera Varia 5.0 Negra XXL', 'VAR-104', 67990, 30000, 19, 'product',
   false, true, 3, 3, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  -- Una talla que la tienda no muestra: nunca se nombra afuera.
  ('c1a00000-0000-4000-8000-000000000105', 'c1a00000-0000-4000-8000-000000000001',
   'Rodillera Varia 5.0 Negra S/M', 'VAR-105', 67990, 30000, 19, 'product',
   false, true, 4, 4, true, true, false, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  -- El guante: dos tallas en stock.
  ('c1a00000-0000-4000-8000-000000000111', 'c1a00000-0000-4000-8000-000000000001',
   'Guante Varia Grip M', 'VAR-111', 29990, 12000, 19, 'product',
   false, true, 5, 5, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  ('c1a00000-0000-4000-8000-000000000112', 'c1a00000-0000-4000-8000-000000000001',
   'Guante Varia Grip L', 'VAR-112', 31990, 12000, 19, 'product',
   false, true, 5, 5, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  -- Suelto, en la misma categoría.
  ('c1a00000-0000-4000-8000-000000000121', 'c1a00000-0000-4000-8000-000000000001',
   'Codera Varia Lite', 'VAR-121', 39990, 15000, 19, 'product',
   false, true, 2, 2, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000201', 'Protecciones'),
  -- Un servicio no es variante.
  ('c1a00000-0000-4000-8000-000000000131', 'c1a00000-0000-4000-8000-000000000001',
   'Ajuste de protecciones', 'VAR-131', 5000, 0, 19, 'service',
   true, false, 0, 0, true, true, false, 'exact', null, null),
  -- De otra tienda.
  ('c1a00000-0000-4000-8000-000000000141', 'c1a00000-0000-4000-8000-000000000002',
   'Rodillera Varia 5.0 Ajena', 'VAR-141', 65990, 30000, 19, 'product',
   false, true, 2, 2, true, true, true, 'exact',
   'c1a00000-0000-4000-8000-000000000202', 'Protecciones');
select set_config('request.jwt.claim.role', '', true);

-- Las tablas son privadas: sólo sus funciones las leen y escriben.
select ok(
  not has_table_privilege('anon', 'public.product_models', 'SELECT')
  and not has_table_privilege('authenticated', 'public.product_models', 'SELECT')
  and not has_table_privilege('authenticated', 'public.product_model_members', 'INSERT')
  and not has_table_privilege('service_role', 'public.product_model_members', 'SELECT')
  and has_function_privilege('anon', 'public.get_public_product_model_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('anon', 'public.get_public_product_models_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.product_model_summaries_internal_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.product_model_summaries_internal_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.product_model_save_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.product_model_save_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.get_merchant_product_models_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_merchant_product_models_v1(uuid, uuid[])', 'EXECUTE'),
  'the tables are private; the store reads models, the team saves them, the feed reads groups');

-- Una sola versión de cada lectura de la tienda, con el parámetro nuevo.
select is(
  (select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('get_public_products_faceted_v2', 'get_public_product_facets_v2',
                        'get_public_search_category_counts_v1', 'get_public_product_page_v2')),
  4,
  'adding p_group_models replaced each store read instead of duplicating it');

-- Antes de armar modelos, el listado agrupado es el de siempre.
create function pg_temp.listed(p_group boolean, p_only boolean default true)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku), '{}')
  from public.get_public_products_faceted_v2(
    p_tenant_id := 'c1a00000-0000-4000-8000-000000000001',
    p_category_ids := array['c1a00000-0000-4000-8000-000000000201'::uuid],
    p_only_in_stock := p_only,
    p_limit := 100,
    p_group_models := p_group
  ) r
$$;

select is(
  pg_temp.listed(true),
  pg_temp.listed(false),
  'with no models, grouping lists the same products');

-- La caja no arma modelos.
select set_config('request.jwt.claims', '{"sub":"c1a00000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c1a00000-0000-4000-8000-000000000092', true);
set local role authenticated;
select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Rodillera Varia 5.0","axes":[{"name":"Talla","values":["S/M"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000101","options":{"Talla":"S/M"}}]}'::jsonb)$$,
  '42501', 'catalog_edit_forbidden',
  'the cashier cannot group products');
reset role;

-- Administración sí.
select set_config('request.jwt.claims', '{"sub":"c1a00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c1a00000-0000-4000-8000-000000000091', true);
set local role authenticated;

select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Rodillera Varia 5.0","axes":[{"name":"Talla","values":["S/M"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000141","options":{"Talla":"S/M"}}]}'::jsonb)$$,
  '22023', 'product_model_member_invalid',
  'a product of another shop is not a variant');
select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Ajustes","axes":[{"name":"Talla","values":["S/M"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000131","options":{"Talla":"S/M"}}]}'::jsonb)$$,
  '22023', 'product_model_member_invalid',
  'a service is not a variant');
select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Rodillera Varia 5.0","axes":[{"name":"Talla","values":["S/M"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000101","options":{"Talla":"M"}}]}'::jsonb)$$,
  '22023', 'product_model_member_invalid',
  'an option that is not among the axis values is refused');
select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Rodillera Varia 5.0","axes":[{"name":"Talla","values":["S/M","S/M "]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000101","options":{"Talla":"S/M"}}]}'::jsonb)$$,
  '22023', 'product_model_invalid',
  'an axis cannot repeat a value, spaces aside');
select throws_ok(
  $$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Rodillera Varia 5.0","axes":[{"name":"Talla","values":["S/M","XXL"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000101","options":{"Talla":"S/M"}},
                 {"product_id":"c1a00000-0000-4000-8000-000000000103","options":{"Talla":" S/M"}}]}'::jsonb)$$,
  '23505', 'product_model_duplicate_options',
  'two variants cannot be the same combination');

-- La rodillera: Color × Talla, cinco variantes (una que la tienda no muestra).
create temp table saved_model on commit drop as
select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
  '{"name":"  Rodillera Varia 5.0 ",
    "axes":[{"name":"Color","values":["Blanco/Negro","Negra"]},
            {"name":"Talla","values":["S/M","L/XL","XXL"]}],
    "members":[
      {"product_id":"c1a00000-0000-4000-8000-000000000101","options":{"Color":"Blanco/Negro","Talla":"S/M"}},
      {"product_id":"c1a00000-0000-4000-8000-000000000102","options":{"Color":"Blanco/Negro","Talla":"L/XL"}},
      {"product_id":"c1a00000-0000-4000-8000-000000000103","options":{"Color":"Blanco/Negro","Talla":"XXL"}},
      {"product_id":"c1a00000-0000-4000-8000-000000000104","options":{"Color":"Negra","Talla":"XXL"}},
      {"product_id":"c1a00000-0000-4000-8000-000000000105","options":{"Color":"Negra","Talla":"S/M"}}]}'::jsonb) as doc;

select is(
  (select doc ->> 'name' from saved_model),
  'Rodillera Varia 5.0',
  'the model is saved with its name trimmed');
select is(
  (select jsonb_array_length(doc -> 'members') from saved_model),
  5,
  'the team sees every variant, the hidden one too');
select is(
  (select doc -> 'members' -> 3 -> 'options' from saved_model),
  '{"Color":"Negra","Talla":"XXL"}'::jsonb,
  'each variant keeps its options, in the order given');

-- El guante en otro modelo, y la rodillera no puede robarle una talla.
select isnt(
  public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    '{"name":"Guante Varia Grip","axes":[{"name":"Talla","values":["M","L"]}],
      "members":[{"product_id":"c1a00000-0000-4000-8000-000000000111","options":{"Talla":"M"}},
                 {"product_id":"c1a00000-0000-4000-8000-000000000112","options":{"Talla":"L"}}]}'::jsonb),
  null,
  'the glove is its own model');
select throws_ok(
  format($$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    jsonb_build_object('id', %L, 'name', 'Rodillera Varia 5.0',
      'axes', '[{"name":"Talla","values":["M"]}]'::jsonb,
      'members', '[{"product_id":"c1a00000-0000-4000-8000-000000000111","options":{"Talla":"M"}}]'::jsonb))$$,
    (select doc ->> 'id' from saved_model)),
  '23505', 'product_model_member_taken',
  'a product already in another model is not taken silently');

-- Dos personas no se pisan: con un updated_at viejo, se niega.
select throws_ok(
  format($$select public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    (select doc from saved_model) || jsonb_build_object('updated_at', %L))$$,
    '2020-01-01T00:00:00+00:00'),
  '40001', 'product_model_stale',
  'a save based on an old read is refused');

select is(
  public.product_model_for_product_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000104') ->> 'id',
  (select doc ->> 'id' from saved_model),
  'any variant opens its model in the ERP');
select is(
  public.product_model_for_product_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000121'),
  null,
  'a loose product has no model');
select ok(
  exists (
    select 1 from public.product_model_candidates_v1(
      'c1a00000-0000-4000-8000-000000000001', 'c1a00000-0000-4000-8000-000000000121', 'grip')
     where sku = 'VAR-112' and model_name = 'Guante Varia Grip'),
  'the candidates say which ones are already in a model');
reset role;

-- La ficha, como la ve un visitante.
set local role anon;
select is(
  public.get_public_product_model_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000102') -> 'axes' -> 1 ->> 'name',
  'Talla',
  'the store reads the model axes in order');
select is(
  (select array_agg(v.value ->> 'sku' order by v.ordinality)
     from jsonb_array_elements(public.get_public_product_model_v1(
            'c1a00000-0000-4000-8000-000000000001',
            'c1a00000-0000-4000-8000-000000000102') -> 'variants')
            with ordinality v(value, ordinality)),
  array['VAR-101', 'VAR-102', 'VAR-103', 'VAR-104'],
  'the store sees every variant it shows, sold out included, and never the hidden one');
select ok(
  (select bool_and(v ? 'stock_quantity' and v ? 'website_price' and v ? 'options' and not v ? 'cost')
     from jsonb_array_elements(public.get_public_product_model_v1(
            'c1a00000-0000-4000-8000-000000000001',
            'c1a00000-0000-4000-8000-000000000101') -> 'variants') v),
  'each variant has the shape of a store product, without its cost');
select is(
  public.get_public_product_model_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000105'),
  null,
  'a hidden variant does not reveal its model');
select is(
  public.get_public_product_model_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000121'),
  null,
  'a loose product has no model in the store');
select is(
  (select count(*)::integer from public.get_public_product_models_v1(
     'c1a00000-0000-4000-8000-000000000001', '{}'::uuid[])),
  0,
  'an empty list asks nothing (the canonical read would answer the whole catalog)');
select is(
  (select array_agg(product_id::text order by product_id) from public.get_public_product_models_v1(
     'c1a00000-0000-4000-8000-000000000001',
     array['c1a00000-0000-4000-8000-000000000101', 'c1a00000-0000-4000-8000-000000000105',
           'c1a00000-0000-4000-8000-000000000121']::uuid[])),
  array['c1a00000-0000-4000-8000-000000000101'],
  'the card summary names only what the store shows and only what is grouped');
select is(
  (select axes from public.get_public_product_models_v1(
     'c1a00000-0000-4000-8000-000000000001',
     array['c1a00000-0000-4000-8000-000000000101']::uuid[])),
  '[{"name":"Color","count":2},{"name":"Talla","count":3}]'::jsonb,
  'the summary counts the values the store shows: 2 colors, 3 sizes');

-- El listado sin el parámetro no cambia; con él, una tarjeta por modelo.
select is(
  pg_temp.listed(false),
  array['VAR-101', 'VAR-103', 'VAR-104', 'VAR-111', 'VAR-112', 'VAR-121'],
  'without p_group_models the listing is what it was');
-- Lo representa la que se vende primero en el orden de la búsqueda (por
-- nombre: «Guante Varia Grip L» antes que «… M»).
select is(
  pg_temp.listed(true),
  array['VAR-101', 'VAR-112', 'VAR-121'],
  'with p_group_models each model is one card');
select is(
  (select r.model_summary from public.get_public_products_faceted_v2(
     p_tenant_id := 'c1a00000-0000-4000-8000-000000000001',
     p_limit := 100, p_group_models := true) r where r.sku = 'VAR-101'),
  '{"variants":4,"axes":[{"name":"Color","count":2},{"name":"Talla","count":3}],"priceMin":65990,"priceMax":67990}'::jsonb,
  'the card carries the model summary');
select is(
  (select r.total_count from public.get_public_products_faceted_v2(
     p_tenant_id := 'c1a00000-0000-4000-8000-000000000001',
     p_limit := 1, p_group_models := true) r),
  3::bigint,
  'the page count is in models');
select ok(
  (select bool_and(r.model_id is null and r.model_summary is null)
     from public.get_public_products_faceted_v2(
       p_tenant_id := 'c1a00000-0000-4000-8000-000000000001',
       p_limit := 100) r),
  'without p_group_models the new columns are empty');
select is(
  (select item_count from public.get_public_product_facets_v2(
     p_tenant_id := 'c1a00000-0000-4000-8000-000000000001', p_group_models := true)
    where facet_key = 'category' and value_id = 'c1a00000-0000-4000-8000-000000000201'),
  3::bigint,
  'the category filter counts models');
select is(
  (select item_count from public.get_public_product_facets_v2(
     p_tenant_id := 'c1a00000-0000-4000-8000-000000000001')
    where facet_key = 'category' and value_id = 'c1a00000-0000-4000-8000-000000000201'),
  6::bigint,
  'without p_group_models the filter counts products, as before');
select is(
  (select item_count from public.get_public_search_category_counts_v1(
     'c1a00000-0000-4000-8000-000000000001', 'varia', false, true)
    where category_id = 'c1a00000-0000-4000-8000-000000000201'),
  3::bigint,
  'a search counts models when grouped');
select is(
  (select item_count from public.get_public_search_category_counts_v1(
     'c1a00000-0000-4000-8000-000000000001', 'varia', false)
    where category_id = 'c1a00000-0000-4000-8000-000000000201'),
  6::bigint,
  'and products without the parameter');

-- La ficha completa: sin el parámetro, la de siempre.
select ok(
  not (public.get_public_product_page_v2('c1a00000-0000-4000-8000-000000000001', 'VAR-101') ? 'model'),
  'without p_group_models the page has no model key');
select is(
  (select array_agg(r ->> 'sku' order by r ->> 'sku')
     from jsonb_array_elements(public.get_public_product_page_v2(
       'c1a00000-0000-4000-8000-000000000001', 'VAR-101') -> 'related') r),
  array['VAR-103', 'VAR-104', 'VAR-111', 'VAR-112', 'VAR-121'],
  'without p_group_models the related products are what they were');
select is(
  (select jsonb_array_length(public.get_public_product_page_v2(
     'c1a00000-0000-4000-8000-000000000001', 'VAR-101', null, true) -> 'model' -> 'variants')),
  4,
  'with p_group_models the page carries its model');
select is(
  (select array_agg(r ->> 'sku' order by r ->> 'sku')
     from jsonb_array_elements(public.get_public_product_page_v2(
       'c1a00000-0000-4000-8000-000000000001', 'VAR-101', null, true) -> 'related') r),
  array['VAR-112', 'VAR-121'],
  'with p_group_models the related skip the other sizes and keep one per model');
select is(
  (select r -> 'model_summary' ->> 'variants'
     from jsonb_array_elements(public.get_public_product_page_v2(
       'c1a00000-0000-4000-8000-000000000001', 'VAR-101', null, true) -> 'related') r
    where r ->> 'sku' = 'VAR-112'),
  '2',
  'a related model carries its card summary');
reset role;

-- Google Merchant: el grupo de cada producto del feed.
select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
select is(
  (select count(distinct model_id)::integer from public.get_merchant_product_models_v1(
     'c1a00000-0000-4000-8000-000000000001',
     array['c1a00000-0000-4000-8000-000000000101', 'c1a00000-0000-4000-8000-000000000104',
           'c1a00000-0000-4000-8000-000000000111']::uuid[])),
  2,
  'the feed reads one group per model');
select is(
  (select count(*)::integer from public.get_merchant_product_models_v1(
     'c1a00000-0000-4000-8000-000000000002',
     array['c1a00000-0000-4000-8000-000000000101']::uuid[])),
  0,
  'another shop never reads this shop''s groups');
reset role;
select set_config('request.jwt.claim.role', '', true);

-- Desarmar: dejar fuera una variante la suelta; un modelo vacío se borra.
select set_config('request.jwt.claims', '{"sub":"c1a00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c1a00000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  jsonb_array_length(public.product_model_save_v1('c1a00000-0000-4000-8000-000000000001',
    (select doc - 'members' from saved_model)
      || jsonb_build_object('members', (select jsonb_agg(m) from jsonb_array_elements(
           (select doc -> 'members' from saved_model)) m
           where m ->> 'product_id' <> 'c1a00000-0000-4000-8000-000000000105'))) -> 'members'),
  4,
  'leaving a variant out releases it');
select is(
  public.product_model_for_product_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000105'),
  null,
  'the released product is loose again');
select lives_ok(
  format($$select public.product_model_delete_v1('c1a00000-0000-4000-8000-000000000001', %L)$$,
    (select doc ->> 'id' from saved_model)),
  'the team can undo a model');
select is(
  public.product_model_for_product_v1('c1a00000-0000-4000-8000-000000000001',
    'c1a00000-0000-4000-8000-000000000101'),
  null,
  'undoing a model leaves its products loose');
select throws_ok(
  format($$select public.product_model_delete_v1('c1a00000-0000-4000-8000-000000000002', %L)$$,
    (select doc ->> 'id' from saved_model)),
  '42501', 'catalog_tenant_forbidden',
  'nobody undoes another shop''s model');
reset role;

select * from finish();
rollback;
