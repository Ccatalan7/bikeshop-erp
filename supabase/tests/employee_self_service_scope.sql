begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_function(
  'public',
  'get_my_employee_self_service',
  array['date'],
  'ERP labor self-service has one server-authoritative RPC'
);
select ok(
  (
    select function_row.prosecdef and function_row.provolatile = 's'
    from pg_proc function_row
    join pg_namespace namespace_row
      on namespace_row.oid = function_row.pronamespace
    where namespace_row.nspname = 'public'
      and function_row.proname = 'get_my_employee_self_service'
      and function_row.proargtypes = array['date'::regtype::oid]::oidvector
  ),
  'the self-service RPC is a stable SECURITY DEFINER projection'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_my_employee_self_service(date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_my_employee_self_service(date)',
    'EXECUTE'
  ),
  'only authenticated API callers can execute labor self-service'
);
select is(
  (
    select function_row.pronargs
    from pg_proc function_row
    join pg_namespace namespace_row
      on namespace_row.oid = function_row.pronamespace
    where namespace_row.nspname = 'public'
      and function_row.proname = 'get_my_employee_self_service'
      and function_row.proargtypes = array['date'::regtype::oid]::oidvector
  ),
  1::smallint,
  'the RPC accepts no client tenant or employee selector'
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
    '7e150000-0000-4000-8000-000000000001',
    'Self Service Tenant A',
    'self-service-a',
    'owner-self-a@example.invalid',
    'Pacific/Auckland',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000002',
    'Self Service Tenant B',
    'self-service-b',
    'owner-self-b@example.invalid',
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
    '7e150000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'active-self@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e150000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'inactive-self@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e150000-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'leave-self@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e150000-0000-4000-8000-000000000104',
    'authenticated',
    'authenticated',
    'cross-tenant-self@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e150000-0000-4000-8000-000000000105',
    'authenticated',
    'authenticated',
    'duplicate-profile-self@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7e150000-0000-4000-8000-000000000106',
    'authenticated',
    'authenticated',
    'missing-profile-self@example.invalid',
    '',
    now(),
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
  job_title,
  status
)
values
  (
    '7e150000-0000-4000-8000-000000000201',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000101',
    'SELF-201',
    'Active',
    'Employee',
    'active-self@example.invalid',
    'Mechanic',
    'active'
  ),
  (
    '7e150000-0000-4000-8000-000000000202',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000102',
    'SELF-202',
    'Inactive',
    'Employee',
    'inactive-self@example.invalid',
    'Cashier',
    'inactive'
  ),
  (
    '7e150000-0000-4000-8000-000000000203',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000103',
    'SELF-203',
    'Leave',
    'Employee',
    'leave-self@example.invalid',
    'Cashier',
    'on_leave'
  ),
  (
    '7e150000-0000-4000-8000-000000000204',
    '7e150000-0000-4000-8000-000000000002',
    '7e150000-0000-4000-8000-000000000104',
    'SELF-204',
    'Cross',
    'Tenant',
    'cross-tenant-self@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '7e150000-0000-4000-8000-000000000205',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000105',
    'SELF-205',
    'Duplicate',
    'Profile',
    'duplicate-profile-self@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '7e150000-0000-4000-8000-000000000206',
    '7e150000-0000-4000-8000-000000000001',
    null,
    'SELF-206',
    'Team',
    'Published',
    'team-published@example.invalid',
    'Sales',
    'active'
  ),
  (
    '7e150000-0000-4000-8000-000000000207',
    '7e150000-0000-4000-8000-000000000001',
    null,
    'SELF-207',
    'Team',
    'Inactive',
    'team-inactive@example.invalid',
    'Sales',
    'inactive'
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
    '7e150000-0000-4000-8000-000000000301',
    '7e150000-0000-4000-8000-000000000101',
    '7e150000-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true,
    '7e150000-0000-4000-8000-000000000201'
  ),
  (
    '7e150000-0000-4000-8000-000000000302',
    '7e150000-0000-4000-8000-000000000102',
    '7e150000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '7e150000-0000-4000-8000-000000000202'
  ),
  (
    '7e150000-0000-4000-8000-000000000303',
    '7e150000-0000-4000-8000-000000000103',
    '7e150000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '7e150000-0000-4000-8000-000000000203'
  ),
  (
    '7e150000-0000-4000-8000-000000000304',
    '7e150000-0000-4000-8000-000000000104',
    '7e150000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '7e150000-0000-4000-8000-000000000204'
  ),
  (
    '7e150000-0000-4000-8000-000000000305',
    '7e150000-0000-4000-8000-000000000105',
    '7e150000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '7e150000-0000-4000-8000-000000000205'
  );

