begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(12);

insert into public.tenants (id, shop_name)
values ('71111111-1111-4111-8111-111111111111', 'Payroll Ledger Test');

-- Tenant bootstrap seeds the default chart and payment methods. This fixture
-- uses deterministic IDs, so isolate it from those defaults inside the rollback.
delete from public.payment_methods
where tenant_id = '71111111-1111-4111-8111-111111111111';
delete from public.accounts
where tenant_id = '71111111-1111-4111-8111-111111111111';

insert into public.accounts (id, tenant_id, code, name, type, category)
values
  ('72222222-2222-4222-8222-222222222221', '71111111-1111-4111-8111-111111111111', '1102', 'Banco', 'asset', 'currentAsset'),
  ('72222222-2222-4222-8222-222222222222', '71111111-1111-4111-8111-111111111111', '1135', 'Anticipos al Personal', 'asset', 'currentAsset'),
  ('72222222-2222-4222-8222-222222222223', '71111111-1111-4111-8111-111111111111', '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'),
  ('72222222-2222-4222-8222-222222222224', '71111111-1111-4111-8111-111111111111', '610101', 'Sueldo Braulio', 'expense', 'operatingExpense');

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
values (
  '73333333-3333-4333-8333-333333333333',
  '71111111-1111-4111-8111-111111111111',
  'transfer',
  'Transferencia',
  '72222222-2222-4222-8222-222222222221',
  'no_tax'
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
)
values (
  '74444444-4444-4444-8444-444444444444',
  '71111111-1111-4111-8111-111111111111',
  'TEST-001',
  'Braulio',
  'Muñoz',
  'Mecánico',
  '72222222-2222-4222-8222-222222222224',
  '73333333-3333-4333-8333-333333333333'
);

-- Keep deterministic ERP identity evidence even though this legacy ledger
-- regression intentionally builds its business fixture through privileged SQL.
-- Client authorization and RPC-only mutation are covered by the reconciliation
-- contract suite; triggers and accounting projections remain enabled here.
set local session_replication_role = replica;

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  banned_until,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  '70000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  'payroll-accountant@example.invalid',
  '',
  now(),
  null,
  '{"account_type":"erp_staff"}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);

insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '70000000-0000-4000-8000-000000000002',
  '70000000-0000-4000-8000-000000000001',
  '71111111-1111-4111-8111-111111111111',
  'accountant',
  '{"access_accounting":true}'::jsonb,
  true
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '70000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;
reset role;

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
)
values (
  '75555555-5555-4555-8555-555555555555',
  '71111111-1111-4111-8111-111111111111',
  'NOM-TEST-001',
  '2026-05-25',
  '2026-05-31',
  'Semana 22: 25 may - 31 may',
  16,
  56000,
  1,
  'confirmed'
);

insert into public.expenses (
  id, tenant_id, expense_number, document_type, issue_date, posting_status,
  payment_status, subtotal, total_amount, balance, reference, notes
)
values (
  '76666666-6666-4666-8666-666666666666',
  '71111111-1111-4111-8111-111111111111',
  'GTO-TEST-001',
  'ticket',
  '2026-05-31 12:00:00+00',
  'posted',
  'pending',
  56000,
  56000,
  56000,
  'Semana 22 - NOM-TEST-001',
  'Pago de salario: Braulio Muñoz'
);

insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  expense_id, salary_account_id
)
values (
  '77777777-7777-4777-8777-777777777777',
  '71111111-1111-4111-8111-111111111111',
  '75555555-5555-4555-8555-555555555555',
  '74444444-4444-4444-8444-444444444444',
  'Braulio Muñoz',
  16,
  3500,
  56000,
  56000,
  '73333333-3333-4333-8333-333333333333',
  '76666666-6666-4666-8666-666666666666',
  '72222222-2222-4222-8222-222222222224'
);

