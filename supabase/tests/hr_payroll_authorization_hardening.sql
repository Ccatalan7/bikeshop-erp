begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select is(
  (
    select count(*)::integer
    from unnest(array[
      'departments',
      'job_roles',
      'employees',
      'work_schedules',
      'employee_contracts',
      'attendances',
      'attendance_records',
      'leave_requests',
      'medical_leaves',
      'employment_contracts',
      'payroll_runs',
      'payroll_entries',
      'payroll_records',
      'shifts',
      'planning_roles',
      'employee_planning_roles',
      'employee_default_shift_blocks',
      'planned_shifts',
      'shift_change_requests',
      'payroll_vouchers',
      'payroll_voucher_lines',
      'employee_advances',
      'employee_advance_allocations'
    ]) table_name_value
    join pg_class table_row
      on table_row.oid =
        to_regclass('public.' || table_name_value)
    where table_row.relrowsecurity is true
  ),
  23,
  'every HR, planning, attendance, and payroll base table has RLS enabled'
);

select is(
  (
    select count(*)::integer
    from pg_policies policy_row
    where policy_row.schemaname = 'public'
      and policy_row.tablename = any(array[
        'employees',
        'employee_contracts',
        'attendances',
        'attendance_records',
        'leave_requests',
        'medical_leaves',
        'employment_contracts',
        'payroll_runs',
        'payroll_entries',
        'payroll_records',
        'shifts',
        'planning_roles',
        'employee_planning_roles',
        'employee_default_shift_blocks',
        'planned_shifts',
        'shift_change_requests',
        'payroll_vouchers',
        'payroll_voucher_lines',
        'employee_advances',
        'employee_advance_allocations'
      ])
      and (
        coalesce(policy_row.qual, '') like '%user_tenant_id%'
        or coalesce(policy_row.with_check, '') like '%user_tenant_id%'
      )
  ),
  0,
  'no sensitive HR/payroll policy retains generic tenant-wide authority'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.work_schedules',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.employee_contracts',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.employees',
    'SELECT'
  )
  and not has_table_privilege(
    'anon',
    'public.payroll_voucher_lines',
    'SELECT'
  ),
  'anonymous API access is removed from HR and payroll tables'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.employees',
    'DELETE'
  ),
  'authenticated callers must retire employees through the canonical command'
);

select ok(
  to_regclass('public.payroll_voucher_number_seq') is not null
  and (
    select bool_and(
      not has_sequence_privilege(
        role_name,
        'public.payroll_voucher_number_seq',
        privilege_name
      )
    )
    from unnest(array['anon', 'authenticated', 'service_role']) role_name
    cross join unnest(array['USAGE', 'SELECT', 'UPDATE']) privilege_name
  ),
  'the payroll voucher counter exists but is not directly mutable by API roles'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_erp_employee_directory()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_erp_employee_directory()',
    'EXECUTE'
  ),
  'the minimal ERP directory is authenticated-only'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_erp_chat_principal_directory()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_erp_chat_principal_directory()',
    'EXECUTE'
  )
  and pg_get_function_result(
    'public.get_erp_chat_principal_directory()'::regprocedure
  ) not like '%email%',
  'the redacted ERP chat principal directory is authenticated-only'
);

