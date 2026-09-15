begin;

select no_plan();

select has_function('public', 'assistant_query_workshop_jobs_v2',
  array['text','text','text','text','integer'],
  'filtered workshop query RPC exists');
select has_function('public', 'assistant_query_tasks_v2',
  array['text','text','text','text','text','integer'],
  'filtered task query RPC exists');
select ok((select bool_and(function.prosecdef
      and function.proconfig @> array[
        'search_path=pg_catalog, public, pg_temp',
        'statement_timeout=4500ms'
      ]::text[])
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname in (
      'assistant_query_workshop_jobs_v2', 'assistant_query_tasks_v2'
    )), 'filtered operational RPCs fix search_path and DB timeout');
select ok((select bool_and(
    has_function_privilege('authenticated', function.oid, 'EXECUTE')
    and not has_function_privilege('anon', function.oid, 'EXECUTE')
    and not has_function_privilege('service_role', function.oid, 'EXECUTE'))
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname in (
      'assistant_query_workshop_jobs_v2', 'assistant_query_tasks_v2'
    )), 'filtered operational RPCs remain caller-JWT only');

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1730000-0000-4000-8000-000000000001', 'Filtered tenant A',
   'filtered-a@example.invalid', 'America/Santiago'),
  ('a1730000-0000-4000-8000-000000000002', 'Filtered tenant B',
   'filtered-b@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1730000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'filtered-cashier@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  ('a1730000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'filtered-mechanic@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  ('a1730000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'filtered-other@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values
  ('a1730000-0000-4000-8000-000000000011',
   'a1730000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb),
  ('a1730000-0000-4000-8000-000000000012',
   'a1730000-0000-4000-8000-000000000002', 'mechanic', '{}'::jsonb);

insert into public.customers (id, tenant_id, name, is_active)
values
  ('a1730000-0000-4000-8000-000000000101',
   'a1730000-0000-4000-8000-000000000001', 'Claudia Filtro', true),
  ('a1730000-0000-4000-8000-000000000102',
   'a1730000-0000-4000-8000-000000000002', 'Cliente Vecino', true);

insert into public.job_statuses (
  id, tenant_id, name, code, phase, sort_order, is_system, is_active
) values (
  'a1730000-0000-4000-8000-000000000111',
  'a1730000-0000-4000-8000-000000000001',
  'Cancelled custom', 'CANCELLED', 'complete', 90, false, true
);

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, arrival_date, deadline,
  status, status_id, priority, client_request, assigned_technician_name,
  completed_at
) values
  ('a1730000-0000-4000-8000-000000000201',
   'a1730000-0000-4000-8000-000000000001', 'PG-FILTER-URGENT',
   'a1730000-0000-4000-8000-000000000101', null, now(),
   now() - interval '2 days', 'PENDIENTE', null, 'URGENTE', 'Ajustar frenos',
   'Nombre privado del técnico', null),
  ('a1730000-0000-4000-8000-000000000202',
   'a1730000-0000-4000-8000-000000000001', 'PG-FILTER-TODAY',
   'a1730000-0000-4000-8000-000000000101', null, now(), now(),
   'PENDIENTE', null, 'NORMAL', 'Cambiar transmisión', null, null),
  ('a1730000-0000-4000-8000-000000000203',
   'a1730000-0000-4000-8000-000000000001', 'PG-FILTER-DONE',
   'a1730000-0000-4000-8000-000000000101', null, now(),
   now() - interval '3 days', 'FINALIZADO', null, 'URGENTE', 'Ya terminado',
   null, now() - interval '1 day'),
  ('a1730000-0000-4000-8000-000000000205',
   'a1730000-0000-4000-8000-000000000001', 'PG-FILTER-CANCELLED',
   'a1730000-0000-4000-8000-000000000101', null, now(),
   now() - interval '4 days', 'PENDIENTE',
   'a1730000-0000-4000-8000-000000000111', 'NORMAL',
   'Cancelado por catálogo', null, null),
  ('a1730000-0000-4000-8000-000000000204',
   'a1730000-0000-4000-8000-000000000002', 'PG-NEIGHBOR-SECRET',
   'a1730000-0000-4000-8000-000000000102', null, now(),
   now() - interval '1 day', 'PENDIENTE', null, 'URGENTE', 'No filtrar afuera',
   null, null);

insert into public.smart_tasks (
  id, tenant_id, title, description, status, priority, due_date, assigned_to
) values
  ('a1730000-0000-4000-8000-000000000301',
   'a1730000-0000-4000-8000-000000000001', 'Cobrar retiro urgente',
   'Tarea vencida propia', 'pending', 'urgent', now() - interval '2 days',
   'a1730000-0000-4000-8000-000000000011'),
  ('a1730000-0000-4000-8000-000000000302',
   'a1730000-0000-4000-8000-000000000001', 'Preparar repuestos',
   'Tarea de hoy sin asignar', 'in_progress', 'high', now(), null),
  ('a1730000-0000-4000-8000-000000000303',
   'a1730000-0000-4000-8000-000000000001', 'Confirmar entrega',
   'Tarea de mañana ajena', 'pending', 'normal', now() + interval '1 day',
   'a1730000-0000-4000-8000-000000000013'),
  ('a1730000-0000-4000-8000-000000000304',
   'a1730000-0000-4000-8000-000000000002', 'Tarea vecina secreta',
   null, 'pending', 'urgent', now() - interval '1 day',
   'a1730000-0000-4000-8000-000000000012');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1730000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1730000-0000-4000-8000-000000000011', true);
set local role authenticated;

create temp table filtered_overdue_job as
select public.assistant_query_workshop_jobs_v2(
  null, 'overdue', 'open', 'urgent', 10
) payload;
select is((select payload->>'resultCount' from filtered_overdue_job), '1',
  'urgent overdue open workshop work needs no keyword phrase');
select is((select payload#>>'{items,0,entityId}' from filtered_overdue_job),
  'a1730000-0000-4000-8000-000000000201',
  'workshop item returns its tenant-validated entity reference');
select is((select payload#>>'{items,0,assignedTechnicianName}'
  from filtered_overdue_job), null::text,
  'filtered workshop result does not infer or expose staff identity');
select is((select array_agg(key order by key)
  from filtered_overdue_job,
  lateral jsonb_object_keys(payload#>'{items,0}') key),
  array['arrivalDate','assignedTechnicianName','clientRequest',
    'customerName','deliveryDeadline','entityId','jobNumber','priority',
    'status']::text[],
  'filtered workshop projection has only exact reviewed fields');
select is(public.assistant_query_workshop_jobs_v2(
  '', 'overdue', 'completed', 'urgent', 10
)->>'resultCount', '1',
  'completed lifecycle filter is independent from keyword search');
select is(public.assistant_query_workshop_jobs_v2(
  null, 'any', 'cancelled', 'any', 10
)#>>'{items,0,entityId}', 'a1730000-0000-4000-8000-000000000205',
  'canonical custom status code wins over stale legacy status text');
select is(public.assistant_query_workshop_jobs_v2(
  'transmisión', 'today', 'open', 'any', 10
)->>'resultCount', '1',
  'optional keyword and closed workshop filters compose');
select is(public.assistant_query_workshop_jobs_v2(
  null, 'any', 'any', 'any', 10
)->>'resultCount', '4',
  'workshop query never crosses into another tenant');
select is(public.assistant_query_workshop_jobs_v2(
  null, 'any', 'any', 'any', 1
)->>'hasMore', 'true',
  'workshop result truthfully signals a bounded continuation');

create temp table filtered_my_task as
select public.assistant_query_tasks_v2(
  null, 'overdue', 'pending', 'urgent', 'me', 10
) payload;
select is((select payload->>'resultCount' from filtered_my_task), '1',
  'my overdue urgent tasks need no keyword phrase');
select is((select payload#>>'{items,0,entityId}' from filtered_my_task),
  'a1730000-0000-4000-8000-000000000301',
  'task item returns its tenant-validated entity reference');
select is((select payload#>>'{items,0,assigneeName}' from filtered_my_task),
  'Tú', 'task output labels only the authenticated caller');
select is((select array_agg(key order by key)
  from filtered_my_task,
  lateral jsonb_object_keys(payload#>'{items,0}') key),
  array['assigneeName','dueDate','entityId','linkedContext','priority','status',
    'title']::text[],
  'filtered task projection has only exact reviewed fields');
select is(public.assistant_query_tasks_v2(
  null, 'today', 'in_progress', 'high', 'unassigned', 10
)->>'resultCount', '1',
  'unassigned tasks today are expressible as closed filters');
select is(public.assistant_query_tasks_v2(
  null, 'tomorrow', 'pending', 'normal', 'any', 10
)->>'resultCount', '1',
  'tomorrow task filter works without exposing another assignee');
select is(public.assistant_query_tasks_v2(
  null, 'any', 'any', 'any', 'any', 10
)->>'resultCount', '3',
  'task query never crosses into another tenant');
select is(public.assistant_query_tasks_v2(
  null, 'any', 'any', 'any', 'any', 1
)->>'hasMore', 'true',
  'task result truthfully signals a bounded continuation');

select throws_ok($$select public.assistant_query_workshop_jobs_v2(
  null, null, 'open', 'urgent', 10
)$$, '22023', 'Invalid AI tool arguments',
  'null workshop horizon is rejected');
select throws_ok($$select public.assistant_query_workshop_jobs_v2(
  null, 'month', 'open', 'urgent', 10
)$$, '22023', 'Invalid AI tool arguments',
  'unbounded workshop horizon is rejected');
select throws_ok($$select public.assistant_query_tasks_v2(
  null, 'today', 'pending', 'urgent', 'other_staff', 10
)$$, '22023', 'Invalid AI tool arguments',
  'task assignee filter cannot probe another staff member');
select throws_ok($$select public.assistant_query_tasks_v2(
  null, 'today', 'pending', 'urgent', 'me', null
)$$, '22023', 'Invalid AI tool arguments',
  'null task limit is rejected');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1730000-0000-4000-8000-000000000012',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1730000-0000-4000-8000-000000000012', true);
set local role authenticated;
select is(public.assistant_query_workshop_jobs_v2(
  null, 'overdue', 'open', 'urgent', 10
) #>> '{items,0,entityId}',
  'a1730000-0000-4000-8000-000000000204',
  'second role receives only its own tenant workshop entity');
select is(public.assistant_query_tasks_v2(
  null, 'overdue', 'pending', 'urgent', 'me', 10
) #>> '{items,0,entityId}',
  'a1730000-0000-4000-8000-000000000304',
  'second role receives only its own tenant task entity');
reset role;

select * from finish();
rollback;
