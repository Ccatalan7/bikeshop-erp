begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Fase 2 de las tareas del taller (dueño, 2026-09-26): quien hace el trabajo
-- marca cada servicio como hecho o pendiente, con quién y cuándo, y deja una
-- nota para el siguiente turno. Todo por comando, en el ERP y en el portal.

select has_column('public', 'smart_task_job_items', 'done_at',
  'el vínculo tarea↔servicio guarda cuándo quedó hecho');
select has_column('public', 'smart_task_job_items', 'done_by',
  'y quién lo marcó');
select has_column('public', 'smart_tasks', 'handoff_note',
  'la tarea guarda una nota para el siguiente turno');
select ok(
  not has_table_privilege('authenticated', 'public.smart_task_job_items', 'UPDATE'),
  'marcar un servicio sólo se hace por comando');
select ok(
  has_function_privilege('authenticated', 'public.get_my_worker_tasks_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_my_worker_tasks_v1()', 'EXECUTE'),
  'la proyección del portal conserva sus permisos al cambiar de forma');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name, owner_email, timezone) values
  ('e2760000-0000-4000-8000-000000000001', 'Taller A',
   'p2-a@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2760000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'p2-manager@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2760000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'p2-vicente@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e2760000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'p2-lucas@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  -- Ana: otra manager que sólo marca y escribe; su cuenta se borra al final.
  ('e2760000-0000-4000-8000-000000000015', 'authenticated', 'authenticated',
   'p2-ana@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now());

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
) values
  ('e2760000-0000-4000-8000-000000000021', 'e2760000-0000-4000-8000-000000000001',
   'e2760000-0000-4000-8000-000000000012',
   'P2-001', 'Vicente', 'Díaz', 'Mecánico', 'full_time', 'active', 0),
  ('e2760000-0000-4000-8000-000000000022', 'e2760000-0000-4000-8000-000000000001',
   null, 'P2-002', 'Braulio', 'Muñoz', 'Mecánico', 'full_time', 'active', 0),
  ('e2760000-0000-4000-8000-000000000023', 'e2760000-0000-4000-8000-000000000001',
   'e2760000-0000-4000-8000-000000000013',
   'P2-003', 'Lucas', 'Pacheco', 'Mecánico', 'full_time', 'active', 0);

-- La cuenta del portal nace después de la ficha: el alta lo valida.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2760000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'p2-braulio@example.invalid', '', now(),
   jsonb_build_object(
     'account_type', 'worker_portal',
     'tenant_id', 'e2760000-0000-4000-8000-000000000001',
     'employee_id', 'e2760000-0000-4000-8000-000000000022',
     'role', 'worker'
   ), '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id) values
  ('e2760000-0000-4000-8000-000000000011',
   'e2760000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null),
  ('e2760000-0000-4000-8000-000000000012',
   'e2760000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'e2760000-0000-4000-8000-000000000021'),
  ('e2760000-0000-4000-8000-000000000013',
   'e2760000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'e2760000-0000-4000-8000-000000000023'),
  ('e2760000-0000-4000-8000-000000000015',
   'e2760000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000011', true);

insert into public.employee_portal_accounts (
  id, tenant_id, employee_id, auth_user_id, username, login_email, is_active, created_by
) values (
  'e2760000-0000-4000-8000-000000000031', 'e2760000-0000-4000-8000-000000000001',
  'e2760000-0000-4000-8000-000000000022', 'e2760000-0000-4000-8000-000000000014',
  'p2braulio', 'p2-braulio@example.invalid', true,
  'e2760000-0000-4000-8000-000000000011'
);

insert into public.customers (id, tenant_id, name) values
  ('e2760000-0000-4000-8000-000000000041',
   'e2760000-0000-4000-8000-000000000001', 'Cliente Taller');

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, arrival_date, status, priority,
  client_request, created_by
) values
  ('e2760000-0000-4000-8000-000000000061', 'e2760000-0000-4000-8000-000000000001',
   'P2-JOB-1', 'e2760000-0000-4000-8000-000000000041', now(), 'PENDIENTE',
   'NORMAL', 'Mantención', 'e2760000-0000-4000-8000-000000000011');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values
  ('e2760000-0000-4000-8000-000000000081', 'e2760000-0000-4000-8000-000000000001',
   'e2760000-0000-4000-8000-000000000061', 'Purga de frenos', 'service', 1, 0),
  ('e2760000-0000-4000-8000-000000000082', 'e2760000-0000-4000-8000-000000000001',
   'e2760000-0000-4000-8000-000000000061', 'Cambio de cadena', 'service', 1, 0),
  ('e2760000-0000-4000-8000-000000000083', 'e2760000-0000-4000-8000-000000000001',
   'e2760000-0000-4000-8000-000000000061', 'Centrado de rueda', 'service', 1, 0);

create temp table p2_ctx(key text primary key, id uuid, at timestamptz, n int);
grant select, insert, update on p2_ctx to authenticated;

-- ============================================================================
-- La manager encarga
-- ============================================================================

set local role authenticated;

insert into p2_ctx (key, id)
select 'vicente', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Hacer el trabajo',
  'assigned_employee_id', 'e2760000-0000-4000-8000-000000000021',
  'linked_job_id', 'e2760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array(
    'e2760000-0000-4000-8000-000000000081',
    'e2760000-0000-4000-8000-000000000082')
), 'p2-create-vicente')) #>> '{task,id}')::uuid;

