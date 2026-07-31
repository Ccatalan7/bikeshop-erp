begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_payroll_voucher_draft_v2(date,date,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.prepare_payroll_voucher_draft_v2(date,date,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.prepare_payroll_voucher_draft_v2(date,date,text,text)',
    'EXECUTE'
  ),
  'only authenticated ERP callers can execute weekly draft preparation'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.generate_payroll_voucher_draft(date,date,text)',
    'EXECUTE'
  ),
  'the authenticated client can no longer invoke the legacy generator'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_payroll_attendance_summary_for_period_v2(date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_payroll_attendance_summary_for_period_v2(date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_payroll_attendance_summary_for_period_v2(date,date)',
    'EXECUTE'
  ),
  'the regular/overtime preview projection is authenticated-only'
);

select ok(
  to_regclass(
    'public.ux_payroll_vouchers_tenant_week_non_voided'
  ) is not null
  and (
    select index_row.indisunique
      and index_row.indisvalid
      and index_row.indpred is not null
      and pg_get_indexdef(index_row.indexrelid)
        like '%(tenant_id, period_start, period_end)%'
      and pg_get_expr(index_row.indpred, index_row.indrelid)
        ~ 'status.*voided'
    from pg_catalog.pg_index index_row
    where index_row.indexrelid =
      'public.ux_payroll_vouchers_tenant_week_non_voided'::regclass
  ),
  'a valid partial unique index protects one non-voided voucher per week'
);

set local session_replication_role = replica;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  owner_email,
  timezone,
  is_active
)
values (
  '7f292100-0000-4000-8000-000000000001',
  'Payroll Prepare Tenant',
  'payroll-prepare-v2',
  'payroll-prepare@example.invalid',
  'America/Santiago',
  true
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '7f292100-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'payroll-manager@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f292100-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'payroll-cashier@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category
)
values
  (
    '7f292100-0000-4000-8000-000000000301',
    '7f292100-0000-4000-8000-000000000001',
    '1102',
    'Banco',
    'asset',
    'currentAsset'
  ),
  (
    '7f292100-0000-4000-8000-000000000302',
    '7f292100-0000-4000-8000-000000000001',
    '1101',
    'Caja',
    'asset',
    'currentAsset'
  ),
  (
    '7f292100-0000-4000-8000-000000000303',
    '7f292100-0000-4000-8000-000000000001',
    '610101',
    'Sueldo transferencia',
    'expense',
    'operatingExpense'
  ),
  (
    '7f292100-0000-4000-8000-000000000304',
    '7f292100-0000-4000-8000-000000000001',
    '610102',
    'Sueldo efectivo',
    'expense',
    'operatingExpense'
  );

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id,
  default_tax_treatment,
  is_active
)
values
  (
    '7f292100-0000-4000-8000-000000000401',
    '7f292100-0000-4000-8000-000000000001',
    'transfer',
    'Transferencia',
    '7f292100-0000-4000-8000-000000000301',
    'no_tax',
    true
  ),
  (
    '7f292100-0000-4000-8000-000000000402',
    '7f292100-0000-4000-8000-000000000001',
    'cash',
    'Efectivo',
    '7f292100-0000-4000-8000-000000000302',
    'no_tax',
    true
  );

insert into public.employees (
  id,
  tenant_id,
  employee_number,
  first_name,
  last_name,
  job_title,
  status,
  hourly_rate,
  preferred_payment_method,
  preferred_payment_method_id,
  salary_account_id
)
values
  (
    '7f292100-0000-4000-8000-000000000201',
    '7f292100-0000-4000-8000-000000000001',
    'PREP-001',
    'Lucas',
    'Pacheco',
    'Mecánico',
    'active',
    3500,
    'transfer',
    '7f292100-0000-4000-8000-000000000401',
    '7f292100-0000-4000-8000-000000000303'
  ),
  (
    '7f292100-0000-4000-8000-000000000202',
    '7f292100-0000-4000-8000-000000000001',
    'PREP-002',
    'Guillermo',
    'Pinto',
    'Mecánico',
    'active',
    4000,
    'cash',
    '7f292100-0000-4000-8000-000000000402',
    '7f292100-0000-4000-8000-000000000304'
  ),
  (
    '7f292100-0000-4000-8000-000000000203',
    '7f292100-0000-4000-8000-000000000001',
    'PREP-003',
    'Sin',
    'Asistencia',
    'Mecánico',
    'active',
    3500,
    null,
    null,
    '7f292100-0000-4000-8000-000000000303'
  );

insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  employee_id,
  role,
  permissions,
  is_active
)
values
  (
    '7f292100-0000-4000-8000-000000000111',
    '7f292100-0000-4000-8000-000000000101',
    '7f292100-0000-4000-8000-000000000001',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  ),
  (
    '7f292100-0000-4000-8000-000000000112',
    '7f292100-0000-4000-8000-000000000102',
    '7f292100-0000-4000-8000-000000000001',
    null,
    'cashier',
    '{}'::jsonb,
    true
  );

insert into public.attendances (
  id,
  tenant_id,
  employee_id,
  check_in,
  check_out,
  worked_hours,
  overtime_hours,
  status
)
values
  (
    '7f292100-0000-4000-8000-000000000501',
    '7f292100-0000-4000-8000-000000000001',
    '7f292100-0000-4000-8000-000000000201',
    '2026-07-20 13:00:00+00',
    '2026-07-20 21:00:00+00',
    8,
    2,
    'completed'
  ),
  (
    '7f292100-0000-4000-8000-000000000502',
    '7f292100-0000-4000-8000-000000000001',
    '7f292100-0000-4000-8000-000000000202',
    '2026-07-21 13:00:00+00',
    '2026-07-21 17:00:00+00',
    4,
    0,
    'approved'
  ),
  (
    '7f292100-0000-4000-8000-000000000503',
    '7f292100-0000-4000-8000-000000000001',
    '7f292100-0000-4000-8000-000000000201',
    '2026-07-22 13:00:00+00',
    null,
    10,
    5,
    'ongoing'
  ),
  (
    '7f292100-0000-4000-8000-000000000504',
    '7f292100-0000-4000-8000-000000000001',
    '7f292100-0000-4000-8000-000000000202',
    '2026-07-27 13:00:00+00',
    '2026-07-27 21:00:00+00',
    8,
    0,
    'completed'
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f292100-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f292100-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      date '2026-07-20',
      date '2026-07-26',
      'Semana 30',
      'prepare-denied-0001'
    )
  $$,
  '42501',
  'Payroll access denied',
  'an ERP member without payroll authority cannot prepare a draft'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"7f292100-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f292100-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select is(
  (
    select attendance_summary.overtime_hours
    from public.get_payroll_attendance_summary_for_period_v2(
      date '2026-07-20',
      date '2026-07-26'
    ) attendance_summary
    where attendance_summary.employee_id =
      '7f292100-0000-4000-8000-000000000201'
  ),
  2.00::numeric,
  'the read-only preview exposes completed overtime instead of hiding it'
);
select is(
  (
    select attendance_summary.total_hours
    from public.get_payroll_attendance_summary_for_period_v2(
      date '2026-07-20',
      date '2026-07-26'
    ) attendance_summary
    where attendance_summary.employee_id =
      '7f292100-0000-4000-8000-000000000202'
  ),
  4.00::numeric,
  'the read-only preview includes approved regular hours'
);

select throws_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      date '2026-07-21',
      date '2026-07-27',
      'Semana inválida',
      'prepare-invalid-week-0001'
    )
  $$,
  '22023',
  'payroll_prepare_draft_invalid_week',
  'the command accepts only a Monday-through-Sunday civil week'
);

select set_config(
  'test.payroll_prepare.receipt',
  public.prepare_payroll_voucher_draft_v2(
    date '2026-07-20',
    date '2026-07-26',
    'Semana 30',
    'prepare-attendance-0001'
  )::text,
  true
);

