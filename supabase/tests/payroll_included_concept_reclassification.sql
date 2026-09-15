begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';

select plan(22);

select ok(
  to_regclass(
    'public.payroll_payment_workspace_concept_dispositions'
  ) is not null
  and to_regclass(
    'public.payroll_payment_workspace_v2_operations'
  ) is not null
  and has_function_privilege(
    'authenticated',
    'public.apply_payroll_payment_workspace_v2(uuid,text,bigint,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_payroll_payment_workspace_v2(uuid,text,bigint,jsonb)',
    'EXECUTE'
  ),
  'the V2 disposition owner exists behind the payroll RPC ACL'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.payroll_payment_workspace_concept_dispositions',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_payment_workspace_v2_operations',
    'SELECT'
  )
  and not has_table_privilege(
    'service_role',
    'public.payroll_payment_workspace_concept_dispositions',
    'UPDATE'
  ),
  'clients and service role cannot forge disposition or idempotency evidence'
);

insert into public.tenants (id, shop_name, timezone)
values (
  '9a111111-1111-4111-8111-111111111111',
  'Included Payroll Concept Test',
  'America/Santiago'
);

delete from public.payment_methods
where tenant_id = '9a111111-1111-4111-8111-111111111111';
delete from public.accounts
where tenant_id = '9a111111-1111-4111-8111-111111111111';

insert into public.accounts (id, tenant_id, code, name, type, category)
values
  (
    '9a222222-2222-4222-8222-222222222221',
    '9a111111-1111-4111-8111-111111111111',
    '1102', 'Banco', 'asset', 'currentAsset'
  ),
  (
    '9a222222-2222-4222-8222-222222222222',
    '9a111111-1111-4111-8111-111111111111',
    '1101', 'Caja', 'asset', 'currentAsset'
  ),
  (
    '9a222222-2222-4222-8222-222222222223',
    '9a111111-1111-4111-8111-111111111111',
    '2105', 'Cuentas por Pagar - Gastos',
    'liability', 'currentLiability'
  ),
  (
    '9a222222-2222-4222-8222-222222222224',
    '9a111111-1111-4111-8111-111111111111',
    '2106', 'Sueldos por Pagar', 'liability', 'currentLiability'
  ),
  (
    '9a222222-2222-4222-8222-222222222225',
    '9a111111-1111-4111-8111-111111111111',
    '610101', 'Sueldo Fernando', 'expense', 'operatingExpense'
  ),
  (
    '9a222222-2222-4222-8222-222222222226',
    '9a111111-1111-4111-8111-111111111111',
    '620401', 'Insumos de taller', 'expense', 'operatingExpense'
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
)
values
  (
    '9a333333-3333-4333-8333-333333333331',
    '9a111111-1111-4111-8111-111111111111',
    'transfer', 'Transferencia',
    '9a222222-2222-4222-8222-222222222221', 'no_tax'
  ),
  (
    '9a333333-3333-4333-8333-333333333332',
    '9a111111-1111-4111-8111-111111111111',
    'cash', 'Efectivo',
    '9a222222-2222-4222-8222-222222222222', 'no_tax'
  );

set local session_replication_role = replica;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9a000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated',
  'included-payroll-manager@example.invalid', '', now(),
  '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  '9a000000-0000-4000-8000-000000000002',
  '9a000000-0000-4000-8000-000000000001',
  '9a111111-1111-4111-8111-111111111111',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"9a000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a000000-0000-4000-8000-000000000001',
  true
);

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title,
  salary_account_id, preferred_payment_method_id
) values (
  '9a444444-4444-4444-8444-444444444441',
  '9a111111-1111-4111-8111-111111111111',
  'IPC-001', 'Fernando', 'Tapia', 'Mecánico',
  '9a222222-2222-4222-8222-222222222225',
  '9a333333-3333-4333-8333-333333333331'
);

insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  '9a555555-5555-4555-8555-555555555551',
  '9a111111-1111-4111-8111-111111111111',
  'IPC-FERNANDO', '2026-07-27', '2026-08-02', 'Semana Fernando',
  18, 72000, 1, 'draft'
);

insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values (
  '9a777777-7777-4777-8777-777777777771',
  '9a111111-1111-4111-8111-111111111111',
  '9a555555-5555-4555-8555-555555555551',
  '9a444444-4444-4444-8444-444444444441',
  'Fernando Tapia', 18, 4000, 72000, 72000,
  '9a333333-3333-4333-8333-333333333331',
  '9a222222-2222-4222-8222-222222222221',
  '9a222222-2222-4222-8222-222222222225'
);

