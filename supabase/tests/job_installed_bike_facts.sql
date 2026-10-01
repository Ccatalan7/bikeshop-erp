begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Lo instalado cambia la ficha en la misma transacción que termina el
-- trabajo (ítem 4, 2026-09-28): la regla vive en el servidor y la app ya no la
-- calcula ni la envía después.

select ok(
  not has_function_privilege('authenticated',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE'),
  'la regla interna sólo la llaman los comandos del servidor');
select ok(
  has_function_privilege('authenticated',
    'public.sync_job_installed_bike_facts_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.sync_job_installed_bike_facts_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.sync_job_installed_bike_facts_v1(uuid)', 'EXECUTE'),
  'reaplicar lo instalado es de un empleado autenticado');
select ok(
  position('errcode = ''40001''' in pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)) = 0
  and position('errcode = ''serialization_failure''' in pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)) = 0
  and position('errcode = ''PT409''' in pg_get_functiondef(
    'public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)) > 0,
  'el conflicto de la transición no es un 40001 que PostgREST reintente sin fin');
select ok(
  position('Lo instalado toma el trabajo antes que la llave' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
  between 1 and position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)),
  'el parche de lo instalado toma el trabajo antes que la llave, como la transición');
select ok(
  position('for update' in pg_get_functiondef(
    'public.sync_job_installed_bike_facts_v1(uuid)'::regprocedure)) > 0,
  'dos sincronizaciones del mismo trabajo van una después de la otra');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2790000-0000-4000-8000-000000000001', 'Taller instalado A'),
  ('e2790000-0000-4000-8000-000000000002', 'Taller instalado B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2790000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'instalado-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2790000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'instalado-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2790000-0000-4000-8000-000000000099',
   'e2790000-0000-4000-8000-000000000001', 'admin'),
  ('e2790000-0000-4000-8000-000000000098',
   'e2790000-0000-4000-8000-000000000002', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2790000-0000-4000-8000-000000000010',
   'e2790000-0000-4000-8000-000000000001', 'Cliente instalado');

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('e2790000-0000-4000-8000-000000000031',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010', 'Trek', 'Marlin 5'),
  ('e2790000-0000-4000-8000-000000000032',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010', 'Oxford', 'Uno'),
  ('e2790000-0000-4000-8000-000000000033',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010', 'Oxford', 'Dos');

-- La Marlin tiene ficha: la rueda delantera dice 32H sin confirmar.
insert into public.bike_profiles (tenant_id, bike_id, technical_profile) values (
  'e2790000-0000-4000-8000-000000000001',
  'e2790000-0000-4000-8000-000000000031',
  jsonb_build_object(
    'values', jsonb_build_object('frontSpokeHoles', 32),
    'sources', jsonb_build_object('frontSpokeHoles', 'intake'),
    'confirmed', jsonb_build_object('frontSpokeHoles', false)
  )
);

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2790000-0000-4000-8000-000000000051',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010',
   'e2790000-0000-4000-8000-000000000031', 'PG-INST-1',
   'e2790000-0000-4000-8000-000000000099'),
  ('e2790000-0000-4000-8000-000000000052',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010',
   'e2790000-0000-4000-8000-000000000032', 'PG-INST-2',
   'e2790000-0000-4000-8000-000000000099');

-- Un trabajo de una bici y otro de dos.
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   'e2790000-0000-4000-8000-000000000031'),
  ('e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000052',
   'e2790000-0000-4000-8000-000000000032'),
  ('e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000052',
   'e2790000-0000-4000-8000-000000000033')
on conflict (job_id, bike_id) do nothing;

-- Trabajo 1: el Enrayado arma la trasera de 28H (rueda por la respuesta),
-- otro arma «ambas» (no instala una rueda) y otro dice 99H. Van en la pestaña
-- de su bici: una línea de General no es de ninguna (20261001195000).
-- Trabajo 2: una línea de General sin bici en un trabajo de dos, y una línea
-- de la Oxford Dos que arma su delantera de 36H.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_name, item_type, location_key,
  service_configuration_data
) values
  ('e2790000-0000-4000-8000-000000000061',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2790000-0000-4000-8000-000000000051'), 'Enrayado + Centrado',
   'service', 'none', '{"which_wheel": "rear", "hole_count": "28"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000062',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2790000-0000-4000-8000-000000000051'), 'Enrayado ambas',
   'service', 'none', '{"which_wheel": "both", "hole_count": "32"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000063',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2790000-0000-4000-8000-000000000051'), 'Enrayado mal tipeado',
   'service', 'front', '{"hole_count": "99"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000066',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2790000-0000-4000-8000-000000000051'), 'Enrayado sin rueda',
   'service', 'none', '{"hole_count": "28"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000067',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000051',
   (select id from public.mechanic_job_bikes where job_id = 'e2790000-0000-4000-8000-000000000051'), 'Enrayado raro',
   'service', 'rear', '{"hole_count": "28.5"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000064',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000052', null, 'Enrayado sin bici',
   'service', 'front', '{"hole_count": "28"}'::jsonb),
  ('e2790000-0000-4000-8000-000000000065',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000052',
   (select id from public.mechanic_job_bikes
     where job_id = 'e2790000-0000-4000-8000-000000000052'
       and bike_id = 'e2790000-0000-4000-8000-000000000033'),
   'Enrayado Oxford Dos', 'service', 'front', '{"hole_count": "36"}'::jsonb);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2790000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2790000-0000-4000-8000-000000000099', true);

