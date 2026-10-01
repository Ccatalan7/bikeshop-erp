begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Bandeja de comandos del taller (ítem 3 de la cola, 2026-09-27): cada
-- intento se anota para soporte, y las fotos de la bici viven en un bucket
-- del taller donde sólo su personal sube y borra.

-- ============================================================================
-- Permisos
-- ============================================================================

select has_table('public', 'workshop_command_attempts',
  'los intentos de los comandos del taller tienen su tabla');
select ok(
  has_function_privilege('authenticated',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE'),
  'anota intentos sólo un empleado autenticado');
select ok(
  has_table_privilege('authenticated', 'public.workshop_command_attempts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'DELETE')
  and not has_table_privilege('anon', 'public.workshop_command_attempts', 'SELECT'),
  'los intentos no se escriben ni se corrigen a mano');

-- PostgREST 14 reintenta sin fin una transacción que falla con 40001: los
-- conflictos que la bandeja recibe usan PT409 (HTTP 409), sin reintento.
select ok(
  pg_get_functiondef('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure)
    not like '%serialization_failure%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    not like '%serialization_failure%'
  and pg_get_functiondef('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure)
    like '%errcode = ''PT409''%',
  'los conflictos de la ficha no usan 40001, que PostgREST reintenta sin fin');

select is(
  (select public from storage.buckets where id = 'bike-images'),
  true,
  'las fotos de la bici se leen por URL, como las del trabajo');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name) values
  ('e3790000-0000-4000-8000-000000000001', 'Taller bandeja A'),
  ('e3790000-0000-4000-8000-000000000002', 'Taller bandeja B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e3790000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'bandeja-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e3790000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'bandeja-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role) values
  ('e3790000-0000-4000-8000-000000000099',
   'e3790000-0000-4000-8000-000000000001', 'admin'),
  ('e3790000-0000-4000-8000-000000000098',
   'e3790000-0000-4000-8000-000000000002', 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000099', true);

-- ============================================================================
-- Intentos: los cinco resultados que soporte tiene que distinguir
-- ============================================================================

select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a1',
      'operation_key', 'op-sin-red', 'command_kind', 'bike_aggregate_save',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'offline',
      'error_code', 'transport', 'error_message', 'SocketException: sin red',
      'bike_id', 'e3790000-0000-4000-8000-000000000031',
      'client_started_at', '2026-09-27T20:00:00Z', 'duration_ms', 30012,
      'client_platform', 'macos', 'app_version', '1.0.3+61'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a2',
      'operation_key', 'op-sin-red', 'command_kind', 'bike_aggregate_save',
      'attempt_number', 2, 'trigger', 'resume', 'outcome', 'reconciled',
      'bike_id', 'e3790000-0000-4000-8000-000000000031',
      'client_started_at', '2026-09-27T20:05:00Z', 'duration_ms', 410),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a3',
      'operation_key', 'op-cambiada', 'command_kind', 'bike_fact_patch',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'stale',
      'error_code', '40001',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-27T20:01:00Z', 'duration_ms', 220),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a4',
      'operation_key', 'op-rechazada', 'command_kind', 'bike_fact_patch',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'rejected',
      'error_code', '22023',
      'client_started_at', '2026-09-27T20:02:00Z'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a5',
      'operation_key', 'op-escrita', 'command_kind', 'bike_aggregate_save',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'committed',
      'client_started_at', '2026-09-27T20:03:00Z', 'duration_ms', 180)
  )),
  '{"inserted": 5, "duplicates": 0, "invalid": 0}'::jsonb,
  'una tanda con los cinco resultados queda anotada');

select results_eq(
  $$select outcome collate "C" from public.workshop_command_attempts
     where tenant_id = 'e3790000-0000-4000-8000-000000000001'
     order by outcome collate "C"$$,
  $$values ('committed'::text collate "C"), ('offline'), ('reconciled'),
           ('rejected'), ('stale')$$,
  'soporte distingue sin red, reconciliado, ficha cambiada, rechazado y escrito');

select is(
  (select user_id from public.workshop_command_attempts
    where attempt_id = 'e3790000-0000-4000-8000-0000000000a1'),
  'e3790000-0000-4000-8000-000000000099'::uuid,
  'el taller y la persona los pone el servidor, no la app');

