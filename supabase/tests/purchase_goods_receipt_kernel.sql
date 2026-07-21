begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(34);

insert into public.tenants (id, shop_name)
values ('99100000-0000-4000-8000-000000000001', 'Purchase Receipt Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99100000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'purchase-receipt@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99100000-0000-4000-8000-000000000001'
  ), now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '99100000-0000-4000-8000-000000000099',
  '99100000-0000-4000-8000-000000000001', 'admin'
);

update auth.users
set raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
  'tenant_id', '99100000-0000-4000-8000-000000000001'
)
where id = '99100000-0000-4000-8000-000000000099';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99100000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '99100000-0000-4000-8000-000000000099', true);

select set_config('app.product_set_composition_writer', 'migration', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
) values (
  '99100000-0000-4000-8000-000000000002',
  '99100000-0000-4000-8000-000000000001',
  'Receipt Product', 'RECEIPT-001', 2000, 1000, 'product', false,
  true, 0, 0, 0, 100
);
select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products set inventory_qty = 5, stock_quantity = 5
where id = '99100000-0000-4000-8000-000000000002';
select set_config('app.skip_stock_adjustment_trigger', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level, is_set
) values
  ('99100000-0000-4000-8000-000000000005', '99100000-0000-4000-8000-000000000001', 'Receipt Set', 'RECEIPT-SET', 5000, 3000, 'product', false, true, 0, 0, 0, 100, true),
  ('99100000-0000-4000-8000-000000000006', '99100000-0000-4000-8000-000000000001', 'Set Component A', 'SET-A', 2000, 1000, 'product', false, true, 0, 0, 0, 100, false),
  ('99100000-0000-4000-8000-000000000007', '99100000-0000-4000-8000-000000000001', 'Set Component B', 'SET-B', 3000, 2000, 'product', false, true, 0, 0, 0, 100, false);

select set_config('app.product_set_composition_writer', 'migration', true);
update public.products set
  parent_set_id = '99100000-0000-4000-8000-000000000005',
  component_label = case when id = '99100000-0000-4000-8000-000000000006'::uuid then 'A' else 'B' end,
  component_position = case when id = '99100000-0000-4000-8000-000000000006'::uuid then 1 else 2 end
where id in ('99100000-0000-4000-8000-000000000006'::uuid, '99100000-0000-4000-8000-000000000007'::uuid);
insert into public.product_set_components (
  tenant_id, set_product_id, component_product_id, component_label,
  component_position, quantity_in_set
) values
  ('99100000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000005', '99100000-0000-4000-8000-000000000006', 'A', 1, 1),
  ('99100000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000005', '99100000-0000-4000-8000-000000000007', 'B', 2, 2);
select set_config('app.product_set_composition_writer', '', true);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, net_amount, tax, total, balance, items
) values (
  '99100000-0000-4000-8000-000000000003',
  '99100000-0000-4000-8000-000000000001',
  'FC-RECEIPT-001', 'Receipt Supplier', 'draft',
  10000, 10000, 0, 10000, 10000,
  jsonb_build_array(jsonb_build_object(
    'line_id', '99100000-0000-4000-8000-000000000004',
    'product_id', '99100000-0000-4000-8000-000000000002',
    'product_name', 'Receipt Product', 'product_sku', 'RECEIPT-001',
    'quantity', 10, 'unit_cost', 1000,
    'purchase_treatment', 'inventory', 'is_service', false
  ), jsonb_build_object(
    'line_id', '99100000-0000-4000-8000-000000000008',
    'product_id', '99100000-0000-4000-8000-000000000005',
    'product_name', 'Receipt Set', 'product_sku', 'RECEIPT-SET',
    'quantity', 2, 'unit_cost', 3000,
    'purchase_treatment', 'inventory', 'is_service', false
  ))
);
update public.purchase_invoices set status = 'confirmed', confirmed_date = now()
where id = '99100000-0000-4000-8000-000000000003';

select throws_ok(
  $$ select public.create_purchase_goods_receipt(
    '99100000-0000-4000-8000-000000000003',
    '[{"line_index":0,"accepted_quantity":6}]'::jsonb,
    now(), null, null, null, 'disabled-attempt'
  ) $$,
  'P0001', 'Purchase receipt workflow is not active for this tenant',
  'receipt command is disabled by default'
);
select is(
  (select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'),
  5, 'disabled attempt leaves stock unchanged'
);

insert into public.purchase_receipt_control_settings (
  tenant_id, control_mode, activated_at, activated_by
) values (
  '99100000-0000-4000-8000-000000000001', 'enforce', now(),
  '99100000-0000-4000-8000-000000000099'
);

select throws_ok(
  $$ select public.create_purchase_goods_receipt(
    '99100000-0000-4000-8000-000000000003',
    '[{"line_index":0,"accepted_quantity":0}]'::jsonb,
    now(), null, null, null, 'receipt-noop'
  ) $$,
  'P0001', 'Receipt line must record a received or discrepancy quantity',
  'zero-effect receipt lines are rejected'
);
select throws_ok(
  $$ select public.create_purchase_goods_receipt(
    '99100000-0000-4000-8000-000000000003',
    '[{"line_index":0,"accepted_quantity":5,"damaged_quantity":1}]'::jsonb,
    now(), null, null, null, 'receipt-discrepancy-without-reason'
  ) $$,
  'P0001', 'Receipt discrepancy reason is required',
  'receipt discrepancies require an explicit reason'
);

create temp table receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  '99100000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":6,"damaged_quantity":1,"shortage_quantity":1,"discrepancy_reason":"Caja incompleta"}]'::jsonb,
  '2026-07-11 12:00:00+00', 'GUIA-001', 'Bodega principal',
  'Recepción parcial', 'receipt-attempt-001'
) as payload;

