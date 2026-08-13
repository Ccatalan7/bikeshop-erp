begin;

select no_plan();

select has_function('public', 'assistant_get_business_snapshot_v1',
  array['text'], 'general business snapshot RPC exists');
select ok((select function.prosecdef
    and function.proconfig @> array[
      'search_path=pg_catalog, public, pg_temp',
      'statement_timeout=4500ms'
    ]::text[]
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'assistant_get_business_snapshot_v1'),
  'snapshot fixes search_path and a database-side timeout');
select ok(has_function_privilege('authenticated',
    'public.assistant_get_business_snapshot_v1(text)', 'EXECUTE')
    and not has_function_privilege('anon',
      'public.assistant_get_business_snapshot_v1(text)', 'EXECUTE')
    and not has_function_privilege('service_role',
      'public.assistant_get_business_snapshot_v1(text)', 'EXECUTE'),
  'snapshot is caller-JWT only');

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1720000-0000-4000-8000-000000000001', 'Snapshot tenant A',
   'snapshot-a@example.invalid', 'America/Santiago'),
  ('a1720000-0000-4000-8000-000000000002', 'Snapshot tenant B',
   'snapshot-b@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1720000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'snapshot-cashier@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  ('a1720000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'snapshot-mechanic@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values
  ('a1720000-0000-4000-8000-000000000011',
   'a1720000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb),
  ('a1720000-0000-4000-8000-000000000012',
   'a1720000-0000-4000-8000-000000000002', 'mechanic', '{}'::jsonb);

-- Tenant bootstrap seeds payment methods under a synthetic tenant claim. Use
-- the real tenant-A fixture user for subsequent audit-triggered business rows.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1720000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1720000-0000-4000-8000-000000000011', true);

insert into public.customers (id, tenant_id, name, is_active)
values (
  'a1720000-0000-4000-8000-000000000101',
  'a1720000-0000-4000-8000-000000000001',
  'Nombre que nunca debe salir', true
);

insert into public.products (
  id, tenant_id, name, sku, inventory_qty, stock_quantity, min_stock_level,
  track_stock, is_service, purchase_treatment, is_active
) values
  ('a1720000-0000-4000-8000-000000000201',
   'a1720000-0000-4000-8000-000000000001', 'Producto secreto sin stock',
   'SNAP-OUT', 0, 0, 2, true, false, 'inventory', true),
  ('a1720000-0000-4000-8000-000000000202',
   'a1720000-0000-4000-8000-000000000001', 'Producto secreto bajo',
   'SNAP-LOW', 1, 1, 2, true, false, 'inventory', true);

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, arrival_date, deadline,
  status, priority, client_request, requires_approval,
  approved_by_customer
) values
  ('a1720000-0000-4000-8000-000000000301',
   'a1720000-0000-4000-8000-000000000001', 'PG-SNAPSHOT-1',
   'a1720000-0000-4000-8000-000000000101', null, now(), now(),
   'PENDIENTE', 'URGENTE', 'Texto privado', true, false),
  ('a1720000-0000-4000-8000-000000000302',
   'a1720000-0000-4000-8000-000000000001', 'PG-SNAPSHOT-2',
   'a1720000-0000-4000-8000-000000000101', null, now(),
   now() - interval '2 days', 'PENDIENTE', 'NORMAL', 'Texto atrasado',
   false, false);

insert into public.smart_tasks (
  id, tenant_id, title, description, status, priority, due_date, assigned_to
) values
  ('a1720000-0000-4000-8000-000000000401',
   'a1720000-0000-4000-8000-000000000001', 'Tarea privada urgente',
   'Descripción privada', 'pending', 'urgent', now(),
   'a1720000-0000-4000-8000-000000000011'),
  ('a1720000-0000-4000-8000-000000000402',
   'a1720000-0000-4000-8000-000000000001', 'Tarea privada atrasada',
   null, 'in_progress', 'normal', now() - interval '2 days', null);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1720000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1720000-0000-4000-8000-000000000011', true);
set local role authenticated;

create temp table snapshot_a as
select public.assistant_get_business_snapshot_v1('today') payload;

select is((select payload->>'authorityTenantId' from snapshot_a),
  'a1720000-0000-4000-8000-000000000001',
  'snapshot derives its tenant from the caller');
select is((select payload->>'status' from snapshot_a), 'success',
  'closed three-source snapshot succeeds');
select is((select payload->>'resultCount' from snapshot_a), '3',
  'snapshot returns exactly the three reviewed operational sources');
select is((select payload#>>'{items,0,source}' from snapshot_a),
  'workshop_jobs', 'workshop is the first stable source');
select is((select payload#>>'{items,0,openCount}' from snapshot_a), '2',
  'workshop snapshot counts active jobs');
select is((select payload#>>'{items,0,overdueCount}' from snapshot_a), '1',
  'workshop snapshot counts overdue jobs at tenant business date');
select is((select payload#>>'{items,0,urgentCount}' from snapshot_a), '1',
  'workshop snapshot counts urgent jobs');
select is((select payload#>>'{items,0,awaitingApprovalCount}' from snapshot_a),
  '1', 'workshop snapshot counts pending customer approvals');
select is((select payload#>>'{items,1,assignedToMeCount}' from snapshot_a),
  '1', 'task snapshot counts only assignments to the caller');
select is((select payload#>>'{items,2,trackedItemCount}' from snapshot_a),
  '2', 'inventory snapshot counts reviewed tracked products');
select is((select payload#>>'{items,2,lowStockCount}' from snapshot_a),
  '1', 'inventory snapshot separates low stock');
select is((select payload#>>'{items,2,outOfStockCount}' from snapshot_a),
  '1', 'inventory snapshot separates out of stock');
select ok((select bool_and(
    (select array_agg(key order by key)
     from jsonb_object_keys(item) key) = array[
       'assignedToMeCount','awaitingApprovalCount','dueInHorizonCount',
       'horizon','lowStockCount','openCount','outOfStockCount',
       'overdueCount','source','sourceStatus','trackedItemCount','urgentCount'
     ]::text[])
  from snapshot_a,
  lateral jsonb_array_elements(payload->'items') item),
  'every source item has the same exact closed scalar projection');
select ok((select payload::text not like '%Nombre que nunca%'
    and payload::text not like '%Producto secreto%'
    and payload::text not like '%Texto privado%'
    and payload::text not like '%Tarea privada%'
  from snapshot_a),
  'snapshot exposes no names, row identifiers or free text');
select throws_ok(
  $$select public.assistant_get_business_snapshot_v1(null)$$,
  '22023', 'Invalid AI tool arguments', 'null snapshot horizon is rejected');
select throws_ok(
  $$select public.assistant_get_business_snapshot_v1('month')$$,
  '22023', 'Invalid AI tool arguments', 'unbounded snapshot horizon is rejected');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1720000-0000-4000-8000-000000000012',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1720000-0000-4000-8000-000000000012', true);
set local role authenticated;

create temp table snapshot_b as
select public.assistant_get_business_snapshot_v1('next_7_days') payload;
select is((select payload->>'authorityTenantId' from snapshot_b),
  'a1720000-0000-4000-8000-000000000002',
  'second role remains bound to its own tenant');
select ok((select bool_and(item->>'sourceStatus' = 'verifiedEmpty')
  from snapshot_b, lateral jsonb_array_elements(payload->'items') item),
  'a valid empty tenant reports per-source verifiedEmpty rather than unavailable');
select ok((select bool_and(
    case item->>'source'
      when 'workshop_jobs' then
        (item->>'openCount')::bigint = 0
        and (item->>'overdueCount')::bigint = 0
        and (item->>'dueInHorizonCount')::bigint = 0
        and (item->>'urgentCount')::bigint = 0
        and (item->>'awaitingApprovalCount')::bigint = 0
        and item->'assignedToMeCount' = 'null'::jsonb
        and item->'trackedItemCount' = 'null'::jsonb
        and item->'lowStockCount' = 'null'::jsonb
        and item->'outOfStockCount' = 'null'::jsonb
      when 'tasks' then
        (item->>'openCount')::bigint = 0
        and (item->>'overdueCount')::bigint = 0
        and (item->>'dueInHorizonCount')::bigint = 0
        and (item->>'urgentCount')::bigint = 0
        and (item->>'assignedToMeCount')::bigint = 0
        and item->'awaitingApprovalCount' = 'null'::jsonb
        and item->'trackedItemCount' = 'null'::jsonb
        and item->'lowStockCount' = 'null'::jsonb
        and item->'outOfStockCount' = 'null'::jsonb
      when 'inventory' then
        (item->>'trackedItemCount')::bigint = 0
        and (item->>'lowStockCount')::bigint = 0
        and (item->>'outOfStockCount')::bigint = 0
        and item->'openCount' = 'null'::jsonb
        and item->'overdueCount' = 'null'::jsonb
        and item->'dueInHorizonCount' = 'null'::jsonb
        and item->'urgentCount' = 'null'::jsonb
        and item->'awaitingApprovalCount' = 'null'::jsonb
        and item->'assignedToMeCount' = 'null'::jsonb
      else false
    end
  ) from snapshot_b, lateral jsonb_array_elements(payload->'items') item),
  'verified-empty sources return zeros only for applicable metrics and null otherwise');
select ok((select bool_and(
    coalesce((item->>'openCount')::bigint, 0) = 0
    and coalesce((item->>'trackedItemCount')::bigint, 0) = 0)
  from snapshot_b, lateral jsonb_array_elements(payload->'items') item),
  'second tenant cannot aggregate first-tenant operations');
reset role;

select * from finish();
rollback;
