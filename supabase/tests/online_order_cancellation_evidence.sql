begin;

select plan(26);

insert into public.tenants(id, shop_name)
values
  ('9e000000-0000-4000-8000-000000000001', 'Online Cancellation Evidence'),
  ('9e000000-0000-4000-8000-000000000002', 'Online Cancellation Other Tenant');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '9e000000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
    'online-cancel@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9e000000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9e000000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
    'online-cancel-other@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9e000000-0000-4000-8000-000000000002'),
    now(), now()
  );

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Replace any trigger-created rows with deterministic staff profiles.
delete from public.user_profiles
where user_id in (
  '9e000000-0000-4000-8000-000000000099',
  '9e000000-0000-4000-8000-000000000098'
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
  (
    '9e000000-0000-4000-8000-000000000099',
    '9e000000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '9e000000-0000-4000-8000-000000000098',
    '9e000000-0000-4000-8000-000000000002',
    'admin',
    '{}'::jsonb,
    true
  );
update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
       || jsonb_build_object('tenant_id', '9e000000-0000-4000-8000-000000000001')
 where id = '9e000000-0000-4000-8000-000000000099';
update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
       || jsonb_build_object('tenant_id', '9e000000-0000-4000-8000-000000000002')
 where id = '9e000000-0000-4000-8000-000000000098';

select set_config('request.jwt.claim.sub', '9e000000-0000-4000-8000-000000000099', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e000000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values(
  '9e000000-0000-4000-8000-000000000010',
  '9e000000-0000-4000-8000-000000000001',
  'Online cancellation product', 'ONLINE-CANCEL-001', 1000, 500, 19,
  'product', false, true, 10, 10, 0, 100
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, items
)
values(
  '9e000000-0000-4000-8000-000000000011',
  '9e000000-0000-4000-8000-000000000001',
  'FV-ONLINE-CANCEL-001', 'Unpaid Online Customer', 'confirmed',
  2000, 2000, 0, 2000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e000000-0000-4000-8000-000000000010',
    'product_sku', 'ONLINE-CANCEL-001',
    'product_name', 'Online cancellation product',
    'quantity', 2, 'price', 1000, 'cost', 500,
    'is_service', false, 'purchase_treatment', 'inventory'
  ))
);

insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, total, status, payment_status, sales_invoice_id
)
values(
  '9e000000-0000-4000-8000-000000000012',
  '9e000000-0000-4000-8000-000000000001',
  'WEB-CANCEL-001', 'unpaid@example.invalid', 'Unpaid Online Customer',
  2000, 2000, 'pending', 'pending',
  '9e000000-0000-4000-8000-000000000011'
);

select is(
  (select stock_quantity from public.products where id = '9e000000-0000-4000-8000-000000000010'),
  8,
  'posted online invoice consumes stock before cancellation'
);

create temp table online_cancel_result on commit drop as
select public.cancel_online_order(
  '9e000000-0000-4000-8000-000000000012',
  'Cliente desistió antes del pago',
  0
) result;