select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'), 11, 'accepted quantity increases inventory');
select is((select stock_quantity from public.products where id = '99100000-0000-4000-8000-000000000002'), 11, 'receipt keeps stock columns equal');
select is((select accepted_quantity from public.purchase_receipt_lines limit 1), 6, 'receipt stores accepted quantity');
select is((select damaged_quantity from public.purchase_receipt_lines limit 1), 1, 'receipt stores damaged quantity separately');
select is((select shortage_quantity from public.purchase_receipt_lines limit 1), 1, 'receipt stores shortage without adding stock');
select is((select remaining_quantity from public.purchase_receipt_lines limit 1), 4, 'partial receipt keeps remaining quantity open');
select is((select quantity::integer from public.stock_movements where id = (select stock_movement_id from public.purchase_receipt_lines limit 1)), 6, 'movement records only accepted quantity');
select ok(exists(select 1 from public.stock_movements where source_document_type = 'purchase_receipt' and stock_before = 5 and stock_after = 11), 'movement stores exact receipt balances and source');
select is((select status from public.purchase_invoices where id = '99100000-0000-4000-8000-000000000003'), 'confirmed', 'physical receipt does not alter payment/accounting status');
select is((select count(*)::integer from public.stock_adjustments where product_id = '99100000-0000-4000-8000-000000000002'), 0, 'receipt creates no phantom manual adjustment');
select ok(exists(select 1 from public.inventory_accounting_operations where id = ((select payload->>'operation_id' from receipt_result)::uuid) and outcome = 'completed'), 'receipt completes its trace operation');

create temp table replay_result on commit drop as
select public.create_purchase_goods_receipt(
  '99100000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":6}]'::jsonb,
  '2026-07-11 12:00:00+00', null, null, null, 'receipt-attempt-001'
) as payload;
select ok((select (payload->>'replayed')::boolean from replay_result), 'same idempotency key returns the original receipt');
select is((select count(*)::integer from public.purchase_receipts), 1, 'idempotent replay creates no second receipt');
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'), 11, 'idempotent replay creates no second stock change');

select public.create_purchase_goods_receipt(
  '99100000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":4}]'::jsonb,
  '2026-07-11 13:00:00+00', null, null, null, 'receipt-attempt-002'
);
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'), 15, 'second partial receipt accepts only the remainder');
select is((select max(previously_received_quantity) from public.purchase_receipt_lines), 6, 'second receipt records prior accepted quantity');

select throws_ok(
  $$ select public.create_purchase_goods_receipt(
    '99100000-0000-4000-8000-000000000003',
    '[{"line_index":0,"accepted_quantity":1}]'::jsonb,
    now(), null, null, null, 'receipt-attempt-003'
  ) $$,
  'P0001', 'Receipt line 0 exceeds remaining quantity',
  'over-receipt is rejected atomically'
);

create temp table void_result on commit drop as
select public.void_purchase_goods_receipt(
  (select id from public.purchase_receipts where idempotency_key = 'receipt-attempt-002'),
  'Recepción duplicada confirmada', 'receipt-void-002'
) as payload;
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'), 11, 'void removes only the selected receipt quantity');
select is((select status from public.purchase_receipts where idempotency_key = 'receipt-attempt-002'), 'voided', 'void preserves receipt evidence with voided status');
select ok(exists(
  select 1 from public.stock_movements reversal
  join public.stock_movements original on original.id = reversal.reversal_of_id
  where reversal.movement_type = 'purchase_receipt_reversal'
    and reversal.quantity = -4 and reversal.stock_before = 15 and reversal.stock_after = 11
    and original.quantity = 4
), 'void appends an exact reversal linked to the original movement');
select ok(exists(select 1 from public.inventory_accounting_operations where id = ((select payload->>'operation_id' from void_result)::uuid) and outcome = 'completed'), 'void completes its own trace operation');
select ok((select (public.void_purchase_goods_receipt(
  (select id from public.purchase_receipts where idempotency_key = 'receipt-attempt-002'),
  'Recepción duplicada confirmada', 'receipt-void-002'
)->>'replayed')::boolean), 'void retry returns the original reversal operation');
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000002'), 11, 'void replay does not remove stock twice');

create temp table set_receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  '99100000-0000-4000-8000-000000000003',
  '[{"line_index":1,"accepted_quantity":2}]'::jsonb,
  '2026-07-11 14:00:00+00', null, null, null, 'receipt-set-001'
) as payload;
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000005'), 0, 'set header never receives on-hand stock');
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000006'), 2, 'set receipt posts first component quantity');
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000007'), 4, 'set receipt multiplies component quantity_in_set');
select is((select count(*)::integer from public.purchase_receipt_line_movements where receipt_id = ((select payload->>'receipt_id' from set_receipt_result)::uuid)), 2, 'set receipt maps both component movements to one purchased line');
select is((select count(*)::integer from public.purchase_receipt_line_movements where receipt_id = ((select payload->>'receipt_id' from set_receipt_result)::uuid) and movement_role = 'set_component'), 2, 'component mappings retain their posting role');

select public.void_purchase_goods_receipt(
  (select (payload->>'receipt_id')::uuid from set_receipt_result),
  'Anulación de recepción de set', 'receipt-set-void-001'
);
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000006'), 0, 'set void reverses first component');
select is((select inventory_qty from public.products where id = '99100000-0000-4000-8000-000000000007'), 0, 'set void reverses multiplied component quantity');

select * from finish();
rollback;
