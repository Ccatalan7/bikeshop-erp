begin;

select no_plan();

select has_function('public', 'assistant_search_inventory_v1', array['text'],
  'inventory tool RPC exists');
select has_function('public', 'assistant_list_attention_items_v1', array['text'],
  'attention tool RPC exists');
select has_function('public', 'assistant_search_workshop_jobs_v1',
  array['text','integer'], 'workshop search RPC exists');
select has_function('public', 'assistant_get_workshop_view_context_v1',
  array['uuid[]'], 'non-model workshop view-context reread exists');
select has_function('public', 'assistant_search_tasks_v1',
  array['text','integer'], 'task search RPC exists');
select has_function('public', 'assistant_search_customers_v1',
  array['text','integer'], 'customer search RPC exists');
select has_function('public', 'assistant_search_suppliers_v1',
  array['text','integer'], 'supplier search RPC exists');
select has_function('public', 'assistant_search_sales_invoices_v1',
  array['text','integer'], 'sales invoice search RPC exists');
select has_function('public', 'assistant_search_purchase_invoices_v1',
  array['text','integer'], 'purchase invoice search RPC exists');

select ok(
  (select bool_and(function.prosecdef
      and coalesce(function.proconfig::text, '') like '%search_path=%'
      and function.proconfig @> array['statement_timeout=4500ms']::text[])
   from pg_proc function
   join pg_namespace namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'assistant_search_inventory_v1', 'assistant_list_attention_items_v1',
       'assistant_search_workshop_jobs_v1',
       'assistant_get_workshop_view_context_v1', 'assistant_search_tasks_v1',
       'assistant_search_customers_v1', 'assistant_search_suppliers_v1',
       'assistant_search_sales_invoices_v1',
       'assistant_search_purchase_invoices_v1'
     )),
  'all tool RPCs are security definer with fixed search_path and DB timeout'
);

select ok(
  (select bool_and(
    has_function_privilege('authenticated', function.oid, 'EXECUTE')
    and not has_function_privilege('anon', function.oid, 'EXECUTE')
    and not has_function_privilege('service_role', function.oid, 'EXECUTE')
  )
   from pg_proc function
   join pg_namespace namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname in (
       'assistant_search_inventory_v1', 'assistant_list_attention_items_v1',
       'assistant_search_workshop_jobs_v1',
       'assistant_get_workshop_view_context_v1', 'assistant_search_tasks_v1',
       'assistant_search_customers_v1', 'assistant_search_suppliers_v1',
       'assistant_search_sales_invoices_v1',
       'assistant_search_purchase_invoices_v1'
     )),
  'tool execution is caller-JWT only and the compromised service role has no grant'
);

