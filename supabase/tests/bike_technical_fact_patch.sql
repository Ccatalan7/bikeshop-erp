begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Escribir en la ficha dato por dato (paso B del backbone, 2026-09-27): sólo
-- las claves que cambian, rechazando todo si la ficha ya no dice lo que el
-- cliente vio, con recibo para el reintento.

select has_table('public', 'bike_technical_fact_patches',
  'cada escritura a la ficha deja su recibo');
select ok(
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE'),
  'escribe en la ficha sólo un empleado autenticado');
select ok(
  not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'INSERT')
  and not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'DELETE')
  and not has_table_privilege('anon', 'public.bike_technical_fact_patches', 'SELECT'),
  'los recibos no se escriben a mano');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e2780000-0000-4000-8000-000000000001', 'Taller ficha A'),
  ('e2780000-0000-4000-8000-000000000002', 'Taller ficha B');

-- Sembrar un taller deja su propia identidad en los claims de la
-- transacción; se limpia para que los trabajos del fixture no la hereden.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e2780000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'ficha-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e2780000-0000-4000-8000-000000000099',
   'e2780000-0000-4000-8000-000000000001', 'admin');

insert into public.customers (id, tenant_id, name) values
  ('e2780000-0000-4000-8000-000000000010',
   'e2780000-0000-4000-8000-000000000001', 'Cliente ficha'),
  ('e2780000-0000-4000-8000-000000000020',
   'e2780000-0000-4000-8000-000000000002', 'Cliente otro taller');

