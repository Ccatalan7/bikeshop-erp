begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(8);

create temp table payment_integrity_results (
  name text primary key,
  passed boolean not null,
  message text
) on commit drop;

insert into public.tenants (id, shop_name)
values ('81111111-1111-4111-8111-111111111111', 'Payment Integrity Test');

insert into public.accounts (id, tenant_id, code, name, type, category)
values (
  '82222222-2222-4222-8222-222222222222',
  '81111111-1111-4111-8111-111111111111',
  '1101',
  'Caja',
  'asset',
  'currentAsset'
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
values (
  '83333333-3333-4333-8333-333333333333',
  '81111111-1111-4111-8111-111111111111',
  'cash',
  'Efectivo',
  '82222222-2222-4222-8222-222222222222',
  'no_tax'
);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, total, paid_amount, balance
)
values (
  '84444444-4444-4444-8444-444444444444',
  '81111111-1111-4111-8111-111111111111',
  'FV-PAY-GUARD-001',
  'Cliente Test',
  'confirmed',
  10000,
  0,
  10000
);

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key
)
values (
  '85555555-5555-4555-8555-555555555555',
  '81111111-1111-4111-8111-111111111111',
  '84444444-4444-4444-8444-444444444444',
  '83333333-3333-4333-8333-333333333333',
  5000,
  'sales-once'
);

select is(
  (select balance from public.sales_invoices where id = '84444444-4444-4444-8444-444444444444'),
  5000::numeric,
  'sales payment recalculates remaining balance'
);

do $$
begin
  insert into public.sales_payments (
    tenant_id, invoice_id, payment_method_id, amount, idempotency_key
  )
  values (
    '81111111-1111-4111-8111-111111111111',
    '84444444-4444-4444-8444-444444444444',
    '83333333-3333-4333-8333-333333333333',
    5001,
    'sales-overpay'
  );

  insert into payment_integrity_results values ('sales_overpay', false, 'insert unexpectedly succeeded');
exception
  when others then
    insert into payment_integrity_results
    values ('sales_overpay', sqlerrm like 'El pago excede el saldo pendiente%', sqlerrm);
end $$;

select ok(
  (select passed from payment_integrity_results where name = 'sales_overpay'),
  'sales rejects one peso over the remaining balance'
);

do $$
begin
  insert into public.sales_payments (
    tenant_id, invoice_id, payment_method_id, amount, idempotency_key
  )
  values (
    '81111111-1111-4111-8111-111111111111',
    '84444444-4444-4444-8444-444444444444',
    '83333333-3333-4333-8333-333333333333',
    1000,
    'sales-once'
  );

  insert into payment_integrity_results values ('sales_idempotency', false, 'insert unexpectedly succeeded');
exception
  when unique_violation then
    insert into payment_integrity_results values ('sales_idempotency', true, sqlerrm);
  when others then
    insert into payment_integrity_results values ('sales_idempotency', false, sqlerrm);
end $$;

select ok(
  (select passed from payment_integrity_results where name = 'sales_idempotency'),
  'sales idempotency key prevents duplicate payment rows'
);

update public.sales_payments
   set deleted_at = now()
 where id = '85555555-5555-4555-8555-555555555555';

select is(
  (select balance from public.sales_invoices where id = '84444444-4444-4444-8444-444444444444'),
  10000::numeric,
  'sales soft-deleted payments no longer count toward balance'
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_name, status, total, paid_amount, balance
)
values (
  '86666666-6666-4666-8666-666666666666',
  '81111111-1111-4111-8111-111111111111',
  'FC-PAY-GUARD-001',
  'Proveedor Test',
  'received',
  10000,
  0,
  10000
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, idempotency_key
)
values (
  '87777777-7777-4777-8777-777777777777',
  '81111111-1111-4111-8111-111111111111',
  '86666666-6666-4666-8666-666666666666',
  '83333333-3333-4333-8333-333333333333',
  5000,
  'purchase-once'
);

select is(
  (select balance from public.purchase_invoices where id = '86666666-6666-4666-8666-666666666666'),
  5000::numeric,
  'purchase payment recalculates remaining balance'
);

do $$
begin
  insert into public.purchase_payments (
    tenant_id, invoice_id, payment_method_id, amount, idempotency_key
  )
  values (
    '81111111-1111-4111-8111-111111111111',
    '86666666-6666-4666-8666-666666666666',
    '83333333-3333-4333-8333-333333333333',
    5001,
    'purchase-overpay'
  );

  insert into payment_integrity_results values ('purchase_overpay', false, 'insert unexpectedly succeeded');
exception
  when others then
    insert into payment_integrity_results
    values ('purchase_overpay', sqlerrm like 'El pago excede el saldo pendiente%', sqlerrm);
end $$;

select ok(
  (select passed from payment_integrity_results where name = 'purchase_overpay'),
  'purchase rejects one peso over the remaining balance'
);

do $$
begin
  insert into public.purchase_payments (
    tenant_id, invoice_id, payment_method_id, amount, idempotency_key
  )
  values (
    '81111111-1111-4111-8111-111111111111',
    '86666666-6666-4666-8666-666666666666',
    '83333333-3333-4333-8333-333333333333',
    1000,
    'purchase-once'
  );

  insert into payment_integrity_results values ('purchase_idempotency', false, 'insert unexpectedly succeeded');
exception
  when unique_violation then
    insert into payment_integrity_results values ('purchase_idempotency', true, sqlerrm);
  when others then
    insert into payment_integrity_results values ('purchase_idempotency', false, sqlerrm);
end $$;

select ok(
  (select passed from payment_integrity_results where name = 'purchase_idempotency'),
  'purchase idempotency key prevents duplicate payment rows'
);

select ok(
  exists (
    select 1
      from public.journal_entries
     where tenant_id = '81111111-1111-4111-8111-111111111111'
       and source_module = 'purchase_payments'
       and source_reference = '87777777-7777-4777-8777-777777777777'
  ),
  'purchase payment journal entry is keyed by payment id'
);

select * from finish();

rollback;