select ok(
  (select bool_and(function.prosrc not ilike '%portal_password%'
      and function.prosrc not ilike '%portal_username%'
      and function.prosrc not ilike '%bank_details%')
   from pg_proc function
   join pg_namespace namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'assistant_search_suppliers_v1'),
  'supplier projection cannot reference credential or bank columns'
);

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1710000-0000-4000-8000-000000000001', 'AI tools A',
   'tools-owner-a@example.invalid', 'America/Santiago'),
  ('a1710000-0000-4000-8000-000000000002', 'AI tools B',
   'tools-owner-b@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1710000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'cashier-tools@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1710000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'accountant-tools@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1710000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'credential-manager-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1710000-0000-4000-8000-000000000014', 'authenticated', 'authenticated',
   'credential-manager-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values
  ('a1710000-0000-4000-8000-000000000011',
   'a1710000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb),
  ('a1710000-0000-4000-8000-000000000012',
   'a1710000-0000-4000-8000-000000000001', 'accountant', '{}'::jsonb),
  ('a1710000-0000-4000-8000-000000000013',
   'a1710000-0000-4000-8000-000000000001', 'manager',
   '{"can_manage_supplier_credentials":true}'::jsonb),
  ('a1710000-0000-4000-8000-000000000014',
   'a1710000-0000-4000-8000-000000000002', 'manager',
   '{"can_manage_supplier_credentials":true}'::jsonb);

-- The production invariant permits only one active profile per Auth user, so
-- cross-tenant fixtures use business rows rather than an ambiguous authority.
insert into public.customers (
  id, tenant_id, name, email, rut, phone, is_active, updated_at
) values
  ('a1710000-0000-4000-8000-000000000101',
   'a1710000-0000-4000-8000-000000000001', 'Claudia Arcos',
   'claudia-tools@example.invalid', '11.111.111-1', '+56911111111', true, now()),
  ('a1710000-0000-4000-8000-000000000102',
   'a1710000-0000-4000-8000-000000000002', 'Cliente Secreto Vecino',
   'neighbor-tools@example.invalid', '22.222.222-2', '+56922222222', true, now());

insert into public.customers (
  id, tenant_id, name, email, rut, phone, is_active, updated_at
)
select
  ('a1710000-0000-4000-8000-' || lpad((800 + series)::text, 12, '0'))::uuid,
  'a1710000-0000-4000-8000-000000000001',
  'Cliente Límite ' || lpad(series::text, 2, '0'),
  'limit-' || series || '@example.invalid', null, null, true, now()
from generate_series(1, 11) series;

insert into public.bikes (
  id, tenant_id, customer_id, brand, model, serial_number
) values (
  'a1710000-0000-4000-8000-000000000103',
  'a1710000-0000-4000-8000-000000000001',
  'a1710000-0000-4000-8000-000000000101', 'Trek', 'Marlin', 'AI-BIKE-1'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1710000-0000-4000-8000-000000000013',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1710000-0000-4000-8000-000000000013', true);

insert into public.suppliers (
  id, tenant_id, name, rut, portal_username, portal_password, bank_details,
  is_active, updated_at
) values
  ('a1710000-0000-4000-8000-000000000201',
   'a1710000-0000-4000-8000-000000000001', 'Proveedor Andes', '76.111.111-1',
   'never-return-user', 'never-return-password', '{"account":"never-return"}', true, now());

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1710000-0000-4000-8000-000000000014',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1710000-0000-4000-8000-000000000014', true);

insert into public.suppliers (
  id, tenant_id, name, rut, portal_username, portal_password, bank_details,
  is_active, updated_at
) values
  ('a1710000-0000-4000-8000-000000000202',
   'a1710000-0000-4000-8000-000000000002', 'Proveedor Vecino Secreto', '76.222.222-2',
   'neighbor-user', 'neighbor-password', '{"account":"neighbor"}', true, now());

-- The remaining cross-tenant rows are neutral read fixtures; do not attribute
-- their unrelated audit side effects to either credential manager.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  brand, category_name, warehouse_location, is_active
) values
  ('a1710000-0000-4000-8000-000000000301',
   'a1710000-0000-4000-8000-000000000001', 'Cadena Shimano Deore',
   'CHAIN-DEORE-12', 29990, 10000, 4, 4, 'Shimano', 'Cadenas', 'A-03', true),
  ('a1710000-0000-4000-8000-000000000302',
   'a1710000-0000-4000-8000-000000000002', 'Cadena Vecina Secreta',
   'CHAIN-NEIGHBOR', 999, 1, 8, 8, 'Secret', 'Cadenas', 'Z-99', true);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, date, status, total, balance
) values
  ('a1710000-0000-4000-8000-000000000401',
   'a1710000-0000-4000-8000-000000000001', 'FV-AI-001', 'Claudia Arcos',
   now(), 'sent', 29990, 29990),
  ('a1710000-0000-4000-8000-000000000402',
   'a1710000-0000-4000-8000-000000000002', 'FV-SECRET-999', 'Cliente Vecino',
   now(), 'sent', 999999, 999999);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name, date, status,
  total, balance
) values
  ('a1710000-0000-4000-8000-000000000501',
   'a1710000-0000-4000-8000-000000000001', 'FC-AI-001',
   'a1710000-0000-4000-8000-000000000201', 'Proveedor Andes', now(),
   'sent', 10000, 10000),
  ('a1710000-0000-4000-8000-000000000502',
   'a1710000-0000-4000-8000-000000000002', 'FC-SECRET-999',
   'a1710000-0000-4000-8000-000000000202', 'Proveedor Vecino Secreto', now(),
  'sent', 999999, 999999);

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, arrival_date, deadline,
  status, priority, client_request, assigned_technician_name
) values
  ('a1710000-0000-4000-8000-000000000601',
   'a1710000-0000-4000-8000-000000000001', 'PG-AI-001',
   'a1710000-0000-4000-8000-000000000101', null, now(), now(),
   'PENDIENTE', 'URGENTE', 'Cambiar cadena', 'Vicente'),
  ('a1710000-0000-4000-8000-000000000602',
   'a1710000-0000-4000-8000-000000000001', 'PG-AI-002',
   'a1710000-0000-4000-8000-000000000101',
   'a1710000-0000-4000-8000-000000000103', now(), now(),
   'FINALIZADO', 'NORMAL', 'Trabajo terminado', 'Lucas');

