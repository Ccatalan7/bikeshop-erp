-- Despacho por zona (20261014030000): el checkout cotiza con la región de
-- destino, el editor guarda zonas y tramos, y el pedido cobra el de su
-- región. Datos inventados; todo se deshace al final.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(27);

create temp table zone_ids (name text primary key, id uuid not null) on commit drop;

-- Cómo llega la región: Google, una dirección guardada o escrita a mano.
select is(public.online_shipping_region_code('Región de Valparaíso'), 'CL-VS', 'Google''s region name');
select is(public.online_shipping_region_code('Región Metropolitana de Santiago'), 'CL-RM', 'the capital''s region');
select is(public.online_shipping_region_code('V Región'), 'CL-VS', 'a roman numeral');
select is(public.online_shipping_region_code('rm'), 'CL-RM', 'the short name');
select is(public.online_shipping_region_code('Ñuble'), 'CL-NB', 'with its accent');
select is(public.online_shipping_region_code('Aysén del General Carlos Ibáñez del Campo'), 'CL-AI', 'the long name');
select is(public.online_shipping_region_code('Los Ríos'), 'CL-LR', 'Los Ríos is not Los Lagos');
select is(public.online_shipping_region_code('Narnia'), null, 'not a region of Chile');

insert into public.tenants (id, shop_name) values
  ('96400000-0000-4000-8000-000000000001', 'Zonas Test'),
  ('96400000-0000-4000-8000-000000000002', 'Zonas Otro');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('96400000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'zonas@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96400000-0000-4000-8000-000000000001'), now(), now()),
  ('96400000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'zonas-otro@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96400000-0000-4000-8000-000000000002'), now(), now());
delete from public.user_profiles where user_id in (
  '96400000-0000-4000-8000-000000000099', '96400000-0000-4000-8000-000000000098'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('96400000-0000-4000-8000-000000000099', '96400000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('96400000-0000-4000-8000-000000000098', '96400000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

-- Una tarifa como las de antes, sin zona: cae en «Todo Chile».
insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross, shipping_gross,
  tax_rate, estimated_min_business_days, estimated_max_business_days
) values
  ('96400000-0000-4000-8000-000000000001', 'CL', 0, null, 6990, 19, 3, 12);

select is(
  (select name || '|' || cardinality(region_codes)::text
     from public.online_shipping_zones
    where tenant_id = '96400000-0000-4000-8000-000000000001'),
  'Todo Chile|16',
  'a tier without a zone lands in «Todo Chile», every region'
);
select is(
  (public.quote_public_online_shipping(
     '96400000-0000-4000-8000-000000000001', 'shipping', 11000, 'CL'
   )->>'shipping_gross')::numeric::int,
  6990,
  'with one zone, a checkout that sends no region quotes as before'
);

-- El editor guarda dos zonas.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96400000-0000-4000-8000-000000000099', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96400000-0000-4000-8000-000000000099', true);

select is(
  jsonb_array_length(public.save_online_shipping_zones($$[
    {"name": "Región de Valparaíso", "region_codes": ["CL-VS"], "tiers": [
      {"min_order_gross": 0, "max_order_gross": 30000, "shipping_gross": 5990,
       "estimated_min_business_days": 1, "estimated_max_business_days": 3},
      {"min_order_gross": 30000, "max_order_gross": null, "shipping_gross": 7990,
       "estimated_min_business_days": 1, "estimated_max_business_days": 3}
    ]},
    {"name": "Centro", "region_codes": ["CL-RM", "CL-LI"], "tiers": [
      {"min_order_gross": 0, "max_order_gross": 30000, "shipping_gross": 7490,
       "estimated_min_business_days": 2, "estimated_max_business_days": 5},
      {"min_order_gross": 30000, "shipping_gross": 9990,
       "estimated_min_business_days": 2, "estimated_max_business_days": 5}
    ]}
  ]$$::jsonb)),
  2,
  'the editor saves two zones'
);
select is(
  (select count(*)::int from public.online_shipping_zones
    where tenant_id = '96400000-0000-4000-8000-000000000001' and is_active),
  2,
  '«Todo Chile» is replaced, not added to'
);

select is(
  (public.quote_public_online_shipping(
     '96400000-0000-4000-8000-000000000001', 'shipping', 11000, 'CL', 'Región de Valparaíso'
   )->>'shipping_gross')::numeric::int,
  5990,
  'Viña del Mar pays the Valparaíso price'
);
select is(
  (select ((q->>'shipping_gross')::numeric::int)::text || '|' || (q->>'zone_name') || '|' || (q->>'region_code')
     from (select public.quote_public_online_shipping(
       '96400000-0000-4000-8000-000000000001', 'shipping', 50000, 'CL', 'Región Metropolitana de Santiago'
     ) as q) quote),
  '9990|Centro|CL-RM',
  'Santiago pays the central zone''s band for its subtotal, and the quote says which zone'
);
select throws_ok(
  $$select public.quote_public_online_shipping(
      '96400000-0000-4000-8000-000000000001', 'shipping', 11000, 'CL', 'Biobío')$$,
  '23514',
  'Por ahora no despachamos a la región de Biobío.',
  'a region outside every zone is said before paying'
);
select throws_ok(
  $$select public.quote_public_online_shipping(
      '96400000-0000-4000-8000-000000000001', 'shipping', 11000, 'CL')$$,
  '22023',
  'Indica la región de despacho para calcular el costo.',
  'with several zones the region is needed'
);
select throws_ok(
  $$select public.quote_public_online_shipping(
      '96400000-0000-4000-8000-000000000001', 'shipping', 11000, 'CL', 'Narnia')$$,
  '22023',
  'No reconocemos la región «Narnia». Elígela de nuevo en la dirección.',
  'a region that is not one says so'
);
select is(
  (public.quote_public_online_shipping(
     '96400000-0000-4000-8000-000000000001', 'pickup', 11000, 'CL'
   )->>'shipping_gross')::numeric::int,
  0,
  'pickup in store costs nothing and needs no region'
);

-- Lo que el editor no deja guardar, y lo anterior sigue igual.
select throws_ok(
  $$select public.save_online_shipping_zones('[
    {"name": "A", "region_codes": ["CL-VS"], "tiers": [{"min_order_gross": 0, "shipping_gross": 5990}]},
    {"name": "B", "region_codes": ["CL-VS", "CL-RM"], "tiers": [{"min_order_gross": 0, "shipping_gross": 7990}]}
  ]'::jsonb)$$,
  '23514',
  'Una región no puede estar en dos zonas: Valparaíso.',
  'a region in two zones is refused'
);
select throws_ok(
  $$select public.save_online_shipping_zones('[
    {"name": "A", "region_codes": ["CL-VS"], "tiers": [
      {"min_order_gross": 0, "max_order_gross": 20000, "shipping_gross": 5990},
      {"min_order_gross": 30000, "shipping_gross": 7990}
    ]}
  ]'::jsonb)$$,
  '22023',
  'Los tramos de «A» deben seguirse sin huecos desde $0.',
  'a gap between bands is refused'
);
select throws_ok(
  $$select public.save_online_shipping_zones('[
    {"name": "A", "region_codes": ["CL-VS"], "tiers": [
      {"min_order_gross": 0, "max_order_gross": 20000, "shipping_gross": 5990}
    ]}
  ]'::jsonb)$$,
  '22023',
  'En «A» sólo el último tramo queda sin tope.',
  'a zone that stops at a ceiling is refused'
);
select is(
  (select string_agg(name, ',' order by sort_order) from public.online_shipping_zones
    where tenant_id = '96400000-0000-4000-8000-000000000001' and is_active),
  'Región de Valparaíso,Centro',
  'a refused save leaves the zones as they were'
);

-- La tienda publica cada tramo con su zona.
select is(
  (select string_agg(zone_name || ':' || shipping_gross::int, ',' order by zone_sort_order, min_order_gross)
     from public.get_public_online_shipping_tiers('96400000-0000-4000-8000-000000000001')),
  'Región de Valparaíso:5990,Región de Valparaíso:7990,Centro:7490,Centro:9990',
  'the store reads every active band with its zone'
);

-- El pedido cobra el despacho de su región.
insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '96400000-0000-4000-8000-000000000010', '96400000-0000-4000-8000-000000000001',
  'Repuesto de zona', 'ZONA-001', 11000, 11000, 4000, 19,
  'product', false, 'inventory', true, 10, 10, 0, 100, true, true, true
);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into zone_ids
select 'order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96400000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'zona-test-001',
    'customer_email', 'cliente-zona@example.invalid',
    'customer_name', 'Cliente Zona',
    'customer_address', 'Calle Inventada 123',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Calle Inventada 123',
    'shipping_city', 'Comuna Inventada',
    'shipping_state', 'Región Metropolitana de Santiago',
    'shipping_quote_cost', 7490,
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '96400000-0000-4000-8000-000000000010', 'quantity', 1
  ))
);
select is(
  (select shipping_cost::int from public.online_orders
    where id = (select id from zone_ids where name = 'order')),
  7490,
  'an order to Santiago is charged the central zone''s shipping'
);

