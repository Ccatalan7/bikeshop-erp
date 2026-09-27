begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- Una tarea es del TRABAJADOR, tenga o no cuenta, y le llega sola cuando la
-- tiene (dueño, 2026-09-26): «si un trabajador se crea un usuario luego de
-- que le fueron asignadas tareas, esas tareas son heredadas y llegan a su
-- bandeja de entrada».

select has_column('public', 'smart_tasks', 'assigned_employee_id',
  'la tarea guarda al trabajador responsable');
select has_function('public', 'smart_task_employee_principal_v1', array['uuid', 'uuid'],
  'la cuenta de un trabajador se resuelve en un solo lugar');
select has_function('public', 'smart_task_user_employee_v1', array['uuid', 'uuid'],
  'el trabajador detrás de una cuenta se resuelve en un solo lugar');
select has_function('public', 'smart_task_sync_employee_account_v1', array['uuid', 'uuid'],
  'la sincronización con la cuenta del trabajador es una función del servidor');
select ok(
  not has_function_privilege('authenticated',
    'public.smart_task_sync_employee_account_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.smart_task_employee_principal_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_user_employee_v1(uuid, uuid)', 'EXECUTE'),
  'nadie llama la sincronización ni los resolvedores desde el cliente');
select ok(
  (select bool_and(tgdeferrable and tginitdeferred and tgenabled <> 'D')
     from pg_trigger
    where tgname in (
      'trg_employees_smart_task_account_sync',
      'trg_portal_accounts_smart_task_account_sync',
      'trg_user_profiles_smart_task_account_sync'
    )),
  'la sincronización corre diferida, al confirmar el cambio de acceso');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name, owner_email, timezone) values
  ('e1760000-0000-4000-8000-000000000001', 'Taller A',
   'emp-a@example.invalid', 'America/Santiago'),
  ('e1760000-0000-4000-8000-000000000002', 'Taller B',
   'emp-b@example.invalid', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e1760000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'emp-manager@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb, '{}'::jsonb, now(), now()),
  ('e1760000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'emp-vicente@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  -- Lucas: usuario ERP que existe desde antes pero todavía no está vinculado
  -- a su ficha de trabajador.
  ('e1760000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'emp-lucas@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now());

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
) values
  ('e1760000-0000-4000-8000-000000000021', 'e1760000-0000-4000-8000-000000000001',
   'e1760000-0000-4000-8000-000000000012',
   'EMP-001', 'Vicente', 'Díaz', 'Mecánico', 'full_time', 'active', 0),
  ('e1760000-0000-4000-8000-000000000022', 'e1760000-0000-4000-8000-000000000001',
   null, 'EMP-002', 'Braulio', 'Muñoz', 'Mecánico', 'full_time', 'active', 0),
  ('e1760000-0000-4000-8000-000000000023', 'e1760000-0000-4000-8000-000000000001',
   null, 'EMP-003', 'Lucas', 'Pacheco', 'Mecánico', 'full_time', 'active', 0),
  ('e1760000-0000-4000-8000-000000000024', 'e1760000-0000-4000-8000-000000000001',
   null, 'EMP-004', 'Rodrigo', 'Nieto', 'Mecánico', 'full_time', 'inactive', 0),
  ('e1760000-0000-4000-8000-000000000025', 'e1760000-0000-4000-8000-000000000001',
   null, 'EMP-005', 'Tomás', 'SinCuenta', 'Mecánico', 'full_time', 'active', 0),
  ('e1760000-0000-4000-8000-000000000029', 'e1760000-0000-4000-8000-000000000002',
   null, 'EMP-B01', 'Ajeno', 'Otro', 'Mecánico', 'full_time', 'active', 0);

insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id) values
  ('e1760000-0000-4000-8000-000000000011',
   'e1760000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null),
  ('e1760000-0000-4000-8000-000000000012',
   'e1760000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'e1760000-0000-4000-8000-000000000021'),
  ('e1760000-0000-4000-8000-000000000013',
   'e1760000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb, null);

insert into public.customers (id, tenant_id, name) values
  ('e1760000-0000-4000-8000-000000000041',
   'e1760000-0000-4000-8000-000000000001', 'Cliente Taller');

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, arrival_date, status, priority,
  client_request, created_by
) values
  ('e1760000-0000-4000-8000-000000000061', 'e1760000-0000-4000-8000-000000000001',
   'EMP-JOB-1', 'e1760000-0000-4000-8000-000000000041', now(), 'PENDIENTE',
   'NORMAL', 'Mantención', 'e1760000-0000-4000-8000-000000000011');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values
  ('e1760000-0000-4000-8000-000000000081', 'e1760000-0000-4000-8000-000000000001',
   'e1760000-0000-4000-8000-000000000061', 'Purga de frenos', 'service', 1, 0),
  ('e1760000-0000-4000-8000-000000000082', 'e1760000-0000-4000-8000-000000000001',
   'e1760000-0000-4000-8000-000000000061', 'Cambio de cadena', 'service', 1, 0);

create or replace function pg_temp.commit_sync() returns void language plpgsql as $fn$
begin
  set constraints
    trg_employees_smart_task_account_sync,
    trg_portal_accounts_smart_task_account_sync,
    trg_user_profiles_smart_task_account_sync
  immediate;
  set constraints
    trg_employees_smart_task_account_sync,
    trg_portal_accounts_smart_task_account_sync,
    trg_user_profiles_smart_task_account_sync
  deferred;
end;
$fn$;

create temp table emp_ctx(key text primary key, id uuid);
grant select, insert, update on emp_ctx to authenticated;

-- ============================================================================
-- La manager asigna a trabajadores con y sin cuenta
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

insert into emp_ctx
select 'braulio_job', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Purga de frenos',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000022',
  'linked_job_id', 'e1760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('e1760000-0000-4000-8000-000000000081')
), 'emp-create-braulio-job')) #>> '{task,id}')::uuid;

