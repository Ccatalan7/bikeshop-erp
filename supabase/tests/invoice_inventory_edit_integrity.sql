begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(24);

insert into public.tenants (id, shop_name)
values ('91000000-0000-4000-8000-000000000001', 'Invoice Inventory Integrity Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '91000000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'inventory-trace-test@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '91000000-0000-4000-8000-000000000001',
    'name', 'Inventory Trace Test'
  ),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '91000000-0000-4000-8000-000000000099',
  '91000000-0000-4000-8000-000000000001',
  'admin'
)
on conflict (user_id, tenant_id) do update set role = excluded.role;

update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('tenant_id', '91000000-0000-4000-8000-000000000001')
where id = '91000000-0000-4000-8000-000000000099';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '91000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '91000000-0000-4000-8000-000000000099', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '91000000-0000-4000-8000-000000000002',
  '91000000-0000-4000-8000-000000000001',
  'Sales Trace Product',
  'TRACE-SALES-PRODUCT',
  1000,
  500,
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
set inventory_qty = 20,
    stock_quantity = 20
where id = '91000000-0000-4000-8000-000000000002';
select set_config('app.skip_stock_adjustment_trigger', '', true);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, items
)
values (
  '91000000-0000-4000-8000-000000000003',
  '91000000-0000-4000-8000-000000000001',
  'FV-TRACE-001',
  'Trace Customer',
  'confirmed',
  2000,
  2000,
  0,
  2000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '91000000-0000-4000-8000-000000000002',
    'product_sku', 'TRACE-SALES-PRODUCT',
    'product_name', 'Sales Trace Product',
    'quantity', 2,
    'price', 1000,
    'cost', 500,
    'is_service', false,
    'purchase_treatment', 'inventory'
  ))
);

select is(
  (select inventory_qty from public.products where id = '91000000-0000-4000-8000-000000000002'),
  18,
  'confirmed sales invoice deducts legacy inventory quantity once'
);

select is(
  (select stock_quantity from public.products where id = '91000000-0000-4000-8000-000000000002'),
  18,
  'confirmed sales invoice keeps both stock columns equal'
);

update public.sales_invoices
set items = jsonb_build_array(jsonb_build_object(
      'product_id', '91000000-0000-4000-8000-000000000002',
      'product_sku', 'TRACE-SALES-PRODUCT',
      'product_name', 'Sales Trace Product',
      'quantity', 5,
      'price', 1000,
      'cost', 500,
      'is_service', false,
      'purchase_treatment', 'inventory'
    )),
    subtotal = 5000,
    net_amount = 5000,
    total = 5000
where id = '91000000-0000-4000-8000-000000000003';

select is(
  (select inventory_qty from public.products where id = '91000000-0000-4000-8000-000000000002'),
  15,
  'posted sales quantity edit replaces the old stock snapshot'
);

select is(
  (select stock_quantity from public.products where id = '91000000-0000-4000-8000-000000000002'),
  15,
  'posted sales edit preserves dual-column equality'
);

select is(
  (select sum(quantity)::integer
     from public.stock_movements
    where reference = 'sales_invoice:91000000-0000-4000-8000-000000000003'),
  -5,
  'sales movement ledger has the edited invoice net quantity'
);

select is(
  (select count(*)::integer
     from public.stock_adjustments
    where tenant_id = '91000000-0000-4000-8000-000000000001'
      and product_id = '91000000-0000-4000-8000-000000000002'
      and adjustment_type = 'manual'),
  0,
  'posted sales edit creates no phantom manual adjustment'
);

create temp table sales_movement_count_before_price_edit on commit drop as
select count(*)::integer as value
from public.stock_movements
where reference = 'sales_invoice:91000000-0000-4000-8000-000000000003';

update public.sales_invoices
set items = jsonb_build_array(jsonb_build_object(
      'product_id', '91000000-0000-4000-8000-000000000002',
      'product_sku', 'TRACE-SALES-PRODUCT',
      'product_name', 'Sales Trace Product',
      'quantity', 5,
      'price', 1200,
      'cost', 500,
      'is_service', false,
      'purchase_treatment', 'inventory'
    )),
    subtotal = 6000,
    net_amount = 6000,
    total = 6000
where id = '91000000-0000-4000-8000-000000000003';

select is(
  (select stock_quantity from public.products where id = '91000000-0000-4000-8000-000000000002'),
  15,
  'sales price-only edit does not change stock'
);

select is(
  (select count(*)::integer
     from public.stock_movements
    where reference = 'sales_invoice:91000000-0000-4000-8000-000000000003'),
  (select value from sales_movement_count_before_price_edit),
  'sales price-only edit creates no stock movement noise'
);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '91000000-0000-4000-8000-000000000004',
  '91000000-0000-4000-8000-000000000001',
  'Purchase Trace Product',
  'TRACE-PURCHASE-PRODUCT',
  1500,
  700,
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
where id = '91000000-0000-4000-8000-000000000004';
select set_config('app.skip_stock_adjustment_trigger', '', true);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, tax, total, items
)
values (
  '91000000-0000-4000-8000-000000000005',
  '91000000-0000-4000-8000-000000000001',
  'FC-TRACE-001',
  'Trace Supplier',
  'received',
  7000,
  0,
  7000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '91000000-0000-4000-8000-000000000004',
    'product_name', 'Purchase Trace Product',
    'quantity', 10,
    'unit_cost', 700,
    'purchase_treatment', 'inventory'
  ))
);

select is(
  (select stock_quantity from public.products where id = '91000000-0000-4000-8000-000000000004'),
  15,
  'received purchase invoice adds stock once'
);