insert into p2_ctx (key, id)
select 'braulio', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Centrar la rueda',
  'assigned_employee_id', 'e2760000-0000-4000-8000-000000000022',
  'linked_job_id', 'e2760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('e2760000-0000-4000-8000-000000000083')
), 'p2-create-braulio')) #>> '{task,id}')::uuid;

insert into p2_ctx (key, id)
select 'note', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Idea para la vitrina', 'task_kind', 'note'
), 'p2-create-note')) #>> '{task,id}')::uuid;

reset role;

select is(
  (select count(*)::int from public.smart_task_job_items
    where task_id = (select id from p2_ctx where key = 'vicente') and done_at is null),
  2, 'los servicios de una tarea nacen pendientes');

update p2_ctx set n = (select version from public.smart_tasks
  where id = (select id from p2_ctx where key = 'vicente'))
 where key = 'vicente';

-- ============================================================================
-- Vicente marca sus servicios
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000081',
                         'done', true),
      'p2-vicente-done-1')$$,
  'el responsable marca un servicio hecho');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000081',
                         'done', true),
      'p2-vicente-done-1-again')$$,
  'marcarlo otra vez no falla');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000083',
                         'done', true),
      'p2-vicente-foreign-item')$$,
  '23503', null, 'un servicio que no es de la tarea no se marca en ella');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('done', true), 'p2-vicente-no-item')$$,
  '22023', null, 'marcar exige decir qué servicio');

reset role;

select results_eq(
  $$select done_at is not null, done_by
      from public.smart_task_job_items
     where task_id = (select id from p2_ctx where key = 'vicente')
       and job_item_id = 'e2760000-0000-4000-8000-000000000081'$$,
  $$values (true, 'e2760000-0000-4000-8000-000000000012'::uuid)$$,
  'el servicio queda hecho, con quién lo marcó');
select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from p2_ctx where key = 'vicente')
      and event_type = 'job_item_done'
      and payload ->> 'item_name' = 'Purga de frenos'),
  1, 'el ledger registra una sola vez, con el nombre del servicio');
select is(
  (select version from public.smart_tasks
    where id = (select id from p2_ctx where key = 'vicente')),
  (select n + 1 from p2_ctx where key = 'vicente'),
  'marcar sube la versión una vez: repetir no cuenta');

set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000081',
                         'done', false),
      'p2-vicente-undo-1')$$,
  'se puede volver a pendiente');
reset role;

select results_eq(
  $$select done_at, done_by
      from public.smart_task_job_items
     where task_id = (select id from p2_ctx where key = 'vicente')
       and job_item_id = 'e2760000-0000-4000-8000-000000000081'$$,
  $$values (null::timestamptz, null::uuid)$$,
  'pendiente otra vez borra cuándo y quién');
select ok(
  exists (select 1 from public.smart_task_events
    where task_id = (select id from p2_ctx where key = 'vicente')
      and event_type = 'job_item_reopened'),
  'y el ledger lo cuenta');

set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000081',
                         'done', true),
      'p2-vicente-done-1-final')$$,
  'y hecho de nuevo');
reset role;

update p2_ctx set at = (select done_at from public.smart_task_job_items
  where task_id = (select id from p2_ctx where key = 'vicente')
    and job_item_id = 'e2760000-0000-4000-8000-000000000081')
 where key = 'vicente';

-- Otro mecánico del taller no marca el trabajo de Vicente.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000082',
                         'done', true),
      'p2-lucas-mark')$$,
  '42501', null, 'quien no es responsable, ni lo encargó, ni es manager, no marca');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Me metí yo'), 'p2-lucas-note')$$,
  '42501', null, 'ni deja la nota del turno');
reset role;

