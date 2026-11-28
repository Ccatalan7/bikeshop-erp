begin;

select no_plan();

-- The stamp the store server asks before trusting a page it kept
-- (20261128083000). What the site editor writes moves it within the same
-- transaction, shop by shop. The write counters of the other tables move
-- only after a commit, so they cannot be seen from inside this transaction:
-- the read-back verify_public_storefront_change_stamp.sql covers the list.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('c5a90000-0000-4000-8000-000000000001', 'Tienda de la huella',
   'huella@example.invalid', 'America/Santiago', true),
  ('c5a90000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra-huella@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value) values
  ('c5a90000-0000-4000-8000-000000000001', 'store_name', 'Tienda de la huella'),
  ('c5a90000-0000-4000-8000-000000000002', 'store_name', 'Otra tienda');

insert into public.website_pages (id, tenant_id, slug, title, is_published)
values
  ('c5a90000-0000-4000-8000-000000000501',
   'c5a90000-0000-4000-8000-000000000001', 'inicio', 'Inicio', true),
  ('c5a90000-0000-4000-8000-000000000502',
   'c5a90000-0000-4000-8000-000000000002', 'inicio', 'Inicio', true);

insert into public.website_blocks
  (id, tenant_id, page_id, block_type, block_data, order_index, is_visible)
values
  ('c5a90000-0000-4000-8000-000000000601',
   'c5a90000-0000-4000-8000-000000000001',
   'c5a90000-0000-4000-8000-000000000501', 'text',
   '{"text": "Hola"}'::jsonb, 0, true),
  ('c5a90000-0000-4000-8000-000000000602',
   'c5a90000-0000-4000-8000-000000000002',
   'c5a90000-0000-4000-8000-000000000502', 'text',
   '{"text": "Hola"}'::jsonb, 0, true);

insert into public.website_navigation
  (id, tenant_id, menu_location, label, link_type, link_value, order_index,
   is_visible)
values
  ('c5a90000-0000-4000-8000-000000000401',
   'c5a90000-0000-4000-8000-000000000001', 'header', 'Productos', 'url',
   '/productos', 1, true);

reset session_replication_role;

create temporary table stamps (moment text primary key, stamp text not null)
  on commit drop;
grant select, insert on stamps to anon;

select ok(
  has_function_privilege('anon',
    'public.get_public_storefront_change_stamp_v1(uuid)', 'EXECUTE'),
  'la llave pública puede preguntar la huella');
select ok(
  not has_function_privilege('anon',
    'private.public_storefront_watched_tables_v1()', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'private.public_storefront_watched_tables_v1()', 'EXECUTE'),
  'la lista de tablas no queda al alcance de la API');
select is(
  (select p.prosecdef and p.proconfig = array['search_path=""']
     from pg_proc p
    where p.oid =
      'public.get_public_storefront_change_stamp_v1(uuid)'::regprocedure),
  true,
  'corre como su dueño y sin ruta de búsqueda');
select ok(
  (select count(*) = count(distinct name) and count(*) >= 40
     from unnest(private.public_storefront_watched_tables_v1()) as w(name)),
  'la lista nombra cada tabla una vez');

set local role anon;

insert into stamps values
  ('inicio', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000001')),
  ('otra', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000002'));

select matches(
  (select stamp from stamps where moment = 'inicio'),
  '^[0-9a-f]{32}$',
  'la huella es un md5: dice que algo cambió, no qué');
select is(
  public.get_public_storefront_change_stamp_v1(
    'c5a90000-0000-4000-8000-000000000001'),
  (select stamp from stamps where moment = 'inicio'),
  'sin escrituras la huella es la misma');
select isnt(
  (select stamp from stamps where moment = 'inicio'),
  (select stamp from stamps where moment = 'otra'),
  'cada tienda tiene la huella de su propio sitio');

reset role;

-- A block the editor saves: the very next question sees it.
update public.website_blocks
   set block_data = '{"text": "Hola de nuevo"}'::jsonb
 where id = 'c5a90000-0000-4000-8000-000000000601';

set local role anon;
insert into stamps values
  ('bloque', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000001'));
select isnt(
  (select stamp from stamps where moment = 'bloque'),
  (select stamp from stamps where moment = 'inicio'),
  'un bloque editado mueve la huella en la misma transacción');
select is(
  public.get_public_storefront_change_stamp_v1(
    'c5a90000-0000-4000-8000-000000000002'),
  (select stamp from stamps where moment = 'otra'),
  'y no la de la otra tienda');
reset role;

-- A setting, a page and a menu item each move it; so does a deleted row.
update public.website_settings
   set value = 'Tienda renombrada'
 where tenant_id = 'c5a90000-0000-4000-8000-000000000001'
   and key = 'store_name';

set local role anon;
insert into stamps values
  ('ajuste', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000001'));
select isnt(
  (select stamp from stamps where moment = 'ajuste'),
  (select stamp from stamps where moment = 'bloque'),
  'un ajuste del sitio mueve la huella');
reset role;

update public.website_pages
   set title = 'Portada'
 where id = 'c5a90000-0000-4000-8000-000000000501';

set local role anon;
insert into stamps values
  ('pagina', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000001'));
select isnt(
  (select stamp from stamps where moment = 'pagina'),
  (select stamp from stamps where moment = 'ajuste'),
  'una página editada mueve la huella');
reset role;

delete from public.website_navigation
 where id = 'c5a90000-0000-4000-8000-000000000401';

set local role anon;
insert into stamps values
  ('menu', public.get_public_storefront_change_stamp_v1(
     'c5a90000-0000-4000-8000-000000000001'));
select isnt(
  (select stamp from stamps where moment = 'menu'),
  (select stamp from stamps where moment = 'pagina'),
  'un ítem de menú borrado mueve la huella');
reset role;

select * from finish();
rollback;
