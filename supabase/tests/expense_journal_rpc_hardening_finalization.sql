begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(47);

select has_function(
  'public',
  'assert_expense_rpc_tenant',
  array['uuid'],
  'expense journal tenant assertion exists'
);
select function_privs_are(
  'public',
  'assert_expense_rpc_tenant',
  array['uuid'],
  current_user,
  array['EXECUTE'],
  'tenant assertion is executable only by its owner'
);
select function_privs_are(
  'public',
  'assert_expense_deleted_source_operation',
  array['text', 'uuid', 'text', 'text'],
  current_user,
  array['EXECUTE'],
  'deleted-source operation proof is executable only by its owner'
);

select ok(
  not exists (
    select 1
    from pg_proc function_row
    cross join lateral aclexplode(
      coalesce(function_row.proacl, acldefault('f', function_row.proowner))
    ) acl
    where function_row.oid in (
      'public.create_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.delete_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry_owner_only(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry_owner_only(uuid)'::regprocedure,
      'public.rebuild_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.recalculate_expense_totals_owner_only(uuid)'::regprocedure,
      'public.create_expense_journal_entry_untraced(uuid)'::regprocedure,
      'public.delete_expense_journal_entry_untraced(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry_untraced(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry_untraced(uuid)'::regprocedure,
      'public.handle_expense_line_change()'::regprocedure,
      'public.handle_expense_payment_change()'::regprocedure
    )
      and acl.privilege_type = 'EXECUTE'
      and (acl.grantee = 0 or acl.grantee <> function_row.proowner)
  ),
  'retained and untraced implementations are owner-only'
);

select ok(
  not exists (
    select 1
    from pg_proc function_row
    cross join lateral aclexplode(
      coalesce(function_row.proacl, acldefault('f', function_row.proowner))
    ) acl
    where function_row.oid in (
      'public.create_expense_journal_entry(uuid)'::regprocedure,
      'public.delete_expense_journal_entry(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry(uuid)'::regprocedure,
      'public.rebuild_expense_journal_entry(uuid)'::regprocedure,
      'public.recalculate_expense_totals(uuid)'::regprocedure
    )
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0
        or pg_get_userbyid(acl.grantee) not in (
          pg_get_userbyid(function_row.proowner),
          'authenticated',
          'service_role'
        )
      )
  ),
  'public wrappers expose no EXECUTE grant outside the exact allowlist'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.rebuild_expense_journal_entry(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.recalculate_expense_totals(uuid)',
    'EXECUTE'
  )
  and not exists (
    select 1
    from unnest(array[
      'public.create_expense_journal_entry(uuid)',
      'public.delete_expense_journal_entry(uuid)',
      'public.create_expense_payment_journal_entry(uuid)',
      'public.delete_expense_payment_journal_entry(uuid)'
    ]) signature
    where has_function_privilege('authenticated', signature, 'EXECUTE')
  ),
  'authenticated employees can rebuild/recalculate but cannot directly create or delete journals'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.create_expense_journal_entry(uuid)',
      'public.delete_expense_journal_entry(uuid)',
      'public.create_expense_payment_journal_entry(uuid)',
      'public.delete_expense_payment_journal_entry(uuid)',
      'public.rebuild_expense_journal_entry(uuid)',
      'public.recalculate_expense_totals(uuid)'
    ]) signature
    where not has_function_privilege('service_role', signature, 'EXECUTE')
  ),
  'service role retains the internal journal entry points'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'public.create_expense_journal_entry(uuid)',
      'public.delete_expense_journal_entry(uuid)',
      'public.create_expense_payment_journal_entry(uuid)',
      'public.delete_expense_payment_journal_entry(uuid)',
      'public.rebuild_expense_journal_entry(uuid)',
      'public.recalculate_expense_totals(uuid)'
    ]) signature
    where has_function_privilege('anon', signature, 'EXECUTE')
  ),
  'anonymous callers cannot execute an expense journal entry point'
);
select ok(
  not exists (
    select 1
    from pg_roles role
    cross join unnest(array[
      'public.create_expense_journal_entry(uuid)',
      'public.delete_expense_journal_entry(uuid)',
      'public.create_expense_payment_journal_entry(uuid)',
      'public.delete_expense_payment_journal_entry(uuid)',
      'public.rebuild_expense_journal_entry(uuid)',
      'public.recalculate_expense_totals(uuid)'
    ]) signature
    where role.rolname = 'codex_test_runner'
      and has_function_privilege(role.rolname, signature, 'EXECUTE')
  ),
  'read-only diagnostic login cannot execute expense journal mutations'
);