select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a1',
      'operation_key', 'op-sin-red', 'command_kind', 'bike_aggregate_save',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'offline',
      'client_started_at', '2026-09-27T20:00:00Z')
  )),
  '{"inserted": 0, "duplicates": 1, "invalid": 0}'::jsonb,
  'si la respuesta se perdió y la app reenvía, el intento no se duplica');

-- El guardado de líneas y ficha del trabajo pasa por la misma bandeja
-- (20260928080000): su intento se anota con el trabajo.
select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a6',
      'operation_key', 'op-lineas', 'command_kind', 'job_line_save',
      'attempt_number', 2, 'trigger', 'resume', 'outcome', 'reconciled',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-28T10:00:00Z', 'duration_ms', 350)
  )),
  '{"inserted": 1, "duplicates": 0, "invalid": 0}'::jsonb,
  'el intento del guardado de líneas se anota');
delete from public.workshop_command_attempts
 where attempt_id = 'e3790000-0000-4000-8000-0000000000a6';

select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a7',
      'operation_key', 'op-lineas:factura', 'command_kind', 'job_invoice_continuation',
      'attempt_number', 1, 'trigger', 'resume', 'outcome', 'offline',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-28T10:05:00Z', 'duration_ms', 120)
  )),
  '{"inserted": 1, "duplicates": 0, "invalid": 0}'::jsonb,
  'el intento de la continuación de la factura se anota');
delete from public.workshop_command_attempts
 where attempt_id = 'e3790000-0000-4000-8000-0000000000a7';

select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a8',
      'operation_key', 'op-estado', 'command_kind', 'job_status_transition',
      'attempt_number', 1, 'trigger', 'resume', 'outcome', 'committed',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-28T10:06:00Z', 'duration_ms', 90)
  )),
  '{"inserted": 1, "duplicates": 0, "invalid": 0}'::jsonb,
  'el intento del cambio de estado se anota');
delete from public.workshop_command_attempts
 where attempt_id = 'e3790000-0000-4000-8000-0000000000a8';

-- La decisión de garantía por la bandeja, también la que sale sin enviarse
-- porque su guardado no se escribió (punto 2 del cierre, 2026-09-29).
select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000a9',
      'operation_key', 'op-garantia', 'command_kind', 'job_warranty_decision',
      'attempt_number', 1, 'trigger', 'resume', 'outcome', 'reconciled',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-29T10:07:00Z', 'duration_ms', 80),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000aa',
      'operation_key', 'op-garantia-2', 'command_kind', 'job_warranty_decision',
      'attempt_number', 0, 'trigger', 'discard', 'outcome', 'discarded',
      'error_code', 'prerequisite_not_written',
      'job_id', 'e3790000-0000-4000-8000-000000000051',
      'client_started_at', '2026-09-29T10:08:00Z', 'duration_ms', 0)
  )),
  '{"inserted": 2, "duplicates": 0, "invalid": 0}'::jsonb,
  'el intento de la decisión de garantía se anota, también el descartado con su guardado');
delete from public.workshop_command_attempts
 where attempt_id in ('e3790000-0000-4000-8000-0000000000a9',
                      'e3790000-0000-4000-8000-0000000000aa');

select is(
  public.record_workshop_command_attempts_v1(jsonb_build_array(
    jsonb_build_object(
      'attempt_id', 'no-es-uuid', 'operation_key', 'op',
      'command_kind', 'bike_aggregate_save', 'attempt_number', 1,
      'trigger', 'save', 'outcome', 'committed',
      'client_started_at', '2026-09-27T20:00:00Z'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000b1',
      'operation_key', 'op', 'command_kind', 'job_status',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'committed',
      'client_started_at', '2026-09-27T20:00:00Z'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000b2',
      'operation_key', 'op', 'command_kind', 'bike_fact_patch',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'maybe',
      'client_started_at', '2026-09-27T20:00:00Z'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000b3',
      'operation_key', 'op', 'command_kind', 'bike_fact_patch',
      'attempt_number', 1, 'trigger', 'save', 'outcome', 'committed',
      'client_started_at', 'ayer'),
    jsonb_build_object(
      'attempt_id', 'e3790000-0000-4000-8000-0000000000b4',
      'operation_key', 'op-bien', 'command_kind', 'bike_fact_patch',
      'attempt_number', 1, 'trigger', 'retry', 'outcome', 'committed',
      'client_started_at', '2026-09-27T20:00:00Z')
  )),
  '{"inserted": 1, "duplicates": 0, "invalid": 4}'::jsonb,
  'un intento mal formado se cuenta y se salta; el resto de la tanda entra');