select public.ensure_payroll_line_expense(
  '9a777777-7777-4777-8777-777777777771'
);

set local session_replication_role = replica;
update public.payroll_vouchers
set status = 'confirmed'
where id = '9a555555-5555-4555-8555-555555555551';
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"9a000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a000000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;

select set_config(
  'test.included.payload',
  jsonb_build_object(
    'salary_targets', jsonb_build_array(jsonb_build_object(
      'target_id', '9a888888-8888-4888-8888-888888888881',
      'voucher_id', '9a555555-5555-4555-8555-555555555551',
      'expected_reconciliation_version', (
        select voucher.reconciliation_version
        from public.payroll_vouchers voucher
        where voucher.id = '9a555555-5555-4555-8555-555555555551'
      ),
      'legs', jsonb_build_array(
        jsonb_build_object(
          'leg_id', '9a999999-9999-4999-8999-999999999991',
          'voucher_line_id', '9a777777-7777-4777-8777-777777777771',
          'kind', 'payment', 'funding_kind', 'bank', 'amount', 12000,
          'payment_method_id', '9a333333-3333-4333-8333-333333333331',
          'payment_account_id', '9a222222-2222-4222-8222-222222222221',
          'payment_date', '2026-08-10 15:00:00+00',
          'reference', 'BANK-FERNANDO-22000'
        ),
        jsonb_build_object(
          'leg_id', '9a999999-9999-4999-8999-999999999992',
          'voucher_line_id', '9a777777-7777-4777-8777-777777777771',
          'kind', 'payment', 'funding_kind', 'cash', 'amount', 50000,
          'payment_method_id', '9a333333-3333-4333-8333-333333333332',
          'payment_account_id', '9a222222-2222-4222-8222-222222222222',
          'payment_date', '2026-08-10 15:05:00+00',
          'reference', 'CASH-FERNANDO-50000'
        )
      )
    )),
    'additional_concepts', jsonb_build_array(jsonb_build_object(
      'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
      'target_id', '9a888888-8888-4888-8888-888888888881',
      'beneficiary_employee_id',
        '9a444444-4444-4444-8444-444444444441',
      'expense_account_id', '9a222222-2222-4222-8222-222222222226',
      'amount', 10000,
      'description', 'Reembolso por cajas plásticas',
      'disposition', 'included_in_payroll_total',
      'voucher_id', '9a555555-5555-4555-8555-555555555551',
      'voucher_line_id', '9a777777-7777-4777-8777-777777777771',
      'expected_reconciliation_version', (
        select voucher.reconciliation_version
        from public.payroll_vouchers voucher
        where voucher.id = '9a555555-5555-4555-8555-555555555551'
      ),
      'payment_legs', jsonb_build_array(jsonb_build_object(
        'leg_id', '9adddddd-dddd-4ddd-8ddd-ddddddddddd1',
        'amount', 10000,
        'funding_kind', 'bank',
        'payment_method_id', '9a333333-3333-4333-8333-333333333331',
        'payment_account_id', '9a222222-2222-4222-8222-222222222221',
        'payment_date', '2026-08-10 15:00:00+00',
        'reference', 'BANK-FERNANDO-22000'
      ))
    ))
  )::text,
  true
);

select set_config(
  'test.included.receipt',
  public.apply_payroll_payment_workspace_v2(
    '9acccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'workspace-included-concept-0001',
    0,
    current_setting('test.included.payload')::jsonb
  )::text,
  true
);

select ok(
  (current_setting('test.included.receipt')::jsonb->>'api_version')::int = 2
  and current_setting('test.included.receipt')::jsonb->>'status' = 'applied'
  and current_setting('test.included.receipt')::jsonb
      ->'targets'->0->>'status' = 'paid'
  and current_setting('test.included.receipt')::jsonb
      ->'additional_concepts'->0->>'disposition'
        = 'included_in_payroll_total'
  and current_setting('test.included.receipt')::jsonb
      ->'additional_concepts'->0->>'voucher_line_id'
        = '9a777777-7777-4777-8777-777777777771'
  and current_setting('test.included.receipt')::jsonb
      ->'additional_concepts'->0->>'target_id'
        = '9a888888-8888-4888-8888-888888888881'
  and current_setting('test.included.receipt')::jsonb
      ->'additional_concepts'->0
        ? 'reclassification_journal_entry_id',
  'the receipt exposes final paid state and exact included-concept lineage'
);

