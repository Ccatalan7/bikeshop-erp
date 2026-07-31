begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege(
    'authenticated',
    'public.learn_payroll_beneficiary_alias(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.learn_payroll_beneficiary_alias(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.learn_payroll_beneficiary_alias(uuid,text)',
    'EXECUTE'
  ),
  'only authenticated ERP callers can execute alias learning'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.payroll_beneficiary_aliases',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_beneficiary_aliases',
    'INSERT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_beneficiary_aliases',
    'UPDATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.payroll_beneficiary_aliases',
    'DELETE'
  ),
  'authenticated clients read aliases through RLS but mutate only through the command'
);

select ok(
  (
    select table_row.relrowsecurity
    from pg_catalog.pg_class table_row
    where table_row.oid =
      'public.payroll_beneficiary_aliases'::regclass
  ),
  'beneficiary aliases retain row-level security'
);

select throws_ok(
  $$
    select public.learn_payroll_beneficiary_alias(
      '7f291900-0000-4000-8000-000000000201',
      'Unauthenticated beneficiary'
    )
  $$,
  '28000',
  'payroll_alias_authentication_required',
  'the command requires an authenticated actor'
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
    '7f291900-0000-4000-8000-000000000001',
    'Alias Learning Tenant A',
    'alias-learning-a',
    'alias-learning-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7f291900-0000-4000-8000-000000000002',
    'Alias Learning Tenant B',
    'alias-learning-b',
    'alias-learning-b@example.invalid',
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
    '7f291900-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'alias-manager-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f291900-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'alias-worker-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '7f291900-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'alias-manager-b@example.invalid',
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
  status
)
values
  (
    '7f291900-0000-4000-8000-000000000201',
    '7f291900-0000-4000-8000-000000000001',
    'ALIAS-A-201',
    'Vicente',
    'Díaz',
    'Manager',
    'active'
  ),
  (
    '7f291900-0000-4000-8000-000000000202',
    '7f291900-0000-4000-8000-000000000001',
    'ALIAS-A-202',
    'Lucas',
    'Reyes',
    'Mechanic',
    'active'
  ),
  (
    '7f291900-0000-4000-8000-000000000203',
    '7f291900-0000-4000-8000-000000000002',
    'ALIAS-B-203',
    'Tenant',
    'Two',
    'Mechanic',
    'active'
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
    '7f291900-0000-4000-8000-000000000111',
    '7f291900-0000-4000-8000-000000000101',
    '7f291900-0000-4000-8000-000000000001',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  ),
  (
    '7f291900-0000-4000-8000-000000000112',
    '7f291900-0000-4000-8000-000000000102',
    '7f291900-0000-4000-8000-000000000001',
    null,
    'cashier',
    '{}'::jsonb,
    true
  ),
  (
    '7f291900-0000-4000-8000-000000000113',
    '7f291900-0000-4000-8000-000000000103',
    '7f291900-0000-4000-8000-000000000002',
    null,
    'accountant',
    '{"access_accounting":true}'::jsonb,
    true
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"7f291900-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f291900-0000-4000-8000-000000000102',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.learn_payroll_beneficiary_alias(
      '7f291900-0000-4000-8000-000000000201',
      'Vicente Díaz'
    )
  $$,
  '42501',
  'payroll_alias_not_authorized',
  'an ERP member without payroll authority cannot learn aliases'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"7f291900-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f291900-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.learn_payroll_beneficiary_alias(
      '7f291900-0000-4000-8000-000000000203',
      'Cross tenant employee'
    )
  $$,
  '23503',
  'payroll_alias_employee_not_found',
  'a payroll manager cannot target an employee in another tenant'
);

select throws_ok(
  $$
    select public.learn_payroll_beneficiary_alias(
      null,
      'Missing employee'
    )
  $$,
  '22023',
  'payroll_alias_invalid',
  'the command rejects a missing employee identifier'
);

select set_config(
  'test.alias.created_receipt',
  public.learn_payroll_beneficiary_alias(
    '7f291900-0000-4000-8000-000000000201',
    'Vicente Díaz'
  )::text,
  true
);

select is(
  current_setting('test.alias.created_receipt')::jsonb->>'status',
  'created',
  'the first explicit alias opt-in creates the identity'
);
select is(
  current_setting('test.alias.created_receipt')::jsonb->>'employee_id',
  '7f291900-0000-4000-8000-000000000201',
  'the creation receipt identifies the selected employee'
);
select is(
  current_setting('test.alias.created_receipt')::jsonb->>'normalized_alias',
  'vicente diaz',
  'the command normalizes accents and case server-side'
);

