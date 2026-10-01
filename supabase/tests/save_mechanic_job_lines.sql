begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Las líneas del trabajo y lo que «Configurar» confirma de la bici se guardan
-- en una sola transacción con recibo (ítem 4, 2026-09-28): un corte a mitad no
-- deja líneas sin su ficha ni ficha sin sus líneas, un reintento no duplica y
-- un cambio ajeno a las líneas no se pisa.

select has_function('public', 'save_mechanic_job_lines_v1',
  array['text', 'uuid', 'jsonb', 'jsonb', 'jsonb', 'jsonb', 'jsonb', 'boolean'],
  'existe el comando que guarda cabecera, bicis, líneas, ficha y factura juntas');
select ok(
  has_function_privilege('authenticated',
    'public.get_mechanic_job_line_save_v1(text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_mechanic_job_line_save_v1(text)', 'EXECUTE'),
  'y la consulta de su recibo, igual');
select ok(
  has_function_privilege('authenticated',
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)', 'EXECUTE'),
  'lo llama el empleado autenticado, no el anónimo');

insert into public.tenants (id, shop_name) values
  ('e28a0000-0000-4000-8000-000000000001', 'Taller guardado de líneas'),
  ('e28a0000-0000-4000-8000-000000000002', 'Otro taller');

-- El alta del taller deja su propia identidad en la sesión.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e28a0000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'guardado-lineas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e28a0000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
  'guardado-lineas-ajeno@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role) values
  ('e28a0000-0000-4000-8000-000000000099',
   'e28a0000-0000-4000-8000-000000000001', 'admin'),
  ('e28a0000-0000-4000-8000-000000000098',
   'e28a0000-0000-4000-8000-000000000002', 'admin');
insert into public.customers (id, tenant_id, name) values
  ('e28a0000-0000-4000-8000-000000000010',
   'e28a0000-0000-4000-8000-000000000001', 'Cliente líneas'),
  ('e28a0000-0000-4000-8000-000000000011',
   'e28a0000-0000-4000-8000-000000000002', 'Cliente ajeno');
insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('e28a0000-0000-4000-8000-000000000031',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000010', 'Trek', 'Marlin 5'),
  ('e28a0000-0000-4000-8000-000000000032',
   'e28a0000-0000-4000-8000-000000000002',
   'e28a0000-0000-4000-8000-000000000011', 'Oxford', 'Ajena'),
  ('e28a0000-0000-4000-8000-000000000033',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000010', 'Giant', 'Talon 3');
-- Las pastillas del catálogo: su descripción trae renglones con viñeta, que
-- desde 20260929040000 son instrucción y no se convierten en tareas.
insert into public.products (id, tenant_id, name, product_type, description) values (
  'e28a0000-0000-4000-8000-000000000071',
  'e28a0000-0000-4000-8000-000000000001', 'Pastillas', 'product',
  E'Pastillas orgánicas para disco\n- Revisar desgaste\n\n  • Asentar pastillas');
insert into public.bike_profiles (tenant_id, bike_id, technical_profile) values (
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000031',
  jsonb_build_object(
    'values', jsonb_build_object('brakeType', 'rim'),
    'sources', jsonb_build_object('brakeType', 'intake'),
    'confirmed', jsonb_build_object('brakeType', true)));
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('e28a0000-0000-4000-8000-000000000051',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000010',
   'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-1',
   'e28a0000-0000-4000-8000-000000000099'),
  ('e28a0000-0000-4000-8000-000000000052',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000010',
   'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-2',
   'e28a0000-0000-4000-8000-000000000099'),
  ('e28a0000-0000-4000-8000-000000000053',
   'e28a0000-0000-4000-8000-000000000002',
   'e28a0000-0000-4000-8000-000000000011',
   'e28a0000-0000-4000-8000-000000000032', 'PG-AJENO-1',
   'e28a0000-0000-4000-8000-000000000099');
insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id) values
  ('e28a0000-0000-4000-8000-000000000041',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000051',
   'e28a0000-0000-4000-8000-000000000031'),
  ('e28a0000-0000-4000-8000-000000000042',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000052',
   'e28a0000-0000-4000-8000-000000000031');

-- Las líneas se cargaron antes: su versión es de otra transacción. En la
-- prueba todo corre en una sola, donde `now()` no cambia.
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_name, item_type, location_key,
  service_configuration_data, quantity, unit_price, updated_at
) values
  ('e28a0000-0000-4000-8000-000000000061',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000051',
   'e28a0000-0000-4000-8000-000000000041', 'Revisión de frenos', 'service',
   'none', '{"brake_type": "rim"}'::jsonb, 1, 15000, now() - interval '1 day'),
  ('e28a0000-0000-4000-8000-000000000062',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000051',
   'e28a0000-0000-4000-8000-000000000041', 'Cámara 29', 'product',
   'none', null, 1, 5000, now() - interval '1 day'),
  ('e28a0000-0000-4000-8000-000000000063',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000051',
   'e28a0000-0000-4000-8000-000000000041', 'Parche', 'product',
   'none', null, 1, 1000, now() - interval '1 day'),
  ('e28a0000-0000-4000-8000-000000000064',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000052',
   'e28a0000-0000-4000-8000-000000000042', 'Lubricación', 'service',
   'none', null, 1, 3000, now() - interval '1 day'),
  ('e28a0000-0000-4000-8000-000000000065',
   'e28a0000-0000-4000-8000-000000000001',
   'e28a0000-0000-4000-8000-000000000052',
   'e28a0000-0000-4000-8000-000000000042', 'Cadena', 'product',
   'none', null, 1, 12000, now() - interval '1 day');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e28a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e28a0000-0000-4000-8000-000000000099', true);

-- Lo que el formulario vio al abrir el trabajo.
create function pg_temp.seen(p_job uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'updated_at', updated_at) order by id), '[]'::jsonb)
    from public.mechanic_job_items
   where job_id = p_job
$$;
create function pg_temp.brake() returns jsonb language sql as $$
  select technical_profile->'values'->'brakeType'
    from public.bike_profiles
   where bike_id = 'e28a0000-0000-4000-8000-000000000031'
$$;
create function pg_temp.config(p_line uuid) returns jsonb language sql as $$
  select service_configuration_data
    from public.mechanic_job_items where id = p_line
$$;
create function pg_temp.lines(p_job uuid) returns integer language sql as $$
  select count(*)::integer from public.mechanic_job_items where job_id = p_job
$$;
create function pg_temp.receipts() returns integer language sql as $$
  select count(*)::integer from public.mechanic_job_line_saves
   where tenant_id = 'e28a0000-0000-4000-8000-000000000001'
$$;
create function pg_temp.tasks() returns integer language sql as $$
  select count(*)::integer from public.mechanic_job_tasks
   where job_id = 'e28a0000-0000-4000-8000-000000000051'
$$;
create function pg_temp.fact_receipts() returns integer language sql as $$
  select count(*)::integer from public.bike_technical_fact_patches
   where tenant_id = 'e28a0000-0000-4000-8000-000000000001'
$$;
-- El error completo de un guardado que falla, con su detalle y su pista.
create function pg_temp.save_error(
  p_key text, p_job uuid, p_seen jsonb, p_lines jsonb, p_facts jsonb,
  p_header jsonb default null, p_job_bikes jsonb default null,
  p_invoice boolean default false
) returns jsonb language plpgsql as $$
declare
  v_state text;
  v_message text;
  v_detail text;
  v_hint text;
begin
  perform public.save_mechanic_job_lines_v1(
    p_key, p_job, p_seen, p_lines, p_facts, p_header, p_job_bikes, p_invoice);
  return null;
exception when others then
  get stacked diagnostics
    v_state = returned_sqlstate,
    v_message = message_text,
    v_detail = pg_exception_detail,
    v_hint = pg_exception_hint;
  return jsonb_build_object(
    'state', v_state, 'message', v_message, 'detail', v_detail, 'hint', v_hint);
end;
$$;

create temporary table payloads (
  label text primary key, seen jsonb, lines jsonb, facts jsonb);
insert into payloads values (
  'guardar',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  jsonb_build_array(
    -- Configurar cambió la revisión de frenos: hidráulico.
    jsonb_build_object(
      'client_key', 'e28a0000-0000-4000-8000-000000000061',
      'id', 'e28a0000-0000-4000-8000-000000000061',
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000041',
      'product_name', 'Revisión de frenos', 'item_type', 'service',
      'quantity', 1, 'unit_price', 15000, 'location_key', 'none',
      'service_configuration_data', jsonb_build_object('brake_type', 'hydraulic_disc'),
      'notes', 'Frenos hidráulicos', 'creates_lifecycle', false),
    -- La cámara sigue igual.
    jsonb_build_object(
      'client_key', 'e28a0000-0000-4000-8000-000000000062',
      'id', 'e28a0000-0000-4000-8000-000000000062',
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000041',
      'product_name', 'Cámara 29', 'item_type', 'product',
      'quantity', 1, 'unit_price', 5000, 'location_key', 'none',
      'creates_lifecycle', false),
    -- Una línea nueva, del catálogo; el parche se quitó.
    jsonb_build_object(
      'client_key', 'nueva-pastillas',
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000041',
      'product_id', 'e28a0000-0000-4000-8000-000000000071',
      'product_name', 'Pastillas', 'item_type', 'product',
      'quantity', 2, 'unit_price', 8000, 'location_key', 'front',
      'creates_lifecycle', false)),
  jsonb_build_array(jsonb_build_object(
    'bike_id', 'e28a0000-0000-4000-8000-000000000031',
    'facts', jsonb_build_array(jsonb_build_object(
      'key', 'brakeType', 'op', 'set', 'value', 'hydraulic_disc',
      'expected', 'rim', 'expected_confirmed', true)))));

create temporary table results (label text primary key, result jsonb);

-- ============================================================================
-- Un corte después de escribir líneas y ficha, antes del recibo: nada queda
-- ============================================================================

-- El corte dice lo que ya estaba escrito cuando llegó: así la prueba muestra
-- que es intermedio, no un rechazo antes de empezar.
create function public.test_cut_before_line_save_receipt()
returns trigger language plpgsql as $$
begin
  raise exception 'corte simulado antes del recibo (línea: %, pastillas: %, tareas: %, parche: %, ficha: %)',
    (select service_configuration_data->>'brake_type' from public.mechanic_job_items
      where id = 'e28a0000-0000-4000-8000-000000000061'),
    (select count(*) from public.mechanic_job_items where product_name = 'Pastillas'),
    (select count(*) from public.mechanic_job_tasks
      where job_id = 'e28a0000-0000-4000-8000-000000000051'),
    (select count(*) from public.mechanic_job_items
      where id = 'e28a0000-0000-4000-8000-000000000063'),
    (select technical_profile->'values'->>'brakeType' from public.bike_profiles
      where bike_id = 'e28a0000-0000-4000-8000-000000000031');
