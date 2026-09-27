begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Notas por servicio con su historia (dueño, 2026-09-27): cada servicio de
-- una tarea tiene un hilo de notas; se ve la vigente, se continúa con una
-- nueva o se corrige la propia, y la línea de tiempo dice quién, cuándo y
-- desde dónde.

select has_table('public', 'smart_task_job_item_notes',
  'cada nota de servicio es una fila');
select ok(
  has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smart_task_job_item_notes', 'DELETE')
  and not has_table_privilege('anon', 'public.smart_task_job_item_notes', 'SELECT'),
  'las notas se leen, pero se escriben sólo por comando');
select ok(
  has_function_privilege('authenticated',
    'public.get_smart_task_service_timeline_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_smart_task_service_timeline_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.get_smart_task_service_notes_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_smart_task_service_notes_v1(uuid)', 'EXECUTE'),
  'la línea de tiempo y la nota vigente son de quien ve la tarea');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name, owner_email, timezone) values
  ('e2770000-0000-4000-8000-000000000001', 'Taller A',
   'p3-a@example.invalid', 'America/Santiago'),
  ('e2770000-0000-4000-8000-000000000002', 'Taller B',
   'p3-b@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2770000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'p3-manager@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2770000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'p3-vicente@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2770000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'p3-lucas@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  -- Ana: otra manager que escribe una nota; su cuenta se borra al final.
  ('e2770000-0000-4000-8000-000000000015', 'authenticated', 'authenticated',
   'p3-ana@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2770000-0000-4000-8000-000000000016', 'authenticated', 'authenticated',
   'p3-otro@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb, '{}'::jsonb, now(), now());

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
) values
  ('e2770000-0000-4000-8000-000000000020', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000011',
   'P3-000', 'Claudio', 'Catalán', 'Dueño', 'full_time', 'active', 0),
  ('e2770000-0000-4000-8000-000000000021', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000012',
   'P3-001', 'Vicente', 'Díaz', 'Mecánico', 'full_time', 'active', 0),
  ('e2770000-0000-4000-8000-000000000022', 'e2770000-0000-4000-8000-000000000001',
   null, 'P3-002', 'Braulio', 'Muñoz', 'Mecánico', 'full_time', 'active', 0),
  ('e2770000-0000-4000-8000-000000000023', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000013',
   'P3-003', 'Lucas', 'Pacheco', 'Mecánico', 'full_time', 'active', 0);

-- La cuenta del portal nace después de la ficha: el alta lo valida.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2770000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'p3-braulio@example.invalid', '', now(),
   jsonb_build_object(
     'account_type', 'worker_portal',
     'tenant_id', 'e2770000-0000-4000-8000-000000000001',
     'employee_id', 'e2770000-0000-4000-8000-000000000022',
     'role', 'worker'
   ), '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id) values
  ('e2770000-0000-4000-8000-000000000011',
   'e2770000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb,
   'e2770000-0000-4000-8000-000000000020'),
  ('e2770000-0000-4000-8000-000000000012',
   'e2770000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'e2770000-0000-4000-8000-000000000021'),
  ('e2770000-0000-4000-8000-000000000013',
   'e2770000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'e2770000-0000-4000-8000-000000000023'),
  ('e2770000-0000-4000-8000-000000000015',
   'e2770000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null),
  ('e2770000-0000-4000-8000-000000000016',
   'e2770000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, null);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000011', true);

insert into public.employee_portal_accounts (
  id, tenant_id, employee_id, auth_user_id, username, login_email, is_active, created_by
) values (
  'e2770000-0000-4000-8000-000000000031', 'e2770000-0000-4000-8000-000000000001',
  'e2770000-0000-4000-8000-000000000022', 'e2770000-0000-4000-8000-000000000014',
  'p3braulio', 'p3-braulio@example.invalid', true,
  'e2770000-0000-4000-8000-000000000011'
);

insert into public.customers (id, tenant_id, name) values
  ('e2770000-0000-4000-8000-000000000041',
   'e2770000-0000-4000-8000-000000000001', 'Cliente Taller');

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, arrival_date, status, priority,
  client_request, created_by
) values
  ('e2770000-0000-4000-8000-000000000061', 'e2770000-0000-4000-8000-000000000001',
   'P3-JOB-1', 'e2770000-0000-4000-8000-000000000041', now(), 'PENDIENTE',
   'NORMAL', 'Mantención', 'e2770000-0000-4000-8000-000000000011');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values
  ('e2770000-0000-4000-8000-000000000081', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000061', 'Purga de frenos', 'service', 1, 0),
  ('e2770000-0000-4000-8000-000000000082', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000061', 'Cambio de cadena', 'service', 1, 0),
  ('e2770000-0000-4000-8000-000000000083', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000061', 'Centrado de rueda', 'service', 1, 0),
  ('e2770000-0000-4000-8000-000000000084', 'e2770000-0000-4000-8000-000000000001',
   'e2770000-0000-4000-8000-000000000061', 'Ajuste de cambios', 'service', 1, 0);

create temp table p3_ctx(key text primary key, id uuid, at timestamptz, n int);
grant select, insert, update on p3_ctx to authenticated;

-- ============================================================================
-- El encargo trae la primera nota de cada servicio
-- ============================================================================

set local role authenticated;

insert into p3_ctx (key, id)
select 'vicente', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Hacer el trabajo',
  'assigned_employee_id', 'e2770000-0000-4000-8000-000000000021',
  'linked_job_id', 'e2770000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array(
    'e2770000-0000-4000-8000-000000000081',
    'e2770000-0000-4000-8000-000000000082'),
  'job_item_notes', jsonb_build_object(
    'e2770000-0000-4000-8000-000000000082', '  La cadena ya viene cambiada  ',
    'e2770000-0000-4000-8000-000000000081', '   ')
), 'p3-create-vicente')) #>> '{task,id}')::uuid;

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Nota de otro servicio',
      'linked_job_id', 'e2770000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000084'),
      'job_item_notes', jsonb_build_object(
        'e2770000-0000-4000-8000-000000000083', 'No es de esta tarea')
    ), 'p3-create-foreign-note')$$,
  '23503', null, 'una nota del encargo va sobre un servicio del encargo');
