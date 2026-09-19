begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_bank_reconciliation_actions_v3(uuid,bigint,text,jsonb)',
    'EXECUTE'
  ),
  'accountants apply v3; anonymous callers cannot'
);

insert into public.tenants (id, shop_name, timezone) values
  ('e4000000-0000-4000-8000-000000000001', 'Paga sueldos', 'America/Santiago'),
  ('e4000000-0000-4000-8000-000000000901', 'Otro taller', 'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id in (
   'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000901'
 );
delete from public.payment_terminal_profiles
 where tenant_id in (
   'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000901'
 );
delete from public.payment_methods
 where tenant_id in (
   'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000901'
 );
delete from public.accounts
 where tenant_id in (
   'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000901'
 );
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e4000000-0000-4000-8000-000000000010', 'e4000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e4000000-0000-4000-8000-000000000011', 'e4000000-0000-4000-8000-000000000001',
   '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'),
  ('e4000000-0000-4000-8000-000000000012', 'e4000000-0000-4000-8000-000000000001',
   '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'),
  ('e4000000-0000-4000-8000-000000000013', 'e4000000-0000-4000-8000-000000000001',
   '6101', 'Gastos de personal', 'expense', 'operatingExpense'),
  ('e4000000-0000-4000-8000-000000000910', 'e4000000-0000-4000-8000-000000000901',
   '1110', 'Banco ajeno', 'asset', 'currentAsset');
insert into public.accounts (id, tenant_id, code, name, type, category, parent_id) values
  ('e4000000-0000-4000-8000-000000000014', 'e4000000-0000-4000-8000-000000000001',
   '610101', 'Sueldo Braulio', 'expense', 'operatingExpense',
   'e4000000-0000-4000-8000-000000000013'),
  ('e4000000-0000-4000-8000-000000000015', 'e4000000-0000-4000-8000-000000000001',
   '610102', 'Sueldo Vicente', 'expense', 'operatingExpense',
   'e4000000-0000-4000-8000-000000000013');

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e4000000-0000-4000-8000-000000000010', 'no_tax');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e4000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'pays-payroll@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e4000000-0000-4000-8000-000000000003',
  'e4000000-0000-4000-8000-000000000002',
  'e4000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
-- Another shop's week: never payable from this tenant's statement.
insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title
) values (
  'e4000000-0000-4000-8000-000000000950', 'e4000000-0000-4000-8000-000000000901',
  'E-1', 'Braulio', 'Muñoz', 'Mecánico'
);
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label, status
) values (
  'e4000000-0000-4000-8000-000000000951', 'e4000000-0000-4000-8000-000000000901',
  'NOM-00037', '2026-08-24', '2026-08-30', 'Semana 35', 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, total_amount,
  is_included
) values (
  'e4000000-0000-4000-8000-000000000952', 'e4000000-0000-4000-8000-000000000901',
  'e4000000-0000-4000-8000-000000000951', 'e4000000-0000-4000-8000-000000000950',
  'Braulio Muñoz', 71400, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e4000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e4000000-0000-4000-8000-000000000002', true
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
) values
  ('e4000000-0000-4000-8000-000000000030', 'e4000000-0000-4000-8000-000000000001',
   'E-1', 'Braulio', 'Muñoz', 'Mecánico',
   'e4000000-0000-4000-8000-000000000014', 'e4000000-0000-4000-8000-000000000020'),
  ('e4000000-0000-4000-8000-000000000031', 'e4000000-0000-4000-8000-000000000001',
   'E-2', 'Vicente', 'Díaz', 'Mecánico',
   'e4000000-0000-4000-8000-000000000015', 'e4000000-0000-4000-8000-000000000020');

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  'e4000000-0000-4000-8000-000000000040', 'e4000000-0000-4000-8000-000000000001',
  'NOM-00037', '2026-08-24', '2026-08-30', 'Semana 35', 40, 181300, 2, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values
  ('e4000000-0000-4000-8000-000000000041', 'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000040', 'e4000000-0000-4000-8000-000000000030',
   'Braulio Muñoz', 17, 4200, 71400, 71400,
   'e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000010',
   'e4000000-0000-4000-8000-000000000014'),
  ('e4000000-0000-4000-8000-000000000042', 'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000040', 'e4000000-0000-4000-8000-000000000031',
   'Vicente Díaz', 23, 4778.26, 109900, 109900,
   'e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000010',
   'e4000000-0000-4000-8000-000000000015');

