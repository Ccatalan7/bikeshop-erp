begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('ea000000-0000-4000-8000-000000000001', 'Reversa con fecha',
   'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id = 'ea000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'ea000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'ea000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'ea000000-0000-4000-8000-000000000001';

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'ea000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'reversal-dates@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'ea000000-0000-4000-8000-000000000003',
  'ea000000-0000-4000-8000-000000000002',
  'ea000000-0000-4000-8000-000000000001',
  'accountant',
  '{"access_accounting":true,"access_hr":true}'::jsonb, true
);
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('ea000000-0000-4000-8000-000000000010',
   'ea000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('ea000000-0000-4000-8000-000000000011',
   'ea000000-0000-4000-8000-000000000001',
   '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'),
  ('ea000000-0000-4000-8000-000000000012',
   'ea000000-0000-4000-8000-000000000001',
   '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'),
  ('ea000000-0000-4000-8000-000000000013',
   'ea000000-0000-4000-8000-000000000001',
   '6101', 'Gastos de personal', 'expense', 'operatingExpense');
insert into public.accounts (
  id, tenant_id, code, name, type, category, parent_id
) values (
  'ea000000-0000-4000-8000-000000000014',
  'ea000000-0000-4000-8000-000000000001',
  '610101', 'Sueldo Braulio', 'expense', 'operatingExpense',
  'ea000000-0000-4000-8000-000000000013'
);
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values (
  'ea000000-0000-4000-8000-000000000020',
  'ea000000-0000-4000-8000-000000000001',
  'transfer', 'Transferencia', 'ea000000-0000-4000-8000-000000000010', 'no_tax'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ea000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'ea000000-0000-4000-8000-000000000002', true
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
) values (
  'ea000000-0000-4000-8000-000000000030',
  'ea000000-0000-4000-8000-000000000001',
  'E-1', 'Braulio', 'Muñoz', 'Mecánico',
  'ea000000-0000-4000-8000-000000000014',
  'ea000000-0000-4000-8000-000000000020'
);
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  'ea000000-0000-4000-8000-000000000040',
  'ea000000-0000-4000-8000-000000000001',
  'NOM-91001', '2026-08-24', '2026-08-30', 'Semana 35', 25, 100000, 1, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values (
  'ea000000-0000-4000-8000-000000000041',
  'ea000000-0000-4000-8000-000000000001',
  'ea000000-0000-4000-8000-000000000040',
  'ea000000-0000-4000-8000-000000000030',
  'Braulio Muñoz', 25, 4000, 100000, 100000,
  'ea000000-0000-4000-8000-000000000020',
  'ea000000-0000-4000-8000-000000000010',
  'ea000000-0000-4000-8000-000000000014'
);

select public.confirm_payroll_voucher_v2(
  'ea000000-0000-4000-8000-000000000040',
  'reversal-dates:confirm',
  (select reconciliation_version from public.payroll_vouchers
    where id = 'ea000000-0000-4000-8000-000000000040')
);

-- A salary paid on 31 August, weeks before anybody notices the mistake.
select public.pay_payroll_voucher_v2(
  'ea000000-0000-4000-8000-000000000040',
  'reversal-dates:pay',
  (select reconciliation_version from public.payroll_vouchers
    where id = 'ea000000-0000-4000-8000-000000000040'),
  jsonb_build_object(
    'ea000000-0000-4000-8000-000000000041',
    jsonb_build_array(jsonb_build_object(
      'kind', 'payment',
      'amount', 30000,
      'payment_method_id', 'ea000000-0000-4000-8000-000000000020',
      'payment_account_id', 'ea000000-0000-4000-8000-000000000010',
      'payment_date', '2026-08-31T12:00:00Z',
      'reference', 'Transferencia 31-08-2026'
    ))
  )
);

create temp table paid on commit drop as
select payment.id, payment.payment_date, payment.expense_id
  from public.expense_payments payment
 where payment.tenant_id = 'ea000000-0000-4000-8000-000000000001';

select public.reverse_payroll_settlement_v1(
  'ea000000-0000-4000-8000-000000000040',
  'payment',
  (select id from paid),
  'Se registró en la cuenta equivocada',
  'reversal-dates:reverse',
  (select reconciliation_version from public.payroll_vouchers
    where id = 'ea000000-0000-4000-8000-000000000040')
);

-- A correction is not money moving the day it is noticed: both sides sit in
-- the month the payment claimed, or August shows a salary that was never
-- paid and September a negative one.
select results_eq(
  $$select reversal.amount::integer, reversal.payment_date::date
      from public.expense_payments reversal
     where reversal.tenant_id = 'ea000000-0000-4000-8000-000000000001'
       and reversal.reversal_of_id is not null$$,
  $$values (-30000, '2026-08-31'::date)$$,
  'the counter-payment is dated as the payment it cancels'
);

select results_eq(
  $$select entry.entry_date::date, entry.type
      from public.journal_entries entry
      join public.expense_payments reversal
        on reversal.id = entry.source_document_id
     where entry.tenant_id = 'ea000000-0000-4000-8000-000000000001'
       and entry.source_module = 'expense_payments'
       and reversal.reversal_of_id is not null$$,
  $$values ('2026-08-31'::date, 'payment_reversal'::text)$$,
  'its journal follows the same date, so no month keeps half of the pair'
);

select ok(
  (
    select reversal.created_at::date = current_date
       and reversal.reversal_reason = 'Se registró en la cuenta equivocada'
      from public.expense_payments reversal
     where reversal.tenant_id = 'ea000000-0000-4000-8000-000000000001'
       and reversal.reversal_of_id is not null
  ),
  'when it was corrected, and why, stay on the row'
);

select is(
  (
    select coalesce(sum(payment.amount), 0)::integer
      from public.expense_payments payment
     where payment.tenant_id = 'ea000000-0000-4000-8000-000000000001'
       and payment.payment_date >= '2026-08-01'
       and payment.payment_date < '2026-09-01'
  ),
  0,
  'August is left owing nothing for a salary it never paid'
);

select * from finish();
rollback;