insert into public.expense_lines (
  tenant_id, expense_id, line_index, account_id, account_code, account_name,
  description, quantity, unit_price, subtotal, total
)
values (
  '71111111-1111-4111-8111-111111111111',
  '76666666-6666-4666-8666-666666666666',
  0,
  '72222222-2222-4222-8222-222222222224',
  '610101',
  'Sueldo Braulio',
  'Salario: Braulio Muñoz',
  1,
  56000,
  56000,
  56000
);

select set_config(
  'test.payroll.accrual_operation_id',
  (
    select entry.operation_id::text
    from public.journal_entries entry
    where entry.tenant_id = '71111111-1111-4111-8111-111111111111'
      and entry.source_module = 'expenses'
      and entry.source_document_id =
        '76666666-6666-4666-8666-666666666666'
  ),
  true
);

insert into public.payroll_money_command_contexts (
  transaction_id,
  tenant_id,
  command,
  operation_key,
  actor_id
)
values (
  txid_current(),
  '71111111-1111-4111-8111-111111111111',
  'advance_registration',
  'ledger-advance-fixture-0001',
  '70000000-0000-4000-8000-000000000001'
);

insert into public.employee_advances (
  id, tenant_id, employee_id, amount, payment_method_id, paid_at, reference
)
values (
  '78888888-8888-4888-8888-888888888888',
  '71111111-1111-4111-8111-111111111111',
  '74444444-4444-4444-8444-444444444444',
  20500,
  '73333333-3333-4333-8333-333333333333',
  '2026-05-26 23:50:00+00',
  'MBT-ADVANCE-TEST'
);

delete from public.payroll_money_command_contexts
where transaction_id = txid_current();

select ok(
  exists (
    select 1 from public.journal_entries
     where source_module = 'employee_advances'
       and source_reference = '78888888-8888-4888-8888-888888888888'
       and entry_date = '2026-05-26 23:50:00+00'
       and total_debit = 20500
       and total_credit = 20500
  ),
  'advance creates a balanced journal entry on its actual payment date'
);

insert into public.payroll_money_command_contexts (
  transaction_id,
  tenant_id,
  command,
  operation_key,
  actor_id
)
values (
  txid_current(),
  '71111111-1111-4111-8111-111111111111',
  'manual_payment',
  'ledger-allocation-fixture-0001',
  '70000000-0000-4000-8000-000000000001'
);

insert into public.employee_advance_allocations (
  id, tenant_id, advance_id, voucher_line_id, amount, applied_at
)
values (
  '79999999-9999-4999-8999-999999999999',
  '71111111-1111-4111-8111-111111111111',
  '78888888-8888-4888-8888-888888888888',
  '77777777-7777-4777-8777-777777777777',
  20500,
  '2026-05-31 12:00:00+00'
);

delete from public.payroll_money_command_contexts
where transaction_id = txid_current();

select ok(
  exists (
    select 1 from public.employee_advances
     where id = '78888888-8888-4888-8888-888888888888'
       and status = 'applied'
       and amount_applied = 20500
  ),
  'allocation closes the available advance balance'
);

select ok(
  exists (
    select 1 from public.expenses
     where id = '76666666-6666-4666-8666-666666666666'
       and payment_status = 'partial'
       and amount_paid = 20500
       and balance = 35500
  ),
  'advance allocation partially settles the payroll obligation'
);