select is(
  (
    select jsonb_agg(jsonb_build_object(
      'line', line->>'line_id',
      'status', line->>'status',
      'amount', (line->>'amount')::numeric,
      'versioned', jsonb_typeof(line->'reconciliation_version'),
      'payable_from', line->>'payable_from'
    ) order by line->>'employee_name')
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v2(
        'e4000000-0000-4000-8000-000000000010', '2026-08-25', '2026-09-05'
      )->'payroll_lines'
    ) line
  ),
  jsonb_build_array(
    jsonb_build_object('line', 'e4000000-0000-4000-8000-000000000041',
      'status', 'draft', 'amount', 71400, 'versioned', 'number',
      'payable_from', '2026-08-30'),
    jsonb_build_object('line', 'e4000000-0000-4000-8000-000000000042',
      'status', 'draft', 'amount', 109900, 'versioned', 'number',
      'payable_from', '2026-08-30')
  ),
  'the catalog lists what a week owes, its status, version and first payable day'
);

create temp table pays_payroll_import on commit drop as
select public.save_bank_statement_import_v1(
  'pays-payroll:import', repeat('a', 64), repeat('b', 64),
  'e4000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    jsonb_build_object(
      'source_row_id', 'braulio', 'ordinal', 1, 'booking_date', '2026-08-31',
      'operation_date', null, 'direction', 'debit', 'amount', 71400,
      'description', 'App-traspaso A: Braulio Munoz Internet',
      'normalized_description', 'app traspaso a braulio munoz internet',
      'counterparty_observed', 'Braulio Munoz Internet', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 10, 'source_line_end', 10,
      'fingerprint', repeat('c', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'vicente', 'ordinal', 2, 'booking_date', '2026-09-03',
      'operation_date', null, 'direction', 'debit', 'amount', 109900,
      'description', 'App-traspaso A: Vicente Diaz Internet',
      'normalized_description', 'app traspaso a vicente diaz internet',
      'counterparty_observed', 'Vicente Diaz Internet', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 11, 'source_line_end', 11,
      'fingerprint', repeat('d', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'fee', 'ordinal', 3, 'booking_date', '2026-09-04',
      'operation_date', null, 'direction', 'debit', 'amount', 459,
      'description', 'Comision Compras En El Extranjero',
      'normalized_description', 'comision compras en el extranjero',
      'counterparty_observed', null, 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 12, 'source_line_end', 12,
      'fingerprint', repeat('e', 64)
    )
  )
) as receipt;

create temp table pays_payroll_ids on commit drop as
select
  (select receipt->>'import_id' from pays_payroll_import)::uuid as import_id,
  (select (receipt->>'revision')::bigint from pays_payroll_import) as revision,
  (select id from public.bank_statement_rows
    where tenant_id = 'e4000000-0000-4000-8000-000000000001'
      and source_row_id = 'braulio') as braulio_row,
  (select id from public.bank_statement_rows
    where tenant_id = 'e4000000-0000-4000-8000-000000000001'
      and source_row_id = 'vicente') as vicente_row,
  (select id from public.bank_statement_rows
    where tenant_id = 'e4000000-0000-4000-8000-000000000001'
      and source_row_id = 'fee') as fee_row;

-- The three rows, with the salaries' payroll payload parameterised.
create temp table pays_payroll_actions on commit drop as
select
  jsonb_build_array(
    jsonb_build_object(
      'row_id', ids.braulio_row, 'action', 'pay_payroll',
      'payroll', jsonb_build_object(
        'voucher_id', 'e4000000-0000-4000-8000-000000000040',
        'voucher_line_id', 'e4000000-0000-4000-8000-000000000041',
        'expected_amount', 71400, 'amount', 71400,
        'payment_method_id', 'e4000000-0000-4000-8000-000000000020',
        'confirm_draft', true
      )
    ),
    jsonb_build_object(
      'row_id', ids.vicente_row, 'action', 'pay_payroll',
      'payroll', jsonb_build_object(
        'voucher_id', 'e4000000-0000-4000-8000-000000000040',
        'voucher_line_id', 'e4000000-0000-4000-8000-000000000042',
        'expected_amount', 109900, 'amount', 109900,
        'payment_method_id', 'e4000000-0000-4000-8000-000000000020',
        'confirm_draft', true
      )
    ),
    jsonb_build_object(
      'row_id', ids.fee_row, 'action', 'dismiss',
      'reason', 'Se registra en otra revisión'
    )
  ) as good
