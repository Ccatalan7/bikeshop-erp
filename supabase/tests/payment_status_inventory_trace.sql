begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(26);

insert into public.tenants (id, shop_name)
values ('93000000-0000-4000-8000-000000000001', 'Payment Status Inventory Trace Test');

select set_config('request.jwt.claim.sub', '', true);

create temp table selected_payment_method on commit drop as
select id
from public.payment_methods
where tenant_id = '93000000-0000-4000-8000-000000000001'
  and coalesce(requires_reference, false) is false
order by created_at, id
limit 1;

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '93000000-0000-4000-8000-000000000002',
  '93000000-0000-4000-8000-000000000001',
  'Payment Trace Purchase Product',
  'PAYMENT-TRACE-PURCHASE',
  2000,
  1000,
  'product',
  false,
  true,
  0,
  0,
  0,
  100
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, received_date,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '93000000-0000-4000-8000-000000000003',
  '93000000-0000-4000-8000-000000000001',
  'FC-PAY-TRACE-001',
  'Payment Trace Supplier',
  'received',
  now(),
  10000,
  0,
  10000,
  0,
  10000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '93000000-0000-4000-8000-000000000002',
    'product_name', 'Payment Trace Purchase Product',
    'quantity', 5,
    'unit_cost', 1000,
    'purchase_treatment', 'inventory'
  ))
);

create temp table purchase_movement_baseline on commit drop as
select count(*)::integer value
from public.stock_movements
where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000003';

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '93000000-0000-4000-8000-000000000004',
  '93000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000003',
  id,
  4999.6,
  'purchase-payment-rounding-1',
  now()
from selected_payment_method;

select is(
  (select amount from public.purchase_payments where id = '93000000-0000-4000-8000-000000000004'),
  5000::numeric,
  'fractional purchase payment is normalized to a whole CLP peso'
);

select is(
  (select status from public.purchase_invoices where id = '93000000-0000-4000-8000-000000000003'),
  'received',
  'partial payment preserves the received workflow state'
);

select is(
  (select stock_quantity from public.products where id = '93000000-0000-4000-8000-000000000002'),
  5,
  'partial payment does not change received inventory'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000003'),
  (select value from purchase_movement_baseline),
  'partial payment creates no purchase reversal/reapply movement churn'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_type = 'purchase_payment'
      and trace.document_id = '93000000-0000-4000-8000-000000000004'
      and trace.action = 'insert'
      and trace.outcome = 'completed'
      and jsonb_array_length(trace.stock_movements) = 0
      and jsonb_array_length(trace.journal_entries) = 1
  ),
  'partial payment trace connects the payment journal and proves zero stock effects'
);

update public.purchase_payments
set amount = 5001
where id = '93000000-0000-4000-8000-000000000004';

select is(
  (select status from public.purchase_invoices where id = '93000000-0000-4000-8000-000000000003'),
  'received',
  'one-peso payment edit preserves the received workflow state'
);

select results_eq(
  $$
    select paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000003'
  $$,
  $$values (5001::numeric, 4999::numeric)$$,
  'one-peso payment edit recalculates exact whole-peso totals'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000003'),
  (select value from purchase_movement_baseline),
  'one-peso payment edit creates no inventory movement'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_type = 'purchase_payment'
      and trace.document_id = '93000000-0000-4000-8000-000000000004'
      and trace.action = 'update'
      and trace.outcome = 'completed'
      and jsonb_array_length(trace.stock_movements) = 0
      and exists (
        select 1 from jsonb_array_elements(trace.checkpoints) checkpoint
        where checkpoint->>'phase' = 'journal_reversed'
      )
  ),
  'payment edit trace preserves the replaced journal snapshot'
);

select is(
  (
    select count(*)::integer
    from public.journal_entries
    where source_module = 'purchase_payments'
      and source_reference = '93000000-0000-4000-8000-000000000004'
      and total_debit = 5001
      and total_credit = 5001
  ),
  1,
  'one-peso payment edit leaves exactly one balanced current journal'
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '93000000-0000-4000-8000-000000000005',
  '93000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000003',
  id,
  4999,
  'purchase-payment-rounding-2',
  now() + interval '1 second'
from selected_payment_method;

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000003'
  $$,
  $$values ('received'::text, 10000::numeric, 0::numeric)$$,
  'full payment preserves received status with an exact zero balance'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000003'),
  (select value from purchase_movement_baseline),
  'full payment creates no inventory movement'
);

delete from public.purchase_payments
where id = '93000000-0000-4000-8000-000000000005';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000003'
  $$,
  $$values ('received'::text, 5001::numeric, 4999::numeric)$$,
  'undoing the last payment restores the partial balance without downgrading receipt'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000003'),
  (select value from purchase_movement_baseline),
  'undoing the last payment creates no inventory movement'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_type = 'purchase_payment'
      and trace.document_id = '93000000-0000-4000-8000-000000000005'
      and trace.action = 'delete'
      and trace.outcome = 'completed'
      and jsonb_array_length(trace.stock_movements) = 0
      and jsonb_array_length(trace.journal_entries) = 0
      and exists (
        select 1 from jsonb_array_elements(trace.checkpoints) checkpoint
        where checkpoint->>'phase' = 'journal_reversed'
      )
  ),
  'payment undo trace preserves the deleted payment and journal lineage'
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, prepayment_model,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '93000000-0000-4000-8000-000000000006',
  '93000000-0000-4000-8000-000000000001',
  'FC-PREPAY-TRACE-001',
  'Prepayment Trace Supplier',
  'confirmed',
  true,
  10000,
  0,
  10000,
  0,
  10000,
  '[]'::jsonb
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '93000000-0000-4000-8000-000000000007',
  '93000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000006',
  id,
  4000,
  'prepayment-partial-1',
  now()