select is(
  (
    select entry.operation_id::text
    from public.journal_entries entry
    where entry.tenant_id = '71111111-1111-4111-8111-111111111111'
      and entry.source_module = 'expenses'
      and entry.source_document_id =
        '76666666-6666-4666-8666-666666666666'
  ),
  current_setting('test.payroll.accrual_operation_id'),
  'advance allocation preserves the immutable accrual operation lineage'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_operations operation
    where operation.tenant_id =
      '71111111-1111-4111-8111-111111111111'
      and operation.document_type = 'expense'
      and operation.document_id =
        '76666666-6666-4666-8666-666666666666'
      and operation.action = 'update'
      and operation.outcome = 'completed'
      and (operation.before_snapshot->>'amount_paid')::numeric = 0
      and (
        operation.context->'expense_after'->>'amount_paid'
      )::numeric = 20500
  ),
  'nested totals-only expense trace completes with the settled header'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.tenant_id =
      '71111111-1111-4111-8111-111111111111'
      and checkpoint.phase = 'source_snapshotted'
      and checkpoint.entity_type = 'expense'
      and checkpoint.entity_id =
        '76666666-6666-4666-8666-666666666666'
      and (checkpoint.payload->>'cash_payment_total')::numeric = 0
      and (checkpoint.payload->>'advance_allocation_total')::numeric = 20500
      and (checkpoint.payload->>'payment_total')::numeric = 20500
  ),
  'expense trace records cash and advance settlement evidence separately'
);

insert into public.payroll_money_command_contexts (
  transaction_id,
  tenant_id,
  command,
  operation_key,
  actor_id
)
values (
  txid_current(),
  '71111111-1111-4111-8111-111111111111',
  'manual_payment',
  'ledger-payment-fixture-0001',
  '70000000-0000-4000-8000-000000000001'
);

insert into public.expense_payments (
  id, tenant_id, expense_id, payment_method_id, amount, payment_date, reference
)
values (
  '7aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '71111111-1111-4111-8111-111111111111',
  '76666666-6666-4666-8666-666666666666',
  '73333333-3333-4333-8333-333333333333',
  35500,
  '2026-06-01 20:03:00+00',
  'MBT-FINAL-TEST'
);

delete from public.payroll_money_command_contexts
where transaction_id = txid_current();

select ok(
  exists (
    select 1 from public.journal_entries
     where source_module = 'expense_payments'
       and source_reference = '7aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
       and entry_date = '2026-06-01 20:03:00+00'
       and total_debit = 35500
       and total_credit = 35500
  ),
  'partial payroll payment creates a balanced journal on the actual date'
);

select ok(
  exists (
    select 1 from public.expenses
     where id = '76666666-6666-4666-8666-666666666666'
       and payment_status = 'paid'
       and amount_paid = 56000
       and balance = 0
  ),
  'advance plus final transfer fully settle the salary expense'
);

select ok(
  (
    select coalesce(sum(debit_amount), 0) = coalesce(sum(credit_amount), 0)
      from public.journal_lines
     where entry_id in (
       select id from public.journal_entries
        where tenant_id = '71111111-1111-4111-8111-111111111111'
     )
  ),
  'all payroll ledger journal entries remain balanced'
);

select ok(
  (
    select abs(coalesce(sum(debit_amount - credit_amount), 0)) < 0.01
      from public.journal_lines
     where tenant_id = '71111111-1111-4111-8111-111111111111'
       and account_code = '2106'
  ),
  'salary payable liability is fully cleared after advance allocation and final payment'
);

insert into public.payroll_money_command_contexts (
  transaction_id,
  tenant_id,
  command,
  operation_key,
  actor_id
)
values (
  txid_current(),
  '71111111-1111-4111-8111-111111111111',
  'legacy_reversal',
  'ledger-reversal-fixture-0001',
  '70000000-0000-4000-8000-000000000001'
);

delete from public.expense_payments
where id = '7aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

delete from public.employee_advance_allocations
where id = '79999999-9999-4999-8999-999999999999';

delete from public.payroll_money_command_contexts
where transaction_id = txid_current();

select ok(
  exists (
    select 1 from public.expenses
     where id = '76666666-6666-4666-8666-666666666666'
       and payment_status = 'pending'
       and amount_paid = 0
       and balance = 56000
  ),
  'reverting payroll settlements reopens the full salary obligation'
);

select ok(
  exists (
    select 1 from public.employee_advances
     where id = '78888888-8888-4888-8888-888888888888'
       and status = 'open'
       and amount_applied = 0
  ),
  'reverting the allocation restores the advance balance'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();

rollback;