select ok(
  pg_get_function_result(
    'public.get_erp_employee_directory()'::regprocedure
  ) not like '%rut%'
  and pg_get_function_result(
    'public.get_erp_employee_directory()'::regprocedure
  ) not like '%email%'
  and pg_get_function_result(
    'public.get_erp_employee_directory()'::regprocedure
  ) not like '%phone%'
  and pg_get_function_result(
    'public.get_erp_employee_directory()'::regprocedure
  ) not like '%salary%'
  and pg_get_function_result(
    'public.get_erp_employee_directory()'::regprocedure
  ) not like '%bank%',
  'the directory signature excludes contact, identity, bank, and salary data'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.confirm_payroll_voucher_internal(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.calculate_payroll_internal(uuid,uuid,integer,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.ensure_payroll_line_expense(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.calculate_attendance_hours()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.validate_hr_payroll_tenant_consistency()',
    'EXECUTE'
  ),
  'payroll implementations and trigger helpers are not direct API commands'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.confirm_payroll_voucher(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.confirm_payroll_voucher_v2(uuid,text,bigint)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.calculate_payroll(uuid,uuid,integer,integer)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_income_expense_timeseries(integer,boolean)',
    'EXECUTE'
  ),
  'authorized wrappers expose the versioned payroll command and retain safe public RPCs'
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
values
  (
    '7e280000-0000-4000-8000-000000000001',
    'HR Security Tenant A',
    'hr-security-a',
    'owner-hr-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7e280000-0000-4000-8000-000000000002',
    'HR Security Tenant B',
    'hr-security-b',
    'owner-hr-b@example.invalid',
    'Pacific/Auckland',
    true
  );

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  banned_until,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '7e280000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'manager-a@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'accountant-a@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'cashier-self@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000104',
    'authenticated',
    'authenticated',
    'banned-manager@example.invalid',
    '',
    now(),
    statement_timestamp() + interval '1 day',
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000105',
    'authenticated',
    'authenticated',
    'expired-accountant@example.invalid',
    '',
    now(),
    statement_timestamp() - interval '1 day',
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000106',
    'authenticated',
    'authenticated',
    'accountant-b@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000107',
    'authenticated',
    'authenticated',
    'unlinked-cashier@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000108',
    'authenticated',
    'authenticated',
    'worker-a@example.invalid',
    '',
    now(),
    null,
    jsonb_build_object(
      'account_type',
      'worker_portal',
      'tenant_id',
      '7e280000-0000-4000-8000-000000000001',
      'employee_id',
      '7e280000-0000-4000-8000-000000000208',
      'role',
      'worker'
    ),
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000109',
    'authenticated',
    'authenticated',
    'disabled-link@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e280000-0000-4000-8000-000000000110',
    'authenticated',
    'authenticated',
    'cross-link@example.invalid',
    '',
    now(),
    null,
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.employees (
  id,
  tenant_id,
  user_id,
  employee_number,
  first_name,
  last_name,
  email,
  phone,
  rut,
  job_title,
  system_role,
  status,
  base_salary,
  bank_name,
  bank_account_number
)
values
  (
    '7e280000-0000-4000-8000-000000000201',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000101',
    'HR-201',
    'Manager',
    'Active',
    'manager-a@example.invalid',
    '+560001',
    '11.111.111-1',
    'Manager',
    'manager',
    'active',
    2000000,
    'Manager Bank',
    '201'
  ),
  (
    '7e280000-0000-4000-8000-000000000202',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000102',
    'HR-202',
    'Accountant',
    'Active',
    'accountant-a@example.invalid',
    '+560002',
    '22.222.222-2',
    'Accountant',
    'accountant',
    'active',
    1800000,
    'Accounting Bank',
    '202'
  ),
  (
    '7e280000-0000-4000-8000-000000000203',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000103',
    'HR-203',
    'Cashier',
    'Self',
    'cashier-self@example.invalid',
    '+560003',
    '33.333.333-3',
    'Cashier',
    'cashier',
    'active',
    900000,
    'Self Bank',
    '203'
  ),
  (
    '7e280000-0000-4000-8000-000000000204',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000104',
    'HR-204',
    'Manager',
    'Banned',
    'banned-manager@example.invalid',
    '+560004',
    '44.444.444-4',
    'Manager',
    'manager',
    'active',
    2100000,
    'Banned Bank',
    '204'
  ),
  (
    '7e280000-0000-4000-8000-000000000205',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000105',
    'HR-205',
    'Accountant',
    'Expired Ban',
    'expired-accountant@example.invalid',
    '+560005',
    '55.555.555-5',
    'Accountant',
    'accountant',
    'active',
    1700000,
    'Expired Bank',
    '205'
  ),
  (
    '7e280000-0000-4000-8000-000000000206',
    '7e280000-0000-4000-8000-000000000001',
    null,
    'HR-206',
    'Coworker',
    'No Login',
    'coworker@example.invalid',
    '+560006',
    '66.666.666-6',
    'Mechanic',
    null,
    'active',
    1200000,
    'Coworker Bank',
    '206'
  ),
  (
    '7e280000-0000-4000-8000-000000000207',
    '7e280000-0000-4000-8000-000000000002',
    '7e280000-0000-4000-8000-000000000106',
    'HR-207',
    'Cross',
    'Tenant',
    'accountant-b@example.invalid',
    '+560007',
    '77.777.777-7',
    'Accountant',
    'accountant',
    'active',
    1900000,
    'Cross Bank',
    '207'
  ),
  (
    '7e280000-0000-4000-8000-000000000208',
    '7e280000-0000-4000-8000-000000000001',
    null,
    'HR-208',
    'Worker',
    'Portal',
    'worker-a@example.invalid',
    '+560008',
    '88.888.888-8',
    'Mechanic',
    null,
    'active',
    1100000,
    'Worker Bank',
    '208'
  ),
  (
    '7e280000-0000-4000-8000-000000000209',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000109',
    'HR-209',
    'Disabled',
    'Profile',
    'disabled-link@example.invalid',
    '+560009',
    '99.999.999-9',
    'Sales',
    'cashier',
    'active',
    1000000,
    'Disabled Bank',
    '209'
  ),
  (
    '7e280000-0000-4000-8000-000000000210',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000110',
    'HR-210',
    'Cross',
    'Profile Link',
    'cross-link@example.invalid',
    '+560010',
    '10.101.010-1',
    'Sales',
    'cashier',
    'active',
    1000000,
    'Cross Profile Bank',
    '210'
  ),
  (
    '7e280000-0000-4000-8000-000000000211',
    '7e280000-0000-4000-8000-000000000002',
    null,
    'HR-211',
    'Profile',
    'Tenant B',
    'profile-b@example.invalid',
    '+560011',
    '10.101.011-K',
    'Sales',
    null,
    'active',
    1000000,
    'Profile B Bank',
    '211'
  );

insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  role,
  permissions,
  is_active,
  employee_id
)
values
  (
    '7e280000-0000-4000-8000-000000000301',
    '7e280000-0000-4000-8000-000000000101',
    '7e280000-0000-4000-8000-000000000001',
    'manager',
    '{"manage_users":true,"access_accounting":true}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000201'
  ),
  (
    '7e280000-0000-4000-8000-000000000302',
    '7e280000-0000-4000-8000-000000000102',
    '7e280000-0000-4000-8000-000000000001',
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000202'
  ),
  (
    '7e280000-0000-4000-8000-000000000303',
    '7e280000-0000-4000-8000-000000000103',
    '7e280000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000203'
  ),
  (
    '7e280000-0000-4000-8000-000000000304',
    '7e280000-0000-4000-8000-000000000104',
    '7e280000-0000-4000-8000-000000000001',
    'manager',
    '{"manage_users":true,"access_accounting":true}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000204'
  ),
  (
    '7e280000-0000-4000-8000-000000000305',
    '7e280000-0000-4000-8000-000000000105',
    '7e280000-0000-4000-8000-000000000001',
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000205'
  ),
  (
    '7e280000-0000-4000-8000-000000000306',
    '7e280000-0000-4000-8000-000000000106',
    '7e280000-0000-4000-8000-000000000002',
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000207'
  ),
  (
    '7e280000-0000-4000-8000-000000000307',
    '7e280000-0000-4000-8000-000000000107',
    '7e280000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    null
  ),
  (
    '7e280000-0000-4000-8000-000000000309',
    '7e280000-0000-4000-8000-000000000109',
    '7e280000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    false,
    '7e280000-0000-4000-8000-000000000209'
  ),
  (
    '7e280000-0000-4000-8000-000000000310',
    '7e280000-0000-4000-8000-000000000110',
    '7e280000-0000-4000-8000-000000000002',
    'cashier',
    '{}'::jsonb,
    true,
    '7e280000-0000-4000-8000-000000000211'
  );

insert into public.employee_portal_accounts (
  id,
  tenant_id,
  employee_id,
  auth_user_id,
  username,
  login_email,
  is_active,
  must_reset_password
)
values (
  '7e280000-0000-4000-8000-000000000401',
  '7e280000-0000-4000-8000-000000000001',
  '7e280000-0000-4000-8000-000000000208',
  '7e280000-0000-4000-8000-000000000108',
  'worker.security',
  'worker-a@example.invalid',
  true,
  false
);

insert into public.work_schedules (
  id,
  tenant_id,
  name,
  weekly_hours
)
values
  (
    '7e280000-0000-4000-8000-000000000501',
    '7e280000-0000-4000-8000-000000000001',
    'Tenant A Schedule',
    40
  ),
  (
    '7e280000-0000-4000-8000-000000000502',
    '7e280000-0000-4000-8000-000000000002',
    'Tenant B Schedule',
    40
  );

insert into public.employee_contracts (
  id,
  tenant_id,
  employee_id,
  start_date,
  salary_amount,
  position_title,
  status
)
values
  (
    '7e280000-0000-4000-8000-000000000511',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000203',
    '2026-01-01',
    900000,
    'Cashier',
    'active'
  ),
  (
    '7e280000-0000-4000-8000-000000000512',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    '2026-01-01',
    1200000,
    'Mechanic',
    'active'
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
    '7e280000-0000-4000-8000-000000000521',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000203',
    '2026-07-01 02:30:00+00',
    '2026-07-01 10:30:00+00',
    8,
    0,
    'completed'
  ),
  (
    '7e280000-0000-4000-8000-000000000522',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    statement_timestamp() - interval '1 hour',
    null,
    null,
    0,
    'ongoing'
  ),
  (
    '7e280000-0000-4000-8000-000000000523',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000208',
    '2026-07-02 13:00:00+00',
    '2026-07-02 21:00:00+00',
    8,
    0,
    'approved'
  ),
  (
    '7e280000-0000-4000-8000-000000000524',
    '7e280000-0000-4000-8000-000000000002',
    '7e280000-0000-4000-8000-000000000207',
    '2026-07-02 00:00:00+00',
    '2026-07-02 08:00:00+00',
    8,
    0,
    'approved'
  ),
  (
    '7e280000-0000-4000-8000-000000000526',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000203',
    '2026-07-01 03:00:00+00',
    '2026-07-01 07:00:00+00',
    4,
    0,
    'rejected'
  );

insert into public.medical_leaves (
  id,
  tenant_id,
  employee_id,
  leave_type,
  start_date,
  end_date,
  doctor_rut,
  diagnosis,
  certificate_url,
  status
)
values
  (
    '7e280000-0000-4000-8000-000000000531',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000203',
    'enfermedad_comun',
    '2026-07-10',
    '2026-07-11',
    '12.345.678-9',
    'Private self diagnosis',
    'private/self.pdf',
    'approved'
  ),
  (
    '7e280000-0000-4000-8000-000000000532',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    'enfermedad_comun',
    '2026-07-12',
    '2026-07-13',
    '98.765.432-1',
    'Private coworker diagnosis',
    'private/coworker.pdf',
    'approved'
  );

insert into public.payroll_vouchers (
  id,
  tenant_id,
  voucher_number,
  period_start,
  period_end,
  status,
  total_amount
)
values
  (
    '7e280000-0000-4000-8000-000000000541',
    '7e280000-0000-4000-8000-000000000001',
    'PV-HR-A',
    '2026-07-01',
    '2026-07-31',
    'confirmed',
    2000000
  ),
  (
    '7e280000-0000-4000-8000-000000000542',
    '7e280000-0000-4000-8000-000000000002',
    'PV-HR-B',
    '2026-07-01',
    '2026-07-31',
    'confirmed',
    1900000
  );

insert into public.payroll_voucher_lines (
  id,
  tenant_id,
  voucher_id,
  employee_id,
  employee_name,
  worked_hours,
  hourly_rate,
  regular_amount,
  total_amount,
  is_included
)
values
  (
    '7e280000-0000-4000-8000-000000000551',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000541',
    '7e280000-0000-4000-8000-000000000203',
    'Cashier Self',
    8,
    10000,
    80000,
    80000,
    true
  ),
  (
    '7e280000-0000-4000-8000-000000000552',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000541',
    '7e280000-0000-4000-8000-000000000206',
    'Coworker No Login',
    8,
    10000,
    80000,
    80000,
    true
  ),
  (
    '7e280000-0000-4000-8000-000000000553',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000541',
    '7e280000-0000-4000-8000-000000000208',
    'Worker Portal',
    8,
    10000,
    80000,
    80000,
    true
  ),
  (
    '7e280000-0000-4000-8000-000000000554',
    '7e280000-0000-4000-8000-000000000002',
    '7e280000-0000-4000-8000-000000000542',
    '7e280000-0000-4000-8000-000000000207',
    'Cross Tenant',
    8,
    10000,
    80000,
    80000,
    true
  );

insert into public.employee_advances (
  id,
  tenant_id,
  employee_id,
  amount,
  amount_applied,
  paid_at,
  status
)
values
  (
    '7e280000-0000-4000-8000-000000000561',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000203',
    10000,
    5000,
    '2026-07-01 12:00:00+00',
    'partially_applied'
  ),
  (
    '7e280000-0000-4000-8000-000000000562',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    10000,
    0,
    '2026-07-01 12:00:00+00',
    'open'
  );

insert into public.employee_advance_allocations (
  id,
  tenant_id,
  advance_id,
  voucher_line_id,
  amount,
  applied_at
)
values (
  '7e280000-0000-4000-8000-000000000571',
  '7e280000-0000-4000-8000-000000000001',
  '7e280000-0000-4000-8000-000000000561',
  '7e280000-0000-4000-8000-000000000551',
  5000,
  '2026-07-31 12:00:00+00'
);

insert into public.planning_roles (
  id,
  tenant_id,
  code,
  name,
  is_active
)
values (
  '7e280000-0000-4000-8000-000000000581',
  '7e280000-0000-4000-8000-000000000001',
  'security_worker',
  'Security Worker',
  true
);

insert into public.planned_shifts (
  id,
  tenant_id,
  employee_id,
  planning_role_id,
  title,
  start_at,
  end_at,
  status
)
values
  (
    '7e280000-0000-4000-8000-000000000591',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000208',
    '7e280000-0000-4000-8000-000000000581',
    'Own worker shift',
    '2026-07-02 13:00:00+00',
    '2026-07-02 21:00:00+00',
    'published'
  ),
  (
    '7e280000-0000-4000-8000-000000000592',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    '7e280000-0000-4000-8000-000000000581',
    'Coworker shift',
    '2026-07-02 13:00:00+00',
    '2026-07-02 21:00:00+00',
    'published'
  );

insert into public.shift_change_requests (
  id,
  tenant_id,
  employee_id,
  planned_shift_id,
  request_type,
  status,
  worker_note
)
values
  (
    '7e280000-0000-4000-8000-000000000601',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000208',
    '7e280000-0000-4000-8000-000000000591',
    'update',
    'pending',
    'Own worker request'
  ),
  (
    '7e280000-0000-4000-8000-000000000602',
    '7e280000-0000-4000-8000-000000000001',
    '7e280000-0000-4000-8000-000000000206',
    '7e280000-0000-4000-8000-000000000592',
    'update',
    'pending',
    'Coworker request'
  );

set local session_replication_role = origin;

-- Linked ordinary ERP employee: own sensitive rows only, plus the curated
-- non-sensitive directory.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000103',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.employees),
  1,
  'ordinary ERP employee can read only the exact own full employee row'
);
select is(
  (
    select rut
    from public.employees
    where id = '7e280000-0000-4000-8000-000000000203'
  ),
  '33.333.333-3',
  'the exact ERP employee may read their own identity data'
);
select is(
  (select count(*)::integer from public.employee_contracts),
  1,
  'ordinary ERP employee sees only their own salary contract'
);
select is(
  (select count(*)::integer from public.medical_leaves),
  1,
  'ordinary ERP employee sees only their own medical leave'
);
select is(
  (select count(*)::integer from public.payroll_voucher_lines),
  1,
  'ordinary ERP employee sees only their own payroll line'
);
select is(
  (select count(*)::integer from public.payroll_vouchers),
  0,
  'ordinary ERP employee cannot read aggregate payroll voucher headers'
);
select is(
  (select count(*)::integer from public.employee_advances),
  1,
  'ordinary ERP employee sees only their own advance'
);
select is(
  (select count(*)::integer from public.employee_advance_allocations),
  1,
  'ordinary ERP employee sees only allocations attached to their own payroll'
);
select is(
  (select count(*)::integer from public.get_erp_employee_directory()),
  9,
  'the directory returns non-terminated operational coworkers in one tenant'
);
select is(
  (select count(*)::integer from public.get_erp_chat_principal_directory()),
  5,
  'chat directory returns active same-tenant ERP principals only'
);
select is(
  (
    select employee_id
    from public.get_erp_chat_principal_directory()
    where user_id = '7e280000-0000-4000-8000-000000000107'::uuid
  ),
  null::uuid,
  'an active ERP principal without an employee record remains chat-addressable'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000103'::uuid
  ),
  null::uuid,
  'directory lookup never confuses an Auth user UUID with an employee UUID'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000203'::uuid
  ),
  '7e280000-0000-4000-8000-000000000103'::uuid,
  'directory exposes an active bilateral ERP user link'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000204'::uuid
  ),
  null::uuid,
  'directory suppresses a currently banned user link'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000205'::uuid
  ),
  '7e280000-0000-4000-8000-000000000105'::uuid,
  'directory accepts an expired temporary ban'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000209'::uuid
  ),
  null::uuid,
  'directory suppresses an inactive profile link'
);
select is(
  (
    select user_id
    from public.get_erp_employee_directory()
    where employee_id =
      '7e280000-0000-4000-8000-000000000210'::uuid
  ),
  null::uuid,
  'directory suppresses a user profile linked in another tenant'
);
select is(
  (
    select total_days
    from public.get_attendance_summary(
      '7e280000-0000-4000-8000-000000000203',
      '2026-06-30',
      '2026-06-30'
    )
  ),
  1,
  'attendance assigns a UTC instant to the prior America/Santiago shop day'
);
select is(
  (
    select total_days
    from public.get_attendance_summary(
      '7e280000-0000-4000-8000-000000000203',
      '2026-07-01',
      '2026-07-01'
    )
  ),
  0,
  'attendance does not use the UTC session date as the shop date'
);
select throws_ok(
  $$ select * from public.get_checked_in_employees() $$,
  '42501',
  'Attendance access denied',
  'ordinary ERP employee cannot inspect team check-in state'
);
select throws_ok(
  $$
    select public.confirm_payroll_voucher_v2(
      '7e280000-0000-4000-8000-000000000541',
      'ordinary-user-confirm-denied',
      0
    )
  $$,
  '42501',
  'Payroll access denied',
  'ordinary ERP employee cannot confirm payroll'
);
select throws_ok(
  $$
    select public.calculate_payroll(
      '7e280000-0000-4000-8000-000000000002',
      '7e280000-0000-4000-8000-000000000207',
      2026,
      7
    )
  $$,
  '42501',
  'Payroll access denied',
  'ordinary ERP employee cannot calculate cross-tenant payroll'
);

