begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.set_employee_payroll_payment_method(uuid,timestamp with time zone,uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.set_employee_payroll_payment_method(uuid,timestamp with time zone,uuid,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.set_employee_payroll_payment_method(uuid,timestamp with time zone,uuid,text,text,text)',
    'EXECUTE'
  ),
  'only authenticated ERP callers can execute the payment-method command'
);

select is(
  (
    select proargnames
    from pg_catalog.pg_proc
    where oid =
      'public.set_employee_payroll_payment_method(uuid,timestamp with time zone,uuid,text,text,text)'::regprocedure
  ),
  array[
    'p_employee_id',
    'p_expected_updated_at',
    'p_method_id',
    'p_bank_name',
    'p_bank_account_type',
    'p_bank_account_number'
  ]::text[],
  'the client cannot provide a competing legacy method code'
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
    '7f2a0100-0000-4000-8000-000000000001',
    'Payment Method Tenant A',
    'payment-method-a',
    'payment-method-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000002',
    'Payment Method Tenant B',
    'payment-method-b',
    'payment-method-b@example.invalid',
    'America/Santiago',
    true
  );

insert into public.accounts (
  id,
  tenant_id,
  code,
  name,
  type,
  category,
  is_active
)
values
  (
    '7f2a0100-0000-4000-8000-000000000301',
    '7f2a0100-0000-4000-8000-000000000001',
    '1110',
    'Banco A',
    'asset',
    'currentAsset',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000302',
    '7f2a0100-0000-4000-8000-000000000001',
    '1101',
    'Caja A',
    'asset',
    'currentAsset',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000303',
    '7f2a0100-0000-4000-8000-000000000001',
    '1199',
    'Cuenta inactiva A',
    'asset',
    'currentAsset',
    false
  ),
  (
    '7f2a0100-0000-4000-8000-000000000304',
    '7f2a0100-0000-4000-8000-000000000002',
    '1110',
    'Banco B',
    'asset',
    'currentAsset',
    true
  );

insert into public.payment_methods (
  id,
  tenant_id,
  code,
  name,
  account_id,
  is_active
)
values
  (
    '7f2a0100-0000-4000-8000-000000000401',
    '7f2a0100-0000-4000-8000-000000000001',
    'transfer',
    'Transferencia A',
    '7f2a0100-0000-4000-8000-000000000301',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000402',
    '7f2a0100-0000-4000-8000-000000000001',
    'cash',
    'Efectivo A',
    '7f2a0100-0000-4000-8000-000000000302',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000403',
    '7f2a0100-0000-4000-8000-000000000001',
    'check',
    'Cheque A',
    '7f2a0100-0000-4000-8000-000000000301',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000404',
    '7f2a0100-0000-4000-8000-000000000001',
    'bank_transfer_inactive',
    'Transferencia inactiva A',
    '7f2a0100-0000-4000-8000-000000000303',
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000405',
    '7f2a0100-0000-4000-8000-000000000002',
    'transfer',
    'Transferencia B',
    '7f2a0100-0000-4000-8000-000000000304',
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
    '7f2a0100-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'payment-manager-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f2a0100-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'payment-accountant-a@example.invalid',
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
  employee_number,
  first_name,
  last_name,
  job_title,
  status,
  updated_at,
  preferred_payment_method,
  bank_name,
  bank_account_type,
  bank_account_number
)
values
  (
    '7f2a0100-0000-4000-8000-000000000201',
    '7f2a0100-0000-4000-8000-000000000001',
    'PAYMENT-A-201',
    'Vicente',
    'Díaz',
    'Manager',
    'active',
    '2026-08-01 12:00:00.123456+00',
    'cash',
    'Banco anterior',
    'Cuenta Vista',
    '00001111'
  ),
  (
    '7f2a0100-0000-4000-8000-000000000202',
    '7f2a0100-0000-4000-8000-000000000002',
    'PAYMENT-B-202',
    'Tenant',
    'Two',
    'Mechanic',
    'active',
    '2026-08-01 12:00:00.123456+00',
    'cash',
    null,
    null,
    null
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
    '7f2a0100-0000-4000-8000-000000000111',
    '7f2a0100-0000-4000-8000-000000000101',
    '7f2a0100-0000-4000-8000-000000000001',
    null,
    'manager',
    '{"manage_users":true}'::jsonb,
    true
  ),
  (
    '7f2a0100-0000-4000-8000-000000000112',
    '7f2a0100-0000-4000-8000-000000000102',
    '7f2a0100-0000-4000-8000-000000000001',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a0100-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a0100-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      null,
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000402'
    )
  $$,
  '22023',
  'payroll_employee_payment_method_invalid',
  'missing command identity is a deterministic rejection before writing'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000402'
    )
  $$,
  '42501',
  'payroll_employee_payment_method_not_authorized',
  'payroll-only authority cannot mutate the HR-owned employee row'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"7f2a0100-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f2a0100-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-07-31 12:00:00+00',
      '7f2a0100-0000-4000-8000-000000000402'
    )
  $$,
  '40001',
  'payroll_employee_payment_method_version_conflict',
  'a stale employee version is rejected before writing'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000403'
    )
  $$,
  '23514',
  'payroll_employee_payment_method_unsupported',
  'a configured but unsupported method cannot enter the Payroll preference'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000404',
      'Banco',
      'Cuenta Vista',
      '1234'
    )
  $$,
  '23503',
  'payroll_employee_payment_method_unavailable',
  'a method whose backing account is inactive is unavailable'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000405',
      'Banco',
      'Cuenta Vista',
      '1234'
    )
  $$,
  '23503',
  'payroll_employee_payment_method_unavailable',
  'a same-id method from another tenant is unavailable'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000202',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000401',
      'Banco',
      'Cuenta Vista',
      '1234'
    )
  $$,
  'P0002',
  'payroll_employee_payment_method_employee_not_found',
  'the command cannot target an employee from another tenant'
);

