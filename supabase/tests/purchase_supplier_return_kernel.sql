begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(39);

insert into public.tenants (id, shop_name)
values ('99200000-0000-4000-8000-000000000001', 'Supplier Return Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99200000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'supplier-return@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99200000-0000-4000-8000-000000000001'
  ),
  now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role)
values (
  '99200000-0000-4000-8000-000000000099',
  '99200000-0000-4000-8000-000000000001', 'admin'
);
update auth.users
set raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
  'tenant_id', '99200000-0000-4000-8000-000000000001'
)
where id = '99200000-0000-4000-8000-000000000099';
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99200000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '99200000-0000-4000-8000-000000000099', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level, is_set
) values
  ('99200000-0000-4000-8000-000000000002', '99200000-0000-4000-8000-000000000001', 'Direct Product', 'RETURN-DIRECT', 2000, 1000, 'product', false, true, 0, 0, 0, 100, false),
  ('99200000-0000-4000-8000-000000000005', '99200000-0000-4000-8000-000000000001', 'Return Set', 'RETURN-SET', 5000, 3000, 'product', false, true, 0, 0, 0, 100, true),
  ('99200000-0000-4000-8000-000000000006', '99200000-0000-4000-8000-000000000001', 'Return Component A', 'RETURN-A', 2000, 1000, 'product', false, true, 0, 0, 0, 100, false),
  ('99200000-0000-4000-8000-000000000007', '99200000-0000-4000-8000-000000000001', 'Return Component B', 'RETURN-B', 3000, 2000, 'product', false, true, 0, 0, 0, 100, false);

insert into public.product_set_components (
  tenant_id, set_product_id, component_product_id, component_label,
  component_position, quantity_in_set
) values
  ('99200000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000005', '99200000-0000-4000-8000-000000000006', 'A', 1, 1),
  ('99200000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000005', '99200000-0000-4000-8000-000000000007', 'B', 2, 2);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, net_amount, tax, total, balance, items
) values (
  '99200000-0000-4000-8000-000000000003',
  '99200000-0000-4000-8000-000000000001',
  'FC-RETURN-001', 'Return Supplier', 'draft',
  16000, 16000, 0, 16000, 16000,
  jsonb_build_array(
    jsonb_build_object(
      'line_id', '99200000-0000-4000-8000-000000000004',
      'product_id', '99200000-0000-4000-8000-000000000002',
      'product_name', 'Direct Product', 'product_sku', 'RETURN-DIRECT',
      'quantity', 10, 'unit_cost', 1000,
      'purchase_treatment', 'inventory', 'is_service', false
    ),
    jsonb_build_object(
      'line_id', '99200000-0000-4000-8000-000000000008',
      'product_id', '99200000-0000-4000-8000-000000000005',
      'product_name', 'Return Set', 'product_sku', 'RETURN-SET',
      'quantity', 2, 'unit_cost', 3000,
      'purchase_treatment', 'inventory', 'is_service', false
    )
  )
);
update public.purchase_invoices set status = 'confirmed', confirmed_date = now()
where id = '99200000-0000-4000-8000-000000000003';
insert into public.purchase_receipt_control_settings (
  tenant_id, control_mode, activated_at, activated_by
) values (
  '99200000-0000-4000-8000-000000000001', 'enforce', now(),
  '99200000-0000-4000-8000-000000000099'
);

create temp table source_receipt on commit drop as
select public.create_purchase_goods_receipt(
  '99200000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":10},{"line_index":1,"accepted_quantity":2}]'::jsonb,
  '2026-07-11 14:00:00+00', 'GUIA-RETURN-001', 'Bodega principal',
  'Receipt for supplier return tests', 'supplier-return-source-receipt'
) as payload;

select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000002'), 10, 'source receipt adds direct stock');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000006'), 2, 'source receipt adds first set component');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000007'), 4, 'source receipt adds multiplied set component');

create temp table direct_return on commit drop as
select public.create_purchase_supplier_return(
  (select (payload->>'receipt_id')::uuid from source_receipt),
  jsonb_build_array(jsonb_build_object(
    'receipt_line_id', (
      select id from public.purchase_receipt_lines
      where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt)
        and source_line_index = 0
    ),
    'returned_quantity', 4,
    'reason', 'Producto equivocado'
  )),
  '2026-07-11 15:00:00+00', 'Producto equivocado', 'ENV-RETURN-001',
  'First partial supplier return', 'supplier-return-direct-001'
) as payload;

