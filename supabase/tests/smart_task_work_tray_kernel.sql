begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

-- ============================================================================
-- Estructura
-- ============================================================================

select has_table('public', 'smart_task_events', 'ledger append-only de la bandeja existe');
select has_table('public', 'smart_task_job_items', 'vínculo tarea-servicios existe');
select has_table('public', 'smart_task_user_state', 'estado por usuario (visto/pin/snooze) existe');
select has_table('public', 'smart_task_command_receipts', 'recibos idempotentes existen');
select has_table('public', 'smart_task_message_channels',
  'los canales compartidos de tareas tienen un registro server-owned');
select has_column('public', 'smart_tasks', 'task_kind', 'tarea/nota');
select has_column('public', 'smart_tasks', 'visibility', 'private/team/company');
select has_column('public', 'smart_tasks', 'version', 'versionado optimista');
select has_column('public', 'smart_tasks', 'acknowledged_at', 'recepción separada del estado');
select has_column('public', 'smart_tasks', 'blocked_reason', 'motivo de bloqueo');
select has_column('public', 'smart_task_job_items', 'invalidated_at', 'evidencia invalidable, no borrable');
select has_column('public', 'smart_task_job_items', 'context_changed_at', 'edición de la línea marcada');
select has_column('public', 'smart_task_job_items', 'item_instructions',
  'snapshot durable de las instrucciones del servicio');
select has_column('public', 'erp_notifications', 'recipient_user_id', 'notificación dirigida');
select has_column('public', 'messages', 'thread_root_message_id',
  'las respuestas conservan su mensaje raíz');
select has_column('public', 'conversation_contexts', 'thread_root_message_id',
  'el contexto de tarea apunta a un mensaje raíz real');

select has_function('public', 'smart_task_create_v1', array['jsonb', 'text'],
  'creación idempotente');
select has_function('public', 'smart_task_command_v1',
  array['uuid', 'integer', 'text', 'jsonb', 'text'], 'comando versionado');
select has_function('public', 'get_smart_task_assignment_directory_v1',
  array[]::text[], 'directorio de asignación');
select has_function('public', 'get_my_worker_tasks_v1', array[]::text[],
  'proyección del portal');
select has_function('public', 'worker_task_command_v1',
  array['uuid', 'integer', 'text', 'jsonb', 'text'], 'comando del portal');
select has_function('public', 'smart_task_thread_v1', array['uuid'],
  'hilo canónico consultable');
select has_function('public', 'smart_task_thread_get_or_create_v1',
  array['uuid'], 'hilo get-or-create server-owned');
select has_function('public', 'smart_tasks_guard_primary_context',
  array[]::text[], 'guard de contexto principal');
select has_function('public', 'messaging_thread_relation_guard_v1',
  array[]::text[], 'guard de pertenencia del hilo');
select has_function('public', 'publish_messaging_attachment_in_thread_v1',
  array['uuid', 'text', 'uuid'], 'adjuntos publicables como respuestas');
select has_function('public', 'smart_task_channel_for_v1',
  array['smart_tasks', 'uuid'], 'resolución server-owned del canal por audiencia');

select ok(
  not has_table_privilege('authenticated', 'public.smart_task_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smart_task_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smart_task_events', 'DELETE'),
  'el ledger de eventos es append-only y solo por comandos');
select ok(
  not has_table_privilege('authenticated', 'public.smart_task_job_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smart_task_job_items', 'DELETE'),
  'los vínculos a servicios solo cambian por comandos');
select ok(
  position('new.item_instructions := nullif(btrim(v_item.notes)' in
    pg_get_functiondef(
      'public.smart_task_job_items_guard()'::regprocedure)) > 0
  and position('new.notes is distinct from old.notes' in
    pg_get_functiondef(
      'public.smart_task_job_items_mark_context_changed()'::regprocedure)) > 0
  and position('item_instructions' in pg_get_functiondef(
    'public.get_my_worker_tasks_v1()'::regprocedure)) > 0,
  'las instrucciones se capturan, se vigilan y llegan al portal');
select ok(
  not has_table_privilege('authenticated', 'public.smart_task_command_receipts', 'SELECT'),
  'los recibos idempotentes no son visibles para clientes');
select ok(
  not has_table_privilege('authenticated', 'public.smart_tasks', 'DELETE'),
  'la bandeja cancela: el DELETE de cliente está revocado');
select ok(
  has_function_privilege('authenticated', 'public.smart_task_create_v1(jsonb,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.smart_task_create_v1(jsonb,text)', 'EXECUTE'),
  'solo un JWT autenticado crea tareas');
select ok(
  has_function_privilege('authenticated',
    'public.smart_task_can_view_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_can_view_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_can_view_v1(uuid)', 'EXECUTE'),
  'el helper de visibilidad solo se expone al rol que lo necesita en RLS');
select ok(
  not has_table_privilege('authenticated',
    'public.erp_notifications', 'UPDATE')
  and has_column_privilege('authenticated',
    'public.erp_notifications', 'read_at', 'UPDATE')
  and not has_column_privilege('authenticated',
    'public.erp_notifications', 'recipient_user_id', 'UPDATE'),
  'el cliente solo marca read_at y no puede redirigir notificaciones');

-- El claim idempotente serializa concurrentes con lock transaccional.
select ok(position('pg_advisory_xact_lock' in pg_get_functiondef(
  'public.smart_task_claim_receipt(uuid,uuid,text,text,text)'::regprocedure
)) > 0, 'el claim de idempotencia toma lock transaccional antes de leer');
select ok(
  position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.smart_task_lock_job_items(uuid,uuid[])'::regprocedure)) > 0
  and position('smart_task_job_items_tenant' in pg_get_functiondef(
    'public.smart_task_lock_job_items(uuid,uuid[])'::regprocedure)) > 0
  and position('smart_task_lock_job_items' in pg_get_functiondef(
    'public.smart_task_create_v1(jsonb,text)'::regprocedure)) > 0
  and position('smart_task_lock_job_items' in pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure))
      < position('select * into v_task' in pg_get_functiondef(
    'public.smart_task_apply_command(uuid,uuid,boolean,text[],uuid,integer,text,jsonb)'::regprocedure)),
  'crear y relinkear serializan servicios antes de bloquear filas de tarea');
select ok(
  not has_function_privilege('authenticated',
    'public.smart_task_lock_job_items(uuid,uuid[])', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_lock_job_items(uuid,uuid[])', 'EXECUTE'),
  'el lock de servicios es un helper interno, no una RPC pública');

-- El hilo por tarea es único a nivel de base.
select ok(exists (
  select 1 from pg_indexes
  where schemaname = 'public'
    and indexname = 'uq_conversation_contexts_task_thread'
), 'índice único parcial del hilo de tarea existe');

-- El ledger impide el hard-delete de la tarea (FK RESTRICT).
select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.smart_task_events'::regclass
    and contype = 'f'
    and confrelid = 'public.smart_tasks'::regclass
    and confdeltype = 'r'
), 'los eventos protegen la tarea contra el borrado físico');