create temporary table status_ids as
select code, id
  from public.job_statuses
 where tenant_id = 'e2790000-0000-4000-8000-000000000001';

create temporary table results (label text primary key, result jsonb);

-- ============================================================================
-- Un trabajo en curso no instala nada
-- ============================================================================

insert into results
select 'en_curso', public.transition_mechanic_job_status(
  'e2790000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'EN_CURSO'),
  'inst-en-curso');

select is(
  (select result->'installed_bike_facts' from results where label = 'en_curso'),
  'null'::jsonb,
  'un trabajo en curso no cambia la ficha');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where tenant_id = 'e2790000-0000-4000-8000-000000000001'),
  0,
  'ni deja recibos');

-- ============================================================================
-- Terminar el trabajo escribe lo instalado en la misma transacción
-- ============================================================================

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2790000-0000-4000-8000-000000000051',
    (select id from status_ids where code = 'FINALIZADO'),
    'inst-terminado')$$,
  '23514', null,
  '99H, la rueda ausente y 28.5H impiden cerrar un trabajo con destino ambiguo');
select is(
  (select status from public.mechanic_jobs
    where id = 'e2790000-0000-4000-8000-000000000051'),
  'EN_CURSO',
  'el cierre rechazado deja el estado anterior');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where tenant_id = 'e2790000-0000-4000-8000-000000000001'),
  0,
  'también deshace el parche válido de 28H');
select is(
  (select count(*)::integer from public.mechanic_job_status_transition_events
    where operation_key = 'inst-terminado'),
  0,
  'la llave rechazada no deja recibo y puede repetirse tras corregir');

-- El operador deja estas tres líneas como evidencia de servicio sin afirmar
-- que hayan instalado una rueda. La línea válida conserva 28H atrás.
update public.mechanic_job_items
   set service_configuration_data = '{}'::jsonb
 where id in (
   'e2790000-0000-4000-8000-000000000063',
   'e2790000-0000-4000-8000-000000000066',
   'e2790000-0000-4000-8000-000000000067'
 );