from pays_payroll_ids ids;

select throws_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from pays_payroll_ids),
    (select revision from pays_payroll_ids),
    'pays-payroll:no-consent',
    jsonb_set(
      (select good from pays_payroll_actions),
      '{0,payroll,confirm_draft}', 'false'::jsonb
    )
  ),
  '55000',
  'bank_reconciliation_payroll_week_is_draft',
  'a draft week is confirmed only when the row agreed to it'
);

select throws_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from pays_payroll_ids),
    (select revision from pays_payroll_ids),
    'pays-payroll:stale',
    jsonb_set(
      (select good from pays_payroll_actions),
      '{0,payroll,expected_amount}', '70000'::jsonb
    )
  ),
  '40001',
  'bank_reconciliation_payroll_line_changed',
  'a salary that changed since the review is not paid'
);

select throws_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from pays_payroll_ids),
    (select revision from pays_payroll_ids),
    'pays-payroll:foreign',
    jsonb_set(
      jsonb_set(
        (select good from pays_payroll_actions),
        '{0,payroll,voucher_id}',
        '"e4000000-0000-4000-8000-000000000951"'::jsonb
      ),
      '{0,payroll,voucher_line_id}',
      '"e4000000-0000-4000-8000-000000000952"'::jsonb
    )
  ),
  '42501',
  'bank_reconciliation_payroll_not_accessible',
  'another shop''s payroll week cannot be paid from this statement'
);

select is(
  (
    select count(*)::integer
    from public.expense_payments payment
    where payment.tenant_id = 'e4000000-0000-4000-8000-000000000001'
  ),
  0,
  'the rejected attempts paid nothing'
);

create temp table pays_payroll_receipt on commit drop as
select public.apply_bank_reconciliation_actions_v3(
  (select import_id from pays_payroll_ids),
  (select revision from pays_payroll_ids),
  'pays-payroll:apply',
  (select good from pays_payroll_actions)
) as receipt;

select is(
  (
    select jsonb_build_object(
      'paid', (receipt->>'payroll_payment_count')::integer,
      'confirmed', (receipt->>'payroll_confirmed_week_count')::integer,
      'replayed', (receipt->>'replayed')::boolean
    )
    from pays_payroll_receipt
  ),
  '{"paid": 2, "confirmed": 1, "replayed": false}'::jsonb,
  'one apply confirms the week once and pays both salaries'
);

select is(
  (
    select status
    from public.payroll_vouchers
    where id = 'e4000000-0000-4000-8000-000000000040'
  ),
  'paid',
  'Nómina sees the week paid'
);

select is(
  (
    select jsonb_agg(jsonb_build_object(
      'amount', payment.amount,
      'date', (payment.payment_date at time zone 'America/Santiago')::date,
      'bank', payment.payment_account_id = 'e4000000-0000-4000-8000-000000000010'
    ) order by payment.amount)
    from public.expense_payments payment
    join public.payroll_voucher_lines line
      on line.tenant_id = payment.tenant_id
     and line.expense_id = payment.expense_id
    where line.voucher_id = 'e4000000-0000-4000-8000-000000000040'
  ),
  '[{"amount": 71400, "date": "2026-08-31", "bank": true},
    {"amount": 109900, "date": "2026-09-03", "bank": true}]'::jsonb,
  'each salary is paid from this bank on the day the statement shows'
);