insert into public.planned_shifts (
  id,
  tenant_id,
  employee_id,
  title,
  start_at,
  end_at,
  timezone,
  status,
  source,
  store_hours_validated
)
values
  (
    '7e150000-0000-4000-8000-000000000401',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    'Crossing own shift',
    '2026-07-05 11:30:00+00',
    '2026-07-05 14:00:00+00',
    'America/Santiago',
    'published',
    'manual',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000402',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    'Published team shift',
    '2026-07-06 00:00:00+00',
    '2026-07-06 08:00:00+00',
    'America/Santiago',
    'published',
    'manual',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000403',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    'Completed team shift',
    '2026-07-07 00:00:00+00',
    '2026-07-07 08:00:00+00',
    'America/Santiago',
    'completed',
    'manual',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000404',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    'Draft team shift',
    '2026-07-08 00:00:00+00',
    '2026-07-08 08:00:00+00',
    'America/Santiago',
    'draft',
    'manual',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000405',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000207',
    'Inactive team shift',
    '2026-07-09 00:00:00+00',
    '2026-07-09 08:00:00+00',
    'America/Santiago',
    'published',
    'manual',
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
  break_minutes,
  status
)
values
  (
    '7e150000-0000-4000-8000-000000000501',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    '2026-07-05 11:00:00+00',
    '2026-07-05 13:00:00+00',
    2,
    0,
    0,
    'completed'
  ),
  (
    '7e150000-0000-4000-8000-000000000502',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    '2026-07-06 21:00:00+00',
    '2026-07-07 05:00:00+00',
    7.5,
    0,
    30,
    'approved'
  ),
  (
    '7e150000-0000-4000-8000-000000000503',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    '2026-07-07 21:00:00+00',
    '2026-07-08 05:00:00+00',
    7.5,
    0,
    30,
    'rejected'
  ),
  (
    '7e150000-0000-4000-8000-000000000504',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    '2026-07-06 21:00:00+00',
    '2026-07-07 05:00:00+00',
    8,
    0,
    0,
    'approved'
  );

insert into public.payroll_vouchers (
  id,
  tenant_id,
  voucher_number,
  period_start,
  period_end,
  period_label,
  status
)
values
  (
    '7e150000-0000-4000-8000-000000000601',
    '7e150000-0000-4000-8000-000000000001',
    'SELF-PAY-1',
    current_date - 30,
    current_date,
    'Current self period',
    'paid'
  ),
  (
    '7e150000-0000-4000-8000-000000000602',
    '7e150000-0000-4000-8000-000000000001',
    'SELF-PAY-2',
    current_date - 30,
    current_date,
    'Other employee only',
    'paid'
  );

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category
)
values (
  '7e150000-0000-4000-8000-000000000603',
  '7e150000-0000-4000-8000-000000000001',
  'SELF-CASH',
  'Cuenta de pago self-service',
  'asset',
  'currentAsset'
);

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id
)
values (
  '7e150000-0000-4000-8000-000000000604',
  '7e150000-0000-4000-8000-000000000001',
  'self_transfer',
  'Transferencia Banco de Prueba',
  '7e150000-0000-4000-8000-000000000603'
);