select ok(
  exists (
    select 1
    from public.payroll_payment_workspace_concept_dispositions disposition
    where disposition.workspace_id =
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc1'
      and disposition.concept_id =
        '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
      and disposition.disposition = 'included_in_payroll_total'
      and disposition.voucher_id =
        '9a555555-5555-4555-8555-555555555551'
      and disposition.voucher_line_id =
        '9a777777-7777-4777-8777-777777777771'
      and disposition.amount = 10000
      and disposition.reclassification_journal_entry_id is not null
  ),
  'the disposition, voucher link and journal link are durable evidence'
);

select ok(
  (
    select voucher.status = 'paid'
    from public.payroll_vouchers voucher
    where voucher.id = '9a555555-5555-4555-8555-555555555551'
  )
  and exists (
    select 1
    from public.get_payroll_voucher_line_settlements(
      '9a555555-5555-4555-8555-555555555551'
    ) settlement
    where settlement.line_id = '9a777777-7777-4777-8777-777777777771'
      and settlement.cash_paid = 62000
      and settlement.settled_amount = 72000
      and settlement.balance = 0
  ),
  'the 10k included concept settles the remaining payroll-line balance'
);

select ok(
  exists (
    select 1
    from public.payroll_voucher_lines voucher_line
    join public.expenses expense on expense.id = voucher_line.expense_id
    where voucher_line.id = '9a777777-7777-4777-8777-777777777771'
      and expense.total_amount = 72000
      and expense.amount_paid = 72000
      and expense.balance = 0
      and expense.payment_status = 'paid'
  ),
  'the salary expense projection recognizes the included allocation'
);