insert into public.bikes (id, tenant_id, customer_id, brand, model, wheel_size) values
  ('e2780000-0000-4000-8000-000000000031',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000010', 'Phoenix', '04D', '29''''') ,
  ('e2780000-0000-4000-8000-000000000032',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000010', 'Oxford', 'Sin ficha', null),
  ('e2780000-0000-4000-8000-000000000033',
   'e2780000-0000-4000-8000-000000000002',
   'e2780000-0000-4000-8000-000000000020', 'Otra', 'Bici', '26"');

insert into public.bike_profiles (id, tenant_id, bike_id, technical_profile, summary_snapshot) values (
  'e2780000-0000-4000-8000-000000000041',
  'e2780000-0000-4000-8000-000000000001',
  'e2780000-0000-4000-8000-000000000031',
  jsonb_build_object(
    'values', jsonb_build_object(
      'brakeType', 'rim', 'frontSpokeHoles', 32, 'drivetrainSpeeds', 8,
      'suspensionLayout', 'front_suspension', 'valveType', 'schrader'
    ),
    'sources', jsonb_build_object('brakeType', 'intake', 'valveType', 'catalog'),
    'confirmed', jsonb_build_object('brakeType', true, 'valveType', false)
  ),
  '{"warnings": ["Falta confirmar tipo de freno"]}'::jsonb
);

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e2780000-0000-4000-8000-000000000051',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000010',
   'e2780000-0000-4000-8000-000000000031', 'PG-FICHA-1',
   'e2780000-0000-4000-8000-000000000099'),
  ('e2780000-0000-4000-8000-000000000052',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000010',
   'e2780000-0000-4000-8000-000000000032', 'PG-FICHA-2',
   'e2780000-0000-4000-8000-000000000099');

-- La línea del Enrayado que arma la rueda delantera de 28H, y una línea de
-- otro trabajo.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, service_configuration_data
) values
  ('e2780000-0000-4000-8000-000000000061',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000051', 'Enrayado + Centrado', 'service',
   '{"which_wheel": "front", "hole_count": "28"}'::jsonb),
  ('e2780000-0000-4000-8000-000000000062',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000052', 'Enrayado + Centrado', 'service',
   '{}'::jsonb);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2780000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e2780000-0000-4000-8000-000000000099', true);

-- ============================================================================
-- Sólo cambia lo que cambia
-- ============================================================================

select is(
  (select jsonb_array_length(public.patch_bike_technical_facts_v1(
    'op-1',
    'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "rearRotorSizeMm", "op": "set", "value": 180, "expected": null, "expected_confirmed": false},
      {"key": "brakeType", "op": "set", "value": "hydraulic_disc", "expected": "rim", "expected_confirmed": true}]'::jsonb
  )->'applied')),
  2,
  'un dato que faltaba y uno que cambia se aplican');

select is(
  (select technical_profile->'values' from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  jsonb_build_object(
    'brakeType', 'hydraulic_disc', 'frontSpokeHoles', 32, 'drivetrainSpeeds', 8,
    'rearRotorSizeMm', 180,
    'suspensionLayout', 'front_suspension', 'valveType', 'schrader'
  ),
  'las claves que el servicio no nombró quedan intactas');

select is(
  (select technical_profile->'sources'->>'rearRotorSizeMm' || '/' ||
          (technical_profile->'confirmed'->>'rearRotorSizeMm')
     from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  'mechanic/true',
  'lo que confirma el mecánico queda confirmado y con su fuente');

select is(
  (select summary_snapshot from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  '{}'::jsonb,
  'el resumen viejo se vacía para que el lector lo arme de la ficha vigente');

select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2780000-0000-4000-8000-000000000031'
      and source = 'service_wizard_promotion'
      and job_id = 'e2780000-0000-4000-8000-000000000051'),
  1,
  'la historia de la bici dice qué trabajo cambió la ficha');

-- ============================================================================
-- Reintento y reuso de la llave
-- ============================================================================

select is(
  (select (public.patch_bike_technical_facts_v1(
    'op-1',
    'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051',
    'service_wizard',
    '[{"key": "rearRotorSizeMm", "op": "set", "value": 180, "expected": null, "expected_confirmed": false},
      {"key": "brakeType", "op": "set", "value": "hydraulic_disc", "expected": "rim", "expected_confirmed": true}]'::jsonb
  )->>'replayed')::boolean),
  true,
  'un reintento con la misma llave devuelve lo ya confirmado');

select is(
  (select count(*)::integer from public.bike_events
    where bike_id = 'e2780000-0000-4000-8000-000000000031'
      and source = 'service_wizard_promotion'),
  1,
  'el reintento no escribe dos veces');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-1', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "rearRotorSizeMm", "op": "set", "value": 160, "expected": 180, "expected_confirmed": false}]'::jsonb)$$,
  '23000',
  'Bicycle fact key was already used with different content',
  'una llave usada no sirve para otro contenido');

-- ============================================================================
-- Conflicto: la ficha ya no dice lo que el cliente vio
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-2', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 9, "expected": 7, "expected_confirmed": false},
      {"key": "frontRotorSizeMm", "op": "set", "value": 180, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'PT409',
  'Bicycle facts changed since they were loaded; reload before saving',
  'un dato que cambió desde que se cargó rechaza el comando');

select is(
  (select technical_profile->'values' ? 'frontRotorSizeMm' from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  false,
  'un conflicto no deja aplicada ninguna parte del comando');

select is(
  (select count(*)::integer from public.bike_technical_fact_patches
    where operation_key = 'op-2'),
  0,
  'un comando rechazado no deja recibo');

-- ============================================================================
-- Confirmar y borrar
-- ============================================================================

select is(
  (select public.patch_bike_technical_facts_v1(
    'op-3', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "schrader", "expected": "schrader", "expected_confirmed": false}]'::jsonb
  )->'applied'->0->>'op'),
  'confirm',
  'afirmar el valor que ya había lo confirma sin cambiarlo');

select is(
  (select technical_profile->'confirmed'->>'valveType' from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  'true',
  'la válvula queda confirmada');

select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-4', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "rearRotorSizeMm", "op": "remove", "expected": 180, "expected_confirmed": true}]'::jsonb)$$,
  'un dato se borra diciendo qué valor tenía');

select is(
  (select (technical_profile->'values' ? 'rearRotorSizeMm')
       or (technical_profile->'sources' ? 'rearRotorSizeMm')
       or (technical_profile->'confirmed' ? 'rearRotorSizeMm')
     from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  false,
  'borrar quita el valor, la fuente y la confirmación');

-- ============================================================================
-- Aro: columna de la bici, con la etiqueta de la ficha
-- ============================================================================

update public.bike_profiles
   set summary_snapshot = '{"warnings": ["Aro sin confirmar"]}'::jsonb
 where id = 'e2780000-0000-4000-8000-000000000041';

select is(
  (select public.patch_bike_technical_facts_v1(
    'op-5', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "bikes.wheel_size", "op": "set", "value": "29\"", "expected": "29''''", "expected_confirmed": false}]'::jsonb
  )->'bike'->>'wheel_size'),
  '29"',
  'el aro sucio se reemplaza por la etiqueta de la ficha');