-- ============================================================================
-- La nota para el siguiente turno
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', '  Falta la piola trasera; llega mañana.  '),
      'p2-vicente-note')$$,
  'el responsable deja dónde quedó');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', repeat('x', 2001)), 'p2-vicente-note-long')$$,
  '22001', null, 'una nota de turno no es un documento');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'note'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Hola'), 'p2-note-on-note')$$,
  '23514', null, 'una nota no tiene turnos');

reset role;

select results_eq(
  $$select handoff_note, handoff_note_by, handoff_note_at is not null
      from public.smart_tasks where id = (select id from p2_ctx where key = 'vicente')$$,
  $$values ('Falta la piola trasera; llega mañana.'::text,
            'e2760000-0000-4000-8000-000000000012'::uuid, true)$$,
  'la nota queda recortada, con autor y hora del servidor');
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_id = (select id from p2_ctx where key = 'vicente')
      and type = 'smart_task_handoff_note'),
  'e2760000-0000-4000-8000-000000000011'::uuid,
  'la nota le avisa a quien encargó la tarea');
select ok(
  (select body from public.erp_notifications
    where entity_id = (select id from p2_ctx where key = 'vicente')
      and type = 'smart_task_handoff_note') like 'Vicente Díaz sobre Hacer el trabajo: Falta la piola%',
  'el aviso dice quién, sobre qué y qué');

-- La ruta directa no escribe la nota: sólo su comando.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000011', true);
set local role authenticated;
update public.smart_tasks
   set handoff_note = 'Escrita por la puerta de atrás',
       handoff_note_by = 'e2760000-0000-4000-8000-000000000011'
 where id = (select id from p2_ctx where key = 'vicente');
reset role;
select is(
  (select handoff_note from public.smart_tasks
    where id = (select id from p2_ctx where key = 'vicente')),
  'Falta la piola trasera; llega mañana.',
  'una escritura directa no reemplaza la nota del turno');

-- Tampoco se marca un servicio por la puerta de atrás (ni como dueño de la base).
update public.smart_task_job_items
   set done_at = now(), done_by = 'e2760000-0000-4000-8000-000000000011'
 where task_id = (select id from p2_ctx where key = 'vicente')
   and job_item_id = 'e2760000-0000-4000-8000-000000000082';
select is(
  (select done_at from public.smart_task_job_items
    where task_id = (select id from p2_ctx where key = 'vicente')
      and job_item_id = 'e2760000-0000-4000-8000-000000000082'),
  null::timestamptz,
  'marcar sin el comando no atribuye trabajo a nadie');

-- La manager borra la nota (vacía = sin nota).
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', '   '), 'p2-manager-clear-note')$$,
  'quien encargó puede borrar la nota');
reset role;
select results_eq(
  $$select handoff_note, handoff_note_at, handoff_note_by
      from public.smart_tasks where id = (select id from p2_ctx where key = 'vicente')$$,
  $$values (null::text, null::timestamptz, null::uuid)$$,
  'sin nota no queda ni autor ni hora');
select is(
  (select count(*)::int from public.erp_notifications
    where entity_id = (select id from p2_ctx where key = 'vicente')
      and type = 'smart_task_handoff_note'),
  0, 'borrar la nota retira su aviso: no queda un texto que ya no está');
select ok(
  exists (select 1 from public.smart_task_events
    where task_id = (select id from p2_ctx where key = 'vicente')
      and event_type = 'handoff_note_cleared')
  and exists (select 1 from public.smart_task_events
    where task_id = (select id from p2_ctx where key = 'vicente')
      and event_type = 'handoff_note_set'
      and payload ->> 'note' = 'Falta la piola trasera; llega mañana.'),
  'el ledger guarda la nota anterior y que se borró');

-- ============================================================================
-- Re-vincular conserva lo hecho
-- ============================================================================

set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_items',
      jsonb_build_object(
        'job_id', 'e2760000-0000-4000-8000-000000000061',
        'job_item_ids', jsonb_build_array(
          'e2760000-0000-4000-8000-000000000081',
          'e2760000-0000-4000-8000-000000000082')),
      'p2-manager-relink')$$,
  'la manager re-vincula los mismos servicios');
reset role;

select results_eq(
  $$select job_item_id, done_at, done_by
      from public.smart_task_job_items
     where task_id = (select id from p2_ctx where key = 'vicente')
     order by job_item_id$$,
  $$values
      ('e2760000-0000-4000-8000-000000000081'::uuid,
       (select at from p2_ctx where key = 'vicente'),
       'e2760000-0000-4000-8000-000000000012'::uuid),
      ('e2760000-0000-4000-8000-000000000082'::uuid, null::timestamptz, null::uuid)$$,
  'lo hecho sigue hecho, con su hora y su autor; lo pendiente, pendiente');