select is(
  (select status from public.online_orders where id = '9e000000-0000-4000-8000-000000000012'),
  'cancelled',
  'unpaid order is cancelled'
);
select is(
  (select sales_invoice_id from public.online_orders where id = '9e000000-0000-4000-8000-000000000012'),
  '9e000000-0000-4000-8000-000000000011'::uuid,
  'cancellation preserves the online-order invoice link'
);
select is(
  (select status from public.sales_invoices where id = '9e000000-0000-4000-8000-000000000011'),
  'cancelled',
  'linked unpaid invoice is preserved and explicitly cancelled'
);
select is(
  (select stock_quantity from public.products where id = '9e000000-0000-4000-8000-000000000010'),
  10,
  'invoice cancellation restores stock exactly once'
);
select is(
  (select inventory_qty from public.products where id = '9e000000-0000-4000-8000-000000000010'),
  10,
  'stock columns remain synchronized after cancellation'
);
select is(
  (select refund_amount from public.online_orders where id = '9e000000-0000-4000-8000-000000000012'),
  0::numeric,
  'cancellation does not invent a refund amount'
);
select is(
  (select refunded_at from public.online_orders where id = '9e000000-0000-4000-8000-000000000012'),
  null::timestamptz,
  'cancellation does not invent a refund timestamp'
);
select ok(
  (select cancellation_operation_id is not null from public.online_orders where id = '9e000000-0000-4000-8000-000000000012'),
  'order stores its cancellation trace operation'
);
select is(
  (select outcome from public.inventory_accounting_operations
    where id = (select cancellation_operation_id from public.online_orders where id = '9e000000-0000-4000-8000-000000000012')),
  'completed',
  'cancellation trace completed its invariant checks'
);
select ok(
  exists(
    select 1
    from public.inventory_accounting_operations operation
    where operation.id = (select cancellation_operation_id from public.online_orders where id = '9e000000-0000-4000-8000-000000000012')
      and operation.context->>'invoice_operation_id' is not null
  ),
  'online cancellation links the child invoice operation'
);
select ok(
  exists(
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.operation_id = (select cancellation_operation_id from public.online_orders where id = '9e000000-0000-4000-8000-000000000012')
      and checkpoint.phase = 'completed'
      and checkpoint.payload->>'invoice_preserved' = 'true'
  ),
  'completed checkpoint exposes preserved invoice evidence'
);
select is(
  (select count(*)::integer from public.sales_invoices where id = '9e000000-0000-4000-8000-000000000011'),
  1,
  'cancellation never deletes the invoice'
);
select ok(
  exists(
    select 1 from public.journal_supersession_evidence
    where source_reference = 'FV-ONLINE-CANCEL-001'
  ),
  'posted invoice journal is preserved as immutable supersession evidence'
);

create temp table online_cancel_counts_before_replay on commit drop as
select
  (select count(*) from public.stock_movements where tenant_id = '9e000000-0000-4000-8000-000000000001') movement_count,
  (select count(*) from public.inventory_accounting_operations where tenant_id = '9e000000-0000-4000-8000-000000000001') operation_count;

select is(
  (public.cancel_online_order(
    '9e000000-0000-4000-8000-000000000012',
    'Retry del mismo comando',
    0
  )->>'replay')::boolean,
  true,
  'replayed cancellation returns the prior result'
);
select is(
  (select count(*) from public.stock_movements where tenant_id = '9e000000-0000-4000-8000-000000000001'),
  (select movement_count from online_cancel_counts_before_replay),
  'replayed cancellation creates no duplicate stock movement'
);
select is(
  (select count(*) from public.inventory_accounting_operations where tenant_id = '9e000000-0000-4000-8000-000000000001'),
  (select operation_count from online_cancel_counts_before_replay),
  'replayed cancellation creates no duplicate operation'
);

insert into public.payment_methods(id, tenant_id, code, name, account_id, default_tax_treatment)
values(
  '9e000000-0000-4000-8000-000000000020',
  '9e000000-0000-4000-8000-000000000001',
  'online_cancel_cash', 'Online cancellation cash',
  (select id from public.accounts where tenant_id = '9e000000-0000-4000-8000-000000000001' and code = '1101' limit 1),
  'no_tax'
);
insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, items
)
values(
  '9e000000-0000-4000-8000-000000000021',
  '9e000000-0000-4000-8000-000000000001',
  'FV-ONLINE-PAID-001', 'Paid Online Customer', 'confirmed',
  1000, 1000, 0, 1000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e000000-0000-4000-8000-000000000010',
    'product_sku', 'ONLINE-CANCEL-001',
    'product_name', 'Online cancellation product',
    'quantity', 1, 'price', 1000, 'cost', 500,
    'is_service', false, 'purchase_treatment', 'inventory'
  ))
);
insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key
)
values(
  '9e000000-0000-4000-8000-000000000022',
  '9e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000021',
  '9e000000-0000-4000-8000-000000000020',
  1000, 'online-paid-once'
);
insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, total, status, payment_status, payment_reference, paid_at,
  sales_invoice_id
)
values(
  '9e000000-0000-4000-8000-000000000023',
  '9e000000-0000-4000-8000-000000000001',
  'WEB-PAID-001', 'paid@example.invalid', 'Paid Online Customer',
  1000, 1000, 'confirmed', 'paid', 'provider-payment-001', now(),
  '9e000000-0000-4000-8000-000000000021'
);