end;
$$;
create trigger zz_test_cut_before_line_save_receipt
  before insert on public.mechanic_job_line_saves
  for each row execute function public.test_cut_before_line_save_receipt();

select throws_like(
  $$select public.save_mechanic_job_lines_v1('guardar-1',
      'e28a0000-0000-4000-8000-000000000051',
      (select seen from payloads where label = 'guardar'),
      (select lines from payloads where label = 'guardar'),
      (select facts from payloads where label = 'guardar'))$$,
  '%corte simulado antes del recibo (línea: hydraulic_disc, pastillas: 1, tareas: 0, parche: 0, ficha: hydraulic_disc)%',
  'el corte llega al final, con líneas y ficha ya escritas');
select is(pg_temp.config('e28a0000-0000-4000-8000-000000000061'),
  '{"brake_type": "rim"}'::jsonb, 'la línea cambiada vuelve a lo que era');
select ok(exists (select 1 from public.mechanic_job_items
                   where id = 'e28a0000-0000-4000-8000-000000000063'),
  'la línea quitada sigue ahí');
select is((select count(*)::integer from public.mechanic_job_items
            where product_name = 'Pastillas'), 0,
  'la línea nueva no quedó');
select is(pg_temp.brake(), '"rim"'::jsonb, 'la ficha no cambió');
select is(pg_temp.fact_receipts(), 0, 'ni quedó el recibo de la ficha');
select is(pg_temp.receipts(), 0, 'ni el del guardado');
select is(pg_temp.tasks(), 0, 'ni las tareas de la línea nueva');
select is(public.get_mechanic_job_line_save_v1('guardar-1'), null,
  'la bandeja pregunta por la llave y no hay recibo: toca reenviar');

drop trigger zz_test_cut_before_line_save_receipt on public.mechanic_job_line_saves;

-- ============================================================================
-- La ficha cambió mientras tanto: las líneas tampoco se guardan
-- ============================================================================

select is(
  (pg_temp.save_error('guardar-ficha-vieja',
     'e28a0000-0000-4000-8000-000000000051',
     (select seen from payloads where label = 'guardar'),
     (select lines from payloads where label = 'guardar'),
     jsonb_build_array(jsonb_build_object(
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'facts', jsonb_build_array(jsonb_build_object(
         'key', 'brakeType', 'op', 'set', 'value', 'hydraulic_disc',
         'expected', 'mechanical_disc', 'expected_confirmed', true)))))
   - 'message' - 'detail'),
  jsonb_build_object('state', 'PT409',
    'hint', 'bike_facts:e28a0000-0000-4000-8000-000000000031'),
  'un conflicto de la ficha rechaza el guardado y dice de qué bici');
select is(pg_temp.config('e28a0000-0000-4000-8000-000000000061'),
  '{"brake_type": "rim"}'::jsonb, 'y la línea no se guardó sin su ficha');
select is(pg_temp.lines('e28a0000-0000-4000-8000-000000000051'), 3,
  'ni se agregó ni se quitó ninguna');

-- Sólo lo que dice la ficha lleva la pista: un error pasajero dentro del
-- parche (un lock que no se pudo tomar) sale igual que llegó, y el formulario
-- no descarta lo pendiente por él.
create function public.test_transient_fact_error()
returns trigger language plpgsql as $$
begin
  raise exception 'lock de prueba no disponible' using errcode = '55P03';
end;
$$;
create trigger zz_test_transient_fact_error
  before insert on public.bike_technical_fact_patches
  for each row execute function public.test_transient_fact_error();
select is(
  (pg_temp.save_error('guardar-pasajero',
     'e28a0000-0000-4000-8000-000000000051',
     (select seen from payloads where label = 'guardar'),
     (select lines from payloads where label = 'guardar'),
     (select facts from payloads where label = 'guardar'))
   - 'message' - 'detail'),
  jsonb_build_object('state', '55P03', 'hint', ''),
  'un error pasajero no se presenta como rechazo de la ficha');
drop trigger zz_test_transient_fact_error on public.bike_technical_fact_patches;

select is(
  (pg_temp.save_error('guardar-dato-invalido',
     'e28a0000-0000-4000-8000-000000000051',
     (select seen from payloads where label = 'guardar'),
     (select lines from payloads where label = 'guardar'),
     jsonb_build_array(jsonb_build_object(
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'facts', jsonb_build_array(jsonb_build_object(
         'key', 'brakeType', 'op', 'set', 'value', 'freno_volador',
         'expected', 'rim', 'expected_confirmed', true)))))
   - 'message' - 'detail'),
  jsonb_build_object('state', 'P0001',
    'hint', 'bike_facts:e28a0000-0000-4000-8000-000000000031'),
  'un dato que la ficha no acepta sí dice de qué bici es');
select is(pg_temp.config('e28a0000-0000-4000-8000-000000000061'),
  '{"brake_type": "rim"}'::jsonb, 'y en los dos casos la línea no se guardó');

-- ============================================================================
-- El reintento con la misma llave, ya sin corte: una sola vez
-- ============================================================================

insert into results
select 'guardado', public.save_mechanic_job_lines_v1('guardar-1',
  'e28a0000-0000-4000-8000-000000000051',
  (select seen from payloads where label = 'guardar'),
  (select lines from payloads where label = 'guardar'),
  (select facts from payloads where label = 'guardar'));

select is(
  (select jsonb_build_object(
     'replayed', result->'replayed', 'inserted', result->'inserted',
     'updated', result->'updated', 'deleted', result->'deleted')
     from results where label = 'guardado'),
  '{"replayed": false, "inserted": 1, "updated": 1, "deleted": 1}'::jsonb,
  'escribe la cambiada, la nueva y la quitada; la igual no se reescribe');
select is(pg_temp.config('e28a0000-0000-4000-8000-000000000061'),
  '{"brake_type": "hydraulic_disc"}'::jsonb, 'la línea dice hidráulico');
select is(pg_temp.brake(), '"hydraulic_disc"'::jsonb,
  'y la ficha también, en la misma transacción');
select ok(
  exists (select 1 from public.bike_technical_fact_patches
           where operation_key = 'guardar-1:ficha:e28a0000-0000-4000-8000-000000000031'
             and source = 'service_wizard'),
  'con la llave derivada de la del guardado');
select ok(not exists (select 1 from public.mechanic_job_items
                       where id = 'e28a0000-0000-4000-8000-000000000063'),
  'el parche se quitó');
select is(
  (select updated_at from public.mechanic_job_items
    where id = 'e28a0000-0000-4000-8000-000000000062'),
  (select (value->>'updated_at')::timestamptz
     from payloads, jsonb_array_elements(seen)
    where label = 'guardar'
      and value->>'id' = 'e28a0000-0000-4000-8000-000000000062'),
  'la línea igual conserva su versión');
select is(
  (select (line->>'id')::uuid
     from results, jsonb_array_elements(result->'lines') line
    where label = 'guardado' and line->>'client_key' = 'nueva-pastillas'),
  (select id from public.mechanic_job_items where product_name = 'Pastillas'),
  'el recibo dice qué id tomó la línea nueva');
select is(jsonb_array_length((select result->'lines' from results
                               where label = 'guardado')), 3,
  'y la versión de cada línea que quedó');
-- La descripción del producto es instrucción: la línea nueva no nace con
-- tareas (antes, el disparador y la app las creaban y se repetían), y el
-- recibo sigue trayendo la cuenta, en 0.
select is(pg_temp.tasks(), 0,
  'la línea nueva no crea tareas desde la descripción de su producto');
select is((select result->'tasks_created' from results where label = 'guardado'),
  '0'::jsonb, 'y el recibo lo dice');

insert into results
select 'reintento', public.save_mechanic_job_lines_v1('guardar-1',
  'e28a0000-0000-4000-8000-000000000051',
  (select seen from payloads where label = 'guardar'),
  (select lines from payloads where label = 'guardar'),
  (select facts from payloads where label = 'guardar'));

select is((select result->'replayed' from results where label = 'reintento'),
  'true'::jsonb, 'la misma llave devuelve el recibo');
select is((select count(*)::integer from public.mechanic_job_items
            where product_name = 'Pastillas'), 1,
  'sin insertar otra vez la línea nueva');
select is(
  (select (result - 'replayed') from results where label = 'reintento'),
  (select (result - 'replayed') from results where label = 'guardado'),
  'con los mismos ids y versiones');
select is(pg_temp.receipts(), 1, 'un solo recibo del guardado');
select is(pg_temp.fact_receipts(), 1, 'y uno de la ficha');
select is(pg_temp.tasks(), 0,
  'el reintento tras una respuesta perdida no crea tareas');

-- La respuesta se perdió: la bandeja pregunta por la llave sin escribir.
select is(public.get_mechanic_job_line_save_v1('guardar-1'),
  (select result from results where label = 'reintento'),
  'la consulta devuelve el mismo recibo que el reintento');
select is(pg_temp.receipts(), 1, 'y no escribe nada');
select is(pg_temp.tasks(), 0, 'ni tareas');
select is(public.get_mechanic_job_line_save_v1('nunca-enviada'), null,
  'una llave que nunca llegó no tiene recibo');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e28a0000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e28a0000-0000-4000-8000-000000000098', true);
select is(public.get_mechanic_job_line_save_v1('guardar-1'), null,
  'otro taller no ve el recibo aunque sepa la llave');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e28a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e28a0000-0000-4000-8000-000000000099', true);

select throws_ok(
  $$select public.save_mechanic_job_lines_v1('guardar-1',
      'e28a0000-0000-4000-8000-000000000051',
      (select seen from payloads where label = 'guardar'),
      '[]'::jsonb,
      '[]'::jsonb)$$,
  '23000',
  'Job line save key was already used with different content',
  'la misma llave con otro contenido se rechaza');

-- ============================================================================
-- Otro cambió las líneas desde que se abrió el formulario
-- ============================================================================