select is(
  (
    select jsonb_agg(jsonb_build_object(
      'row', statement_row.source_row_id,
      'kind', allocation.target_kind,
      'same_payment', allocation.target_id = (
        select payment.id
        from public.expense_payments payment
        join public.payroll_voucher_lines line
          on line.tenant_id = payment.tenant_id
         and line.expense_id = payment.expense_id
        where line.id = (decision.action_snapshot->'payroll_payment'->>'voucher_line_id')::uuid
      ),
      'decision', decision.action_kind
    ) order by statement_row.ordinal)
    from public.bank_reconciliation_allocations allocation
    join public.bank_statement_rows statement_row
      on statement_row.id = allocation.row_id
    join public.bank_reconciliation_row_decisions decision
      on decision.row_id = allocation.row_id
    where allocation.import_id = (select import_id from pays_payroll_ids)
  ),
  '[{"row": "braulio", "kind": "expense_payment", "same_payment": true, "decision": "associate_existing"},
    {"row": "vicente", "kind": "expense_payment", "same_payment": true, "decision": "associate_existing"}]'::jsonb,
  'each bank row is associated with the payment Nómina created for it'
);

select is(
  (
    select coalesce(sum(line.credit_amount), 0) - coalesce(sum(line.debit_amount), 0)
    from public.journal_lines line
    join public.journal_entries entry
      on entry.id = line.entry_id
    where line.tenant_id = 'e4000000-0000-4000-8000-000000000001'
      and line.account_id = 'e4000000-0000-4000-8000-000000000010'
      and entry.status = 'posted'
  ),
  181300::numeric,
  'the ledger takes both salaries out of the bank once'
);

select is(
  (
    select jsonb_build_object(
      'replayed', (receipt->>'replayed')::boolean,
      'paid', (receipt->>'payroll_payment_count')::integer
    )
    from (
      select public.apply_bank_reconciliation_actions_v3(
        (select import_id from pays_payroll_ids),
        (select revision from pays_payroll_ids),
        'pays-payroll:apply',
        (select good from pays_payroll_actions)
      ) as receipt
    ) retry
  ),
  '{"replayed": true, "paid": 2}'::jsonb,
  'a retry returns the first result'
);

select is(
  (
    select count(*)::integer
    from public.expense_payments payment
    where payment.tenant_id = 'e4000000-0000-4000-8000-000000000001'
  ),
  2,
  'and pays nothing twice'
);

select is(
  (
    select jsonb_array_length(
      public.get_bank_reconciliation_candidates_v2(
        'e4000000-0000-4000-8000-000000000010', '2026-08-25', '2026-09-05'
      )->'payroll_lines'
    )
  ),
  0,
  'a paid week no longer appears as owed'
);

-- The same week split across two statements: August confirms it and pays
-- Braulio; September, reviewed while the week was still a draft, pays
-- Vicente without confirming it again.
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  'e4000000-0000-4000-8000-000000000060', 'e4000000-0000-4000-8000-000000000001',
  'NOM-00038', '2026-08-31', '2026-09-06', 'Semana 36', 40, 192500, 2, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values
  ('e4000000-0000-4000-8000-000000000061', 'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000060', 'e4000000-0000-4000-8000-000000000030',
   'Braulio Muñoz', 17, 4261.76, 72450, 72450,
   'e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000010',
   'e4000000-0000-4000-8000-000000000014'),
  ('e4000000-0000-4000-8000-000000000062', 'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000060', 'e4000000-0000-4000-8000-000000000031',
   'Vicente Díaz', 23, 5234.78, 120050, 120050,
   'e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000010',
   'e4000000-0000-4000-8000-000000000015');

create temp table pays_payroll_split on commit drop as
select
  public.save_bank_statement_import_v1(
    'pays-payroll:import-august', repeat('1', 64), repeat('b', 64),
    'e4000000-0000-4000-8000-000000000010',
    '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'source_row_id', 'braulio-36', 'ordinal', 1, 'booking_date', '2026-09-08',
      'operation_date', null, 'direction', 'debit', 'amount', 72450,
      'description', 'App-traspaso A: Braulio Munoz Internet',
      'normalized_description', 'app traspaso a braulio munoz internet',
      'counterparty_observed', 'Braulio Munoz Internet', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 10, 'source_line_end', 10,
      'fingerprint', repeat('f', 64)
    ))
  ) as august,
  public.save_bank_statement_import_v1(
    'pays-payroll:import-september', repeat('2', 64), repeat('b', 64),
    'e4000000-0000-4000-8000-000000000010',
    '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'source_row_id', 'vicente-36', 'ordinal', 1, 'booking_date', '2026-09-09',
      'operation_date', null, 'direction', 'debit', 'amount', 120050,
      'description', 'App-traspaso A: Vicente Diaz Internet',
      'normalized_description', 'app traspaso a vicente diaz internet',
      'counterparty_observed', 'Vicente Diaz Internet', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 10, 'source_line_end', 10,
      'fingerprint', repeat('0', 64)
    ))
  ) as september;

