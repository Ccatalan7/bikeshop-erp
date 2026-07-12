begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(19);

insert into public.tenants (id, shop_name)
values ('94000000-0000-4000-8000-000000000001', 'Multi-bike Payment Trace Test');

select set_config('request.jwt.claim.sub', '', true);

create temp table selected_payment_method on commit drop as
select id
from public.payment_methods
where tenant_id = '94000000-0000-4000-8000-000000000001'
order by created_at, id
limit 1;

insert into public.customers (id, tenant_id, name)
values (
  '94000000-0000-4000-8000-000000000002',
  '94000000-0000-4000-8000-000000000001',
  'Multi-bike Trace Customer'
);

insert into public.bikes (id, tenant_id, customer_id, brand, model, serial_number)
values
  (
    '94000000-0000-4000-8000-000000000003',
    '94000000-0000-4000-8000-000000000001',
    '94000000-0000-4000-8000-000000000002',
    'Trace', 'Bike One', 'TRACE-BIKE-ONE'
  ),
  (
    '94000000-0000-4000-8000-000000000004',
    '94000000-0000-4000-8000-000000000001',
    '94000000-0000-4000-8000-000000000002',
    'Trace', 'Bike Two', 'TRACE-BIKE-TWO'
  );

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values
  (
    '94000000-0000-4000-8000-000000000005',
    '94000000-0000-4000-8000-000000000001',
    'Bike One Part', 'TRACE-BIKE-ONE-PART', 2000, 1000,
    'product', false, true, 0, 0, 0, 100
  ),
  (
    '94000000-0000-4000-8000-000000000006',
    '94000000-0000-4000-8000-000000000001',
    'Bike Two Part', 'TRACE-BIKE-TWO-PART', 2000, 1000,
    'product', false, true, 0, 0, 0, 100
  );

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products
set inventory_qty = 10,
    stock_quantity = 10
where id in (
  '94000000-0000-4000-8000-000000000005',
  '94000000-0000-4000-8000-000000000006'
);
select set_config('app.skip_stock_adjustment_trigger', '', true);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance, items
)
values (
  '94000000-0000-4000-8000-000000000007',
  '94000000-0000-4000-8000-000000000001',
  'FV-MULTIBIKE-TRACE-001',
  '94000000-0000-4000-8000-000000000002',
  'Multi-bike Trace Customer',
  'mechanic_job',
  'draft',
  0, 0, 0, 0, 0, 0,
  '[]'::jsonb
);

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, status,
  invoice_id, is_invoiced, is_paid, tax_treatment
)
values (
  '94000000-0000-4000-8000-000000000008',
  '94000000-0000-4000-8000-000000000001',
  'PG-MULTIBIKE-TRACE-001',
  '94000000-0000-4000-8000-000000000002',
  '94000000-0000-4000-8000-000000000003',
  'PENDIENTE',
  '94000000-0000-4000-8000-000000000007',
  true,
  false,
  'no_tax'
);

insert into public.mechanic_job_bikes (
  id, tenant_id, job_id, bike_id, order_index
)
values
  (
    '94000000-0000-4000-8000-000000000009',
    '94000000-0000-4000-8000-000000000001',
    '94000000-0000-4000-8000-000000000008',
    '94000000-0000-4000-8000-000000000003',
    0
  ),
  (
    '94000000-0000-4000-8000-000000000010',
    '94000000-0000-4000-8000-000000000001',
    '94000000-0000-4000-8000-000000000008',
    '94000000-0000-4000-8000-000000000004',
    1
  );

update public.sales_invoices
set status = 'confirmed',
    subtotal = 10000,
    net_amount = 10000,
    total = 10000,
    balance = 10000,
    items = jsonb_build_array(
      jsonb_build_object(
        'product_id', '94000000-0000-4000-8000-000000000005',
        'product_name', 'Bike One Part',
        'product_sku', 'TRACE-BIKE-ONE-PART',
        'quantity', 2,
        'unit_price', 2000,
        'price', 2000,
        'line_total', 4000,
        'cost', 1000,
        'item_type', 'product',
        'is_service', false,
        'purchase_treatment', 'inventory',
        'job_bike_id', '94000000-0000-4000-8000-000000000009',
        'bike_name', 'Trace Bike One'
      ),
      jsonb_build_object(
        'product_id', '94000000-0000-4000-8000-000000000006',
        'product_name', 'Bike Two Part',
        'product_sku', 'TRACE-BIKE-TWO-PART',
        'quantity', 3,
        'unit_price', 2000,
        'price', 2000,
        'line_total', 6000,
        'cost', 1000,
        'item_type', 'product',
        'is_service', false,
        'purchase_treatment', 'inventory',
        'job_bike_id', '94000000-0000-4000-8000-000000000010',
        'bike_name', 'Trace Bike Two'
      )
    )
where id = '94000000-0000-4000-8000-000000000007';

select is(
  (select count(*)::integer from public.mechanic_job_items where job_id = '94000000-0000-4000-8000-000000000008'),
  2,
  'confirmed multi-bike invoice syncs both item rows to the job'
);

select is(
  (
    select count(distinct job_bike_id)::integer
    from public.mechanic_job_items
    where job_id = '94000000-0000-4000-8000-000000000008'
      and job_bike_id is not null
  ),
  2,
  'invoice-to-job sync preserves both bicycle identities'
);

