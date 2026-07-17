begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(31);

insert into public.tenants (id, shop_name)
values ('98500000-0000-4000-8000-000000000001', 'Expense Trace Test');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '98500000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'expense-trace@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '98500000-0000-4000-8000-000000000001'),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98500000-0000-4000-8000-000000000099',
  '98500000-0000-4000-8000-000000000001',
  'admin'
);

delete from public.payment_methods
where tenant_id = '98500000-0000-4000-8000-000000000001';
delete from public.accounts
where tenant_id = '98500000-0000-4000-8000-000000000001';

insert into public.accounts (id, tenant_id, code, name, type, category)
values
  (
    '98500000-0000-4000-8000-000000000010',
    '98500000-0000-4000-8000-000000000001',
    '1101', 'Caja', 'asset', 'currentAsset'
  ),
  (
    '98500000-0000-4000-8000-000000000011',
    '98500000-0000-4000-8000-000000000001',
    '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'
  ),
  (
    '98500000-0000-4000-8000-000000000012',
    '98500000-0000-4000-8000-000000000001',
    '2120', 'IVA Crédito Fiscal', 'asset', 'currentAsset'
  ),
  (
    '98500000-0000-4000-8000-000000000013',
    '98500000-0000-4000-8000-000000000001',
    '6200', 'Gastos Operacionales', 'expense', 'operatingExpense'
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values (
  '98500000-0000-4000-8000-000000000020',
  '98500000-0000-4000-8000-000000000001',
  'cash',
  'Efectivo',
  '98500000-0000-4000-8000-000000000010',
  'no_tax'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98500000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98500000-0000-4000-8000-000000000099',
  true
);

-- Immediate paid expense, matching the current user-facing expense form.
insert into public.expenses (
  id, tenant_id, expense_number, document_type, issue_date,
  posting_status, payment_status, payment_method_id, payment_account_id,
  subtotal, tax_amount, total_amount, amount_paid, balance
) values (
  '98500000-0000-4000-8000-000000000030',
  '98500000-0000-4000-8000-000000000001',
  'GTO-TRACE-001',
  'ticket',
  '2026-07-17 10:00:00+00',
  'posted',
  'paid',
  '98500000-0000-4000-8000-000000000020',
  '98500000-0000-4000-8000-000000000010',
  1000, 190, 1190, 1190, 0
);

insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, tax_rate, tax_amount, total
) values (
  '98500000-0000-4000-8000-000000000031',
  '98500000-0000-4000-8000-000000000001',
  '98500000-0000-4000-8000-000000000030',
  0,
  '98500000-0000-4000-8000-000000000013',
  '6200',
  'Gastos Operacionales',
  'Compra de prueba',
  1, 1000, 19, 190, 1190
);

select is(
  (select total_amount from public.expenses where id = '98500000-0000-4000-8000-000000000030'),
  1190::numeric,
  'line trigger recalculates the immediate expense total before journal posting'
);
select is(
  (select amount_paid from public.expenses where id = '98500000-0000-4000-8000-000000000030'),
  1190::numeric,
  'immediate paid expense keeps its exact paid amount'
);
select is(
  (select balance from public.expenses where id = '98500000-0000-4000-8000-000000000030'),
  0::numeric,
  'immediate paid expense has zero balance'
);
select is(
  (select count(*)::integer from public.journal_entries where source_module = 'expenses' and source_reference = 'GTO-TRACE-001'),
  1,
  'posted expense owns exactly one accrual journal'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    where entry.source_module = 'expenses'
      and entry.source_reference = 'GTO-TRACE-001'
      and entry.created_by = '98500000-0000-4000-8000-000000000099'
      and operation.document_id = '98500000-0000-4000-8000-000000000030'
      and operation.action = 'line_insert'
      and operation.actor_id = '98500000-0000-4000-8000-000000000099'
      and operation.outcome = 'completed'
  ),
  'final accrual journal links the user, expense, and completed line operation'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.source_reference = 'GTO-TRACE-001'
    group by entry.id
    having sum(line.debit_amount) = sum(line.credit_amount)
       and sum(line.debit_amount) = 1190
  ),
  'expense journal lines balance at the exact document total'
);
select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.document_id = '98500000-0000-4000-8000-000000000030'
      and operation.outcome <> 'completed'
  ),
  0,
  'all accepted expense header and line operations complete'
);
select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.document_id = '98500000-0000-4000-8000-000000000030'
      and not exists (
        select 1 from public.inventory_accounting_checkpoints checkpoint
        where checkpoint.operation_id = operation.id
          and checkpoint.phase = 'invariants_verified'
          and checkpoint.outcome = 'completed'
      )
  ),
  0,
  'every expense operation has a completed invariant checkpoint'
);
select is(
  (
    select count(*)::integer
    from public.stock_movements movement
    join public.inventory_accounting_operations operation
      on operation.id = movement.operation_id
    where operation.document_id = '98500000-0000-4000-8000-000000000030'
  ),
  0,
  'expense header and line actions have zero stock side effects'
);

