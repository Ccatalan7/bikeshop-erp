begin;

select no_plan();

-- Los números como se escriben (20261028010000). El 2026-10-28 el dueño
-- probó la caja en el teléfono: «neumatico 27» no encontraba nada, y en el
-- camino a cada medida («neumatico 2», «27.5 x 2», «2.2», «cassette 11-3»)
-- tampoco, porque un número tenía que estar completo.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('7a9e0000-0000-4000-8000-000000000001', 'Tienda de los números',
  'numeros@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, website_price_mode, category_name,
  brand, description
) values
  ('7a9e0000-0000-4000-8000-000000000101', '7a9e0000-0000-4000-8000-000000000001',
   'Neumático CST AT C1820 27.5 x 2.10', null, 'NU-101', 22000, 8000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'CST', null),
  ('7a9e0000-0000-4000-8000-000000000102', '7a9e0000-0000-4000-8000-000000000001',
   'Neumático Maxxis Rekon Race 27.5 x 2.25 EXO', null, 'NU-102', 30000, 12000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Maxxis', null),
  ('7a9e0000-0000-4000-8000-000000000103', '7a9e0000-0000-4000-8000-000000000001',
   'Neumático Chaoyang Double Hammer 29 x 2.25 27TPI', null, 'NU-103', 18000, 6000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Chaoyang', null),
  ('7a9e0000-0000-4000-8000-000000000104', '7a9e0000-0000-4000-8000-000000000001',
   'Neumático Freedom Roadrunner 700 x 25C', null, 'NU-104', 16000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Freedom', null),
  ('7a9e0000-0000-4000-8000-000000000105', '7a9e0000-0000-4000-8000-000000000001',
   'Cinta tubeless Deemount 27 mm x 10 m', null, 'NU-105', 9000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cintas de llanta', 'Deemount', null),
  ('7a9e0000-0000-4000-8000-000000000106', '7a9e0000-0000-4000-8000-000000000001',
   'Cassette Shimano CS-HG41 8 velocidades 11-34T', null, 'NU-106', 25000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cassettes', 'Shimano', null),
  ('7a9e0000-0000-4000-8000-000000000107', '7a9e0000-0000-4000-8000-000000000001',
   'Cámara Kenda aro 20 x 1.75-2.20 válvula auto', null, 'NU-107', 4000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras', 'Kenda', null),
  ('7a9e0000-0000-4000-8000-000000000108', '7a9e0000-0000-4000-8000-000000000001',
   'Cámara Maxxis aro 27.5 x 1.75-2.40 válvula presta', null, 'NU-108', 7000, 2500, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras', 'Maxxis', null),
  ('7a9e0000-0000-4000-8000-000000000109', '7a9e0000-0000-4000-8000-000000000001',
   'Llanta Weinmann U28 aro 27,5 32 hoyos', null, 'NU-109', 28000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Llantas', 'Weinmann', null),
  ('7a9e0000-0000-4000-8000-000000000110', '7a9e0000-0000-4000-8000-000000000001',
   'Cámara CST aro 26 x 1.50-2.20 válvula auto', null, 'NU-110', 4000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras', 'CST', null),
  -- What a customer typed on 2026-10-28 and did not find, or found wrong.
  ('7a9e0000-0000-4000-8000-000000000111', '7a9e0000-0000-4000-8000-000000000001',
   'Casco MTB Giro Fixture negro', null, 'NU-111', 45000, 20000, 19,
   'product', false, 'inventory', true, 0, 0, true, true, true, 'exact', 'Cascos', 'Giro', null),
  ('7a9e0000-0000-4000-8000-000000000112', '7a9e0000-0000-4000-8000-000000000001',
   'Pastillas de freno disco Shimano B01S resina', null, 'NU-112', 9000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Pastillas', 'Shimano', null),
  ('7a9e0000-0000-4000-8000-000000000113', '7a9e0000-0000-4000-8000-000000000001',
   'Cambio trasero Shimano Altus 8 velocidades', null, 'NU-113', 25000, 9000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Desviador Trasero', 'Shimano', null),
  ('7a9e0000-0000-4000-8000-000000000114', '7a9e0000-0000-4000-8000-000000000001',
   'Desviador delantero Shimano Tourney abrazadera 31.8 mm', null, 'NU-114', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Desviadores delanteros', 'Shimano', null),
  ('7a9e0000-0000-4000-8000-000000000115', '7a9e0000-0000-4000-8000-000000000001',
   'Purgado de frenos hidráulicos', null, 'NU-115', 15000, 0, 19,
   'service', true, 'service', false, 0, 0, true, true, true, 'exact', 'Frenos', null,
   'Cambio del aceite mineral y regulación.'),
  ('7a9e0000-0000-4000-8000-000000000116', '7a9e0000-0000-4000-8000-000000000001',
   'Bolitas de rodamiento 7/32 bolsa de 144', null, 'NU-116', 3000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Rodamientos', null,
   'Para la mantención de la maza.'),
  ('7a9e0000-0000-4000-8000-000000000117', '7a9e0000-0000-4000-8000-000000000001',
   'Lentes fotocromáticos SCVCN', null, 'NU-117', 30000, 10000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Lentes', 'SCVCN', null),
  ('7a9e0000-0000-4000-8000-000000000118', '7a9e0000-0000-4000-8000-000000000001',
   'Roldana de cambio trasero 13 dientes', null, 'NU-118', 3000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Roldanas', null, null),
  ('7a9e0000-0000-4000-8000-000000000119', '7a9e0000-0000-4000-8000-000000000001',
   'Guantes cortos con gel', null, 'NU-119', 12000, 4000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Guantes', null,
   'Los usamos en el taller.'),
  ('7a9e0000-0000-4000-8000-000000000120', '7a9e0000-0000-4000-8000-000000000001',
   'Mantención Full bici rígida', null, 'NU-120', 45000, 0, 19,
   'service', true, 'service', false, 0, 0, true, true, true, 'exact', 'Servicios', null, null),
  ('7a9e0000-0000-4000-8000-000000000121', '7a9e0000-0000-4000-8000-000000000001',
   'Cubre cámara de goma', null, 'NU-121', 1000, 300, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cubre Cámara', null, null),
  -- The second round (20261028040000).
  ('7a9e0000-0000-4000-8000-000000000122', '7a9e0000-0000-4000-8000-000000000001',
   'Guante Radical Mountain Largo 1771 L', null, 'NU-122', 14000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Guantes', 'Radical Mountain', null),
  ('7a9e0000-0000-4000-8000-000000000123', '7a9e0000-0000-4000-8000-000000000001',
   'Eje de motor punta cuadrada 122 mm', null, 'NU-123', 6000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Ejes de motor', null, null),
  ('7a9e0000-0000-4000-8000-000000000124', '7a9e0000-0000-4000-8000-000000000001',
   'Soporte de celular para manubrio', null, 'NU-124', 8000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Accesorios', null, null),
  ('7a9e0000-0000-4000-8000-000000000125', '7a9e0000-0000-4000-8000-000000000001',
   'Pedal aluminio MTB 9/16 (par)', null, 'NU-125', 15000, 5000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Plataformas', null, null);

set local session_replication_role = origin;

create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '7a9e0000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.found(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '7a9e0000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

-- «27»: a 27.5 being typed, or the old 27" (630); the store has no 630.
select is(pg_temp.found('neumatico 27'), array['NU-101', 'NU-102'],
  '«neumatico 27» finds the 27.5 tyres, not a 29 that says «27TPI»');
select is(pg_temp.found('camara 27'), array['NU-108'], 'and «camara 27» the 27.5 tube');
select is(pg_temp.found('llanta 27'), array['NU-109'], '«llanta 27» the 27,5 rim');
select is((pg_temp.ranked('neumatico 27 x 2.10'))[1], 'NU-101',
  'with its width after it, the 27.5 x 2.10 first');
select ok(not 'NU-103' = any (pg_temp.found('neumatico 27 x 2.10')),
  'and no 29 there');
select is(pg_temp.found('neumatico 27 5'), array['NU-101', 'NU-102'],
  '«27 5» is a 27.5 typed without its point');
select ok(
  not 'NU-105' = any (pg_temp.found('aro 27'))
  and 'NU-109' = any (pg_temp.found('aro 27')),
  '«aro 27» is a wheel size, not a 27 mm tape');
select is(pg_temp.found('cinta 27 mm'), array['NU-105'],
  'a number followed by «mm» is no wheel: «cinta 27 mm» finds the tape');

-- The last word, while it is typed.
select is(pg_temp.found('neumatico 2'), array['NU-101', 'NU-102', 'NU-103', 'NU-104'],
  '«neumatico 2» already lists tyres');
select is(pg_temp.found('neumatico 27.5 x 2'), array['NU-101', 'NU-102'],
  '«27.5 x 2» on the way to the width');
select is(pg_temp.found('neumatico 2.2'), array['NU-102', 'NU-103'],
  '«2.2» on the way to 2.25, not 2.10');
select is(pg_temp.found('cassette 11-3'), array['NU-106'],
  '«cassette 11-3» on the way to 11-34');
select is(pg_temp.found('camara 2'), array['NU-107', 'NU-108', 'NU-110'],
  '«camara 2» lists the tubes');

-- The left edge holds: a number never starts inside another.
select is(pg_temp.found('camara 20'), array['NU-107'],
  '«camara 20» is the 20 tube, not the 26 that says «2.20»');
select is(pg_temp.found('neumatico 25'), array['NU-104'],
  '«25» starts «25C», never inside «2.25»');
select is(pg_temp.found('neumatico 29 x 2.25'), array['NU-103'],
  'a complete measure still decides');

-- As a customer types (20261028020000). The store's words first.
select ok(public.catalog_search_documents_refresh_v1() > 0, 'the documents are built');
select ok(
  (select count(*) from public.catalog_search_words
    where tenant_id = '7a9e0000-0000-4000-8000-000000000001' and word = 'pastillas') = 1,
  'and with them the store''s words');

select is(pg_temp.found('kasco'), array['NU-111'], '«kasco» is the helmet');
select is(pg_temp.found('pastiyas'), array['NU-112'], '«pastiyas» (ll typed as y) the pads');
select is(pg_temp.found('pastillas fremo'), array['NU-112'], '«fremo» one letter off «freno»');
select is(pg_temp.found('pastillas b01s'), array['NU-112'], 'a pad''s model as it is written');
select ok((pg_temp.ranked('nuematico'))[1] in ('NU-101', 'NU-102', 'NU-103', 'NU-104'),
  '«nuematico» lists a tyre first, not the rim strip');
select is(pg_temp.found('neumatc'), array['NU-101', 'NU-102', 'NU-103', 'NU-104'],
  'a typo still being typed');
select is(pg_temp.found('lentes'), array['NU-117'], '«lentes» is the glasses, not a pulley with «dientes»');
select is(pg_temp.found('cambio delantero'), array['NU-114'],
  '«cambio delantero» the front derailleur, no rear one');
select ok(
  (pg_temp.ranked('cambio trasero'))[1] = 'NU-113'
  and not 'NU-114' = any (pg_temp.found('cambio trasero')),
  '«cambio trasero» the rear derailleur first, no front one');
select is(pg_temp.found('sangrado'), array['NU-115'], '«sangrado» is the «purgado» service');
select is(pg_temp.found('mantencion'), array['NU-120'],
  '«mantencion» the service, not ball bearings whose description mentions it');
select ok(not 'NU-119' = any (pg_temp.found('taller')),
  '«taller» lists no gloves whose description mentions it');
select is(pg_temp.found('taller'), array['NU-115', 'NU-120'],
  'but every service of the workshop (20261028030000)');
select is(pg_temp.found('arreglo frenos'), array['NU-115'], '«arreglo frenos» the brake service');

select is(pg_temp.found('guantes largos'), array['NU-122'], '«guantes largos» the long glove, named «Largo»');
select is(pg_temp.found('eje cuadrado'), array['NU-123'], '«eje cuadrado» the axle with «punta cuadrada»');
select is(pg_temp.found('pedales'), array['NU-125'], '«pedales» the «Pedal»');
select is(pg_temp.found('porta celular'), array['NU-124'], '«porta celular» the phone holder');
select ok('NU-108' = any (pg_temp.found('camara valvula fina'))
  and not 'NU-107' = any (pg_temp.found('camara valvula fina')),
  '«valvula fina» is presta, not auto');
select ok(
  coalesce(public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'cono'), '') <> 'con',
  '«cono» is never corrected to «con»');

select is(
  public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'Kasco'),
  'casco', 'the store is told what was searched instead');
select is(
  public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'Pastiyas de freno'),
  'pastillas de freno', 'every word, joining ones kept');
select ok(
  public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'casco') is null
  and public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'neumati') is null
  and public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'camara 2') is null
  and public.get_public_search_correction_v1('7a9e0000-0000-4000-8000-000000000001', 'taller') is null,
  'nothing when the words are the store''s, begin one, are numbers or a service word');
select ok(
  has_function_privilege('anon', 'public.get_public_search_correction_v1(uuid,text)', 'execute')
  and not has_table_privilege('anon', 'public.catalog_search_words', 'select')
  and not has_function_privilege('anon', 'public.catalog_search_correct_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_words_rebuild_v1(uuid)', 'execute'),
  'the store asks for the correction; the words stay closed');

select * from finish();

rollback;
