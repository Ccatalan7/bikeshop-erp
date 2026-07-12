begin;

select plan(29);

insert into public.tenants(id, shop_name)
values
  ('9f000000-0000-4000-8000-000000000001', 'Online Manual Payment Test'),
  ('9f000000-0000-4000-8000-000000000002', 'Online Manual Payment Other');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    '9f000000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
    'online-payment@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9f000000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f000000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
    'online-payment-other@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9f000000-0000-4000-8000-000000000002'),
    now(), now()
  );

update public.user_profiles
   set tenant_id = '9f000000-0000-4000-8000-000000000001', role = 'admin'
 where user_id = '9f000000-0000-4000-8000-000000000099';
update public.user_profiles
   set tenant_id = '9f000000-0000-4000-8000-000000000002', role = 'admin'
 where user_id = '9f000000-0000-4000-8000-000000000098';
update auth.users
   set raw_user_meta_data = raw_user_meta_data
       || jsonb_build_object('tenant_id', '9f000000-0000-4000-8000-000000000001')
 where id = '9f000000-0000-4000-8000-000000000099';
update auth.users
   set raw_user_meta_data = raw_user_meta_data
       || jsonb_build_object('tenant_id', '9f000000-0000-4000-8000-000000000002')
 where id = '9f000000-0000-4000-8000-000000000098';

select set_config('request.jwt.claim.sub', '9f000000-0000-4000-8000-000000000099', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '9f000000-0000-4000-8000-000000000099', 'role', 'authenticated')::text,
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
)
values(
  '9f000000-0000-4000-8000-000000000010',
  '9f000000-0000-4000-8000-000000000001',
  'Online transfer product', 'ONLINE-TRANSFER-001', 1000, 400,
  'product', false, true, 10, 10, 0, 100, true, true, true
);

create temp table online_payment_ids(name text primary key, id uuid not null) on commit drop;
insert into online_payment_ids
select 'order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9f000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'manual-payment-order-001',
    'customer_email', 'bank@example.invalid',
    'customer_name', 'Bank Customer',
    'customer_address', 'Transfer Street 1',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Transfer Street 1',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9f000000-0000-4000-8000-000000000010',
    'quantity', 2
  ))
);

select is(
  (select invoice.status from public.online_orders orders join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id where orders.id = (select id from online_payment_ids where name = 'order')),
  'sent',
  'transfer checkout creates a non-posted invoice awaiting confirmation'
);
select is(
  (select stock_quantity from public.products where id = '9f000000-0000-4000-8000-000000000010'),
  10,
  'pending transfer does not consume inventory'
);

select throws_ok(
  format(
    $$select public.confirm_online_order_payment(%L::uuid, null, now())$$,
    (select id from online_payment_ids where name = 'order')
  ),
  '23514',
  'A bank/payment reference is required for manual confirmation',
  'manual confirmation requires auditable payment reference'
);
select throws_ok(
  format(
    $$select public.confirm_online_order_payment(%L::uuid, 'BANK-FUTURE', now() + interval '1 day')$$,
    (select id from online_payment_ids where name = 'order')
  ),
  '23514',
  'Payment date cannot be in the future',
  'future payment date is rejected'
);
select is(
  (select count(*)::integer from public.sales_payments payment join public.online_orders orders on orders.sales_invoice_id = payment.invoice_id where orders.id = (select id from online_payment_ids where name = 'order')),
  0,
  'failed validations create no payment row'
);

insert into online_payment_ids
select 'payment', public.confirm_online_order_payment(
  (select id from online_payment_ids where name = 'order'),
  'BANK-TRANSFER-001',
  clock_timestamp()
);

select is(
  (select payment_status from public.online_orders where id = (select id from online_payment_ids where name = 'order')),
  'paid',
  'successful confirmation marks order paid'
);
select is(
  (select manual_payment_id from public.online_orders where id = (select id from online_payment_ids where name = 'order')),
  (select id from online_payment_ids where name = 'payment'),
  'order retains the exact manual payment identity'
);
select ok(
  (select payment_confirmation_operation_id is not null from public.online_orders where id = (select id from online_payment_ids where name = 'order')),
  'order retains the parent confirmation operation'
);
select is(
  (select invoice.status from public.sales_invoices invoice join public.online_orders orders on orders.sales_invoice_id = invoice.id where orders.id = (select id from online_payment_ids where name = 'order')),
  'paid',
  'linked invoice settles to paid'
);
select is(
  (select paid_amount from public.sales_invoices invoice join public.online_orders orders on orders.sales_invoice_id = invoice.id where orders.id = (select id from online_payment_ids where name = 'order')),
  2000::numeric,
  'invoice paid amount equals the exact order total'
);
select is(
  (select balance from public.sales_invoices invoice join public.online_orders orders on orders.sales_invoice_id = invoice.id where orders.id = (select id from online_payment_ids where name = 'order')),
  0::numeric,
  'invoice balance is zero without decimal residue'
);
select is(
  (select amount from public.sales_payments where id = (select id from online_payment_ids where name = 'payment')),
  2000::numeric,
  'one exact whole-CLP payment is recorded'
);
select is(
  (select reference from public.sales_payments where id = (select id from online_payment_ids where name = 'payment')),
  'BANK-TRANSFER-001',
  'payment evidence stores the bank reference'
);
select is(
  (select idempotency_key from public.sales_payments where id = (select id from online_payment_ids where name = 'payment')),
  'online_order_manual_payment:' || (select id::text from online_payment_ids where name = 'order'),
  'payment has a deterministic idempotency key'
);
select is(
  (select stock_quantity from public.products where id = '9f000000-0000-4000-8000-000000000010'),
  8,
  'manual confirmation consumes inventory exactly once through the invoice'
);
select is(
  (select inventory_qty from public.products where id = '9f000000-0000-4000-8000-000000000010'),
  8,
  'both stock columns remain synchronized'
);
select is(
  (select count(*)::integer from public.journal_entries where source_module = 'sales_payments' and source_reference = (select id::text from online_payment_ids where name = 'payment')),
  1,
  'payment owns exactly one posted journal'
);
select is(
  (select count(*)::integer from (
    select entry.id from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.source_reference in (
      (select id::text from online_payment_ids where name = 'payment'),
      (select invoice.invoice_number from public.sales_invoices invoice join public.online_orders orders on orders.sales_invoice_id = invoice.id where orders.id = (select id from online_payment_ids where name = 'order'))
    )
    group by entry.id having sum(line.debit_amount) <> sum(line.credit_amount)
  ) broken),
  0,
  'invoice and payment journals are balanced'
);
select is(
  (select outcome from public.inventory_accounting_operations where id = (select payment_confirmation_operation_id from public.online_orders where id = (select id from online_payment_ids where name = 'order'))),
  'completed',
  'parent confirmation operation completes invariant checks'
);
select ok(
  (select context->>'invoice_operation_id' is not null and context->>'payment_operation_id' is not null
   from public.inventory_accounting_operations where id = (select payment_confirmation_operation_id from public.online_orders where id = (select id from online_payment_ids where name = 'order'))),
  'parent operation links invoice and payment child operations'
);
select is(
  (select count(*)::integer from public.stock_movements movement
   join public.inventory_accounting_operations operation on operation.id = movement.operation_id
   where operation.document_type = 'sales_payment'
     and operation.document_id = (select id from online_payment_ids where name = 'payment')),
  0,
  'payment child operation has zero stock movements'
);

