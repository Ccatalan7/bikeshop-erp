begin;

select no_plan();

select has_function('public', 'assistant_search_inventory_v1', array['text'],
  'inventory tool RPC exists');
select has_function('public', 'assistant_search_inventory_v2', array['text','text'],
  'filtered inventory list RPC exists');
select has_function('public', 'assistant_search_inventory_v3',
  array['text','text','jsonb'],
  'technical-spec inventory list RPC exists');
select has_function('public', 'assistant_search_inventory_v4',
  array['text','text','text','jsonb'],
  'category-and-spec inventory list RPC exists');
select has_function('public', 'assistant_inspect_inventory_schema_v1',
  array['text','text'],
  'inventory capability discovery RPC exists');
select has_function('public', 'assistant_search_inventory_v5',
  array['text','text','text','jsonb'],
  'typed-predicate inventory list RPC exists');
select has_function('public', 'assistant_inspect_inventory_schema_v2',
  array['text','text'],
  'operational and technical capability discovery RPC exists');
select has_function('public', 'assistant_search_inventory_v6',
  array['text','text','text','jsonb','jsonb','text','text','integer','text'],
  'typed inventory query RPC exists');
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
       'assistant_search_inventory_v1', 'assistant_search_inventory_v2',
       'assistant_search_inventory_v3',
       'assistant_search_inventory_v4',
       'assistant_list_attention_items_v1',
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
       'assistant_search_inventory_v1', 'assistant_search_inventory_v2',
       'assistant_search_inventory_v3',
       'assistant_search_inventory_v4',
       'assistant_list_attention_items_v1',
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

insert into public.product_categories (
  id, tenant_id, name, full_path, level, is_active
) values
  ('a1710000-0000-4000-8000-000000000921',
   'a1710000-0000-4000-8000-000000000001',
   'Camaras', 'Camaras', 0, true),
  ('a1710000-0000-4000-8000-000000000922',
   'a1710000-0000-4000-8000-000000000001',
   'Accesorios', 'Accesorios', 0, true),
  ('a1710000-0000-4000-8000-000000000930',
   'a1710000-0000-4000-8000-000000000001',
   'Motores', 'Componentes / Transmision / Motores', 2, true),
  ('a1710000-0000-4000-8000-000000000931',
   'a1710000-0000-4000-8000-000000000001',
   'Motor', 'Componentes / Transmision / Motores / Motor', 3, true)
on conflict do nothing;

update public.product_categories
set parent_id = 'a1710000-0000-4000-8000-000000000930'
where id = 'a1710000-0000-4000-8000-000000000931';

insert into public.spec_templates (
  id, tenant_id, key, name, technical_family, is_active
) values (
  'a1710000-0000-4000-8000-000000000933',
  'a1710000-0000-4000-8000-000000000001',
  'ai_motor_test', 'Motor AI test', 'bottom_bracket', true
)
on conflict do nothing;

insert into public.category_tech_mappings (
  id, tenant_id, category_id, technical_family, template_id, status
) values
  ('a1710000-0000-4000-8000-000000000923',
   'a1710000-0000-4000-8000-000000000001',
   'a1710000-0000-4000-8000-000000000921',
   'tube', null, 'active'),
  ('a1710000-0000-4000-8000-000000000932',
   'a1710000-0000-4000-8000-000000000001',
   'a1710000-0000-4000-8000-000000000931',
   'bottom_bracket', 'a1710000-0000-4000-8000-000000000933', 'active')
on conflict (tenant_id, category_id) do update
set technical_family = excluded.technical_family,
  template_id = excluded.template_id, status = excluded.status;

