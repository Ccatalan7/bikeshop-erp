begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.inventory_operation_id', '', true);
select set_config('app.inventory_source_document_type', '', true);
select set_config('app.inventory_source_document_id', '', true);
select set_config('app.inventory_source_channel', '', true);
select set_config('app.inventory_trace_context_stack', '[]', true);

select plan(18);

insert into public.tenants (id, shop_name)
values (
  '99717000-0000-4000-8000-000000000001',
  'Invoice Payment Trace Upsert Test'
);

select set_config('request.jwt.claim.sub', '', true);

create temp table selected_payment_method on commit drop as
select id
from public.payment_methods
where tenant_id = '99717000-0000-4000-8000-000000000001'
order by created_at, id
limit 1;

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
)
values (
  '99717000-0000-4000-8000-000000000002',
  '99717000-0000-4000-8000-000000000001',
  'FV-UPSERT-TRACE-001',
  'Sales Upsert Customer',
  'manual_sale',
  'confirmed',
  1000, 1000, 0, 1000, 0, 1000,
  'no_tax',
  '[]'::jsonb
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, received_date,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '99717000-0000-4000-8000-000000000003',
  '99717000-0000-4000-8000-000000000001',
  'FC-UPSERT-TRACE-001',
  'Purchase Upsert Supplier',
  'received',
  now(),
  1000, 0, 1000, 0, 1000,
  '[]'::jsonb
);

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000004',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000002',
  id,
  100,
  'no_tax',
  100,
  0,
  'sales-upsert-existing',
  'sales-before',
  now()
from selected_payment_method;

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000005',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000003',
  id,
  100,
  'purchase-upsert-existing',
  'purchase-before',
  now()
from selected_payment_method;

select ok(
  nullif(current_setting('app.inventory_operation_id', true), '') is null
  and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'ordinary invoice/payment inserts finish with empty trace context'
);

create temp table operations_before_do_nothing on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

-- BEFORE INSERT still fires for these conflicts, but canonical INSERT tracing
-- starts only in successful AFTER INSERT and therefore creates no orphan root.
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
)
values (
  '99717000-0000-4000-8000-000000000002',
  '99717000-0000-4000-8000-000000000001',
  'FV-UPSERT-TRACE-001', 'Ignored', 'manual_sale', 'confirmed',
  1000, 1000, 0, 1000, 100, 900, 'no_tax', '[]'::jsonb
)
on conflict (id) do nothing;

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, received_date,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '99717000-0000-4000-8000-000000000003',
  '99717000-0000-4000-8000-000000000001',
  'FC-UPSERT-TRACE-001', 'Ignored', 'received', now(),
  1000, 0, 1000, 100, 900, '[]'::jsonb
)
on conflict (id) do nothing;

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000004',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000002',
  id, 100, 'no_tax', 100, 0, 'sales-upsert-existing', 'ignored', now()
from selected_payment_method
on conflict (id) do nothing;

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000005',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000003',
  id, 100, 'purchase-upsert-existing', 'ignored', now()
from selected_payment_method
on conflict (id) do nothing;

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and not exists (
        select 1 from operations_before_do_nothing baseline
        where baseline.id = operation.id
      )
  ),
  0,
  'DO NOTHING on all four traced tables creates no operation root'
);
select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations
    where tenant_id = '99717000-0000-4000-8000-000000000001'
      and outcome = 'started'
  ),
  0,
  'DO NOTHING leaves no latent started operation'
);
select ok(
  nullif(current_setting('app.inventory_operation_id', true), '') is null
  and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'DO NOTHING leaves operation GUC and context stack empty'
);

create temp table operations_before_do_update on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
)
values (
  '99717000-0000-4000-8000-000000000002',
  '99717000-0000-4000-8000-000000000001',
  'FV-UPSERT-TRACE-001', 'Sales Upsert Changed', 'manual_sale', 'confirmed',
  1000, 1000, 0, 1000, 100, 900, 'no_tax', '[]'::jsonb
)
on conflict (id) do update
set customer_name = excluded.customer_name;

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, received_date,
  subtotal, tax, total, paid_amount, balance, items
)
values (
  '99717000-0000-4000-8000-000000000003',
  '99717000-0000-4000-8000-000000000001',
  'FC-UPSERT-TRACE-001', 'Purchase Upsert Changed', 'received', now(),
  1000, 0, 1000, 100, 900, '[]'::jsonb
)
on conflict (id) do update
set supplier_name = excluded.supplier_name;

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000004',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000002',
  id, 100, 'no_tax', 100, 0, 'sales-upsert-existing', 'sales-after', now()