insert into public.payroll_voucher_lines (
  id,
  tenant_id,
  voucher_id,
  employee_id,
  employee_name,
  worked_hours,
  overtime_hours,
  regular_amount,
  overtime_amount,
  total_amount,
  payment_method,
  payment_method_id,
  is_included
)
values
  (
    '7e150000-0000-4000-8000-000000000611',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000601',
    '7e150000-0000-4000-8000-000000000201',
    'Active Employee',
    160,
    2,
    800000,
    20000,
    820000,
    'legacy-transfer',
    '7e150000-0000-4000-8000-000000000604',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000612',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000601',
    '7e150000-0000-4000-8000-000000000206',
    'Team Published',
    160,
    0,
    700000,
    0,
    700000,
    'transfer',
    null,
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000613',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000602',
    '7e150000-0000-4000-8000-000000000206',
    'Team Published',
    160,
    0,
    700000,
    0,
    700000,
    'transfer',
    null,
    true
  );

insert into public.shift_change_requests (
  id,
  tenant_id,
  employee_id,
  request_type,
  status,
  worker_note
)
values
  (
    '7e150000-0000-4000-8000-000000000701',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    'availability',
    'pending',
    'Own request'
  ),
  (
    '7e150000-0000-4000-8000-000000000702',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    'availability',
    'pending',
    'Other request'
  );

insert into public.employee_default_shift_blocks (
  id,
  tenant_id,
  employee_id,
  day_of_week,
  start_time,
  end_time,
  is_active
)
values
  (
    '7e150000-0000-4000-8000-000000000801',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000201',
    1,
    '09:00',
    '18:00',
    true
  ),
  (
    '7e150000-0000-4000-8000-000000000802',
    '7e150000-0000-4000-8000-000000000001',
    '7e150000-0000-4000-8000-000000000206',
    1,
    '09:00',
    '18:00',
    true
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7e150000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select is(
  public.get_my_employee_self_service('2026-07-08'::date)->>'tenant_id',
  '7e150000-0000-4000-8000-000000000001',
  'the RPC derives the tenant from the exact active profile'
);
select is(
  public.get_my_employee_self_service('2026-07-08'::date)->>'employee_id',
  '7e150000-0000-4000-8000-000000000201',
  'the RPC derives the exact active employee from auth.uid()'
);
select is(
  public.get_my_employee_self_service('2026-07-08'::date)->>'timezone',
  'Pacific/Auckland',
  'the store timezone is authoritative'
);
select is(
  public.get_my_employee_self_service('2026-07-08'::date)->>'week_start',
  '2026-07-06',
  'a week anchor is normalized to shop-calendar Monday'
);
select is(
  public.get_my_employee_self_service('2026-07-08'::date)->>'week_start_at',
  '2026-07-05T12:00:00+00:00',
  'the UTC boundary comes from store midnight rather than device timezone'
);
select is(
  (
    select
      extract(
        epoch from (
          (snapshot.payload->>'week_end_at')::timestamp with time zone
          - (snapshot.payload->>'week_start_at')::timestamp with time zone
        )
      ) / 3600
    from (
      select public.get_my_employee_self_service('2026-09-23'::date) as payload
    ) snapshot
  ),
  167::numeric,
  'week boundaries are independently derived across the store DST transition'
);
select is(
  jsonb_array_length(
    public.get_my_employee_self_service('2026-07-08'::date)->'my_shifts'
  ),
  1,
  'a self shift crossing into the selected week is included by overlap'
);
select is(
  (
    public.get_my_employee_self_service('2026-07-08'::date)
      ->'my_shifts'->0->>'planned_minutes_in_week'
  )::numeric,
  120.00::numeric,
  'a crossing shift contributes only its selected-week overlap'
);
select is(
  (
    select array_agg(team_shift->>'status' order by team_shift->>'status')
    from jsonb_array_elements(
      public.get_my_employee_self_service('2026-07-08'::date)
        ->'team_shifts'
    ) team_shift
  ),
  array['completed', 'published']::text[],
  'team coverage contains only published and completed active-team shifts'
);
select is(
  jsonb_array_length(
    public.get_my_employee_self_service('2026-07-08'::date)->'attendances'
  ),
  3,
  'attendance uses interval overlap and returns only the signed-in employee'
);
select is(
  (
    select (attendance_row->>'worked_minutes_in_week')::numeric
    from jsonb_array_elements(
      public.get_my_employee_self_service('2026-07-08'::date)
        ->'attendances'
    ) attendance_row
    where attendance_row->>'status' = 'rejected'
  ),
  0::numeric,
  'rejected attendance remains visible but contributes no worked time'
);
select is(
  (
    select sum((attendance_row->>'worked_minutes_in_week')::numeric)
    from jsonb_array_elements(
      public.get_my_employee_self_service('2026-07-08'::date)
        ->'attendances'
    ) attendance_row
  ),
  510.00::numeric,
  'only completed and approved attendance contributes to weekly worked time'
);
select is(
  (
    select array_agg(payroll_row->>'employee_id')
    from jsonb_array_elements(
      public.get_my_employee_self_service('2026-07-08'::date)
        ->'payroll_lines'
    ) payroll_row
  ),
  array['7e150000-0000-4000-8000-000000000201']::text[],
  'payroll starts at the own line and never returns another employee voucher'
);
select is(
  (
    select payroll_row->>'payment_method'
    from jsonb_array_elements(
      public.get_my_employee_self_service('2026-07-08'::date)
        ->'payroll_lines'
    ) payroll_row
  ),
  'Transferencia Banco de Prueba',
  'payroll resolves the tenant payment-method display name'
);
select is(
  jsonb_array_length(
    public.get_my_employee_self_service('2026-07-08'::date)
      ->'change_requests'
  ),
  1,
  'shift-change requests are self-owned'
);
select is(
  jsonb_array_length(
    public.get_my_employee_self_service('2026-07-08'::date)
      ->'default_shift_blocks'
  ),
  1,
  'the base weekly schedule is self-owned'
);

reset role;

update auth.users
set banned_until = statement_timestamp() + interval '1 day'
where id = '7e150000-0000-4000-8000-000000000101';

set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'a currently banned ERP employee cannot use labor self-service'
);
reset role;