from selected_payment_method;

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000006'
  $$,
  $$values ('confirmed'::text, 4000::numeric, 6000::numeric)$$,
  'partial prepayment remains confirmed rather than falsely paid'
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '93000000-0000-4000-8000-000000000008',
  '93000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000006',
  id,
  6000,
  'prepayment-partial-2',
  now() + interval '1 second'
from selected_payment_method;

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000006'
  $$,
  $$values ('paid'::text, 10000::numeric, 0::numeric)$$,
  'combined prepayments mark the invoice paid only at exact full payment'
);

update public.purchase_payments
set amount = 5999
where id = '93000000-0000-4000-8000-000000000008';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000006'
  $$,
  $$values ('confirmed'::text, 9999::numeric, 1::numeric)$$,
  'one-peso reduction downgrades a prepayment from paid to confirmed'
);

update public.purchase_payments
set amount = 6000
where id = '93000000-0000-4000-8000-000000000008';

delete from public.purchase_payments
where id = '93000000-0000-4000-8000-000000000008';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000006'
  $$,
  $$values ('confirmed'::text, 4000::numeric, 6000::numeric)$$,
  'undoing the final prepayment returns to the correct partial confirmed state'
);

update public.journal_entries
set source_reference = 'FC-PREPAY-TRACE-001'
where source_module = 'purchase_payments'
  and source_reference = '93000000-0000-4000-8000-000000000007';

update public.purchase_payments
set amount = 4001
where id = '93000000-0000-4000-8000-000000000007';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000006'
  $$,
  $$values ('confirmed'::text, 4001::numeric, 5999::numeric)$$,
  'editing a uniquely matched legacy payment journal preserves exact invoice state'
);

select results_eq(
  $$
    select
      count(*) filter (
        where source_reference = '93000000-0000-4000-8000-000000000007'
      )::integer as current_journals,
      count(*) filter (
        where source_reference = 'FC-PREPAY-TRACE-001'
      )::integer as legacy_journals
    from public.journal_entries
    where source_module = 'purchase_payments'
      and source_reference in (
        '93000000-0000-4000-8000-000000000007',
        'FC-PREPAY-TRACE-001'
      )
  $$,
  $$values (1, 0)$$,
  'legacy payment edit replaces the old invoice-number journal without duplication'
);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '93000000-0000-4000-8000-000000000009',
  '93000000-0000-4000-8000-000000000001',
  'Paid Before Receipt Product',
  'PAID-BEFORE-RECEIPT',
  2000,
  1000,
  'product',
  false,
  true,
  0,
  0,
  0,
  100
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, prepayment_model,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '93000000-0000-4000-8000-000000000010',
  '93000000-0000-4000-8000-000000000001',
  'FC-PAID-BEFORE-RECEIPT-001',
  'Paid Before Receipt Supplier',
  'confirmed',
  false,
  6000,
  0,
  6000,
  0,
  6000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '93000000-0000-4000-8000-000000000009',
    'product_name', 'Paid Before Receipt Product',
    'quantity', 3,
    'unit_cost', 1000,
    'purchase_treatment', 'inventory'
  ))
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '93000000-0000-4000-8000-000000000011',
  '93000000-0000-4000-8000-000000000001',
  '93000000-0000-4000-8000-000000000010',
  id,
  6000,
  'standard-paid-before-receipt',
  now()
from selected_payment_method;

select results_eq(
  $$
    select invoice.status, product.stock_quantity
    from public.purchase_invoices invoice
    join public.products product
      on product.id = '93000000-0000-4000-8000-000000000009'
    where invoice.id = '93000000-0000-4000-8000-000000000010'
  $$,
  $$values ('paid'::text, 0)$$,
  'payment before physical receipt does not add inventory'
);

update public.purchase_invoices
set status = 'received',
    received_date = now()
where id = '93000000-0000-4000-8000-000000000010';

select is(
  (select stock_quantity from public.products where id = '93000000-0000-4000-8000-000000000009'),
  3,
  'paid-to-received transition adds physical inventory exactly once'
);

create temp table paid_before_receipt_movement_baseline on commit drop as
select count(*)::integer value
from public.stock_movements
where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000010';

delete from public.purchase_payments
where id = '93000000-0000-4000-8000-000000000011';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.purchase_invoices
    where id = '93000000-0000-4000-8000-000000000010'
  $$,
  $$values ('received'::text, 0::numeric, 6000::numeric)$$,
  'undo after receipt preserves receipt while restoring the unpaid balance'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'purchase_invoice:93000000-0000-4000-8000-000000000010'),
  (select value from paid_before_receipt_movement_baseline),
  'undo after receipt creates no inventory reversal/reapply churn'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_inconsistencies_view
    where tenant_id = '93000000-0000-4000-8000-000000000001'
  ),
  0,
  'payment back-and-forth fixture surfaces no trace inconsistency'
);

select * from finish();

rollback;