select is(
  public.messaging_context_belongs_to_tenant('task', gen_random_uuid(), gen_random_uuid()),
  false,
  'el contexto task existe en la validación de mensajería (y no inventa pertenencia)');

-- ============================================================================
-- Fixture
-- ============================================================================

insert into public.tenants (id, shop_name, owner_email, timezone) values
  ('a1760000-0000-4000-8000-000000000001', 'Bandeja tenant A',
   'tray-a@example.invalid', 'America/Santiago'),
  ('a1760000-0000-4000-8000-000000000002', 'Bandeja tenant B',
   'tray-b@example.invalid', 'America/Santiago');

-- El seed de inicialización de tenant deja request.jwt.claim.sub apuntando al
-- ID DEL TENANT; sin esta limpieza, auth.uid() devuelve el tenant y cualquier
-- trigger que capture actor escribe basura (costó un FK violado encontrarlo).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1760000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'tray-manager@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb,
   '{"display_name":"La Manager"}'::jsonb, now(), now()),
  ('a1760000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'tray-mech@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1760000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'tray-cashier@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb,
   '{"display_name":"El Cajero"}'::jsonb, now(), now()),
  ('a1760000-0000-4000-8000-000000000015', 'authenticated', 'authenticated',
   'tray-outsider@example.invalid', '', now(),
   '{"account_type":"erp_owner"}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1760000-0000-4000-8000-000000000016', 'authenticated', 'authenticated',
   'tray-ghost@example.invalid', '', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1760000-0000-4000-8000-000000000017', 'authenticated', 'authenticated',
   'tray-semi@example.invalid', '', now(),
   '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now());

insert into public.employees (
  id, tenant_id, user_id, employee_number, first_name, last_name, job_title,
  employment_type, status, base_salary
) values
  ('a1760000-0000-4000-8000-000000000021',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000012',
   'TRAY-001', 'Marcos', 'Mecánico', 'Mecánico', 'full_time', 'active', 0),
  ('a1760000-0000-4000-8000-000000000022',
   'a1760000-0000-4000-8000-000000000001',
   null,
   'TRAY-002', 'Pedro', 'Portal', 'Mecánico', 'full_time', 'active', 0),
  ('a1760000-0000-4000-8000-000000000023',
   'a1760000-0000-4000-8000-000000000001',
   null,
   'TRAY-003', 'Sofía', 'SinCuenta', 'Mecánica', 'full_time', 'active', 0),
  -- Vinculada a un usuario auth pero SIN perfil activo: exactamente una vez
  -- en el directorio, como no elegible.
  ('a1760000-0000-4000-8000-000000000024',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000017',
   'TRAY-004', 'Semi', 'Enlazada', 'Mecánica', 'full_time', 'active', 0);

-- El usuario de portal se crea después de su empleado: el guard de identidad
-- de auth.users exige que tenant y empleado existan al nacer la cuenta.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1760000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'tray-portal@example.invalid', '', now(),
   jsonb_build_object(
     'account_type', 'worker_portal',
     'tenant_id', 'a1760000-0000-4000-8000-000000000001',
     'employee_id', 'a1760000-0000-4000-8000-000000000022',
     'role', 'worker'
   ), '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, employee_id) values
  ('a1760000-0000-4000-8000-000000000011',
   'a1760000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, null),
  ('a1760000-0000-4000-8000-000000000012',
   'a1760000-0000-4000-8000-000000000001', 'mechanic', '{}'::jsonb,
   'a1760000-0000-4000-8000-000000000021'),
  ('a1760000-0000-4000-8000-000000000013',
   'a1760000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, null),
  ('a1760000-0000-4000-8000-000000000015',
   'a1760000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, null);

insert into public.employee_portal_accounts (
  id, tenant_id, employee_id, auth_user_id, username, login_email, is_active,
  created_by
) values (
  'a1760000-0000-4000-8000-000000000031',
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000022',
  'a1760000-0000-4000-8000-000000000014',
  'pedro', 'tray-portal@example.invalid', true,
  'a1760000-0000-4000-8000-000000000011'
);

insert into public.customers (id, tenant_id, name) values
  ('a1760000-0000-4000-8000-000000000041',
   'a1760000-0000-4000-8000-000000000001', 'Cliente Bandeja'),
  ('a1760000-0000-4000-8000-000000000042',
   'a1760000-0000-4000-8000-000000000002', 'Cliente Ajeno');

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('a1760000-0000-4000-8000-000000000051',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000041', 'Trek', '820'),
  ('a1760000-0000-4000-8000-000000000052',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000041', 'Giant', 'Talon');

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, arrival_date,
  status, priority, client_request, created_by
) values
  ('a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000001', 'TRAY-JOB-1',
   'a1760000-0000-4000-8000-000000000041',
   'a1760000-0000-4000-8000-000000000051', now(),
   'PENDIENTE', 'NORMAL', 'Ajuste general',
   'a1760000-0000-4000-8000-000000000011'),
  ('a1760000-0000-4000-8000-000000000062',
   'a1760000-0000-4000-8000-000000000002', 'TRAY-JOB-B',
   'a1760000-0000-4000-8000-000000000042', null, now(),
   'PENDIENTE', 'NORMAL', 'Trabajo ajeno',
   'a1760000-0000-4000-8000-000000000015');

insert into public.mechanic_job_bikes (id, tenant_id, job_id, bike_id) values
  ('a1760000-0000-4000-8000-000000000071',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000051'),
  ('a1760000-0000-4000-8000-000000000072',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000052');

insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_name, notes, item_type,
  quantity, unit_price
) values
  ('a1760000-0000-4000-8000-000000000081',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000071',
   'Ajuste de cambios', 'AJUSTAR CAMBIO TRASERO Y VERIFICAR TENSIÓN.',
   'service', 1, 0),
  ('a1760000-0000-4000-8000-000000000082',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000071',
   'Mantención de motor', 'REVISAR MOTOR Y DOCUMENTAR RUIDOS.',
   'service', 1, 0),
  ('a1760000-0000-4000-8000-000000000083',
   'a1760000-0000-4000-8000-000000000002',
   'a1760000-0000-4000-8000-000000000062',
   null,
   'Servicio ajeno', null, 'service', 1, 0),
  ('a1760000-0000-4000-8000-000000000084',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000072',
   'Cadena KMC X10', null, 'product', 1, 15990),
  ('a1760000-0000-4000-8000-000000000085',
   'a1760000-0000-4000-8000-000000000001',
   'a1760000-0000-4000-8000-000000000061',
   'a1760000-0000-4000-8000-000000000072',
   'Limpieza transmisión', 'LIMPIAR Y LUBRICAR TODA LA TRANSMISIÓN.',
   'service', 1, 0);

create temp table tray_ctx(key text primary key, id uuid);
grant select, insert, update on tray_ctx to authenticated;

-- ============================================================================
-- Una tarea neutral admite un solo contexto, siempre del mismo tenant
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Seguimiento del cliente',
      'linked_customer_id', 'a1760000-0000-4000-8000-000000000041'
    ), 'tray-context-customer')$$,
  'un cliente del tenant puede ser el único contexto de la tarea');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Contexto ajeno',
      'linked_customer_id', 'a1760000-0000-4000-8000-000000000042'
    ), 'tray-context-cross-tenant')$$,
  '23503', null,
  'un contexto de otro tenant se rechaza aunque el FK exista');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Dos contextos',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
      'linked_customer_id', 'a1760000-0000-4000-8000-000000000041'
    ), 'tray-context-multiple')$$,
  '23514', null,
  'una tarea no puede mezclar dos contextos principales');