update public.expense_lines
set quantity = 2,
    tax_amount = 380,
    total = 2380
where id = '98500000-0000-4000-8000-000000000031';

select is(
  (select total_amount from public.expenses where id = '98500000-0000-4000-8000-000000000030'),
  2380::numeric,
  'line edit recalculates the header from the updated line amounts'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    where entry.source_reference = 'GTO-TRACE-001'
      and entry.total_debit = 2380
      and entry.total_credit = 2380
      and operation.action = 'line_update'
      and operation.outcome = 'completed'
  ),
  'line edit replaces the journal under the same completed operation'
);
select ok(
  exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    join public.inventory_accounting_operations operation
      on operation.id = checkpoint.operation_id
    where operation.document_id = '98500000-0000-4000-8000-000000000030'
      and operation.action = 'line_update'
      and checkpoint.phase = 'journal_reversed'
  ),
  'line edit records the superseded journal checkpoint'
);

select public.rebuild_expense_journal_entry('98500000-0000-4000-8000-000000000030');
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    where entry.source_reference = 'GTO-TRACE-001'
      and operation.action = 'rebuild_journal'
      and operation.executor = 'database_rpc'
      and operation.outcome = 'completed'
  ),
  'current-client atomic rebuild leaves the final journal fully traced'
);
select is(
  nullif(current_setting('app.inventory_operation_id', true), ''),
  null::text,
  'atomic rebuild clears transaction-local trace context'
);

-- Posted payable expense with a partial payment and its undo.
insert into public.expenses (
  id, tenant_id, expense_number, document_type, issue_date,
  posting_status, payment_status, subtotal, total_amount, amount_paid, balance
) values (
  '98500000-0000-4000-8000-000000000040',
  '98500000-0000-4000-8000-000000000001',
  'GTO-TRACE-002',
  'invoice',
  '2026-07-17 11:00:00+00',
  'posted', 'pending', 10000, 10000, 0, 10000
);
insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, tax_rate, tax_amount, total
) values (
  '98500000-0000-4000-8000-000000000041',
  '98500000-0000-4000-8000-000000000001',
  '98500000-0000-4000-8000-000000000040',
  0,
  '98500000-0000-4000-8000-000000000013',
  '6200', 'Gastos Operacionales', 'Cuenta por pagar',
  1, 10000, 0, 0, 10000
);
insert into public.expense_payments (
  id, tenant_id, expense_id, payment_method_id, payment_account_id,
  amount, payment_date, reference
) values (
  '98500000-0000-4000-8000-000000000050',
  '98500000-0000-4000-8000-000000000001',
  '98500000-0000-4000-8000-000000000040',
  '98500000-0000-4000-8000-000000000020',
  '98500000-0000-4000-8000-000000000010',
  4000,
  '2026-07-17 12:00:00+00',
  'Pago parcial trazado'
);