create temp table expense_rpc_fake_trigger_target (id integer);
create or replace function pg_temp.call_expense_delete_without_operation()
returns trigger
language plpgsql
as $$
begin
  perform public.delete_expense_payment_journal_entry(
    '9a215000-0000-4000-8000-000000000998'
  );
  return NEW;
end;
$$;
create trigger expense_rpc_fake_delete
after insert on expense_rpc_fake_trigger_target
for each row execute function pg_temp.call_expense_delete_without_operation();

select throws_ok(
  $$insert into expense_rpc_fake_trigger_target values (1)$$,
  '42501',
  'Expense not found or access denied',
  'trigger depth alone cannot authorize missing-source journal cleanup'
);

insert into public.tenants (id, shop_name)
values
  ('9a215000-0000-4000-8000-000000000001', 'Expense RPC Tenant A'),
  ('9a215000-0000-4000-8000-000000000002', 'Expense RPC Tenant B');

-- Tenant bootstrap currently seeds payment methods under a transaction-local
-- compatibility claim. Clear that internal fixture context before exercising
-- expense trace triggers as the database owner.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Production owns an auth onboarding trigger that is absent from schema-only
-- clones. Use its explicit existing-tenant customer path so it never creates a
-- third tenant; the test then adds the exact ERP profile it needs.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9a215000-0000-4000-8000-000000000091',
  'authenticated',
  'authenticated',
  'expense-rpc-a@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '9a215000-0000-4000-8000-000000000001',
    'name', 'Expense RPC Fixture'
  ),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '9a215000-0000-4000-8000-000000000091',
  '9a215000-0000-4000-8000-000000000001',
  'admin'
);

delete from public.payment_methods
where tenant_id = '9a215000-0000-4000-8000-000000000001';
delete from public.accounts
where tenant_id = '9a215000-0000-4000-8000-000000000001';

insert into public.accounts (id, tenant_id, code, name, type, category)
values
  (
    '9a215000-0000-4000-8000-000000000010',
    '9a215000-0000-4000-8000-000000000001',
    '1101', 'Caja', 'asset', 'currentAsset'
  ),
  (
    '9a215000-0000-4000-8000-000000000011',
    '9a215000-0000-4000-8000-000000000001',
    '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'
  ),
  (
    '9a215000-0000-4000-8000-000000000012',
    '9a215000-0000-4000-8000-000000000001',
    '2120', 'IVA Crédito Fiscal', 'asset', 'currentAsset'
  ),
  (
    '9a215000-0000-4000-8000-000000000013',
    '9a215000-0000-4000-8000-000000000001',
    '6200', 'Gastos Operacionales', 'expense', 'operatingExpense'
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values (
  '9a215000-0000-4000-8000-000000000020',
  '9a215000-0000-4000-8000-000000000001',
  'expense_rpc_cash',
  'Efectivo RPC',
  '9a215000-0000-4000-8000-000000000010',
  'no_tax'
);

-- Build both tenant fixtures without firing the accounting lifecycle. The
-- behavior under test begins only after all USER triggers are restored.
alter table public.expenses disable trigger user;
alter table public.expense_lines disable trigger user;

insert into public.expenses (
  id, tenant_id, expense_number, document_type, issue_date,
  posting_status, payment_status, subtotal, tax_amount, total_amount,
  amount_paid, balance
) values
  (
    '9a215000-0000-4000-8000-000000000101',
    '9a215000-0000-4000-8000-000000000001',
    'GTO-RPC-SHARED',
    'ticket',
    '2026-07-19 12:00:00+00',
    'posted',
    'pending',
    1, 0, 1, 0, 1
  ),
  (
    '9a215000-0000-4000-8000-000000000201',
    '9a215000-0000-4000-8000-000000000002',
    'GTO-RPC-SHARED',
    'ticket',
    '2026-07-19 12:00:00+00',
    'posted',
    'pending',
    777, 0, 777, 0, 777
  );

insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, subtotal, tax_rate,
  tax_amount, total
) values (
  '9a215000-0000-4000-8000-000000000102',
  '9a215000-0000-4000-8000-000000000001',
  '9a215000-0000-4000-8000-000000000101',
  0,
  '9a215000-0000-4000-8000-000000000013',
  '6200',
  'Gastos Operacionales',
  'Gasto propio balanceado',
  1, 1000, 1000, 0, 0, 1000
);