insert into public.products (
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  brand, category_id, category_name, warehouse_location, is_active,
  min_stock_level
) values
  ('a1710000-0000-4000-8000-000000000301',
   'a1710000-0000-4000-8000-000000000001', 'Cadena Shimano Deore',
   'CHAIN-DEORE-12', 29990, 10000, 4, 4, 'Shimano', null,
   'Cadenas', 'A-03', true, 2),
  ('a1710000-0000-4000-8000-000000000302',
   'a1710000-0000-4000-8000-000000000002', 'Cadena Vecina Secreta',
   'CHAIN-NEIGHBOR', 999, 1, 8, 8, 'Secret', null,
   'Cadenas', 'Z-99', true, 2),
  ('a1710000-0000-4000-8000-000000000303',
   'a1710000-0000-4000-8000-000000000001', 'Camara 29 Disponible',
   'TUBE-29-OK', 7000, 3000, 7, 7, 'Test',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000304',
   'a1710000-0000-4000-8000-000000000001', 'Camara 29 Stock Bajo',
   'TUBE-29-LOW', 6500, 2800, 1, 1, 'Test',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000305',
   'a1710000-0000-4000-8000-000000000001', 'Camara 29 Agotada',
   'TUBE-29-ZERO', 6000, 2500, 0, 0, 'Test',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000306',
   'a1710000-0000-4000-8000-000000000001', 'Camara 26 Incidental',
   '6938112671129', 5000, 1900, 3, 3, 'Test',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000307',
   'a1710000-0000-4000-8000-000000000001', 'Camara Kenda 26',
   '4420', 7000, 2600, 3, 3, 'Kenda',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000308',
   'a1710000-0000-4000-8000-000000000001',
   'Camara 29 Etiqueta Equivocada', 'TUBE-CONFLICT',
   7000, 2600, 4, 4, 'Test',
   'a1710000-0000-4000-8000-000000000921', 'Camaras', 'A-04', true, 2),
  ('a1710000-0000-4000-8000-000000000309',
   'a1710000-0000-4000-8000-000000000001',
   'Camara 29 Mal Categorizada', 'TUBE-WRONG-CATEGORY',
   7000, 2600, 4, 4, 'Test',
   'a1710000-0000-4000-8000-000000000922', 'Accesorios', 'A-04', true, 2);

insert into public.products (
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  brand, category_id, category_name, warehouse_location, is_active,
  min_stock_level
) values
  ('a1710000-0000-4000-8000-000000000310',
   'a1710000-0000-4000-8000-000000000001',
   'Motor cuadradillo 118 mm', 'MOTOR-118', 12000, 5000, 3, 3, 'Test',
   'a1710000-0000-4000-8000-000000000931', 'Motor', 'A-05', true, 1),
  ('a1710000-0000-4000-8000-000000000311',
   'a1710000-0000-4000-8000-000000000001',
   'Motor cuadradillo 127 mm', 'MOTOR-127', 12000, 5000, 3, 3, 'Test',
   'a1710000-0000-4000-8000-000000000931', 'Motor', 'A-05', true, 1),
  ('a1710000-0000-4000-8000-000000000312',
   'a1710000-0000-4000-8000-000000000001',
   'Motor sellado 68x122.5 mm', 'MOTOR-AMBIGUO', 12000, 5000, 3, 3, 'Test',
   'a1710000-0000-4000-8000-000000000931', 'Motor', 'A-05', true, 1);

update public.products
set description = 'Alternativa compatible cuando no exista camara 29'
where id = 'a1710000-0000-4000-8000-000000000306';

insert into public.spec_definitions (
  id, tenant_id, key, label, data_type, allowed_values,
  is_filterable, is_compatibility_relevant
) values
  ('a1710000-0000-4000-8000-000000000901', null, 'wheel_size',
   'Tamaño de Rueda', 'single_select',
   '["26\"","27.5\"","29\"","700c"]'::jsonb, true, true),
  ('a1710000-0000-4000-8000-000000000902', null, 'spindle_length_mm',
   'Largo eje', 'number', '[]'::jsonb, true, true)
on conflict do nothing;

insert into public.spec_template_fields (
  id, tenant_id, template_id, spec_definition_id, section_key, sort_order
)
select 'a1710000-0000-4000-8000-000000000934',
  'a1710000-0000-4000-8000-000000000001',
  'a1710000-0000-4000-8000-000000000933', definition.id,
  'compatibility', 1
from public.spec_definitions definition
where definition.key = 'spindle_length_mm'
  and definition.tenant_id is null
on conflict do nothing;

insert into public.product_spec_values (
  id, tenant_id, product_id, spec_definition_id,
  value_option, display_value
)
select fixture.id, 'a1710000-0000-4000-8000-000000000001',
  fixture.product_id, definition.id, fixture.value_option, fixture.value_option
from (values
  ('a1710000-0000-4000-8000-000000000911'::uuid,
   'a1710000-0000-4000-8000-000000000303'::uuid, '29"'),
  ('a1710000-0000-4000-8000-000000000912'::uuid,
   'a1710000-0000-4000-8000-000000000306'::uuid, '26"'),
  ('a1710000-0000-4000-8000-000000000913'::uuid,
   'a1710000-0000-4000-8000-000000000308'::uuid, '26"'),
  ('a1710000-0000-4000-8000-000000000914'::uuid,
   'a1710000-0000-4000-8000-000000000309'::uuid, '29"')
) fixture(id, product_id, value_option)
join public.spec_definitions definition
  on definition.key = 'wheel_size' and definition.tenant_id is null;