insert into payloads values (
  'otro_trabajo',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000052'),
  jsonb_build_array(
    jsonb_build_object(
      'client_key', 'e28a0000-0000-4000-8000-000000000064',
      'id', 'e28a0000-0000-4000-8000-000000000064',
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000042',
      'product_name', 'Lubricación', 'item_type', 'service',
      'quantity', 1, 'unit_price', 3500, 'location_key', 'none'),
    jsonb_build_object(
      'client_key', 'e28a0000-0000-4000-8000-000000000065',
      'id', 'e28a0000-0000-4000-8000-000000000065',
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000042',
      'product_name', 'Cadena', 'item_type', 'product',
      'quantity', 1, 'unit_price', 12000, 'location_key', 'none')),
  '[]'::jsonb);

-- Otra persona, en otra transacción: cambia una, agrega otra.
update public.mechanic_job_items set notes = 'la tocó otro'
 where id = 'e28a0000-0000-4000-8000-000000000065';
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_name, item_type, unit_price
) values (
  'e28a0000-0000-4000-8000-000000000066',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000052',
  'e28a0000-0000-4000-8000-000000000042', 'Agregada por otro', 'product', 900);

select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint',
            'lines', (select jsonb_agg(c order by c->>'line_id')
                        from jsonb_array_elements((e->>'detail')::jsonb) c))
     from (select pg_temp.save_error('otro-1',
             'e28a0000-0000-4000-8000-000000000052',
             (select seen from payloads where label = 'otro_trabajo'),
             (select lines from payloads where label = 'otro_trabajo'),
             '[]'::jsonb) as e) x),
  jsonb_build_object('state', 'PT409', 'hint', 'job_lines_changed',
    'lines', jsonb_build_array(
      jsonb_build_object('line_id', 'e28a0000-0000-4000-8000-000000000065',
                         'reason', 'changed'),
      jsonb_build_object('line_id', 'e28a0000-0000-4000-8000-000000000066',
                         'reason', 'added'))),
  'nombra la línea que cambió otro y la que agregó');
select is(
  (select unit_price from public.mechanic_job_items
    where id = 'e28a0000-0000-4000-8000-000000000064'),
  3000::numeric, 'y no pisa nada: la lubricación sigue a 3000');
select ok(exists (select 1 from public.mechanic_job_items
                   where id = 'e28a0000-0000-4000-8000-000000000066'),
  'ni borra la que agregó el otro');

delete from public.mechanic_job_items
 where id = 'e28a0000-0000-4000-8000-000000000064';
select is(
  (select (e->>'detail')::jsonb @> jsonb_build_array(jsonb_build_object(
            'line_id', 'e28a0000-0000-4000-8000-000000000064',
            'reason', 'removed'))
     from (select pg_temp.save_error('otro-2',
             'e28a0000-0000-4000-8000-000000000052',
             (select seen from payloads where label = 'otro_trabajo'),
             (select lines from payloads where label = 'otro_trabajo'),
             '[]'::jsonb) as e) x),
  true, 'y la que borró');

-- ============================================================================
-- Sólo la ficha, con las líneas protegidas por un pago
-- ============================================================================

insert into results
select 'solo_ficha', public.save_mechanic_job_lines_v1('solo-ficha-1',
  'e28a0000-0000-4000-8000-000000000051', null, null,
  jsonb_build_array(jsonb_build_object(
    'bike_id', 'e28a0000-0000-4000-8000-000000000031',
    'facts', jsonb_build_array(jsonb_build_object(
      'key', 'valveType', 'op', 'set', 'value', 'presta',
      'expected', null, 'expected_confirmed', false)))));
select is(
  (select jsonb_build_object('lines', result->'lines',
            'inserted', result->'inserted', 'deleted', result->'deleted')
     from results where label = 'solo_ficha'),
  '{"lines": null, "inserted": 0, "deleted": 0}'::jsonb,
  'sin líneas no las toca');
select is(
  (select technical_profile->'values'->'valveType' from public.bike_profiles
    where bike_id = 'e28a0000-0000-4000-8000-000000000031'),
  '"presta"'::jsonb, 'y escribe la ficha con su recibo');

-- ============================================================================
-- Con la factura pagada, la cabecera sólo acepta lo que el formulario manda
-- ============================================================================

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  'e28a0000-0000-4000-8000-000000000081',
  'e28a0000-0000-4000-8000-000000000001', 'FV-LINEAS-1',
  'e28a0000-0000-4000-8000-000000000010', 'Cliente líneas', 'manual_sale',
  'draft', 20000, 20000, 0, 20000, 0, 20000, 'no_tax', '[]'::jsonb);
-- El pago existe; su asiento no es lo que se prueba aquí.
insert into public.payment_methods (id, tenant_id, code, name, account_id, is_active)
values ('e28a0000-0000-4000-8000-000000000082',
  'e28a0000-0000-4000-8000-000000000001', 'caja-lineas', 'Caja líneas',
  (select account.id from public.accounts account
    where account.tenant_id = 'e28a0000-0000-4000-8000-000000000001'
      and account.code = '1101'), true);
alter table public.sales_payments disable trigger user;
insert into public.sales_payments (id, tenant_id, invoice_id, payment_method_id, amount)
values ('e28a0000-0000-4000-8000-000000000083',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000081',
  'e28a0000-0000-4000-8000-000000000082', 20000);
alter table public.sales_payments enable trigger user;
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, bike_id, job_number, created_by, invoice_id
) values (
  'e28a0000-0000-4000-8000-000000000054',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000010',
  'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-PAGADO',
  'e28a0000-0000-4000-8000-000000000099',
  'e28a0000-0000-4000-8000-000000000081');

select is(
  (pg_temp.save_error('pagado-1',
     'e28a0000-0000-4000-8000-000000000054', null, null, '[]'::jsonb,
     jsonb_build_object(
       'is_warranty_job', jsonb_build_object('value', true, 'expected', false),
       'diagnosis', jsonb_build_object('value', 'Garantía', 'expected', null)))
   - 'message' - 'hint'),
  jsonb_build_object('state', '55000', 'detail', '["is_warranty_job"]'),
  'la garantía de un trabajo pagado no cambia desde el comando');
select is(
  (select jsonb_build_object('warranty', is_warranty_job, 'diagnosis', diagnosis)
     from public.mechanic_jobs where id = 'e28a0000-0000-4000-8000-000000000054'),
  '{"warranty": false, "diagnosis": null}'::jsonb,
  'y nada de esa cabecera quedó');
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('pagado-2',
      'e28a0000-0000-4000-8000-000000000054', null, null, '[]'::jsonb,
      jsonb_build_object('diagnosis', jsonb_build_object(
        'value', 'Garantía', 'expected', null)))$$,
  'el diagnóstico de un trabajo pagado sí se sigue editando');

-- Su bici ya estaba antes del pago; la guardia de pago de la bici no se
-- prueba aquí.
alter table public.mechanic_job_bikes
  disable trigger trg_mechanic_job_bikes_guard_paid_snapshot;
insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id) values (
  'e28a0000-0000-4000-8000-000000000044',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000054',
  'e28a0000-0000-4000-8000-000000000031');
alter table public.mechanic_job_bikes
  enable trigger trg_mechanic_job_bikes_guard_paid_snapshot;
select is(
  (pg_temp.save_error('pagado-bici-1',
     'e28a0000-0000-4000-8000-000000000054', null, null, '[]'::jsonb, null,
     jsonb_build_array(jsonb_build_object(
       'client_key', 'bici-31',
       'id', 'e28a0000-0000-4000-8000-000000000044',
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'requires_approval', true, 'diagnosis', 'Revisada',
       'expected', jsonb_build_object(
         'requires_approval', false, 'diagnosis', null))))
   - 'message' - 'hint'),
  jsonb_build_object('state', '55000', 'detail', '["requires_approval"]'),
  'la aprobación de la bici de un trabajo pagado no cambia desde el comando');
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('pagado-bici-2',
      'e28a0000-0000-4000-8000-000000000054', null, null, '[]'::jsonb, null,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'bici-31',
        'id', 'e28a0000-0000-4000-8000-000000000044',
        'bike_id', 'e28a0000-0000-4000-8000-000000000031',
        'diagnosis', 'Revisada',
        'expected', jsonb_build_object('diagnosis', null))))$$,
  'su diagnóstico sí');
select is(
  (select jsonb_build_object('approval', requires_approval, 'diagnosis', diagnosis)
     from public.mechanic_job_bikes
    where id = 'e28a0000-0000-4000-8000-000000000044'),
  '{"approval": false, "diagnosis": "Revisada"}'::jsonb,
  'y queda sólo el diagnóstico');

-- ============================================================================
-- Mano de obra de 1,5 h: guardar, reabrir y guardar sin tocarla
-- ============================================================================

-- Lo que manda el formulario al reabrir sin cambios: cada línea como quedó.
create function pg_temp.reopened(p_job uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'client_key', i.id, 'id', i.id, 'job_bike_id', i.job_bike_id,
           'product_id', i.product_id, 'service_product_id', i.service_product_id,
           'product_name', i.product_name, 'product_sku', i.product_sku,
           'quantity', i.quantity, 'unit_price', i.unit_price, 'notes', i.notes,
           'service_configuration_data', i.service_configuration_data,
           'item_type', i.item_type, 'system_key', i.system_key,
           'component_slot_key', i.component_slot_key,
           'location_key', i.location_key,
           'intervention_type', i.intervention_type,
           'creates_lifecycle', i.creates_lifecycle) order by i.id), '[]'::jsonb)
    from public.mechanic_job_items i
   where i.job_id = p_job
$$;

insert into results
select 'mano_de_obra', public.save_mechanic_job_lines_v1('horas-1',
  'e28a0000-0000-4000-8000-000000000051',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  pg_temp.reopened('e28a0000-0000-4000-8000-000000000051') || jsonb_build_array(
    jsonb_build_object(
      'client_key', 'labor-1', 'product_name', 'Mano de obra', 'product_sku', '',
      'quantity', 1.5, 'unit_price', 20000, 'item_type', 'service',
      'notes', 'Labor: 1.5h @ $20000/hr', 'location_key', 'none',
      'creates_lifecycle', false)),
  '[]'::jsonb);
create temporary table labor_before as
select id, quantity, total_price, updated_at
  from public.mechanic_job_items where product_name = 'Mano de obra';
select is(
  (select jsonb_build_object('quantity', quantity, 'total', total_price)
     from labor_before),
  '{"quantity": 1.50, "total": 30000.00}'::jsonb,
  'la mano de obra queda con 1,5 h y su total');

