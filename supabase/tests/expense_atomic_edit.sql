begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(23);

insert into public.tenants (id, shop_name)
values ('98800000-0000-4000-8000-000000000001', 'Atomic Expense Edit Test');

insert into auth.users (
  id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '98800000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'atomic-expense@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '98800000-0000-4000-8000-000000000001'),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '98800000-0000-4000-8000-000000000099';

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98800000-0000-4000-8000-000000000099',
  '98800000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.suppliers (id, tenant_id, name, default_tax_treatment)
values (
  '98800000-0000-4000-8000-000000000020',
  '98800000-0000-4000-8000-000000000001',
  'NIC Chile Test',
  'tax_included'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98800000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98800000-0000-4000-8000-000000000099',
  true
);

insert into public.expenses (
  id, tenant_id, expense_number, category_id, supplier_id, supplier_name,
  document_type, document_number, issue_date, posting_status, payment_status,
  payment_method_id, payment_account_id, subtotal, tax_amount, total_amount,
  amount_paid, balance, paid_at, posted_at, notes, reference
)
select
  '98800000-0000-4000-8000-000000000030',
  '98800000-0000-4000-8000-000000000001',
  'GTO-ATOMIC-001',
  category.id,
  '98800000-0000-4000-8000-000000000020',
  'NIC Chile Test',
  'receipt',
  '21179232-TEST',
  '2026-07-17 00:00:00+00',
  'posted',
  'paid',
  method.id,
  method.account_id,
  19980,
  0,
  19980,
  19980,
  0,
  '2026-07-17 02:00:19+00',
  '2026-07-17 02:00:19+00',
  'Pago NIC Chile Test',
  '21179232-TEST'
from public.expense_categories category
join public.payment_methods method on method.tenant_id = category.tenant_id
where category.tenant_id = '98800000-0000-4000-8000-000000000001'
  and lower(category.name) = lower('Servicios Digitales')
  and method.code = 'card';

insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, subtotal, tax_rate,
  tax_amount, total
)
select
  '98800000-0000-4000-8000-000000000031',
  '98800000-0000-4000-8000-000000000001',
  '98800000-0000-4000-8000-000000000030',
  0,
  account.id,
  account.code,
  account.name,
  'Restauración de dominio vinabike.cl',
  1,
  19980,
  19980,
  0,
  0,
  19980
from public.accounts account
where account.tenant_id = '98800000-0000-4000-8000-000000000001'
  and account.code = '6207-01';

create temp table atomic_expense_before as
select
  expense.updated_at,
  expense.paid_at,
  expense.posted_at,
  expense.category_id,
  (
    select count(*)
    from public.journal_supersession_evidence evidence
    where evidence.tenant_id = expense.tenant_id
      and evidence.source_reference = expense.expense_number
  ) as evidence_count
from public.expenses expense
where expense.id = '98800000-0000-4000-8000-000000000030';

select public.save_expense_aggregate(
  'atomic-expense-edit-001',
  '98800000-0000-4000-8000-000000000030',
  (select updated_at from atomic_expense_before),
  jsonb_build_object(
    'category_id', (select category_id from atomic_expense_before),
    'supplier_id', '98800000-0000-4000-8000-000000000020',
    'supplier_name', 'NIC Chile Test',
    'document_type', 'invoice',
    'document_number', '21179232-TEST',
    'issue_date', '2026-07-17T00:00:00.000Z',
    'payment_method_id', (
      select id from public.payment_methods
      where tenant_id = '98800000-0000-4000-8000-000000000001'
        and code = 'card'
    ),
    'payment_account_id', (
      select account_id from public.payment_methods
      where tenant_id = '98800000-0000-4000-8000-000000000001'
        and code = 'card'
    ),
    'notes', 'Pago NIC Chile Test',
    'reference', '21179232-TEST',
    'account_id', (
      select id from public.accounts
      where tenant_id = '98800000-0000-4000-8000-000000000001'
        and code = '6207-01'
    ),
    'description', 'Restauración de dominio vinabike.cl',
    'total_amount', 19980
  )
);