create temp table pays_payroll_split_receipts on commit drop as
select
  public.apply_bank_reconciliation_actions_v3(
    (split.august->>'import_id')::uuid, (split.august->>'revision')::bigint,
    'pays-payroll:apply-august',
    jsonb_build_array(jsonb_build_object(
      'row_id', (select id from public.bank_statement_rows
                  where import_id = (split.august->>'import_id')::uuid),
      'action', 'pay_payroll',
      'payroll', jsonb_build_object(
        'voucher_id', 'e4000000-0000-4000-8000-000000000060',
        'voucher_line_id', 'e4000000-0000-4000-8000-000000000061',
        'expected_amount', 72450, 'amount', 72450,
        'payment_method_id', 'e4000000-0000-4000-8000-000000000020',
        'confirm_draft', true
      )
    ))
  ) as august
from pays_payroll_split split;

select is(
  (
    select (receipt->>'payroll_confirmed_week_count')::integer
    from (
      select public.apply_bank_reconciliation_actions_v3(
        (split.september->>'import_id')::uuid,
        (split.september->>'revision')::bigint,
        'pays-payroll:apply-september',
        jsonb_build_array(jsonb_build_object(
          'row_id', (select id from public.bank_statement_rows
                      where import_id = (split.september->>'import_id')::uuid),
          'action', 'pay_payroll',
          'payroll', jsonb_build_object(
            'voucher_id', 'e4000000-0000-4000-8000-000000000060',
            'voucher_line_id', 'e4000000-0000-4000-8000-000000000062',
            'expected_amount', 120050, 'amount', 120050,
            'payment_method_id', 'e4000000-0000-4000-8000-000000000020',
            'confirm_draft', true
          )
        ))
      ) as receipt
      from pays_payroll_split split
    ) september
  ),
  0,
  'a week the other statement already confirmed is paid without confirming again'
);

select is(
  (
    select status
    from public.payroll_vouchers
    where id = 'e4000000-0000-4000-8000-000000000060'
  ),
  'paid',
  'and the split week ends paid'
);

-- A week paid partly with a cash advance during it: the transfer is the
-- balance minus the advance, and the advance is applied in the same apply.
insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e4000000-0000-4000-8000-000000000016', 'e4000000-0000-4000-8000-000000000001',
   '1101', 'Caja', 'asset', 'currentAsset');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e4000000-0000-4000-8000-000000000021', 'e4000000-0000-4000-8000-000000000001',
   'cash', 'Efectivo', 'e4000000-0000-4000-8000-000000000016', 'no_tax');
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  'e4000000-0000-4000-8000-000000000070', 'e4000000-0000-4000-8000-000000000001',
  'NOM-00035', '2026-08-10', '2026-08-16', 'Semana 33', 11.6, 40600, 1, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values
  ('e4000000-0000-4000-8000-000000000071', 'e4000000-0000-4000-8000-000000000001',
   'e4000000-0000-4000-8000-000000000070', 'e4000000-0000-4000-8000-000000000030',
   'Braulio Muñoz', 11.6, 3500, 40600, 40600,
   'e4000000-0000-4000-8000-000000000020', 'e4000000-0000-4000-8000-000000000010',
   'e4000000-0000-4000-8000-000000000014');

create temp table pays_payroll_advance on commit drop as
select public.register_employee_advance_v3(
  'pays-payroll:advance-braulio', 'e4000000-0000-4000-8000-000000000030', 30000,
  'e4000000-0000-4000-8000-000000000021', 'e4000000-0000-4000-8000-000000000016',
  '2026-08-12 15:00:00+00', null, null, 'requested_advance',
  'Pidió efectivo durante la semana', null, null, null
) as receipt;