select throws_ok(
  $$select public.cancel_online_order('9e000000-0000-4000-8000-000000000023', 'No corresponde', 0)$$,
  '23514',
  'Paid orders cannot be cancelled directly. Open the linked sales invoice and use Correcciones: devolución, nota de crédito y reembolso registrado.',
  'paid order cancellation is refused before any mutation'
);
select is(
  (select status from public.online_orders where id = '9e000000-0000-4000-8000-000000000023'),
  'confirmed',
  'refused paid cancellation leaves the order unchanged'
);
select is(
  (select count(*)::integer from public.sales_payments where invoice_id = '9e000000-0000-4000-8000-000000000021' and deleted_at is null),
  1,
  'refused paid cancellation preserves active payment evidence'
);
select is(
  (select status from public.sales_invoices where id = '9e000000-0000-4000-8000-000000000021'),
  'paid',
  'refused paid cancellation preserves invoice settlement status'
);
select is(
  (select stock_quantity from public.products where id = '9e000000-0000-4000-8000-000000000010'),
  9,
  'refused paid cancellation does not restore or alter stock'
);

-- Build the validation order in two deterministic phases so its immutable
-- line tax snapshot exists before the normal processing command runs.
select set_config('app.public_order_rpc_in_progress', 'true', true);
insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name, delivery_type,
  subtotal, tax_amount, shipping_cost, discount_amount, total,
  status, payment_status, payment_method
)
values(
  '9e000000-0000-4000-8000-000000000030',
  '9e000000-0000-4000-8000-000000000001',
  'WEB-VALIDATION-001', 'validation@example.invalid', 'Validation Customer',
  'pickup', 840, 160, 0, 0, 1000, 'pending', 'pending', 'transfer'
);
insert into public.online_order_items(
  id, tenant_id, order_id, product_id, product_name, product_sku,
  quantity, unit_price, subtotal, unit_cost, tax_rate, is_service,
  purchase_treatment, product_type
) values (
  '9e000000-0000-4000-8000-000000000031',
  '9e000000-0000-4000-8000-000000000001',
  '9e000000-0000-4000-8000-000000000030',
  '9e000000-0000-4000-8000-000000000010',
  'Online cancellation product', 'ONLINE-CANCEL-001',
  1, 1000, 1000, 500, 19, false, 'inventory', 'product'
);
select set_config('app.public_order_rpc_in_progress', '', true);
select public.process_online_order('9e000000-0000-4000-8000-000000000030');

select throws_ok(
  $$select public.cancel_online_order('9e000000-0000-4000-8000-000000000030', 'Invalid fraction', 0.5)$$,
  '23514',
  'Refund amount must be a non-negative whole CLP amount',
  'fractional CLP refund request is rejected'
);
select throws_ok(
  $$select public.cancel_online_order('9e000000-0000-4000-8000-000000000030', 'Invalid refund', 1)$$,
  '23514',
  'This command does not execute money refunds. Use the linked invoice Correcciones workflow.',
  'nonzero fake refund request is rejected'
);
select is(
  (select status from public.online_orders where id = '9e000000-0000-4000-8000-000000000030'),
  'confirmed',
  'invalid refund requests leave the order untouched'
);

select set_config('request.jwt.claim.sub', '9e000000-0000-4000-8000-000000000098', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '9e000000-0000-4000-8000-000000000098', 'role', 'authenticated')::text,
  true
);
select throws_ok(
  $$select public.cancel_online_order('9e000000-0000-4000-8000-000000000030', 'Cross tenant', 0)$$,
  '42501',
  'Order not found or access denied: 9e000000-0000-4000-8000-000000000030',
  'cancellation cannot cross tenant boundaries'
);

select * from finish();
rollback;