update public.employees
set base_salary = 1
where id = '7e280000-0000-4000-8000-000000000203';

reset role;

select is(
  (
    select base_salary
    from public.employees
    where id = '7e280000-0000-4000-8000-000000000203'
  ),
  900000::numeric,
  'self-read authority does not grant direct remuneration mutation'
);

-- HR manager has same-tenant HR authority and no cross-tenant rows.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.employees),
  9,
  'active HR manager reads all and only same-tenant employees'
);
select is(
  (select count(*)::integer from public.medical_leaves),
  2,
  'active HR manager may administer same-tenant medical leave records'
);
select is(
  (select count(*)::integer from public.get_checked_in_employees()),
  1,
  'active HR manager may inspect current tenant check-ins'
);
select lives_ok(
  $$
    update public.attendances
    set notes = 'Manager reviewed'
    where id = '7e280000-0000-4000-8000-000000000521'
  $$,
  'active HR manager may update same-tenant attendance'
);
select throws_ok(
  $$
    insert into public.attendances (
      id,
      tenant_id,
      employee_id,
      check_in,
      status
    )
    values (
      '7e280000-0000-4000-8000-000000000525',
      '7e280000-0000-4000-8000-000000000001',
      '7e280000-0000-4000-8000-000000000207',
      statement_timestamp(),
      'ongoing'
    )
  $$,
  '23514',
  'HR/payroll tenant mismatch',
  'HR manager cannot attach a cross-tenant employee to attendance'
);