insert into public.smart_tasks (
  id, tenant_id, title, description, status, priority, due_date, assigned_to
) values
  ('a1710000-0000-4000-8000-000000000701',
   'a1710000-0000-4000-8000-000000000001', 'Llamar a Claudia',
   'Confirmar retiro', 'pending', 'high', now(),
   'a1710000-0000-4000-8000-000000000011');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1710000-0000-4000-8000-000000000011', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1710000-0000-4000-8000-000000000011', true);
set local role authenticated;

select is(public.assistant_search_customers_v1('Claudia', 10) ->> 'status',
  'success', 'an authorized operational read succeeds');
select is(public.assistant_search_customers_v1('No Existe', 10) ->> 'status',
  'verifiedEmpty', 'a successful empty read is explicitly verifiedEmpty');
select is(public.assistant_search_customers_v1('Claudia', 10) ->> 'authorityTenantId',
  'a1710000-0000-4000-8000-000000000001',
  'every envelope carries the server-derived tenant');
select is(public.assistant_search_customers_v1('Vecino Secreto', 10) ->> 'resultCount',
  '0', 'customer search cannot see another tenant');
select is(public.assistant_search_customers_v1('Cliente Límite', 10)
  ->> 'resultCount', '10', 'customer projection honors its closed result bound');
select is(public.assistant_search_customers_v1('Cliente Límite', 10)
  ->> 'hasMore', 'true', 'bounded search reports additional authorized rows');
select is(public.assistant_search_inventory_v1('Cadena Shimano') ->> 'resultCount',
  '1', 'inventory token matching returns the authorized product');
select is(public.assistant_search_inventory_v1('Cadena Shimano')
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000301',
  'inventory result returns its tenant-validated entity reference');
select is(public.assistant_search_inventory_v1('Cadena Vecina') ->> 'resultCount',
  '0', 'inventory search cannot see another tenant');
select is(public.assistant_search_sales_invoices_v1('FV-AI-001', 10) ->> 'resultCount',
  '1', 'cashier has the sales capability');
