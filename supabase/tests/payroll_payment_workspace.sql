begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';

select plan(22);

select ok(
  to_regclass('public.payroll_payment_workspaces') is not null
  and to_regclass('public.payroll_payment_workspace_legs') is not null
  and to_regclass('public.payroll_payment_statement_allocations') is not null
  and has_function_privilege(
    'authenticated',
    'public.apply_payroll_payment_workspace_v1(uuid,text,bigint,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_payroll_payment_workspace_v1(uuid,text,bigint,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.guard_payroll_workspace_additional_expense_salary_branch()',
    'EXECUTE'
  )
  and exists (
    select 1
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    where namespace.nspname = 'public'
      and proc.proname =
        'guard_payroll_workspace_additional_expense_salary_branch'
      and proc.prosecdef is true
      and proc.proconfig @>
        array['search_path=pg_catalog, public']::text[]
  )
  and exists (
    select 1
    from pg_trigger workspace_trigger
    where workspace_trigger.tgrelid =
      'public.payroll_payment_workspace_legs'::regclass
      and workspace_trigger.tgname =
        'trg_guard_payroll_workspace_additional_expense_salary_branch'
      and workspace_trigger.tgenabled <> 'D'
  ),
  'the canonical workspace owner and sealed salary-branch trigger exist'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.payroll_payment_workspaces', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.payroll_payment_workspace_legs', 'UPDATE'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_payment_statement_allocations',
    'DELETE'
  ),
  'client and service roles cannot forge workspace or bank evidence rows'
);

insert into public.tenants (id, shop_name, timezone)
values (
  '8a111111-1111-4111-8111-111111111111',
  'Payroll Workspace Test',
  'America/Santiago'
);

delete from public.payment_methods
where tenant_id = '8a111111-1111-4111-8111-111111111111';
delete from public.accounts
where tenant_id = '8a111111-1111-4111-8111-111111111111';

insert into public.accounts (id, tenant_id, code, name, type, category)
values
  (
    '8a222222-2222-4222-8222-222222222221',
    '8a111111-1111-4111-8111-111111111111',
    '1102', 'Banco', 'asset', 'currentAsset'
  ),
  (
    '8a222222-2222-4222-8222-222222222222',
    '8a111111-1111-4111-8111-111111111111',
    '1101', 'Caja', 'asset', 'currentAsset'
  ),
  (
    '8a222222-2222-4222-8222-222222222223',
    '8a111111-1111-4111-8111-111111111111',
    '2105', 'Cuentas por Pagar - Gastos',
    'liability', 'currentLiability'
  ),
  (
    '8a222222-2222-4222-8222-222222222224',
    '8a111111-1111-4111-8111-111111111111',
    '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'
  ),
  (
    '8a222222-2222-4222-8222-222222222225',
    '8a111111-1111-4111-8111-111111111111',
    '610101', 'Sueldo Fernando', 'expense', 'operatingExpense'
  ),
  (
    '8a222222-2222-4222-8222-222222222226',
    '8a111111-1111-4111-8111-111111111111',
    '610102', 'Sueldo Vicente', 'expense', 'operatingExpense'
  ),
  (
    '8a222222-2222-4222-8222-222222222227',
    '8a111111-1111-4111-8111-111111111111',
    '620401', 'Insumos de taller', 'expense', 'operatingExpense'
  );

insert into public.accounts (
  id, tenant_id, code, name, type, category, parent_id
) values
  (
    '8a222222-2222-4222-8222-222222222228',
    '8a111111-1111-4111-8111-111111111111',
    '6101', 'Gastos de personal', 'expense', 'operatingExpense', null
  ),
  (
    '8a222222-2222-4222-8222-222222222229',
    '8a111111-1111-4111-8111-111111111111',
    '61010101', 'Detalle sueldo Fernando', 'expense', 'operatingExpense',
    '8a222222-2222-4222-8222-222222222225'
  ),
  (
    '8a222222-2222-4222-8222-222222222230',
    '8a111111-1111-4111-8111-111111111111',
    '610199', 'Cuenta salarial futura', 'expense', 'operatingExpense',
    '8a222222-2222-4222-8222-222222222228'
  );