-- ============================================================================
-- Se borra la cuenta de quien marcó y escribió: queda lo hecho, sin nombre
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000015', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000015', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000082',
                         'done', true),
      'p2-ana-mark')$$,
  'una manager marca un servicio de la tarea de otro');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Cadena cambiada; falta probarla en ruta'),
      'p2-ana-note')$$,
  'y le deja la nota del turno');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

delete from public.user_profiles
 where user_id = 'e2760000-0000-4000-8000-000000000015';
select lives_ok(
  $$delete from auth.users where id = 'e2760000-0000-4000-8000-000000000015'$$,
  'la cuenta de quien marcó y escribió se puede borrar');
select results_eq(
  $$select link.done_at is not null, link.done_by, task.handoff_note, task.handoff_note_by
      from public.smart_task_job_items link
      join public.smart_tasks task on task.id = link.task_id
     where link.task_id = (select id from p2_ctx where key = 'vicente')
       and link.job_item_id = 'e2760000-0000-4000-8000-000000000082'$$,
  $$values (true, null::uuid, 'Cadena cambiada; falta probarla en ruta'::text, null::uuid)$$,
  'lo hecho sigue hecho y la nota sigue, sólo sin nombre');

-- ============================================================================
-- Una tarea cerrada no se marca
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000012', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'complete',
      '{}'::jsonb, 'p2-vicente-complete')$$,
  'completar sigue siendo una decisión aparte');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000082',
                         'done', true),
      'p2-vicente-closed-mark')$$,
  '23514', null, 'una tarea cerrada conserva sus servicios como quedaron');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Ya está'), 'p2-vicente-closed-note')$$,
  '23514', null, 'una tarea cerrada no tiene siguiente turno');
reset role;

-- ============================================================================
-- Braulio, desde su portal
-- ============================================================================

select is(
  public.erp_actor_display_name('e2760000-0000-4000-8000-000000000014',
    'e2760000-0000-4000-8000-000000000001'),
  'Braulio Muñoz',
  'quien actúa desde su portal se nombra por su ficha');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e2760000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e2760000-0000-4000-8000-000000000014', true);
set local role authenticated;

select results_eq(
  $$select item ->> 'job_item_id', item ? 'done_at'
      from public.get_my_worker_tasks_v1() task,
           jsonb_array_elements(task.job_items) item$$,
  $$values ('e2760000-0000-4000-8000-000000000083'::text, false)$$,
  'el portal recibe cada servicio con su identidad, pendiente');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p2_ctx where key = 'braulio'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000083',
                         'done', true),
      'p2-braulio-done')$$,
  'el portal marca su servicio');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p2_ctx where key = 'braulio'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Rayos tensados; falta revisar el salto'),
      'p2-braulio-note')$$,
  'el portal deja la nota del turno');
select results_eq(
  $$select item ->> 'done_by_name', item ? 'done_at', task.handoff_note,
           task.handoff_note_by_name
      from public.get_my_worker_tasks_v1() task,
           jsonb_array_elements(task.job_items) item$$,
  $$values ('Braulio Muñoz'::text, true, 'Rayos tensados; falta revisar el salto'::text,
            'Braulio Muñoz'::text)$$,
  'el portal ve lo que marcó y su nota, con su nombre');
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from p2_ctx where key = 'vicente'), null, 'set_handoff_note',
      jsonb_build_object('note', 'Ajena'), 'p2-braulio-foreign')$$,
  '42501', null, 'el portal no toca tareas que no son suyas');

reset role;

select is(
  (select recipient_user_id from public.erp_notifications
    where entity_id = (select id from p2_ctx where key = 'braulio')
      and type = 'smart_task_handoff_note'),
  'e2760000-0000-4000-8000-000000000011'::uuid,
  'la nota del portal también le avisa a quien encargó');

-- El taller borra el servicio: queda la evidencia y ya no se marca hecho.
delete from public.mechanic_job_items
 where id = 'e2760000-0000-4000-8000-000000000083';

set local role authenticated;
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from p2_ctx where key = 'braulio'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000083',
                         'done', false),
      'p2-braulio-undo-removed')$$,
  'un servicio que el taller borró se puede volver a pendiente');
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from p2_ctx where key = 'braulio'), null, 'set_job_item_done',
      jsonb_build_object('job_item_id', 'e2760000-0000-4000-8000-000000000083',
                         'done', true),
      'p2-braulio-done-removed')$$,
  '23514', null, 'pero no se marca hecho algo que ya no está en el trabajo');
reset role;

select * from finish();
rollback;