select set_config(
  'test.alias.existing_receipt',
  public.learn_payroll_beneficiary_alias(
    '7f291900-0000-4000-8000-000000000201',
    '  VICENTE   DÍAZ  '
  )::text,
  true
);

select is(
  current_setting('test.alias.existing_receipt')::jsonb->>'status',
  'existing',
  'the same normalized alias is idempotent for the same employee'
);
select is(
  (select count(*)::integer from public.payroll_beneficiary_aliases),
  1,
  'idempotent replay creates no duplicate alias row'
);

select set_config(
  'test.alias.conflict_receipt',
  public.learn_payroll_beneficiary_alias(
    '7f291900-0000-4000-8000-000000000202',
    'VICENTE DIAZ'
  )::text,
  true
);

select is(
  current_setting('test.alias.conflict_receipt')::jsonb->>'status',
  'conflict',
  'the same normalized alias conflicts for a different employee'
);
select is(
  (
    select employee_id::text
    from public.payroll_beneficiary_aliases
    where normalized_alias = 'vicente diaz'
  ),
  '7f291900-0000-4000-8000-000000000201',
  'a conflict never reassigns the existing alias'
);

select throws_ok(
  $$
    insert into public.payroll_beneficiary_aliases (
      tenant_id,
      employee_id,
      alias
    )
    values (
      '7f291900-0000-4000-8000-000000000001',
      '7f291900-0000-4000-8000-000000000202',
      'Direct insert denied'
    )
  $$,
  '42501',
  null,
  'authenticated callers cannot bypass the RPC with a direct insert'
);
select throws_ok(
  $$
    update public.payroll_beneficiary_aliases
    set employee_id = '7f291900-0000-4000-8000-000000000202'
    where normalized_alias = 'vicente diaz'
  $$,
  '42501',
  null,
  'authenticated callers cannot directly reassign an alias'
);
select throws_ok(
  $$
    delete from public.payroll_beneficiary_aliases
    where normalized_alias = 'vicente diaz'
  $$,
  '42501',
  null,
  'authenticated callers cannot directly delete an alias'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"7f291900-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7f291900-0000-4000-8000-000000000103',
  true
);
set local role authenticated;

select set_config(
  'test.alias.tenant_b_receipt',
  public.learn_payroll_beneficiary_alias(
    '7f291900-0000-4000-8000-000000000203',
    'VICENTE DIAZ'
  )::text,
  true
);

select is(
  current_setting('test.alias.tenant_b_receipt')::jsonb->>'status',
  'created',
  'the same normalized text may identify a tenant-local employee elsewhere'
);
select is(
  (select count(*)::integer from public.payroll_beneficiary_aliases),
  1,
  'RLS exposes only the signed-in tenant alias'
);
select is(
  (
    select employee_id::text
    from public.payroll_beneficiary_aliases
    where normalized_alias = 'vicente diaz'
  ),
  '7f291900-0000-4000-8000-000000000203',
  'the second tenant owns its independent alias mapping'
);

select throws_ok(
  $$
    select public.learn_payroll_beneficiary_alias(
      '7f291900-0000-4000-8000-000000000201',
      'Cross tenant reassignment'
    )
  $$,
  '23503',
  'payroll_alias_employee_not_found',
  'a second-tenant manager cannot target the first tenant employee'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select is(
  (
    select count(*)::integer
    from public.payroll_beneficiary_aliases
    where normalized_alias = 'vicente diaz'
  ),
  2,
  'tenant-local aliases coexist without overwriting each other'
);
select ok(
  exists (
    select 1
    from public.payroll_beneficiary_aliases
    where tenant_id = '7f291900-0000-4000-8000-000000000001'
      and employee_id = '7f291900-0000-4000-8000-000000000201'
      and normalized_alias = 'vicente diaz'
  )
  and exists (
    select 1
    from public.payroll_beneficiary_aliases
    where tenant_id = '7f291900-0000-4000-8000-000000000002'
      and employee_id = '7f291900-0000-4000-8000-000000000203'
      and normalized_alias = 'vicente diaz'
  ),
  'cross-tenant learning preserves both original employee owners'
);

select * from finish();
rollback;