select is(
  (select document_type from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  'invoice',
  'atomic edit changes the receipt into an invoice'
);
select is(
  (select subtotal from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  16790::numeric,
  'atomic edit stores integer CLP net amount'
);
select is(
  (select tax_amount from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  3190::numeric,
  'atomic edit stores integer CLP IVA credit'
);
select is(
  (select total_amount from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  19980::numeric,
  'atomic edit preserves the document total'
);
select is(
  (select category_id from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  (select category_id from atomic_expense_before),
  'atomic edit preserves the explicit expense category'
);
select is(
  (select paid_at from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  (select paid_at from atomic_expense_before),
  'atomic edit preserves the original paid timestamp'
);
select is(
  (select posted_at from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  (select posted_at from atomic_expense_before),
  'atomic edit preserves the original accounting timestamp'
);
select is(
  (select subtotal from public.expense_lines where id = '98800000-0000-4000-8000-000000000031'),
  16790::numeric,
  'expense line stores the same integer CLP net amount'
);
select is(
  (select tax_amount from public.expense_lines where id = '98800000-0000-4000-8000-000000000031'),
  3190::numeric,
  'expense line stores the same integer CLP IVA amount'
);
select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_module = 'expenses'
      and entry.source_document_id = '98800000-0000-4000-8000-000000000030'
  ),
  1,
  'atomic edit leaves exactly one active accrual journal'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    join public.journal_lines expense_line
      on expense_line.entry_id = entry.id and expense_line.account_code = '6207-01'
    join public.journal_lines tax_line
      on tax_line.entry_id = entry.id and tax_line.account_code = '2120'
    join public.journal_lines bank_line
      on bank_line.entry_id = entry.id and bank_line.account_code = '1110'
    where entry.source_document_id = '98800000-0000-4000-8000-000000000030'
      and operation.action = 'aggregate_update'
      and operation.outcome = 'completed'
      and expense_line.debit_amount = 16790
      and tax_line.debit_amount = 3190
      and bank_line.credit_amount = 19980
      and entry.total_debit = entry.total_credit
      and entry.total_debit = 19980
  ),
  'replacement journal has exact expense, IVA, and bank postings'
);
select is(
  (
    select count(*) - before.evidence_count
    from public.journal_supersession_evidence evidence
    cross join atomic_expense_before before
    where evidence.tenant_id = '98800000-0000-4000-8000-000000000001'
      and evidence.source_reference = 'GTO-ATOMIC-001'
    group by before.evidence_count
  ),
  1::bigint,
  'atomic edit archives exactly one superseded journal'
);
select ok(
  exists (
    select 1
    from public.journal_supersession_evidence evidence
    where evidence.tenant_id = '98800000-0000-4000-8000-000000000001'
      and evidence.source_reference = 'GTO-ATOMIC-001'
      and evidence.captured_reason = 'expense_atomic_edit'
      and (evidence.header_snapshot->>'total_debit')::numeric = 19980
      and jsonb_array_length(evidence.lines_snapshot) = 2
  ),
  'supersession evidence keeps the complete previous header and lines'
);
select is(
  (
    select count(*)::integer
    from public.expense_aggregate_save_operations receipt
    where receipt.operation_key = 'atomic-expense-edit-001'
      and receipt.expense_id = '98800000-0000-4000-8000-000000000030'
  ),
  1,
  'atomic edit stores one durable command receipt'
);
select is(
  (
    public.save_expense_aggregate(
      'atomic-expense-edit-001',
      '98800000-0000-4000-8000-000000000030',
      (select updated_at from atomic_expense_before),
      jsonb_build_object(
        'category_id', (select category_id from atomic_expense_before),
        'supplier_id', '98800000-0000-4000-8000-000000000020',
        'supplier_name', 'NIC Chile Test',
        'document_type', 'invoice',
        'document_number', '21179232-TEST',
        'issue_date', '2026-07-17T00:00:00.000Z',
        'payment_method_id', (select id from public.payment_methods where tenant_id = '98800000-0000-4000-8000-000000000001' and code = 'card'),
        'payment_account_id', (select account_id from public.payment_methods where tenant_id = '98800000-0000-4000-8000-000000000001' and code = 'card'),
        'notes', 'Pago NIC Chile Test',
        'reference', '21179232-TEST',
        'account_id', (select id from public.accounts where tenant_id = '98800000-0000-4000-8000-000000000001' and code = '6207-01'),
        'description', 'Restauración de dominio vinabike.cl',
        'total_amount', 19980
      )
    )->>'replayed'
  )::boolean,
  true,
  'same operation key replays the committed result'
);
select ok(
  (
    select count(*) = 1
    from public.journal_entries entry
    where entry.source_document_id = '98800000-0000-4000-8000-000000000030'
  ) and (
    select count(*) - before.evidence_count = 1
    from public.journal_supersession_evidence evidence
    cross join atomic_expense_before before
    where evidence.tenant_id = '98800000-0000-4000-8000-000000000001'
      and evidence.source_reference = 'GTO-ATOMIC-001'
    group by before.evidence_count
  ),
  'idempotent replay creates no journal or evidence duplicate'
);
select throws_ok(
  $$
    select public.save_expense_aggregate(
      'atomic-expense-edit-stale',
      '98800000-0000-4000-8000-000000000030',
      (select updated_at - interval '1 second' from atomic_expense_before),
      jsonb_build_object(
        'document_type', 'invoice',
        'total_amount', 19980,
        'account_id', (select id from public.accounts where tenant_id = '98800000-0000-4000-8000-000000000001' and code = '6207-01'),
        'payment_method_id', (select id from public.payment_methods where tenant_id = '98800000-0000-4000-8000-000000000001' and code = 'card')
      )
    )
  $$,
  '40001',
  'Expense was modified after this form was loaded',
  'stale form version is rejected without overwriting newer data'
);
select throws_ok(
  format(
    $sql$
      select public.save_expense_aggregate(
        'atomic-expense-edit-invalid',
        '98800000-0000-4000-8000-000000000030',
        %L::timestamptz,
        jsonb_build_object(
          'document_type', 'invoice',
          'total_amount', 19980,
          'account_id', '98800000-0000-4000-8000-000000000099',
          'payment_method_id', (select id from public.payment_methods where tenant_id = '98800000-0000-4000-8000-000000000001' and code = 'card')
        )
      )
    $sql$,
    (select updated_at from public.expenses where id = '98800000-0000-4000-8000-000000000030')
  ),
  '42501',
  'Expense account not found for current tenant',
  'invalid account aborts the aggregate before any mutation'
);
select is(
  (select document_type from public.expenses where id = '98800000-0000-4000-8000-000000000030'),
  'invoice',
  'failed aggregate leaves the committed expense unchanged'
);
select lives_ok(
  $$
    update public.expenses
    set notes = 'Legacy posted header edit remains compatible'
    where id = '98800000-0000-4000-8000-000000000030'
  $$,
  'legacy posted header update waits for its owning trigger depth'
);
select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_document_id = '98800000-0000-4000-8000-000000000030'
  ),
  1,
  'legacy posted header update also leaves one active journal'
);
select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.document_id = '98800000-0000-4000-8000-000000000030'
      and operation.outcome <> 'completed'
  ),
  0,
  'all accepted atomic and compatibility operations complete'
);
select is(
  (
    select count(*)::integer
    from public.stock_movements movement
    join public.inventory_accounting_operations operation
      on operation.id = movement.operation_id
    where operation.document_id = '98800000-0000-4000-8000-000000000030'
  ) + (
    select count(*)::integer
    from public.inventory_accounting_inconsistencies_view inconsistency
    where inconsistency.tenant_id = '98800000-0000-4000-8000-000000000001'
      and inconsistency.severity in ('high', 'critical')
  ),
  0,
  'expense edit creates no stock effect or severe accounting inconsistency'
);

select * from finish();
rollback;