update public.purchase_invoices
set items = jsonb_build_array(jsonb_build_object(
      'product_id', '91000000-0000-4000-8000-000000000004',
      'product_name', 'Purchase Trace Product',
      'quantity', 12,
      'unit_cost', 700,
      'purchase_treatment', 'inventory'
    )),
    subtotal = 8400,
    total = 8400
where id = '91000000-0000-4000-8000-000000000005';

select is(
  (select stock_quantity from public.products where id = '91000000-0000-4000-8000-000000000004'),
  17,
  'received purchase quantity edit replaces the old stock snapshot'
);

select is(
  (select count(*)::integer
     from public.stock_adjustments
    where tenant_id = '91000000-0000-4000-8000-000000000001'
      and product_id = '91000000-0000-4000-8000-000000000004'
      and adjustment_type = 'manual'),
  0,
  'purchase restore creates no phantom manual adjustment'
);

create temp table purchase_movement_count_before_price_edit on commit drop as
select count(*)::integer as value
from public.stock_movements
where reference = 'purchase_invoice:91000000-0000-4000-8000-000000000005';

update public.purchase_invoices
set items = jsonb_build_array(jsonb_build_object(
      'product_id', '91000000-0000-4000-8000-000000000004',
      'product_name', 'Purchase Trace Product',
      'quantity', 12,
      'unit_cost', 750,
      'purchase_treatment', 'inventory'
    )),
    subtotal = 9000,
    total = 9000
where id = '91000000-0000-4000-8000-000000000005';

select is(
  (select count(*)::integer
     from public.stock_movements
    where reference = 'purchase_invoice:91000000-0000-4000-8000-000000000005'),
  (select value from purchase_movement_count_before_price_edit),
  'purchase cost-only edit creates no stock movement noise'
);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, items
)
values (
  '91000000-0000-4000-8000-000000000006',
  '91000000-0000-4000-8000-000000000001',
  'FV-TRACE-QUICK-001',
  'Quick Sale Customer',
  'quick_sale',
  'draft',
  0,
  0,
  0,
  0,
  '[]'::jsonb
);

select is(
  (select source_channel
   from public.inventory_accounting_operations
   where document_id = '91000000-0000-4000-8000-000000000006'
   order by created_at desc
   limit 1),
  'quick_sale',
  'quick sale has a distinct database trace source'
);

select is(
  (select count(*)::integer
   from public.inventory_accounting_operations
   where tenant_id = '91000000-0000-4000-8000-000000000001'
     and document_type = 'sales_invoice'
     and document_id = '91000000-0000-4000-8000-000000000003'),
  3,
  'sales invoice create and two edits each have one trace root'
);

select is(
  (select count(*)::integer
   from public.inventory_accounting_operations
   where tenant_id = '91000000-0000-4000-8000-000000000001'
     and outcome <> 'completed'),
  0,
  'all successful invoice trace roots are completed'
);

select ok(
  not exists (
    select 1
    from public.stock_movements
    where reference = 'sales_invoice:91000000-0000-4000-8000-000000000003'
      and operation_id is null
  ),
  'every new sales movement links to its trace operation'
);

select ok(
  not exists (
    select 1
    from public.stock_movements
    where reference = 'purchase_invoice:91000000-0000-4000-8000-000000000005'
      and operation_id is null
  ),
  'every new purchase movement links to its trace operation'
);

select ok(
  not exists (
    select 1
    from public.journal_entries
    where tenant_id = '91000000-0000-4000-8000-000000000001'
      and source_module in ('sales_invoices', 'purchase_invoices')
      and operation_id is null
  ),
  'current invoice journals link to their trace operation'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_checkpoints cp
    join public.inventory_accounting_operations op on op.id = cp.operation_id
    where op.document_id = '91000000-0000-4000-8000-000000000003'
      and cp.phase = 'movement_recorded'
  ),
  'sales trace contains movement-recorded checkpoints'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_checkpoints cp
    join public.inventory_accounting_operations op on op.id = cp.operation_id
    where op.document_id = '91000000-0000-4000-8000-000000000003'
      and cp.phase = 'journal_reversed'
  ),
  'posted sales edit preserves a checkpoint snapshot of the replaced journal'
);

select ok(
  not exists (
    select 1
    from public.stock_movements sm
    where sm.operation_id is not null
      and round(
        sm.stock_before + case
          when sm.type in ('OUT', 'TRANSFER_OUT') then -abs(sm.quantity)
          when sm.type in ('IN', 'TRANSFER_IN') then abs(sm.quantity)
          else sm.quantity
        end,
        2
      ) <> round(sm.stock_after, 2)
  ),
  'persisted traced movement balances satisfy before plus delta equals after'
);

select ok(
  not exists (
    select 1
    from public.inventory_accounting_operations
    where tenant_id = '91000000-0000-4000-8000-000000000001'
      and actor_id is distinct from '91000000-0000-4000-8000-000000000099'::uuid
  ),
  'invoice trace roots capture the authenticated actor'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_id = '91000000-0000-4000-8000-000000000003'
      and jsonb_array_length(trace.checkpoints) >= 4
      and jsonb_array_length(trace.stock_movements) > 0
      and exists (
        select 1
        from jsonb_array_elements(trace.checkpoints) checkpoint
        where checkpoint->>'phase' = 'journal_posted'
      )
  ),
  'trace view reconstructs source, checkpoints, movements, and journals'
);

select is(
  (select count(*)::integer
   from public.inventory_accounting_inconsistencies_view
   where tenant_id = '91000000-0000-4000-8000-000000000001'),
  0,
  'certified invoice fixtures surface no trace inconsistencies'
);

select * from finish();

rollback;