select is(
  (
    select jsonb_build_object(
      'available', (advance->>'available')::numeric,
      'paid_on', advance->>'paid_on',
      'method', advance->>'payment_method_code'
    )
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v2(
        'e4000000-0000-4000-8000-000000000010', '2026-08-10', '2026-08-31'
      )->'open_advances'
    ) advance
    where advance->>'advance_id' = (select receipt->>'advance_id' from pays_payroll_advance)
  ),
  '{"available": 30000, "paid_on": "2026-08-12", "method": "cash"}'::jsonb,
  'the catalog lists the open advance Nómina will discount'
);

create temp table pays_payroll_advance_import on commit drop as
select public.save_bank_statement_import_v1(
  'pays-payroll:import-advance', repeat('3', 64), repeat('b', 64),
  'e4000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'source_row_id', 'braulio-33', 'ordinal', 1, 'booking_date', '2026-08-18',
    'operation_date', null, 'direction', 'debit', 'amount', 10600,
    'description', 'App-traspaso A: Braulio Munoz Internet',
    'normalized_description', 'app traspaso a braulio munoz internet',
    'counterparty_observed', 'Braulio Munoz Internet', 'document_number', null,
    'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', 10, 'source_line_end', 10,
    'fingerprint', repeat('9', 64)
  ))
) as receipt;

create temp table pays_payroll_advance_action on commit drop as
select
  (imported.receipt->>'import_id')::uuid as import_id,
  (imported.receipt->>'revision')::bigint as revision,
  jsonb_build_array(jsonb_build_object(
    'row_id', (select id from public.bank_statement_rows
                where import_id = (imported.receipt->>'import_id')::uuid),
    'action', 'pay_payroll',
    'payroll', jsonb_build_object(
      'voucher_id', 'e4000000-0000-4000-8000-000000000070',
      'voucher_line_id', 'e4000000-0000-4000-8000-000000000071',
      'expected_amount', 40600, 'amount', 10600,
      'payment_method_id', 'e4000000-0000-4000-8000-000000000020',
      'confirm_draft', true,
      'advances', jsonb_build_array(jsonb_build_object(
        'advance_id', (select receipt->>'advance_id' from pays_payroll_advance),
        'amount', 30000
      ))
    )
  )) as actions
from pays_payroll_advance_import imported;

select throws_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from pays_payroll_advance_action),
    (select revision from pays_payroll_advance_action),
    'pays-payroll:advance-foreign',
    jsonb_set(
      (select actions from pays_payroll_advance_action),
      '{0,payroll,advances,0,advance_id}',
      '"e4000000-0000-4000-8000-0000000009ff"'::jsonb
    )
  ),
  '40001',
  'bank_reconciliation_payroll_advance_invalid',
  'an advance that is not this worker''s open one is refused'
);

select is(
  (
    select (receipt->>'payroll_payment_count')::integer
    from (
      select public.apply_bank_reconciliation_actions_v3(
        (select import_id from pays_payroll_advance_action),
        (select revision from pays_payroll_advance_action),
        'pays-payroll:advance-apply',
        (select actions from pays_payroll_advance_action)
      ) as receipt
    ) applied
  ),
  1,
  'the transfer pays the week together with the advance'
);

select is(
  (
    select jsonb_build_object(
      'week', voucher.status,
      'advance', advance.status,
      'applied', advance.amount_applied,
      'paid_by_bank', (
        select sum(payment.amount)
        from public.expense_payments payment
        join public.payroll_voucher_lines line
          on line.tenant_id = payment.tenant_id
         and line.expense_id = payment.expense_id
        where line.id = 'e4000000-0000-4000-8000-000000000071'
      )
    )
    from public.payroll_vouchers voucher
    cross join public.employee_advances advance
    where voucher.id = 'e4000000-0000-4000-8000-000000000070'
      and advance.id = (select (receipt->>'advance_id')::uuid from pays_payroll_advance)
  ),
  '{"week": "paid", "advance": "applied", "applied": 30000, "paid_by_bank": 10600}'::jsonb,
  'Nómina ends the week paid: $10.600 from the bank and the $30.000 advance'
);

select * from finish();
rollback;