select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Nota larga',
      'linked_job_id', 'e2770000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000084'),
      'job_item_notes', jsonb_build_object(
        'e2770000-0000-4000-8000-000000000084', repeat('x', 2001))
    ), 'p3-create-long-note')$$,
  '22001', null, 'y tiene un largo razonable');

insert into p3_ctx (key, id)
select 'braulio', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Centrar la rueda',
  'assigned_employee_id', 'e2770000-0000-4000-8000-000000000022',
  'linked_job_id', 'e2770000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000083'),
  'job_item_notes', jsonb_build_object(
    'e2770000-0000-4000-8000-000000000083', 'Salto lateral en la trasera')
), 'p3-create-braulio')) #>> '{task,id}')::uuid;

insert into p3_ctx (key, id)
select 'note', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Idea para la vitrina', 'task_kind', 'note'
), 'p3-create-note')) #>> '{task,id}')::uuid;

reset role;

select results_eq(
  $$select job_item_id, body, created_by
      from public.smart_task_job_item_notes
     where task_id = (select id from p3_ctx where key = 'vicente')$$,
  $$values ('e2770000-0000-4000-8000-000000000082'::uuid,
            'La cadena ya viene cambiada'::text,
            'e2770000-0000-4000-8000-000000000011'::uuid)$$,
  'la nota del encargo queda sobre su servicio, recortada; la vacía no existe');
select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from p3_ctx where key = 'vicente')
      and event_type = 'job_item_note_added'
      and (payload ->> 'at_create')::boolean),
  1, 'el ledger guarda la nota del encargo');
select is(
  (select count(*)::int from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
      and type = 'smart_task_service_note'),
  0, 'la nota del encargo no avisa aparte: llega con la asignación');

-- ============================================================================
-- Vicente continúa el hilo; nadie escribe por la puerta de atrás
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'note', 'Ojo: el cassette está gastado'),
      'p3-vicente-continue')$$,
  'el responsable continúa el hilo con una nota nueva');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'note', '   '),
      'p3-vicente-empty')$$,
  '22023', null, 'una nota vacía no es una nota');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000083',
                         'note', 'Ajena'),
      'p3-vicente-foreign-item')$$,
  '23503', null, 'un servicio que no es de la tarea no se anota en ella');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body = 'La cadena ya viene cambiada'),
        'note', 'La cadena NO viene cambiada'),
      'p3-vicente-edit-foreign')$$,
  '42501', null, 'nadie corrige la nota de otro');
