begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(7);

insert into public.tenants(id, shop_name)
values ('99800000-0000-4000-8000-000000000001', 'Sales Correction Status Test');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.syncing_job_to_invoice', 'true', true);
insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, balance, tax_treatment, items
) values
('99800000-0000-4000-8000-000000000010','99800000-0000-4000-8000-000000000001','FV-GUARD-SENT','Customer','sent',1000,1000,0,1000,1000,'no_tax','[]'),
('99800000-0000-4000-8000-000000000011','99800000-0000-4000-8000-000000000001','FV-GUARD-CONFIRMED','Customer','confirmed',1000,1000,0,1000,1000,'no_tax','[]'),
('99800000-0000-4000-8000-000000000012','99800000-0000-4000-8000-000000000001','FV-GUARD-PAID','Customer','paid',1000,1000,0,1000,0,'no_tax','[]');
select set_config('app.syncing_job_to_invoice', '', true);

insert into public.inventory_accounting_operations(
  id, tenant_id, operation_key, source_channel, action,
  document_type, document_id, executor
) values
('99800000-0000-4000-8000-000000000020','99800000-0000-4000-8000-000000000001','guard:return:sent','sales_return','create','sales_return','99800000-0000-4000-8000-000000000030','database_command'),
('99800000-0000-4000-8000-000000000021','99800000-0000-4000-8000-000000000001','guard:return:confirmed','sales_return','create','sales_return','99800000-0000-4000-8000-000000000031','database_command'),
('99800000-0000-4000-8000-000000000022','99800000-0000-4000-8000-000000000001','guard:return:paid','sales_return','create','sales_return','99800000-0000-4000-8000-000000000032','database_command'),
('99800000-0000-4000-8000-000000000023','99800000-0000-4000-8000-000000000001','guard:credit:sent','sales_credit_note','create','sales_credit_note','99800000-0000-4000-8000-000000000033','database_command'),
('99800000-0000-4000-8000-000000000024','99800000-0000-4000-8000-000000000001','guard:credit:confirmed','sales_credit_note','create','sales_credit_note','99800000-0000-4000-8000-000000000034','database_command');

insert into public.journal_entries(
  id, tenant_id, entry_number, description, type, status,
  total_debit, total_credit, operation_id,
  source_document_type, source_document_id
) values (
  '99800000-0000-4000-8000-000000000040',
  '99800000-0000-4000-8000-000000000001',
  'JE-GUARD-001', 'Guard fixture', 'sales_credit_note', 'posted',
  1000, 1000, '99800000-0000-4000-8000-000000000024',
  'sales_credit_note', '99800000-0000-4000-8000-000000000034'
);

select throws_ok($$
  insert into public.sales_returns(
    id, tenant_id, sales_invoice_id, return_number, returned_at,
    reason, idempotency_key, operation_id
  ) values (
    '99800000-0000-4000-8000-000000000030',
    '99800000-0000-4000-8000-000000000001',
    '99800000-0000-4000-8000-000000000010',
    'DV-GUARD-SENT', now(), 'Too early', 'guard-return-sent',
    '99800000-0000-4000-8000-000000000020'
  )
$$, 'P0001', 'Sales invoice must be paid before a physical return',
  'sent invoice cannot receive a physical return');

select throws_ok($$
  insert into public.sales_returns(
    id, tenant_id, sales_invoice_id, return_number, returned_at,
    reason, idempotency_key, operation_id
  ) values (
    '99800000-0000-4000-8000-000000000031',
    '99800000-0000-4000-8000-000000000001',
    '99800000-0000-4000-8000-000000000011',
    'DV-GUARD-CONFIRMED', now(), 'Not delivered', 'guard-return-confirmed',
    '99800000-0000-4000-8000-000000000021'
  )
$$, 'P0001', 'Sales invoice must be paid before a physical return',
  'confirmed but undelivered invoice cannot receive a physical return');

select lives_ok($$
  insert into public.sales_returns(
    id, tenant_id, sales_invoice_id, return_number, returned_at,
    reason, idempotency_key, operation_id
  ) values (
    '99800000-0000-4000-8000-000000000032',
    '99800000-0000-4000-8000-000000000001',
    '99800000-0000-4000-8000-000000000012',
    'DV-GUARD-PAID', now(), 'Delivered customer return', 'guard-return-paid',
    '99800000-0000-4000-8000-000000000022'
  )
$$, 'paid invoice can receive a physical return');

select throws_ok($$
  insert into public.sales_credit_notes(
    id, tenant_id, sales_invoice_id, credit_note_number, issue_date,
    reason_code, reason, net_amount, tax_amount, total_amount,
    idempotency_key, operation_id, journal_entry_id
  ) values (
    '99800000-0000-4000-8000-000000000033',
    '99800000-0000-4000-8000-000000000001',
    '99800000-0000-4000-8000-000000000010',
    'NCV-GUARD-SENT', now(), 'adjustment', 'Too early', 1000, 0, 1000,
    'guard-credit-sent', '99800000-0000-4000-8000-000000000023',
    '99800000-0000-4000-8000-000000000040'
  )
$$, 'P0001', 'Sales invoice must be confirmed before a credit note',
  'sent invoice cannot receive a credit note');

select lives_ok($$
  insert into public.sales_credit_notes(
    id, tenant_id, sales_invoice_id, credit_note_number, issue_date,
    reason_code, reason, net_amount, tax_amount, total_amount,
    idempotency_key, operation_id, journal_entry_id
  ) values (
    '99800000-0000-4000-8000-000000000034',
    '99800000-0000-4000-8000-000000000001',
    '99800000-0000-4000-8000-000000000011',
    'NCV-GUARD-CONFIRMED', now(), 'adjustment', 'Balance correction',
    1000, 0, 1000, 'guard-credit-confirmed',
    '99800000-0000-4000-8000-000000000024',
    '99800000-0000-4000-8000-000000000040'
  )
$$, 'confirmed invoice can receive a financial credit note');

select is((select count(*)::integer from public.sales_returns), 1,
  'only the paid physical return was inserted');
select is((select count(*)::integer from public.sales_credit_notes), 1,
  'only the confirmed financial credit note was inserted');

select * from finish();
rollback;