from selected_payment_method
on conflict (id) do update
set reference = excluded.reference;

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  idempotency_key, reference, date
)
select
  '99717000-0000-4000-8000-000000000005',
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000003',
  id, 100, 'purchase-upsert-existing', 'purchase-after', now()
from selected_payment_method
on conflict (id) do update
set reference = excluded.reference;

create temp table do_update_operations on commit drop as
select operation.*
from public.inventory_accounting_operations operation
where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
  and not exists (
    select 1 from operations_before_do_update baseline
    where baseline.id = operation.id
  );

select is(
  (select count(*)::integer from do_update_operations),
  4,
  'DO UPDATE creates one root for each of the four traced rows'
);
select results_eq(
  $$
    select document_type, action, count(*)::integer
    from do_update_operations
    group by document_type, action
    order by document_type
  $$,
  $$
    values
      ('purchase_invoice'::text, 'update'::text, 1),
      ('purchase_payment'::text, 'update'::text, 1),
      ('sales_invoice'::text, 'update'::text, 1),
      ('sales_payment'::text, 'update'::text, 1)
  $$,
  'DO UPDATE records only UPDATE identities and never an INSERT orphan'
);
select is(
  (select count(*)::integer from do_update_operations where outcome = 'completed'),
  4,
  'every DO UPDATE root completes'
);
select ok(
  nullif(current_setting('app.inventory_operation_id', true), '') is null
  and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'DO UPDATE restores the transaction trace context'
);

-- One mixed multi-row UPSERT proves the successful INSERT and conflicting
-- UPDATE paths can coexist in one statement without sharing row identity.
create temp table operations_before_mixed_sales_invoice on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, source, status,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
)
values
  (
    '99717000-0000-4000-8000-000000000002',
    '99717000-0000-4000-8000-000000000001',
    'FV-UPSERT-TRACE-001', 'Sales Mixed Update', 'manual_sale', 'confirmed',
    1000, 1000, 0, 1000, 100, 900, 'no_tax', '[]'::jsonb
  ),
  (
    '99717000-0000-4000-8000-000000000012',
    '99717000-0000-4000-8000-000000000001',
    'FV-UPSERT-TRACE-002', 'Sales Mixed Insert', 'manual_sale', 'draft',
    0, 0, 0, 0, 0, 0, 'no_tax', '[]'::jsonb
  )
on conflict (id) do update
set customer_name = excluded.customer_name;

select results_eq(
  $$
    select action, count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.document_type = 'sales_invoice'
      and not exists (
        select 1 from operations_before_mixed_sales_invoice baseline
        where baseline.id = operation.id
      )
    group by action
    order by action
  $$,
  $$values ('insert'::text, 1), ('update'::text, 1)$$,
  'mixed multi-row sales invoice UPSERT creates one INSERT and one UPDATE root'
);
select ok(
  not exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.outcome = 'started'
  ) and nullif(current_setting('app.inventory_operation_id', true), '') is null,
  'mixed invoice UPSERT completes both roots and restores context'
);

create temp table operations_before_mixed_purchase_invoice on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status,
  subtotal, tax, total, paid_amount, balance, items
)
values
  (
    '99717000-0000-4000-8000-000000000003',
    '99717000-0000-4000-8000-000000000001',
    'FC-UPSERT-TRACE-001', 'Purchase Mixed Update', 'received',
    1000, 0, 1000, 100, 900, '[]'::jsonb
  ),
  (
    '99717000-0000-4000-8000-000000000013',
    '99717000-0000-4000-8000-000000000001',
    'FC-UPSERT-TRACE-002', 'Purchase Mixed Insert', 'draft',
    0, 0, 0, 0, 0, '[]'::jsonb
  )