reset role;

-- ============================================================================
-- Caso dueño: la manager reparte un trabajo entre dos mecánicos
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

insert into tray_ctx
select 'task1', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Ajuste de cambios Trek 820',
  'assigned_to', 'a1760000-0000-4000-8000-000000000012',
  'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081'),
  'due_date', (now() + interval '2 days')::text
), 'tray-create-1')) #>> '{task,id}')::uuid;

insert into tray_ctx
select 'task2', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Mantención de motor Trek 820',
  'assigned_to', 'a1760000-0000-4000-8000-000000000014',
  'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array(
    'a1760000-0000-4000-8000-000000000082',
    'a1760000-0000-4000-8000-000000000085'
  )
), 'tray-create-2')) #>> '{task,id}')::uuid;

reset role;

select is(
  (select count(*)::int from public.smart_tasks
    where id in (select id from tray_ctx where key in ('task1', 'task2'))),
  2, 'las dos tareas del caso dueño existen sobre el mismo trabajo');
select is(
  (select count(*)::int from public.smart_task_job_items link
    where link.job_id = 'a1760000-0000-4000-8000-000000000061'),
  3, 'cada tarea cubre sus propios servicios del trabajo');
select is(
  (select link.item_name from public.smart_task_job_items link
    where link.task_id = (select id from tray_ctx where key = 'task1')),
  'Ajuste de cambios', 'el snapshot conserva el nombre del servicio');
select is(
  (select link.item_instructions from public.smart_task_job_items link
    where link.task_id = (select id from tray_ctx where key = 'task1')),
  'AJUSTAR CAMBIO TRASERO Y VERIFICAR TENSIÓN.',
  'el snapshot conserva las instrucciones completas del servicio');
select is(
  (select link.bike_label from public.smart_task_job_items link
    where link.task_id = (select id from tray_ctx where key = 'task1')),
  'Trek 820', 'el snapshot conserva la bicicleta');
select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from tray_ctx where key = 'task1')
      and event_type in ('created', 'assigned', 'job_items_linked')),
  3, 'la creación deja su rastro completo de eventos');
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task1')
      and type = 'smart_task_assigned'),
  'a1760000-0000-4000-8000-000000000012'::uuid,
  'la asignación notifica al mecánico, dirigida y no broadcast');

-- Replay idempotente: misma clave y mismo payload devuelven la misma tarea.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

select is(
  ((public.smart_task_create_v1(jsonb_build_object(
    'title', 'Ajuste de cambios Trek 820',
    'assigned_to', 'a1760000-0000-4000-8000-000000000012',
    'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
    'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081'),
    'due_date', (now() + interval '2 days')::text
  ), 'tray-create-1')) #>> '{task,id}')::uuid,
  (select id from tray_ctx where key = 'task1'),
  'replay con la misma clave devuelve la misma tarea sin duplicar');

-- Solape: los mismos servicios ya están cubiertos por una tarea activa.
select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Duplicada sin decisión',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081')
    ), 'tray-create-overlap-1')$$,
  '23505', null,
  'crear sobre servicios ya cubiertos exige una decisión deliberada');

insert into tray_ctx
select 'task3', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Colaboración en ajuste',
  'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081'),
  'overlap_decision', 'collaborate'
), 'tray-create-3')) #>> '{task,id}')::uuid;

insert into tray_ctx
select 'task4', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Traspaso del ajuste',
  'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
  'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081'),
  'overlap_decision', 'transfer'
), 'tray-create-4')) #>> '{task,id}')::uuid;

reset role;

select is(
  (select count(*)::int from public.smart_task_job_items
    where task_id in (select id from tray_ctx where key in ('task1', 'task3'))),
  0, 'el traspaso deliberado desvincula el servicio de las tareas anteriores');
select is(
  (select count(*)::int from public.smart_task_events
    where event_type = 'job_items_unlinked'
      and task_id = (select id from tray_ctx where key = 'task1')),
  1, 'el traspaso queda auditado en la tarea que lo perdió');
select is(
  (select count(*)::int from public.smart_task_job_items
    where task_id = (select id from tray_ctx where key = 'task4')),
  1, 'la tarea destino quedó con el servicio');

-- Limpieza del experimento de solape para el resto del caso.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$update public.smart_tasks set linked_job_id = null
     where id = (select id from tray_ctx where key = 'task4')$$,
  '23514', null,
  'la ruta directa no puede dejar servicios huérfanos al cambiar el trabajo');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task3'), null, 'cancel',
      '{}'::jsonb, 'tray-cancel-3')$$,
  'la creadora cancela la tarea de colaboración');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task4'), null, 'cancel',
      '{}'::jsonb, 'tray-cancel-4')$$,
  'la creadora cancela la tarea de traspaso');

reset role;

-- Cancelar preserva el ledger completo, y el hard-delete está bloqueado
-- incluso para mantenimiento mientras exista historia.
select ok(
  (select count(*) from public.smart_task_events
    where task_id = (select id from tray_ctx where key = 'task4')) >= 3,
  'la tarea cancelada conserva toda su historia');
select throws_ok(
  $$delete from public.smart_tasks
     where id = (select id from tray_ctx where key = 'task4')$$,
  '23503', null,
  'ni siquiera un rol de mantenimiento borra una tarea con ledger');

select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

-- ============================================================================
-- Elegibilidad de asignación y líneas elegibles
-- ============================================================================

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Para nadie',
      'assigned_to', 'a1760000-0000-4000-8000-000000000016'
    ), 'tray-create-ghost')$$,
  '23514', null,
  'un usuario sin membresía del tenant no recibe tareas');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Taller sin identidad de trabajador',
      'assigned_to', 'a1760000-0000-4000-8000-000000000013',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061'
    ), 'tray-create-cashier-job')$$,
  '23514', null,
  'una tarea de taller exige asignado unido a un trabajador');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Nota asignada',
      'task_kind', 'note',
      'assigned_to', 'a1760000-0000-4000-8000-000000000012'
    ), 'tray-create-note-assigned')$$,
  '23514', null,
  'una nota no admite asignado');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Servicio de otro trabajo',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000083')
    ), 'tray-create-foreign-item')$$,
  '23514', null,
  'un servicio de otro trabajo (u otro tenant) no se puede vincular');