insert into emp_ctx
select 'braulio_done', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Ordenar el banco',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000022'
), 'emp-create-braulio-done')) #>> '{task,id}')::uuid;

insert into emp_ctx
select 'lucas', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Cambio de cadena',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000023'
), 'emp-create-lucas')) #>> '{task,id}')::uuid;

insert into emp_ctx
select 'vicente_by_user', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Armar presupuesto',
  'assigned_to', 'e1760000-0000-4000-8000-000000000012'
), 'emp-create-vicente-user')) #>> '{task,id}')::uuid;

insert into emp_ctx
select 'vicente_by_employee', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Llamar al cliente',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000021'
), 'emp-create-vicente-employee')) #>> '{task,id}')::uuid;

insert into emp_ctx
select 'vicente_keep', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Revisar stock de cámaras',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000021'
), 'emp-create-vicente-keep')) #>> '{task,id}')::uuid;

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Trabajador de otro taller',
      'assigned_employee_id', 'e1760000-0000-4000-8000-000000000029'
    ), 'emp-create-cross-tenant')$$,
  '23514', null, 'un trabajador de otro tenant no recibe tareas de éste');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Trabajador que se fue',
      'assigned_employee_id', 'e1760000-0000-4000-8000-000000000024'
    ), 'emp-create-inactive')$$,
  '23514', null, 'un trabajador inactivo no recibe tareas');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Cuenta que no calza',
      'assigned_employee_id', 'e1760000-0000-4000-8000-000000000022',
      'assigned_to', 'e1760000-0000-4000-8000-000000000012'
    ), 'emp-create-mismatch')$$,
  '23514', null, 'la cuenta enviada tiene que ser del trabajador asignado');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Nota con responsable', 'task_kind', 'note',
      'assigned_employee_id', 'e1760000-0000-4000-8000-000000000022'
    ), 'emp-create-note')$$,
  '23514', null, 'una nota no tiene responsable, tampoco por trabajador');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Personal con responsable', 'visibility', 'private',
      'assigned_employee_id', 'e1760000-0000-4000-8000-000000000022'
    ), 'emp-create-private')$$,
  '23514', null, 'una tarea personal no tiene responsable, tampoco por trabajador');

reset role;

select results_eq(
  $$select assigned_employee_id, assigned_to, assigned_at is not null
      from public.smart_tasks where id = (select id from emp_ctx where key = 'braulio_job')$$,
  $$values ('e1760000-0000-4000-8000-000000000022'::uuid, null::uuid, true)$$,
  'Braulio no tiene cuenta y la tarea igual es suya, con fecha de asignación');
select is(
  (select count(*)::int from public.smart_task_job_items
    where task_id = (select id from emp_ctx where key = 'braulio_job')),
  1, 'la tarea de taller de alguien sin cuenta se anexa a su servicio');