select is(
  (select summary_snapshot from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  '{}'::jsonb,
  'cambiar sólo el aro también vacía el resumen que lo mostraba');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-6', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "bikes.wheel_size", "op": "set", "value": "29 pulgadas", "expected": "29\"", "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle wheel size must be one of the ficha labels',
  'un aro fuera de la lista de la ficha no se escribe');

-- ============================================================================
-- Bici sin ficha: nace con sólo lo que el servicio sabe
-- ============================================================================

select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-7', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "brakeType", "op": "set", "value": "mechanical_disc", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'un servicio puede crear la ficha que no existía');

select is(
  (select technical_profile->'values' from public.bike_profiles
    where bike_id = 'e2780000-0000-4000-8000-000000000032'),
  '{"brakeType": "mechanical_disc"}'::jsonb,
  'la ficha nueva trae sólo el dato confirmado');

select is(
  (select event_type || ' / ' || title from public.bike_events
    where bike_id = 'e2780000-0000-4000-8000-000000000032'
      and source = 'service_wizard_promotion'),
  'profile_created / Ficha creada desde un servicio',
  'la historia dice que la ficha nació del servicio');

-- ============================================================================
-- Límites
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-8', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "suspensionLayout", "op": "set", "value": "rigid", "expected": "front_suspension", "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact key suspensionLayout is not writable from a service',
  'un servicio no escribe claves fuera del contrato');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-9', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": "9", "expected": 8, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact drivetrainSpeeds must be a number',
  'una medida va como número');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-10', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "presta", "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Each bicycle fact needs key, op, expected and expected_confirmed, and nothing else',
  'un dato sin el valor que se vio no se acepta');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-11', 'e2780000-0000-4000-8000-000000000033',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "presta", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  '42501',
  'Bicycle not found for current tenant',
  'la bici de otro taller no existe para este empleado');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-12', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "presta", "expected": "schrader", "expected_confirmed": false}]'::jsonb)$$,
  '42501',
  'The job does not include this bicycle',
  'un trabajo que no incluye la bici no la puede promover');

-- ============================================================================
-- Revisión de Codex (2026-09-27)
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-13', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "remove", "expected": "schrader", "expected_confirmed": false}]'::jsonb)$$,
  'PT409',
  'Bicycle facts changed since they were loaded; reload before saving',
  'borrar desde una copia que veía el dato sin confirmar no pisa la confirmación de otro');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-14', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "frontRotorSizeMm", "op": "set", "value": 150.5, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact frontRotorSizeMm is out of its workshop range',
  'un rotor fraccionario o fuera de rango no es un rotor');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-15', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 999, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact drivetrainSpeeds is out of its workshop range',
  'velocidades imposibles no se escriben');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-16', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "brakeType", "op": "set", "value": "inexistente", "expected": "hydraulic_disc", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact brakeType has an unknown value',
  'un tipo de freno fuera del vocabulario no se escribe');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-18', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "unknown", "expected": "schrader", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact valveType cannot be confirmed as unknown',
  'un servicio no confirma «desconocido» como dato de la bici');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-19', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "schrader", "expected": "presta", "expected_confirmed": false}]'::jsonb)$$,
  'PT409',
  'Bicycle facts changed since they were loaded; reload before saving',
  'afirmar desde una copia vieja el valor que ya está no lo confirma sin verlo');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-20', 'e2780000-0000-4000-8000-000000000031', null, 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "presta", "expected": "schrader", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'A service fact needs the job that confirmed it',
  'un servicio sin trabajo no escribe en la ficha');

-- ============================================================================
-- Sugerir: un dato de la bici completa visto en una sola rueda (paso C)
-- ============================================================================

update public.bike_profiles
   set last_confirmed_at = '2026-01-15 10:00:00+00'
 where bike_id = 'e2780000-0000-4000-8000-000000000032';

select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-21', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "valveType", "op": "suggest", "value": "presta", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'una rueda sugiere la válvula que la ficha no sabía');

select is(
  (select technical_profile->'values'->>'valveType'
       || '/' || (technical_profile->'sources'->>'valveType')
       || '/' || coalesce(technical_profile->'confirmed'->>'valveType', 'sin confirmar')
     from public.bike_profiles
    where bike_id = 'e2780000-0000-4000-8000-000000000032'),
  'presta/service_wizard/sin confirmar',
  'lo sugerido queda escrito, con su fuente y sin confirmar');

select is(
  (select last_confirmed_at from public.bike_profiles
    where bike_id = 'e2780000-0000-4000-8000-000000000032'),
  '2026-01-15 10:00:00+00'::timestamptz,
  'una sugerencia sola no renueva la «Última confirmación» de la ficha');