select throws_ok(
  $$insert into public.smart_task_job_item_notes (tenant_id, task_id, job_item_id, body)
    values ('e2770000-0000-4000-8000-000000000001',
            (select id from p3_ctx where key = 'vicente'),
            'e2770000-0000-4000-8000-000000000082', 'Directo')$$,
  '42501', null, 'no se escribe una nota fuera del comando');
select results_eq(
  $$select body, note_count
      from public.get_smart_task_service_notes_v1(
        (select id from p3_ctx where key = 'vicente'))$$,
  $$values ('Ojo: el cassette está gastado'::text, 2)$$,
  'la vigente es la última, y el hilo cuenta dos');

reset role;

select is(
  (select recipient_user_id from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
      and type = 'smart_task_service_note'),
  'e2770000-0000-4000-8000-000000000011'::uuid,
  'la nota nueva le avisa a quien encargó');
select ok(
  (select body like '%«Cambio de cadena»%cassette%' from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
      and type = 'smart_task_service_note'),
  'el aviso dice sobre qué servicio y qué dice');

update public.smart_task_job_item_notes
   set body = 'Reescrita a mano'
 where body = 'Ojo: el cassette está gastado';
select is(
  (select count(*)::int from public.smart_task_job_item_notes
    where body = 'Ojo: el cassette está gastado'),
  1, 'un update directo no cambia el texto');

-- La manager marca el aviso leído antes de la corrección.
update public.erp_notifications set read_at = now()
 where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
   and type = 'smart_task_service_note';

-- ============================================================================
-- Vicente corrige lo suyo
-- ============================================================================

set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body = 'Ojo: el cassette está gastado'),
        'note', 'Ojo: el cassette y los platos están gastados'),
      'p3-vicente-edit')$$,
  'quien escribió una nota la corrige');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body like 'Ojo: el cassette y%'),
        'note', 'Ojo: el cassette y los platos están gastados'),
      'p3-vicente-edit-again')$$,
  'corregir con el mismo texto no falla');
reset role;

select results_eq(
  $$select body, edited_by is not null, edited_at is not null
      from public.smart_task_job_item_notes
     where task_id = (select id from p3_ctx where key = 'vicente')
       and created_by = 'e2770000-0000-4000-8000-000000000012'$$,
  $$values ('Ojo: el cassette y los platos están gastados'::text, true, true)$$,
  'la nota queda corregida, con quién y cuándo');
select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from p3_ctx where key = 'vicente')
      and event_type = 'job_item_note_edited'
      and payload ->> 'previous_note' = 'Ojo: el cassette está gastado'),
  1, 'el ledger guarda lo que decía antes, una sola vez');
select ok(
  (select read_at is not null and body like '%platos%'
     from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
      and type = 'smart_task_service_note'),
  'corregir actualiza el aviso sin volver a encenderlo');

-- ============================================================================
-- Re-vincular no pierde el hilo
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'set_job_items',
      jsonb_build_object(
        'job_id', 'e2770000-0000-4000-8000-000000000061',
        'job_item_ids', jsonb_build_array(
          'e2770000-0000-4000-8000-000000000081',
          'e2770000-0000-4000-8000-000000000082')),
      'p3-manager-relink')$$,
  'la manager re-vincula los mismos servicios');
select results_eq(
  $$select body, note_count
      from public.get_smart_task_service_notes_v1(
        (select id from p3_ctx where key = 'vicente'))$$,
  $$values ('Ojo: el cassette y los platos están gastados'::text, 2)$$,
  'el hilo sigue entero después de re-vincular');

-- Marca el servicio hecho para verlo en la línea de tiempo.
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'done', true),
      'p3-manager-done')$$,
  'la manager marca el servicio hecho');

-- ============================================================================
-- La línea de tiempo del servicio
-- ============================================================================