reset role;

-- Accountant has payroll/compensation authority, not private diagnoses.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.employees),
  9,
  'accounting authority may read same-tenant employee remuneration inputs'
);
select is(
  (select count(*)::integer from public.employee_contracts),
  2,
  'accounting authority may read same-tenant salary contracts'
);
select is(
  (select count(*)::integer from public.medical_leaves),
  0,
  'accounting authority cannot read private medical diagnoses or documents'
);
select is(
  (select count(*)::integer from public.payroll_vouchers),
  1,
  'accounting authority reads same-tenant payroll headers only'
);
-- The legacy client-facing generator is intentionally revoked: the versioned
-- v2 command is the only authorized draft writer.
select throws_ok(
  $$
    select public.generate_payroll_voucher_draft(
      '2026-06-30',
      '2026-06-30',
      'Shop-day payroll hardening'
    )
  $$,
  '42501',
  'permission denied for function generate_payroll_voucher_draft',
  'accounting authority cannot call the revoked legacy draft generator'
);
select throws_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      '2026-06-30',
      '2026-06-30',
      'Shop-day payroll hardening',
      'hardening-shop-day-draft-0001'
    )
  $$,
  '22023',
  'payroll_prepare_draft_invalid_week',
  'v2 rejects a shop-day period: payroll weeks are Monday through Sunday'
);
select lives_ok(
  $$
    select public.prepare_payroll_voucher_draft_v2(
      '2026-06-29',
      '2026-07-05',
      'Weekly payroll hardening',
      'hardening-weekly-draft-0001'
    )
  $$,
  'accounting authority can prepare a weekly payroll draft through v2'
);
select is(
  (
    select line.worked_hours
    from public.payroll_voucher_lines line
    join public.payroll_vouchers voucher
      on voucher.id = line.voucher_id
     and voucher.tenant_id = line.tenant_id
    where voucher.period_label = 'Weekly payroll hardening'
      and line.employee_id =
        '7e280000-0000-4000-8000-000000000203'
  ),
  8::numeric,
  'draft uses the tenant day boundary and excludes rejected attendance'
);
select lives_ok(
  $$ select * from public.get_income_expense_timeseries(1, false) $$,
  'accounting authority retains payroll-aware accounting projections'
);
select throws_ok(
  $$
    select public.calculate_payroll(
      '7e280000-0000-4000-8000-000000000002',
      '7e280000-0000-4000-8000-000000000207',
      2026,
      7
    )
  $$,
  '42501',
  'Payroll access denied',
  'accountant cannot select an arbitrary tenant in calculate_payroll'
);
select throws_ok(
  $$
    insert into public.payroll_voucher_lines (
      id,
      tenant_id,
      voucher_id,
      employee_id,
      employee_name,
      total_amount
    )
    values (
      '7e280000-0000-4000-8000-000000000555',
      '7e280000-0000-4000-8000-000000000001',
      '7e280000-0000-4000-8000-000000000542',
      '7e280000-0000-4000-8000-000000000202',
      'Cross Voucher',
      1
    )
  $$,
  '42501',
  'permission denied for table payroll_voucher_lines',
  'direct payroll line DML is rejected before cross-tenant linkage'
);

