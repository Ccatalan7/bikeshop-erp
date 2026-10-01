begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Una línea corregida en un trabajo terminado escribe la ficha en la misma
-- transacción que la guarda, sin la llamada que la app hace después (ítem 4,
-- 2026-09-28). Si la app se cierra entre guardar la línea y esa llamada, la
-- ficha ya no queda atrás.

select has_trigger('public', 'mechanic_job_items',
  'trg_mechanic_job_items_installed_bike_facts_update',
  'cambiar una línea aplica lo instalado');
select has_trigger('public', 'mechanic_job_items',
  'trg_mechanic_job_items_installed_bike_facts_insert',
  'agregar una línea aplica lo instalado');

insert into public.tenants (id, shop_name) values
  ('e27a0000-0000-4000-8000-000000000001', 'Taller línea terminada');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e27a0000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'linea-terminada@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role) values
  ('e27a0000-0000-4000-8000-000000000099',
   'e27a0000-0000-4000-8000-000000000001', 'admin');
insert into public.customers (id, tenant_id, name) values
  ('e27a0000-0000-4000-8000-000000000010',
   'e27a0000-0000-4000-8000-000000000001', 'Cliente línea');
insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('e27a0000-0000-4000-8000-000000000031',
   'e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000010', 'Trek', 'Marlin 5');
insert into public.bike_profiles (tenant_id, bike_id, technical_profile) values (
  'e27a0000-0000-4000-8000-000000000001',
  'e27a0000-0000-4000-8000-000000000031',
  jsonb_build_object(
    'values', jsonb_build_object('rearSpokeHoles', 32),
    'sources', jsonb_build_object('rearSpokeHoles', 'intake'),
    'confirmed', jsonb_build_object('rearSpokeHoles', true)));
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e27a0000-0000-4000-8000-000000000051',
   'e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000010',
   'e27a0000-0000-4000-8000-000000000031', 'PG-LINEA-1',
   'e27a0000-0000-4000-8000-000000000099'),
  ('e27a0000-0000-4000-8000-000000000052',
   'e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000010',
   'e27a0000-0000-4000-8000-000000000031', 'PG-LINEA-2',
   'e27a0000-0000-4000-8000-000000000099');
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000051',
   'e27a0000-0000-4000-8000-000000000031'),
  ('e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000052',
   'e27a0000-0000-4000-8000-000000000031')
on conflict (job_id, bike_id) do nothing;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key,
  service_configuration_data, unit_price
) values
  ('e27a0000-0000-4000-8000-000000000061',
   'e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000051', 'Enrayado + Centrado',
   'service', 'rear', '{"hole_count": "28"}'::jsonb, 25000),
  ('e27a0000-0000-4000-8000-000000000062',
   'e27a0000-0000-4000-8000-000000000001',
   'e27a0000-0000-4000-8000-000000000052', 'Enrayado en curso',
   'service', 'front', '{"hole_count": "32"}'::jsonb, 25000);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e27a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e27a0000-0000-4000-8000-000000000099', true);

create temporary table results (label text primary key, result jsonb);
insert into results
select 'terminado', public.transition_mechanic_job_status(
  'e27a0000-0000-4000-8000-000000000051',
  (select id from public.job_statuses
    where tenant_id = 'e27a0000-0000-4000-8000-000000000001'
      and code = 'FINALIZADO'),
  'linea-terminado');

create function pg_temp.rear() returns jsonb language sql as $$
  select technical_profile->'values'->'rearSpokeHoles'
    from public.bike_profiles
   where bike_id = 'e27a0000-0000-4000-8000-000000000031'
$$;
create function pg_temp.receipts() returns integer language sql as $$
  select count(*)::integer
    from public.bike_technical_fact_patches
   where tenant_id = 'e27a0000-0000-4000-8000-000000000001'
$$;

select is(pg_temp.rear(), '28'::jsonb, 'terminar el trabajo escribe las 28H atrás');

-- ============================================================================
-- Corregir la línea escribe la ficha en la misma sentencia
-- ============================================================================

-- Lo que hace la app al guardar: un `update` de la línea, sin llamar después
-- a `sync_job_installed_bike_facts_v1` (la app se cerró ahí).
update public.mechanic_job_items
   set service_configuration_data = '{"hole_count": "32"}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000061';

select is(pg_temp.rear(), '32'::jsonb,
  'la ficha ya dice 32H sin la llamada de después');
select ok(
  exists (select 1 from public.bike_technical_fact_patches
           where operation_key = 'job_completion:e27a0000-0000-4000-8000-000000000061:2:rearSpokeHoles=32'),
  'con la siguiente llave de la línea, la misma que usaba la app');

-- Si el guardado de la línea se deshace, la ficha también.
savepoint antes_de_36;
update public.mechanic_job_items
   set service_configuration_data = '{"hole_count": "36"}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000061';
rollback to savepoint antes_de_36;