select is(
  (select jsonb_array_length(public.patch_bike_technical_facts_v1(
    'op-22', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "suggest", "value": "presta", "expected": "presta", "expected_confirmed": false}]'::jsonb
  )->'applied')),
  0,
  'una sugerencia nunca pisa un dato que la ficha ya tiene');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-23', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "bikes.wheel_size", "op": "suggest", "value": "29\"", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle wheel size has no confirmation mark to hold a suggestion',
  'el aro no se sugiere: la columna no distingue sugerido de confirmado');

-- ============================================================================
-- Lo instalado cambia la ficha al terminar el trabajo, no al configurarlo
-- ============================================================================

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-26', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Spoke holes change only when the job that installs the wheel is finished',
  'configurar el Enrayado no cambia las perforaciones de la ficha');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:frontSpokeHoles=28', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Installed parts change the bicycle only when the job is finished',
  'una rueda presupuestada o en curso no cambia la ficha');

update public.mechanic_jobs
   set status = 'FINALIZADO'
 where id = 'e2780000-0000-4000-8000-000000000051';

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-27', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'An installed fact needs the job line that installed it',
  'lo instalado nombra la línea que lo instaló');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000062:1:frontSpokeHoles=28', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  '42501',
  'The job line is not part of this job and bicycle',
  'una línea de otro trabajo no cambia esta bici');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:drivetrainSpeeds=9', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "drivetrainSpeeds", "op": "set", "value": 9, "expected": 8, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact drivetrainSpeeds is not installed by a job',
  'un trabajo terminado sólo escribe lo que se instala');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:frontSpokeHoles=36', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The installed fact key does not match the facts it writes',
  'la llave dice lo mismo que el comando');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:frontSpokeHoles=32', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 32, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install frontSpokeHoles',
  'la línea armó 28H: no puede instalar 32H');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:rearSpokeHoles=28', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "rearSpokeHoles", "op": "set", "value": 28, "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'The job line did not install rearSpokeHoles',
  'la línea armó la rueda delantera, no la trasera');

-- Una línea de General sólo instala en un trabajo de una sola bici. Desde
-- 20260928140000 la puerta ya rechaza agregar la segunda bici a un trabajo
-- terminado con una línea así; el parche se defiende igual de ese estado
-- viejo, que aquí se arma sin ella.
alter table public.mechanic_job_bikes disable trigger trg_mechanic_job_bikes_gate_job_lines;
insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id) values
  ('e2780000-0000-4000-8000-000000000071',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000051',
   'e2780000-0000-4000-8000-000000000031'),
  ('e2780000-0000-4000-8000-000000000072',
   'e2780000-0000-4000-8000-000000000001',
   'e2780000-0000-4000-8000-000000000051',
   'e2780000-0000-4000-8000-000000000032');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:frontSpokeHoles=28', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  '42501',
  'The job line is not part of this job and bicycle',
  'una línea de General no elige bici en un trabajo de dos');

delete from public.mechanic_job_bikes
 where job_id = 'e2780000-0000-4000-8000-000000000051'
   and tenant_id = 'e2780000-0000-4000-8000-000000000001';
alter table public.mechanic_job_bikes enable trigger trg_mechanic_job_bikes_gate_job_lines;

select lives_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:1:frontSpokeHoles=28', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 28, "expected": 32, "expected_confirmed": false}]'::jsonb)$$,
  'con el trabajo terminado, la rueda armada cambia la ficha');

select is(
  (select (technical_profile->'values'->>'frontSpokeHoles')
       || '/' || (technical_profile->'sources'->>'frontSpokeHoles')
       || '/' || (technical_profile->'confirmed'->>'frontSpokeHoles')
     from public.bike_profiles
    where id = 'e2780000-0000-4000-8000-000000000041'),
  '28/job_completion/true',
  'la ficha dice qué la cambió: el trabajo terminado');

-- Un trabajo cancelado después no admite lo instalado.
update public.mechanic_jobs
   set status = 'CANCELADO'
 where id = 'e2780000-0000-4000-8000-000000000051';

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000061:2:frontSpokeHoles=32', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'job_completion',
    '[{"key": "frontSpokeHoles", "op": "set", "value": 32, "expected": 28, "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Installed parts change the bicycle only when the job is finished',
  'un trabajo cancelado no cambia la ficha');

