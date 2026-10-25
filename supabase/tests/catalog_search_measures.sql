begin;

select no_plan();

-- Una medida que el cliente escribe decide, y buscar una pieza encuentra esa
-- pieza (20261025010000). El 2026-10-24 «cassette 7v» listaba cassettes de 8
-- y 9 y espaciadores (la nota «… 7v sólo según filas C-731» de la opción HG),
-- «camara 20» cámaras de 26 («1.50-2.20» se partía en «2 20») y
-- «manubrio 31.8» tees.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('3ea50000-0000-4000-8000-000000000001', 'Tienda de las medidas',
  'medidas@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, website_price_mode, category_name,
  brand, description
) values
  ('3ea50000-0000-4000-8000-000000000201', '3ea50000-0000-4000-8000-000000000001',
   'Piñón con rosca Falcon FW-71 7 velocidades 14-28T', null, 'ME-201', 12000, 4000, 19,
   'product', false, 'inventory', true, 4, 4, true, true, true, 'exact', 'Piñones', 'Falcon', null),
  ('3ea50000-0000-4000-8000-000000000202', '3ea50000-0000-4000-8000-000000000001',
   'Cassette Eclipse 8 velocidades 11-42T', null, 'ME-202', 35000, 12000, 19,
   'product', false, 'inventory', true, 1, 1, true, true, true, 'exact', 'Cassette', 'Eclipse',
   'Núcleo Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731)'),
  ('3ea50000-0000-4000-8000-000000000203', '3ea50000-0000-4000-8000-000000000001',
   'Espaciador de cassette Risk 1.5 mm', null, 'ME-203', 3000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Espaciadores de Cassette', 'Risk',
   'Para núcleo HG (8/9/10v; ROAD 11v y 7v según filas)'),
  ('3ea50000-0000-4000-8000-000000000204', '3ea50000-0000-4000-8000-000000000001',
   'Maza Trasera Disco 36H para Piñon con hilo 8S',
   'Maza trasera Eclipse para disco y piñón con rosca, 36 rayos', 'ME-204', 25000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Maza', 'Eclipse', null),
  ('3ea50000-0000-4000-8000-000000000205', '3ea50000-0000-4000-8000-000000000001',
   'Cámara aro 20 x 1.50-2.20 válvula auto', null, 'ME-205', 4000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Cámaras', 'RBX', null),
  ('3ea50000-0000-4000-8000-000000000206', '3ea50000-0000-4000-8000-000000000001',
   'Cámara aro 26 x 1.75-2.20 válvula auto', null, 'ME-206', 4000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Cámaras', 'Ritech', null),
  ('3ea50000-0000-4000-8000-000000000207', '3ea50000-0000-4000-8000-000000000001',
   'Kit de parches 20 unidades para cámara', null, 'ME-207', 3000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Parches', null, null),
  ('3ea50000-0000-4000-8000-000000000208', '3ea50000-0000-4000-8000-000000000001',
   'Manubrio MTB 31.8 x 780 mm', null, 'ME-208', 20000, 7000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Manubrios', 'Zoom', null),
  ('3ea50000-0000-4000-8000-000000000209', '3ea50000-0000-4000-8000-000000000001',
   'Tee MTB 31.8 x 45 mm', null, 'ME-209', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Tee', 'Wake', null),
  ('3ea50000-0000-4000-8000-000000000210', '3ea50000-0000-4000-8000-000000000001',
   'Manubrio urbano 25.4 x 600 mm', null, 'ME-210', 12000, 4000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Manubrios', null, null),
  ('3ea50000-0000-4000-8000-000000000211', '3ea50000-0000-4000-8000-000000000001',
   'Disco de freno 180 mm 6 pernos', null, 'ME-211', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Rotores', null, null),
  ('3ea50000-0000-4000-8000-000000000212', '3ea50000-0000-4000-8000-000000000001',
   'Disco de freno 160 mm 6 pernos', null, 'ME-212', 14000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Rotores', null, null),
  ('3ea50000-0000-4000-8000-000000000213', '3ea50000-0000-4000-8000-000000000001',
   'Adaptador de freno disco post mount 160 a 180 mm', null, 'ME-213', 8000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Adaptadores', null, null),
  ('3ea50000-0000-4000-8000-000000000214', '3ea50000-0000-4000-8000-000000000001',
   'Cambio trasero Sensah MX8 8 velocidades', null, 'ME-214', 30000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cambios', 'Sensah',
   'Compatible con Shimano'),
  ('3ea50000-0000-4000-8000-000000000215', '3ea50000-0000-4000-8000-000000000001',
   'Cambio trasero Shimano Altus 7/8 velocidades', null, 'ME-215', 25000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cambios', 'Shimano', null),
  ('3ea50000-0000-4000-8000-000000000216', '3ea50000-0000-4000-8000-000000000001',
   'Manilla de cambio delantera Shimano Tourney 3x7', null, 'ME-216', 12000, 4000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Shifters', 'Shimano', null),
  ('3ea50000-0000-4000-8000-000000000217', '3ea50000-0000-4000-8000-000000000001',
   'Manilla de cambio trasera SunRace M10 5/6/7 velocidades', null, 'ME-217', 10000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Shifters', 'SunRace', null),
  ('3ea50000-0000-4000-8000-000000000218', '3ea50000-0000-4000-8000-000000000001',
   'Cortacadena IceToolz hasta 12 velocidades', null, 'ME-218', 18000, 6000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Corta Cadena', 'IceToolz', null),
  ('3ea50000-0000-4000-8000-000000000219', '3ea50000-0000-4000-8000-000000000001',
   'Cadena ZTTO 12 velocidades', null, 'ME-219', 30000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas', 'ZTTO', null),
  ('3ea50000-0000-4000-8000-000000000220', '3ea50000-0000-4000-8000-000000000001',
   'Eslabón rápido Risk 12 velocidades (par)', null, 'ME-220', 5000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas', 'Risk', null),
  ('3ea50000-0000-4000-8000-000000000221', '3ea50000-0000-4000-8000-000000000001',
   'Llave para motor sellado Bike Hand', null, 'ME-221', 9000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas', 'Bike Hand', null),
  ('3ea50000-0000-4000-8000-000000000222', '3ea50000-0000-4000-8000-000000000001',
   'Motor sellado 68 x 122.5 mm', null, 'ME-222', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Motores', 'Neco', null),
  ('3ea50000-0000-4000-8000-000000000223', '3ea50000-0000-4000-8000-000000000001',
   'Neumático Maxxis 27.5 x 2.25', null, 'ME-223', 40000, 14000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Maxxis', null),
  ('3ea50000-0000-4000-8000-000000000224', '3ea50000-0000-4000-8000-000000000001',
   'Neumático Freedom 700 x 23C', null, 'ME-224', 18000, 6000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Freedom', null),
  ('3ea50000-0000-4000-8000-000000000225', '3ea50000-0000-4000-8000-000000000001',
   'Neumático Kenda 29 x 2.25', null, 'ME-225', 26000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Kenda', null),
  ('3ea50000-0000-4000-8000-000000000226', '3ea50000-0000-4000-8000-000000000001',
   'Llanta aro 29 doble pared, 32 rayos', null, 'ME-226', 30000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Llantas', null, null),
  ('3ea50000-0000-4000-8000-000000000227', '3ea50000-0000-4000-8000-000000000001',
   'Llanta aro 29 doble pared, 36 rayos', null, 'ME-227', 30000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Llantas', null, null),
  ('3ea50000-0000-4000-8000-000000000228', '3ea50000-0000-4000-8000-000000000001',
   'Pastillas de freno disco Shimano B01S', null, 'ME-228', 8000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Pastillas', 'Shimano', null),
  ('3ea50000-0000-4000-8000-000000000229', '3ea50000-0000-4000-8000-000000000001',
   'Manilla de cambio Shimano SL-M315 7 velocidades', null, 'ME-229', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Shifters', 'Shimano', null);

create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '3ea50000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.found(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '3ea50000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

-- Speeds.
select is(
  pg_temp.found('cassette 7v'),
  array['ME-201'],
  '«7v» is the 7-speed freewheel, not an 8-speed cassette or a spacer whose note says «7v»'
);
select is(
  pg_temp.found('cassette 8v'),
  array['ME-202'],
  'an 8-speed cassette, not a hub for a threaded freewheel'
);
select is(
  pg_temp.found('cadena 12v'),
  array['ME-219', 'ME-220'],
  'a 12-speed chain and its quick link, not the chain tool'
);
select is(
  pg_temp.found('corta cadena'),
  array['ME-218'],
  'and the chain tool when the tool is asked'
);
select is(
  (pg_temp.ranked('shifter 7v'))[1],
  'ME-229',
  'a rear 7-speed shifter before a front one for 3x7'
);
select ok(
  'ME-216' = any (pg_temp.ranked('shifter 7v')),
  'the front one is still there, after'
);
select is(
  (pg_temp.ranked('desviador shimano 8v'))[1],
  'ME-215',
  'the brand written first: Shimano before what says it fits Shimano'
);

-- Wheel sizes, decimals and widths.
select is(
  pg_temp.found('camara 20'),
  array['ME-205'],
  '«20» is the wheel: «1.50-2.20» is no longer «2 20», and a patch kit is not a tube'
);
select is(
  pg_temp.found('neumatico 29x2.25'),
  array['ME-225'],
  'a 29 tyre, not a 700 x 23 road one with the same bead seat'
);
select is(
  pg_temp.found('neumatico 27.5 2.1'),
  array['ME-223'],
  'the wheel decides, the width orders: a 27.5 x 2.25 when there is no 2.1'
);
select is(
  pg_temp.found('llanta 29 32 hoyos'),
  array['ME-226'],
  '«32 hoyos» is the rim''s spoke count'
);

-- The part asked.
select is(
  pg_temp.found('manubrio 31.8'),
  array['ME-208'],
  'a 31.8 handlebar, not the 31.8 stem nor a 25.4 handlebar'
);
select is(
  pg_temp.found('tee 31.8'),
  array['ME-209'],
  'and the stem when the stem is asked'
);
select is(
  pg_temp.found('disco 180mm'),
  array['ME-211'],
  '«disco» is the rotor and «180mm» its «180 mm»'
);
select is(
  pg_temp.found('pastillas shimano'),
  array['ME-228'],
  'pads, not a Shimano shift lever'
);
select is(
  pg_temp.ranked('motor'),
  array['ME-222', 'ME-221'],
  'the bottom bracket, then the wrench for it'
);

-- The helpers.
select is(
  public.catalog_search_query_v2('Cámara 29x2,25 180mm 11 velocidades'),
  'camara 29 2.25 180 mm 11v',
  'a search keeps its decimals and splits «mm»'
);
select is(
  public.catalog_search_text_v2('Cámara aro 20 x 1.50-2.20, válvula.'),
  'camara aro 20 x 1.50 2.20 valvula',
  'a product''s text keeps «2.20» as one word'
);
select is(
  public.catalog_search_bead_of_v1('27.5'),
  584::numeric,
  '27.5 is the 584 bead seat'
);
select ok(
  not has_function_privilege('anon', 'public.catalog_search_query_v2(text)', 'execute'),
  'the helpers stay closed to the public key'
);

select * from finish();
rollback;