select results_eq(
  $$select kind, actor_name, from_portal, note, previous_note, at_create, is_current
      from public.get_smart_task_service_timeline_v1(
        (select id from p3_ctx where key = 'vicente'),
        'e2770000-0000-4000-8000-000000000082')$$,
  $$values
      ('done'::text, 'Claudio Catalán'::text, false, null::text, null::text, false, false),
      ('note_edited', 'Vicente Díaz', false,
       'Ojo: el cassette y los platos están gastados', 'Ojo: el cassette está gastado',
       false, true),
      ('note_continued', 'Vicente Díaz', false, 'Ojo: el cassette está gastado', null,
       false, false),
      ('note_written', 'Claudio Catalán', false, 'La cadena ya viene cambiada', null,
       true, false),
      ('assigned', 'Claudio Catalán', false, null, null, false, false)$$,
  'la línea de tiempo cuenta la historia del servicio, lo último primero');
select is(
  (select count(*)::int from public.get_smart_task_service_timeline_v1(
     (select id from p3_ctx where key = 'vicente'),
     'e2770000-0000-4000-8000-000000000081')),
  1, 'el otro servicio sólo tiene su encargo');
reset role;

-- Otro taller no ve la historia.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000016', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000016', true);
set local role authenticated;
select throws_ok(
  $$select * from public.get_smart_task_service_timeline_v1(
      (select id from p3_ctx where key = 'vicente'),
      'e2770000-0000-4000-8000-000000000082')$$,
  '42501', null, 'otro taller no ve la línea de tiempo');
select is(
  (select count(*)::int from public.smart_task_job_item_notes),
  0, 'ni las notas');
reset role;

-- ============================================================================
-- Lucas no trabaja la tarea; Vicente retira lo suyo
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000013', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000081',
                         'note', 'Opino'),
      'p3-lucas-add')$$,
  '42501', null, 'quien no trabaja la tarea no le escribe notas');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000012', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'withdraw_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body like 'Ojo: el cassette y%')),
      'p3-vicente-withdraw')$$,
  'quien escribió una nota la retira');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body like 'Ojo: el cassette y%'),
        'note', 'Revivida'),
      'p3-vicente-edit-withdrawn')$$,
  '23514', null, 'una nota retirada no se corrige');
select results_eq(
  $$select body, note_count
      from public.get_smart_task_service_notes_v1(
        (select id from p3_ctx where key = 'vicente'))$$,
  $$values ('La cadena ya viene cambiada'::text, 1)$$,
  'retirada la última, vuelve a regir la anterior');
select results_eq(
  $$select kind, previous_note
      from public.get_smart_task_service_timeline_v1(
        (select id from p3_ctx where key = 'vicente'),
        'e2770000-0000-4000-8000-000000000082')
     limit 1$$,
  $$values ('note_withdrawn'::text, 'Ojo: el cassette y los platos están gastados'::text)$$,
  'y la línea de tiempo dice qué se retiró');
select is(
  (select kind from public.get_smart_task_service_timeline_v1(
     (select id from p3_ctx where key = 'vicente'),
     'e2770000-0000-4000-8000-000000000082')
    where is_current),
  'note_written', 'la vigente se marca donde se escribió');
reset role;

select is(
  (select count(*)::int from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'vicente')::text
      and type = 'smart_task_service_note'),
  0, 'retirar la nota retira su aviso');

-- ============================================================================
-- Se borra la cuenta de quien escribió: la nota queda, sin nombre
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000015', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000015', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000081',
                         'note', 'Purgar con DOT 4'),
      'p3-ana-add')$$,
  'una manager escribe en la tarea de otro');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body = 'Purgar con DOT 4'),
        'note', 'Purgar con DOT 5.1'),
      'p3-ana-edit')$$,
  'y la corrige');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

delete from public.user_profiles
 where user_id = 'e2770000-0000-4000-8000-000000000015';
select lives_ok(
  $$delete from auth.users where id = 'e2770000-0000-4000-8000-000000000015'$$,
  'la cuenta de quien escribió se puede borrar');
select results_eq(
  $$select body, created_by, edited_by, edited_at is not null
      from public.smart_task_job_item_notes
     where job_item_id = 'e2770000-0000-4000-8000-000000000081'$$,
  $$values ('Purgar con DOT 5.1'::text, null::uuid, null::uuid, true)$$,
  'la nota sigue, corregida, sólo sin nombre');

-- ============================================================================
-- El portal: la vigente, continuar, corregir y la línea de tiempo
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000014', true);
set local role authenticated;