update public.accounts
set parent_id = '8a222222-2222-4222-8222-222222222228'
where id in (
  '8a222222-2222-4222-8222-222222222225',
  '8a222222-2222-4222-8222-222222222226'
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
values
  (
    '8a333333-3333-4333-8333-333333333331',
    '8a111111-1111-4111-8111-111111111111',
    'transfer', 'Transferencia',
    '8a222222-2222-4222-8222-222222222221', 'no_tax'
  ),
  (
    '8a333333-3333-4333-8333-333333333332',
    '8a111111-1111-4111-8111-111111111111',
    'cash', 'Efectivo',
    '8a222222-2222-4222-8222-222222222222', 'no_tax'
  );

set local session_replication_role = replica;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '8a000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated',
  'workspace-manager@example.invalid', '', now(),
  '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  '8a000000-0000-4000-8000-000000000002',
  '8a000000-0000-4000-8000-000000000001',
  '8a111111-1111-4111-8111-111111111111',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '8a000000-0000-4000-8000-000000000001',
  true
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
) values
  (
    '8a444444-4444-4444-8444-444444444441',
    '8a111111-1111-4111-8111-111111111111',
    'PWS-001', 'Fernando', 'Tapia', 'Mecánico',
    '8a222222-2222-4222-8222-222222222225',
    '8a333333-3333-4333-8333-333333333331'
  ),
  (
    '8a444444-4444-4444-8444-444444444442',
    '8a111111-1111-4111-8111-111111111111',
    'PWS-002', 'Vicente', 'Díaz', 'Mecánico',
    '8a222222-2222-4222-8222-222222222226',
    '8a333333-3333-4333-8333-333333333331'
  );

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
    '8a555555-5555-4555-8555-555555555551',
    '8a111111-1111-4111-8111-111111111111',
    'PWS-FERNANDO', '2026-07-27', '2026-08-02', 'Semana Fernando',
    29, 145000, 2, 'draft'
  );

insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values
  (
    '8a777777-7777-4777-8777-777777777771',
    '8a111111-1111-4111-8111-111111111111',
    '8a555555-5555-4555-8555-555555555551',
    '8a444444-4444-4444-8444-444444444441',
    'Fernando Tapia', 25, 5000, 125000, 125000,
    '8a333333-3333-4333-8333-333333333331',
    '8a222222-2222-4222-8222-222222222221',
    '8a222222-2222-4222-8222-222222222225'
  ),
  (
    '8a777777-7777-4777-8777-777777777772',
    '8a111111-1111-4111-8111-111111111111',
    '8a555555-5555-4555-8555-555555555551',
    '8a444444-4444-4444-8444-444444444442',
    'Vicente Díaz', 4, 5000, 20000, 20000,
    '8a333333-3333-4333-8333-333333333331',
    '8a222222-2222-4222-8222-222222222221',
    '8a222222-2222-4222-8222-222222222226'
  );

select public.ensure_payroll_line_expense(
  '8a777777-7777-4777-8777-777777777771'
);
select public.ensure_payroll_line_expense(
  '8a777777-7777-4777-8777-777777777772'
);

