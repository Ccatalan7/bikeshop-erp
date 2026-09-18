begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_bank_reconciliation_candidates_v2(uuid,date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_bank_reconciliation_candidates_v2(uuid,date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.bank_reconciliation_candidate_identity(uuid,text,uuid)',
    'EXECUTE'
  ),
  'accountants call the catalog; the identity helper stays internal'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone) values
  ('e3000000-0000-4000-8000-000000000001', 'Candidates v2', 'America/Santiago'),
  ('e3000000-0000-4000-8000-000000000901', 'Otro taller', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e3000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'candidates-v2@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e3000000-0000-4000-8000-000000000003',
  'e3000000-0000-4000-8000-000000000002',
  'e3000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

insert into public.accounts (id, tenant_id, code, name, type, category, is_active) values
  ('e3000000-0000-4000-8000-000000000010', 'e3000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset', true),
  ('e3000000-0000-4000-8000-000000000011', 'e3000000-0000-4000-8000-000000000001',
   '6201', 'Arriendo de Locales', 'expense', 'operatingExpense', true),
  ('e3000000-0000-4000-8000-000000000012', 'e3000000-0000-4000-8000-000000000001',
   '6101-03', 'Salario - Vicente Díaz', 'expense', 'operatingExpense', true),
  ('e3000000-0000-4000-8000-000000000013', 'e3000000-0000-4000-8000-000000000001',
   '1130', 'Cuentas por Cobrar', 'asset', 'currentAsset', true);

insert into public.payment_methods (id, tenant_id, code, name, account_id, is_active) values
  ('e3000000-0000-4000-8000-000000000020', 'e3000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e3000000-0000-4000-8000-000000000010', true);

insert into public.customers (id, tenant_id, name) values
  ('e3000000-0000-4000-8000-000000000030', 'e3000000-0000-4000-8000-000000000001',
   'Carolina Bravo');

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment, date
) values
  ('e3000000-0000-4000-8000-000000000031', 'e3000000-0000-4000-8000-000000000001',
   'FV-788', 'e3000000-0000-4000-8000-000000000030', 'Carolina Bravo', 'paid', 'pos',
   32000, 32000, 0, 32000, 32000, 0, 'no_tax', '2026-06-27 15:00:00+00'),
  ('e3000000-0000-4000-8000-000000000032', 'e3000000-0000-4000-8000-000000000001',
   'FV-790', null, 'Marcela Landaeta', 'sent', 'pos',
   34000, 34000, 0, 34000, 0, 34000, 'no_tax', '2026-07-06 15:00:00+00');

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, idempotency_key, amount, date
) values (
  'e3000000-0000-4000-8000-000000000033', 'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000031', 'e3000000-0000-4000-8000-000000000020',
  'candidates-v2:sale', 32000, '2026-06-27 15:00:00+00'
);

-- The payment's own journal: v1 offered it as a second, identical candidate.
insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type, source_module,
  source_reference, status, total_debit, total_credit
) values (
  'e3000000-0000-4000-8000-000000000034', 'e3000000-0000-4000-8000-000000000001',
  'AC-788', '2026-06-27 15:00:00+00', 'Pago factura FV-788 - Transferencia',
  'automatic', 'sales_payments', 'e3000000-0000-4000-8000-000000000033',
  'posted', 32000, 32000
);
insert into public.journal_lines (
  tenant_id, entry_id, account_id, account_code, account_name, debit_amount, credit_amount
) values
  ('e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000034',
   'e3000000-0000-4000-8000-000000000010', '1110', 'Banco de Chile', 32000, 0),
  ('e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000034',
   'e3000000-0000-4000-8000-000000000013', '1130', 'Cuentas por Cobrar', 0, 32000);

insert into public.suppliers (
  id, tenant_id, name, legal_name, rut, aliases, is_active
) values (
  'e3000000-0000-4000-8000-000000000040', 'e3000000-0000-4000-8000-000000000001',
  'MKR Imports', 'Mauricio Kishinevsky Rosental S.A.', '96.623.280-3',
  array['MKR'], true
);

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name, status, total, balance, date
) values (
  'e3000000-0000-4000-8000-000000000041', 'e3000000-0000-4000-8000-000000000001',
  '208049', 'e3000000-0000-4000-8000-000000000040', 'MKR Imports', 'received',
  62178, 0, '2026-06-30 12:00:00+00'
);