insert into results
select 'reabierta', public.save_mechanic_job_lines_v1('horas-2',
  'e28a0000-0000-4000-8000-000000000051',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
  '[]'::jsonb);
select is(
  (select jsonb_build_object('inserted', result->'inserted',
            'updated', result->'updated', 'deleted', result->'deleted')
     from results where label = 'reabierta'),
  '{"inserted": 0, "updated": 0, "deleted": 0}'::jsonb,
  'reabrir y guardar sin cambios no reescribe nada');
select is(
  (select jsonb_build_object('id', i.id, 'quantity', i.quantity,
            'total', i.total_price, 'version', i.updated_at)
     from public.mechanic_job_items i where i.product_name = 'Mano de obra'),
  (select jsonb_build_object('id', id, 'quantity', quantity,
            'total', total_price, 'version', updated_at)
     from labor_before),
  'la misma línea, con sus horas, su total y su versión');
-- Mano de obra para los costos igual que para la factura: se guardaba como
-- texto libre, que los costos suman a repuestos y la factura a mano de obra.
-- Revisión de frenos 15 000 + 1,5 h × 20 000; cámara 5 000 + pastillas 16 000.
select is(
  (select jsonb_build_object('parts', parts_cost, 'labor', labor_cost)
     from public.mechanic_jobs
    where id = 'e28a0000-0000-4000-8000-000000000051'),
  '{"parts": 21000.00, "labor": 45000.00}'::jsonb,
  'y cuenta como mano de obra, no como repuesto');

-- ============================================================================
-- La cabecera en el mismo comando: sólo lo que cambió, con lo que se vio
-- ============================================================================

-- Un campo de la cabecera tal como lo manda el servidor.
create function pg_temp.seen_header(p_job uuid, p_column text) returns jsonb
language sql as $$
  select to_jsonb(j)->p_column from public.mechanic_jobs j where j.id = p_job
$$;

insert into results
select 'cabecera', public.save_mechanic_job_lines_v1('cabecera-1',
  'e28a0000-0000-4000-8000-000000000051',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
  '[]'::jsonb,
  jsonb_build_object(
    'diagnosis', jsonb_build_object(
      'value', 'Pastillas cristalizadas',
      'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000051', 'diagnosis')),
    -- La fecha que vio, escrita de otra forma: se compara como fecha.
    'arrival_date', jsonb_build_object(
      'value', '2026-09-20T09:30:00Z',
      'expected', to_jsonb((select to_char(arrival_date at time zone 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                              from public.mechanic_jobs
                             where id = 'e28a0000-0000-4000-8000-000000000051')))));
select is(
  (select jsonb_build_object('diagnosis', diagnosis,
            'arrival', arrival_date = '2026-09-20 09:30:00+00')
     from public.mechanic_jobs where id = 'e28a0000-0000-4000-8000-000000000051'),
  '{"diagnosis": "Pastillas cristalizadas", "arrival": true}'::jsonb,
  'la cabecera cambia en la misma transacción que las líneas');
select is(
  (select result->'header'->>'diagnosis' from results where label = 'cabecera'),
  'Pastillas cristalizadas',
  'y el recibo trae la cabecera que quedó, para el guardado siguiente');
select ok(
  not ((select result->'header' from results where label = 'cabecera')
       ?| array['invoice_id', 'status', 'total_cost', 'final_cost']),
  'sólo con los campos que edita el formulario');

-- Otra persona cambió la prioridad desde la tabla: el formulario, que sólo
-- cambió el diagnóstico, no la pisa.
update public.mechanic_jobs set priority = 'URGENTE'
 where id = 'e28a0000-0000-4000-8000-000000000051';
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('cabecera-2',
      'e28a0000-0000-4000-8000-000000000051', null, null, '[]'::jsonb,
      jsonb_build_object('diagnosis', jsonb_build_object(
        'value', 'Pastillas cambiadas',
        'expected', (select result->'header'->'diagnosis'
                       from results where label = 'cabecera'))))$$,
  'un cambio ajeno en otro campo no choca');
select is(
  (select jsonb_build_object('diagnosis', diagnosis, 'priority', priority)
     from public.mechanic_jobs where id = 'e28a0000-0000-4000-8000-000000000051'),
  '{"diagnosis": "Pastillas cambiadas", "priority": "URGENTE"}'::jsonb,
  'y la prioridad que puso el otro queda');

-- Otra persona cambió el mismo campo: no se guarda nada, tampoco las líneas.
update public.mechanic_jobs set diagnosis = 'Lo que escribió otro'
 where id = 'e28a0000-0000-4000-8000-000000000051';
select is(
  (pg_temp.save_error('cabecera-3',
     'e28a0000-0000-4000-8000-000000000051',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000051')
       || jsonb_build_array(jsonb_build_object(
            'client_key', 'nueva-luz', 'product_name', 'Luz trasera',
            'quantity', 1, 'unit_price', 7000)),
     '[]'::jsonb,
     jsonb_build_object('diagnosis', jsonb_build_object(
       'value', 'Lo mío', 'expected', 'Pastillas cambiadas')))
   - 'message'),
  jsonb_build_object('state', 'PT409', 'detail', '["diagnosis"]',
    'hint', 'job_header_changed'),
  'el mismo campo cambiado por otro rechaza el guardado y dice cuál');
select is((select count(*)::integer from public.mechanic_job_items
            where product_name = 'Luz trasera'), 0,
  'y la línea nueva no quedó');
select is(
  (select diagnosis from public.mechanic_jobs
    where id = 'e28a0000-0000-4000-8000-000000000051'),
  'Lo que escribió otro', 'ni se pisó lo del otro');

-- El descuento se aplica al final, con el subtotal de las líneas nuevas.
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('cabecera-4',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
      '[]'::jsonb,
      jsonb_build_object('discount_amount', jsonb_build_object(
        'value', 1000,
        'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000051',
                                        'discount_amount'))))$$,
  'el descuento viaja en el mismo comando');
select is(
  (select jsonb_build_object('discount', discount_amount,
            'total', total_cost = parts_cost + labor_cost - 1000,
            'final', final_cost = total_cost)
     from public.mechanic_jobs
    where id = 'e28a0000-0000-4000-8000-000000000051'),
  '{"discount": 1000.00, "total": true, "final": true}'::jsonb,
  'y el total ya lo descuenta: antes quedaba el de antes del descuento');

select throws_like(
  $$select public.save_mechanic_job_lines_v1('cabecera-5',
      'e28a0000-0000-4000-8000-000000000051', null, null, '[]'::jsonb,
      jsonb_build_object('invoice_id', jsonb_build_object(
        'value', null, 'expected', null)))$$,
  '%Header field invoice_id is not one the form edits%',
  'la factura, el estado y los costos no se tocan desde aquí');

-- ============================================================================
-- Las bicis del trabajo en el mismo comando
-- ============================================================================

create function pg_temp.bike_diagnosis(p_job_bike uuid) returns text
language sql as $$
  select diagnosis from public.mechanic_job_bikes where id = p_job_bike
$$;
create function pg_temp.job_bike(p_job uuid, p_bike uuid) returns uuid
language sql as $$
  select id from public.mechanic_job_bikes where job_id = p_job and bike_id = p_bike
$$;

-- Rechazado por la cabecera: el diagnóstico de la bici tampoco queda (antes
-- el formulario lo escribía por su cuenta, antes del comando).
select is(
  (pg_temp.save_error('bicis-1',
     'e28a0000-0000-4000-8000-000000000051',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
     '[]'::jsonb,
     jsonb_build_object('diagnosis', jsonb_build_object(
       'value', 'Mío', 'expected', 'No es lo que hay')),
     jsonb_build_array(jsonb_build_object(
       'client_key', 'bici-31',
       'id', 'e28a0000-0000-4000-8000-000000000041',
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'diagnosis', 'Frenos revisados',
       'expected', jsonb_build_object('diagnosis', null))))->>'hint'),
  'job_header_changed', 'un conflicto de cabecera rechaza el guardado');
select is(pg_temp.bike_diagnosis('e28a0000-0000-4000-8000-000000000041'), null,
  'y el diagnóstico de la bici no quedó escrito sin lo demás');

-- Una bici nueva con su línea, que la nombra por su llave; de la otra, sólo
-- el campo que cambió, con lo que se vio.
insert into results
select 'bicis', public.save_mechanic_job_lines_v1('bicis-2',
  'e28a0000-0000-4000-8000-000000000051',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  pg_temp.reopened('e28a0000-0000-4000-8000-000000000051')
    || jsonb_build_array(jsonb_build_object(
         'client_key', 'nueva-luz', 'product_name', 'Luz delantera',
         'quantity', 1, 'unit_price', 7000, 'job_bike_key', 'bici-33')),
  '[]'::jsonb, null,
  jsonb_build_array(
    jsonb_build_object(
      'client_key', 'bici-31',
      'id', 'e28a0000-0000-4000-8000-000000000041',
      'bike_id', 'e28a0000-0000-4000-8000-000000000031',
      'diagnosis', 'Frenos revisados',
      'expected', jsonb_build_object('diagnosis', null)),
    jsonb_build_object(
      'client_key', 'bici-33',
      'bike_id', 'e28a0000-0000-4000-8000-000000000033',
      'order_index', 1, 'diagnosis', 'Llega sin luz')));
select is(
  (select jsonb_build_object('inserted', result->'job_bikes_inserted',
            'updated', result->'job_bikes_updated',
            'deleted', result->'job_bikes_deleted')
     from results where label = 'bicis'),
  '{"inserted": 1, "updated": 1, "deleted": 0}'::jsonb,
  'agrega la bici nueva y escribe lo que cambió de la otra');
select is(pg_temp.bike_diagnosis('e28a0000-0000-4000-8000-000000000041'),
  'Frenos revisados', 'el diagnóstico de la bici queda con las líneas');
select is(
  (select line.job_bike_id from public.mechanic_job_items line
    where line.product_name = 'Luz delantera'),
  pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                   'e28a0000-0000-4000-8000-000000000033'),
  'la línea nueva queda en la bici nueva');
select is(
  (select jsonb_build_object('id', (entry->>'id')::uuid,
            'diagnosis', entry->'row'->>'diagnosis')
     from results, jsonb_array_elements(result->'job_bikes') entry
    where label = 'bicis' and entry->>'client_key' = 'bici-33'),
  jsonb_build_object('id', pg_temp.job_bike(
      'e28a0000-0000-4000-8000-000000000051',
      'e28a0000-0000-4000-8000-000000000033'),
    'diagnosis', 'Llega sin luz'),
  'el recibo dice qué id tomó, por su llave, y lo que quedó');