select ok(
  exists (
    select 1 from public.smart_task_events
    where task_id = (select id from emp_ctx where key = 'braulio_job')
      and event_type = 'assigned'
      and payload ->> 'assigned_employee_id' = 'e1760000-0000-4000-8000-000000000022'
  ),
  'el ledger registra a quién se asignó aunque no tenga cuenta');
select is(
  (select assigned_employee_id from public.smart_tasks
    where id = (select id from emp_ctx where key = 'vicente_by_user')),
  'e1760000-0000-4000-8000-000000000021'::uuid,
  'asignar por cuenta deja escrito el trabajador detrás de ella');
select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'vicente_by_employee')),
  'e1760000-0000-4000-8000-000000000012'::uuid,
  'asignar al trabajador con usuario le llega a su usuario');

-- Una tarea de Braulio ya cerrada no se hereda: la bandeja recibe lo abierto.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from emp_ctx where key = 'braulio_done'), null, 'complete',
      '{}'::jsonb, 'emp-complete-braulio-done')$$,
  'la manager completa una tarea de alguien sin cuenta');
reset role;

-- ============================================================================
-- Braulio recibe su cuenta del portal: hereda lo abierto
-- ============================================================================

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e1760000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'emp-braulio@example.invalid', '', now(),
   jsonb_build_object(
     'account_type', 'worker_portal',
     'tenant_id', 'e1760000-0000-4000-8000-000000000001',
     'employee_id', 'e1760000-0000-4000-8000-000000000022',
     'role', 'worker'
   ), '{}'::jsonb, now(), now());

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);

insert into public.employee_portal_accounts (
  id, tenant_id, employee_id, auth_user_id, username, login_email, is_active, created_by
) values (
  'e1760000-0000-4000-8000-000000000031', 'e1760000-0000-4000-8000-000000000001',
  'e1760000-0000-4000-8000-000000000022', 'e1760000-0000-4000-8000-000000000014',
  'braulio', 'emp-braulio@example.invalid', true,
  'e1760000-0000-4000-8000-000000000011'
);

select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'braulio_job')),
  null::uuid,
  'antes de confirmar el alta de la cuenta, la tarea todavía no se movió');

-- Lo que hace el COMMIT: corre la sincronización diferida. Sólo la nuestra:
-- los chequeos de consistencia de identidad también son diferidos y miran
-- estados intermedios que las funciones de vínculo arreglan antes del COMMIT.
select pg_temp.commit_sync();

select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'braulio_job')),
  'e1760000-0000-4000-8000-000000000014'::uuid,
  'la tarea abierta de Braulio le llega a su cuenta nueva del portal');
select is(
  (select assigned_employee_id from public.smart_tasks
    where id = (select id from emp_ctx where key = 'braulio_job')),
  'e1760000-0000-4000-8000-000000000022'::uuid,
  'la herencia no le cambia el dueño a la tarea');
select ok(
  exists (
    select 1 from public.smart_task_events
    where task_id = (select id from emp_ctx where key = 'braulio_job')
      and event_type = 'assigned'
      and payload ->> 'source' = 'employee_access_sync'
      and payload ->> 'assigned_to' = 'e1760000-0000-4000-8000-000000000014'
      and actor_user_id = 'e1760000-0000-4000-8000-000000000011'
  ),
  'la herencia deja su evento a nombre de quien asignó: el aviso llega aunque '
  'el trabajador sea quien creó su cuenta');
select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'braulio_done')),
  null::uuid,
  'una tarea ya completada no se hereda');
select is(
  (select assigned_by from public.smart_tasks
    where id = (select id from emp_ctx where key = 'braulio_job')),
  'e1760000-0000-4000-8000-000000000011'::uuid,
  'heredar no cambia quién asignó');

-- ============================================================================
-- Lucas: su usuario ERP se vincula a su ficha y hereda
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.link_erp_user_to_employee(
      'e1760000-0000-4000-8000-000000000013',
      'e1760000-0000-4000-8000-000000000023')$$,
  'la manager vincula el usuario de Lucas a su ficha');
reset role;
select pg_temp.commit_sync();

select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'lucas')),
  'e1760000-0000-4000-8000-000000000013'::uuid,
  'la tarea de Lucas le llega a su usuario del ERP apenas se vincula');

