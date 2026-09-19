-- Fixture of the two-connection payroll race, committed on the synthetic
-- LOCAL stack only. Driven by scripts/db/payroll_lock_probe.sh; never run
-- against a hosted project.
--
-- One week of $100.000 owed to one worker, and a $40.000 charge in the
-- statement that a review wants to pay it with.
\ir payroll_lock_cleanup.sql

begin;

set local session_replication_role = replica;
insert into public.tenants (id, shop_name, timezone) values
  ('e9000000-0000-4000-8000-000000000001', 'Carrera de Nómina',
   'America/Santiago');
delete from public.payment_terminal_terms
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e9000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'payroll-lock-probe@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e9000000-0000-4000-8000-000000000003',
  'e9000000-0000-4000-8000-000000000002',
  'e9000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e9000000-0000-4000-8000-000000000010',
   'e9000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e9000000-0000-4000-8000-000000000011',
   'e9000000-0000-4000-8000-000000000001',
   '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'),
  ('e9000000-0000-4000-8000-000000000012',
   'e9000000-0000-4000-8000-000000000001',
   '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'),
  ('e9000000-0000-4000-8000-000000000013',
   'e9000000-0000-4000-8000-000000000001',
   '6101', 'Gastos de personal', 'expense', 'operatingExpense');
insert into public.accounts (
  id, tenant_id, code, name, type, category, parent_id
) values (
  'e9000000-0000-4000-8000-000000000014',
  'e9000000-0000-4000-8000-000000000001',
  '610101', 'Sueldo Braulio', 'expense', 'operatingExpense',
  'e9000000-0000-4000-8000-000000000013'
);
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values (
  'e9000000-0000-4000-8000-000000000020',
  'e9000000-0000-4000-8000-000000000001',
  'transfer', 'Transferencia', 'e9000000-0000-4000-8000-000000000010', 'no_tax'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"e9000000-0000-4000-8000-000000000002","role":"authenticated"}',
  false
);
select set_config(
  'request.jwt.claim.sub', 'e9000000-0000-4000-8000-000000000002', false
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
) values (
  'e9000000-0000-4000-8000-000000000030',
  'e9000000-0000-4000-8000-000000000001',
  'E-1', 'Braulio', 'Muñoz', 'Mecánico',
  'e9000000-0000-4000-8000-000000000014',
  'e9000000-0000-4000-8000-000000000020'
);
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  'e9000000-0000-4000-8000-000000000040',
  'e9000000-0000-4000-8000-000000000001',
  'NOM-90001', '2026-08-24', '2026-08-30', 'Semana 35', 25, 100000, 1, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values (
  'e9000000-0000-4000-8000-000000000041',
  'e9000000-0000-4000-8000-000000000001',
  'e9000000-0000-4000-8000-000000000040',
  'e9000000-0000-4000-8000-000000000030',
  'Braulio Muñoz', 25, 4000, 100000, 100000,
  'e9000000-0000-4000-8000-000000000020',
  'e9000000-0000-4000-8000-000000000010',
  'e9000000-0000-4000-8000-000000000014'
);

-- The week is already recognized, as it is when Nómina has been working on
-- it: what changes under the review is the balance, not the lifecycle.
select public.confirm_payroll_voucher_v2(
  'e9000000-0000-4000-8000-000000000040',
  'payroll-lock-probe:confirm',
  (select reconciliation_version from public.payroll_vouchers
    where id = 'e9000000-0000-4000-8000-000000000040')
);

select public.save_bank_statement_import_v1(
  'payroll-lock-probe:import', repeat('9', 64), repeat('8', 64),
  'e9000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'source_row_id', 'braulio', 'ordinal', 1, 'booking_date', '2026-08-31',
    'operation_date', null, 'direction', 'debit', 'amount', 40000,
    'description', 'App-traspaso A: Braulio Munoz Internet',
    'normalized_description', 'app traspaso a braulio munoz internet',
    'counterparty_observed', 'Braulio Munoz Internet', 'document_number', null,
    'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', 1, 'source_line_end', 1,
    'fingerprint', repeat('7', 64)
  ))
);

commit;

-- What both connections need to name.
select import.id as import_id, import.revision, row.id as row_id
  from public.bank_statement_imports import
  join public.bank_statement_rows row on row.import_id = import.id
 where import.tenant_id = 'e9000000-0000-4000-8000-000000000001';