select throws_ok(
  $$select public.record_workshop_command_attempts_v1('{"no": "lista"}'::jsonb)$$,
  '22023',
  'Attempts must be a JSON array',
  'la tanda es una lista');

select throws_ok(
  format($$select public.record_workshop_command_attempts_v1(%L::jsonb)$$,
    (select jsonb_agg(jsonb_build_object('attempt_id', gen_random_uuid()))
       from generate_series(1, 101))),
  '22023',
  'At most 100 attempts per call',
  'una tanda tiene a lo más cien intentos');

-- El otro taller no ve estos intentos.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000098', true);
set local role authenticated;

select is(
  (select count(*)::integer from public.workshop_command_attempts),
  0,
  'un taller no ve los intentos de otro');

reset role;

-- Sin cuenta de empleado no se anota nada.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.record_workshop_command_attempts_v1('[]'::jsonb)$$,
  '42501',
  'Exactly one active employee tenant is required',
  'sin empleado activo no hay intentos');

-- ============================================================================
-- Fotos de la bici: sólo el personal del taller, sólo en su carpeta
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000099', true);
set local role authenticated;

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('bike-images',
      'e3790000-0000-4000-8000-000000000001/e3790000-0000-4000-8000-000000000031/foto.jpg',
      'e3790000-0000-4000-8000-000000000099')$$,
  'el taller sube la foto en su carpeta, bajo la bici');

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('bike-images',
      'e3790000-0000-4000-8000-000000000002/e3790000-0000-4000-8000-000000000033/foto.jpg',
      'e3790000-0000-4000-8000-000000000099')$$,
  '42501',
  null,
  'no sube fotos en la carpeta de otro taller');

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('bike-images', 'e3790000-0000-4000-8000-000000000001/foto.jpg',
      'e3790000-0000-4000-8000-000000000099')$$,
  '42501',
  null,
  'una foto sin bici en la ruta no entra: el barrido no tendría de quién es');

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000098', true);
set local role authenticated;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'bike-images'),
  0,
  'otro taller no lista las fotos');

-- La API de Storage borra con esta marca y la política del usuario; sin ella,
-- un delete directo lo frena `storage.protect_delete`.
select set_config('storage.allow_delete_query', 'true', true);

delete from storage.objects where bucket_id = 'bike-images';

reset role;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'bike-images'),
  1,
  'ni las borra');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000099', true);
set local role authenticated;

delete from storage.objects where bucket_id = 'bike-images';

reset role;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'bike-images'),
  0,
  'el taller borra la foto huérfana de su carpeta');

-- ============================================================================
-- Adjuntos del trabajo (`job-images`): lo mismo, con el trabajo en la ruta
-- ============================================================================

select is(
  (select jsonb_build_object('public', public,
            'pdf', 'application/pdf' = any (allowed_mime_types))
     from storage.buckets where id = 'job-images'),
  '{"public": true, "pdf": true}'::jsonb,
  'los adjuntos del trabajo se leen por URL y aceptan PDF');

set local role authenticated;

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('job-images',
      'e3790000-0000-4000-8000-000000000001/e3790000-0000-4000-8000-000000000051/adjunto.pdf',
      'e3790000-0000-4000-8000-000000000099')$$,
  'el taller sube el adjunto en su carpeta, bajo el trabajo');

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('job-images',
      'e3790000-0000-4000-8000-000000000002/e3790000-0000-4000-8000-000000000051/adjunto.pdf',
      'e3790000-0000-4000-8000-000000000099')$$,
  '42501',
  null,
  'no sube adjuntos en la carpeta de otro taller');

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner)
    values ('job-images', 'e3790000-0000-4000-8000-000000000001/adjunto.pdf',
      'e3790000-0000-4000-8000-000000000099')$$,
  '42501',
  null,
  'un adjunto sin trabajo en la ruta no entra');

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000098', true);
set local role authenticated;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'job-images'),
  0,
  'otro taller no lista los adjuntos');

delete from storage.objects where bucket_id = 'job-images';

reset role;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'job-images'),
  1,
  'ni los borra');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e3790000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e3790000-0000-4000-8000-000000000099', true);
set local role authenticated;

delete from storage.objects where bucket_id = 'job-images';

reset role;

select is(
  (select count(*)::integer from storage.objects where bucket_id = 'job-images'),
  0,
  'el taller borra el adjunto huérfano de su carpeta');

select * from finish();
rollback;