-- Lucas tiene otra tarea abierta cuando pierde su usuario.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into emp_ctx
select 'lucas_keep', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Revisar frenos',
  'assigned_employee_id', 'e1760000-0000-4000-8000-000000000023'
), 'emp-create-lucas-keep')) #>> '{task,id}')::uuid;
reset role;

select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'lucas_keep')),
  'e1760000-0000-4000-8000-000000000013'::uuid,
  'con usuario vinculado, la tarea nueva de Lucas le llega a ese usuario');
select is(
  (select count(*)::int from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from emp_ctx where key = 'lucas_keep')
      and type = 'smart_task_assigned'
      and recipient_user_id = 'e1760000-0000-4000-8000-000000000013'),
  1, 'a Lucas le llega el aviso de su tarea nueva');

-- Lucas la ve en su bandeja.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select is(
  (select count(*)::int from public.smart_tasks
    where assigned_to = auth.uid() and status = 'pending'),
  2, 'Lucas ve la heredada y la nueva en «Asignadas a mí»');
reset role;

-- Se le quita el usuario a Lucas: sus tareas dejan de llegar a esa cuenta y
-- siguen a su nombre.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.unlink_erp_user_from_employee(
      'e1760000-0000-4000-8000-000000000013',
      'e1760000-0000-4000-8000-000000000023')$$,
  'la manager desvincula el usuario de Lucas');
reset role;
select pg_temp.commit_sync();

select results_eq(
  $$select assigned_employee_id, assigned_to
      from public.smart_tasks where id = (select id from emp_ctx where key = 'lucas_keep')$$,
  $$values ('e1760000-0000-4000-8000-000000000023'::uuid, null::uuid)$$,
  'sin cuenta, la tarea deja la bandeja vieja y sigue siendo de Lucas');
select ok(
  exists (
    select 1 from public.smart_task_events
    where task_id = (select id from emp_ctx where key = 'lucas_keep')
      and event_type = 'details_updated'
      and payload ->> 'source' = 'employee_access_sync'
      and payload ->> 'previous_assignee' = 'e1760000-0000-4000-8000-000000000013'
  ),
  'perder la cuenta queda registrado sin decir que la tarea quedó sin responsable');
select is(
  (select count(*)::int from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from emp_ctx where key = 'lucas_keep')
      and type = 'smart_task_assigned'
      and recipient_user_id = 'e1760000-0000-4000-8000-000000000013'),
  0, 'la cuenta que se fue ya no conserva el aviso de «Tarea asignada»');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select lives_ok(
  $$select public.link_erp_user_to_employee(
      'e1760000-0000-4000-8000-000000000013',
      'e1760000-0000-4000-8000-000000000023')$$,
  'la manager vuelve a vincular a Lucas');
reset role;
select pg_temp.commit_sync();

select is(
  (select assigned_to from public.smart_tasks
    where id = (select id from emp_ctx where key = 'lucas_keep')),
  'e1760000-0000-4000-8000-000000000013'::uuid,
  'al volver a tener cuenta, la tarea le vuelve a llegar');

-- ============================================================================
-- Reasignar y devolver mueven trabajador y cuenta juntos
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from emp_ctx where key = 'vicente_by_employee'), null, 'assign',
      jsonb_build_object('assigned_employee_id', 'e1760000-0000-4000-8000-000000000022'),
      'emp-reassign-to-braulio')$$,
  'la manager reasigna de Vicente a Braulio por trabajador');
reset role;

select results_eq(
  $$select assigned_employee_id, assigned_to
      from public.smart_tasks where id = (select id from emp_ctx where key = 'vicente_by_employee')$$,
  $$values ('e1760000-0000-4000-8000-000000000022'::uuid,
            'e1760000-0000-4000-8000-000000000014'::uuid)$$,
  'reasignar deja la tarea en Braulio y en su cuenta, no en la de Vicente');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from emp_ctx where key = 'lucas'), null, 'assign',
      '{}'::jsonb, 'emp-unassign-lucas')$$,
  'la manager desasigna');
reset role;

select results_eq(
  $$select assigned_employee_id, assigned_to
      from public.smart_tasks where id = (select id from emp_ctx where key = 'lucas')$$,
  $$values (null::uuid, null::uuid)$$,
  'desasignar suelta trabajador y cuenta');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000012', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from emp_ctx where key = 'vicente_by_user'), null, 'return',
      jsonb_build_object('reason', 'No me corresponde'), 'emp-return-vicente')$$,
  'Vicente devuelve su tarea');
