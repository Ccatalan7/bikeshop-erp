begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(12);

insert into public.tenants (id, shop_name)
values ('98600000-0000-4000-8000-000000000001', 'Digital Expense Test');

select ok(
  exists (
    select 1
    from public.accounts
    where tenant_id = '98600000-0000-4000-8000-000000000001'
      and code = '6207'
      and name = 'Servicios Digitales'
      and type = 'expense'
      and category = 'operatingExpense'
      and is_active
  ),
  'new tenants receive the Servicios Digitales parent expense account'
);

select ok(
  exists (
    select 1
    from public.accounts child
    join public.accounts parent
      on parent.tenant_id = child.tenant_id
     and parent.id = child.parent_id
    where child.tenant_id = '98600000-0000-4000-8000-000000000001'
      and child.code = '6207-01'
      and child.name = 'Dominios y Hosting'
      and parent.code = '6207'
  ),
  'Dominios y Hosting is a precise child of Servicios Digitales'
);

select ok(
  exists (
    select 1
    from public.expense_categories category
    join public.accounts default_account
      on default_account.tenant_id = category.tenant_id
     and default_account.id = category.default_account_id
    where category.tenant_id = '98600000-0000-4000-8000-000000000001'
      and category.name = 'Servicios Digitales'
      and default_account.code = '6207'
  ),
  'Servicios Digitales category exists and defaults to its parent account'
);

select is(
  public.get_expense_category_name_for_account(
    '6207-01',
    'Dominios y Hosting'
  ),
  'Servicios Digitales',
  'domain account code maps to the Servicios Digitales category'
);

select is(
  public.get_expense_category_name_for_account(
    '9999',
    'Renovación de dominio web'
  ),
  'Servicios Digitales',
  'domain account names use the digital-services fallback'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.seed_digital_services_expense_classification(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.seed_digital_services_expense_classification(uuid)',
    'execute'
  ),
  'clients cannot invoke the tenant-wide digital classification seeder'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.handle_new_tenant_digital_expense_classification()',
    'execute'
  )
  and not has_function_privilege(
    'authenticated',
    'public.handle_new_tenant_digital_expense_classification()',
    'execute'
  ),
  'clients cannot invoke the internal new-tenant trigger function'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '98600000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'digital-expense@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '98600000-0000-4000-8000-000000000001'),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '98600000-0000-4000-8000-000000000099';

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98600000-0000-4000-8000-000000000099',
  '98600000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
select
  '98600000-0000-4000-8000-000000000020',
  '98600000-0000-4000-8000-000000000001',
  'digital_expense_card',
  'Tarjeta gasto digital',
  account.id,
  'no_tax'
from public.accounts account
where account.tenant_id = '98600000-0000-4000-8000-000000000001'
  and account.code = '1101';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98600000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98600000-0000-4000-8000-000000000099',
  true
);

insert into public.expenses (
  id, tenant_id, expense_number, supplier_name, document_type,
  document_number, issue_date, posting_status, payment_status,
  payment_method_id, payment_account_id, subtotal, tax_amount,
  total_amount, amount_paid, balance
)
select
  '98600000-0000-4000-8000-000000000030',
  '98600000-0000-4000-8000-000000000001',
  'GTO-DIGITAL-001',
  'NIC Chile',
  'receipt',
  '21179232',
  '2026-07-17 12:00:00+00',
  'posted',
  'paid',
  method.id,
  method.account_id,
  19980,
  0,
  19980,
  19980,
  0
from public.payment_methods method
where method.id = '98600000-0000-4000-8000-000000000020';

insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, subtotal,
  tax_rate, tax_amount, total
)
select
  '98600000-0000-4000-8000-000000000031',
  '98600000-0000-4000-8000-000000000001',
  '98600000-0000-4000-8000-000000000030',
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
where account.tenant_id = '98600000-0000-4000-8000-000000000001'
  and account.code = '6207-01';

-- Rebuild after synchronizing all lines instead of asserting an intermediate
-- header-without-lines state.
select public.create_expense_journal_entry(
  '98600000-0000-4000-8000-000000000030'
);

select is(
  (
    select category.name
    from public.expenses expense
    join public.expense_categories category on category.id = expense.category_id
    where expense.id = '98600000-0000-4000-8000-000000000030'
  ),
  'Servicios Digitales',
  'database fallback categorizes an older uncategorized client expense'
);

select is(
  (
    select count(*)::integer
    from public.journal_entries
    where source_module = 'expenses'
      and source_reference = 'GTO-DIGITAL-001'
  ),
  1,
  'posted NIC expense creates exactly one journal entry'
);

select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.source_module = 'expenses'
      and entry.source_reference = 'GTO-DIGITAL-001'
      and line.account_code = '6207-01'
      and line.account_name = 'Dominios y Hosting'
      and line.debit_amount = 19980
      and line.credit_amount = 0
  ),
  'journal debits Dominios y Hosting for the exact receipt amount'
);

select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.source_module = 'expenses'
      and entry.source_reference = 'GTO-DIGITAL-001'
    group by entry.id
    having sum(line.debit_amount) = sum(line.credit_amount)
       and sum(line.debit_amount) = 19980
  ),
  'NIC expense journal remains balanced at the exact receipt total'
);

select is(
  (
    select count(*)::integer
    from public.expenses
    where id = '98600000-0000-4000-8000-000000000030'
      and category_id is null
  ),
  0,
  'stored NIC expense cannot remain uncategorized'
);

select * from finish();
rollback;