create temp table online_payment_counts_before_replay on commit drop as
select
  (select count(*) from public.sales_payments where tenant_id = '9f000000-0000-4000-8000-000000000001') payment_count,
  (select count(*) from public.stock_movements where tenant_id = '9f000000-0000-4000-8000-000000000001') movement_count,
  (select count(*) from public.inventory_accounting_operations where tenant_id = '9f000000-0000-4000-8000-000000000001') operation_count;

select is(
  public.confirm_online_order_payment(
    (select id from online_payment_ids where name = 'order'),
    'BANK-TRANSFER-001-RETRY', clock_timestamp()
  ),
  (select id from online_payment_ids where name = 'payment'),
  'replay returns the exact original payment'
);
select is(
  (select count(*) from public.sales_payments where tenant_id = '9f000000-0000-4000-8000-000000000001'),
  (select payment_count from online_payment_counts_before_replay),
  'replay creates no duplicate payment'
);
select is(
  (select count(*) from public.stock_movements where tenant_id = '9f000000-0000-4000-8000-000000000001'),
  (select movement_count from online_payment_counts_before_replay),
  'replay creates no duplicate movement'
);
select is(
  (select count(*) from public.inventory_accounting_operations where tenant_id = '9f000000-0000-4000-8000-000000000001'),
  (select operation_count from online_payment_counts_before_replay),
  'replay creates no duplicate operation'
);

insert into online_payment_ids
select 'partial_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9f000000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'manual-payment-partial-001',
    'customer_email', 'partial@example.invalid',
    'customer_name', 'Partial Customer',
    'customer_address', 'Partial Street 1',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Partial Street 1',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9f000000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);
update public.sales_invoices
   set status = 'confirmed'
 where id = (select sales_invoice_id from public.online_orders where id = (select id from online_payment_ids where name = 'partial_order'));
insert into public.sales_payments(
  tenant_id, invoice_id, payment_method_id, idempotency_key, amount, reference
)
select
  '9f000000-0000-4000-8000-000000000001', orders.sales_invoice_id,
  method.id, 'existing-partial-payment', 500, 'BANK-PARTIAL-001'
from public.online_orders orders
join public.payment_methods method
  on method.tenant_id = orders.tenant_id and method.code = 'transfer'
where orders.id = (select id from online_payment_ids where name = 'partial_order')
limit 1;

select throws_ok(
  format(
    $$select public.confirm_online_order_payment(%L::uuid, 'BANK-PARTIAL-REMAINDER', now())$$,
    (select id from online_payment_ids where name = 'partial_order')
  ),
  '23514',
  'This invoice already has payments. Use the invoice payment workspace for partial or corrective settlement.',
  'shortcut refuses an invoice with a pre-existing partial payment'
);
select is(
  (select count(*)::integer from public.sales_payments payment join public.online_orders orders on orders.sales_invoice_id = payment.invoice_id where orders.id = (select id from online_payment_ids where name = 'partial_order') and payment.deleted_at is null),
  1,
  'partial-payment refusal leaves the existing payment untouched'
);
select is(
  (select payment_status from public.online_orders where id = (select id from online_payment_ids where name = 'partial_order')),
  'pending',
  'partial-payment refusal does not falsely mark the order paid'
);

select set_config('request.jwt.claim.sub', '9f000000-0000-4000-8000-000000000098', true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '9f000000-0000-4000-8000-000000000098', 'role', 'authenticated')::text,
  true
);
select throws_ok(
  format(
    $$select public.confirm_online_order_payment(%L::uuid, 'CROSS-TENANT', now())$$,
    (select id from online_payment_ids where name = 'partial_order')
  ),
  '42501',
  'Order not found or access denied: ' || (select id::text from online_payment_ids where name = 'partial_order'),
  'manual confirmation cannot cross tenant boundaries'
);

select * from finish();
rollback;