select is(
  current_setting('test.payroll_prepare.receipt')::jsonb->>'command',
  'prepare_payroll_voucher_draft_v2',
  'the receipt identifies the versioned server command'
);
select is(
  (
    current_setting('test.payroll_prepare.receipt')::jsonb
      ->>'contract_version'
  )::integer,
  2,
  'the receipt exposes the command contract version'
);
select is(
  current_setting('test.payroll_prepare.receipt')::jsonb->>'status',
  'draft',
  'the prepared aggregate remains a draft'
);
select is(
  (
    current_setting('test.payroll_prepare.receipt')::jsonb
      ->>'total_hours'
  )::numeric,
  14.00::numeric,
  'completed and approved regular plus overtime hours are included'
);
select is(
  (
    current_setting('test.payroll_prepare.receipt')::jsonb
      ->>'total_amount'
  )::numeric,
  54500.00::numeric,
  'the server calculates regular and 1.5x overtime amounts'
);
select is(
  (
    current_setting('test.payroll_prepare.receipt')::jsonb
      ->>'employee_count'
  )::integer,
  2,
  'only workers with payable hours count toward the aggregate'
);
select is(
  (
    current_setting('test.payroll_prepare.receipt')::jsonb
      ->>'line_count'
  )::integer,
  3,
  'the server snapshots every active worker and excludes zero-hour lines'
);
select is(
  current_setting('test.payroll_prepare.receipt')::jsonb
    #>> '{origin,projection}',
  'server_derived',
  'the receipt records that the snapshot was derived on the server'
);
select is(
  current_setting('test.payroll_prepare.receipt')::jsonb
    #> '{origin,included_statuses}',
  '["completed", "approved"]'::jsonb,
  'the receipt records the accepted Attendance states'
);

select is(
  (
    select voucher.total_amount
    from public.payroll_vouchers voucher
    where voucher.id = (
      current_setting('test.payroll_prepare.receipt')::jsonb
        ->>'voucher_id'
    )::uuid
  ),
  54500.00::numeric,
  'the voucher header persists the authoritative server total'
);
select is(
  (
    select voucher_line.total_amount
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = (
      current_setting('test.payroll_prepare.receipt')::jsonb
        ->>'voucher_id'
    )::uuid
      and voucher_line.employee_id =
        '7f292100-0000-4000-8000-000000000201'
  ),
  38500.00::numeric,
  'the overtime worker line matches the canonical calculation'
);
select ok(
  (
    select
      voucher_line.payment_method_id =
        '7f292100-0000-4000-8000-000000000401'
      and voucher_line.payment_account_id =
        '7f292100-0000-4000-8000-000000000301'
      and voucher_line.salary_account_id =
        '7f292100-0000-4000-8000-000000000303'
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = (
      current_setting('test.payroll_prepare.receipt')::jsonb
        ->>'voucher_id'
    )::uuid
      and voucher_line.employee_id =
        '7f292100-0000-4000-8000-000000000201'
  ),
  'payment method and both accounts come from canonical server configuration'
);
select is(
  (
    select voucher_line.is_included
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = (
      current_setting('test.payroll_prepare.receipt')::jsonb
        ->>'voucher_id'
    )::uuid
      and voucher_line.employee_id =
        '7f292100-0000-4000-8000-000000000203'
  ),
  false,
  'a worker without completed or approved hours is retained but not included'
);

select is(
  public.prepare_payroll_voucher_draft_v2(
    date '2026-07-20',
    date '2026-07-26',
    'Semana 30',
    'prepare-attendance-0001'
  ),
  current_setting('test.payroll_prepare.receipt')::jsonb,
  'an exact retry returns the immutable original receipt'
);
select is(
  (
    select count(*)::integer
    from public.payroll_vouchers voucher
    where voucher.tenant_id =
      '7f292100-0000-4000-8000-000000000001'
      and voucher.period_start = date '2026-07-20'
      and voucher.period_end = date '2026-07-26'
      and voucher.status <> 'voided'
  ),
  1,
  'exact replay creates no duplicate weekly aggregate'
);
select is(
  (
    select count(*)::integer
    from public.payroll_voucher_draft_operations operation
    where operation.tenant_id =
      '7f292100-0000-4000-8000-000000000001'
      and operation.operation_key = 'prepare-attendance-0001'
  ),
  1,
  'exact replay creates one operation receipt'
);

select throws_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      date '2026-07-20',
      date '2026-07-26',
      'Semana 30 modificada',
      'prepare-attendance-0001'
    )
  $$,
  'P0001',
  'payroll_prepare_draft_idempotency_conflict',
  'the same operation key cannot be reused for a different payload'
);

select throws_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      date '2026-07-20',
      date '2026-07-26',
      'Otra nómina para la misma semana',
      'prepare-attendance-0002'
    )
  $$,
  '23505',
  'payroll_voucher_period_already_exists',
  'a different operation cannot create a second non-voided weekly voucher'
);

reset role;

select * from finish();
rollback;