insert into public.purchase_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, date
) values (
  'e3000000-0000-4000-8000-000000000042', 'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000041', 'e3000000-0000-4000-8000-000000000020',
  62178, '2026-06-30 12:00:00+00'
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title, status,
  salary_account_id
) values (
  'e3000000-0000-4000-8000-000000000050', 'e3000000-0000-4000-8000-000000000001',
  'E-1', 'Vicente', 'Díaz', 'Mecánico', 'active',
  'e3000000-0000-4000-8000-000000000012'
);

insert into public.payroll_beneficiary_aliases (
  tenant_id, employee_id, alias, normalized_alias, created_by
) values (
  'e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000050',
  'Vicente Diaz Frias', 'vicente diaz frias',
  'e3000000-0000-4000-8000-000000000002'
);

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label, status
) values
  ('e3000000-0000-4000-8000-000000000051', 'e3000000-0000-4000-8000-000000000001',
   'NOM-00030', '2026-07-06', '2026-07-12', 'Semana 28', 'paid'),
  ('e3000000-0000-4000-8000-000000000052', 'e3000000-0000-4000-8000-000000000001',
   'NOM-00037', '2026-08-24', '2026-08-30', 'Semana 35', 'draft');

insert into public.expenses (
  id, tenant_id, expense_number, issue_date, total_amount, reference, notes
) values (
  'e3000000-0000-4000-8000-000000000053', 'e3000000-0000-4000-8000-000000000001',
  'GTO-00157', '2026-07-12 12:00:00+00', 129500, 'NOM-00030',
  'Pago de salario: Vicente Díaz'
);

insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, total_amount,
  is_included, expense_id
) values
  ('e3000000-0000-4000-8000-000000000054', 'e3000000-0000-4000-8000-000000000001',
   'e3000000-0000-4000-8000-000000000051', 'e3000000-0000-4000-8000-000000000050',
   'Vicente Díaz', 129500, true, 'e3000000-0000-4000-8000-000000000053'),
  ('e3000000-0000-4000-8000-000000000055', 'e3000000-0000-4000-8000-000000000001',
   'e3000000-0000-4000-8000-000000000052', 'e3000000-0000-4000-8000-000000000050',
   'Vicente Díaz', 109900, true, null);

insert into public.expense_payments (
  id, tenant_id, expense_id, payment_method_id, amount, payment_date
) values (
  'e3000000-0000-4000-8000-000000000056', 'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000053', 'e3000000-0000-4000-8000-000000000020',
  129500, '2026-08-12 12:00:00+00'
);

-- Nómina already tied this salary payment to the 14 July bank transfer.
insert into public.payroll_statement_imports (
  id, tenant_id, file_sha256, account_fingerprint, erp_account_id, parser_name,
  parser_version, source_type, create_operation_key, create_payload_hash, created_by
) values (
  'e3000000-0000-4000-8000-000000000057', 'e3000000-0000-4000-8000-000000000001',
  repeat('a', 64), repeat('b', 64), 'e3000000-0000-4000-8000-000000000010',
  'banco_chile_statement', 'v1', 'pdf_text', 'candidates-v2:payroll-import',
  repeat('c', 64), 'e3000000-0000-4000-8000-000000000002'
);
insert into public.payroll_statement_rows (
  id, tenant_id, import_id, row_ordinal, transaction_date, direction, amount,
  beneficiary_observed, base_fingerprint, fingerprint
) values (
  'e3000000-0000-4000-8000-000000000058', 'e3000000-0000-4000-8000-000000000001',
  'e3000000-0000-4000-8000-000000000057', 1, '2026-07-14', 'debit', 135000,
  'Vicente Diaz Internet', repeat('d', 64), repeat('e', 64)
);
insert into public.payroll_payment_statement_allocations (
  tenant_id, workspace_id, workspace_leg_id, import_id, statement_row_id,
  row_fingerprint, observed_amount, allocated_amount, result_expense_payment_id,
  applied_by
) values (
  'e3000000-0000-4000-8000-000000000001', gen_random_uuid(), gen_random_uuid(),
  'e3000000-0000-4000-8000-000000000057', 'e3000000-0000-4000-8000-000000000058',
  repeat('e', 64), 135000, 129500, 'e3000000-0000-4000-8000-000000000056',
  'e3000000-0000-4000-8000-000000000002'
);