reset role;

select results_eq(
  $$select assigned_employee_id, assigned_to
      from public.smart_tasks where id = (select id from emp_ctx where key = 'vicente_by_user')$$,
  $$values (null::uuid, null::uuid)$$,
  'devolver suelta también al trabajador: la tarea vuelve a quedar sin responsable');

-- El asignado no se pasa la tarea a otro trabajador por la vía directa.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
set local role authenticated;
select throws_ok(
  $$update public.smart_tasks
       set assigned_employee_id = 'e1760000-0000-4000-8000-000000000023'
     where id = (select id from emp_ctx where key = 'vicente_keep')$$,
  '42501', null,
  'cambiar de trabajador es reasignar, y sólo lo hace el creador o una manager');
reset role;

-- ============================================================================
-- El relleno sólo escribe quién es: no toca fecha, autor, acuse ni versión
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into emp_ctx
select 'legacy', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Tarea de antes', 'assigned_to', 'e1760000-0000-4000-8000-000000000012'
), 'emp-create-legacy')) #>> '{task,id}')::uuid;
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000012', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from emp_ctx where key = 'legacy'), null, 'acknowledge',
      '{}'::jsonb, 'emp-ack-legacy')$$,
  'Vicente acusa recibo de su tarea');
reset role;

-- Así quedaba una tarea antes de esta migración: cuenta sin trabajador.
alter table public.smart_tasks disable trigger trg_smart_tasks_guard_work_tray;
alter table public.smart_tasks disable trigger trg_smart_tasks_audit_direct_write;
update public.smart_tasks set assigned_employee_id = null
 where id = (select id from emp_ctx where key = 'legacy');
alter table public.smart_tasks enable trigger trg_smart_tasks_guard_work_tray;
alter table public.smart_tasks enable trigger trg_smart_tasks_audit_direct_write;

create temp table legacy_before as
select assigned_at, assigned_by, acknowledged_at, acknowledged_by, version,
       (select count(*) from public.smart_task_events e where e.task_id = t.id) as events
  from public.smart_tasks t where id = (select id from emp_ctx where key = 'legacy');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
do $do$
begin
  perform set_config('vinabike.smart_task_cmd', 'employee_backfill', true);
  update public.smart_tasks task
     set assigned_employee_id = public.smart_task_user_employee_v1(
       task.tenant_id, task.assigned_to)
   where task.assigned_to is not null
     and task.assigned_employee_id is null
     and public.smart_task_user_employee_v1(task.tenant_id, task.assigned_to) is not null;
  perform set_config('vinabike.smart_task_cmd', '', true);
end;
$do$;

select results_eq(
  $$select t.assigned_employee_id, t.assigned_to, t.assigned_at, t.assigned_by,
           t.acknowledged_at, t.acknowledged_by, t.version,
           (select count(*) from public.smart_task_events e where e.task_id = t.id)
      from public.smart_tasks t where t.id = (select id from emp_ctx where key = 'legacy')$$,
  $$select 'e1760000-0000-4000-8000-000000000021'::uuid,
           'e1760000-0000-4000-8000-000000000012'::uuid,
           assigned_at, assigned_by, acknowledged_at, acknowledged_by, version, events
      from legacy_before$$,
  'el relleno escribe a Vicente y conserva fecha, autor, acuse, versión y eventos');

-- ============================================================================
-- La ruta directa también registra la asignación a alguien sin cuenta
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'e1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'e1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
with created as (
  insert into public.smart_tasks (tenant_id, title, created_by, assigned_employee_id)
  values ('e1760000-0000-4000-8000-000000000001', 'Directa',
          'e1760000-0000-4000-8000-000000000011',
          'e1760000-0000-4000-8000-000000000025')
  returning id
)
insert into emp_ctx select 'direct', id from created;
reset role;

select ok(
  exists (
    select 1 from public.smart_task_events
    where task_id = (select id from emp_ctx where key = 'direct')
      and event_type = 'assigned'
      and payload ->> 'source' = 'direct'
      and payload ->> 'assigned_employee_id' = 'e1760000-0000-4000-8000-000000000025'
  ),
  'la ruta directa registra la asignación a Tomás aunque no tenga cuenta');

select * from finish();
rollback;