-- ============================================================================
-- Fluido de freno y eje de cada rueda (paso F.2): los códigos del registro
-- ============================================================================

select is(
  (select jsonb_array_length(public.patch_bike_technical_facts_v1(
    'op-f2-1', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "frontBrakeFluidType", "op": "set", "value": "aceite_mineral", "expected": null, "expected_confirmed": false},
      {"key": "rearBrakeFluidType", "op": "set", "value": "dot_4", "expected": null, "expected_confirmed": false},
      {"key": "frontAxleInterface", "op": "set", "value": "catalog_d2128659275dc69ee5e50dc9500992fa", "expected": null, "expected_confirmed": false}]'::jsonb
  )->'applied')),
  3,
  'cada freno guarda su fluido (mineral adelante, DOT atrás) y la maza su eje');

select is(
  (select (technical_profile->'values'->>'frontBrakeFluidType')
       || '/' || (technical_profile->'values'->>'rearBrakeFluidType')
       || '/' || (technical_profile->'sources'->>'rearBrakeFluidType')
       || '/' || (technical_profile->'confirmed'->>'rearBrakeFluidType')
       || '/' || (technical_profile->'values'->>'frontAxleInterface')
     from public.bike_profiles
    where bike_id = 'e2780000-0000-4000-8000-000000000032'),
  'aceite_mineral/dot_4/mechanic/true/catalog_d2128659275dc69ee5e50dc9500992fa',
  'la ficha guarda el código del registro de cada freno, confirmado por el mecánico');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-f2-5', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "brakeFluidType", "op": "set", "value": "dot_4", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact key brakeFluidType is not writable from a service',
  'el fluido ya no es un dato de la bici completa');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-f2-2', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "rearBrakeFluidType", "op": "set", "value": "mineral_oil", "expected": "dot_4", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact rearBrakeFluidType has an unknown value',
  'un fluido fuera del registro no se escribe');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-f2-3', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "rearAxleInterface", "op": "set", "value": "catalog_de6e897b1c6ced32e6762f3ceaebffd6", "expected": null, "expected_confirmed": false}]'::jsonb)$$,
  'P0001',
  'Bicycle fact rearAxleInterface cannot be confirmed as unknown',
  '«Desconocido / sin confirmar» del registro no se confirma como eje');

-- El editor de la ficha puede guardar «Desconocido»; una sugerencia lo llena.
update public.bike_profiles
   set technical_profile = jsonb_set(technical_profile, '{values,rearAxleInterface}',
         '"catalog_de6e897b1c6ced32e6762f3ceaebffd6"'::jsonb)
 where bike_id = 'e2780000-0000-4000-8000-000000000032';

select is(
  (select public.patch_bike_technical_facts_v1(
    'op-f2-4', 'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'service_wizard',
    '[{"key": "rearAxleInterface", "op": "suggest", "value": "catalog_04c89a1828095f03f3c390c821f8bccd", "expected": "catalog_de6e897b1c6ced32e6762f3ceaebffd6", "expected_confirmed": false}]'::jsonb
  )->'applied'->0->>'to'),
  'catalog_04c89a1828095f03f3c390c821f8bccd',
  'una sugerencia llena el eje que la ficha tenía como desconocido');

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'job_completion:e2780000-0000-4000-8000-000000000062:1:frontAxleInterface=catalog_855ee050fed24e28691a34b52fb4105e',
    'e2780000-0000-4000-8000-000000000032',
    'e2780000-0000-4000-8000-000000000052', 'job_completion',
    '[{"key": "frontAxleInterface", "op": "set", "value": "catalog_855ee050fed24e28691a34b52fb4105e", "expected": "catalog_d2128659275dc69ee5e50dc9500992fa", "expected_confirmed": true}]'::jsonb)$$,
  'P0001',
  'Bicycle fact frontAxleInterface is not installed by a job',
  'el eje no lo instala un trabajo hasta que una pieza lo declare');

update public.tenants
   set is_active = false
 where id = 'e2780000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.patch_bike_technical_facts_v1(
    'op-17', 'e2780000-0000-4000-8000-000000000031',
    'e2780000-0000-4000-8000-000000000051', 'service_wizard',
    '[{"key": "valveType", "op": "set", "value": "presta", "expected": "schrader", "expected_confirmed": true}]'::jsonb)$$,
  '42501',
  'Exactly one active employee tenant is required',
  'un taller suspendido no escribe fichas aunque la cuenta siga activa');

select * from finish();
rollback;