select is(
  (public.get_mechanic_job_line_save_v1('bicis-2') - 'replayed'),
  (select result - 'replayed' from results where label = 'bicis'),
  'tras una respuesta perdida, el recibo trae las bicis');
select is(
  (select count(*)::integer from public.mechanic_job_bikes
    where job_id = 'e28a0000-0000-4000-8000-000000000051'), 2,
  'sin agregar la bici otra vez');

-- Quitar la bici con su línea todavía en ella: no queda borrada a medias.
create temporary table quitada as
select pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                        'e28a0000-0000-4000-8000-000000000033') as id;
select throws_like(
  $$select public.save_mechanic_job_lines_v1('bicis-3',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
      '[]'::jsonb, null,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'bici-33', 'id', (select id from quitada),
        'bike_id', 'e28a0000-0000-4000-8000-000000000033',
        'remove', true,
        'expected', jsonb_build_object('diagnosis', 'Llega sin luz'))))$$,
  '%es de una bici que sale de este trabajo%',
  'una línea no se queda en una bici que sale');

insert into results
select 'bici_quitada', public.save_mechanic_job_lines_v1('bicis-4',
  'e28a0000-0000-4000-8000-000000000051',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
  (select jsonb_agg(line)
     from jsonb_array_elements(
            pg_temp.reopened('e28a0000-0000-4000-8000-000000000051')) line
    where line->>'product_name' <> 'Luz delantera'),
  '[]'::jsonb, null,
  jsonb_build_array(jsonb_build_object(
    'client_key', 'bici-33', 'id', (select id from quitada),
    'bike_id', 'e28a0000-0000-4000-8000-000000000033', 'remove', true,
    'expected', jsonb_build_object('diagnosis', 'Llega sin luz'))));
select is(
  (select jsonb_build_object('updated', result->'job_bikes_updated',
            'deleted', result->'job_bikes_deleted', 'lines', result->'deleted')
     from results where label = 'bici_quitada'),
  '{"updated": 0, "deleted": 1, "lines": 1}'::jsonb,
  'quita la bici que se marcó y su línea; la otra no se toca');
select ok(
  not exists (select 1 from public.mechanic_job_bikes
               where id = (select id from quitada)),
  'la bici ya no está en el trabajo');

-- Otra persona agrega una bici sin líneas: un guardado que no la nombra la
-- deja (antes, «las que faltan» se borraban).
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id, order_index)
values ('e28a0000-0000-4000-8000-000000000001',
        'e28a0000-0000-4000-8000-000000000051',
        'e28a0000-0000-4000-8000-000000000033', 1);
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('bicis-agregada',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
      '[]'::jsonb, null, '[]'::jsonb)$$,
  'un guardado que no nombra la bici que agregó otro');
select ok(
  pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                   'e28a0000-0000-4000-8000-000000000033') is not null,
  'la deja en el trabajo');

-- Otra persona cambió el diagnóstico de la bici: el formulario no lo pisa.
update public.mechanic_job_bikes set diagnosis = 'Lo que vio otro'
 where id = 'e28a0000-0000-4000-8000-000000000041';
select is(
  (pg_temp.save_error('bicis-pisar',
     'e28a0000-0000-4000-8000-000000000051',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
     '[]'::jsonb, null,
     jsonb_build_array(jsonb_build_object(
       'client_key', 'bici-31',
       'id', 'e28a0000-0000-4000-8000-000000000041',
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'diagnosis', 'Lo mío',
       'expected', jsonb_build_object('diagnosis', 'Frenos revisados'))))
   - 'message'),
  jsonb_build_object('state', 'PT409',
    'detail', jsonb_build_array(jsonb_build_object(
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000041',
      'field', 'diagnosis'))::text,
    'hint', 'job_bikes_changed'),
  'el diagnóstico que cambió otro rechaza el guardado y dice cuál');
select is(pg_temp.bike_diagnosis('e28a0000-0000-4000-8000-000000000041'),
  'Lo que vio otro', 'y queda lo del otro');

-- Otra persona quitó la bici que el formulario todavía muestra.
select is(
  (pg_temp.save_error('bicis-5',
     'e28a0000-0000-4000-8000-000000000051',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
     '[]'::jsonb, null,
     jsonb_build_array(jsonb_build_object(
       'client_key', 'bici-ajena',
       'id', 'e28a0000-0000-4000-8000-000000000042',
       'bike_id', 'e28a0000-0000-4000-8000-000000000031',
       'diagnosis', 'x', 'expected', jsonb_build_object('diagnosis', null))))
   - 'message'),
  jsonb_build_object('state', 'PT409',
    'detail', jsonb_build_array(jsonb_build_object(
      'job_bike_id', 'e28a0000-0000-4000-8000-000000000042',
      'reason', 'removed'))::text,
    'hint', 'job_bikes_changed'),
  'una bici que ya no está en el trabajo es un conflicto, no se inserta');

select throws_like(
  $$select public.save_mechanic_job_lines_v1('bicis-6',
      'e28a0000-0000-4000-8000-000000000051', null, null, '[]'::jsonb, null,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'bici-33',
        'bike_id', 'e28a0000-0000-4000-8000-000000000033')))$$,
  '%keeps its bicycles%',
  'sin líneas (trabajo con pago) no se agregan bicis');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('bicis-7',
      'e28a0000-0000-4000-8000-000000000051', null, null, '[]'::jsonb, null,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'bici-31',
        'id', 'e28a0000-0000-4000-8000-000000000041',
        'bike_id', 'e28a0000-0000-4000-8000-000000000031',
        'diagnosis', 'Sin lo visto')))$$,
  '%sends each changed field with the value it saw%',
  'de una bici que ya estaba, nada cambia sin lo que se vio');

-- Quitar una bici que otro cambió desde que se cargó: no se borra.
update public.mechanic_job_bikes set diagnosis = 'Lo escribió otro'
 where id = pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                             'e28a0000-0000-4000-8000-000000000033');
select is(
  (pg_temp.save_error('bicis-quitar-cambiada',
     'e28a0000-0000-4000-8000-000000000051',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
     '[]'::jsonb, null,
     jsonb_build_array(jsonb_build_object(
       'client_key', 'bici-33',
       'id', pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                              'e28a0000-0000-4000-8000-000000000033'),
       'bike_id', 'e28a0000-0000-4000-8000-000000000033', 'remove', true,
       'expected', jsonb_build_object('diagnosis', null))))->>'hint'),
  'job_bikes_changed', 'quitar una bici que otro cambió es un conflicto');
select is(
  pg_temp.bike_diagnosis(pg_temp.job_bike(
    'e28a0000-0000-4000-8000-000000000051',
    'e28a0000-0000-4000-8000-000000000033')),
  'Lo escribió otro', 'y la bici queda con lo del otro');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('bicis-quitar-sin-visto',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      pg_temp.reopened('e28a0000-0000-4000-8000-000000000051'),
      '[]'::jsonb, null,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'bici-33',
        'id', pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                               'e28a0000-0000-4000-8000-000000000033'),
        'bike_id', 'e28a0000-0000-4000-8000-000000000033',
        'remove', true)))$$,
  '%what was seen of it%',
  'una bici no sale sin lo que se vio de ella');

-- Mover una línea de una bici a otra: los costos de las dos.
select lives_ok(
  $$select public.save_mechanic_job_lines_v1('mover-linea',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      (select jsonb_agg(case when line->>'product_name' = 'Cámara 29'
                        then line || jsonb_build_object('job_bike_id',
                               pg_temp.job_bike('e28a0000-0000-4000-8000-000000000051',
                                                'e28a0000-0000-4000-8000-000000000033'))
                        else line end)
         from jsonb_array_elements(
                pg_temp.reopened('e28a0000-0000-4000-8000-000000000051')) line),
      '[]'::jsonb)$$,
  'la cámara pasa a la otra bici');
select is(
  (select jsonb_agg(jsonb_build_object('bike', jb.bike_id, 'parts', jb.parts_cost)
                    order by jb.bike_id)
     from public.mechanic_job_bikes jb
    where jb.job_id = 'e28a0000-0000-4000-8000-000000000051'),
  jsonb_build_array(
    jsonb_build_object('bike', 'e28a0000-0000-4000-8000-000000000031',
                       'parts', 16000),
    jsonb_build_object('bike', 'e28a0000-0000-4000-8000-000000000033',
                       'parts', 5000)),
  'la bici de antes deja de contarla y la nueva la cuenta');

-- ============================================================================
-- La factura del trabajo, en la misma transacción que el recibo
-- ============================================================================

create function pg_temp.invoice_of(p_job uuid) returns uuid language sql as $$
  select invoice_id from public.mechanic_jobs where id = p_job
$$;
create function pg_temp.invoices() returns integer language sql as $$
  select count(*)::integer from public.sales_invoices
   where tenant_id = 'e28a0000-0000-4000-8000-000000000001'
$$;
create temporary table invoices_before as select pg_temp.invoices() as n;

-- El guardado tal como lo respalda la bandeja: el mismo en el corte, el
-- reenvío y la repetición.
create temporary table factura_payload as
select pg_temp.seen('e28a0000-0000-4000-8000-000000000052') as seen,
       pg_temp.reopened('e28a0000-0000-4000-8000-000000000052')
         || jsonb_build_array(jsonb_build_object(
              'client_key', 'nueva-cinta', 'product_name', 'Cinta de manubrio',
              'quantity', 1, 'unit_price', 6000)) as lines;

-- Un corte después de escribir líneas y factura, antes del recibo.
create function public.test_cut_before_invoice_receipt()
returns trigger language plpgsql as $$
begin
  raise exception 'corte simulado con factura (factura: %)',
    (select invoice_id is not null from public.mechanic_jobs
      where id = 'e28a0000-0000-4000-8000-000000000052');
end;
$$;
create trigger zz_test_cut_before_invoice_receipt
  before insert on public.mechanic_job_line_saves
  for each row execute function public.test_cut_before_invoice_receipt();
select throws_like(
  $$select public.save_mechanic_job_lines_v1('factura-1',
      'e28a0000-0000-4000-8000-000000000052',
      (select seen from factura_payload), (select lines from factura_payload),
      '[]'::jsonb, null, null, true)$$,
  '%corte simulado con factura (factura: t)%',
  'el corte llega con la factura ya creada');
