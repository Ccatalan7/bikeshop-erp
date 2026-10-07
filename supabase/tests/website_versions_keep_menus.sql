-- «Versiones guardadas» (2026-10-06): una versión guarda bloques, ajustes y
-- también los menús; volver a ella deja los menús como estaban (padres e
-- hijos) y los datos de cada página, sin romperse por un bloque de una página
-- borrada después, crea antes una versión «Antes de volver a …», y sólo
-- quedan las últimas 30 automáticas (las con nombre no se podan). Quien puede
-- editar el sitio sin ser administrador deja la versión automática de su
-- «Guardar», pero no restaura. Otra tienda no ve ni restaura la versión.
begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants(id, shop_name) values
  ('e2860000-0000-4000-8000-000000000001', 'Tienda versiones'),
  ('e2860000-0000-4000-8000-000000000002', 'Otra tienda');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2860000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'versiones@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2860000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'otra-tienda@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2860000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'editor@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles(user_id, tenant_id, role) values
  ('e2860000-0000-4000-8000-000000000091', 'e2860000-0000-4000-8000-000000000001', 'admin'),
  ('e2860000-0000-4000-8000-000000000092', 'e2860000-0000-4000-8000-000000000002', 'admin');
insert into public.user_profiles(user_id, tenant_id, role, permissions) values
  ('e2860000-0000-4000-8000-000000000093', 'e2860000-0000-4000-8000-000000000001',
   'manager', '{"edit_settings": true}'::jsonb);