select results_eq(
  $$select item #>> '{note,body}', item #>> '{note,author_name}',
           (item #>> '{note,mine}')::boolean, (item ->> 'note_count')::int
      from public.get_my_worker_tasks_v1() task,
           jsonb_array_elements(task.job_items) item$$,
  $$values ('Salto lateral en la trasera'::text, 'Claudio Catalán'::text, false, 1)$$,
  'el portal ve la nota vigente de su servicio, con autor');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000083',
                         'note', 'Tiene dos rayos cortados'),
      'p3-braulio-continue')$$,
  'el portal continúa el hilo');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'edit_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body = 'Tiene dos rayos cortados'),
        'note', 'Tiene tres rayos cortados'),
      'p3-braulio-edit')$$,
  'y corrige lo suyo');
select results_eq(
  $$select item #>> '{note,body}', item #>> '{note,author_name}',
           (item #>> '{note,mine}')::boolean, (item ->> 'note_count')::int,
           item #> '{note,edited_at}' is not null
      from public.get_my_worker_tasks_v1() task,
           jsonb_array_elements(task.job_items) item$$,
  $$values ('Tiene tres rayos cortados'::text, 'Braulio Muñoz'::text, true, 2, true)$$,
  'el portal ve su nota como vigente, suya y corregida');
select results_eq(
  $$select kind, actor_name, from_portal
      from public.get_smart_task_service_timeline_v1(
        (select id from p3_ctx where key = 'braulio'),
        'e2770000-0000-4000-8000-000000000083')
     limit 2$$,
  $$values ('note_edited'::text, 'Braulio Muñoz'::text, true),
           ('note_continued', 'Braulio Muñoz', true)$$,
  'la línea de tiempo dice que fue desde el portal');
select throws_ok(
  $$select * from public.get_smart_task_service_timeline_v1(
      (select id from p3_ctx where key = 'vicente'),
      'e2770000-0000-4000-8000-000000000082')$$,
  '42501', null, 'el portal no ve la historia de tareas ajenas');
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'note', 'Ajena'), 'p3-braulio-foreign')$$,
  '42501', null, 'ni escribe en ellas');
reset role;

select is(
  (select recipient_user_id from public.erp_notifications
    where data ->> 'task_id' = (select id from p3_ctx where key = 'braulio')::text
      and type = 'smart_task_service_note'),
  'e2770000-0000-4000-8000-000000000011'::uuid,
  'la nota del portal le avisa a quien encargó');

-- Quien encargó escribe también: cada nota tiene su aviso, y el de Braulio
-- no pisa el que ella tiene sin leer.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000083',
                         'note', 'Cambia los rayos por DT Swiss'),
      'p3-manager-note-braulio')$$,
  'quien encargó continúa el hilo del portal');
reset role;
select results_eq(
  $$select recipient_user_id, read_at is null, entity_type
      from public.erp_notifications
     where data ->> 'task_id' = (select id from p3_ctx where key = 'braulio')::text
       and type = 'smart_task_service_note'
     order by occurred_at, recipient_user_id$$,
  $$values
      ('e2770000-0000-4000-8000-000000000011'::uuid, true,
       'smart_task_service_note'::text),
      ('e2770000-0000-4000-8000-000000000014'::uuid, true,
       'smart_task_service_note'::text)$$,
  'dos notas, dos avisos: ninguno pisa al otro');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000014', true);

-- El taller borra el servicio: se puede retirar lo escrito, no agregar.
delete from public.mechanic_job_items
 where id = 'e2770000-0000-4000-8000-000000000083';

set local role authenticated;
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000083',
                         'note', 'Sigue sin rayos'),
      'p3-braulio-add-removed')$$,
  '23514', null, 'un servicio que el taller sacó ya no recibe notas');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'withdraw_job_item_note',
      jsonb_build_object(
        'note_id', (select id from public.smart_task_job_item_notes
                     where body = 'Tiene tres rayos cortados')),
      'p3-braulio-withdraw-removed')$$,
  'pero lo escrito se puede retirar');
select is(
  (select kind from public.get_smart_task_service_timeline_v1(
     (select id from p3_ctx where key = 'braulio'),
     'e2770000-0000-4000-8000-000000000083')
    where kind = 'service_removed'),
  'service_removed', 'la línea de tiempo muestra que el taller lo sacó');