alter table public.expense_lines enable trigger user;
alter table public.expenses enable trigger user;

-- The foreign journal deliberately shares the mutable expense_number. Its
-- immutable source_document_id belongs to tenant B and must survive every
-- tenant-A recalculation, rebuild, and deletion below.
insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, source_document_type, source_document_id,
  status, total_debit, total_credit
) values (
  '9a215000-0000-4000-8000-000000000203',
  '9a215000-0000-4000-8000-000000000002',
  'JE-RPC-B',
  '2026-07-19 12:01:00+00',
  'Foreign same-number journal sentinel',
  'purchase',
  'expenses',
  'GTO-RPC-SHARED',
  'expense',
  '9a215000-0000-4000-8000-000000000201',
  'posted',
  777,
  777
);

alter table public.expense_payments disable trigger user;
insert into public.expense_payments (
  id, tenant_id, expense_id, amount, payment_date, reference
) values
  (
    '9a215000-0000-4000-8000-000000000202',
    '9a215000-0000-4000-8000-000000000002',
    '9a215000-0000-4000-8000-000000000201',
    0,
    '2026-07-19 12:05:00+00',
    'Cross-tenant denial fixture'
  ),
  (
    '9a215000-0000-4000-8000-000000000204',
    '9a215000-0000-4000-8000-000000000001',
    '9a215000-0000-4000-8000-000000000201',
    25,
    '2026-07-19 12:06:00+00',
    'Corrupt parent-tenant fixture'
  );
alter table public.expense_payments enable trigger user;

select set_config(
  'test.expense_rpc.expense_b',
  (
    select md5(to_jsonb(expense)::text)
    from public.expenses expense
    where expense.id = '9a215000-0000-4000-8000-000000000201'
  ),
  true
);
select set_config(
  'test.expense_rpc.journal_b',
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  true
);
select set_config(
  'test.expense_rpc.operations_b',
  (
    select count(*)::text
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a215000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a215000-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.create_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000201'
    )$$,
  '42501',
  'permission denied for function create_expense_journal_entry',
  'employees cannot directly create an expense journal'
);
select throws_ok(
  $$select public.delete_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000201'
    )$$,
  '42501',
  'permission denied for function delete_expense_journal_entry',
  'employees cannot directly delete an expense journal'
);
select throws_ok(
  $$select public.create_expense_payment_journal_entry(
      '9a215000-0000-4000-8000-000000000202'
    )$$,
  '42501',
  'permission denied for function create_expense_payment_journal_entry',
  'employees cannot directly create an expense payment journal'
);
select throws_ok(
  $$select public.delete_expense_payment_journal_entry(
      '9a215000-0000-4000-8000-000000000202'
    )$$,
  '42501',
  'permission denied for function delete_expense_payment_journal_entry',
  'employees cannot directly delete an expense payment journal'
);
select throws_ok(
  $$select public.rebuild_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000201'
    )$$,
  '42501',
  'Expense not found or access denied',
  'tenant A cannot rebuild a journal for tenant B expense'
);
select throws_ok(
  $$select public.recalculate_expense_totals(
      '9a215000-0000-4000-8000-000000000201'
    )$$,
  '42501',
  'Expense not found or access denied',
  'tenant A cannot recalculate totals for tenant B expense'
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a215000-0000-4000-8000-000000000091',
    'role', 'service_role'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.recalculate_expense_totals(
      '9a215000-0000-4000-8000-000000000201'
    )$$,
  '42501',
  'Expense not found or access denied',
  'authenticated database role cannot forge service_role through JWT claims'
);
reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9a215000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;
select throws_ok(
  $$select public.rebuild_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000999'
    )$$,
  '42501',
  'Expense not found or access denied',
  'an authenticated missing expense is indistinguishable from denied access'
);
select throws_ok(
  $$select public.recalculate_expense_totals(
      '9a215000-0000-4000-8000-000000000999'
    )$$,
  '42501',
  'Expense not found or access denied',
  'a missing recalculate target is indistinguishable from denied access'
);