drop trigger zz_test_cut_before_invoice_receipt on public.mechanic_job_line_saves;
select is(pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000052'), null,
  'y no deja factura');
select is(pg_temp.invoices(), (select n from invoices_before),
  'ni una factura suelta');

-- La app se cerró sin respuesta: la bandeja reenvía el mismo comando.
insert into results
select 'factura', public.save_mechanic_job_lines_v1('factura-1',
  'e28a0000-0000-4000-8000-000000000052',
  (select seen from factura_payload), (select lines from factura_payload),
  '[]'::jsonb, null, null, true);
select is(
  (select jsonb_build_object('action', result->'invoice'->>'action',
            'invoice', (result->'invoice'->>'invoice_id')::uuid)
     from results where label = 'factura'),
  jsonb_build_object('action', 'created',
    'invoice', pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000052')),
  'el comando crea la factura del trabajo y el recibo la nombra');
select is(
  (select total from public.sales_invoices
    where id = pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000052')),
  (select sum(total_price) from public.mechanic_job_items
    where job_id = 'e28a0000-0000-4000-8000-000000000052'),
  'con las líneas que acaba de guardar, la nueva incluida');

-- Llegó, pero la respuesta se perdió: el reenvío devuelve el recibo.
insert into results
select 'factura_repetida', public.save_mechanic_job_lines_v1('factura-1',
  'e28a0000-0000-4000-8000-000000000052',
  (select seen from factura_payload), (select lines from factura_payload),
  '[]'::jsonb, null, null, true);
select is(
  (select jsonb_build_object('replayed', result->'replayed',
            'invoice', result->'invoice')
     from results where label = 'factura_repetida'),
  (select jsonb_build_object('replayed', true, 'invoice', result->'invoice')
     from results where label = 'factura'),
  'el reenvío devuelve el recibo con la misma factura');
select is(
  (public.get_mechanic_job_line_save_v1('factura-1') - 'replayed'),
  (select result - 'replayed' from results where label = 'factura'),
  'tras una respuesta perdida, el recibo dice la misma factura');
select is(pg_temp.invoices(), (select n from invoices_before) + 1,
  'una sola factura');

-- Editar el trabajo facturado: la factura queda con lo nuevo, descuento
-- incluido, en el mismo comando.
insert into results
select 'factura_editada', public.save_mechanic_job_lines_v1('factura-2',
  'e28a0000-0000-4000-8000-000000000052',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000052'),
  (select jsonb_agg(case when line->>'product_name' = 'Cinta de manubrio'
                    then line || jsonb_build_object('unit_price', 9000)
                    else line end)
     from jsonb_array_elements(
            pg_temp.reopened('e28a0000-0000-4000-8000-000000000052')) line),
  '[]'::jsonb,
  jsonb_build_object('discount_amount', jsonb_build_object(
    'value', 500,
    'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000052',
                                    'discount_amount'))),
  null, true);
select is(
  (select result->'invoice'->>'action' from results where label = 'factura_editada'),
  'synced', 'con factura, la sincroniza');
select is(
  (select total from public.sales_invoices
    where id = pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000052')),
  (select sum(total_price) - 500 from public.mechanic_job_items
    where job_id = 'e28a0000-0000-4000-8000-000000000052'),
  'con el precio y el descuento nuevos');
select is(pg_temp.invoices(), (select n from invoices_before) + 1,
  'sin crear otra');

-- Con la factura pagada, la continuación no la toca.
create temporary table paid_before as
select to_jsonb(invoice) - 'updated_at' as row
  from public.sales_invoices invoice
 where id = 'e28a0000-0000-4000-8000-000000000081';
insert into results
select 'factura_pagada', public.save_mechanic_job_lines_v1('factura-pagada',
  'e28a0000-0000-4000-8000-000000000054', null, null, '[]'::jsonb,
  jsonb_build_object('diagnosis', jsonb_build_object(
    'value', 'Pagado y revisado',
    'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000054',
                                    'diagnosis'))),
  null, true);
select is(
  (select result->'invoice'->>'action' from results where label = 'factura_pagada'),
  'protected', 'con pagos la factura queda protegida');
select is(
  (select to_jsonb(invoice) - 'updated_at' from public.sales_invoices invoice
    where id = 'e28a0000-0000-4000-8000-000000000081'),
  (select row from paid_before),
  'y queda exactamente como estaba');

-- Con la factura confirmada (ya contabilizada) y sin pagos, lo que cambiaría
-- lo que se cobra se rechaza antes de escribir: `sync_job_to_invoice` dejaría
-- su total nuevo con el asiento de antes, y no sincronizar dejaría el trabajo
-- distinto de su factura. Se corrige desde la factura; el diagnóstico sigue.
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  'e28a0000-0000-4000-8000-000000000084',
  'e28a0000-0000-4000-8000-000000000001', 'FV-LINEAS-CONFIRMADA',
  'e28a0000-0000-4000-8000-000000000010', 'Cliente líneas', 'manual_sale',
  'confirmed', 10000, 10000, 0, 10000, 0, 10000, 'no_tax', '[]'::jsonb);
-- La línea antes de vincular la factura: con ella ya confirmada, ninguna
-- escritura directa entra (abajo).
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, bike_id, job_number, created_by
) values (
  'e28a0000-0000-4000-8000-000000000057',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000010',
  'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-CONFIRMADA',
  'e28a0000-0000-4000-8000-000000000099');
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key, quantity,
  unit_price, updated_at
) values (
  'e28a0000-0000-4000-8000-000000000067',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000057', 'Revisión', 'service', 'none', 1,
  10000, now() - interval '1 day');
update public.mechanic_jobs
   set invoice_id = 'e28a0000-0000-4000-8000-000000000084'
 where id = 'e28a0000-0000-4000-8000-000000000057';
create temporary table confirmed_before as
select to_jsonb(invoice) - 'updated_at' as row
  from public.sales_invoices invoice
 where id = 'e28a0000-0000-4000-8000-000000000084';
create temporary table confirmed_lines_before as
select to_jsonb(i) as row
  from public.mechanic_job_items i
 where job_id = 'e28a0000-0000-4000-8000-000000000057';
create function pg_temp.confirmed_unchanged() returns boolean language sql as $$
  select (select to_jsonb(invoice) - 'updated_at' from public.sales_invoices invoice
           where id = 'e28a0000-0000-4000-8000-000000000084')
         = (select row from confirmed_before)
     and (select jsonb_agg(to_jsonb(i) order by i.id) from public.mechanic_job_items i
           where job_id = 'e28a0000-0000-4000-8000-000000000057')
         = (select jsonb_agg(row order by row->>'id') from confirmed_lines_before)
     and (select discount_amount from public.mechanic_jobs
           where id = 'e28a0000-0000-4000-8000-000000000057') = 0
     and not exists (select 1 from public.mechanic_job_line_saves
                      where operation_key like 'confirmada-%')
$$;

select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint',
            'detail', (e->>'detail')::jsonb)
     from pg_temp.save_error('confirmada-nueva',
       'e28a0000-0000-4000-8000-000000000057',
       pg_temp.seen('e28a0000-0000-4000-8000-000000000057'),
       pg_temp.reopened('e28a0000-0000-4000-8000-000000000057')
         || jsonb_build_array(jsonb_build_object(
              'client_key', 'nueva-lavado', 'product_name', 'Lavado',
              'item_type', 'service', 'quantity', 1, 'unit_price', 8000)),
       '[]'::jsonb, null, null, true) e),
  '{"state": "55000", "hint": "invoice_posted", "detail": ["línea: Lavado"]}'::jsonb,
  'con la factura confirmada, una línea nueva se rechaza y dice cuál');
select ok(pg_temp.confirmed_unchanged(),
  'sin escribir nada: ni la línea, ni la factura, ni el recibo');
select matches(
  (select e->>'message' from pg_temp.save_error('confirmada-nueva',
     'e28a0000-0000-4000-8000-000000000057',
     pg_temp.seen('e28a0000-0000-4000-8000-000000000057'),
     pg_temp.reopened('e28a0000-0000-4000-8000-000000000057')
       || jsonb_build_array(jsonb_build_object(
            'client_key', 'nueva-lavado', 'product_name', 'Lavado',
            'item_type', 'service', 'quantity', 1, 'unit_price', 8000)),
     '[]'::jsonb, null, null, true) e),
  'FV-LINEAS-CONFIRMADA.*se corrige desde la factura',
  'y manda a corregir desde la factura, que nombra');
select is(
  (select (e->>'detail')::jsonb
     from pg_temp.save_error('confirmada-precio',
       'e28a0000-0000-4000-8000-000000000057',
       pg_temp.seen('e28a0000-0000-4000-8000-000000000057'),
       (select jsonb_agg(line || jsonb_build_object('unit_price', 12000))
          from jsonb_array_elements(
                 pg_temp.reopened('e28a0000-0000-4000-8000-000000000057')) line),
       '[]'::jsonb, null, null, true) e),
  '["línea: Revisión"]'::jsonb,
  'también un precio cambiado');
select is(
  (select (e->>'detail')::jsonb
     from pg_temp.save_error('confirmada-quitar',
       'e28a0000-0000-4000-8000-000000000057',
       pg_temp.seen('e28a0000-0000-4000-8000-000000000057'),
       '[]'::jsonb, '[]'::jsonb, null, null, true) e),
  '["quitar: Revisión"]'::jsonb,
  'y una línea quitada');
select is(
  (select (e->>'detail')::jsonb
     from pg_temp.save_error('confirmada-descuento',
       'e28a0000-0000-4000-8000-000000000057', null, null, '[]'::jsonb,
       jsonb_build_object('discount_amount', jsonb_build_object(
         'value', 1000,
         'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000057',
                                         'discount_amount'))),
       null, true) e),
  '["discount_amount"]'::jsonb,
  'y el descuento');
select ok(pg_temp.confirmed_unchanged(), 'y nada de eso quedó escrito');

-- El diagnóstico sí, con las líneas tal como estaban: la factura no cambia y
-- el recibo dice que está confirmada.
insert into results
select 'confirmada_diagnostico', public.save_mechanic_job_lines_v1(
  'confirmada-diagnostico',
  'e28a0000-0000-4000-8000-000000000057',
  pg_temp.seen('e28a0000-0000-4000-8000-000000000057'),
  pg_temp.reopened('e28a0000-0000-4000-8000-000000000057'),
  '[]'::jsonb,
  jsonb_build_object('diagnosis', jsonb_build_object(
    'value', 'Revisada después de facturar',
    'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000057',
                                    'diagnosis'))),
  null, true);
