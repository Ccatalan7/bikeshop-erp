begin;

select no_plan();

-- Presencia en internet (20261014150000): las cifras de Google por tenant,
-- sólo de lectura para la app.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('e7b00000-0000-4000-8000-000000000001', 'Tienda con presencia',
  'presencia@example.invalid', 'America/Santiago', true),
       ('e7b00000-0000-4000-8000-000000000002', 'Otra tienda',
  'otra-presencia@example.invalid', 'America/Santiago', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e7b00000-0000-4000-8000-000000000090', 'authenticated', 'authenticated',
   'presencia-admin@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', 'e7b00000-0000-4000-8000-000000000001'), now(), now()),
  ('e7b00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'presencia-mecanico@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', 'e7b00000-0000-4000-8000-000000000001'), now(), now()),
  ('e7b00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'presencia-otra@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', 'e7b00000-0000-4000-8000-000000000002'), now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('e7b00000-0000-4000-8000-000000000090', 'e7b00000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('e7b00000-0000-4000-8000-000000000091', 'e7b00000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb, true),
  ('e7b00000-0000-4000-8000-000000000092', 'e7b00000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

insert into public.web_presence_search_daily (tenant_id, day, clicks, impressions, position) values
  ('e7b00000-0000-4000-8000-000000000001', date '2026-10-01', 3, 100, 9.5),
  ('e7b00000-0000-4000-8000-000000000002', date '2026-10-01', 7, 300, 4.0);

-- Dos semanas: la consulta subió de la posición 14 a la 6.
insert into public.web_presence_search_terms (tenant_id, day, kind, term, clicks, impressions, position) values
  ('e7b00000-0000-4000-8000-000000000001', date '2026-10-08', 'query', 'taller bicicletas', 2, 30, 6),
  ('e7b00000-0000-4000-8000-000000000001', date '2026-10-09', 'query', 'taller bicicletas', 1, 10, 6),
  ('e7b00000-0000-4000-8000-000000000001', date '2026-10-01', 'query', 'taller bicicletas', 1, 25, 14),
  ('e7b00000-0000-4000-8000-000000000001', date '2026-10-08', 'query', 'repuestos', 0, 6, 50),
  ('e7b00000-0000-4000-8000-000000000002', date '2026-10-08', 'query', 'ajeno', 9, 90, 1);

set local session_replication_role = origin;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e7b00000-0000-4000-8000-000000000090', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'e7b00000-0000-4000-8000-000000000090', true);
set local role authenticated;

select results_eq($$
  select clicks from public.web_presence_search_daily order by day
$$, $$ values (3) $$, 'cada tienda ve sólo sus cifras');

select throws_ok($$
  insert into public.web_presence_search_daily (tenant_id, day, clicks, impressions)
  values ('e7b00000-0000-4000-8000-000000000001', date '2026-10-02', 99, 99)
$$, '42501', null, 'la app no escribe las cifras: sólo la función');

select results_eq($$
  select term, clicks, impressions, avg_position, previous_clicks, previous_impressions, previous_avg_position
    from public.web_presence_terms_v1('e7b00000-0000-4000-8000-000000000001', 'query',
      date '2026-10-08', date '2026-10-14', 10)
$$, $$ values
  ('taller bicicletas'::text, 3, 40, 6.0::numeric, 1, 25, 14.0::numeric),
  ('repuestos', 0, 6, 50.0, 0, 0, null::numeric)
$$, 'el período se compara con el anterior del mismo largo, con la posición ponderada');

select throws_ok($$
  select * from public.web_presence_terms_v1('e7b00000-0000-4000-8000-000000000002', 'query',
    date '2026-10-08', date '2026-10-14', 10)
$$, '42501', 'catalog_tenant_forbidden', 'no se leen las consultas de otra tienda');

select is(
  public.web_presence_save_settings_v1('e7b00000-0000-4000-8000-000000000001', 'p498064152', true)
    ->> 'ga4_property_id',
  '498064152', 'la propiedad de Analytics se guarda como número');

select is(
  (select ga4_property_id from public.web_presence_settings
    where tenant_id = 'e7b00000-0000-4000-8000-000000000001'),
  '498064152', 'y queda en la configuración de la tienda');

select throws_ok($$
  select public.invoke_web_presence_collect('collect')
$$, '42501', null, 'la app no dispara la recolección por la base');

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e7b00000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'e7b00000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_ok($$
  select public.web_presence_save_settings_v1('e7b00000-0000-4000-8000-000000000001', '1', true)
$$, '42501', 'catalog_edit_forbidden', 'un mecánico ve las cifras pero no cambia la configuración');
reset role;

select * from finish();
rollback;