select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000002'), 6, 'supplier return removes only the shipped direct quantity');
select is((select returned_quantity from public.purchase_supplier_return_lines where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return)), 4, 'return line stores commercial returned quantity');
select is((select previously_returned_quantity from public.purchase_supplier_return_lines where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return)), 0, 'first return records zero prior returns');
select is((select returnable_quantity_before from public.purchase_supplier_return_lines where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return)), 10, 'first return snapshots the returnable receipt quantity');
select ok(exists(
  select 1
  from public.purchase_supplier_return_line_movements mapping
  join public.stock_movements returned on returned.id = mapping.stock_movement_id
  where mapping.supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return)
    and returned.quantity = -4 and returned.stock_before = 10 and returned.stock_after = 6
), 'return movement records exact before, change, and after balances');
select ok(exists(
  select 1
  from public.purchase_supplier_return_line_movements mapping
  join public.stock_movements returned on returned.id = mapping.stock_movement_id
  where mapping.supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return)
    and returned.reversal_of_id = mapping.original_receipt_movement_id
), 'return movement points to the exact original receipt movement');
select ok(exists(
  select 1 from public.inventory_accounting_operations operation
  where operation.id = (select (payload->>'operation_id')::uuid from direct_return)
    and operation.outcome = 'completed'
), 'supplier return completes its trace operation');
select ok(exists(
  select 1 from public.inventory_accounting_checkpoints checkpoint
  where checkpoint.operation_id = (select (payload->>'operation_id')::uuid from direct_return)
    and checkpoint.phase = 'accounting_planned'
    and checkpoint.outcome = 'warning'
    and checkpoint.payload->>'reason' = 'awaiting_explicit_purchase_credit_note'
), 'trace explicitly records that no financial credit was invented');
select is((select status from public.purchase_invoices where id = '99200000-0000-4000-8000-000000000003'), 'confirmed', 'physical return leaves invoice status unchanged');
select is((select balance::numeric from public.purchase_invoices where id = '99200000-0000-4000-8000-000000000003'), 16000::numeric, 'physical return leaves AP balance unchanged');
select ok(exists(
  select 1
  from public.journal_entries entry
  where entry.operation_id = (select (payload->>'operation_id')::uuid from direct_return)
    and entry.total_debit = 4000
    and entry.total_credit = 4000
    and exists (select 1 from public.journal_lines line where line.entry_id = entry.id and line.account_code = '1145' and line.debit_amount = 4000)
    and exists (select 1 from public.journal_lines line where line.entry_id = entry.id and line.account_code = '1105' and line.credit_amount = 4000)
), 'physical supplier return reclassifies inventory value to supplier claims exactly once');

create temp table replay_return on commit drop as
select public.create_purchase_supplier_return(
  (select (payload->>'receipt_id')::uuid from source_receipt),
  jsonb_build_array(jsonb_build_object(
    'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 0),
    'returned_quantity', 4
  )),
  '2026-07-11 15:00:00+00', 'Retry', null, null, 'supplier-return-direct-001'
) as payload;
select ok((select (payload->>'replayed')::boolean from replay_return), 'supplier return retry returns the original document');
select is((select count(*)::integer from public.purchase_supplier_returns), 1, 'idempotent retry creates no second return');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000002'), 6, 'idempotent retry does not remove stock twice');

create temp table direct_return_two on commit drop as
select public.create_purchase_supplier_return(
  (select (payload->>'receipt_id')::uuid from source_receipt),
  jsonb_build_array(jsonb_build_object(
    'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 0),
    'returned_quantity', 6
  )),
  '2026-07-11 16:00:00+00', 'Return remainder', null, null, 'supplier-return-direct-002'
) as payload;
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000002'), 0, 'second partial return removes the remaining direct quantity');
select is((select previously_returned_quantity from public.purchase_supplier_return_lines where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from direct_return_two)), 4, 'second return records prior posted return quantity');

select throws_ok(
  format(
    'select public.create_purchase_supplier_return(%L::uuid, %L::jsonb, now(), %L, null, null, %L)',
    (select payload->>'receipt_id' from source_receipt),
    jsonb_build_array(jsonb_build_object(
      'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 0),
      'returned_quantity', 1
    ))::text,
    'Over return', 'supplier-return-direct-over'
  ),
  'P0001', 'Supplier return exceeds remaining received quantity',
  'over-return is rejected atomically'
);
select is((select count(*)::integer from public.purchase_supplier_returns), 2, 'failed over-return leaves no document');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000002'), 0, 'failed over-return leaves stock unchanged');

