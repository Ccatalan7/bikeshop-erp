begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(10);

insert into public.tenants (id, shop_name)
values ('92000000-0000-4000-8000-000000000001', 'Manual Stock Trace Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '92000000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'manual-stock-trace@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '92000000-0000-4000-8000-000000000001',
    'name', 'Manual Stock Trace Test'
  ),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '92000000-0000-4000-8000-000000000099',
  '92000000-0000-4000-8000-000000000001',
  'admin'
)
on conflict (user_id, tenant_id) do update set role = excluded.role;

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('tenant_id', '92000000-0000-4000-8000-000000000001')
where id = '92000000-0000-4000-8000-000000000099';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '92000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '92000000-0000-4000-8000-000000000099', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '92000000-0000-4000-8000-000000000002',
  '92000000-0000-4000-8000-000000000001',
  'Manual Trace Product',
  'TRACE-MANUAL-PRODUCT',
  1000,
  400,
  'product',
  false,
  true,
  0,
  0,
  0,
  100
);

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products
set inventory_qty = 5,
    stock_quantity = 5
where id = '92000000-0000-4000-8000-000000000002';
select set_config('app.skip_stock_adjustment_trigger', '', true);

create temp table manual_adjustment_result on commit drop as
select public.apply_inventory_stock_adjustment(
  '92000000-0000-4000-8000-000000000002',
  2,
  'OUT',
  'damage',
  'Regression fixture',
  now(),
  'product_form'
) as payload;

select ok(
  nullif((select payload->>'operation_id' from manual_adjustment_result), '') is not null,
  'structured adjustment returns its trace operation id'
);

select is(
  (select inventory_qty from public.products where id = '92000000-0000-4000-8000-000000000002'),
  3,
  'manual stock decrease updates legacy inventory quantity'
);

select is(
  (select stock_quantity from public.products where id = '92000000-0000-4000-8000-000000000002'),
  3,
  'manual stock decrease keeps both stock columns equal'
);

select ok(
  exists (
    select 1
      from public.stock_adjustments adjustment
      join manual_adjustment_result result
        on adjustment.id = (result.payload->>'adjustment_id')::uuid
     where adjustment.operation_id = (result.payload->>'operation_id')::uuid
       and adjustment.source_document_id = adjustment.id
  ),
  'stock adjustment row links to its operation and source document'
);

select ok(
  exists (
    select 1
      from public.stock_movements movement
      join manual_adjustment_result result
        on movement.id = (result.payload->>'movement_id')::uuid
     where movement.operation_id = (result.payload->>'operation_id')::uuid
       and movement.stock_before = 5
       and movement.stock_after = 3
  ),
  'stock movement stores the operation and true before/after balances'
);

select ok(
  exists (
    select 1
      from public.journal_entries entry
      join manual_adjustment_result result
        on entry.id = (result.payload->>'journal_entry_id')::uuid
     where entry.operation_id = (result.payload->>'operation_id')::uuid
       and entry.total_debit = entry.total_credit
  ),
  'inventory adjustment journal links to the operation and balances'
);

select ok(
  exists (
    select 1
      from public.inventory_accounting_operations operation
      join manual_adjustment_result result
        on operation.id = (result.payload->>'operation_id')::uuid
     where operation.source_channel = 'product_form'
       and operation.document_type = 'stock_adjustment'
       and operation.outcome = 'completed'
  ),
  'manual adjustment trace root identifies its source and completes'
);

select is(
  (
    select count(distinct checkpoint.phase)::integer
      from public.inventory_accounting_checkpoints checkpoint
      join manual_adjustment_result result
        on checkpoint.operation_id = (result.payload->>'operation_id')::uuid
     where checkpoint.phase in (
       'accepted', 'source_snapshotted', 'inventory_planned',
       'inventory_applied', 'movement_recorded', 'accounting_planned',
       'journal_posted', 'invariants_verified', 'completed'
     )
  ),
  9,
  'manual adjustment trace records every expected checkpoint phase'
);

select ok(
  exists (
    select 1
      from public.inventory_accounting_operation_trace_view trace
      join manual_adjustment_result result
        on trace.operation_id = (result.payload->>'operation_id')::uuid
     where jsonb_array_length(trace.stock_movements) = 1
       and jsonb_array_length(trace.journal_entries) = 1
  ),
  'trace view reconstructs the manual stock and accounting effects'
);

select is(
  (
    select count(*)::integer
      from public.inventory_accounting_inconsistencies_view
     where tenant_id = '92000000-0000-4000-8000-000000000001'
  ),
  0,
  'manual adjustment fixture surfaces no trace inconsistencies'
);

select * from finish();

rollback;