select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Un producto no es trabajo',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000084')
    ), 'tray-create-product-line')$$,
  '23514', null,
  'una línea de producto no puede respaldar una tarea');

reset role;

-- ============================================================================
-- Ciclo de vida del mecánico ERP + límites de autoridad del asignado
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'acknowledge',
      '{}'::jsonb, 'tray-ack-1')$$,
  'el asignado acusa recibo');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'start',
      '{}'::jsonb, 'tray-start-1')$$,
  'el asignado inicia');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'block',
      '{}'::jsonb, 'tray-block-sin-motivo')$$,
  '22023', null, 'bloquear sin motivo se rechaza');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'block',
      jsonb_build_object('reason', 'Falta repuesto'), 'tray-block-1')$$,
  'bloquear con motivo');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), 1, 'complete',
      '{}'::jsonb, 'tray-complete-stale')$$,
  '40001', null, 'una versión vencida no puede mutar (conflicto optimista)');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'unblock',
      '{}'::jsonb, 'tray-unblock-1')$$,
  'desbloquear');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'complete',
      '{}'::jsonb, 'tray-complete-1')$$,
  'completar');

-- El asignado NO reasigna, NO edita alcance ni detalles: eso es de
-- creador/manager, por RPC y por ruta directa.
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000013'),
      'tray-mech-assign')$$,
  '42501', null, 'el asignado no reasigna por RPC');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'update_details',
      jsonb_build_object('title', 'Reescrita por el asignado'),
      'tray-mech-details')$$,
  '42501', null, 'el asignado no reescribe detalles por RPC');
select throws_ok(
  $$update public.smart_tasks set title = 'Reescrita directa'
     where id = (select id from tray_ctx where key = 'task1')$$,
  '42501', null, 'el asignado no reescribe el título ni por ruta directa');
select throws_ok(
  $$update public.smart_tasks set assigned_to = 'a1760000-0000-4000-8000-000000000013'
     where id = (select id from tray_ctx where key = 'task1')$$,
  '42501', null, 'el asignado no traspasa por ruta directa');

reset role;

select results_eq(
  $$select task.status, task.acknowledged_by, task.completed_by,
           task.started_at is not null, task.blocked_reason is null
      from public.smart_tasks task
     where task.id = (select id from tray_ctx where key = 'task1')$$,
  $$values ('completed'::text,
            'a1760000-0000-4000-8000-000000000012'::uuid,
            'a1760000-0000-4000-8000-000000000012'::uuid,
            true, true)$$,
  'el ciclo dejó recepción, inicio, autor de término y limpió el bloqueo');
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task1')
      and type = 'smart_task_blocked'),
  'a1760000-0000-4000-8000-000000000011'::uuid,
  'el bloqueo del asignado notificó a la creadora, dirigida');
select is(
  (select count(*)::int from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task1')
      and type = 'smart_task_completed'),
  1, 'el término notificó a la creadora');

-- Si bloquea la manager, el aviso va al asignado — no a ella misma.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into tray_ctx
select 'task5', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Bloqueada por la jefa',
  'assigned_to', 'a1760000-0000-4000-8000-000000000012'
), 'tray-create-5')) #>> '{task,id}')::uuid;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task5'), null, 'block',
      jsonb_build_object('reason', 'Cliente pide esperar'), 'tray-block-5')$$,
  'la manager bloquea una tarea asignada');
reset role;
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task5')
      and type = 'smart_task_blocked'),
  'a1760000-0000-4000-8000-000000000012'::uuid,
  'el bloqueo de la manager notificó al asignado');

-- ============================================================================
-- Ruta directa legada: permitida para el ciclo del asignado, y AUDITADA
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$update public.smart_tasks set status = 'pending'
     where id = (select id from tray_ctx where key = 'task1')$$,
  'reabrir directo (toggle legado) sigue permitido al asignado');
select throws_ok(
  $$update public.smart_tasks set status = 'blocked'
     where id = (select id from tray_ctx where key = 'task1')$$,
  '23514', null,
  'una escritura directa no puede bloquear sin motivo: el guard también rige fuera de los RPC');
select lives_ok(
  $$update public.smart_tasks set status = 'completed'
     where id = (select id from tray_ctx where key = 'task1')$$,
  'volver a completar directo');

-- Tarea privada del mecánico.
insert into tray_ctx
select 'private1', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Comprar noodles',
  'visibility', 'private'
), 'tray-create-private')) #>> '{task,id}')::uuid;

reset role;

-- La ruta directa quedó en el ledger con source=direct.
select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from tray_ctx where key = 'task1')
      and event_type in ('reopened', 'completed')
      and payload ->> 'source' = 'direct'),
  2, 'los cambios directos legados quedaron auditados en el mismo ledger');

-- ============================================================================
-- RLS: privacidad, autoridad y aislamiento
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;

select is(
  (select count(*)::int from public.smart_tasks
    where id = (select id from tray_ctx where key = 'private1')),
  0, 'una tarea privada ajena no existe para terceros');
select is(
  (select count(*)::int from public.smart_tasks
    where id = (select id from tray_ctx where key = 'task1')),
  1, 'una tarea de equipo sí es visible para el resto del tenant');

create temp table tray_probe(affected int);
grant select, insert on tray_probe to authenticated;
with updated as (
  update public.smart_tasks set title = 'Hackeada'
   where id = (select id from tray_ctx where key = 'task1')
  returning 1
)
insert into tray_probe select count(*) from updated;

select throws_ok(
  $$delete from public.smart_tasks
     where id = (select id from tray_ctx where key = 'task1')$$,
  '42501', null,
  'el DELETE de cliente está revocado: la bandeja cancela, no borra');

select throws_ok(
  $$insert into public.smart_task_events (tenant_id, task_id, event_type, task_version)
    values ('a1760000-0000-4000-8000-000000000001',
            (select id from tray_ctx where key = 'task1'), 'completed', 99)$$,
  '42501', null,
  'nadie escribe el ledger de eventos por fuera de los comandos');

reset role;

select results_eq(
  'select coalesce(sum(affected), -1)::int from tray_probe',
  'values (0)',
  'un usuario sin autoridad no editó nada (0 filas, silencioso)');
select is(
  (select title from public.smart_tasks
    where id = (select id from tray_ctx where key = 'task1')),
  'Ajuste de cambios Trek 820', 'el título quedó intacto');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000015', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000015', true);
set local role authenticated;
select is(
  (select count(*)::int from public.smart_tasks
    where tenant_id = 'a1760000-0000-4000-8000-000000000001'),
  0, 'otro tenant no ve ninguna tarea');
select is(
  (select count(*)::int from public.smart_task_events
    where tenant_id = 'a1760000-0000-4000-8000-000000000001'),
  0, 'otro tenant no ve ningún evento');