reset role;

-- Future ban fails closed across RLS and SECURITY DEFINER wrappers.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000104","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000104',
  true
);
set local role authenticated;

select is(
  public.erp_member_tenant_id(),
  null::uuid,
  'a future Auth ban removes authoritative ERP membership'
);
select is(
  (select count(*)::integer from public.employees),
  0,
  'a banned manager JWT cannot read HR rows'
);
select is(
  (select count(*)::integer from public.payroll_vouchers),
  0,
  'a banned manager JWT cannot read payroll rows'
);
select throws_ok(
  $$ select * from public.get_attendance_summary_for_period(current_date, current_date) $$,
  '42501',
  'Attendance access denied',
  'a banned manager JWT cannot use attendance definer-rights RPCs'
);
select throws_ok(
  $$ select * from public.get_income_expense_timeseries(1, false) $$,
  '42501',
  'Accounting access denied',
  'a banned manager JWT cannot use accounting definer-rights RPCs'
);

reset role;

-- An expired temporary ban is not a permanent authorization tombstone.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000105","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000105',
  true
);
set local role authenticated;

select is(
  public.erp_member_tenant_id(),
  '7e280000-0000-4000-8000-000000000001'::uuid,
  'an expired Auth ban restores authoritative ERP membership'
);
select is(
  (select count(*)::integer from public.payroll_vouchers),
  2,
  'an expired-ban accountant regains same-tenant payroll reads'
);
select is(
  (select count(*)::integer from public.medical_leaves),
  0,
  'expired-ban accounting authority still cannot read diagnoses'
);
select lives_ok(
  $$ select * from public.get_income_expense_timeseries(1, false) $$,
  'an expired-ban accountant regains accounting projections'
);

