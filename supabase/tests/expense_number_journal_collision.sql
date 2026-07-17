begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(9);

insert into public.tenants (id, shop_name)
values ('98700000-0000-4000-8000-000000000001', 'Expense Collision Test');

insert into auth.users (
  id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '98700000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'expense-collision@example.invalid',
  '',
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '98700000-0000-4000-8000-000000000001'),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '98700000-0000-4000-8000-000000000099';

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98700000-0000-4000-8000-000000000099',
  '98700000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.document_sequences (tenant_id, document_type, last_number)
values ('98700000-0000-4000-8000-000000000001', 'expense', 133)
on conflict (tenant_id, document_type)
do update set last_number = excluded.last_number;

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit,
  created_at, updated_at
) values (
  '98700000-0000-4000-8000-000000000010',
  '98700000-0000-4000-8000-000000000001',
  'AC-LEGACY-EXPENSE',
  '2026-07-09 12:00:00+00',
  'Preserved journal for a deleted legacy expense',
  'purchase',
  'expenses',
  'GTO-00135',
  'posted',
  19980,
  19980,
  '2026-07-09 12:00:00+00',
  '2026-07-09 12:00:00+00'
);

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount
)
select
  '98700000-0000-4000-8000-000000000011',
  '98700000-0000-4000-8000-000000000001',
  '98700000-0000-4000-8000-000000000010',
  account.id,
  account.code,
  account.name,
  'Legacy debit',
  19980,
  0
from public.accounts account
where account.tenant_id = '98700000-0000-4000-8000-000000000001'
  and account.code = '1101';

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount
)
select
  '98700000-0000-4000-8000-000000000012',
  '98700000-0000-4000-8000-000000000001',
  '98700000-0000-4000-8000-000000000010',
  account.id,
  account.code,
  account.name,
  'Legacy credit',
  0,
  19980
from public.accounts account
where account.tenant_id = '98700000-0000-4000-8000-000000000001'
  and account.code = '1110';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98700000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98700000-0000-4000-8000-000000000099',
  true
);

-- This is the exact pre-fix failure shape: the header has no lines or accrual
-- yet, while an unrelated preserved journal owns the same historical text
-- reference. UUID-based trace identity must ignore that journal.
insert into public.expenses (
  id, tenant_id, expense_number, supplier_name, document_type,
  issue_date, posting_status, payment_status, subtotal, tax_amount,
  total_amount, amount_paid, balance
) values (
  '98700000-0000-4000-8000-000000000025',
  '98700000-0000-4000-8000-000000000001',
  'GTO-00135',
  'Collision probe',
  'receipt',
  '2026-07-17 12:00:00+00',
  'draft',
  'pending',
  0,
  0,
  0,
  0,
  0
);

select ok(
  exists (
    select 1
    from public.expenses expense
    where expense.id = '98700000-0000-4000-8000-000000000025'
  ),
  'expense header trace ignores an unrelated journal with the same text reference'
);

select is(
  public.preview_next_document_number(
    '98700000-0000-4000-8000-000000000001',
    'expense'
  ),
  'GTO-00136',
  'expense preview skips a preserved orphan journal reference'
);

select is(
  public.get_next_document_number(
    '98700000-0000-4000-8000-000000000001',
    'expense'
  ),
  'GTO-00136',
  'expense issuance skips a preserved orphan journal reference'
);

select is(
  (
    select last_number
    from public.document_sequences
    where tenant_id = '98700000-0000-4000-8000-000000000001'
      and document_type = 'expense'
  ),
  136,
  'expense sequence advances to the non-colliding high-water mark'
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
select
  '98700000-0000-4000-8000-000000000020',
  '98700000-0000-4000-8000-000000000001',
  'expense_collision_card',
  'Tarjeta gasto colisión',
  account.id,
  'no_tax'
from public.accounts account
where account.tenant_id = '98700000-0000-4000-8000-000000000001'
  and account.code = '1101';

insert into public.expenses (
  id, tenant_id, expense_number, category_id, supplier_name, document_type,
  document_number, issue_date, posting_status, payment_status,
  payment_method_id, payment_account_id, subtotal, tax_amount,
  total_amount, amount_paid, balance
)
select
  '98700000-0000-4000-8000-000000000030',
  '98700000-0000-4000-8000-000000000001',
  'GTO-00136',
  category.id,
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
join public.expense_categories category
  on category.tenant_id = method.tenant_id
 and lower(category.name) = lower('Servicios Digitales')
where method.id = '98700000-0000-4000-8000-000000000020';

insert into public.expense_lines (
  id, tenant_id, expense_id, line_index, account_id, account_code,
  account_name, description, quantity, unit_price, subtotal,
  tax_rate, tax_amount, total
)
select
  '98700000-0000-4000-8000-000000000031',
  '98700000-0000-4000-8000-000000000001',
  '98700000-0000-4000-8000-000000000030',
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
where account.tenant_id = '98700000-0000-4000-8000-000000000001'
  and account.code = '6207-01';

select public.rebuild_expense_journal_entry(
  '98700000-0000-4000-8000-000000000030'
);

select ok(
  exists (
    select 1
    from public.expenses expense
    join public.expense_categories category on category.id = expense.category_id
    where expense.id = '98700000-0000-4000-8000-000000000030'
      and expense.total_amount = 19980
      and expense.amount_paid = 19980
      and expense.balance = 0
      and category.name = 'Servicios Digitales'
  ),
  'the retried NIC expense persists with correct totals and category'
);

select is(
  (
    select count(*)::integer
    from public.journal_entries entry
    where entry.source_module = 'expenses'
      and entry.source_document_id = '98700000-0000-4000-8000-000000000030'
      and entry.source_reference = 'GTO-00136'
  ),
  1,
  'the retried expense creates exactly one UUID-linked accrual journal'
);

select ok(
  exists (
    select 1
    from public.journal_entries entry
    join public.journal_lines line on line.entry_id = entry.id
    where entry.source_document_id = '98700000-0000-4000-8000-000000000030'
    group by entry.id
    having sum(line.debit_amount) = sum(line.credit_amount)
       and sum(line.debit_amount) = 19980
  ),
  'the retried NIC expense journal balances at 19980'
);

select ok(
  exists (
    select 1
    from public.journal_entries entry
    where entry.id = '98700000-0000-4000-8000-000000000010'
      and entry.source_reference = 'GTO-00135'
      and entry.source_document_id is null
  ),
  'preserved orphan accounting evidence is not deleted or reassigned'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_inconsistencies_view inconsistency
    where inconsistency.tenant_id = '98700000-0000-4000-8000-000000000001'
      and inconsistency.severity in ('high', 'critical')
  ),
  0,
  'the collision-safe retry leaves no high-severity accounting inconsistency'
);

select * from finish();
rollback;