update auth.users
set banned_until = statement_timestamp() - interval '1 day'
where id = '7e150000-0000-4000-8000-000000000101';

set local role authenticated;
select lives_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'an expired temporary ban does not permanently block labor self-service'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000102',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'an inactive employee fails closed'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000103',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'an on-leave employee fails closed'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000104',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'a cross-tenant employee link fails closed'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000106',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'a missing active ERP profile fails closed'
);
reset role;

set local session_replication_role = replica;
insert into public.employee_portal_accounts (
  id,
  tenant_id,
  employee_id,
  auth_user_id,
  username,
  login_email,
  is_active
)
values (
  '7e150000-0000-4000-8000-000000000901',
  '7e150000-0000-4000-8000-000000000001',
  '7e150000-0000-4000-8000-000000000201',
  null,
  'self.portal.conflict',
  'self-portal-conflict@worker-login.invalid',
  true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'an active Worker portal identity conflict fails closed'
);
reset role;

drop index if exists public.user_profiles_one_active_tenant_per_user_uidx;
set local session_replication_role = replica;
insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  role,
  permissions,
  is_active,
  employee_id
)
values (
  '7e150000-0000-4000-8000-000000000315',
  '7e150000-0000-4000-8000-000000000105',
  '7e150000-0000-4000-8000-000000000002',
  'cashier',
  '{}'::jsonb,
  true,
  null
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claim.sub',
  '7e150000-0000-4000-8000-000000000105',
  true
);
set local role authenticated;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  'P0001',
  'erp_employee_self_service_context_invalid',
  'duplicated active ERP profiles fail closed'
);
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$select public.get_my_employee_self_service('2026-07-08'::date)$$,
  '42501',
  'permission denied for function get_my_employee_self_service',
  'anonymous callers cannot invoke the self-service RPC'
);
reset role;

select * from finish();
rollback;