select is(public.assistant_search_sales_invoices_v1('FV-AI-001', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000401',
  'sales invoice result returns its tenant-validated entity reference');
select is(public.assistant_search_workshop_jobs_v1('PG-AI-001', 10)
  ->> 'resultCount', '1', 'legacy job without a primary bike remains searchable');
select is(public.assistant_search_workshop_jobs_v1('PG-AI-001', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000601',
  'workshop result returns its tenant-validated entity reference');
select is(public.assistant_search_tasks_v1('Llamar Claudia', 10)
  #>> '{items,0,assigneeName}', 'Tú',
  'task projection identifies only the caller without exposing staff names');
select is(public.assistant_search_tasks_v1('Llamar Claudia', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000701',
  'task result returns its tenant-validated entity reference');
select is(public.assistant_list_attention_items_v1('today') ->> 'resultCount',
  '2', 'attention combines the open urgent job and task');
select ok(public.assistant_list_attention_items_v1('today')::text
  not like '%Trabajo terminado%', 'legacy terminal workshop jobs are excluded');
select is(public.assistant_get_workshop_view_context_v1(array[
  'a1710000-0000-4000-8000-000000000601'::uuid
]) ->> 'resultCount', '1', 'visible workshop context is reread in tenant');
select throws_ok($$select public.assistant_get_workshop_view_context_v1(array[
  'a1710000-0000-4000-8000-000000000601'::uuid,
  'a1710000-0000-4000-8000-000000000602'::uuid,
  gen_random_uuid()
])$$, '42501', 'AI workshop view context is unavailable',
  'partial/missing visible context is unavailable rather than silently filtered');

select throws_ok(
  $$select public.assistant_search_suppliers_v1('Andes', 10)$$,
  '42501', 'AI tool is not available',
  'cashier cannot invoke a purchase capability RPC even if it knows its name'
);
select throws_ok($$select public.assistant_list_attention_items_v1(null)$$,
  '22023','Invalid AI tool arguments','null attention horizon is rejected');
select throws_ok($$select public.assistant_search_customers_v1('Claudia',null)$$,
  '22023','Invalid AI tool arguments','null result limit is rejected');
select throws_ok(format(
  'select public.assistant_search_customers_v1(%L,10)', repeat('😀',61)
), '22023','Invalid AI tool arguments','query bound is measured in UTF-8 bytes');
select throws_ok(
  $$select public.assistant_search_customers_v1('x', 11)$$,
  '22023', 'Invalid AI tool arguments', 'search result limits are bounded'
);
select throws_ok(
  $$select public.assistant_get_workshop_view_context_v1(
    array_fill(gen_random_uuid(), array[21])
  )$$,
  '22023', 'Invalid AI view context', 'view context has a fixed twenty-id bound'
);

select ok(
  not ((public.assistant_search_customers_v1('Claudia', 10) -> 'items' -> 0)
    ?| array['id','tenantId','rut','email','phone']),
  'customer result exposes only the reviewed entity reference, never a generic id, tenant key or contact PII'
);
select is(public.assistant_search_customers_v1('Claudia', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000101',
  'customer result returns its tenant-validated entity reference');
select ok(
  (select array_agg(key order by key) = array[
    'asOf','authorityTenantId','hasMore','items','resultCount','status'
  ]::text[] from jsonb_object_keys(
    public.assistant_search_customers_v1('Claudia', 10)
  ) key),
  'tool envelope has the exact closed top-level keys'
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1710000-0000-4000-8000-000000000012', 'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1710000-0000-4000-8000-000000000012', true);

select is(public.assistant_search_suppliers_v1('Andes', 10) ->> 'resultCount',
  '1', 'accountant has purchase read capability');
select ok(
  (select array_agg(key order by key) = array[
     'entityId','isActive','name','updatedAt'
   ]::text[]
   from jsonb_object_keys(
     public.assistant_search_suppliers_v1('Andes', 10) -> 'items' -> 0
   ) key),
  'supplier result has only the four allowlisted fields'
);
select is(public.assistant_search_suppliers_v1('Andes', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000201',
  'supplier result returns its tenant-validated entity reference');
select ok(
  public.assistant_search_suppliers_v1('Andes', 10)::text not like '%never-return%'
  and public.assistant_search_suppliers_v1('Andes', 10)::text not like '%password%'
  and public.assistant_search_suppliers_v1('Andes', 10)::text not like '%account%',
  'supplier output contains no credentials or bank data'
);
select is(public.assistant_search_purchase_invoices_v1('FC-AI-001', 10)
  ->> 'resultCount', '1', 'purchase invoice tool uses authorized tenant read model');
select is(public.assistant_search_purchase_invoices_v1('FC-AI-001', 10)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000501',
  'purchase invoice result returns its tenant-validated entity reference');
select is(public.assistant_search_purchase_invoices_v1('SECRET-999', 10)
  ->> 'resultCount', '0', 'purchase invoice read cannot cross tenants');

select * from finish();
rollback;