select results_eq(
  $$
    select order_index, subtotal
    from public.mechanic_job_bikes
    where job_id = '94000000-0000-4000-8000-000000000008'
    order by order_index
  $$,
  $$values (0, 4000::numeric), (1, 6000::numeric)$$,
  'per-bicycle totals remain separated after invoice sync'
);

select results_eq(
  $$
    select sku, stock_quantity
    from public.products
    where id in (
      '94000000-0000-4000-8000-000000000005',
      '94000000-0000-4000-8000-000000000006'
    )
    order by sku
  $$,
  $$values ('TRACE-BIKE-ONE-PART'::text, 8), ('TRACE-BIKE-TWO-PART'::text, 7)$$,
  'confirmed shared invoice deducts each bicycle part exactly once'
);

create temp table sales_movement_baseline on commit drop as
select count(*)::integer value
from public.stock_movements
where reference = 'sales_invoice:94000000-0000-4000-8000-000000000007';

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '94000000-0000-4000-8000-000000000011',
  '94000000-0000-4000-8000-000000000001',
  '94000000-0000-4000-8000-000000000007',
  id,
  4000,
  'multibike-partial-payment-1',
  now()
from selected_payment_method;

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '94000000-0000-4000-8000-000000000007'
  $$,
  $$values ('confirmed'::text, 4000::numeric, 6000::numeric)$$,
  'partial job payment keeps the shared invoice confirmed with exact balance'
);

select is(
  (select is_paid from public.mechanic_jobs where id = '94000000-0000-4000-8000-000000000008'),
  false,
  'partial shared payment keeps the multi-bike job unpaid'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'sales_invoice:94000000-0000-4000-8000-000000000007'),
  (select value from sales_movement_baseline),
  'partial job payment creates no stock movement'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_type = 'sales_payment'
      and trace.document_id = '94000000-0000-4000-8000-000000000011'
      and trace.action = 'insert'
      and trace.source_channel = 'mechanic_job_payment'
      and trace.outcome = 'completed'
      and jsonb_array_length(trace.stock_movements) = 0
  ),
  'multi-bike partial payment has a mechanic-job payment trace with zero stock effects'
);

update public.sales_payments
set amount = 4001
where id = '94000000-0000-4000-8000-000000000011';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '94000000-0000-4000-8000-000000000007'
  $$,
  $$values ('confirmed'::text, 4001::numeric, 5999::numeric)$$,
  'one-peso edit on a partial job payment remains exact and confirmed'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'sales_invoice:94000000-0000-4000-8000-000000000007'),
  (select value from sales_movement_baseline),
  'one-peso job payment edit creates no stock movement'
);

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key, date
)
select
  '94000000-0000-4000-8000-000000000012',
  '94000000-0000-4000-8000-000000000001',
  '94000000-0000-4000-8000-000000000007',
  id,
  5999,
  'multibike-partial-payment-2',
  now() + interval '1 second'
from selected_payment_method;

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '94000000-0000-4000-8000-000000000007'
  $$,
  $$values ('paid'::text, 10000::numeric, 0::numeric)$$,
  'second partial payment completes the shared multi-bike invoice'
);

select is(
  (select is_paid from public.mechanic_jobs where id = '94000000-0000-4000-8000-000000000008'),
  true,
  'full shared payment marks the multi-bike job paid'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'sales_invoice:94000000-0000-4000-8000-000000000007'),
  (select value from sales_movement_baseline),
  'completing payment creates no stock movement'
);

delete from public.sales_payments
where id = '94000000-0000-4000-8000-000000000012';

select results_eq(
  $$
    select status, paid_amount, balance
    from public.sales_invoices
    where id = '94000000-0000-4000-8000-000000000007'
  $$,
  $$values ('confirmed'::text, 4001::numeric, 5999::numeric)$$,
  'undoing final payment returns the shared invoice to partial confirmed state'
);

select is(
  (select is_paid from public.mechanic_jobs where id = '94000000-0000-4000-8000-000000000008'),
  false,
  'undoing final payment returns the multi-bike job to unpaid'
);

select is(
  (select count(*)::integer from public.stock_movements where reference = 'sales_invoice:94000000-0000-4000-8000-000000000007'),
  (select value from sales_movement_baseline),
  'undoing multi-bike job payment creates no stock movement'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operation_trace_view trace
    where trace.document_type = 'sales_payment'
      and trace.document_id = '94000000-0000-4000-8000-000000000012'
      and trace.action = 'delete'
      and trace.outcome = 'completed'
      and jsonb_array_length(trace.stock_movements) = 0
      and exists (
        select 1 from jsonb_array_elements(trace.checkpoints) checkpoint
        where checkpoint->>'phase' = 'journal_reversed'
      )
  ),
  'multi-bike payment undo preserves its payment and journal reversal trace'
);

select hasnt_column(
  'public',
  'sales_payments',
  'job_bike_id',
  'payments are intentionally invoice/job-level, not allocated per bicycle'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_inconsistencies_view
    where tenant_id = '94000000-0000-4000-8000-000000000001'
  ),
  0,
  'multi-bike payment back-and-forth fixture surfaces no trace inconsistency'
);

select * from finish();

rollback;