select is(
  (select jsonb_build_object('action', result->'invoice'->>'action',
            'updated', result->'updated', 'inserted', result->'inserted',
            'diagnosis', result->'header'->>'diagnosis')
     from results where label = 'confirmada_diagnostico'),
  '{"action": "posted", "updated": 0, "inserted": 0, "diagnosis": "Revisada después de facturar"}'::jsonb,
  'el diagnóstico se guarda y la factura confirmada queda como estaba');
select is(
  (select to_jsonb(invoice) - 'updated_at' from public.sales_invoices invoice
    where id = 'e28a0000-0000-4000-8000-000000000084'),
  (select row from confirmed_before),
  'exactamente como estaba');
select is(
  (select sum(total_price) - max(j.discount_amount)
     from public.mechanic_job_items i
     join public.mechanic_jobs j on j.id = i.job_id
    where i.job_id = 'e28a0000-0000-4000-8000-000000000057'),
  (select total from public.sales_invoices
    where id = 'e28a0000-0000-4000-8000-000000000084'),
  'y el trabajo cobra lo mismo que su factura');

-- Tampoco por fuera del comando: la pestaña Tareas inserta líneas por su
-- cuenta, y un Guardar sin cambios llama a `sync_job_to_invoice`.
select throws_ok(
  $$insert into public.mechanic_job_items (
      tenant_id, job_id, product_name, item_type, location_key, quantity,
      unit_price
    ) values (
      'e28a0000-0000-4000-8000-000000000001',
      'e28a0000-0000-4000-8000-000000000057', 'Lavado', 'service', 'none', 1,
      8000)$$,
  '55000', null,
  'una línea agregada por fuera tampoco entra con la factura confirmada');
select throws_ok(
  $$update public.mechanic_jobs set discount_amount = 1000
     where id = 'e28a0000-0000-4000-8000-000000000057'$$,
  '55000', null,
  'ni un descuento escrito por fuera');
-- Una línea que llegó igual (sembrada saltándose las guardias) no se
-- proyecta a la factura confirmada por la sincronización pública.
set local session_replication_role = replica;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key, quantity,
  unit_price, total_price
) values (
  'e28a0000-0000-4000-8000-000000000069',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000057', 'Colada', 'service', 'none', 1,
  4000, 4000);
set local session_replication_role = origin;
select public.sync_job_to_invoice('e28a0000-0000-4000-8000-000000000057');
select is(
  (select to_jsonb(invoice) - 'updated_at' from public.sales_invoices invoice
    where id = 'e28a0000-0000-4000-8000-000000000084'),
  (select row from confirmed_before),
  'sync_job_to_invoice no reescribe una factura confirmada');
set local session_replication_role = replica;
delete from public.mechanic_job_items
 where id = 'e28a0000-0000-4000-8000-000000000069';
set local session_replication_role = origin;

-- Lo que cambia lo que se cobra va por la factura: su edición rehace stock y
-- asiento y lo proyecta al trabajo, que sigue cobrando lo mismo que ella.
update public.sales_invoices
   set items = jsonb_build_array(
         jsonb_build_object('description', 'Revisión', 'quantity', 1,
           'unit_price', 10000, 'total', 10000, 'item_type', 'service',
           'mechanic_job_item_id', 'e28a0000-0000-4000-8000-000000000067'),
         jsonb_build_object('description', 'Lavado', 'quantity', 1,
           'unit_price', 8000, 'total', 8000, 'item_type', 'service')),
       subtotal = 18000, net_amount = 18000, total = 18000, balance = 18000
 where id = 'e28a0000-0000-4000-8000-000000000084';
select is(
  (select jsonb_build_object('lines', count(*), 'total', sum(total_price))
     from public.mechanic_job_items
    where job_id = 'e28a0000-0000-4000-8000-000000000057'),
  (select jsonb_build_object('lines', 2, 'total', total)
     from public.sales_invoices
    where id = 'e28a0000-0000-4000-8000-000000000084'),
  'la corrección desde la factura llega al trabajo');

-- Una factura emitida con una nota de crédito contabilizada: su guardia
-- rechaza cambiar sus líneas, así que el comando la trata como confirmada y
-- rechaza antes, sin dejar el trabajo cambiado ni una factura en `failed`.
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  'e28a0000-0000-4000-8000-000000000085',
  'e28a0000-0000-4000-8000-000000000001', 'FV-LINEAS-CON-NOTA',
  'e28a0000-0000-4000-8000-000000000010', 'Cliente líneas', 'manual_sale',
  'issued', 10000, 10000, 0, 10000, 0, 10000, 'no_tax', '[]'::jsonb);
insert into public.mechanic_jobs (
  id, tenant_id, customer_id, bike_id, job_number, created_by, invoice_id
) values (
  'e28a0000-0000-4000-8000-000000000059',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000010',
  'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-CON-NOTA',
  'e28a0000-0000-4000-8000-000000000099',
  'e28a0000-0000-4000-8000-000000000085');
insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, location_key, quantity,
  unit_price, updated_at
) values (
  'e28a0000-0000-4000-8000-000000000068',
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000059', 'Revisión', 'service', 'none', 1,
  10000, now() - interval '1 day');
-- La nota se siembra sin su operación ni su asiento: sólo importa que exista
-- contabilizada, que es lo que mira la guardia de la factura.
set local session_replication_role = replica;
insert into public.sales_credit_notes (
  tenant_id, sales_invoice_id, credit_note_number, status, issue_date,
  reason_code, reason, net_amount, tax_amount, total_amount,
  idempotency_key, operation_id, journal_entry_id
) values (
  'e28a0000-0000-4000-8000-000000000001',
  'e28a0000-0000-4000-8000-000000000085', 'NC-LINEAS-1', 'posted', now(),
  'discount', 'Descuento posterior', 2000, 0, 2000, 'nc-lineas-1',
  gen_random_uuid(), gen_random_uuid());
set local session_replication_role = origin;
create temporary table credited_before as
select to_jsonb(invoice) - 'updated_at' as row
  from public.sales_invoices invoice
 where id = 'e28a0000-0000-4000-8000-000000000085';
select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint',
            'detail', (e->>'detail')::jsonb)
     from pg_temp.save_error('con-nota-nueva',
       'e28a0000-0000-4000-8000-000000000059',
       pg_temp.seen('e28a0000-0000-4000-8000-000000000059'),
       pg_temp.reopened('e28a0000-0000-4000-8000-000000000059')
         || jsonb_build_array(jsonb_build_object(
              'client_key', 'nueva-lavado', 'product_name', 'Lavado',
              'item_type', 'service', 'quantity', 1, 'unit_price', 8000)),
       '[]'::jsonb, null, null, true) e),
  '{"state": "55000", "hint": "invoice_posted", "detail": ["línea: Lavado"]}'::jsonb,
  'con una nota de crédito, una línea nueva se rechaza antes de escribir');
select is(pg_temp.lines('e28a0000-0000-4000-8000-000000000059'), 1,
  'y el trabajo no cambia');
select is(
  public.save_mechanic_job_lines_v1('con-nota-diagnostico',
    'e28a0000-0000-4000-8000-000000000059',
    pg_temp.seen('e28a0000-0000-4000-8000-000000000059'),
    pg_temp.reopened('e28a0000-0000-4000-8000-000000000059'),
    '[]'::jsonb,
    jsonb_build_object('diagnosis', jsonb_build_object(
      'value', 'Revisada con nota',
      'expected', pg_temp.seen_header('e28a0000-0000-4000-8000-000000000059',
                                      'diagnosis'))),
    null, true)->'invoice'->>'action',
  'posted', 'el diagnóstico sí, sin intentar la factura (no queda en failed)');
select is(
  (select to_jsonb(invoice) - 'updated_at' from public.sales_invoices invoice
    where id = 'e28a0000-0000-4000-8000-000000000085'),
  (select row from credited_before),
  'y la factura con nota queda como estaba');

-- Un servicio que todavía no se puede facturar: el guardado queda y el recibo
-- dice por qué no hay factura. La factura queda pendiente de sí misma, no de
-- otro Guardar: la repetición de la llave y la continuación la vuelven a
-- intentar.
insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, created_by)
values ('e28a0000-0000-4000-8000-000000000055',
        'e28a0000-0000-4000-8000-000000000001',
        'e28a0000-0000-4000-8000-000000000010', 'PG-LINEAS-SIN-BICI',
        'e28a0000-0000-4000-8000-000000000099');
create temporary table imposible_payload as
select jsonb_build_array(jsonb_build_object(
         'client_key', 'nueva-revision', 'product_name', 'Revisión general',
         'item_type', 'service', 'quantity', 1, 'unit_price', 10000)) as lines;
insert into results
select 'factura_imposible', public.save_mechanic_job_lines_v1('factura-imposible',
  'e28a0000-0000-4000-8000-000000000055', '[]'::jsonb,
  (select lines from imposible_payload), '[]'::jsonb, null, null, true);
select is(
  (select jsonb_build_object('action', result->'invoice'->>'action',
            'code', result->'invoice'->'error'->>'code')
     from results where label = 'factura_imposible'),
  '{"action": "failed", "code": "23514"}'::jsonb,
  'la factura que no se puede crear queda dicha en el recibo');
select is(
  (select count(*)::integer from public.mechanic_job_items
    where job_id = 'e28a0000-0000-4000-8000-000000000055'), 1,
  'y la línea sí se guardó');
select is(pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000055'), null,
  'sin factura');

-- La app se reinicia con la causa todavía ahí: la repetición y la
-- continuación lo intentan, siguen en `failed` y no escriben nada más.
insert into results
select 'imposible_repetida', public.save_mechanic_job_lines_v1('factura-imposible',
  'e28a0000-0000-4000-8000-000000000055', '[]'::jsonb,
  (select lines from imposible_payload), '[]'::jsonb, null, null, true);
insert into results
select 'imposible_continuada',
       public.continue_mechanic_job_invoice_v1('factura-imposible');
select is(
  (select jsonb_agg(jsonb_build_object(
            'replayed', result->'replayed',
            'action', result->'invoice'->>'action') order by label)
     from results where label in ('imposible_repetida', 'imposible_continuada')),
  '[{"replayed": false, "action": "failed"}, {"replayed": true, "action": "failed"}]'::jsonb,
  'la repetición y la continuación la intentan y siguen diciendo el fallo');