select is(pg_temp.rear(), '32'::jsonb,
  'una línea que no se guardó no deja la ficha en 36H');
select is(pg_temp.receipts(), 2, 'ni su recibo');

-- ============================================================================
-- Lo que no toca lo instalado no escribe nada
-- ============================================================================

-- La app manda la fila completa: cambiar el precio con la misma
-- configuración no es instalar otra vez.
update public.mechanic_job_items
   set unit_price = 30000,
       service_configuration_data = '{"hole_count": "32"}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000061';
select is(pg_temp.receipts(), 2, 'cambiar el precio no escribe la ficha');

-- En un trabajo sin terminar, configurar no cambia la ficha.
update public.mechanic_job_items
   set service_configuration_data = '{"hole_count": "24"}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000062';
select is(pg_temp.receipts(), 2, 'un trabajo en curso no instala');

-- ============================================================================
-- Agregar una línea a un trabajo terminado
-- ============================================================================

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key,
  service_configuration_data, unit_price
) values (
  'e27a0000-0000-4000-8000-000000000063',
  'e27a0000-0000-4000-8000-000000000001',
  'e27a0000-0000-4000-8000-000000000051', 'Enrayado delantero',
  'service', 'front', '{"hole_count": "28"}'::jsonb, 25000);

select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e27a0000-0000-4000-8000-000000000031'),
  '28'::jsonb,
  'la línea agregada instala su rueda al guardarse');

-- ============================================================================
-- Si la ficha no toma lo que instala la línea, la línea no se guarda
-- ============================================================================

-- Sin un empleado en la sesión el parche no escribe: antes la línea quedaba
-- en 36H y la ficha en 32H hasta que alguien llamara después.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "36"}'::jsonb
     where id = 'e27a0000-0000-4000-8000-000000000061'$$,
  '23514',
  null,
  'sin empleado, guardar la línea falla');
select is(
  (select service_configuration_data->>'hole_count'
     from public.mechanic_job_items
    where id = 'e27a0000-0000-4000-8000-000000000061'),
  '32',
  'la línea sigue en 32H');
select is(pg_temp.rear(), '32'::jsonb, 'y la ficha también: no quedan distintas');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e27a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e27a0000-0000-4000-8000-000000000099', true);

select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = '{"hole_count": "99"}'::jsonb
     where id = 'e27a0000-0000-4000-8000-000000000061'$$,
  '%fuera de 12 a 48%',
  'un número imposible en una línea terminada no se guarda');

update public.mechanic_job_items
   set service_configuration_data = '{"hole_count": "36"}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000061';
select is(pg_temp.rear(), '36'::jsonb, 'con empleado, línea y ficha pasan juntas a 36H');

-- ============================================================================
-- Borrar o desconfigurar una línea terminada queda en la historia de la bici
-- ============================================================================

create function pg_temp.notices(p_type text) returns integer language sql as $$
  select count(*)::integer
    from public.bike_events
   where bike_id = 'e27a0000-0000-4000-8000-000000000031'
     and source = 'installed_fact_notice'
     and event_type = p_type
     and severity = 'warning'
$$;

-- Si la historia de la bici no acepta el aviso, la línea no se borra: no se
-- va sin dejarlo. Se fuerza el fallo con un disparador de esta prueba.
create function public.test_reject_installed_fact_notice()
returns trigger language plpgsql as $$
begin
  if new.source = 'installed_fact_notice' then
    raise exception 'historia de la bici no disponible';
  end if;
  return new;
end;
$$;
create trigger zz_test_reject_installed_fact_notice
  before insert on public.bike_events
  for each row execute function public.test_reject_installed_fact_notice();

select throws_like(
  $$delete from public.mechanic_job_items
     where id = 'e27a0000-0000-4000-8000-000000000063'$$,
  '%historia de la bici no disponible%',
  'sin poder anotar el aviso, borrar la línea terminada falla');
select ok(
  exists (select 1 from public.mechanic_job_items
           where id = 'e27a0000-0000-4000-8000-000000000063'),
  'y la línea sigue ahí');
select throws_like(
  $$update public.mechanic_job_items
       set service_configuration_data = '{}'::jsonb
     where id = 'e27a0000-0000-4000-8000-000000000063'$$,
  '%historia de la bici no disponible%',
  'quitarle las perforaciones tampoco pasa sin su aviso');

-- Una línea borrada antes de que existiera este disparador (lo que se borró
-- antes de desplegar): nadie anotó su aviso.
alter table public.mechanic_job_items
  disable trigger trg_mechanic_job_items_installed_bike_facts_delete;
delete from public.mechanic_job_items
 where id = 'e27a0000-0000-4000-8000-000000000063';
alter table public.mechanic_job_items
  enable trigger trg_mechanic_job_items_installed_bike_facts_delete;

-- En la llamada que sigue al guardado el aviso es de mejor esfuerzo: si la
-- historia no lo acepta, la llamada no falla y la respuesta lo dice igual.
insert into results
select 'sync_sin_historia', public.sync_job_installed_bike_facts_v1(
  'e27a0000-0000-4000-8000-000000000051');