reset role;

-- ============================================================================
-- Estado por usuario: visto/pin/snooze
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000012', true);
set local role authenticated;

select lives_ok(
  $$insert into public.smart_task_user_state (task_id, user_id, seen_at, seen_version, tenant_id)
    values ((select id from tray_ctx where key = 'task1'),
            'a1760000-0000-4000-8000-000000000012', now(), 7,
            'a1760000-0000-4000-8000-000000000001')$$,
  'el usuario marca visto lo suyo');
select throws_ok(
  $$insert into public.smart_task_user_state (task_id, user_id, seen_at, tenant_id)
    values ((select id from tray_ctx where key = 'task1'),
            'a1760000-0000-4000-8000-000000000013', now(),
            'a1760000-0000-4000-8000-000000000001')$$,
  '42501', null, 'nadie escribe el estado de otro usuario');

reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select is(
  (select count(*)::int from public.smart_task_user_state),
  0, 'el estado por usuario es privado: terceros no lo ven');
select throws_ok(
  $$insert into public.smart_task_user_state (task_id, user_id, seen_at, tenant_id)
    values ((select id from tray_ctx where key = 'private1'),
            'a1760000-0000-4000-8000-000000000013', now(),
            'a1760000-0000-4000-8000-000000000001')$$,
  '42501', null, 'no se marca visto lo que no se puede ver');
reset role;

-- ============================================================================
-- Directorio de asignación honesto y deduplicado
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

create temp table tray_directory as
select * from public.get_smart_task_assignment_directory_v1();

reset role;

select results_eq(
  $$select display_name, employee_id is null
      from tray_directory
      where user_id = 'a1760000-0000-4000-8000-000000000011'$$,
  $$values ('La Manager'::text, true)$$,
  'el owner corporativo conserva identidad de cuenta y no se finge trabajador');
select is(
  (select access from tray_directory
    where user_id = 'a1760000-0000-4000-8000-000000000012'),
  'erp', 'el mecánico ERP aparece como principal erp');
select is(
  (select access from tray_directory
    where user_id = 'a1760000-0000-4000-8000-000000000014'),
  'portal', 'el trabajador de portal aparece elegible');
select results_eq(
  $$select access, user_id is null from tray_directory
     where employee_id = 'a1760000-0000-4000-8000-000000000023'$$,
  $$values ('none'::text, true)$$,
  'la empleada sin cuenta aparece como no elegible, para Invitar');
select results_eq(
  $$select access, count(*)::int from tray_directory
     where employee_id = 'a1760000-0000-4000-8000-000000000024'
     group by access$$,
  $$values ('none'::text, 1)$$,
  'una empleada enlazada a usuario sin perfil aparece exactamente una vez, no elegible');
select is(
  (select count(*)::int from tray_directory),
  (select count(distinct coalesce(employee_id::text, user_id::text))::int
     from tray_directory),
  'un principal canónico por persona: sin duplicados');
select is(
  (select count(*)::int from tray_directory
    where tenant_id <> 'a1760000-0000-4000-8000-000000000001'),
  0, 'el directorio no cruza tenants');

-- ============================================================================
-- Portal del trabajador
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000014', true);
set local role authenticated;

select results_eq(
  $$select title, job_number, bike_labels
      from public.get_my_worker_tasks_v1()$$,
  $$values ('Mantención de motor Trek 820'::text, 'TRAY-JOB-1'::text,
            '["Giant Talon", "Trek 820"]'::jsonb)$$,
  'el portal ve su tarea con trabajo y TODAS las bicicletas de sus servicios');
select is(
  (select count(*)::int
     from public.get_my_worker_tasks_v1() task,
          jsonb_array_elements(task.job_items) item
    where item ? 'unit_price' or item ? 'total_price' or item ? 'adhoc_price'),
  0, 'la proyección del portal no expone precios');
select is(
  (select count(*)::int
     from public.get_my_worker_tasks_v1() task,
          jsonb_array_elements(task.job_items) item
    where nullif(btrim(item->>'item_instructions'), '') is not null),
  2, 'el portal recibe las instrucciones de todos sus servicios vinculados');
select is(
  (select count(*)::int from public.smart_tasks
    where assigned_to <> 'a1760000-0000-4000-8000-000000000014'),
  0, 'el portal solo alcanza sus propias tareas por cualquier vía');

select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from tray_ctx where key = 'task2'), null, 'acknowledge',
      '{}'::jsonb, 'tray-portal-ack')$$,
  'el portal acusa recibo');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from tray_ctx where key = 'task2'), null, 'start',
      '{}'::jsonb, 'tray-portal-start')$$,
  'el portal inicia');
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from tray_ctx where key = 'task2'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000014'),
      'tray-portal-assign')$$,
  '42501', null, 'el portal no asigna: superficie acotada');
select lives_ok(
  $$select public.worker_task_command_v1(
      (select id from tray_ctx where key = 'task2'), null, 'complete',
      '{}'::jsonb, 'tray-portal-complete')$$,
  'el portal completa');
select throws_ok(
  $$select public.worker_task_command_v1(
      (select id from tray_ctx where key = 'task1'), null, 'acknowledge',
      '{}'::jsonb, 'tray-portal-foreign')$$,
  '42501', null, 'el portal no toca tareas que no son suyas');

reset role;

select is(
  (select status from public.smart_tasks
    where id = (select id from tray_ctx where key = 'task2')),
  'completed', 'la tarea del portal quedó completada');

-- ============================================================================
-- Evidencia durable: borrar o editar la línea no borra el vínculo
-- ============================================================================

update public.mechanic_job_items
   set product_name = 'Mantención de motor (renombrada)'
 where id = 'a1760000-0000-4000-8000-000000000082';
select ok(
  (select context_changed_at is not null and invalidated_at is null
     from public.smart_task_job_items
    where job_item_id = 'a1760000-0000-4000-8000-000000000082'),
  'editar la línea marca context_changed_at sin invalidar');

update public.mechanic_job_items
   set notes = 'INSTRUCCIÓN ACTUALIZADA DESPUÉS DE ASIGNAR.'
 where id = 'a1760000-0000-4000-8000-000000000081';
select results_eq(
  $$select item_instructions, context_changed_at is not null
      from public.smart_task_job_items
     where job_item_id = 'a1760000-0000-4000-8000-000000000081'$$,
  $$values ('AJUSTAR CAMBIO TRASERO Y VERIFICAR TENSIÓN.'::text, true)$$,
  'editar instrucciones marca el contexto y preserva el snapshot asignado');

delete from public.mechanic_job_items
 where id = 'a1760000-0000-4000-8000-000000000085';
select results_eq(
  $$select item_name, invalidated_at is not null
      from public.smart_task_job_items
     where job_item_id = 'a1760000-0000-4000-8000-000000000085'$$,
  $$values ('Limpieza transmisión'::text, true)$$,
  'borrar la línea conserva el snapshot y marca la invalidación');