reset role;

-- Braulio cierra su tarea y el taller le desactiva el portal: su sesión
-- vieja ya no lee notas ni historial.
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p3_ctx where key = 'braulio'), null, 'complete',
      '{}'::jsonb, 'p3-braulio-complete')$$,
  'Braulio completa su tarea');
reset role;
update public.employee_portal_accounts
   set is_active = false
 where id = 'e2770000-0000-4000-8000-000000000031';
set local role authenticated;
select throws_ok(
  $$select * from public.get_smart_task_service_timeline_v1(
      (select id from p3_ctx where key = 'braulio'),
      'e2770000-0000-4000-8000-000000000083')$$,
  '42501', null, 'un portal desactivado no lee la historia de su tarea cerrada');
select is(
  (select count(*)::int from public.smart_task_job_item_notes),
  0, 'ni sus notas');
reset role;

-- ============================================================================
-- Re-vincular no borra de la historia lo que cambió el taller
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into p3_ctx (key, id)
select 'lucas', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Ajustar los cambios',
  'assigned_employee_id', 'e2770000-0000-4000-8000-000000000023',
  'linked_job_id', 'e2770000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000084')
), 'p3-create-lucas')) #>> '{task,id}')::uuid;
reset role;

update public.mechanic_job_items
   set description = 'Ajuste de cambios y cable nuevo'
 where id = 'e2770000-0000-4000-8000-000000000084';
update p3_ctx set at = (select context_changed_at from public.smart_task_job_items
  where task_id = (select id from p3_ctx where key = 'lucas'))
 where key = 'lucas';

set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'lucas'), null, 'set_job_items',
      jsonb_build_object(
        'job_id', 'e2770000-0000-4000-8000-000000000061',
        'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000084')),
      'p3-manager-relink-lucas')$$,
  'la manager re-vincula el servicio que el taller cambió');
select is(
  (select context_changed_at from public.smart_task_job_items
    where task_id = (select id from p3_ctx where key = 'lucas')),
  null, 'el vínculo nuevo nace sin la marca');
select results_eq(
  $$select occurred_at, kind
      from public.get_smart_task_service_timeline_v1(
        (select id from p3_ctx where key = 'lucas'),
        'e2770000-0000-4000-8000-000000000084')
     where kind = 'service_changed'$$,
  $$select at, 'service_changed'::text from p3_ctx where key = 'lucas'$$,
  'pero la historia conserva el cambio del taller, con su hora');

-- Desvincular del todo y volver a vincular tampoco lo pierde.
reset role;
update public.mechanic_job_items
   set description = 'Ajuste de cambios, cable y funda nuevos'
 where id = 'e2770000-0000-4000-8000-000000000084';
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'lucas'), null, 'set_job_items',
      jsonb_build_object('job_id', null), 'p3-manager-unlink-lucas')$$,
  'la manager desvincula el trabajo');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'lucas'), null, 'set_job_items',
      jsonb_build_object(
        'job_id', 'e2770000-0000-4000-8000-000000000061',
        'job_item_ids', jsonb_build_array('e2770000-0000-4000-8000-000000000084')),
      'p3-manager-relink-lucas-again')$$,
  'y lo vuelve a vincular');
select is(
  (select count(*)::int from public.get_smart_task_service_timeline_v1(
     (select id from p3_ctx where key = 'lucas'),
     'e2770000-0000-4000-8000-000000000084')
    where kind = 'service_changed'),
  2, 'la historia tiene los dos cambios del taller');
reset role;

-- ============================================================================
-- Tareas cerradas y notas sueltas
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000012', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'complete',
      '{}'::jsonb, 'p3-vicente-complete')$$,
  'Vicente completa la tarea');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'vicente'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'note', 'Tarde'),
      'p3-vicente-closed')$$,
  '23514', null, 'una tarea cerrada no recibe notas');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2770000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2770000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p3_ctx where key = 'note'), null, 'add_job_item_note',
      jsonb_build_object('job_item_id', 'e2770000-0000-4000-8000-000000000082',
                         'note', 'En una nota'),
      'p3-note-kind')$$,
  '23514', null, 'una nota suelta no tiene servicios que anotar');
reset role;

select * from finish();
rollback;