select throws_ok(
  $$
    select public.set_employee_payroll_payment_method(
      '7f2a0100-0000-4000-8000-000000000201',
      '2026-08-01 12:00:00.123456+00',
      '7f2a0100-0000-4000-8000-000000000401',
      null,
      'Cuenta Vista',
      null
    )
  $$,
  '23514',
  'payroll_employee_payment_method_bank_details_required',
  'transfer requires the two bank fields the sheet marks mandatory'
);

select set_config(
  'test.payment_method.transfer_receipt',
  public.set_employee_payroll_payment_method(
    '7f2a0100-0000-4000-8000-000000000201',
    '2026-08-01 12:00:00.123456+00',
    '7f2a0100-0000-4000-8000-000000000401',
    '  BancoEstado  ',
    'Cuenta Corriente',
    '  12345678  '
  )::text,
  true
);

select is(
  current_setting('test.payment_method.transfer_receipt')::jsonb
    ->>'preferred_payment_method',
  'transfer',
  'the server derives the legacy method code from the locked method row'
);

select ok(
  (
    current_setting('test.payment_method.transfer_receipt')::jsonb
      ->>'updated_at'
  )::timestamp with time zone
    <> '2026-08-01 12:00:00.123456+00'::timestamp with time zone,
  'the employee updated_at trigger rotates the optimistic version'
);

select is(
  current_setting('test.payment_method.transfer_receipt')::jsonb,
  (
    select jsonb_build_object(
      'id', id,
      'tenant_id', tenant_id,
      'updated_at', updated_at,
      'preferred_payment_method', preferred_payment_method,
      'preferred_payment_method_id', preferred_payment_method_id,
      'bank_name', bank_name,
      'bank_account_type', bank_account_type,
      'bank_account_number', bank_account_number
    )
    from public.employees
    where id = '7f2a0100-0000-4000-8000-000000000201'
  ),
  'the receipt exactly matches the complete stored payment snapshot'
);

select is(
  (
    select jsonb_build_object(
      'method_id', preferred_payment_method_id,
      'method_code', preferred_payment_method,
      'bank_name', bank_name,
      'bank_type', bank_account_type,
      'bank_number', bank_account_number
    )
    from public.employees
    where id = '7f2a0100-0000-4000-8000-000000000201'
  ),
  jsonb_build_object(
    'method_id', '7f2a0100-0000-4000-8000-000000000401'::uuid,
    'method_code', 'transfer',
    'bank_name', 'BancoEstado',
    'bank_type', 'Cuenta Corriente',
    'bank_number', '12345678'
  ),
  'transfer atomically stores the derived method pair and trimmed bank fields'
);

select is(
  (
    select count(*)::integer
    from jsonb_object_keys(
      current_setting('test.payment_method.transfer_receipt')::jsonb
    )
  ),
  8,
  'the receipt exposes only the narrow payment-configuration snapshot'
);

select set_config(
  'test.payment_method.cash_receipt',
  public.set_employee_payroll_payment_method(
    '7f2a0100-0000-4000-8000-000000000201',
    (
      select updated_at
      from public.employees
      where id = '7f2a0100-0000-4000-8000-000000000201'
    ),
    '7f2a0100-0000-4000-8000-000000000402',
    null,
    null,
    null
  )::text,
  true
);

select is(
  (
    select jsonb_build_object(
      'method_id', preferred_payment_method_id,
      'method_code', preferred_payment_method,
      'bank_name', bank_name,
      'bank_type', bank_account_type,
      'bank_number', bank_account_number
    )
    from public.employees
    where id = '7f2a0100-0000-4000-8000-000000000201'
  ),
  jsonb_build_object(
    'method_id', '7f2a0100-0000-4000-8000-000000000402'::uuid,
    'method_code', 'cash',
    'bank_name', 'BancoEstado',
    'bank_type', 'Cuenta Corriente',
    'bank_number', '12345678'
  ),
  'cash changes the method pair without erasing the stored bank account'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