set local session_replication_role = replica;
update public.payroll_vouchers
set status = 'confirmed'
where id = '8a555555-5555-4555-8555-555555555551';
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"8a000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '8a000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select set_config(
  'test.workspace.payload',
  jsonb_build_object(
    'statement', jsonb_build_object(
      'filename', 'cartola agosto.pdf',
      'file_digest', repeat('a', 64),
      'statement_start', '2026-08-01',
      'statement_end', '2026-08-11',
      'account_id', '8a222222-2222-4222-8222-222222222221'
    ),
    'rows', jsonb_build_array(
      jsonb_build_object(
        'source_row_id', 'ocr-row-1',
        'ordinal', 1,
        'transaction_date', '2026-08-10',
        'direction', 'debit',
        'amount', 85000,
        'description', 'Transferencia a Fernando Tapia'
      ),
      jsonb_build_object(
        'source_row_id', 'ocr-row-2',
        'ordinal', 2,
        'transaction_date', '2026-08-11',
        'direction', 'debit',
        'amount', 20000,
        'description', 'Transferencia a Vicente Diaz'
      ),
      jsonb_build_object(
        'source_row_id', 'ocr-row-3',
        'ordinal', 3,
        'transaction_date', '2026-08-11',
        'direction', 'debit',
        'amount', 6000,
        'description', 'Transferencia adicional persistida'
      )
    ),
    'salary_targets', jsonb_build_array(
      jsonb_build_object(
        'target_id', '8a888888-8888-4888-8888-888888888881',
        'voucher_id', '8a555555-5555-4555-8555-555555555551',
        'expected_reconciliation_version', (
          select voucher.reconciliation_version
          from public.payroll_vouchers voucher
          where voucher.id = '8a555555-5555-4555-8555-555555555551'
        ),
        'legs', jsonb_build_array(
          jsonb_build_object(
            'leg_id', '8a999999-9999-4999-8999-999999999991',
            'voucher_line_id', '8a777777-7777-4777-8777-777777777771',
            'kind', 'payment', 'funding_kind', 'bank', 'amount', 75000,
            'payment_method_id', '8a333333-3333-4333-8333-333333333331',
            'payment_account_id', '8a222222-2222-4222-8222-222222222221',
            'payment_date', '2026-08-10 15:00:00+00',
            'reference', 'BANK-SALARY-75000',
            'evidence', jsonb_build_array(jsonb_build_object(
              'source_row_id', 'ocr-row-1', 'amount', 75000
            ))
          ),
          jsonb_build_object(
            'leg_id', '8a999999-9999-4999-8999-999999999992',
            'voucher_line_id', '8a777777-7777-4777-8777-777777777771',
            'kind', 'payment', 'funding_kind', 'cash', 'amount', 50000,
            'payment_method_id', '8a333333-3333-4333-8333-333333333332',
            'payment_account_id', '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:05:00+00',
            'reference', 'CASH-SALARY-50000'
          )
        )
      ),
      jsonb_build_object(
        'target_id', '8a888888-8888-4888-8888-888888888882',
        'voucher_id', '8a555555-5555-4555-8555-555555555551',
        'expected_reconciliation_version', (
          select voucher.reconciliation_version
          from public.payroll_vouchers voucher
          where voucher.id = '8a555555-5555-4555-8555-555555555551'
        ),
        'legs', jsonb_build_array(jsonb_build_object(
          'leg_id', '8a999999-9999-4999-8999-999999999993',
          'voucher_line_id', '8a777777-7777-4777-8777-777777777772',
          'kind', 'payment', 'funding_kind', 'bank', 'amount', 20000,
          'payment_method_id', '8a333333-3333-4333-8333-333333333331',
          'payment_account_id', '8a222222-2222-4222-8222-222222222221',
          'payment_date', '2026-08-11 15:00:00+00',
          'reference', 'BANK-SALARY-20000',
          'evidence', jsonb_build_array(jsonb_build_object(
            'source_row_id', 'ocr-row-2', 'amount', 20000
          ))
        ))
      )
    ),
    'additional_concepts', jsonb_build_array(jsonb_build_object(
      'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'beneficiary_employee_id', '8a444444-4444-4444-8444-444444444441',
      'expense_account_id', '8a222222-2222-4222-8222-222222222227',
      'amount', 15000,
      'description', 'Reintegro cajas plasticas para el taller',
      'payment_legs', jsonb_build_array(
        jsonb_build_object(
          'leg_id', '8adddddd-dddd-4ddd-8ddd-ddddddddddd1',
          'amount', 10000,
          'funding_kind', 'bank',
          'payment_method_id', '8a333333-3333-4333-8333-333333333331',
          'payment_account_id', '8a222222-2222-4222-8222-222222222221',
          'payment_date', '2026-08-10 15:00:00+00',
          'reference', 'BANK-REIMBURSEMENT-10000',
          'evidence', jsonb_build_array(jsonb_build_object(
            'source_row_id', 'ocr-row-1', 'amount', 10000
          ))
        ),
        jsonb_build_object(
          'leg_id', '8adddddd-dddd-4ddd-8ddd-ddddddddddd2',
          'amount', 5000,
          'funding_kind', 'cash',
          'payment_method_id', '8a333333-3333-4333-8333-333333333332',
          'payment_account_id', '8a222222-2222-4222-8222-222222222222',
          'payment_date', '2026-08-10 15:05:00+00',
          'reference', 'CASH-REIMBURSEMENT-5000'
        )
      )
    ))
  )::text,
  true
);