-- ============================================================================
-- Hilo por tarea: get-or-create server-owned, único y con participantes exactos
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

select is(
  public.smart_task_thread_v1((select id from tray_ctx where key = 'task1')),
  null, 'sin hilo todavía');
insert into tray_ctx
select 'thread1', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task1'))) ->> 'conversation_id')::uuid;
insert into tray_ctx
select 'thread1_root', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task1'))) ->> 'root_message_id')::uuid;
select is(
  (public.smart_task_thread_get_or_create_v1(
    (select id from tray_ctx where key = 'task1'))) ->> 'created',
  'false', 'la segunda llamada devuelve el mismo hilo, no otro');
select is(
  public.smart_task_thread_v1((select id from tray_ctx where key = 'task1')),
  (select id from tray_ctx where key = 'thread1'),
  'el hilo se consulta desde la tarea');

insert into public.messages (
  conversation_id, sender_id, tenant_id, content, type, metadata
) values (
  (select id from tray_ctx where key = 'thread1'),
  'a1760000-0000-4000-8000-000000000011',
  'a1760000-0000-4000-8000-000000000001',
  'Respuesta vinculada a la tarea',
  'text',
  jsonb_build_object(
    'thread_root_message_id',
    (select id from tray_ctx where key = 'thread1_root')
  )
);

reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread1')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'el canal de equipo incluye exactamente a los usuarios ERP activos');
select is(
  (select count(*)::int from public.conversation_contexts
    where context_type = 'task'
      and context_id = (select id from tray_ctx where key = 'task1')),
  1, 'el contexto task existe una sola vez en mensajería');
select is(
  (select thread_root_message_id from public.conversation_contexts
    where context_type = 'task'
      and context_id = (select id from tray_ctx where key = 'task1')),
  (select id from tray_ctx where key = 'thread1_root'),
  'la tarea conserva un mensaje raíz canónico');
select results_eq(
  $$select type, metadata->>'task_thread_root'
      from public.messages
     where id = (select id from tray_ctx where key = 'thread1_root')$$,
  $$values ('system'::text, 'true'::text)$$,
  'el mensaje raíz representa la tarea y no finge un comentario humano');
select is(
  (select thread_root_message_id from public.messages
    where content = 'Respuesta vinculada a la tarea'),
  (select id from tray_ctx where key = 'thread1_root'),
  'el metadata legado se normaliza a la relación durable de respuesta');

-- Una tarea de equipo se conversa en el canal compartido: cualquier miembro
-- ERP que ya puede verla también puede abrir su hilo exacto.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_thread_get_or_create_v1(
      (select id from tray_ctx where key = 'task1'))$$,
  'un miembro ERP abre el hilo visible del canal de equipo');
reset role;

-- Hilo de una tarea asignada a portal: sin participante fantasma; y al
-- reasignar a un principal ERP, se suma de forma segura.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into tray_ctx
select 'thread2', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task2'))) ->> 'conversation_id')::uuid;
reset role;
select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread2')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'el canal incluye a ERP y no finge al asignado de portal como principal');
select is(
  (select id from tray_ctx where key = 'thread2'),
  (select id from tray_ctx where key = 'thread1'),
  'dos tareas de equipo son raíces distintas dentro del mismo canal');

select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task2'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000012'),
      'tray-reassign-2')$$,
  'la manager reasigna la tarea del portal al mecánico ERP');
reset role;
select results_eq(
  $$select count(*)::int from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread2')
       and participant.user_id = 'a1760000-0000-4000-8000-000000000012'$$,
  'values (1)',
  'el nuevo responsable ERP entró al hilo al reasignar');
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task2')
      and type = 'smart_task_reassigned'),
  'a1760000-0000-4000-8000-000000000014'::uuid,
  'el responsable anterior fue avisado del traspaso');

-- ============================================================================
-- El INSERT directo legado (cliente antiguo, aprobación IA) también nace en
-- el ledger y notifica a su asignado
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

with created as (
  insert into public.smart_tasks (
    tenant_id, title, status, priority, assigned_to, created_by,
    assigned_at, assigned_by, acknowledged_at, acknowledged_by,
    started_at, completed_at, completed_by, cancelled_at, cancelled_by,
    blocked_at, blocked_by, blocked_reason
  ) values (
    'a1760000-0000-4000-8000-000000000001',
    'Insert directo legado', 'pending', 'normal',
    'a1760000-0000-4000-8000-000000000012',
    'a1760000-0000-4000-8000-000000000011',
    '2000-01-01 UTC', 'a1760000-0000-4000-8000-000000000013',
    '2000-01-01 UTC', 'a1760000-0000-4000-8000-000000000013',
    '2000-01-01 UTC', '2000-01-01 UTC',
    'a1760000-0000-4000-8000-000000000013', '2000-01-01 UTC',
    'a1760000-0000-4000-8000-000000000013', '2000-01-01 UTC',
    'a1760000-0000-4000-8000-000000000013', 'motivo falsificado'
  ) returning id
)
insert into tray_ctx select 'task8', id from created;

reset role;

select is(
  (select count(*)::int from public.smart_task_events
    where task_id = (select id from tray_ctx where key = 'task8')
      and event_type in ('created', 'assigned')
      and payload ->> 'source' = 'direct'),
  2, 'un insert directo también deja created+assigned en el ledger');
select is(
  (select recipient_user_id from public.erp_notifications
    where entity_type = 'smart_task'
      and entity_id = (select id from tray_ctx where key = 'task8')
      and type = 'smart_task_assigned'),
  'a1760000-0000-4000-8000-000000000012'::uuid,
  'la asignación por insert directo notifica al asignado');
select results_eq(
  $$select assigned_by,
           assigned_at > now() - interval '1 minute',
           acknowledged_at is null and acknowledged_by is null,
           started_at is null,
           completed_at is null and completed_by is null,
           cancelled_at is null and cancelled_by is null,
           blocked_at is null and blocked_by is null and blocked_reason is null
      from public.smart_tasks
     where id = (select id from tray_ctx where key = 'task8')$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid,
            true, true, true, true, true, true)$$,
  'el INSERT directo no puede falsificar autores ni sellos de auditoría');

-- La escritura legacy debe tocar una fila real: esta regresión vive después
-- de sembrar task8 para que un UPDATE de cero filas no produzca un falso verde.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$update public.smart_tasks
       set assigned_at = '2000-01-01 UTC',
           assigned_by = 'a1760000-0000-4000-8000-000000000013',
           acknowledged_at = '2000-01-01 UTC',
           acknowledged_by = 'a1760000-0000-4000-8000-000000000013',
           completed_at = '2000-01-01 UTC',
           completed_by = 'a1760000-0000-4000-8000-000000000013'
     where id = (select id from tray_ctx where key = 'task8')$$,
  'una escritura legada puede convivir con columnas nuevas desconocidas');