create temp table set_return_one on commit drop as
select public.create_purchase_supplier_return(
  (select (payload->>'receipt_id')::uuid from source_receipt),
  jsonb_build_array(jsonb_build_object(
    'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 1),
    'returned_quantity', 1
  )),
  '2026-07-11 17:00:00+00', 'Return one set', null, null, 'supplier-return-set-001'
) as payload;
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000006'), 1, 'set return removes first component proportionally');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000007'), 2, 'set return removes multiplied component proportionally');
select is((select count(*)::integer from public.purchase_supplier_return_line_movements where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from set_return_one)), 2, 'one commercial set return maps both physical component movements');
select is((select count(*)::integer from public.purchase_supplier_return_line_movements where supplier_return_id = (select (payload->>'supplier_return_id')::uuid from set_return_one) and movement_role = 'set_component'), 2, 'set return preserves component ownership roles');

select throws_ok(
  format(
    'select public.void_purchase_goods_receipt(%L::uuid, %L, %L)',
    (select payload->>'receipt_id' from source_receipt),
    'Cannot void downstream evidence', 'receipt-void-blocked'
  ),
  'P0001', 'Void posted supplier returns before voiding this purchase receipt',
  'receipt cannot be voided while posted supplier returns exist'
);

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products set inventory_qty = 0, stock_quantity = 0
where id = '99200000-0000-4000-8000-000000000007';
select set_config('app.skip_stock_adjustment_trigger', '', true);
select throws_ok(
  format(
    'select public.create_purchase_supplier_return(%L::uuid, %L::jsonb, now(), %L, null, null, %L)',
    (select payload->>'receipt_id' from source_receipt),
    jsonb_build_array(jsonb_build_object(
      'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 1),
      'returned_quantity', 1
    ))::text,
    'Insufficient component', 'supplier-return-set-insufficient'
  ),
  'P0001', 'Insufficient current stock for supplier return',
  'insufficient component stock rejects the whole set return'
);
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000006'), 1, 'failed set return rolls back an earlier component mutation');
select is((select count(*)::integer from public.purchase_supplier_returns), 3, 'failed set return leaves no header or partial evidence');

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products set inventory_qty = 2, stock_quantity = 2
where id = '99200000-0000-4000-8000-000000000007';
select set_config('app.skip_stock_adjustment_trigger', '', true);
create temp table set_return_two on commit drop as
select public.create_purchase_supplier_return(
  (select (payload->>'receipt_id')::uuid from source_receipt),
  jsonb_build_array(jsonb_build_object(
    'receipt_line_id', (select id from public.purchase_receipt_lines where receipt_id = (select (payload->>'receipt_id')::uuid from source_receipt) and source_line_index = 1),
    'returned_quantity', 1
  )),
  '2026-07-11 18:00:00+00', 'Return remaining set', null, null, 'supplier-return-set-002'
) as payload;
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000006'), 0, 'second set return removes remaining first component');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000007'), 0, 'second set return removes remaining multiplied component');

create temp table set_void on commit drop as
select public.void_purchase_supplier_return(
  (select (payload->>'supplier_return_id')::uuid from set_return_two),
  'Shipment cancelled before pickup', 'supplier-return-set-void-002'
) as payload;
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000006'), 1, 'voiding set return restores first component');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000007'), 2, 'voiding set return restores multiplied component');
select is((select status from public.purchase_supplier_returns where id = (select (payload->>'supplier_return_id')::uuid from set_return_two)), 'voided', 'void preserves return evidence with voided status');
select ok(exists(
  select 1 from public.stock_movements reversal
  join public.purchase_supplier_return_line_movements mapping
    on mapping.stock_movement_id = reversal.reversal_of_id
  where reversal.operation_id = (select (payload->>'operation_id')::uuid from set_void)
    and reversal.movement_type = 'purchase_supplier_return_reversal'
), 'return void movements link to the exact returned movements');
select ok((public.void_purchase_supplier_return(
  (select (payload->>'supplier_return_id')::uuid from set_return_two),
  'Shipment cancelled before pickup', 'supplier-return-set-void-002'
)->>'replayed')::boolean, 'supplier return void is idempotent');
select is((select inventory_qty from public.products where id = '99200000-0000-4000-8000-000000000007'), 2, 'void replay does not restore component stock twice');
select is((select status from public.purchase_invoices where id = '99200000-0000-4000-8000-000000000003'), 'confirmed', 'return and void sequence leaves invoice lifecycle unchanged');

select * from finish();
rollback;