reset role;

set local role service_role;
select throws_ok(
  $$select public.create_expense_payment_journal_entry(
      '9a215000-0000-4000-8000-000000000204'
    )$$,
  '23503',
  'Expense payment parent is missing',
  'payment journal creation rejects a parent expense from another tenant'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_module = 'expense_payments'
      and (
        entry.source_reference = '9a215000-0000-4000-8000-000000000204'
        or entry.source_document_id = '9a215000-0000-4000-8000-000000000204'
      )
  ),
  0,
  'rejected cross-tenant payment creates no journal'
);

select is(
  (
    select md5(to_jsonb(expense)::text)
    from public.expenses expense
    where expense.id = '9a215000-0000-4000-8000-000000000201'
  ),
  current_setting('test.expense_rpc.expense_b'),
  'denied calls leave the foreign expense byte-for-byte unchanged'
);
select is(
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.journal_b'),
  'denied calls leave every foreign journal unchanged'
);
select is(
  (
    select count(*)::text
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.operations_b'),
  'denied calls append no foreign accounting operation'
);

set local role authenticated;
select lives_ok(
  $$select public.recalculate_expense_totals(
      '9a215000-0000-4000-8000-000000000101'
    )$$,
  'tenant A can recalculate its own expense totals'
);
reset role;

select is(
  (
    select total_amount
    from public.expenses
    where id = '9a215000-0000-4000-8000-000000000101'
  ),
  1000::numeric,
  'own-tenant recalculation projects the exact line total'
);
select is(
  (
    select md5(to_jsonb(expense)::text)
    from public.expenses expense
    where expense.id = '9a215000-0000-4000-8000-000000000201'
  ),
  current_setting('test.expense_rpc.expense_b'),
  'tenant-A recalculation leaves the same-number tenant-B expense unchanged'
);
select is(
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.journal_b'),
  'tenant-A recalculation leaves the same-number tenant-B journal unchanged'
);

set local role authenticated;
select lives_ok(
  $$select public.rebuild_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000101'
    )$$,
  'tenant A can still rebuild its own expense journal'
);
reset role;

select is(
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.journal_b'),
  'tenant-A rebuild cannot delete the tenant-B same-number journal'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and operation.document_id = '9a215000-0000-4000-8000-000000000101'
      and operation.action = 'rebuild_journal'
      and operation.outcome = 'completed'
  ),
  1,
  'allowed own-tenant rebuild remains traced exactly once'
);
select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000101'
  ),
  1,
  'own-tenant rebuild leaves exactly one accrual journal'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000101'
    group by entry.id
    having sum(line.debit_amount) = sum(line.credit_amount)
       and sum(line.debit_amount) = 1000
  ),
  'own-tenant rebuild preserves an exactly balanced journal'
);