select is(
  (select count(*)::integer
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'sync_sin_historia'
      and problem->>'reason' = 'no_longer_installed'),
  1,
  'la llamada de después no falla por el aviso y lo dice en la respuesta');
select is(pg_temp.notices('installed_fact_unsupported'), 0,
  'aunque la historia no lo tenga todavía');

drop trigger zz_test_reject_installed_fact_notice on public.bike_events;

-- La próxima llamada lo recalcula desde los recibos y lo anota.
insert into results
select 'sync_con_historia', public.sync_job_installed_bike_facts_v1(
  'e27a0000-0000-4000-8000-000000000051');
select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e27a0000-0000-4000-8000-000000000031'),
  '28'::jsonb,
  'borrar la línea no deshace la ficha');
select is(pg_temp.notices('installed_fact_unsupported'), 1,
  'pero la historia de la bici avisa');
select ok(
  (select summary like '%28H en la rueda delantera%una línea que ya no está%'
     from public.bike_events
    where bike_id = 'e27a0000-0000-4000-8000-000000000031'
      and event_type = 'installed_fact_unsupported'),
  'con el dato y la línea que ya no está');

-- A la línea trasera le quitan las perforaciones.
update public.mechanic_job_items
   set service_configuration_data = '{}'::jsonb
 where id = 'e27a0000-0000-4000-8000-000000000061';
select is(pg_temp.notices('installed_fact_unsupported'), 2,
  'desconfigurarla también queda en la historia');

-- La llamada de después no repite los avisos.
insert into results
select 'sync', public.sync_job_installed_bike_facts_v1(
  'e27a0000-0000-4000-8000-000000000051');
select is(pg_temp.notices('installed_fact_unsupported'), 2,
  'cada aviso una sola vez');
select is(
  (select count(*)::integer
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'sync'
      and problem->>'reason' = 'no_longer_installed'),
  2,
  'y la respuesta los sigue diciendo mientras la ficha no se revise');

-- Borrar con el disparador activo deja el aviso en la misma sentencia, sin
-- ninguna llamada después.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key,
  service_configuration_data, unit_price
) values (
  'e27a0000-0000-4000-8000-000000000064',
  'e27a0000-0000-4000-8000-000000000001',
  'e27a0000-0000-4000-8000-000000000051', 'Enrayado delantero nuevo',
  'service', 'front', '{"hole_count": "32"}'::jsonb, 25000);
delete from public.mechanic_job_items
 where id = 'e27a0000-0000-4000-8000-000000000064';
select is(
  (select count(*)::integer
     from public.bike_events
    where bike_id = 'e27a0000-0000-4000-8000-000000000031'
      and source = 'installed_fact_notice'
      and event_type = 'installed_fact_unsupported'
      and payload->>'item_id' = 'e27a0000-0000-4000-8000-000000000064'),
  1,
  'borrar una línea terminada anota su aviso en la misma sentencia');

-- ============================================================================
-- Terminar un trabajo cuya ficha no toma lo instalado se revierte
-- ============================================================================

-- Sin empleado, el parche no tiene autoría. El cierre no puede prometer que
-- se instaló algo ni dejar un aviso como si el trabajo ya hubiera terminado.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e27a0000-0000-4000-8000-000000000052',
    (select id from public.job_statuses
      where tenant_id = 'e27a0000-0000-4000-8000-000000000001'
        and code = 'FINALIZADO'),
    'linea-2-terminado')$$,
  '23514', null,
  'un parche rechazado impide cerrar el trabajo');
select is(
  (select status from public.mechanic_jobs
    where id = 'e27a0000-0000-4000-8000-000000000052'),
  'PENDIENTE',
  'el trabajo sigue abierto');
select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e27a0000-0000-4000-8000-000000000031'),
  '32'::jsonb,
  'la ficha no tomó las 24H (sigue en las 32H de antes)');
select is(pg_temp.notices('installed_fact_pending'), 0,
  'el cierre rechazado no crea un aviso de instalación pendiente');

select is(
  (select count(*)::integer from public.mechanic_job_status_transition_events
   where operation_key = 'linea-2-terminado'),
  0,
  'un cierre rechazado no deja recibo y permite reintentar la misma llave');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e27a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e27a0000-0000-4000-8000-000000000099', true);
insert into results
select 'terminado_con_empleado', public.transition_mechanic_job_status(
  'e27a0000-0000-4000-8000-000000000052',
  (select id from public.job_statuses
    where tenant_id = 'e27a0000-0000-4000-8000-000000000001'
      and code = 'FINALIZADO'),
  'linea-2-terminado');
select is(
  (select result->>'status' from results where label = 'terminado_con_empleado'),
  'FINALIZADO',
  'con el empleado presente, el mismo intento puede terminar');

select * from finish();
rollback;