insert into results
select 'terminado', public.transition_mechanic_job_status(
  'e2790000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'inst-terminado');

select is(
  (select result->>'status' from results where label = 'terminado'),
  'FINALIZADO',
  'el trabajo termina');
select is(
  (select jsonb_path_query_array(result, '$.installed_bike_facts.applied[*].operation_key')
     from results where label = 'terminado'),
  '["job_completion:e2790000-0000-4000-8000-000000000061:1:rearSpokeHoles=28"]'::jsonb,
  'la trasera de 28H se escribe con la llave que ya usaba la app');
select is(
  (select technical_profile->'values'->'rearSpokeHoles' || jsonb_build_array(
            technical_profile->'confirmed'->'rearSpokeHoles',
            technical_profile->'sources'->'rearSpokeHoles')
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000031'),
  '[28, true, "job_completion"]'::jsonb,
  'la ficha dice 28H atrás, confirmado por el trabajo terminado');
select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000031'),
  '32'::jsonb,
  '«ambas» no instala una rueda y 99H no entra: la delantera sigue en 32H');
select is(
  (select jsonb_path_query_array(result, '$.installed_bike_facts.problems[*].reason')
     from results where label = 'terminado'),
  '[]'::jsonb,
  'tras corregir las líneas, el cierre no deja piezas ambiguas');
select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2790000-0000-4000-8000-000000000031'
      and job_id = 'e2790000-0000-4000-8000-000000000051'
      and source = 'job_completion'),
  1,
  'la historia de la bici cuenta el cambio');

-- ============================================================================
-- Repetir no escribe dos veces; una corrección de la ficha no se pisa
-- ============================================================================

insert into results
select 'replay', public.transition_mechanic_job_status(
  'e2790000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'inst-terminado');
insert into results
select 'mismo_estado', public.transition_mechanic_job_status(
  'e2790000-0000-4000-8000-000000000051',
  (select id from status_ids where code = 'FINALIZADO'),
  'inst-mismo-estado');

select is(
  (select (result->'installed_bike_facts') from results where label = 'replay'),
  (select (result->'installed_bike_facts') from results where label = 'terminado'),
  'el reintento con la misma llave devuelve la misma respuesta');
select is(
  (select result->'installed_bike_facts'->'applied' from results where label = 'mismo_estado'),
  '[]'::jsonb,
  'repetir el estado terminado no escribe lo que ya está');
select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where tenant_id = 'e2790000-0000-4000-8000-000000000001'),
  1,
  'un solo recibo');

-- Alguien corrige la ficha a mano: 30H atrás.
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{values,rearSpokeHoles}', '30'::jsonb)
 where bike_id = 'e2790000-0000-4000-8000-000000000031';

insert into results
select 'sync_corregida', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000051');

select is(
  (select technical_profile->'values'->'rearSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000031'),
  '30'::jsonb,
  'la línea no cambió: la corrección de la ficha se respeta');

-- ============================================================================
-- Una línea terminada que se corrige vuelve a escribir lo que instala
-- ============================================================================

update public.mechanic_job_items
   set service_configuration_data = '{"which_wheel": "rear", "hole_count": "32"}'::jsonb
 where id = 'e2790000-0000-4000-8000-000000000061';
insert into results
select 'sync_32', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000051');

update public.mechanic_job_items
   set service_configuration_data = '{"which_wheel": "rear", "hole_count": "28"}'::jsonb
 where id = 'e2790000-0000-4000-8000-000000000061';
insert into results
select 'sync_28', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000051');

select is(
  (select array_agg(operation_key order by split_part(operation_key, ':', 3)::integer)
     from public.bike_technical_fact_patches
    where tenant_id = 'e2790000-0000-4000-8000-000000000001'),
  array[
    'job_completion:e2790000-0000-4000-8000-000000000061:1:rearSpokeHoles=28',
    'job_completion:e2790000-0000-4000-8000-000000000061:2:rearSpokeHoles=32',
    'job_completion:e2790000-0000-4000-8000-000000000061:3:rearSpokeHoles=28'
  ],
  '28 → 32 → 28 escribe cada cambio, también el regreso a 28H');
