begin;

select no_plan();

-- Una palabra se busca como palabra y una pieza pedida es esa pieza
-- (20261101010000). El 2026-11-01, con sólo lo que hay en stock, «grasa»
-- mostraba un cepillo, «rueda» un protector de plato, una roldana, agujas, un
-- gancho y un sellante, y «cono» un collerín y unas cubetas cuyo nombre de
-- proveedor termina en «ECONOM.».

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('7b10a000-0000-4000-8000-000000000001', 'Tienda de las palabras',
  'palabras@example.invalid', 'America/Santiago', true);

insert into public.products (
  id, tenant_id, name, website_name, sku, price, cost, tax_rate, product_type,
  is_service, purchase_treatment, track_stock, inventory_qty, stock_quantity,
  is_active, is_published, show_on_website, website_price_mode, category_name,
  brand, description
) values
  ('7b10a000-0000-4000-8000-000000000101', '7b10a000-0000-4000-8000-000000000001',
   'Grasa lubricante 50 g', null, 'WW-101', 5000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Grasa', null, null),
  -- Its category made it grease while the vocabulary did not know «cepillo».
  ('7b10a000-0000-4000-8000-000000000102', '7b10a000-0000-4000-8000-000000000001',
   'Cepillo limpiador de platos Rito PP-01', null, 'WW-102', 6000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact',
   'Grasa/Aceites/Solución', 'Rito', null),
  ('7b10a000-0000-4000-8000-000000000103', '7b10a000-0000-4000-8000-000000000001',
   'BLOQUEO AGUJA SILLIN ALUMINIO NEGRO GENERICO 2022 ECONOM.',
   'Collerín de asiento con cierre rápido', 'WW-103', 4000, 1500, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Collerín', null, null),
  ('7b10a000-0000-4000-8000-000000000104', '7b10a000-0000-4000-8000-000000000001',
   'Cono de maza delantera 3/8', null, 'WW-104', 2000, 700, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Conos', null, null),
  ('7b10a000-0000-4000-8000-000000000105', '7b10a000-0000-4000-8000-000000000001',
   'Centrador de ruedas profesional', null, 'WW-105', 90000, 40000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Herramientas', null, null),
  ('7b10a000-0000-4000-8000-000000000106', '7b10a000-0000-4000-8000-000000000001',
   'RUEDA DE CAMBIO MEGARANCE COMPATIBLE', 'Roldana de cambio trasero genérica', 'WW-106',
   3000, 1000, 19, 'product', false, 'inventory', true, 2, 2, true, true, true, 'exact',
   'Roldanas', null, null),
  ('7b10a000-0000-4000-8000-000000000107', '7b10a000-0000-4000-8000-000000000001',
   'Aguja de cierre rápido delantera aluminio', null, 'WW-107', 5000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Agujas', null,
   'Asegura la rueda a la horquilla.'),
  ('7b10a000-0000-4000-8000-000000000108', '7b10a000-0000-4000-8000-000000000001',
   'Gancho para colgar bicicleta', null, 'WW-108', 7000, 3000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', null, null,
   'Cuelga la bici de la rueda delantera.'),
  ('7b10a000-0000-4000-8000-000000000109', '7b10a000-0000-4000-8000-000000000001',
   'Líquido antipinchazo RaceLub 500 ml', null, 'WW-109', 6000, 2000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Líquido Tubeless', 'RaceLub', null),
  ('7b10a000-0000-4000-8000-000000000110', '7b10a000-0000-4000-8000-000000000001',
   'Cubre cámara de goma aro 26', null, 'WW-110', 1000, 300, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cubre Cámara', null, null),
  ('7b10a000-0000-4000-8000-000000000111', '7b10a000-0000-4000-8000-000000000001',
   'Cámara Kenda aro 26 x 1.95 válvula auto', null, 'WW-111', 4000, 1000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Cámaras', 'Kenda', null),
  ('7b10a000-0000-4000-8000-000000000112', '7b10a000-0000-4000-8000-000000000001',
   'Neumático Kenda aro 26 x 1.95', null, 'WW-112', 15000, 6000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Neumáticos', 'Kenda', null),
  -- The supplier's title says «de rueda»; the shop's name, a chainring guard.
  ('7b10a000-0000-4000-8000-000000000113', '7b10a000-0000-4000-8000-000000000001',
   'Protector de anillo de rueda de cadena 104BCD', 'Protector de plato 104 BCD', 'WW-113',
   5000, 2000, 19, 'product', false, 'inventory', true, 2, 2, true, true, true, 'exact',
   'Protectores', null, null),
  ('7b10a000-0000-4000-8000-000000000114', '7b10a000-0000-4000-8000-000000000001',
   'Desengrasante RaceLub 1 litro', null, 'WW-114', 9000, 4000, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', 'Desengrasantes', 'RaceLub', null),
  -- No part at all: only «cono» inside «económico» found it.
  ('7b10a000-0000-4000-8000-000000000115', '7b10a000-0000-4000-8000-000000000001',
   'Pulpo elástico económico para carga', null, 'WW-115', 2000, 700, 19,
   'product', false, 'inventory', true, 2, 2, true, true, true, 'exact', null, null, null);

set local session_replication_role = origin;

create function pg_temp.ranked(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku), '{}')
  from public.get_public_products_without_inventory_reservations(
    '7b10a000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

create function pg_temp.found(p_term text)
returns text[]
language sql
as $$
  select coalesce(array_agg(r.sku order by r.sku collate "C"), '{}')
  from public.get_public_products_without_inventory_reservations(
    '7b10a000-0000-4000-8000-000000000001', null, null, null, p_term, null,
    false, 'name', 100, 0
  ) r
$$;

-- The rule, word by word.
select ok(public.catalog_search_has_word_v1('portacaramagiola negro', 'caramagiola'),
  'a word may end another: «caramagiola» in «portacaramagiola»');
select ok(public.catalog_search_has_word_v1('cubrecadenas', 'cadena'),
  'also in its plural');
select ok(public.catalog_search_has_word_v1('conos de maza', 'cono'),
  'a word starts a word: «cono» in «conos»');
select ok(not public.catalog_search_has_word_v1('collerin generico 2022 econom', 'cono'),
  'never inside one: «cono» is not in «econom»');
select ok(not public.catalog_search_has_word_v1('desengrasante racelub', 'grasa'),
  'nor «grasa» in «desengrasante»');
select ok(not public.catalog_search_has_word_v1('claro', 'aro'),
  'a three-letter word only starts a word: «aro» is not in «claro»');
select ok(
  not has_function_privilege('anon', 'public.catalog_search_has_word_v1(text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalog_search_has_word_v1(text, text)', 'execute'),
  'the rule stays closed to the public key'
);

-- The three searches of 2026-11-01.
select is(pg_temp.found('grasa'), array['WW-101'],
  '«grasa» finds the grease: not the brush its category named, nor the degreaser');
select is(pg_temp.found('cono'), array['WW-104'],
  '«cono» finds the cone, not «econom» nor «económico»');
select is(pg_temp.found('rueda'), array['WW-105'],
  '«rueda» finds the truing stand, which is for the wheel; not the jockey wheel '
  'its supplier calls «rueda de cambio», the guard whose supplier title says «de '
  'rueda», nor what only a description says');

-- A word's end and a description still count where they should.
select ok('WW-109' = any (pg_temp.found('pinchazo')),
  '«pinchazo» still finds «antipinchazo»: a word may end another');
select ok('WW-108' = any (pg_temp.found('delantera')),
  'without a part asked, a description still counts');

-- A cover is for the part its own name starts with.
select is((pg_temp.ranked('camara'))[1], 'WW-111', '«camara» lists the tube first');
select ok('WW-110' = any (pg_temp.found('camara')), 'and then the «Cubre cámara»');
select ok(not 'WW-110' = any (pg_temp.found('neumatico')),
  'which is not for the tyre although its rubber («goma») names one');
select ok('WW-110' = any (pg_temp.found('cubre camara')), '«cubre camara» finds it');
select ok('WW-113' = any (pg_temp.found('plato')), 'the chainring guard is for the chainring');

select * from finish();
rollback;