select is(
  (select payment_status from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  'partial',
  'partial expense payment keeps the expense partial'
);
select is(
  (select amount_paid from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  4000::numeric,
  'partial expense payment updates paid amount exactly'
);
select is(
  (select balance from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  6000::numeric,
  'partial expense payment updates remaining balance exactly'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    where entry.source_module = 'expense_payments'
      and entry.source_reference = '98500000-0000-4000-8000-000000000050'
      and entry.created_by = '98500000-0000-4000-8000-000000000099'
      and operation.document_type = 'expense_payment'
      and operation.document_id = '98500000-0000-4000-8000-000000000050'
      and operation.action = 'insert'
      and operation.outcome = 'completed'
  ),
  'partial payment journal links actor, payment, expense context, and operation'
);
select is(
  (
    select count(*)::integer
    from public.stock_movements movement
    join public.inventory_accounting_operations operation
      on operation.id = movement.operation_id
    where operation.document_id = '98500000-0000-4000-8000-000000000050'
  ),
  0,
  'expense payment creates no stock movement'
);

delete from public.expense_payments
where id = '98500000-0000-4000-8000-000000000050';

select is(
  (select payment_status from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  'pending',
  'deleting the partial payment returns the expense to pending'
);
select is(
  (select amount_paid from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  0::numeric,
  'deleting the partial payment clears paid amount'
);
select is(
  (select balance from public.expenses where id = '98500000-0000-4000-8000-000000000040'),
  10000::numeric,
  'deleting the partial payment restores the full balance'
);
select is(
  (
    select count(*)::integer
    from public.journal_entries
    where source_module = 'expense_payments'
      and source_reference = '98500000-0000-4000-8000-000000000050'
  ),
  0,
  'payment undo removes the current payment journal'
);
select ok(
  exists (
    select 1
    from public.inventory_accounting_operations operation
    join public.inventory_accounting_checkpoints checkpoint
      on checkpoint.operation_id = operation.id
    where operation.document_id = '98500000-0000-4000-8000-000000000050'
      and operation.action = 'delete'
      and operation.outcome = 'completed'
      and checkpoint.phase = 'journal_reversed'
      and checkpoint.outcome = 'completed'
  ),
  'payment undo keeps a completed reversal checkpoint'
);

-- Older clients still call delete/create separately. Both calls must be traced.
select public.delete_expense_journal_entry('98500000-0000-4000-8000-000000000040');
select is(
  (select count(*)::integer from public.journal_entries where source_reference = 'GTO-TRACE-002'),
  0,
  'legacy direct journal delete leaves no current accrual journal'
);
select ok(
  exists (
    select 1 from public.inventory_accounting_operations
    where document_id = '98500000-0000-4000-8000-000000000040'
      and action = 'journal_delete'
      and executor = 'database_rpc'
      and outcome = 'completed'
  ),
  'legacy direct journal delete receives its own completed trace'
);
select public.create_expense_journal_entry('98500000-0000-4000-8000-000000000040');
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.inventory_accounting_operations operation
      on operation.id = entry.operation_id
    where entry.source_reference = 'GTO-TRACE-002'
      and operation.action = 'journal_rebuild'
      and operation.executor = 'database_rpc'
      and operation.outcome = 'completed'
  ),
  'legacy direct journal rebuild leaves the final journal traced'
);

delete from public.expenses
where id = '98500000-0000-4000-8000-000000000040';

select is(
  (select count(*)::integer from public.journal_entries where source_reference = 'GTO-TRACE-002'),
  0,
  'expense deletion removes its posted journal by the OLD expense snapshot'
);
select ok(
  exists (
    select 1
    from public.inventory_accounting_operations operation
    join public.inventory_accounting_checkpoints checkpoint
      on checkpoint.operation_id = operation.id
    where operation.document_id = '98500000-0000-4000-8000-000000000040'
      and operation.action = 'delete'
      and operation.outcome = 'completed'
      and checkpoint.phase = 'journal_reversed'
  ),
  'expense deletion is completed with a journal reversal checkpoint'
);
select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '98500000-0000-4000-8000-000000000001'
      and operation.outcome <> 'completed'
  ),
  0,
  'expense test leaves no incomplete operation'
);
select is(
  nullif(current_setting('app.inventory_operation_id', true), ''),
  null::text,
  'all expense paths clear transaction-local trace context'
);

select * from finish();
rollback;