select is(
  (select technical_profile->'values'->'rearSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000031'),
  '28'::jsonb,
  'la ficha termina en lo que la línea instaló al final');

-- ============================================================================
-- Trabajo de dos bicis
-- ============================================================================

select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2790000-0000-4000-8000-000000000052',
    (select id from status_ids where code = 'ENTREGADO'),
    'inst-dos-bicis')$$,
  '23514', null,
  'una línea de General marcada sin bici impide entregar dos bicis');
select is(
  (select status from public.mechanic_jobs
    where id = 'e2790000-0000-4000-8000-000000000052'),
  'PENDIENTE',
  'el rechazo tampoco entrega parcialmente el otro trabajo');
select ok(
  not exists (select 1 from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'),
  'la ficha de Oxford Dos tampoco se escribe parcialmente');

update public.mechanic_job_items
   set service_configuration_data = '{}'::jsonb
 where id = 'e2790000-0000-4000-8000-000000000064';
insert into results
select 'dos_bicis', public.transition_mechanic_job_status(
  'e2790000-0000-4000-8000-000000000052',
  (select id from status_ids where code = 'ENTREGADO'),
  'inst-dos-bicis');

select is(
  (select technical_profile->'values'->'frontSpokeHoles' || jsonb_build_array(
            technical_profile->'confirmed'->'frontSpokeHoles')
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'),
  '[36, true]'::jsonb,
  'la línea de la Oxford Dos le abre la ficha con 36H adelante');
select is(
  (select jsonb_path_query_array(result, '$.installed_bike_facts.problems[*].reason')
     from results where label = 'dos_bicis'),
  '[]'::jsonb,
  'entregar tras corregir ya no deja la línea sin bici');
select ok(
  not exists (
    select 1 from public.bike_profiles
     where bike_id = 'e2790000-0000-4000-8000-000000000032'),
  'y no se adivina la bici');

-- La línea de 36H se pasa a la Oxford Uno sin cambiar las perforaciones: la
-- Uno no lo tenía y ahora sí.
update public.mechanic_job_items
   set job_bike_id = (select id from public.mechanic_job_bikes
                       where job_id = 'e2790000-0000-4000-8000-000000000052'
                         and bike_id = 'e2790000-0000-4000-8000-000000000032')
 where id = 'e2790000-0000-4000-8000-000000000065';
insert into results
select 'otra_bici', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000052');

select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000032'),
  '36'::jsonb,
  'la línea que cambia de bici con las mismas 36H también llega a la otra bici');
select is(
  (select bike_id from public.bike_technical_fact_patches
    where operation_key = 'job_completion:e2790000-0000-4000-8000-000000000065:2:frontSpokeHoles=36'),
  'e2790000-0000-4000-8000-000000000032'::uuid,
  'con la siguiente llave de esa línea');

-- La Oxford Dos conserva las 36H que esa línea le atribuyó: no se deshace
-- solo (el recibo no dice si el dato estaba confirmado ni de dónde venía, y
-- no se sabe cuál asignación era la equivocada), pero se avisa.
select is(
  (select technical_profile->'values'->'frontSpokeHoles'
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'),
  '36'::jsonb,
  'la Oxford Dos sigue diciendo 36H: no se compensa a ciegas');
select is(
  (select jsonb_agg(jsonb_build_object(
            'bike_id', problem->>'bike_id',
            'key', problem->>'key',
            'value', problem->'value',
            'previous', problem->'previous',
            'bike_label', problem->>'bike_label'))
     from results,
          jsonb_array_elements(result->'problems') problem
    where label = 'otra_bici'
      and problem->>'reason' = 'no_longer_installed'),
  jsonb_build_array(jsonb_build_object(
    'bike_id', 'e2790000-0000-4000-8000-000000000033',
    'key', 'frontSpokeHoles',
    'value', 36,
    'previous', null,
    'bike_label', 'Oxford Dos')),
  'y se avisa: la línea ya no es de la Oxford Dos, que antes no tenía el dato');

insert into results
select 'otra_bici_otra_vez', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000052');
select is(
  (select count(*)::integer
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'otra_bici_otra_vez'
      and problem->>'reason' = 'no_longer_installed'),
  1,
  'el aviso sigue mientras nadie revise esa ficha');

-- Alguien guarda la Oxford Dos por otra cosa (las notas), con la ficha
-- completa tal como la manda el formulario: `save_bike_aggregate` real, que
-- deja su `profile_updated`. Nadie miró las perforaciones: el aviso sigue.
insert into results
select 'guardado_notas', public.save_bike_aggregate(
  'form-notas-oxford-dos',
  'e2790000-0000-4000-8000-000000000033',
  'e2790000-0000-4000-8000-000000000010',
  (select updated_at from public.bikes
    where id = 'e2790000-0000-4000-8000-000000000033'),
  (select updated_at from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'),
  jsonb_build_object('brand', 'Oxford', 'model', 'Dos',
                     'notes', 'Cambio de notas, nada más'),
  (select jsonb_build_object(
            'intake_profile', intake_profile,
            'technical_profile', technical_profile)
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'));
insert into results
select 'otra_bici_tras_notas', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000052');
select ok(
  exists (
    select 1 from public.bike_events
     where bike_id = 'e2790000-0000-4000-8000-000000000033'
       and source = 'atomic_bike_save'
       and event_type = 'profile_updated'),
  'el guardado de notas deja su profile_updated, como en la app');
select is(
  (select count(*)::integer
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'otra_bici_tras_notas'
      and problem->>'reason' = 'no_longer_installed'),
  1,
  'guardar la ficha por otro campo no apaga el aviso');

-- El operador elige 36H en «Rayos delanteros» (el formulario lo deja
-- `mechanic` y confirmado): lo revisó, el aviso termina.
insert into results
select 'confirmada_a_mano', public.save_bike_aggregate(
  'form-rayos-oxford-dos',
  'e2790000-0000-4000-8000-000000000033',
  'e2790000-0000-4000-8000-000000000010',
  (select updated_at from public.bikes
    where id = 'e2790000-0000-4000-8000-000000000033'),
  (select updated_at from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'),
  jsonb_build_object('brand', 'Oxford', 'model', 'Dos',
                     'notes', 'Cambio de notas, nada más'),
  (select jsonb_build_object(
            'intake_profile', intake_profile,
            'technical_profile', jsonb_set(technical_profile,
              '{sources,frontSpokeHoles}', '"mechanic"'::jsonb))
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000033'));
insert into results
select 'otra_bici_revisada', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000052');
select is(
  (select count(*)::integer
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'otra_bici_revisada'
      and problem->>'reason' = 'no_longer_installed'),
  0,
  'con el dato elegido a mano en su campo ya no se avisa');

-- En la misma bici, la línea pasa de la rueda trasera a la delantera: la
-- trasera queda con las 28H que la línea ya no respalda.
update public.mechanic_job_items
   set service_configuration_data = '{"which_wheel": "front", "hole_count": "28"}'::jsonb
 where id = 'e2790000-0000-4000-8000-000000000061';
insert into results
select 'otra_rueda', public.sync_job_installed_bike_facts_v1(
  'e2790000-0000-4000-8000-000000000051');
select is(
  (select jsonb_build_array(
            technical_profile->'values'->'frontSpokeHoles',
            technical_profile->'values'->'rearSpokeHoles')
     from public.bike_profiles
    where bike_id = 'e2790000-0000-4000-8000-000000000031'),
  '[28, 28]'::jsonb,
  'la delantera toma 28H y la trasera no se toca');
select is(
  (select jsonb_agg(problem->>'key')
     from results, jsonb_array_elements(result->'problems') problem
    where label = 'otra_rueda'
      and problem->>'reason' = 'no_longer_installed'),
  '["rearSpokeHoles"]'::jsonb,
  'pero se avisa que la trasera ya no la respalda esa línea');

-- ============================================================================
-- Límites
-- ============================================================================

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('e2790000-0000-4000-8000-000000000034',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010', 'Oxford', 'Reintento');
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2790000-0000-4000-8000-000000000053',
   'e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000010',
   'e2790000-0000-4000-8000-000000000034', 'PG-INST-3',
   'e2790000-0000-4000-8000-000000000099');

select is(
  public.sync_job_installed_bike_facts_v1('e2790000-0000-4000-8000-000000000053')->'finished',
  'false'::jsonb,
  'un trabajo sin terminar no instala nada');

-- Un fallo transitorio del parche no parece un dato mal elegido: ni estado ni
-- recibo sobreviven, y la misma llave podrá reconciliarse/reintentarse.
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('e2790000-0000-4000-8000-000000000001',
   'e2790000-0000-4000-8000-000000000053',
   'e2790000-0000-4000-8000-000000000034');
insert into public.mechanic_job_items (
  tenant_id, job_id, job_bike_id, product_name, item_type, location_key,
  service_configuration_data
) values (
  'e2790000-0000-4000-8000-000000000001',
  'e2790000-0000-4000-8000-000000000053',
  (select id from public.mechanic_job_bikes
    where job_id = 'e2790000-0000-4000-8000-000000000053'),
  'Enrayado Oxford Reintento', 'service', 'rear',
  '{"which_wheel":"rear","hole_count":"30"}'::jsonb
);
create function pg_temp.block_profile_once()
returns trigger language plpgsql as $$
begin
  if new.bike_id = 'e2790000-0000-4000-8000-000000000034'::uuid then
    raise exception 'bloqueo de prueba' using errcode = '55P03';
  end if;
  return new;
end;
$$;
create trigger test_profile_lock
before insert or update on public.bike_profiles
for each row execute function pg_temp.block_profile_once();
select throws_ok(
  $$select public.transition_mechanic_job_status(
    'e2790000-0000-4000-8000-000000000053',
    (select id from status_ids where code = 'FINALIZADO'),
    'inst-retry-053')$$,
  '55P03', null,
  'un bloqueo transitorio conserva la semántica de reintento');
select is(
  jsonb_build_array(
    (select status from public.mechanic_jobs
      where id = 'e2790000-0000-4000-8000-000000000053'),
    (select count(*) from public.mechanic_job_status_transition_events
      where operation_key = 'inst-retry-053'),
    (select count(*) from public.bike_technical_fact_patches
      where job_id = 'e2790000-0000-4000-8000-000000000053')),
  '["PENDIENTE", 0, 0]'::jsonb,
  'estado, transición y parche se deshacen ante el bloqueo');
drop trigger test_profile_lock on public.bike_profiles;
insert into results select 'reintento_transitorio',
  public.transition_mechanic_job_status(
    'e2790000-0000-4000-8000-000000000053',
    (select id from status_ids where code = 'FINALIZADO'),
    'inst-retry-053');
select is(
  jsonb_build_array(
    (select result->>'status' from results where label = 'reintento_transitorio'),
    (select technical_profile->'values'->'rearSpokeHoles'
       from public.bike_profiles
      where bike_id = 'e2790000-0000-4000-8000-000000000034')),
  '["FINALIZADO", 30]'::jsonb,
  'el mismo intento se aplica una vez al desaparecer el bloqueo');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2790000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2790000-0000-4000-8000-000000000098', true);

select throws_ok(
  $$select public.sync_job_installed_bike_facts_v1('e2790000-0000-4000-8000-000000000051')$$,
  '42501',
  null,
  'otro taller no reaplica lo instalado de este');

select * from finish();
rollback;