select set_config(
  'test.workspace.receipt',
  public.apply_payroll_payment_workspace_v1(
    '8acccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'workspace-apply-batch-0001',
    0,
    current_setting('test.workspace.payload')::jsonb
  )::text,
  true
);

select ok(
  current_setting('test.workspace.receipt')::jsonb->>'status' = 'applied'
  and (
    current_setting('test.workspace.receipt')::jsonb->>'version'
  )::bigint = 1
  and jsonb_array_length(
    current_setting('test.workspace.receipt')::jsonb->'targets'
  ) = 2
  and (
    current_setting('test.workspace.receipt')::jsonb
      ->'targets'->0->>'voucher_id'
  ) = (
    current_setting('test.workspace.receipt')::jsonb
      ->'targets'->1->>'voucher_id'
  )
  and (
    current_setting('test.workspace.receipt')::jsonb
      ->'targets'->0->>'reconciliation_version'
  )::bigint < (
    current_setting('test.workspace.receipt')::jsonb
      ->'targets'->1->>'reconciliation_version'
  )::bigint
  and jsonb_array_length(
    current_setting('test.workspace.receipt')::jsonb->'additional_concepts'
  ) = 1
  and jsonb_array_length(
    current_setting('test.workspace.receipt')::jsonb
      ->'additional_concepts'->0->'payment_legs'
  ) = 2
  and jsonb_array_length(
    current_setting('test.workspace.receipt')::jsonb->'statement_allocations'
  ) = 3,
  'one batch command returns target receipts, result IDs, and the new workspace version'
);

select ok(
  exists (
    select 1 from public.payroll_statement_imports statement_import
    where statement_import.id = (
      current_setting('test.workspace.receipt')::jsonb
        ->'statement'->>'import_id'
    )::uuid
      and statement_import.status = 'review'
      and statement_import.row_count = 3
  )
  and not exists (
    select 1 from public.payroll_statement_decisions decision
    where decision.import_id = (
      current_setting('test.workspace.receipt')::jsonb
        ->'statement'->>'import_id'
    )::uuid
  ),
  'inline OCR evidence is imported at handoff without forcing full-statement decisions'
);

select ok(
  (
    select count(*) = 2 and sum(allocation.allocated_amount) = 85000
    from public.payroll_payment_statement_allocations allocation
    join public.payroll_statement_rows statement_row
      on statement_row.id = allocation.statement_row_id
    where statement_row.description_observed =
      'Transferencia a Fernando Tapia'
  ),
  'one bank movement is allocated one-to-many across salary and reimbursement'
);

select ok(
  (
    select status = 'paid'
    from public.payroll_vouchers
    where id = '8a555555-5555-4555-8555-555555555551'
  )
  and (
    select count(*) = 2 and sum(payment.amount) = 125000
    from public.expense_payments payment
    where payment.expense_id = (
      select voucher_line.expense_id
      from public.payroll_voucher_lines voucher_line
      where voucher_line.id = '8a777777-7777-4777-8777-777777777771'
    )
  )
  and (
    select count(*) = 1 and sum(payment.amount) = 20000
    from public.expense_payments payment
    where payment.expense_id = (
      select voucher_line.expense_id
      from public.payroll_voucher_lines voucher_line
      where voucher_line.id = '8a777777-7777-4777-8777-777777777772'
    )
  ),
  'CAS threads across two worker targets in one voucher and multiple legs'
);

select ok(
  not exists (
    select 1
    from public.payroll_payment_statement_allocations allocation
    join public.payroll_payment_workspace_legs leg
      on leg.id = allocation.workspace_leg_id
    where leg.funding_kind <> 'bank'
  )
  and exists (
    select 1 from public.payroll_payment_workspace_legs leg
    where leg.id = '8a999999-9999-4999-8999-999999999992'
      and leg.funding_kind = 'cash'
      and leg.result_expense_payment_id is not null
  ),
  'cash remains auditable without fabricated bank evidence'
);