-- The monthly rent: a free-text payee whose account the next proposal reuses.
insert into public.expenses (
  id, tenant_id, expense_number, issue_date, total_amount, supplier_name,
  notes, payment_method_id
) values (
  'e3000000-0000-4000-8000-000000000060', 'e3000000-0000-4000-8000-000000000001',
  'GTO-00139', '2026-07-22 12:00:00+00', 499467, 'Darinka Lagomarsino',
  'Gasto Arriendo', 'e3000000-0000-4000-8000-000000000020'
);
insert into public.expense_lines (
  tenant_id, expense_id, account_id, account_code, account_name
) values (
  'e3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000060',
  'e3000000-0000-4000-8000-000000000011', '6201', 'Arriendo de Locales'
);

-- Another tenant's supplier must never leak into this catalog.
insert into public.suppliers (id, tenant_id, name, is_active) values (
  'e3000000-0000-4000-8000-000000000940', 'e3000000-0000-4000-8000-000000000901',
  'Proveedor ajeno', true
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e3000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e3000000-0000-4000-8000-000000000002', true
);

create temp table catalog_v2 on commit drop as
select public.get_bank_reconciliation_candidates_v2(
  'e3000000-0000-4000-8000-000000000010', '2026-06-01', '2026-09-30'
) as payload;

select is(
  (
    select count(*)
      from jsonb_array_elements(
        public.get_bank_reconciliation_candidates_v1(
          'e3000000-0000-4000-8000-000000000010', '2026-06-01', '2026-09-30'
        )->'candidates'
      ) candidate
     where candidate->>'target_kind' = 'journal_entry'
  ),
  1::bigint,
  'v1 still offers the sales payment journal as a second candidate'
);

select is(
  (
    select count(*)
      from catalog_v2, jsonb_array_elements(payload->'candidates') candidate
     where candidate->>'target_kind' = 'journal_entry'
  ),
  0::bigint,
  'v2 drops the journal that only mirrors a payment candidate'
);

select is(
  (
    select candidate->'counterparty_names'
      from catalog_v2, jsonb_array_elements(payload->'candidates') candidate
     where candidate->>'target_id' = 'e3000000-0000-4000-8000-000000000042'
  ),
  '["MKR", "MKR Imports", "Mauricio Kishinevsky Rosental S.A."]'::jsonb,
  'a supplier payment carries the legal name and aliases the bank shows'
);

select is(
  (
    select jsonb_build_object(
      'kind', candidate->>'counterparty_kind',
      'names', candidate->'counterparty_names',
      'evidence', candidate->'bank_evidence'
    )
      from catalog_v2, jsonb_array_elements(payload->'candidates') candidate
     where candidate->>'target_id' = 'e3000000-0000-4000-8000-000000000056'
  ),
  jsonb_build_object(
    'kind', 'employee',
    'names', '["Vicente Diaz Frias", "Vicente Díaz"]'::jsonb,
    'evidence', '[{"date": "2026-07-14", "amount": 135000.00, "beneficiary": "Vicente Diaz Internet"}]'::jsonb
  ),
  'a salary payment names the employee and keeps the bank row Nómina tied to it'
);

select is(
  (
    select jsonb_build_object(
      'voucher', line->>'voucher_number',
      'amount', (line->>'amount')::numeric,
      'names', line->'counterparty_names'
    )
      from catalog_v2, jsonb_array_elements(payload->'payroll_lines') line
  ),
  jsonb_build_object(
    'voucher', 'NOM-00037',
    'amount', 109900,
    'names', '["Vicente Diaz Frias", "Vicente Díaz"]'::jsonb
  ),
  'only the unpaid payroll line is offered as an expected payment'
);

select is(
  (
    select jsonb_agg(sale->>'invoice_number')
      from catalog_v2, jsonb_array_elements(payload->'open_sales') sale
  ),
  '["FV-790"]'::jsonb,
  'open sales keep only invoices with a balance'
);

select is(
  (
    select party->'usual'->0->>'account_id'
      from catalog_v2, jsonb_array_elements(payload->'parties') party
     where party->>'kind' = 'payee'
       and party->>'display_name' = 'Darinka Lagomarsino'
  ),
  'e3000000-0000-4000-8000-000000000011',
  'a recurring payee keeps the expense account it was booked to'
);

select is(
  (
    select count(*)
      from catalog_v2, jsonb_array_elements(payload->'parties') party
     where party->>'id' = 'e3000000-0000-4000-8000-000000000940'
  ),
  0::bigint,
  'another tenant never appears in the directory'
);

select throws_ok(
  $$select public.get_bank_reconciliation_candidates_v2(
      'e3000000-0000-4000-8000-000000000010', '2026-01-01', '2027-06-30'
    )$$,
  '22023',
  'bank_reconciliation_date_range_invalid',
  'v2 keeps the range guard owned by v1'
);

select * from finish();
rollback;
