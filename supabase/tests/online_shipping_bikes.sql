-- Despacho de bicicletas (20261121120000): cada zona tiene su precio por
-- bicicleta, lo que es bicicleta lo dice su categoría (con sus
-- subcategorías), el resto de la compra paga su tramo de siempre y el pedido
-- cobra lo mismo que vio el cliente. Datos inventados; todo se deshace al
-- final.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(24);

create temp table bike_ids (name text primary key, id uuid not null) on commit drop;

select has_function(
  'public',
  'quote_public_online_shipping',
  array['uuid', 'text', 'numeric', 'text', 'text', 'jsonb'],
  'the store quotes with the cart''s lines'
);

insert into public.tenants (id, shop_name) values
  ('96500000-0000-4000-8000-000000000001', 'Bicis Test'),
  ('96500000-0000-4000-8000-000000000002', 'Bicis Otro');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('96500000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'bicis@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96500000-0000-4000-8000-000000000001'), now(), now()),
  ('96500000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'bicis-otro@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96500000-0000-4000-8000-000000000002'), now(), now());
delete from public.user_profiles where user_id in (
  '96500000-0000-4000-8000-000000000099', '96500000-0000-4000-8000-000000000098'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('96500000-0000-4000-8000-000000000099', '96500000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('96500000-0000-4000-8000-000000000098', '96500000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

-- El equipo guarda zonas con su precio por bicicleta y marca Bicicletas.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96500000-0000-4000-8000-000000000099', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96500000-0000-4000-8000-000000000099', true);

-- Bicicletas › Niños es bicicleta por su categoría madre; Cascos no.
insert into public.product_categories (id, tenant_id, name, full_path, parent_id, level, is_active, show_on_website) values
  ('96500000-0000-4000-8000-000000000030', '96500000-0000-4000-8000-000000000001', 'Bicicletas', 'Bicicletas', null, 0, true, true),
  ('96500000-0000-4000-8000-000000000031', '96500000-0000-4000-8000-000000000001', 'Niños', 'Bicicletas / Niños', '96500000-0000-4000-8000-000000000030', 1, true, true),
  ('96500000-0000-4000-8000-000000000032', '96500000-0000-4000-8000-000000000001', 'Cascos', 'Cascos', null, 0, true, true),
  ('96500000-0000-4000-8000-000000000033', '96500000-0000-4000-8000-000000000002', 'Bicicletas', 'Bicicletas', null, 0, true, true);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, category_id
) values
  ('96500000-0000-4000-8000-000000000010', '96500000-0000-4000-8000-000000000001',
   'Bicicleta de prueba aro 20', 'BICI-001', 250000, 250000, 160000, 19,
   'product', false, 'inventory', true, 5, 5, 0, 100, true, true, true,
   '96500000-0000-4000-8000-000000000031'),
  ('96500000-0000-4000-8000-000000000011', '96500000-0000-4000-8000-000000000001',
   'Casco de prueba', 'CASCO-001', 20000, 20000, 9000, 19,
   'product', false, 'inventory', true, 5, 5, 0, 100, true, true, true,
   '96500000-0000-4000-8000-000000000032');

select is(
  (select string_agg(coalesce((zone->>'bike_shipping_gross')::numeric::int::text, '-'), ',')
     from jsonb_array_elements(public.save_online_shipping_zones($$[
       {"name": "Región de Valparaíso", "region_codes": ["CL-VS"], "bike_shipping_gross": 25990, "tiers": [
         {"min_order_gross": 0, "max_order_gross": 30000, "shipping_gross": 5990,
          "estimated_min_business_days": 1, "estimated_max_business_days": 3},
         {"min_order_gross": 30000, "max_order_gross": null, "shipping_gross": 7990,
          "estimated_min_business_days": 1, "estimated_max_business_days": 3}
       ]},
       {"name": "Norte", "region_codes": ["CL-AN"], "tiers": [
         {"min_order_gross": 0, "shipping_gross": 13990,
          "estimated_min_business_days": 3, "estimated_max_business_days": 7}
       ]}
     ]$$::jsonb)) zone),
  '25990,-',
  'each zone keeps its price per bicycle; a zone without one ships none'
);
select is(
  jsonb_array_length(public.save_online_shipping_bike_categories_v1(
    array['96500000-0000-4000-8000-000000000030']::uuid[]
  )),
  1,
  'the team marks «Bicicletas» as what ships as a bicycle'
);
select throws_ok(
  $$select public.save_online_shipping_bike_categories_v1(
      array['96500000-0000-4000-8000-000000000033']::uuid[])$$,
  '22023',
  'Una de las categorías no existe.',
  'another shop''s category cannot be marked'
);

-- La cotización.
select is(
  (public.quote_public_online_shipping(
     '96500000-0000-4000-8000-000000000001', 'shipping', 250000, 'CL', 'Región de Valparaíso'
   )->>'shipping_gross')::numeric::int,
  7990,
  'without lines the quote is the one from before'
);
select is(
  (select ((q->>'shipping_gross')::numeric::int)::text || '|' || (q->>'bike_units')
     from (select public.quote_public_online_shipping(
       '96500000-0000-4000-8000-000000000001', 'shipping', 250000, 'CL', 'Región de Valparaíso',
       '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 1, "gross": 250000}]'::jsonb
     ) as q) quote),
  '25990|1',
  'a bicycle in a child category pays the zone''s bicycle price'
);
select is(
  (public.quote_public_online_shipping(
     '96500000-0000-4000-8000-000000000001', 'shipping', 500000, 'CL', 'Región de Valparaíso',
     '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 2, "gross": 500000}]'::jsonb
   )->>'shipping_gross')::numeric::int,
  51980,
  'two bicycles pay twice'
);
select is(
  (select ((q->>'shipping_gross')::numeric::int)::text || '|' || ((q->>'parcel_shipping_gross')::numeric::int)::text
          || '|' || ((q->>'shipping_net')::numeric::int + (q->>'shipping_tax')::numeric::int)::text
     from (select public.quote_public_online_shipping(
       '96500000-0000-4000-8000-000000000001', 'shipping', 270000, 'CL', 'Región de Valparaíso',
       '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 1, "gross": 250000},
         {"product_id": "96500000-0000-4000-8000-000000000011", "quantity": 1, "gross": 20000}]'::jsonb
     ) as q) quote),
  '31980|5990|31980',
  'with a helmet, the helmet pays the band of its own amount, and net plus VAT is the total'
);
select is(
  (public.quote_public_online_shipping(
     '96500000-0000-4000-8000-000000000001', 'shipping', 20000, 'CL', 'Región de Valparaíso',
     '[{"product_id": "96500000-0000-4000-8000-000000000011", "quantity": 1, "gross": 20000}]'::jsonb
   )->>'shipping_gross')::numeric::int,
  5990,
  'a cart without bicycles quotes as always, lines or not'
);
select is(
  (public.quote_public_online_shipping(
     '96500000-0000-4000-8000-000000000001', 'shipping', 250000, 'CL', 'Región de Valparaíso',
     '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 1}]'::jsonb
   )->>'shipping_gross')::numeric::int,
  25990,
  'a line without its amount is read at the published price'
);
select throws_ok(
  $$select public.quote_public_online_shipping(
      '96500000-0000-4000-8000-000000000001', 'shipping', 250000, 'CL', 'Antofagasta',
      '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 1, "gross": 250000}]'::jsonb)$$,
  '23514',
  'Por ahora no despachamos bicicletas a la región de Antofagasta. Puedes retirarla en la tienda.',
  'a zone without a bicycle price says so before paying'
);
select is(
  (select ((q->>'shipping_gross')::numeric::int)::text || '|' || (q->>'bike_units')
     from (select public.quote_public_online_shipping(
       '96500000-0000-4000-8000-000000000001', 'pickup', 250000, 'CL', null,
       '[{"product_id": "96500000-0000-4000-8000-000000000010", "quantity": 1, "gross": 250000}]'::jsonb
     ) as q) quote),
  '0|1',
  'picking the bicycle up in store costs nothing'
);
select is(
  (public.quote_public_online_shipping(
     '96500000-0000-4000-8000-000000000001', 'shipping', 250000, 'CL', 'Región de Valparaíso',
     '[{"product_id": "not-a-product", "quantity": 1}, 7, null]'::jsonb
   )->>'shipping_gross')::numeric::int,
  7990,
  'lines that are not products do not count'
);

-- La tienda lee el precio por bicicleta y qué es bicicleta.
select is(
  (select string_agg(distinct coalesce(bike_shipping_gross::int::text, '-'), ',' order by coalesce(bike_shipping_gross::int::text, '-'))
     from public.get_public_online_shipping_tiers('96500000-0000-4000-8000-000000000001')),
  '-,25990',
  'the store reads each zone''s bicycle price'
);
select ok(
  (select bool_and('96500000-0000-4000-8000-000000000031'::uuid = any(bike_category_ids)
                   and '96500000-0000-4000-8000-000000000030'::uuid = any(bike_category_ids)
                   and not ('96500000-0000-4000-8000-000000000032'::uuid = any(bike_category_ids)))
     from public.get_public_online_shipping_tiers('96500000-0000-4000-8000-000000000001')),
  'the store knows «Bicicletas» and its child are bicycles, and helmets are not'
);

-- Una app anterior guarda sin el precio por bicicleta: se conserva.
select public.save_online_shipping_zones($$[
  {"name": "Región de Valparaíso", "region_codes": ["CL-VS"], "tiers": [
    {"min_order_gross": 0, "max_order_gross": 30000, "shipping_gross": 5990,
     "estimated_min_business_days": 1, "estimated_max_business_days": 3},
    {"min_order_gross": 30000, "shipping_gross": 7990,
     "estimated_min_business_days": 1, "estimated_max_business_days": 3}
  ]},
  {"name": "Norte", "region_codes": ["CL-AN"], "tiers": [
    {"min_order_gross": 0, "shipping_gross": 13990}
  ]}
]$$::jsonb);
select is(
  (select bike_shipping_gross::int from public.online_shipping_zones
    where tenant_id = '96500000-0000-4000-8000-000000000001' and is_active and name = 'Región de Valparaíso'),
  25990,
  'saving from an older app keeps the bicycle price of the zone with the same name'
);
select throws_ok(
  $$select public.save_online_shipping_zones('[
    {"name": "A", "region_codes": ["CL-VS"], "bike_shipping_gross": 1999.5,
     "tiers": [{"min_order_gross": 0, "shipping_gross": 5990}]}
  ]'::jsonb)$$,
  '22023',
  'Escribe el despacho de bicicleta de «A» en pesos enteros.',
  'a bicycle price in cents is refused'
);
select is(
  (select bike_shipping_gross::int from public.online_shipping_zones
    where tenant_id = '96500000-0000-4000-8000-000000000001' and is_active and name = 'Región de Valparaíso'),
  25990,
  'a refused save leaves the bicycle price as it was'
);
select is(
  jsonb_array_length(public.online_shipping_bike_categories_for_editor()),
  1,
  'the editor reads the marked category'
);

-- El pedido cobra el despacho de la bicicleta, como el checkout.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into bike_ids
select 'order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96500000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'bici-test-001',
    'customer_email', 'cliente-bici@example.invalid',
    'customer_name', 'Cliente Bici',
    'customer_address', 'Calle Inventada 123',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Calle Inventada 123',
    'shipping_city', 'Comuna Inventada',
    'shipping_state', 'Región de Valparaíso',
    'shipping_quote_cost', 31980,
    'payment_method', 'transfer'
  ),
  jsonb_build_array(
    jsonb_build_object('product_id', '96500000-0000-4000-8000-000000000010', 'quantity', 1),
    jsonb_build_object('product_id', '96500000-0000-4000-8000-000000000011', 'quantity', 1)
  )
);
select is(
  (select shipping_cost::int::text || '|' || (shipping_rate_snapshot->>'bike_units')
     from public.online_orders
    where id = (select id from bike_ids where name = 'order')),
  '31980|1',
  'an order with a bicycle and a helmet is charged what the checkout showed'
);
select throws_ok(
  $$select public.create_public_online_order(
    jsonb_build_object(
      'tenant_id', '96500000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', 'bici-test-002',
      'customer_email', 'cliente-bici@example.invalid',
      'customer_name', 'Cliente Bici',
      'customer_address', 'Calle Inventada 123',
      'delivery_type', 'shipping',
      'shipping_address_line1', 'Calle Inventada 123',
      'shipping_city', 'Comuna Inventada',
      'shipping_state', 'Región de Valparaíso',
      'shipping_quote_cost', 7990,
      'payment_method', 'transfer'
    ),
    jsonb_build_array(jsonb_build_object(
      'product_id', '96500000-0000-4000-8000-000000000010', 'quantity', 1)))$$,
  '40001',
  'Shipping quote changed; refresh checkout before paying',
  'an order quoted without the bicycle''s shipping is not taken'
);

select ok(
  has_function_privilege('anon', 'public.quote_public_online_shipping(uuid,text,numeric,text,text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.quote_online_shipping_internal(uuid,text,numeric,text,text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.online_shipping_bike_lines_internal(uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.online_order_shipping_lines_internal(uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.save_online_shipping_bike_categories_v1(uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.save_online_shipping_bike_categories_v1(uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.online_shipping_bike_categories_for_editor()', 'execute'),
  'staff mark bicycles; the store only quotes'
);

-- Otro taller ve y guarda sólo lo suyo.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96500000-0000-4000-8000-000000000098', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96500000-0000-4000-8000-000000000098', true);
select is(
  jsonb_array_length(public.online_shipping_bike_categories_for_editor()),
  0,
  'another tenant does not see the marked categories'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.online_shipping_bike_categories'::regclass)
  and exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'online_shipping_bike_categories'
       and policyname = 'online_shipping_bike_categories_staff_read'
  ),
  'and the table is read only through its tenant policy'
);

select * from finish();
rollback;