select ok(
  exists (
    select 1
    from public.payroll_payment_workspace_legs leg
    join public.expense_lines expense_line
      on expense_line.expense_id = leg.result_expense_id
    join public.expenses expense
      on expense.id = leg.result_expense_id
    where leg.concept_id = '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
      and leg.leg_type = 'additional_expense'
      and expense_line.account_id =
        '8a222222-2222-4222-8222-222222222227'
      and expense.payment_status = 'paid'
      and expense.total_amount = 15000
      and expense.amount_paid = 15000
      and expense.balance = 0
      and (
        select count(*) = 2 and sum(payment.amount) = 15000
        from public.expense_payments payment
        where payment.expense_id = leg.result_expense_id
      )
  ),
  'the reimbursement becomes its own fully paid expense on a non-salary account'
);

select ok(
  exists (
    select 1
    from public.payroll_payment_workspace_legs leg
    join public.journal_entries entry
      on entry.source_document_id = leg.result_expense_payment_id
      or entry.source_reference = leg.result_expense_payment_id::text
    join public.journal_lines line on line.entry_id = entry.id
    where leg.id = '8adddddd-dddd-4ddd-8ddd-ddddddddddd1'
      and entry.source_module = 'expense_payments'
      and line.account_code = '2105'
      and line.debit_amount = 10000
  )
  and exists (
    select 1
    from public.payroll_payment_workspace_legs leg
    join public.journal_entries entry
      on entry.source_document_id = leg.result_expense_payment_id
      or entry.source_reference = leg.result_expense_payment_id::text
    join public.journal_lines line on line.entry_id = entry.id
    where leg.id = '8a999999-9999-4999-8999-999999999991'
      and entry.source_module = 'expense_payments'
      and line.account_code = '2106'
      and line.debit_amount = 75000
  ),
  'salary and reimbursement clear different liabilities with separate journals'
);

select ok(
  not exists (
    select 1
    from public.journal_entries entry
    left join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '8a111111-1111-4111-8111-111111111111'
    group by entry.id, entry.total_debit, entry.total_credit
    having sum(line.debit_amount) <> sum(line.credit_amount)
       or entry.total_debit <> sum(line.debit_amount)
       or entry.total_credit <> sum(line.credit_amount)
  ),
  'all workspace-created accrual and payment journals remain balanced'
);

select throws_ok(
  $$
    update public.expense_payments payment
    set amount = payment.amount
    where payment.id = (
      select leg.result_expense_payment_id
      from public.payroll_payment_workspace_legs leg
      where leg.id = '8adddddd-dddd-4ddd-8ddd-ddddddddddd1'
    )
  $$,
  '55000',
  'payroll_workspace_result_is_immutable',
  'an applied additional-concept payment cannot diverge from its evidence'
);

select throws_ok(
  $$
    update public.expense_lines expense_line
    set description = expense_line.description
    where expense_line.expense_id = (
      select leg.result_expense_id
      from public.payroll_payment_workspace_legs leg
      where leg.id = '8adddddd-dddd-4ddd-8ddd-ddddddddddd1'
    )
  $$,
  '55000',
  'payroll_workspace_result_is_immutable',
  'the additional-concept accounting line is immutable after apply'
);

select set_config(
  'test.workspace.replay',
  public.apply_payroll_payment_workspace_v1(
    '8acccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'workspace-apply-batch-0001',
    0,
    current_setting('test.workspace.payload')::jsonb
  )::text,
  true
);

select ok(
  (
    current_setting('test.workspace.replay')::jsonb->>'replayed'
  )::boolean
  and (
    select count(*) = 5
    from public.payroll_payment_workspace_legs
    where workspace_id = '8acccccc-cccc-4ccc-8ccc-ccccccccccc1'
  )
  and (
    select count(*) = 3
    from public.payroll_payment_statement_allocations
    where workspace_id = '8acccccc-cccc-4ccc-8ccc-ccccccccccc1'
  ),
  'an acknowledgement retry returns the stored receipt without duplicate movements'
);