insert into public.product_spec_values (
  id, tenant_id, product_id, spec_definition_id,
  value_number, display_value
)
select fixture.id, 'a1710000-0000-4000-8000-000000000001',
  fixture.product_id, definition.id, fixture.value_number,
  fixture.value_number::text || ' mm'
from (values
  ('a1710000-0000-4000-8000-000000000915'::uuid,
   'a1710000-0000-4000-8000-000000000310'::uuid, 118::numeric),
  ('a1710000-0000-4000-8000-000000000916'::uuid,
   'a1710000-0000-4000-8000-000000000311'::uuid, 127::numeric)
) fixture(id, product_id, value_number)
join public.spec_definitions definition
  on definition.key = 'spindle_length_mm' and definition.tenant_id is null;

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
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29"}]'::jsonb
)
  ->> 'resultCount', '2',
  'category, canonical specs, identity fallback and stock are applied before the bound');
select ok(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)::text
  not like '%Camara 26 Incidental%',
  'a measurement cannot be satisfied by an EAN suffix or compatibility prose');
select ok(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)::text
  not like '%Etiqueta Equivocada%',
  'a populated conflicting technical spec outranks a matching product name');
select ok(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)::text
  not like '%TUBE-29-ZERO%',
  'in-stock synthesis cannot receive an out-of-stock product');
select ok(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)::text not like '%TUBE-WRONG-CATEGORY%',
  'a matching name and spec outside the resolved technical family is excluded');
select is(public.assistant_search_inventory_v4(
  'Camara 4420', 'Camaras', 'in_stock', '[]'::jsonb
)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000307',
  'an exact SKU remains authoritative when combined with a product-family term');
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'low_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000304',
  'missing structured data may use explicit identity evidence without guessing');
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'out_of_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
)
  #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000305',
  'out-of-stock list returns only the exact matching product');
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'any',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
) ->> 'resultCount', '3',
  'unfiltered availability preserves only technically valid matches');
select throws_ok(
  $$select public.assistant_search_inventory_v4(
    'Camara 29', 'Camaras', 'available-ish', '[]'::jsonb
  )$$,
  '22023', 'Invalid AI tool arguments',
  'inventory availability is a closed server-side filter'
);
select throws_ok(
  $$select public.assistant_search_inventory_v4(
    'Camara 29', 'Camaras', 'in_stock',
    '[{"field":"invented_measurement","value":"29"}]'::jsonb
  )$$,
  '22023', 'Invalid AI tool arguments',
  'the model cannot invent a technical field outside the canonical registry'
);
select throws_ok(
  $$select public.assistant_search_inventory_v4(
    'Camara 29', 'Categoria Inventada', 'in_stock', '[]'::jsonb
  )$$,
  '22023', 'Invalid AI tool arguments',
  'the model cannot invent a category outside the tenant catalog'
);
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'in_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
) #>> '{items,0,technicalMatch}', 'product_spec',
  'the result exposes when its technical fact came from product_spec_values');
select is(public.assistant_search_inventory_v4(
  'Camara 29', 'Camaras', 'low_stock',
  '[{"field":"wheel_size","value":"29\""}]'::jsonb
) #>> '{items,0,technicalMatch}', 'identity_fallback',
  'the result exposes an identity fallback instead of calling it a filled ficha');
select is(public.assistant_inspect_inventory_schema_v1(
  'motores con eje de menos de 125 mm', 'Motores'
) #>> '{items,2,field}', 'spindle_length_mm',
  'schema discovery expands a parent category and exposes its canonical numeric field');
select is(public.assistant_inspect_inventory_schema_v1(
  'motores con eje de menos de 125 mm', 'Motores'
) #>> '{items,2,operators}', 'eq,neq,lt,lte,gt,gte,between,in',
  'schema discovery advertises only the supported numeric operators');
select is(public.assistant_inspect_inventory_schema_v1(
  'motores con eje de menos de 125 mm', 'Motores'
) #>> '{items,2,populatedCount}', '2',
  'schema discovery reports actual structured coverage instead of guessing from names');
select is(public.assistant_search_inventory_v5(
  null, 'Motores', 'in_stock',
  '[{"field":"spindle_length_mm","operator":"lt","values":[125]}]'::jsonb
) ->> 'resultCount', '1',
  'a numeric less-than predicate is evaluated from product_spec_values');
select is(public.assistant_search_inventory_v5(
  null, 'Motores', 'in_stock',
  '[{"field":"spindle_length_mm","operator":"lt","values":[125]}]'::jsonb
) #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000310',
  'a parent category includes a matching descendant product');
