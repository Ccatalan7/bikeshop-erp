begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(16);

insert into public.tenants(id, shop_name)
values ('99400000-0000-4000-8000-000000000001', 'Sales Invoice Discard Test');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99400000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'invoice-discard@example.invalid', '', now(),
  '{}', '{}', now(), now()
);

delete from public.user_profiles
where user_id = '99400000-0000-4000-8000-000000000099';

insert into public.user_profiles(
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '99400000-0000-4000-8000-000000000099',
  '99400000-0000-4000-8000-000000000001',
  'admin',
  '{"delete_invoices":true}'::jsonb,
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99400000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99400000-0000-4000-8000-000000000099',
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  track_stock, is_service, product_type
) values (
  '99400000-0000-4000-8000-000000000010',
  '99400000-0000-4000-8000-000000000001',
  'Test camera', 'DISCARD-CAMERA', 4000, 1590, 6, 6,
  true, false, 'product'
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  '99400000-0000-4000-8000-000000000020',
  '99400000-0000-4000-8000-000000000001',
  'FV-DISCARD-001', 'Test Customer', 'confirmed', 'manual_sale',
  8000, 8000, 0, 8000, 0, 8000, 'no_tax',
  jsonb_build_array(jsonb_build_object(
    'product_id', '99400000-0000-4000-8000-000000000010',
    'product_sku', 'DISCARD-CAMERA',
    'product_name', 'Test camera',
    'quantity', 2,
    'unit_price', 4000,
    'line_total', 8000,
    'cost', 1590,
    'is_service', false,
    'purchase_treatment', 'inventory'
  ))
);

select is(
  (select stock_quantity::integer from public.products
    where id = '99400000-0000-4000-8000-000000000010'),
  4,
  'confirmed fixture consumes two units'
);
select is(
  (select count(*)::integer from public.journal_entries
    where tenant_id = '99400000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_reference = 'FV-DISCARD-001'),
  1,
  'confirmed fixture owns exactly one invoice journal'
);

create temporary table discard_result as
select public.void_sales_invoice(
  '99400000-0000-4000-8000-000000000020',
  'Factura de prueba; la venta no ocurrió',
  'discard-test-key-001'
) as payload;

select is(
  (select status from public.sales_invoices
    where id = '99400000-0000-4000-8000-000000000020'),
  'cancelled',
  'discard marks the invoice cancelled'
);
select is(
  (select void_reason from public.sales_invoices
    where id = '99400000-0000-4000-8000-000000000020'),
  'Factura de prueba; la venta no ocurrió',
  'discard preserves the mandatory reason'
);
select is(
  (select voided_by from public.sales_invoices
    where id = '99400000-0000-4000-8000-000000000020'),
  '99400000-0000-4000-8000-000000000099'::uuid,
  'discard preserves the authenticated actor'
);
select is(
  (select stock_quantity::integer from public.products
    where id = '99400000-0000-4000-8000-000000000010'),
  6,
  'discard restores the two units'
);
select is(
  (select inventory_qty::integer from public.products
    where id = '99400000-0000-4000-8000-000000000010'),
  6,
  'both stock columns remain synchronized'
);
select is(
  (select sum(quantity)::integer from public.stock_movements
    where reference = 'sales_invoice:99400000-0000-4000-8000-000000000020'),
  0,
  'sale and reversal movements net to zero'
);
select is(
  (select count(*)::integer from public.journal_entries
    where tenant_id = '99400000-0000-4000-8000-000000000001'
      and source_module = 'sales_invoices'
      and source_reference = 'FV-DISCARD-001'),
  0,
  'discard removes the active invoice journal'
);
select is(
  (select operation.outcome
     from public.inventory_accounting_operations operation
     join public.sales_invoices invoice
       on invoice.void_operation_id = operation.id
    where invoice.id = '99400000-0000-4000-8000-000000000020'),
  'completed',
  'discard command trace completes'
);
select is(
  (select operation.action
     from public.inventory_accounting_operations operation
     join public.sales_invoices invoice
       on invoice.void_operation_id = operation.id
    where invoice.id = '99400000-0000-4000-8000-000000000020'),
  'void',
  'discard command is explicitly classified as void'
);
select ok(
  exists(
    select 1
      from public.inventory_accounting_operations child
      join public.sales_invoices invoice
        on (child.context->>'parent_operation_id')::uuid = invoice.void_operation_id
     where invoice.id = '99400000-0000-4000-8000-000000000020'
       and child.document_type = 'sales_invoice'
       and child.document_id = invoice.id
       and child.action = 'update'
       and child.outcome = 'completed'
  ),
  'command root links to the canonical invoice trigger child'
);
select ok(
  exists(
    select 1
      from public.inventory_accounting_checkpoints checkpoint
      join public.sales_invoices invoice
        on invoice.void_operation_id = checkpoint.operation_id
     where invoice.id = '99400000-0000-4000-8000-000000000020'
       and checkpoint.phase = 'journal_reversed'
       and checkpoint.outcome = 'completed'
  ),
  'discard trace records the accounting reversal checkpoint'
);

select is(
  (public.void_sales_invoice(
    '99400000-0000-4000-8000-000000000020',
    'Factura de prueba; la venta no ocurrió',
    'discard-test-key-001'
  )->>'replayed')::boolean,
  true,
  'same idempotency key replays the committed result'
);
select is(
  (select count(*)::integer from public.stock_movements
    where reference = 'sales_invoice:99400000-0000-4000-8000-000000000020'),
  2,
  'idempotent replay does not add another movement'
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  '99400000-0000-4000-8000-000000000021',
  '99400000-0000-4000-8000-000000000001',
  'FV-DISCARD-PAID', 'Test Customer', 'paid', 'manual_sale',
  1000, 1000, 0, 1000, 1000, 0, 'no_tax', '[]'
);

insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, date
)
select
  '99400000-0000-4000-8000-000000000022',
  '99400000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000021',
  method.id,
  1000,
  'no_tax',
  1000,
  0,
  now()
from public.payment_methods method
where method.tenant_id = '99400000-0000-4000-8000-000000000001'
  and method.code = 'cash';

select throws_ok($$
  select public.void_sales_invoice(
    '99400000-0000-4000-8000-000000000021',
    'Should not discard money received',
    'discard-test-paid'
  )
$$, '23514',
  'Una factura pagada representa dinero recibido. Usa devolución o nota de crédito, no Descartar factura.',
  'paid invoices require the post-sale correction workflow'
);

select * from finish();
rollback;