create or replace function pg_temp.as_user(p_user text)
returns void
language sql
as $$
  select set_config('request.jwt.claims', jsonb_build_object(
           'sub', 'e2860000-0000-4000-8000-0000000000' || p_user,
           'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub',
           'e2860000-0000-4000-8000-0000000000' || p_user, true);
$$;

select pg_temp.as_user('91');

-- La tienda nueva trae su menú por defecto (Inicio, Productos, Contacto);
-- se le agrega un padre con un hijo, y un ajuste.
insert into public.website_navigation(
  id, tenant_id, menu_location, label, link_type, link_value, parent_id, order_index
) values
  ('e2860000-0000-4000-8000-000000000101', 'e2860000-0000-4000-8000-000000000001',
   'header', 'Componentes', 'category', 'componentes', null, 1),
  ('e2860000-0000-4000-8000-000000000102', 'e2860000-0000-4000-8000-000000000001',
   'header', 'Frenos', 'category', 'frenos',
   'e2860000-0000-4000-8000-000000000101', 1);
insert into public.website_settings(tenant_id, key, value) values
  ('e2860000-0000-4000-8000-000000000001', 'store_name', 'Antes');

-- Una página con su título y un bloque, y otra que se borrará después.
insert into public.website_pages(id, tenant_id, slug, title, meta_title, is_published) values
  ('e2860000-0000-4000-8000-000000000201', 'e2860000-0000-4000-8000-000000000001',
   'version-uno', 'Versión uno', 'Quiénes somos', true),
  ('e2860000-0000-4000-8000-000000000202', 'e2860000-0000-4000-8000-000000000001',
   'version-temporal', 'Temporal', null, true);
insert into public.website_blocks(id, tenant_id, page_id, block_type, block_data, order_index) values
  ('e2860000-0000-4000-8000-000000000301', 'e2860000-0000-4000-8000-000000000001',
   'e2860000-0000-4000-8000-000000000201', 'text', '{"title":"Hola"}'::jsonb, 0),
  ('e2860000-0000-4000-8000-000000000302', 'e2860000-0000-4000-8000-000000000001',
   'e2860000-0000-4000-8000-000000000202', 'text', '{"title":"Se va"}'::jsonb, 0);

create temp table version_ids(name text primary key, id uuid);
grant all on version_ids to public;

-- La deja quien edita el sitio sin ser administrador, al guardar.
select pg_temp.as_user('93');
insert into version_ids
select 'antes', public.record_website_version('Al guardar · /', 'Menús.');
select throws_ok(
  format('select public.restore_website_backup(%L, true)',
         (select id from version_ids where name = 'antes')),
  '42501',
  null,
  'quien edita sin ser administrador no restaura'
);
select pg_temp.as_user('91');

select is(
  (select jsonb_array_length(navigation_snapshot) from public.website_backups
    where id = (select id from version_ids where name = 'antes')),
  5,
  'la versión guarda las cinco filas del menú'
);

-- Después: el hijo se borra, se agrega otro ítem y cambia el ajuste.
delete from public.website_navigation
 where id = 'e2860000-0000-4000-8000-000000000102';
insert into public.website_navigation(
  id, tenant_id, menu_location, label, link_type, link_value, order_index
) values
  ('e2860000-0000-4000-8000-000000000103', 'e2860000-0000-4000-8000-000000000001',
   'header', 'Ofertas', 'page', 'ofertas', 2);
update public.website_settings set value = 'Después'
 where tenant_id = 'e2860000-0000-4000-8000-000000000001' and key = 'store_name';
update public.website_pages set meta_title = 'Otro título', is_published = false
 where id = 'e2860000-0000-4000-8000-000000000201';
delete from public.website_pages
 where id = 'e2860000-0000-4000-8000-000000000202';

-- Otra tienda no puede volver a esa versión.
select pg_temp.as_user('92');
select throws_ok(
  format('select public.restore_website_backup(%L, true)',
         (select id from version_ids where name = 'antes')),
  '42501',
  null,
  'otra tienda no restaura la versión'
);
select pg_temp.as_user('91');
select ok(
  public.restore_website_backup(
    (select id from version_ids where name = 'antes'), true),
  'volver a la versión'
);

select set_eq(
  $$select label, coalesce(parent_id::text, '-') from public.website_navigation
     where tenant_id = 'e2860000-0000-4000-8000-000000000001'$$,
  $$values ('Inicio', '-'), ('Productos', '-'), ('Contacto', '-'),
           ('Componentes', '-'),
           ('Frenos', 'e2860000-0000-4000-8000-000000000101')$$,
  'los menús vuelven con su padre e hijo, sin el ítem agregado después'
);
select is(
  (select meta_title || ' · ' || is_published::text from public.website_pages
    where id = 'e2860000-0000-4000-8000-000000000201'),
  'Quiénes somos · true',
  'la página vuelve a su título en Google y publicada'
);
select is(
  (select count(*)::int from public.website_blocks
    where id in ('e2860000-0000-4000-8000-000000000301',
                 'e2860000-0000-4000-8000-000000000302')),
  1,
  'el bloque de la página borrada queda fuera'
);
select is(
  (select block_data->>'title' from public.website_blocks
    where id = 'e2860000-0000-4000-8000-000000000301'),
  'Hola',
  'el bloque de la página que sigue vuelve'
);
select is(
  (select value from public.website_settings
    where tenant_id = 'e2860000-0000-4000-8000-000000000001'
      and key = 'store_name'),
  'Antes',
  'los ajustes vuelven'
);
select is(
  (select count(*)::int from public.website_backups
    where tenant_id = 'e2860000-0000-4000-8000-000000000001'
      and name = 'Antes de volver a «Al guardar · /»'),
  1,
  'antes de volver se guardó cómo estaba'
);

-- Una versión antigua sin menús no los toca.
update public.website_backups set navigation_snapshot = null
 where id = (select id from version_ids where name = 'antes');
select ok(
  public.restore_website_backup(
    (select id from version_ids where name = 'antes'), false),
  'volver a una versión sin menús'
);
select is(
  (select count(*)::int from public.website_navigation
    where tenant_id = 'e2860000-0000-4000-8000-000000000001'),
  5,
  'sin menús en la versión, los menús quedan como están'
);

-- Quedan las últimas 30 automáticas; las con nombre no se podan.
select public.create_website_backup('Con nombre', null, false);
select public.create_website_backup('Al guardar · /' || n, null, true)
  from generate_series(1, 35) n;
select is(
  (select count(*)::int from public.website_backups
    where tenant_id = 'e2860000-0000-4000-8000-000000000001'
      and is_auto_backup),
  30,
  'quedan 30 versiones automáticas'
);
select is(
  (select count(*)::int from public.website_backups
    where tenant_id = 'e2860000-0000-4000-8000-000000000001'
      and not is_auto_backup),
  1,
  'la versión con nombre sigue'
);
select is(
  (select count(*)::int from public.website_backups
    where tenant_id = 'e2860000-0000-4000-8000-000000000002'),
  0,
  'la otra tienda no tiene versiones'
);

select * from finish();
rollback;