reset role;
select results_eq(
  $$select assigned_by,
           assigned_at > now() - interval '1 minute',
           acknowledged_at is null and acknowledged_by is null,
           completed_at is null and completed_by is null
      from public.smart_tasks
     where id = (select id from tray_ctx where key = 'task8')$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid,
            true, true, true)$$,
  'el UPDATE directo tampoco puede reescribir evidencia server-owned');

-- Tampoco puede enlazar un trabajo de otro tenant aunque conozca su UUID.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$insert into public.smart_tasks (
      tenant_id, title, status, priority, linked_job_id, created_by
    ) values (
      'a1760000-0000-4000-8000-000000000001',
      'Pega ajena directa', 'pending', 'normal',
      'a1760000-0000-4000-8000-000000000062',
      'a1760000-0000-4000-8000-000000000011'
    )$$,
  '23503', null,
  'la ruta directa rechaza un trabajo ajeno o archivado');
reset role;

-- ============================================================================
-- El hilo sigue al trabajo: el exresponsable sale al reasignar o devolver
-- (salvo creador o manager); su historial permanece
-- ============================================================================

select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
insert into tray_ctx
select 'task9', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Hilo que sigue al trabajo',
  'assigned_to', 'a1760000-0000-4000-8000-000000000012'
), 'tray-create-9')) #>> '{task,id}')::uuid;
insert into tray_ctx
select 'thread9', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task9'))) ->> 'conversation_id')::uuid;
reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread9')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'otra raíz de tarea reutiliza el canal de todos los usuarios ERP activos');

select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task9'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000013'),
      'tray-reassign-9')$$,
  'la manager traspasa la tarea al cajero');
reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread9')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'reasignar no altera la audiencia estable del canal de equipo');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task9'), null, 'return',
      jsonb_build_object('reason', 'No alcanzo esta semana'),
      'tray-return-9')$$,
  'el cajero devuelve la tarea');
reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread9')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'devolver una tarea tampoco convierte el canal compartido en un chat privado');

-- ============================================================================
-- Un supervisor autorizado entra al hilo existente; y la reasignación por
-- ruta DIRECTA también sincroniza participantes
-- ============================================================================

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
insert into tray_ctx
select 'task10', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Hilo con supervisor tardío',
  'assigned_to', 'a1760000-0000-4000-8000-000000000012'
), 'tray-create-10')) #>> '{task,id}')::uuid;
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000012', true);
set local role authenticated;
insert into tray_ctx
select 'thread10', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task10'))) ->> 'conversation_id')::uuid;
reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread10')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'el hilo nace como otra raíz del mismo canal de equipo');

-- La manager (autorizada, no participante) lo abre después: entra.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select is(
  (public.smart_task_thread_get_or_create_v1(
    (select id from tray_ctx where key = 'task10'))) ->> 'created',
  'false', 'el hilo existente no se duplica al abrirlo la manager');
reset role;

select is(
  (select count(*)::int from public.conversation_participants participant
    where participant.conversation_id = (select id from tray_ctx where key = 'thread10')
      and participant.user_id = 'a1760000-0000-4000-8000-000000000011'),
  1, 'la manager autorizada quedó dentro del hilo existente');

-- Reasignación por RUTA DIRECTA (cliente legado): el hilo también sigue.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$update public.smart_tasks
       set assigned_to = 'a1760000-0000-4000-8000-000000000013'
     where id = (select id from tray_ctx where key = 'task10')$$,
  'la manager reasigna por escritura directa legada');
reset role;

select results_eq(
  $$select participant.user_id from public.conversation_participants participant
     where participant.conversation_id = (select id from tray_ctx where key = 'thread10')
     order by participant.user_id$$,
  $$values ('a1760000-0000-4000-8000-000000000011'::uuid),
           ('a1760000-0000-4000-8000-000000000012'::uuid),
           ('a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'la reasignación directa preserva la audiencia completa del canal');

-- Una tarea privada vive en el canal personal de su creador. Al cambiar su
-- visibilidad, la misma raíz y todas sus respuestas cambian de audiencia; no
-- se duplica la conversación ni se pierde el hilo.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
insert into tray_ctx
select 'task12', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Recordatorio personal',
  'visibility', 'private'
), 'tray-create-12')) #>> '{task,id}')::uuid;
insert into tray_ctx
select 'thread12', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task12'))) ->> 'conversation_id')::uuid;
insert into tray_ctx
select 'thread12_root', ((public.smart_task_thread_get_or_create_v1(
  (select id from tray_ctx where key = 'task12'))) ->> 'root_message_id')::uuid;
reset role;

select isnt(
  (select id from tray_ctx where key = 'thread12'),
  (select id from tray_ctx where key = 'thread1'),
  'el canal personal no comparte audiencia con el canal del equipo');
select results_eq(
  $$select conversation.title, participant.user_id
      from public.conversations conversation
      join public.conversation_participants participant
        on participant.conversation_id = conversation.id
     where conversation.id = (select id from tray_ctx where key = 'thread12')$$,
  $$values ('Mis tareas'::text,
            'a1760000-0000-4000-8000-000000000013'::uuid)$$,
  'el canal personal incluye sólo a su dueño');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_thread_get_or_create_v1(
      (select id from tray_ctx where key = 'task12'))$$,
  '42501', null,
  'ni un manager abre una tarea privada de otra persona');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task12'), null,
      'set_visibility', jsonb_build_object('visibility', 'team'),
      'tray-publish-12')$$,
  'el dueño publica su recordatorio al equipo');
reset role;

select is(
  public.smart_task_thread_v1((select id from tray_ctx where key = 'task12')),
  (select id from tray_ctx where key = 'thread1'),
  'publicar mueve la raíz al canal compartido');
select is(
  (select thread_root_message_id
     from public.conversation_contexts
    where context_type = 'task'
      and context_id = (select id from tray_ctx where key = 'task12')),
  (select id from tray_ctx where key = 'thread12_root'),
  'el cambio de audiencia conserva exactamente el mismo mensaje raíz');

-- ============================================================================
-- Contrato de Nota: pending ↔ cancelled (Archivar/Restaurar), nunca el ciclo
-- de tarea; conserva su trabajo. Y `private` es personal de verdad.
-- ============================================================================

select ok(
  not has_function_privilege('authenticated',
    'public.smart_task_assignee_eligible_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_assignee_eligible_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.smart_task_assignee_worker_linked_v1(uuid,uuid)', 'EXECUTE'),
  'los helpers de elegibilidad son internos del kernel: sin EXECUTE de cliente');
select ok(exists (
  select 1 from pg_constraint
  where conname = 'smart_tasks_private_is_personal_check'
    and conrelid = 'public.smart_tasks'::regclass
), 'private implica sin responsable y sin trabajo, a nivel de base');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;