on conflict (id) do update
set supplier_name = excluded.supplier_name;

select results_eq(
  $$
    select action, count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.document_type = 'purchase_invoice'
      and not exists (
        select 1 from operations_before_mixed_purchase_invoice baseline
        where baseline.id = operation.id
      )
    group by action
    order by action
  $$,
  $$values ('insert'::text, 1), ('update'::text, 1)$$,
  'mixed multi-row purchase invoice UPSERT creates one INSERT and one UPDATE root'
);
select ok(
  not exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.outcome = 'started'
  ) and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'mixed purchase invoice UPSERT completes both roots and clears frames'
);

create temp table operations_before_mixed_sales_payment on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  payment.id,
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000002',
  method.id,
  payment.amount,
  'no_tax', payment.amount, 0,
  payment.idempotency_key,
  payment.reference,
  now()
from selected_payment_method method
cross join (
  values
    ('99717000-0000-4000-8000-000000000004'::uuid, 100::numeric,
     'sales-upsert-existing'::text, 'sales-mixed-update'::text),
    ('99717000-0000-4000-8000-000000000014'::uuid, 200::numeric,
     'sales-upsert-new'::text, 'sales-mixed-insert'::text)
) payment(id, amount, idempotency_key, reference)
on conflict (id) do nothing;

select results_eq(
  $$
    select action, count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.document_type = 'sales_payment'
      and not exists (
        select 1 from operations_before_mixed_sales_payment baseline
        where baseline.id = operation.id
      )
    group by action
    order by action
  $$,
  $$values ('insert'::text, 1)$$,
  'mixed multi-row sales payment UPSERT traces the insert and ignores the conflict'
);
select ok(
  not exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.outcome = 'started'
  ) and nullif(current_setting('app.inventory_operation_id', true), '') is null,
  'mixed sales payment UPSERT completes both roots and restores its invoice parent'
);

create temp table operations_before_mixed_purchase_payment on commit drop as
select id from public.inventory_accounting_operations
where tenant_id = '99717000-0000-4000-8000-000000000001';

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount,
  idempotency_key, reference, date
)
select
  payment.id,
  '99717000-0000-4000-8000-000000000001',
  '99717000-0000-4000-8000-000000000003',
  method.id,
  payment.amount,
  payment.idempotency_key,
  payment.reference,
  now()
from selected_payment_method method
cross join (
  values
    ('99717000-0000-4000-8000-000000000005'::uuid, 100::numeric,
     'purchase-upsert-existing'::text, 'purchase-mixed-update'::text),
    ('99717000-0000-4000-8000-000000000015'::uuid, 200::numeric,
     'purchase-upsert-new'::text, 'purchase-mixed-insert'::text)
) payment(id, amount, idempotency_key, reference)
on conflict (id) do nothing;

select results_eq(
  $$
    select action, count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.document_type = 'purchase_payment'
      and not exists (
        select 1 from operations_before_mixed_purchase_payment baseline
        where baseline.id = operation.id
      )
    group by action
    order by action
  $$,
  $$values ('insert'::text, 1)$$,
  'mixed multi-row purchase payment UPSERT traces the insert and ignores the conflict'
);
select ok(
  not exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = '99717000-0000-4000-8000-000000000001'
      and operation.outcome = 'started'
  ) and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'mixed purchase payment UPSERT completes both roots and clears frames'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations
    where tenant_id = '99717000-0000-4000-8000-000000000001'
      and outcome = 'started'
  ),
  0,
  'the complete UPSERT fixture leaves no latent started operation'
);
select ok(
  nullif(current_setting('app.inventory_operation_id', true), '') is null
  and nullif(current_setting('app.inventory_source_document_type', true), '') is null
  and nullif(current_setting('app.inventory_source_document_id', true), '') is null
  and nullif(current_setting('app.inventory_source_channel', true), '') is null
  and coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), '')::jsonb,
    '[]'::jsonb
  ) = '[]'::jsonb,
  'all operation/source GUCs and frame stack are empty at fixture end'
);

select * from finish();

rollback;