select ok(
  (
    select sum(payment.amount) = 62000
    from public.payroll_voucher_lines voucher_line
    join public.expense_payments payment
      on payment.expense_id = voucher_line.expense_id
    where voucher_line.id = '9a777777-7777-4777-8777-777777777771'
  )
  and (
    select count(*) = 1 and sum(payment.amount) = 10000
    from public.payroll_payment_workspace_concept_dispositions disposition
    join public.expense_payments payment
      on payment.expense_id = disposition.result_expense_id
    where disposition.concept_id =
      '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  ),
  'cash is 62k salary plus 10k reimbursement, never 72k plus another 10k'
);

select ok(
  exists (
    select 1
    from public.payroll_payment_workspace_concept_dispositions disposition
    join public.expense_lines expense_line
      on expense_line.expense_id = disposition.result_expense_id
    join public.expenses expense
      on expense.id = disposition.result_expense_id
    where disposition.concept_id =
      '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
      and expense_line.account_id =
        '9a222222-2222-4222-8222-222222222226'
      and expense.total_amount = 10000
      and expense.amount_paid = 10000
      and expense.balance = 0
  ),
  'the reimbursement remains a separate fully paid business expense'
);

select ok(
  exists (
    select 1
    from public.payroll_payment_workspace_concept_dispositions disposition
    join public.journal_lines debit_line
      on debit_line.entry_id = disposition.reclassification_journal_entry_id
    join public.journal_lines credit_line
      on credit_line.entry_id = disposition.reclassification_journal_entry_id
    where disposition.concept_id =
      '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
      and debit_line.account_code = '2106'
      and debit_line.debit_amount = 10000
      and credit_line.account_code = '610101'
      and credit_line.credit_amount = 10000
  ),
  'the non-cash journal reduces salary payable and salary expense by 10k'
);

select ok(
  (
    select coalesce(sum(line.debit_amount - line.credit_amount), 0) = 62000
    from public.journal_lines line
    where line.tenant_id = '9a111111-1111-4111-8111-111111111111'
      and line.account_code = '610101'
  )
  and (
    select coalesce(sum(line.debit_amount - line.credit_amount), 0) = 10000
    from public.journal_lines line
    where line.tenant_id = '9a111111-1111-4111-8111-111111111111'
      and line.account_code = '620401'
  ),
  'the ledger classifies 62k as salary and 10k as workshop expense'
);

select ok(
  (
    select coalesce(sum(line.credit_amount - line.debit_amount), 0) = 0
    from public.journal_lines line
    where line.tenant_id = '9a111111-1111-4111-8111-111111111111'
      and line.account_code = '2106'
  )
  and (
    select coalesce(sum(line.credit_amount - line.debit_amount), 0) = 0
    from public.journal_lines line
    where line.tenant_id = '9a111111-1111-4111-8111-111111111111'
      and line.account_code = '2105'
  ),
  'both salary and reimbursement liabilities clear to zero'
);

select ok(
  not exists (
    select 1
    from public.journal_entries entry
    left join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '9a111111-1111-4111-8111-111111111111'
    group by entry.id, entry.total_debit, entry.total_credit
    having coalesce(sum(line.debit_amount), 0)
             <> coalesce(sum(line.credit_amount), 0)
       or entry.total_debit <> coalesce(sum(line.debit_amount), 0)
       or entry.total_credit <> coalesce(sum(line.credit_amount), 0)
  ),
  'all salary, reimbursement, payment and reclassification journals balance'
);

select set_config(
  'test.included.replay',
  public.apply_payroll_payment_workspace_v2(
    '9acccccc-cccc-4ccc-8ccc-ccccccccccc1',
    'workspace-included-concept-0001',
    0,
    current_setting('test.included.payload')::jsonb
  )::text,
  true
);

select ok(
  (current_setting('test.included.replay')::jsonb->>'replayed')::boolean
  and (
    select count(*) = 1
    from public.payroll_payment_workspace_concept_dispositions disposition
    where disposition.workspace_id =
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc1'
  )
  and (
    select count(*) = 1
    from public.journal_entries entry
    where entry.source_document_type =
      'payroll_concept_reclassification'
      and entry.tenant_id = '9a111111-1111-4111-8111-111111111111'
  ),
  'an exact retry returns the stored receipt without duplicate evidence'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v2(
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'workspace-included-concept-0001',
      0,
      jsonb_set(
        current_setting('test.included.payload')::jsonb,
        '{additional_concepts,0,disposition}',
        '"additional"'::jsonb
      )
    )
  $$,
  'P0001',
  'payroll_workspace_v2_idempotency_conflict',
  'one operation key cannot be replayed with a different disposition'
);

reset role;

select throws_ok(
  $$
    update public.payroll_payment_workspace_concept_dispositions
    set amount = amount
    where concept_id = '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
  $$,
  '55000',
  'payroll_workspace_concept_disposition_is_immutable',
  'the included disposition and voucher link are immutable'
);

select throws_ok(
  $$
    update public.journal_lines line
    set description = line.description
    where line.entry_id = (
      select disposition.reclassification_journal_entry_id
      from public.payroll_payment_workspace_concept_dispositions disposition
      where disposition.concept_id =
        '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    )
  $$,
  '55000',
  'payroll_workspace_reclassification_is_immutable',
  'the accounting reclassification cannot diverge from its disposition'
);

set local role authenticated;

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v2(
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc2',
      'workspace-additional-link-0002',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
          'expense_account_id',
            '9a222222-2222-4222-8222-222222222226',
          'amount', 1000,
          'description', 'Adicional no puede enlazarse',
          'disposition', 'additional',
          'voucher_id', '9a555555-5555-4555-8555-555555555551',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '9aeeeeee-eeee-4eee-8eee-eeeeeeeeeee2',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '9a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '9a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '22023',
  'payroll_workspace_v2_additional_cannot_link_payroll',
  'an additional concept cannot accidentally consume payroll balance'
);

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v2(
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc3',
      'workspace-missing-link-0003',
      0,
      jsonb_build_object(
        'salary_targets', '[]'::jsonb,
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
          'beneficiary_employee_id',
            '9a444444-4444-4444-8444-444444444441',
          'expense_account_id',
            '9a222222-2222-4222-8222-222222222226',
          'amount', 1000,
          'description', 'Incluido sin línea',
          'disposition', 'included_in_payroll_total',
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '9aeeeeee-eeee-4eee-8eee-eeeeeeeeeee3',
            'amount', 1000,
            'funding_kind', 'cash',
            'payment_method_id',
              '9a333333-3333-4333-8333-333333333332',
            'payment_account_id',
              '9a222222-2222-4222-8222-222222222222',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '22023',
  'payroll_workspace_v2_invalid_included_link',
  'included disposition requires voucher, line and exact CAS version'
);

-- A fresh voucher proves that 63k salary plus 10k included cannot consume a
-- 72k line.  The complete V1 work is rolled back by the outer V2 command.
reset role;
insert into public.payroll_vouchers (
  id, tenant_id, voucher_number, period_start, period_end, period_label,
  total_hours, total_amount, employee_count, status
) values (
  '9a555555-5555-4555-8555-555555555552',
  '9a111111-1111-4111-8111-111111111111',
  'IPC-OVER', '2026-07-20', '2026-07-26', 'Semana exceso',
  18, 72000, 1, 'draft'
);
insert into public.payroll_voucher_lines (
  id, tenant_id, voucher_id, employee_id, employee_name, worked_hours,
  hourly_rate, regular_amount, total_amount, payment_method_id,
  payment_account_id, salary_account_id
) values (
  '9a777777-7777-4777-8777-777777777772',
  '9a111111-1111-4111-8111-111111111111',
  '9a555555-5555-4555-8555-555555555552',
  '9a444444-4444-4444-8444-444444444441',
  'Fernando Tapia', 18, 4000, 72000, 72000,
  '9a333333-3333-4333-8333-333333333331',
  '9a222222-2222-4222-8222-222222222221',
  '9a222222-2222-4222-8222-222222222225'
);
select public.ensure_payroll_line_expense(
  '9a777777-7777-4777-8777-777777777772'
);
set local session_replication_role = replica;
update public.payroll_vouchers
set status = 'confirmed'
where id = '9a555555-5555-4555-8555-555555555552';
set local session_replication_role = origin;
set local role authenticated;

select throws_ok(
  $$
    select public.apply_payroll_payment_workspace_v2(
      '9acccccc-cccc-4ccc-8ccc-ccccccccccc4',
      'workspace-over-included-0004',
      0,
      jsonb_build_object(
        'salary_targets', jsonb_build_array(jsonb_build_object(
          'target_id', '9a888888-8888-4888-8888-888888888884',
          'voucher_id', '9a555555-5555-4555-8555-555555555552',
          'expected_reconciliation_version', (
            select reconciliation_version
            from public.payroll_vouchers
            where id = '9a555555-5555-4555-8555-555555555552'
          ),
          'legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '9a999999-9999-4999-8999-999999999994',
            'voucher_line_id', '9a777777-7777-4777-8777-777777777772',
            'kind', 'payment', 'funding_kind', 'bank', 'amount', 63000,
            'payment_method_id',
              '9a333333-3333-4333-8333-333333333331',
            'payment_account_id',
              '9a222222-2222-4222-8222-222222222221',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        )),
        'additional_concepts', jsonb_build_array(jsonb_build_object(
          'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
          'target_id', '9a888888-8888-4888-8888-888888888884',
          'beneficiary_employee_id',
            '9a444444-4444-4444-8444-444444444441',
          'expense_account_id',
            '9a222222-2222-4222-8222-222222222226',
          'amount', 10000,
          'description', 'Excede el saldo salarial',
          'disposition', 'included_in_payroll_total',
          'voucher_id', '9a555555-5555-4555-8555-555555555552',
          'voucher_line_id', '9a777777-7777-4777-8777-777777777772',
          'expected_reconciliation_version', (
            select reconciliation_version
            from public.payroll_vouchers
            where id = '9a555555-5555-4555-8555-555555555552'
          ),
          'payment_legs', jsonb_build_array(jsonb_build_object(
            'leg_id', '9adddddd-dddd-4ddd-8ddd-ddddddddddd4',
            'amount', 10000,
            'funding_kind', 'bank',
            'payment_method_id',
              '9a333333-3333-4333-8333-333333333331',
            'payment_account_id',
              '9a222222-2222-4222-8222-222222222221',
            'payment_date', '2026-08-10 15:00:00+00'
          ))
        ))
      )
    )
  $$,
  '23514',
  'payroll_workspace_v2_salary_and_included_exceed_balance',
  'salary legs plus included concepts cannot exceed authoritative balance'
);

select ok(
  not exists (
    select 1
    from public.payroll_payment_workspaces workspace
    where workspace.id = '9acccccc-cccc-4ccc-8ccc-ccccccccccc4'
  )
  and not exists (
    select 1
    from public.expense_payments payment
    where payment.reference = 'Nómina IPC-OVER'
  ),
  'an over-allocation rolls back every salary and reimbursement movement'
);

-- The worker target remains in the exact V1 receipt shape even when the
-- included concept, rather than a salary leg, is the only settlement input.
select set_config(
  'test.included_only.receipt',
  public.apply_payroll_payment_workspace_v2(
    '9acccccc-cccc-4ccc-8ccc-ccccccccccc5',
    'workspace-included-only-0005',
    0,
    jsonb_build_object(
      'salary_targets', jsonb_build_array(jsonb_build_object(
        'target_id', '9a888888-8888-4888-8888-888888888885',
        'voucher_id', '9a555555-5555-4555-8555-555555555552',
        'expected_reconciliation_version', (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '9a555555-5555-4555-8555-555555555552'
        ),
        'legs', '[]'::jsonb
      )),
      'additional_concepts', jsonb_build_array(jsonb_build_object(
        'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
        'target_id', '9a888888-8888-4888-8888-888888888885',
        'beneficiary_employee_id',
          '9a444444-4444-4444-8444-444444444441',
        'expense_account_id',
          '9a222222-2222-4222-8222-222222222226',
        'amount', 72000,
        'description', 'Concepto incluido cubre el target completo',
        'disposition', 'included_in_payroll_total',
        'voucher_id', '9a555555-5555-4555-8555-555555555552',
        'voucher_line_id', '9a777777-7777-4777-8777-777777777772',
        'expected_reconciliation_version', (
          select reconciliation_version
          from public.payroll_vouchers
          where id = '9a555555-5555-4555-8555-555555555552'
        ),
        'payment_legs', jsonb_build_array(jsonb_build_object(
          'leg_id', '9adddddd-dddd-4ddd-8ddd-ddddddddddd5',
          'amount', 72000,
          'funding_kind', 'bank',
          'payment_method_id',
            '9a333333-3333-4333-8333-333333333331',
          'payment_account_id',
            '9a222222-2222-4222-8222-222222222221',
          'payment_date', '2026-08-10 16:00:00+00'
        ))
      ))
    )
  )::text,
  true
);

select ok(
  current_setting('test.included_only.receipt')::jsonb
      ->'targets'->0->>'target_id'
        = '9a888888-8888-4888-8888-888888888885'
  and current_setting('test.included_only.receipt')::jsonb
      ->'targets'->0->>'voucher_id'
        = '9a555555-5555-4555-8555-555555555552'
  and current_setting('test.included_only.receipt')::jsonb
      ->'targets'->0->>'status' = 'paid'
  and current_setting('test.included_only.receipt')::jsonb
      ->'targets'->0->'legs' = '[]'::jsonb
  and current_setting('test.included_only.receipt')::jsonb
      ->'additional_concepts'->0->>'target_id'
        = '9a888888-8888-4888-8888-888888888885',
  'an included-only worker keeps its UUIDv5 target and exact empty-leg receipt'
);

select set_config(
  'test.additional.receipt',
  public.apply_payroll_payment_workspace_v2(
    '9acccccc-cccc-4ccc-8ccc-ccccccccccc6',
    'workspace-additional-receipt-0006',
    0,
    jsonb_build_object(
      'salary_targets', '[]'::jsonb,
      'additional_concepts', jsonb_build_array(jsonb_build_object(
        'concept_id', '9abbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6',
        'beneficiary_employee_id',
          '9a444444-4444-4444-8444-444444444441',
        'expense_account_id',
          '9a222222-2222-4222-8222-222222222226',
        'amount', 1000,
        'description', 'Reembolso adicional independiente',
        'disposition', 'additional',
        'payment_legs', jsonb_build_array(jsonb_build_object(
          'leg_id', '9adddddd-dddd-4ddd-8ddd-ddddddddddd6',
          'amount', 1000,
          'funding_kind', 'cash',
          'payment_method_id',
            '9a333333-3333-4333-8333-333333333332',
          'payment_account_id',
            '9a222222-2222-4222-8222-222222222222',
          'payment_date', '2026-08-10 16:05:00+00'
        ))
      ))
    )
  )::text,
  true
);

select ok(
  current_setting('test.additional.receipt')::jsonb
      ->'additional_concepts'->0->>'disposition' = 'additional'
  and not (
    current_setting('test.additional.receipt')::jsonb
      ->'additional_concepts'->0
      ?| array[
        'target_id',
        'voucher_id',
        'voucher_line_id',
        'reclassification_id',
        'reclassification_journal_entry_id'
      ]
  ),
  'an additional concept receipt omits payroll and reclassification lineage'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
