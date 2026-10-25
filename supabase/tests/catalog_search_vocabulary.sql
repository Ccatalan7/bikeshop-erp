begin;

select no_plan();

-- La búsqueda del catálogo entiende las palabras del taller (20261024030000).
-- El 2026-10-24 «camara francesa» encontraba tres cámaras y «camara fv»
-- ninguna; «29x2.25» nada aunque los neumáticos dicen «29 x 2.25».

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('5ea70000-0000-4000-8000-000000000001', 'Tienda del buscador',
  'buscador@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, website_price_mode, category_name
) values
  ('5ea70000-0000-4000-8000-000000000101', '5ea70000-0000-4000-8000-000000000001',
   'Cámara aro 26 x 1.95-2.125 válvula francesa 48 mm', null, '5EA7-101', 5000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Cámaras'),
  ('5ea70000-0000-4000-8000-000000000102', '5ea70000-0000-4000-8000-000000000001',
   'Cámara aro 29 x 2.0-2.40 válvula auto 48 mm', null, '5EA7-102', 7000, 1000, 19,
   'product', false, 'inventory', true, 3, 3, true, true, true, 'exact', 'Cámaras'),
  ('5ea70000-0000-4000-8000-000000000103', '5ea70000-0000-4000-8000-000000000001',
   'Neumático Kenda Moser 29 x 2.25', null, '5EA7-103', 26000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos'),
  ('5ea70000-0000-4000-8000-000000000104', '5ea70000-0000-4000-8000-000000000001',
   'Cadena KMC X11 11 velocidades', null, '5EA7-104', 30000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas'),
  ('5ea70000-0000-4000-8000-000000000105', '5ea70000-0000-4000-8000-000000000001',
   'Cadena KMC Z8 8 velocidades', null, '5EA7-105', 12000, 4000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cadenas'),
  ('5ea70000-0000-4000-8000-000000000106', '5ea70000-0000-4000-8000-000000000001',
   'Motor sellado 73x118 mm Neco', null, '5EA7-106', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Motores'),
  ('5ea70000-0000-4000-8000-000000000107', '5ea70000-0000-4000-8000-000000000001',
   'Llave Allen 5 mm', null, '5EA7-107', 3000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas'),
  ('5ea70000-0000-4000-8000-000000000108', '5ea70000-0000-4000-8000-000000000001',
   'Neumático Freedom Comet 700 x 23C', null, '5EA7-108', 18000, 6000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos'),
  ('5ea70000-0000-4000-8000-000000000109', '5ea70000-0000-4000-8000-000000000001',
   'Pastillas de freno disco Shimano B01S', null, '5EA7-109', 8000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Pastillas'),
  ('5ea70000-0000-4000-8000-000000000110', '5ea70000-0000-4000-8000-000000000001',
   'Cassette Shimano Deore 1x12 10-51T', null, '5EA7-110', 90000, 30000, 19,
   'product', false, 'inventory', true, 1, 1, true, true, true, 'exact', 'Cassette'),
  ('5ea70000-0000-4000-8000-000000000111', '5ea70000-0000-4000-8000-000000000001',
   'Postiza A-FORGE A-HG001', null, '5EA7-111', 9000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Postiza'),
  ('5ea70000-0000-4000-8000-000000000112', '5ea70000-0000-4000-8000-000000000001',
   'Llave para motor sellado Bike Hand', null, '5EA7-112', 9000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas'),
  ('5ea70000-0000-4000-8000-000000000113', '5ea70000-0000-4000-8000-000000000001',
   'Patines de freno Baradine MTB', null, '5EA7-113', 4000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Frenos'),
  ('5ea70000-0000-4000-8000-000000000114', '5ea70000-0000-4000-8000-000000000001',
   'Piola de freno MTB', null, '5EA7-114', 1500, 500, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Fundas y piolas'),
  ('5ea70000-0000-4000-8000-000000000115', '5ea70000-0000-4000-8000-000000000001',
   'Cambio trasero Shimano Deore 11 velocidades', null, '5EA7-115', 60000, 20000, 19,
   'product', false, 'inventory', true, 1, 1, true, true, true, 'exact', 'Cambios'),
  ('5ea70000-0000-4000-8000-000000000116', '5ea70000-0000-4000-8000-000000000001',
   'Llanta Weinmann U32 TL aro 27.5 tubeless, válvula francesa', null, '5EA7-116', 30000, 9000, 19,
   'product', false, 'inventory', true, 1, 1, true, true, true, 'exact', 'Llantas');

-- In the order the search answers.
create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '5ea70000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.found(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '5ea70000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

select is(
  pg_temp.found('camara fv'),
  array['5EA7-101'],
  '«fv» is the French valve the name calls «francesa»'
);
select is(
  pg_temp.found('llanta fv'),
  array['5EA7-116'],
  'a tubeless rim answers to its valve'
);
-- 20261024040000: «sin cámara» makes a rim tubeless, not a tube.
select is(
  pg_temp.found('camara francesa'),
  array['5EA7-101'],
  'a tubeless rim is not a tube'
);
select is(
  pg_temp.found('camara presta'),
  array['5EA7-101'],
  '«presta» too'
);
select is(
  pg_temp.found('camara av 29'),
  array['5EA7-102'],
  '«av» is the auto valve, and the size narrows it'
);
select is(
  pg_temp.found('29x2.25'),
  array['5EA7-103'],
  'a measure written without spaces finds the one written with them'
);
select is(
  pg_temp.found('cadena 11v'),
  array['5EA7-104'],
  '«11v» is «11 velocidades»'
);
select is(
  pg_temp.found('cambio 11v'),
  array['5EA7-115'],
  'and «11v» finds an 11-speed derailleur by its «cambio»'
);
select is(
  pg_temp.found('cadena 11s'),
  array['5EA7-104'],
  '«11s» too'
);
select is(
  pg_temp.found('cassette 12 velocidades'),
  array['5EA7-110'],
  '«1x12» in a name is 12 speeds'
);
select is(
  pg_temp.ranked('motor'),
  array['5EA7-106', '5EA7-112'],
  '«motor» is the bottom bracket, before the wrench for it'
);
select is(
  pg_temp.ranked('pedalier'),
  array['5EA7-106', '5EA7-112'],
  'and «pedalier» finds it the same way'
);
select is(
  pg_temp.found('pata de cambio'),
  array['5EA7-111'],
  '«pata de cambio» is the «postiza» the name says'
);
select is(
  pg_temp.found('patines'),
  array['5EA7-113'],
  '«patines» are the rim brake pads'
);
select is(
  pg_temp.found('zapatas'),
  array['5EA7-113'],
  'and so are «zapatas»'
);
select is(
  pg_temp.ranked('cable de freno'),
  array['5EA7-114'],
  '«cable» is the «piola»'
);
select is(
  pg_temp.found('desviador shimano'),
  array['5EA7-115'],
  '«desviador» is the «cambio trasero»'
);
select is(
  pg_temp.found('balatas'),
  array['5EA7-109'],
  '«balatas» are the pads'
);
select is(
  pg_temp.found('cubierta 700c'),
  array['5EA7-108'],
  '«cubierta» is a tyre and «700c» the 700 its name says'
);
select is(
  pg_temp.found('camara para bicicleta aro 29'),
  array['5EA7-102'],
  'joining words ask nothing and «bicicleta» is not required'
);
select is(
  pg_temp.found('av'),
  array['5EA7-102'],
  'two letters start a word: «av» is not found inside «llave»'
);
select is(
  pg_temp.found('neumatico 29'),
  array['5EA7-103'],
  'a tube is no longer a tyre'
);
select is(
  (select count(*)::integer from public.get_public_products_without_inventory_reservations(
    '5ea70000-0000-4000-8000-000000000001', null, null, null, null, null,
    false, 'name', 100, 0
  )),
  16,
  'without a term every product passes'
);
select is(
  pg_temp.found('kenda moser'),
  array['5EA7-103'],
  'a plain search still answers as before'
);

-- The vocabulary is data, normalized, and closed to the public keys.
select ok(
  (select count(*) from public.catalog_search_terms where tenant_id is null) >= 90,
  'the shared vocabulary is seeded'
);
select throws_ok(
  $$insert into public.catalog_search_terms (concept, terms) values ('mal', array['Válvula'])$$,
  '23514',
  null,
  'a word is stored as the search compares it'
);
select throws_ok(
  $$insert into public.catalog_search_terms (concept, kind, terms) values ('mal', 'pieza', array['x'])$$,
  '23514',
  null,
  'a concept is a part or an attribute'
);
select ok(
  not has_table_privilege('anon', 'public.catalog_search_terms', 'select'),
  'the public key does not read the vocabulary table'
);

select * from finish();
rollback;