select set_config(
  'test.workspace.persisted_receipt',
  public.apply_payroll_payment_workspace_v1(
    '8acccccc-cccc-4ccc-8ccc-ccccccccccc2',
    'workspace-persisted-row-0002',
    0,
    jsonb_build_object(
      'salary_targets', '[]'::jsonb,
      'additional_concepts', jsonb_build_array(jsonb_build_object(
        'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
        'expense_account_id',
          '8a222222-2222-4222-8222-222222222227',
        'amount', 6000,
        'description', 'Concepto desde evidencia ya persistida',
        'payment_legs', jsonb_build_array(jsonb_build_object(
          'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
          'amount', 6000,
          'funding_kind', 'bank',
          'payment_method_id',
            '8a333333-3333-4333-8333-333333333331',
          'payment_account_id',
            '8a222222-2222-4222-8222-222222222221',
          'payment_date', '2026-08-11 16:00:00+00',
          'evidence', jsonb_build_array(jsonb_build_object(
            'import_id', (
              select statement_row.import_id
              from public.payroll_statement_rows statement_row
              where statement_row.description_observed =
                'Transferencia adicional persistida'
            ),
            'row_id', (
              select statement_row.id
              from public.payroll_statement_rows statement_row
              where statement_row.description_observed =
                'Transferencia adicional persistida'
            ),
            'amount', 6000
          ))
        ))
      ))
    )
  )::text,
  true
);

select ok(
  current_setting('test.workspace.persisted_receipt')::jsonb->>'status'
    = 'applied'
  and jsonb_array_length(
    current_setting('test.workspace.persisted_receipt')::jsonb
      ->'statement_allocations'
  ) = 1
  and (
    select count(*) = 1 and sum(allocation.allocated_amount) = 6000
    from public.payroll_payment_statement_allocations allocation
    join public.payroll_statement_rows statement_row
      on statement_row.id = allocation.statement_row_id
    where statement_row.description_observed =
      'Transferencia adicional persistida'
  ),
  'the same owner accepts a previously persisted import_id and row_id'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc6',
      'workspace-method-mismatch-0006',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222227',
          'amount', 1000,
          'description', 'Método efectivo disfrazado de banco',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee6',
            'amount', 1000,
            'funding_kind', 'bank',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_funding_method_mismatch',
  'a cash payment method cannot be disguised as bank funding'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc3',
      'workspace-overallocate-0002',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222227',
          'amount', 1,
          'description', 'Asignación duplicada',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee3',
            'amount', 1,
            'funding_kind', 'bank',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333331',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222221',
            'payment_date', '2026-08-10 15:00:00+00',
            'evidence', jsonb_build_array(jsonb_build_object(
              'import_id', (
                select statement_row.import_id
                from public.payroll_statement_rows statement_row
                where statement_row.description_observed =
                  'Transferencia a Fernando Tapia'
              ),
              'row_id', (
                select statement_row.id
                from public.payroll_statement_rows statement_row
                where statement_row.description_observed =
                  'Transferencia a Fernando Tapia'
              ),
              'amount', 1
            ))
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_statement_row_overallocated',
  'a bank row cannot be allocated beyond its observed amount'
);

select ok(
  not exists (
    select 1 from public.payroll_payment_workspaces
    where id = '8acccccc-cccc-4ccc-8ccc-ccccccccccc3'
  ),
  'a rejected over-allocation leaves no partial workspace or expense'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'workspace-salary-concept-0003',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222225',
          'amount', 1000,
          'description', 'No debe mezclarse con salario',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee4',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '42501',
  'payroll_workspace_account_or_employee_invalid',
  'an additional concept can never post to a salary expense account'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc7',
      'workspace-salary-parent-0007',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222228',
          'amount', 1000,
          'description', 'No debe usar el padre de sueldos',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee7',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_salary_account_branch_forbidden',
  'an additional concept cannot post to an ancestor of a salary account'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc8',
      'workspace-salary-descendant-0008',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb8',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222229',
          'amount', 1000,
          'description', 'No debe usar un descendiente de sueldo',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee8',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_salary_account_branch_forbidden',
  'an additional concept cannot post below a salary account'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc9',
      'workspace-salary-sibling-0009',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb9',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222230',
          'amount', 1000,
          'description', 'No debe usar un sibling salarial sin referencias',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee9',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_salary_account_branch_forbidden',
  'an unreferenced sibling in the salary branch remains forbidden'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v1(
      '8acccccc-cccc-4ccc-8ccc-ccccccccccc5',
      'workspace-stale-create-0004',
      1,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '8abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
          'expense_account_id',
            '8a222222-2222-4222-8222-222222222227',
          'amount', 1000,
          'description', 'Versión obsoleta',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '8aeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '8a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '8a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '40001',
  'payroll_workspace_version_conflict',
  'new workspaces require the zero CAS version'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