set local role authenticated;
select lives_ok(
  $$insert into public.expense_payments (
      id, tenant_id, expense_id, amount, payment_date, reference
    ) values (
      '9a215000-0000-4000-8000-000000000103',
      '9a215000-0000-4000-8000-000000000001',
      '9a215000-0000-4000-8000-000000000101',
      400,
      '2026-07-19 13:00:00+00',
      'Trigger compatibility fixture'
    )$$,
  'authenticated payment insert still reaches the tenant-safe journal trigger'
);
reset role;

select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000103'
    group by entry.id
    having sum(line.debit_amount) = sum(line.credit_amount)
       and sum(line.debit_amount) = 400
  ),
  'payment trigger creates one balanced own-tenant payment journal'
);
select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    join public.accounts account
      on account.id = line.account_id
     and account.tenant_id = line.tenant_id
    where entry.source_module = 'expense_payments'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000103'
      and entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and line.credit_amount = 400
      and account.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and account.code = '1101'
  ),
  'payment fallback selects account 1101 from the payment tenant only'
);

set local role authenticated;
select lives_ok(
  $$delete from public.expense_payments
    where id = '9a215000-0000-4000-8000-000000000103'$$,
  'AFTER DELETE payment trigger may clean the removed payment journal'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_module = 'expense_payments'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000103'
  ),
  0,
  'payment delete trigger removes the exact journal after its source row is gone'
);

set local role authenticated;
select lives_ok(
  $$insert into public.expense_payments (
      id, tenant_id, expense_id, amount, payment_date, reference
    ) values (
      '9a215000-0000-4000-8000-000000000104',
      '9a215000-0000-4000-8000-000000000001',
      '9a215000-0000-4000-8000-000000000101',
      250,
      '2026-07-19 13:30:00+00',
      'Parent cascade fixture'
    )$$,
  'authenticated payment insert prepares a journal for the parent cascade case'
);
reset role;

select is(
  (
    select count(*)::integer
      from public.journal_entries entry
     where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
       and entry.source_module = 'expense_payments'
       and entry.source_document_id = '9a215000-0000-4000-8000-000000000104'
  ),
  1,
  'the parent cascade fixture has exactly one payment journal before deletion'
);

set local role service_role;
select lives_ok(
  $$select public.delete_expense_journal_entry(
      '9a215000-0000-4000-8000-000000000101'
    )$$,
  'service cleanup can delete tenant A accrual journal by expense UUID'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and entry.source_module = 'expenses'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000101'
  ),
  0,
  'tenant-A service cleanup removes the exact UUID-owned journal'
);
select is(
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.journal_b'),
  'tenant-A deletion preserves the tenant-B same-number journal'
);

set local role authenticated;
select lives_ok(
  $$delete from public.expenses
    where id = '9a215000-0000-4000-8000-000000000101'$$,
  'expense delete trigger remains compatible with the hardened wrappers'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
      and entry.source_document_id = '9a215000-0000-4000-8000-000000000101'
  ),
  0,
  'expense delete trigger leaves no active accrual journal'
);

select is(
  (
    select count(*)::integer
      from public.journal_entries entry
     where entry.tenant_id = '9a215000-0000-4000-8000-000000000001'
       and entry.source_module = 'expense_payments'
       and entry.source_document_id = '9a215000-0000-4000-8000-000000000104'
  ),
  0,
  'expense deletion cascades live payments and removes their journals'
);

select is(
  (
    select md5(coalesce(string_agg(
      entry.id::text || '|' || coalesce(entry.updated_at::text, ''),
      ',' order by entry.id
    ), ''))
    from public.journal_entries entry
    where entry.tenant_id = '9a215000-0000-4000-8000-000000000002'
  ),
  current_setting('test.expense_rpc.journal_b'),
  'tenant-A source deletion leaves the tenant-B same-number journal intact'
);

select * from finish();
rollback;