-- Guardar de nuevo deja inactivo el tramo con que se cobró, no lo borra.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96400000-0000-4000-8000-000000000099', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96400000-0000-4000-8000-000000000099', true);
select public.save_online_shipping_zones($$[
  {"name": "Todo Chile", "region_codes": ["CL-VS", "CL-RM"], "tiers": [
    {"min_order_gross": 0, "shipping_gross": 8990}
  ]}
]$$::jsonb);
select is(
  (select tier.is_active::text from public.online_orders orders
     join public.online_shipping_rate_tiers tier on tier.id = orders.shipping_rate_tier_id
    where orders.id = (select id from zone_ids where name = 'order')),
  'false',
  'the tier an order was charged with stays, inactive'
);

select ok(
  has_function_privilege('authenticated', 'public.save_online_shipping_zones(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.save_online_shipping_zones(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.online_shipping_zones_for_editor()', 'execute')
  and has_function_privilege('anon', 'public.quote_public_online_shipping(uuid,text,numeric,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.quote_online_shipping_internal(uuid,text,numeric,text,text)', 'execute'),
  'staff edit zones; the store only quotes'
);

-- Otro taller ve y guarda sólo lo suyo.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96400000-0000-4000-8000-000000000098', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96400000-0000-4000-8000-000000000098', true);
select is(
  jsonb_array_length(public.online_shipping_zones_for_editor()),
  0,
  'another tenant does not see the zones'
);

select * from finish();
rollback;