select is(
  (select count(*)::integer from public.mechanic_job_items
    where job_id = 'e28a0000-0000-4000-8000-000000000055'), 1,
  'sin repetir la línea');

-- Alguien clasifica el ingreso desde la tabla (la causa), y la bandeja,
-- después de un reinicio y sin otro Guardar, llama la continuación. Primero
-- la factura está tomada: eso no la marca como hecha ni como fallida.
select public.classify_mechanic_job_intake(
  'e28a0000-0000-4000-8000-000000000055', 'bike',
  'e28a0000-0000-4000-8000-000000000031');
create function public.test_invoice_lock_unavailable()
returns trigger language plpgsql as $$
begin
  raise exception 'lock de la factura no disponible' using errcode = '55P03';
end;
$$;
create trigger zz_test_invoice_lock_unavailable
  before insert on public.sales_invoices
  for each row execute function public.test_invoice_lock_unavailable();
select throws_ok(
  $$select public.continue_mechanic_job_invoice_v1('factura-imposible')$$,
  '55P03', 'La factura del trabajo está tomada por otra operación; se vuelve a intentar.',
  'con la factura tomada, la continuación sale como pasajera');
drop trigger zz_test_invoice_lock_unavailable on public.sales_invoices;
select is(
  public.get_mechanic_job_line_save_v1('factura-imposible')->'invoice'->>'action',
  'failed', 'y el recibo sigue esperando la factura');
insert into results
select 'imposible_resuelta',
       public.continue_mechanic_job_invoice_v1('factura-imposible');
select is(
  (select jsonb_build_object('replayed', result->'replayed',
            'action', result->'invoice'->>'action',
            'invoice', (result->'invoice'->>'invoice_id')::uuid)
     from results where label = 'imposible_resuelta'),
  jsonb_build_object('replayed', false, 'action', 'created',
    'invoice', pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000055')),
  'sin otro Guardar, la continuación crea la factura');
select is(
  (select count(*)::integer from public.sales_invoices
    where id = pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000055')
      and total = 10000), 1,
  'con su línea');
select is(
  public.get_mechanic_job_line_save_v1('factura-imposible')->'invoice',
  (select result->'invoice' from results where label = 'imposible_resuelta'),
  'y el recibo ya la nombra');
create temporary table invoices_after_continuation as
select pg_temp.invoices() as n;
insert into results
select 'imposible_otra_vez',
       public.continue_mechanic_job_invoice_v1('factura-imposible');
insert into results
select 'imposible_repetida_tras', public.save_mechanic_job_lines_v1('factura-imposible',
  'e28a0000-0000-4000-8000-000000000055', '[]'::jsonb,
  (select lines from imposible_payload), '[]'::jsonb, null, null, true);
select is(
  (select jsonb_agg(jsonb_build_object(
            'replayed', result->'replayed', 'invoice', result->'invoice')
            order by label)
     from results where label in ('imposible_otra_vez', 'imposible_repetida_tras')),
  (select jsonb_build_array(
            jsonb_build_object('replayed', true, 'invoice', result->'invoice'),
            jsonb_build_object('replayed', true, 'invoice', result->'invoice'))
     from results where label = 'imposible_resuelta'),
  'repetir la continuación o el guardado devuelve la misma factura');
select is(pg_temp.invoices(), (select n from invoices_after_continuation),
  'sin otra');
select throws_ok(
  $$select public.continue_mechanic_job_invoice_v1('no-existe')$$,
  'P0002', 'No hay un guardado del trabajo con esa llave en este taller.',
  'una llave sin guardado no continúa nada');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e28a0000-0000-4000-8000-000000000098', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e28a0000-0000-4000-8000-000000000098', true);
select throws_ok(
  $$select public.continue_mechanic_job_invoice_v1('factura-imposible')$$,
  'P0002', 'No hay un guardado del trabajo con esa llave en este taller.',
  'otro taller no ve ni continúa la factura de éste');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e28a0000-0000-4000-8000-000000000099', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'e28a0000-0000-4000-8000-000000000099', true);

-- Lo mismo por la repetición del guardado, que es lo que manda la bandeja
-- cuando la respuesta se perdió: con la causa resuelta, la hace una vez.
insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, created_by)
values ('e28a0000-0000-4000-8000-000000000058',
        'e28a0000-0000-4000-8000-000000000001',
        'e28a0000-0000-4000-8000-000000000010', 'PG-LINEAS-SIN-BICI-2',
        'e28a0000-0000-4000-8000-000000000099');
select is(
  public.save_mechanic_job_lines_v1('factura-imposible-2',
    'e28a0000-0000-4000-8000-000000000058', '[]'::jsonb,
    (select lines from imposible_payload), '[]'::jsonb, null, null, true)
    ->'invoice'->>'action',
  'failed', 'otro servicio sin clasificar queda con la factura pendiente');
select public.classify_mechanic_job_intake(
  'e28a0000-0000-4000-8000-000000000058', 'bike',
  'e28a0000-0000-4000-8000-000000000031');
insert into results
select 'imposible_2_repetida', public.save_mechanic_job_lines_v1('factura-imposible-2',
  'e28a0000-0000-4000-8000-000000000058', '[]'::jsonb,
  (select lines from imposible_payload), '[]'::jsonb, null, null, true);
select is(
  (select jsonb_build_object('replayed', result->'replayed',
            'action', result->'invoice'->>'action',
            'inserted', result->'inserted',
            'lines', pg_temp.lines('e28a0000-0000-4000-8000-000000000058'))
     from results where label = 'imposible_2_repetida'),
  '{"replayed": true, "action": "created", "inserted": 1, "lines": 1}'::jsonb,
  'la repetición de la llave la crea, sin repetir la línea');
select is(
  public.get_mechanic_job_line_save_v1('factura-imposible-2')->'invoice'->>'action',
  'created', 'y el recibo queda al día');

-- La factura se cae a mitad por algo pasajero (un lock que no se alcanza a
-- tomar): no queda nada, ni la línea ni el recibo, y la bandeja reenvía el
-- mismo guardado, que deja línea y factura una vez.
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by)
values ('e28a0000-0000-4000-8000-000000000056',
        'e28a0000-0000-4000-8000-000000000001',
        'e28a0000-0000-4000-8000-000000000010',
        'e28a0000-0000-4000-8000-000000000031', 'PG-LINEAS-FACTURA-CAIDA',
        'e28a0000-0000-4000-8000-000000000099');
create temporary table caida_payload as
select jsonb_build_array(jsonb_build_object(
         'client_key', 'nueva-purga', 'product_name', 'Purga de frenos',
         'item_type', 'service', 'quantity', 1, 'unit_price', 15000)) as lines;
create trigger zz_test_invoice_lock_unavailable
  before insert on public.sales_invoices
  for each row execute function public.test_invoice_lock_unavailable();
select is(
  (select jsonb_build_object('state', e->>'state', 'hint', e->>'hint')
     from pg_temp.save_error('factura-caida',
       'e28a0000-0000-4000-8000-000000000056', '[]'::jsonb,
       (select lines from caida_payload), '[]'::jsonb, null, null, true) e),
  '{"state": "55P03", "hint": "invoice_retry"}'::jsonb,
  'un error pasajero de la factura deshace el guardado y se reintenta');
drop trigger zz_test_invoice_lock_unavailable on public.sales_invoices;
select is(
  (select jsonb_build_object(
            'lines', pg_temp.lines('e28a0000-0000-4000-8000-000000000056'),
            'receipt', public.get_mechanic_job_line_save_v1('factura-caida'),
            'invoice', pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000056'))),
  '{"lines": 0, "receipt": null, "invoice": null}'::jsonb,
  'sin línea, sin recibo y sin factura a medias');
insert into results
select 'factura_reenviada', public.save_mechanic_job_lines_v1('factura-caida',
  'e28a0000-0000-4000-8000-000000000056', '[]'::jsonb,
  (select lines from caida_payload), '[]'::jsonb, null, null, true);
select is(
  (select jsonb_build_object('action', result->'invoice'->>'action',
            'inserted', result->'inserted')
     from results where label = 'factura_reenviada'),
  '{"action": "created", "inserted": 1}'::jsonb,
  'el reenvío deja la línea y crea la factura');
select is(
  (select count(*)::integer from public.sales_invoices
    where id = pg_temp.invoice_of('e28a0000-0000-4000-8000-000000000056')
      and total = 15000), 1,
  'una, con su línea');

-- ============================================================================
-- Lo que no se acepta
-- ============================================================================

select throws_ok(
  $$select public.save_mechanic_job_lines_v1('ajeno-1',
      'e28a0000-0000-4000-8000-000000000053', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb)$$,
  'P0002', 'Trabajo no encontrado o eliminado.',
  'el trabajo de otro taller no existe para este');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('id-ajeno-1',
      'e28a0000-0000-4000-8000-000000000051', '[]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'x', 'id', 'e28a0000-0000-4000-8000-000000000064',
        'product_name', 'Lubricación')), '[]'::jsonb)$$,
  '%is not among the lines the form loaded%',
  'una línea que el formulario no cargó no se reescribe por id');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('bici-ajena-1',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      jsonb_build_array(jsonb_build_object(
        'client_key', 'x',
        'job_bike_id', 'e28a0000-0000-4000-8000-000000000042',
        'product_name', 'Suelta')), '[]'::jsonb)$$,
  '%no está en este trabajo%',
  'ni se cuelga de la bici de otro trabajo');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('total-1',
      'e28a0000-0000-4000-8000-000000000051', '[]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'client_key', 'x', 'product_name', 'Algo', 'total_price', 1)),
      '[]'::jsonb)$$,
  '%only line fields%',
  'el total lo calcula la base, no llega del formulario');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('tareas-1',
      'e28a0000-0000-4000-8000-000000000051',
      pg_temp.seen('e28a0000-0000-4000-8000-000000000051'),
      jsonb_build_array(jsonb_build_object(
        'client_key', 'nueva-x', 'product_name', 'Cámara 29',
        'auto_task_description', 'Otra vez')), '[]'::jsonb)$$,
  '%only line fields%',
  'las tareas no llegan del formulario con la línea');
select throws_like(
  $$select public.save_mechanic_job_lines_v1('mitad-1',
      'e28a0000-0000-4000-8000-000000000051', '[]'::jsonb, null, '[]'::jsonb)$$,
  '%travel with the lines the form loaded%',
  'líneas y lo que vio el formulario viajan juntas');

select * from finish();
rollback;