reset role;

-- Unlinked ERP members keep the safe directory but get no full employee row.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000107","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000107',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.employees),
  0,
  'unlinked ERP member cannot read any full employee row'
);
select is(
  (select count(*)::integer from public.get_erp_employee_directory()),
  9,
  'unlinked active ERP member retains the minimal coworker directory'
);

reset role;

-- Worker Portal keeps only its exact planning/attendance/payroll projection.
select set_config(
  'request.jwt.claims',
  '{"sub":"7e280000-0000-4000-8000-000000000108","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e280000-0000-4000-8000-000000000108',
  true
);
set local role authenticated;

select is(
  (select count(*)::integer from public.employees),
  0,
  'Worker Portal cannot read full employee rows'
);
select is(
  (select count(*)::integer from public.planned_shifts),
  1,
  'Worker Portal direct planning read is exact-employee only'
);
select is(
  (select count(*)::integer from public.shift_change_requests),
  1,
  'Worker Portal direct request read is exact-employee only'
);
select is(
  (
    select count(*)::integer
    from public.get_my_worker_attendances(
      '2026-07-01 00:00:00+00',
      '2026-07-03 00:00:00+00'
    )
  ),
  1,
  'Worker Portal attendance RPC remains exact-employee scoped'
);
-- Two own rows: the monthly fixture line plus the weekly v2 draft prepared
-- earlier in this suite. Both vouchers hold other employees' lines, so the
-- count also proves neither voucher leaks a foreign line here.
select is(
  (
    select count(*)::integer
    from public.get_my_worker_payroll_for_period(
      '2026-07-01',
      '2026-07-31'
    )
  ),
  2,
  'Worker Portal payroll RPC remains exact-employee scoped'
);

reset role;

update auth.users
set banned_until = statement_timestamp() + interval '1 day'
where id = '7e280000-0000-4000-8000-000000000108';

set local role authenticated;
select is(
  public.worker_portal_tenant_id(),
  null::uuid,
  'a future ban closes Worker Portal authority'
);
reset role;

update auth.users
set banned_until = statement_timestamp() - interval '1 day'
where id = '7e280000-0000-4000-8000-000000000108';

set local role authenticated;
select is(
  public.worker_portal_tenant_id(),
  '7e280000-0000-4000-8000-000000000001'::uuid,
  'an expired temporary ban restores Worker Portal authority'
);
reset role;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