select ok(public.assistant_search_inventory_v5(
  null, 'Motores', 'in_stock',
  '[{"field":"spindle_length_mm","operator":"lt","values":[125]}]'::jsonb
)::text not like '%MOTOR-AMBIGUO%',
  'a range never infers axle length from an ambiguous multi-measurement name');
select is(public.assistant_search_inventory_v5(
  null, 'Motores', 'in_stock',
  '[{"field":"spindle_length_mm","operator":"gt","values":[125]}]'::jsonb
) #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000311',
  'the same typed primitive supports the opposite numeric comparison');
select is(public.assistant_inspect_inventory_schema_v2(
  'cámaras 29 con más de cinco unidades', 'Camaras'
) #>> '{items,0,field}', 'stock',
  'capability discovery exposes stock as a general operational numeric field');
select is(public.assistant_inspect_inventory_schema_v2(
  'cámaras 29 con más de cinco unidades', 'Camaras'
) #>> '{items,0,operators}', 'eq,neq,lt,lte,gt,gte,between,in',
  'operational discovery advertises exact numeric comparisons');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[{"field":"stock","operator":"gt","values":[5]}]'::jsonb,
  'relevance', 'desc', 10, 'all_matches'
) ->> 'resultCount', '1',
  'a stock threshold composes with category, technical spec and availability');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[{"field":"stock","operator":"gt","values":[5]}]'::jsonb,
  'relevance', 'desc', 10, 'all_matches'
) #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000303',
  'the stock threshold returns only the camera whose effective stock is greater than five');
select is(public.assistant_search_inventory_v6(
  null, 'Motores', 'any', '[]'::jsonb,
  '[{"field":"price","operator":"between","values":[11000,13000]}]'::jsonb,
  'relevance', 'desc', 10, 'all_matches'
) ->> 'resultCount', '3',
  'the same operational predicate primitive works for price in another category');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[]'::jsonb, 'stock', 'desc', 1, 'top_n'
) #>> '{items,0,entityId}', 'a1710000-0000-4000-8000-000000000303',
  'server-owned ordering returns the highest-stock matching product');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[]'::jsonb, 'stock', 'desc', 1, 'top_n'
) ->> 'hasMore', 'false',
  'an explicit top-N selection is complete even when more filtered rows exist');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[]'::jsonb, 'stock', 'desc', 1, 'top_n'
) #>> '{items,0,matchedCount}', '2',
  'metrics count the complete filtered set before the top-N limit');
select is(public.assistant_search_inventory_v6(
  null, 'Camaras', 'in_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb,
  '[]'::jsonb, 'stock', 'desc', 1, 'top_n'
) #>> '{items,0,totalStock}', '8',
  'metrics sum stock over the complete filtered set instead of the returned page');
select throws_ok(
  $$select public.assistant_search_inventory_v6(
    null, 'Camaras', 'any', '[]'::jsonb,
    '[{"field":"invented_metric","operator":"gt","values":[5]}]'::jsonb,
    'relevance', 'desc', 10, 'all_matches'
  )$$,
  '22023', 'Invalid AI tool arguments',
  'operational predicates reject invented fields'
);
select throws_ok(
  $$select public.assistant_search_inventory_v6(
    null, 'Camaras', 'any', '[]'::jsonb,
    '[{"field":"stock","operator":"contains","values":[5]}]'::jsonb,
    'relevance', 'desc', 10, 'all_matches'
  )$$,
  '22023', 'Invalid AI tool arguments',
  'operational numeric fields reject text operators'
);
select is(public.assistant_search_inventory_v5(
  null, 'Camaras', 'low_stock',
  '[{"field":"wheel_size","operator":"eq","values":["29\""]}]'::jsonb
) #>> '{items,0,technicalMatch}', 'identity_fallback',
  'exact equality preserves the explicitly labelled sparse-catalog fallback');
select throws_ok(
  $$select public.assistant_search_inventory_v5(
    null, 'Motores', 'in_stock',
    '[{"field":"spindle_length_mm","operator":"contains","values":["125"]}]'::jsonb
  )$$,
  '22023', 'Invalid AI tool arguments',
  'a numeric field rejects a text operator instead of degrading to keywords'
);
select throws_ok(
  $$select public.assistant_search_inventory_v5(
    null, 'Motores', 'in_stock',
    '[{"field":"invented_measurement","operator":"lt","values":[125]}]'::jsonb
  )$$,
  '22023', 'Invalid AI tool arguments',
  'typed search still rejects invented registry fields'
);
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