-- Una nota puede asociarse al trabajo (sin servicios ni responsable).
insert into tray_ctx
select 'note1', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Nota general del taller',
  'task_kind', 'note',
  'linked_job_id', 'a1760000-0000-4000-8000-000000000061'
), 'tray-create-note1')) #>> '{task,id}')::uuid;

select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'note1'), null, 'complete',
      '{}'::jsonb, 'tray-note-complete')$$,
  '23514', null, 'una nota no se completa: no tiene ciclo de tarea');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'note1'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000012'),
      'tray-note-assign')$$,
  '23514', null, 'una nota no se asigna');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'note1'), null, 'start',
      '{}'::jsonb, 'tray-note-start')$$,
  '23514', null, 'una nota no se inicia');
select throws_ok(
  $$update public.smart_tasks set status = 'completed'
     where id = (select id from tray_ctx where key = 'note1')$$,
  '23514', null,
  'ni la ruta directa legada puede completar una nota');

select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'note1'), null, 'cancel',
      '{}'::jsonb, 'tray-note-archive')$$,
  'Archivar nota (cancelled)');
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'note1'), null, 'reopen',
      '{}'::jsonb, 'tray-note-restore')$$,
  'Restaurar nota (pending)');

reset role;

select results_eq(
  $$select task.status, task.task_kind,
           (select count(*)::int from public.smart_task_events event
             where event.task_id = task.id
               and event.event_type in ('cancelled', 'reopened'))
      from public.smart_tasks task
     where task.id = (select id from tray_ctx where key = 'note1')$$,
  $$values ('pending'::text, 'note'::text, 2)$$,
  'la nota volvió a pending, sigue siendo nota y su archivo quedó en el ledger');
select is(
  (select linked_job_id from public.smart_tasks
    where id = (select id from tray_ctx where key = 'note1')),
  'a1760000-0000-4000-8000-000000000061'::uuid,
  'la nota conserva su asociación al trabajo');

-- Una nota conserva el trabajo, nunca sus servicios; y una nota jamás reserva
-- trabajo (overlaps/traspaso miran solo tareas).
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Nota con servicios',
      'task_kind', 'note',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061',
      'job_item_ids', jsonb_build_array('a1760000-0000-4000-8000-000000000081')
    ), 'tray-note-services')$$,
  '23514', null, 'una nota no puede vincular servicios');
reset role;
select throws_ok(
  $$insert into public.smart_task_job_items (task_id, job_item_id, tenant_id, job_id, item_name)
    values ((select id from tray_ctx where key = 'note1'),
            'a1760000-0000-4000-8000-000000000081',
            'a1760000-0000-4000-8000-000000000001',
            'a1760000-0000-4000-8000-000000000061', 'x')$$,
  '23514', null,
  'la tabla puente también rechaza servicios en una nota, incluso a escritores internos');
select ok(
  position($guard$task.task_kind = 'task'$guard$ in pg_get_functiondef(
    'public.smart_task_active_overlaps(uuid,uuid[],uuid)'::regprocedure)) > 0
  and position($guard$task.task_kind = 'task'$guard$ in pg_get_functiondef(
    'public.smart_task_transfer_overlaps(uuid,uuid,uuid,uuid[])'::regprocedure)) > 0,
  'solape y traspaso consideran solo tareas: una nota no reserva trabajo');

-- private es personal: ni al crear ni por comando puede cargar gente o trabajo.
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Privada con responsable',
      'visibility', 'private',
      'assigned_to', 'a1760000-0000-4000-8000-000000000012'
    ), 'tray-private-assigned')$$,
  '23514', null, 'una privada no puede nacer con responsable');
select throws_ok(
  $$select public.smart_task_create_v1(jsonb_build_object(
      'title', 'Privada con trabajo',
      'visibility', 'private',
      'linked_job_id', 'a1760000-0000-4000-8000-000000000061'
    ), 'tray-private-job')$$,
  '23514', null, 'una privada no puede nacer con trabajo');
select throws_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task5'), null, 'set_visibility',
      jsonb_build_object('visibility', 'private'), 'tray-private-switch')$$,
  '23514', null,
  'una tarea con responsable no puede volverse privada');
reset role;

-- ============================================================================
-- El portal dice quién LE ASIGNÓ: assigner_name viene de assigned_by, no del
-- creador (que queda solo como fallback legacy cuando assigned_by es null)
-- ============================================================================

-- El cajero crea sin asignar; la MANAGER asigna al portal: dos personas
-- distintas, y la que debe verse es la manager.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
insert into tray_ctx
select 'task11', ((public.smart_task_create_v1(jsonb_build_object(
  'title', 'Asignada por otra persona'
), 'tray-create-11')) #>> '{task,id}')::uuid;
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011', true);
set local role authenticated;
select lives_ok(
  $$select public.smart_task_command_v1(
      (select id from tray_ctx where key = 'task11'), null, 'assign',
      jsonb_build_object('assigned_to', 'a1760000-0000-4000-8000-000000000014'),
      'tray-assign-11')$$,
  'la manager asigna al portal la tarea creada por el cajero');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000014', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000014', true);
set local role authenticated;
create temp table tray_assigner as
select projection.creator_name, projection.assigner_name
from public.get_my_worker_tasks_v1() projection
where projection.id = (select id from tray_ctx where key = 'task11');
reset role;

select results_eq(
  $$select assigner_name is not null,
           assigner_name is distinct from creator_name,
           assigner_name = public.erp_actor_display_name(
             'a1760000-0000-4000-8000-000000000011'::uuid,
             'a1760000-0000-4000-8000-000000000001'::uuid)
      from tray_assigner$$,
  $$values (true, true, true)$$,
  'el portal muestra a quien ASIGNÓ (la manager), no al creador');

-- ============================================================================
-- Broadcast legado intacto; lo dirigido no se filtra a terceros
-- ============================================================================

insert into public.erp_notifications (tenant_id, type, title, severity)
values ('a1760000-0000-4000-8000-000000000001', 'legacy_broadcast',
        'Aviso general', 'info');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1760000-0000-4000-8000-000000000013', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000013', true);
set local role authenticated;
select is(
  (select count(*)::int from public.erp_notifications
    where type = 'legacy_broadcast'),
  1, 'el broadcast legado sigue visible para cualquier miembro');
select is(
  (select count(*)::int from public.erp_notifications
    where entity_type = 'smart_task'
      and recipient_user_id is distinct from
        'a1760000-0000-4000-8000-000000000013'::uuid),
  0, 'ninguna notificación dirigida a otros aparece en mi campana');
select lives_ok(
  $$update public.erp_notifications set read_at = now()
     where type = 'legacy_broadcast'$$,
  'el cliente conserva la única mutación legítima: marcar read_at');
select throws_ok(
  $$update public.erp_notifications
       set recipient_user_id = 'a1760000-0000-4000-8000-000000000013'
     where type = 'legacy_broadcast'$$,
  '42501', null,
  'un cliente no puede convertir un broadcast en aviso privado');
reset role;

select * from finish();
rollback;
