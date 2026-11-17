begin;

select no_plan();

-- La búsqueda lee la frase y las velocidades de la bici como las escribe el
-- cliente (20261116234500). El 2026-11-16, en producción, «v brake» listaba
-- tres servicios y ningún freno, «gomas de freno», «extractor de cadena»,
-- «neumatico sin camara» y «cadena 21 velocidades» no encontraban nada, y
-- «forro» traía fundas.
--
-- The vocabulary here is the test's own: the shared rows are replaced inside
-- this transaction, so the rule is tested and not the day's data.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

delete from public.catalog_search_terms where tenant_id is null;

insert into public.catalog_search_terms (tenant_id, concept, kind, terms, broader, phrases)
values
  (null, 'freno', 'part', array['freno', 'frenos', 'brake', 'brakes'], array[]::text[], array[]::text[]),
  (null, 'patin', 'part', array['patin', 'patines', 'zapata', 'zapatas'],
    array['freno', 'frenos'], array['gomas de freno', 'goma de freno']),
  (null, 'neumatico', 'part', array['neumatico', 'neumaticos', 'goma', 'gomas', 'forro', 'forros'],
    array[]::text[], array[]::text[]),
  (null, 'camara', 'part', array['camara', 'camaras'], array[]::text[], array[]::text[]),
  (null, 'tubeless', 'attribute', array['tubeless', 'tlr'], array[]::text[], array['sin camara']),
  (null, 'vbrake', 'attribute', array['vbrake', 'vbrakes'], array['freno', 'frenos'],
    array['v brake', 'v brakes']),
  (null, 'manilla', 'part', array['manilla', 'manillas'], array[]::text[], array['manilla de freno']),
  (null, 'shifter', 'part', array['shifter', 'shifters'], array['cambio', 'cambios'],
    array['manilla de cambio']),
  (null, 'funda', 'part', array['funda', 'fundas'], array[]::text[],
    array['forro de cambio', 'forro cambio']),
  (null, 'piola', 'part', array['piola', 'piolas', 'cable', 'cables'], array[]::text[], array[]::text[]),
  (null, 'cambio', 'part', array['desviador', 'desviadores'], array['cambios'],
    array['cambio trasero', 'cambio delantero']),
  (null, 'cortacadena', 'part', array['cortacadena', 'cortacadenas', 'tronchacadena'],
    array['herramienta'], array['corta cadena', 'extractor de cadena']),
  (null, 'extractor', 'part', array['extractor', 'extractores'], array['herramienta'], array[]::text[]),
  (null, 'cadena', 'part', array['cadena', 'cadenas'], array[]::text[], array[]::text[]),
  (null, 'eje', 'part', array['eje', 'ejes'], array[]::text[], array[]::text[]),
  (null, 'pasante', 'attribute', array['pasante', 'thru'], array['eje', 'ejes'], array['eje pasante']),
  (null, 'rueda', 'part', array['rueda', 'ruedas'], array[]::text[], array[]::text[]),
  (null, 'centrado', 'attribute', array['centrado', 'centrar'], array[]::text[], array[]::text[]);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('b4a5e000-0000-4000-8000-000000000001', 'Tienda de las frases',
  'frases@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website, website_price_mode, category_name, description
) values
  ('b4a5e000-0000-4000-8000-000000000101', 'b4a5e000-0000-4000-8000-000000000001',
   'Patines de freno MTB 70 mm (par)', 'PH-101', 4000, 1000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Pastillas', null),
  ('b4a5e000-0000-4000-8000-000000000102', 'b4a5e000-0000-4000-8000-000000000001',
   'Neumático Kenda 26 x 1.95', 'PH-102', 15000, 6000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', null),
  ('b4a5e000-0000-4000-8000-000000000103', 'b4a5e000-0000-4000-8000-000000000001',
   'Neumático Maxxis Minion tubeless 27.5 x 2.5', 'PH-103', 60000, 30000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', null),
  ('b4a5e000-0000-4000-8000-000000000104', 'b4a5e000-0000-4000-8000-000000000001',
   'Freno V-brake Shimano BR-T4000 trasero', 'PH-104', 12000, 5000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Herraduras', null),
  -- Its description has words in «v»; a «v» typed alone is not found there.
  ('b4a5e000-0000-4000-8000-000000000105', 'b4a5e000-0000-4000-8000-000000000001',
   'Frenos de tiro lateral aluminio (juego)', 'PH-105', 14000, 6000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Herraduras',
   'Vienen con sus pernos y van en la horquilla.'),
  ('b4a5e000-0000-4000-8000-000000000106', 'b4a5e000-0000-4000-8000-000000000001',
   'Patín de freno V-brake con tuerca', 'PH-106', 3000, 1000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Pastillas', null),
  ('b4a5e000-0000-4000-8000-000000000107', 'b4a5e000-0000-4000-8000-000000000001',
   'Cáliper de freno disco mecánico', 'PH-107', 20000, 9000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Frenos',
   'Viene con adaptador y pernos.'),
  ('b4a5e000-0000-4000-8000-000000000108', 'b4a5e000-0000-4000-8000-000000000001',
   'Cortacadena Toopre negro', 'PH-108', 8000, 3000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas', null),
  ('b4a5e000-0000-4000-8000-000000000109', 'b4a5e000-0000-4000-8000-000000000001',
   'Extractor de bielas IceToolz', 'PH-109', 9000, 3000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas', null),
  ('b4a5e000-0000-4000-8000-000000000110', 'b4a5e000-0000-4000-8000-000000000001',
   'Funda de cambio 4 mm negra, rollo 50 m', 'PH-110', 30000, 12000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Fundas', null),
  ('b4a5e000-0000-4000-8000-000000000111', 'b4a5e000-0000-4000-8000-000000000001',
   'Funda cubre asiento negra', 'PH-111', 5000, 2000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Fundas',
   'Protege el asiento de la lluvia.'),
  ('b4a5e000-0000-4000-8000-000000000112', 'b4a5e000-0000-4000-8000-000000000001',
   'Manilla de freno MTB aluminio', 'PH-112', 7000, 3000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Manillas', null),
  -- A «manilla» by its first word, but a shift lever.
  ('b4a5e000-0000-4000-8000-000000000113', 'b4a5e000-0000-4000-8000-000000000001',
   'Manilla de cambio trasera SunRace 7 velocidades', 'PH-113', 9000, 4000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Manillas', null),
  ('b4a5e000-0000-4000-8000-000000000114', 'b4a5e000-0000-4000-8000-000000000001',
   'Cambio trasero Shimano Tourney 7 velocidades', 'PH-114', 15000, 6000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Cambios', null),
  ('b4a5e000-0000-4000-8000-000000000115', 'b4a5e000-0000-4000-8000-000000000001',
   'Cambio delantero Shimano Tourney 3 velocidades', 'PH-115', 12000, 5000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Cambios', null),
  ('b4a5e000-0000-4000-8000-000000000116', 'b4a5e000-0000-4000-8000-000000000001',
   'Cadena KMC Z7 6/7 velocidades', 'PH-116', 8000, 3000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas', null),
  ('b4a5e000-0000-4000-8000-000000000117', 'b4a5e000-0000-4000-8000-000000000001',
   'Cadena KMC X9 9 velocidades', 'PH-117', 16000, 7000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas', null),
  ('b4a5e000-0000-4000-8000-000000000118', 'b4a5e000-0000-4000-8000-000000000001',
   'Centrado de rueda (c/u)', 'PH-118', 6000, 0, 19, 'service', true,
   'inventory', false, 0, 0, true, true, true, 'exact', 'Ruedas', null),
  ('b4a5e000-0000-4000-8000-000000000119', 'b4a5e000-0000-4000-8000-000000000001',
   'Rueda trasera aro 29 Shimano', 'PH-119', 45000, 20000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Ruedas', null),
  ('b4a5e000-0000-4000-8000-000000000120', 'b4a5e000-0000-4000-8000-000000000001',
   'Eje pasante 12 x 142 mm', 'PH-120', 15000, 6000, 19, 'product', false,
   'inventory', true, 2, 2, true, true, true, 'exact', 'Ejes', null);

set local session_replication_role = origin;

create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    'b4a5e000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.found(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku collate "C"), '{}')
  from public.get_public_products_without_inventory_reservations(
    'b4a5e000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

-- A phrase asks for its part, and the part answers for the phrase's words.
select is(pg_temp.found('gomas de freno'), array['PH-101', 'PH-106'],
  '«gomas de freno» finds the pads, which never say «gomas»; not the tyres «gomas» names');
select is(pg_temp.found('extractor de cadena'), array['PH-108'],
  '«extractor de cadena» finds the chain tool, not the crank extractor');
select is(pg_temp.found('neumatico sin camara'), array['PH-103'],
  '«neumatico sin camara» finds the tubeless tyre: «sin camara» asks for no tube');

-- A V-brake is a kind of brake: the brake first, then its pads.
select is((pg_temp.ranked('v brake'))[1], 'PH-104', '«v brake» lists the V-brake first');
select is(pg_temp.found('v brake'), array['PH-104', 'PH-106'],
  'and its pad; not the side-pull brake nor the disc caliper, whose descriptions only have words in «v»');
select is(pg_temp.found('vbrake'), array['PH-104', 'PH-106'], '«vbrake» finds the same');
select is(pg_temp.found('eje pasante'), array['PH-120'],
  '«eje pasante» still asks for the axle the attribute qualifies');

-- «Forro» is a tyre; a housing asked as «forro de cambio» is still a housing.
select is(pg_temp.found('forro'), array['PH-102', 'PH-103'], '«forro» finds the tyres');
select is(pg_temp.found('forro de cambio'), array['PH-110'],
  '«forro de cambio» finds the housing, not the seat cover, which is a «funda» too');

-- The product must say a word of the phrase besides the part's own name.
select is(pg_temp.found('manilla de freno'), array['PH-112'],
  '«manilla de freno» finds the brake lever, not the shift lever that starts with «Manilla»');
select is(pg_temp.found('cambio trasero'), array['PH-114'],
  '«cambio trasero» still needs «trasero»: the front derailleur is out');
select is(pg_temp.found('cambio delantero'), array['PH-115'], 'and «cambio delantero» the front one');

-- A bike's speeds are its cassette's.
select is(pg_temp.found('cadena 21 velocidades'), array['PH-116'],
  '«cadena 21 velocidades» is a 3 x 7: the 6/7 chain, not the 9');
select is(pg_temp.found('cadena 27 velocidades'), array['PH-117'], '27 is a 3 x 9');
select is(pg_temp.found('cadena 18 velocidades'), array['PH-116', 'PH-117'],
  '18 is a 3 x 6 or a 2 x 9');
select is(pg_temp.found('cadena 7v'), array['PH-116'], 'a cassette''s speeds ask as before');

-- The verb of a service finds it.
select is(pg_temp.found('centrar rueda'), array['PH-118'],
  '«centrar rueda» finds the truing service, not the wheel');

select * from finish();
rollback;
