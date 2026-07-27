begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select col_not_null(
  'public',
  'employees',
  'tenant_id',
  'every employee belongs to one tenant'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.user_profiles'::regclass
      and constraint_row.conname = 'user_profiles_employee_tenant_fkey'
      and constraint_row.confrelid = 'public.employees'::regclass
      and constraint_row.conkey = array[
        (
          select attribute.attnum
          from pg_attribute attribute
          where attribute.attrelid = 'public.user_profiles'::regclass
            and attribute.attname = 'employee_id'
        ),
        (
          select attribute.attnum
          from pg_attribute attribute
          where attribute.attrelid = 'public.user_profiles'::regclass
            and attribute.attname = 'tenant_id'
        )
      ]::smallint[]
  ),
  'ERP profile employee links enforce tenant agreement'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.user_invitations'::regclass
      and constraint_row.conname = 'user_invitations_employee_tenant_fkey'
      and constraint_row.confrelid = 'public.employees'::regclass
  ),
  'invitation employee links enforce tenant agreement'
);
select ok(
  exists (
    select 1
    from pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'employees_one_erp_user_uidx'
      and index_row.indexdef like '%UNIQUE INDEX%'
  ),
  'one ERP Auth user can link to at most one employee'
);
select ok(
  exists (
    select 1
    from pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname = 'user_profiles_one_erp_employee_uidx'
      and index_row.indexdef like '%UNIQUE INDEX%'
  ),
  'one employee can retain at most one ERP profile link, active or inactive'
);
select ok(
  exists (
    select 1
    from pg_indexes index_row
    where index_row.schemaname = 'public'
      and index_row.indexname =
        'user_invitations_one_pending_employee_uidx'
      and index_row.indexdef like '%UNIQUE INDEX%'
  ),
  'one employee can have at most one pending ERP invitation'
);
select has_function(
  'public',
  'link_erp_user_to_employee',
  array['uuid', 'uuid'],
  'linking an existing ERP identity is a canonical command'
);
select has_function(
  'public',
  'unlink_erp_user_from_employee',
  array['uuid', 'uuid'],
  'unlinking an ERP identity is a canonical command'
);
select has_function(
  'public',
  'deactivate_and_unlink_erp_user',
  array['uuid', 'uuid'],
  'tenant staff removal is one atomic unlink and deactivate command'
);
select has_function(
  'public',
  'retire_employee',
  array['uuid'],
  'employee retirement is the canonical soft-delete command'
);
select has_function(
  'public',
  'get_my_erp_profile',
  array[]::text[],
  'ERP users have one tenant-safe self context RPC'
);
select has_function(
  'public',
  'update_my_employee_contact',
  array['jsonb'],
  'ERP users have one allowlisted self-contact RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.link_erp_user_to_employee(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.link_erp_user_to_employee(uuid,uuid)',
    'EXECUTE'
  ),
  'only authenticated callers can invoke the link command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.update_my_employee_contact(jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.update_my_employee_contact(jsonb)',
    'EXECUTE'
  ),
  'self-contact mutation is unavailable to anonymous callers'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.deactivate_and_unlink_erp_user(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.deactivate_and_unlink_erp_user(uuid,uuid)',
    'EXECUTE'
  ),
  'only authenticated administrators can request atomic staff detach'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.retire_employee(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.retire_employee(uuid)',
    'EXECUTE'
  ),
  'employee retirement is authenticated and DB-authorized'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.employees',
    'DELETE'
  ),
  'application callers cannot physically delete employee history'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.assert_erp_employee_link_actor(uuid,uuid)',
    'EXECUTE'
  ),
  'the DB hierarchy assertion is an internal primitive'
);
select has_trigger(
  'public',
  'user_invitations',
  'trg_guard_erp_invitation_employee_access',
  'pending invitations serialize against employee access state'
);
select has_trigger(
  'public',
  'employees',
  'trg_deactivate_linked_erp_access_on_employee_exit',
  'employee separation deactivates linked ERP authority'
);
select has_trigger(
  'public',
  'employees',
  'trg_guard_employee_retirement_transition',
  'terminated status is reserved for the canonical retirement command'
);

-- Isolated runtime fixtures. Replica mode bypasses unrelated bootstrap and
-- notification triggers only while deterministic seed state is installed.
set local session_replication_role = replica;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  owner_email,
  is_active
)
values
  (
    '9f27a000-0000-4000-8000-000000000001',
    'Employee Access Tenant A',
    'employee-access-a',
    'owner-access-a@example.invalid',
    true
  ),
  (
    '9f27a000-0000-4000-8000-000000000002',
    'Employee Access Tenant B',
    'employee-access-b',
    'owner-access-b@example.invalid',
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
    '9f27a000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'owner-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_owner","tenant_id":"9f27a000-0000-4000-8000-000000000001","role":"admin"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'admin-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27a000-0000-4000-8000-000000000001","role":"admin"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'manager-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27a000-0000-4000-8000-000000000001","role":"manager"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000104',
    'authenticated',
    'authenticated',
    'cashier-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27a000-0000-4000-8000-000000000001","role":"cashier"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000105',
    'authenticated',
    'authenticated',
    'leave-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27a000-0000-4000-8000-000000000001","role":"cashier"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000106',
    'authenticated',
    'authenticated',
    'worker-access-a@worker-login.invalid',
    '',
    now(),
    '{"account_type":"worker_portal","tenant_id":"9f27a000-0000-4000-8000-000000000001","employee_id":"9f27a000-0000-4000-8000-000000000204","role":"worker"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000107',
    'authenticated',
    'authenticated',
    'invitee-access-a@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000108',
    'authenticated',
    'authenticated',
    'metadata-spoof-access-a@example.invalid',
    '',
    now(),
    '{"account_type":"public_store_customer"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000109',
    'authenticated',
    'authenticated',
    'historical-employee-access-a@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000201',
    'authenticated',
    'authenticated',
    'staff-access-b@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27a000-0000-4000-8000-000000000002","role":"cashier"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
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
    '9f27a000-0000-4000-8000-000000000301',
    '9f27a000-0000-4000-8000-000000000101',
    '9f27a000-0000-4000-8000-000000000001',
    'admin',
    '{"manage_users":true}'::jsonb,
    true,
    '9f27a000-0000-4000-8000-000000000206'
  ),
  (
    '9f27a000-0000-4000-8000-000000000302',
    '9f27a000-0000-4000-8000-000000000102',
    '9f27a000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true,
    '9f27a000-0000-4000-8000-000000000207'
  ),
  (
    '9f27a000-0000-4000-8000-000000000303',
    '9f27a000-0000-4000-8000-000000000103',
    '9f27a000-0000-4000-8000-000000000001',
    'manager',
    '{"manage_users":true}'::jsonb,
    true,
    '9f27a000-0000-4000-8000-000000000210'
  ),
  (
    '9f27a000-0000-4000-8000-000000000304',
    '9f27a000-0000-4000-8000-000000000104',
    '9f27a000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    null
  ),
  (
    '9f27a000-0000-4000-8000-000000000305',
    '9f27a000-0000-4000-8000-000000000105',
    '9f27a000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '9f27a000-0000-4000-8000-000000000205'
  ),
  (
    '9f27a000-0000-4000-8000-000000000308',
    '9f27a000-0000-4000-8000-000000000108',
    '9f27a000-0000-4000-8000-000000000001',
    'cashier',
    '{}'::jsonb,
    true,
    '9f27a000-0000-4000-8000-000000000208'
  ),
  (
    '9f27a000-0000-4000-8000-000000000321',
    '9f27a000-0000-4000-8000-000000000201',
    '9f27a000-0000-4000-8000-000000000002',
    'cashier',
    '{}'::jsonb,
    true,
    null
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
    '9f27a000-0000-4000-8000-000000000201',
    '9f27a000-0000-4000-8000-000000000001',
    null,
    'ACCESS-201',
    'Available',
    'Employee',
    'available-access-a@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000202',
    '9f27a000-0000-4000-8000-000000000001',
    null,
    'ACCESS-202',
    'Pending',
    'Employee',
    'pending-access-a@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000203',
    '9f27a000-0000-4000-8000-000000000001',
    null,
    'ACCESS-203',
    'Invitation',
    'Employee',
    'invitee-access-a@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000204',
    '9f27a000-0000-4000-8000-000000000001',
    null,
    'ACCESS-204',
    'Worker',
    'Employee',
    null,
    'Mechanic',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000205',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000105',
    'ACCESS-205',
    'Leave',
    'Employee',
    'leave-access-a@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000206',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000101',
    'ACCESS-206',
    'Owner',
    'Employee',
    'owner-access-a@example.invalid',
    'Owner',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000207',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000102',
    'ACCESS-207',
    'Administrator',
    'Employee',
    'admin-access-a@example.invalid',
    'Administrator',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000208',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000108',
    'ACCESS-208',
    'Metadata',
    'Spoof',
    'metadata-spoof-access-a@example.invalid',
    'Cashier',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000209',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000109',
    'ACCESS-209',
    'Historical',
    'Identity',
    'historical-employee-access-a@example.invalid',
    'Cashier',
    'inactive'
  ),
  (
    '9f27a000-0000-4000-8000-000000000210',
    '9f27a000-0000-4000-8000-000000000001',
    '9f27a000-0000-4000-8000-000000000103',
    'ACCESS-210',
    'Manager',
    'Employee',
    'manager-access-a@example.invalid',
    'Manager',
    'active'
  ),
  (
    '9f27a000-0000-4000-8000-000000000221',
    '9f27a000-0000-4000-8000-000000000002',
    null,
    'ACCESS-221',
    'Tenant B',
    'Employee',
    'employee-access-b@example.invalid',
    'Cashier',
    'active'
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
  '9f27a000-0000-4000-8000-000000000401',
  '9f27a000-0000-4000-8000-000000000001',
  '9f27a000-0000-4000-8000-000000000204',
  '9f27a000-0000-4000-8000-000000000106',
  'worker.access',
  'worker-access-a@worker-login.invalid',
  true,
  true
);

insert into auth.sessions (
  id,
  user_id,
  created_at,
  updated_at
)
values (
  '9f27a000-0000-4000-8000-000000000601',
  '9f27a000-0000-4000-8000-000000000106',
  now(),
  now()
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  employee_id,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values
  (
    '9f27a000-0000-4000-8000-000000000501',
    '9f27a000-0000-4000-8000-000000000001',
    'pending-access-a@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    '9f27a000-0000-4000-8000-000000000202',
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('p', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000502',
    '9f27a000-0000-4000-8000-000000000001',
    'invitee-access-a@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    '9f27a000-0000-4000-8000-000000000203',
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('i', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000507',
    '9f27a000-0000-4000-8000-000000000001',
    'historical-employee-access-a@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    null,
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('h', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  );

set local session_replication_role = origin;

-- Direct API writes cannot bypass the canonical bidirectional command.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;

select throws_ok(
  $$
    update public.employees
    set user_id = '9f27a000-0000-4000-8000-000000000104'
    where id = '9f27a000-0000-4000-8000-000000000201'
  $$,
  '42501',
  'employee_erp_link_requires_canonical_command',
  'authenticated REST cannot write the employee side directly'
);

select lives_ok(
  $$
    select public.link_erp_user_to_employee(
      '9f27a000-0000-4000-8000-000000000104',
      '9f27a000-0000-4000-8000-000000000201'
    )
  $$,
  'the tenant principal can link an active lower-authority ERP user'
);
select is(
  (
    select employee.user_id
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000201'
  ),
  '9f27a000-0000-4000-8000-000000000104'::uuid,
  'the canonical command writes the employee side'
);
select is(
  (
    select profile.employee_id
    from public.user_profiles profile
    where profile.user_id = '9f27a000-0000-4000-8000-000000000104'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
  ),
  '9f27a000-0000-4000-8000-000000000201'::uuid,
  'the canonical command writes the profile side'
);
select is(
  (
    select count(*)::integer
    from public.user_activity_log activity
    where activity.action = 'employee_erp_identity_linked'
      and activity.user_id =
        '9f27a000-0000-4000-8000-000000000104'
      and activity.details->>'employee_id' =
        '9f27a000-0000-4000-8000-000000000201'
  ),
  1,
  'linking emits one immutable actor-attributed audit receipt'
);

-- DB authorization remains final even when callers skip the Edge function.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000103',
  true
);
select throws_ok(
  $$
    select public.link_erp_user_to_employee(
      '9f27a000-0000-4000-8000-000000000102',
      '9f27a000-0000-4000-8000-000000000203'
    )
  $$,
  '42501',
  'staff_hierarchy_forbidden',
  'a manager cannot bypass Edge to mutate an administrator'
);
select throws_ok(
  $$
    select public.link_erp_user_to_employee(
      '9f27a000-0000-4000-8000-000000000101',
      '9f27a000-0000-4000-8000-000000000203'
    )
  $$,
  '42501',
  'principal_owner_protected',
  'a manager cannot bypass Edge to mutate the tenant principal'
);
select throws_ok(
  $$
    select public.deactivate_and_unlink_erp_user(
      '9f27a000-0000-4000-8000-000000000103',
      '9f27a000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'self_detach_forbidden',
  'a manager cannot bypass Edge to detach their own tenant access'
);

-- Suspension keeps the historical link, but exact unlink remains available.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;
select throws_ok(
  $$
    select public.deactivate_and_unlink_erp_user(
      '9f27a000-0000-4000-8000-000000000101',
      '9f27a000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'self_detach_forbidden',
  'the principal cannot orphan the tenant by directly detaching themselves'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000201","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000201',
  true
);
select throws_ok(
  $$
    select public.deactivate_and_unlink_erp_user(
      '9f27a000-0000-4000-8000-000000000104',
      '9f27a000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'employee_access_management_denied',
  'a foreign tenant caller cannot probe an existing target membership'
);
select throws_ok(
  $$
    select public.deactivate_and_unlink_erp_user(
      'ffffffff-ffff-4fff-8fff-ffffffffffff',
      '9f27a000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'employee_access_management_denied',
  'a foreign tenant caller receives the same error for a missing target'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
select throws_ok(
  $$
    select public.link_erp_user_to_employee(
      '9f27a000-0000-4000-8000-000000000104',
      '9f27a000-0000-4000-8000-000000000221'
    )
  $$,
  'P0001',
  'employee_not_found',
  'link lookup scopes a real foreign employee to the caller tenant'
);
select throws_ok(
  $$
    select public.link_erp_user_to_employee(
      '9f27a000-0000-4000-8000-000000000104',
      'ffffffff-ffff-4fff-8fff-ffffffffffff'
    )
  $$,
  'P0001',
  'employee_not_found',
  'link lookup returns the same result for a missing employee'
);
reset role;
update public.user_profiles
set is_active = false
where user_id = '9f27a000-0000-4000-8000-000000000104'
  and tenant_id = '9f27a000-0000-4000-8000-000000000001';
set local role authenticated;

select lives_ok(
  $$
    select public.unlink_erp_user_from_employee(
      '9f27a000-0000-4000-8000-000000000104',
      '9f27a000-0000-4000-8000-000000000201'
    )
  $$,
  'an administrator can explicitly unlink a suspended exact profile'
);
select ok(
  (
    select employee.user_id is null
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000201'
  )
  and (
    select profile.employee_id is null
    from public.user_profiles profile
    where profile.user_id =
      '9f27a000-0000-4000-8000-000000000104'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
  ),
  'unlink clears both live identity pointers without deleting history'
);

-- Worker and invitation reservations are mutually exclusive in both orders.
reset role;
select throws_ok(
  $$
    insert into public.user_invitations (
      tenant_id,
      email,
      role,
      permissions,
      invited_by,
      employee_id,
      status,
      expires_at
    )
    values (
      '9f27a000-0000-4000-8000-000000000001',
      'worker-conflict@example.invalid',
      'cashier',
      '{}'::jsonb,
      '9f27a000-0000-4000-8000-000000000101',
      '9f27a000-0000-4000-8000-000000000204',
      'pending',
      now() + interval '7 days'
    )
  $$,
  'P0001',
  'worker_access_conflict',
  'an employee with active Worker access cannot receive an ERP invitation'
);
select throws_ok(
  $$
    insert into public.employee_portal_accounts (
      tenant_id,
      employee_id,
      auth_user_id,
      username,
      login_email,
      is_active,
      must_reset_password
    )
    values (
      '9f27a000-0000-4000-8000-000000000001',
      '9f27a000-0000-4000-8000-000000000202',
      '9f27a000-0000-4000-8000-000000000106',
      'pending.worker',
      'pending-worker@worker-login.invalid',
      true,
      true
    )
  $$,
  'P0001',
  'worker_access_conflict',
  'a pending ERP invitation blocks Worker creation'
);

-- Retirement is a single tenant-authorized, hierarchy-aware, retry-safe
-- lifecycle command. Neither REST nor a forged command marker may manufacture
-- the terminal status directly.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;
select set_config(
  'app.employee_retirement_command',
  'true',
  true
);
select throws_ok(
  $$
    update public.employees
    set status = 'terminated'
    where id = '9f27a000-0000-4000-8000-000000000201'
  $$,
  '42501',
  'employee_retirement_requires_canonical_command',
  'an API role cannot forge the retirement command marker'
);
select set_config(
  'app.employee_retirement_command',
  '',
  true
);
select is_empty(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000221'
    returning id
  $$,
  'a direct inactive update cannot see an employee from another tenant'
);
select is_empty(
  $$
    update public.employees
    set status = 'inactive'
    where id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
    returning id
  $$,
  'a missing employee produces the same direct-update result'
);
select throws_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000206'
  $$,
  '42501',
  'self_detach_forbidden',
  'the principal cannot directly deactivate their own linked employee'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000103',
  true
);
select throws_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000210'
  $$,
  '42501',
  'self_detach_forbidden',
  'a manager cannot directly deactivate their own linked employee'
);
select throws_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000206'
  $$,
  '42501',
  'principal_owner_protected',
  'a manager cannot directly deactivate the tenant principal'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000102","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000102',
  true
);
select throws_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000206'
  $$,
  '42501',
  'principal_owner_protected',
  'an administrator cannot directly deactivate the tenant principal'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000108","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000108',
  true
);
select throws_ok(
  $$
    select public.retire_employee(
      '9f27a000-0000-4000-8000-000000000201'
    )
  $$,
  'P0001',
  'employee_not_found',
  'an active non-manager cannot retire an employee'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
select throws_ok(
  $$
    select public.retire_employee(
      '9f27a000-0000-4000-8000-000000000221'
    )
  $$,
  'P0001',
  'employee_not_found',
  'a tenant owner cannot retire an employee from another tenant'
);
select throws_ok(
  $$
    select public.retire_employee(
      '9f27a000-0000-4000-8000-000000000206'
    )
  $$,
  '42501',
  'self_detach_forbidden',
  'the tenant owner cannot retire their own linked employee identity'
);
select lives_ok(
  $$
    select public.unlink_erp_user_from_employee(
      '9f27a000-0000-4000-8000-000000000101',
      '9f27a000-0000-4000-8000-000000000206'
    )
  $$,
  'the owner can explicitly remove their own test employee link afterward'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000103","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000103',
  true
);
select throws_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000207'
  $$,
  '42501',
  'staff_hierarchy_forbidden',
  'a manager cannot directly deactivate an administrator'
);
select throws_ok(
  $$
    select public.retire_employee(
      '9f27a000-0000-4000-8000-000000000207'
    )
  $$,
  '42501',
  'staff_hierarchy_forbidden',
  'a manager cannot retire an administrator'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
select is(
  (
    public.retire_employee(
      '9f27a000-0000-4000-8000-000000000207'
    )->>'erpProfilesDeactivated'
  )::integer,
  1,
  'retirement reports the linked ERP profile it deactivated'
);
reset role;
select ok(
  (
    select employee.status = 'terminated'
      and employee.termination_date is not null
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000207'
  )
  and not (
    select profile.is_active
    from public.user_profiles profile
    where profile.id = '9f27a000-0000-4000-8000-000000000302'
  ),
  'retirement preserves the ERP link but closes its active authority'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
select is(
  (
    public.retire_employee(
      '9f27a000-0000-4000-8000-000000000204'
    )->>'workerSessionsRevoked'
  )::integer,
  1,
  'retirement revokes every live Worker session in the same transaction'
);
reset role;
select ok(
  (
    select employee.status = 'terminated'
      and employee.termination_date is not null
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000204'
  ),
  'Worker retirement records terminal employment state without deleting HR history'
);
select ok(
  (
    select portal.is_active is false
      and portal.must_reset_password is true
      and portal.password_reset_required_at is not null
      and portal.password_credential_issued_at is null
      and portal.password_reset_challenge_started_at is null
    from public.employee_portal_accounts portal
    where portal.id = '9f27a000-0000-4000-8000-000000000401'
  ),
  'Worker retirement preserves the portal record in a fail-closed state'
);
select is(
  (
    select count(*)::integer
    from auth.sessions auth_session
    where auth_session.user_id =
      '9f27a000-0000-4000-8000-000000000106'
  ),
  0,
  'Worker retirement removes the Auth session'
);
select is(
  (
    select count(*)::integer
    from public.user_activity_log activity
    where activity.action = 'employee_retired'
      and activity.details->>'employee_id' =
        '9f27a000-0000-4000-8000-000000000204'
  ),
  1,
  'Worker retirement emits one immutable audit receipt'
);

set local role authenticated;
select is(
  (
    public.retire_employee(
      '9f27a000-0000-4000-8000-000000000204'
    )->>'alreadyRetired'
  )::boolean,
  true,
  'retrying a fully retired employee returns an explicit idempotent receipt'
);
reset role;
select is(
  (
    select count(*)::integer
    from public.user_activity_log activity
    where activity.action = 'employee_retired'
      and activity.details->>'employee_id' =
        '9f27a000-0000-4000-8000-000000000204'
  ),
  1,
  'a retirement retry does not duplicate the audit receipt'
);
select throws_ok(
  $$
    delete from public.employees
    where id = '9f27a000-0000-4000-8000-000000000204'
  $$,
  '42501',
  'employee_retirement_required',
  'even privileged maintenance cannot hard-delete retained Worker history'
);

set local role authenticated;
select is(
  (
    public.retire_employee(
      '9f27a000-0000-4000-8000-000000000202'
    )->>'pendingInvitationsExpired'
  )::integer,
  1,
  'retirement expires the employee pending invitation'
);
reset role;
select ok(
  (
    select employee.status = 'terminated'
      and employee.termination_date is not null
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000202'
  )
  and (
    select invitation.status = 'expired'
      and invitation.token_hash is null
    from public.user_invitations invitation
    where invitation.id = '9f27a000-0000-4000-8000-000000000501'
  ),
  'invitation retirement closes access and destroys the bearer token'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000105","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000105',
  true
);
set local role authenticated;
select throws_ok(
  $$
    select public.retire_employee(
      '9f27a000-0000-4000-8000-000000000205'
    )
  $$,
  'P0001',
  'employee_not_found',
  'ordinary staff are denied before their target identity is disclosed'
);

-- The owner-defined invitation acceptor can write both guarded columns
-- atomically; an already-active member is never silently consumed as success.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000107","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000107',
  true
);
set local role authenticated;
select lives_ok(
  $$ select public.accept_user_invitation(repeat('i', 48)) $$,
  'a confirmed invitee accepts and links through the owner-defined transaction'
);
reset role;
select ok(
  (
    select employee.user_id =
      '9f27a000-0000-4000-8000-000000000107'::uuid
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000203'
  )
  and exists (
    select 1
    from public.user_profiles profile
    where profile.user_id =
      '9f27a000-0000-4000-8000-000000000107'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
      and profile.employee_id =
        '9f27a000-0000-4000-8000-000000000203'
      and profile.is_active is true
  )
  and exists (
    select 1
    from public.user_invitations invitation
    where invitation.id = '9f27a000-0000-4000-8000-000000000502'
      and invitation.status = 'accepted'
      and invitation.accepted_user_id =
        '9f27a000-0000-4000-8000-000000000107'
      and invitation.token_hash is null
  ),
  'invitation acceptance persists the exact bidirectional link and receipt'
);
select is(
  (
    select auth_user.raw_app_meta_data->>'account_type'
    from auth.users auth_user
    where auth_user.id = '9f27a000-0000-4000-8000-000000000107'
  ),
  'erp_staff',
  'invitation acceptance establishes server-owned ERP Auth metadata'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;
select lives_ok(
  $$
    select public.deactivate_and_unlink_erp_user(
      '9f27a000-0000-4000-8000-000000000107',
      '9f27a000-0000-4000-8000-000000000001'
    )
  $$,
  'atomic staff detach unlinks and deactivates a linked invited user'
);
reset role;
select ok(
  (
    select employee.user_id is null
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000203'
  )
  and exists (
    select 1
    from public.user_profiles profile
    where profile.user_id =
      '9f27a000-0000-4000-8000-000000000107'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
      and profile.employee_id is null
      and profile.is_active is false
  )
  and exists (
    select 1
    from public.user_activity_log activity
    where activity.action = 'erp_tenant_access_deactivated'
      and activity.user_id =
        '9f27a000-0000-4000-8000-000000000107'
      and activity.details->>'employee_unlinked' = 'true'
  ),
  'atomic staff detach commits both link pointers, profile state, and audit together'
);

set local session_replication_role = replica;
insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  employee_id,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values (
  '9f27a000-0000-4000-8000-000000000503',
  '9f27a000-0000-4000-8000-000000000001',
  'owner-access-a@example.invalid',
  'cashier',
  '{}'::jsonb,
  '9f27a000-0000-4000-8000-000000000101',
  null,
  'pending',
  now() + interval '7 days',
  encode(
    extensions.digest(
      convert_to(repeat('o', 48), 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now()
);
set local session_replication_role = origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
set local role authenticated;
select throws_ok(
  $$ select public.accept_user_invitation(repeat('o', 48)) $$,
  'P0001',
  'active_staff_email_requires_direct_link',
  'an active member cannot silently consume another invitation'
);

reset role;
set local session_replication_role = replica;
insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  employee_id,
  status,
  expires_at,
  token_hash,
  token_issued_at
)
values
  (
    '9f27a000-0000-4000-8000-000000000504',
    '9f27a000-0000-4000-8000-000000000001',
    'cashier-access-a@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    null,
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('s', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000505',
    '9f27a000-0000-4000-8000-000000000001',
    'staff-access-b@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    null,
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('f', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  ),
  (
    '9f27a000-0000-4000-8000-000000000506',
    '9f27a000-0000-4000-8000-000000000001',
    'worker-access-a@worker-login.invalid',
    'cashier',
    '{}'::jsonb,
    '9f27a000-0000-4000-8000-000000000101',
    null,
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('w', 48), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now()
  );
update public.employee_portal_accounts
set is_active = false
where id = '9f27a000-0000-4000-8000-000000000401';
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000104","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000104',
  true
);
set local role authenticated;
select throws_ok(
  $$ select public.accept_user_invitation(repeat('s', 48)) $$,
  'P0001',
  'staff_membership_inactive',
  'a suspended same-tenant membership cannot accept an impossible invitation'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000201","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000201',
  true
);
select throws_ok(
  $$ select public.accept_user_invitation(repeat('f', 48)) $$,
  'P0001',
  'identity_unavailable',
  'an identity with another active tenant cannot accept an impossible invitation'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000106","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000106',
  true
);
select throws_ok(
  $$ select public.accept_user_invitation(repeat('w', 48)) $$,
  'P0001',
  'identity_unavailable',
  'a Worker Auth identity cannot accept ERP access even while suspended'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000109","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000109',
  true
);
select throws_ok(
  $$ select public.accept_user_invitation(repeat('h', 48)) $$,
  'P0001',
  'identity_unavailable',
  'a global historical employee identity cannot accept even an unbound invitation'
);

-- Self-service context is exact, allowlisted, and ignores forged metadata.
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000105","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000105',
  true
);
select is(
  public.get_my_erp_profile()->'employee'->>'id',
  '9f27a000-0000-4000-8000-000000000205',
  'self context resolves only the exact bidirectional employee link'
);
select is(
  public.update_my_employee_contact(
    '{"phone":" +56 9 1111 2222 ","city":" Viña del Mar "}'::jsonb
  )->>'phone',
  '+56 9 1111 2222',
  'self contact update trims and returns an allowlisted field'
);
select is(
  (
    select employee.city
    from public.employees employee
    where employee.id = '9f27a000-0000-4000-8000-000000000205'
  ),
  'Viña del Mar',
  'self contact update persists only the linked employee row'
);
select throws_ok(
  $$ select public.update_my_employee_contact('{}'::jsonb) $$,
  'P0001',
  'invalid_employee_contact_patch',
  'the empty patch is rejected at runtime'
);
select throws_ok(
  $$
    select public.update_my_employee_contact(
      '{"job_title":"Owner"}'::jsonb
    )
  $$,
  'P0001',
  'invalid_employee_contact_patch',
  'self service cannot mutate role or HR-owned fields'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000108","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000108',
  true
);
select throws_ok(
  $$ select public.get_my_erp_profile() $$,
  'P0001',
  'erp_profile_context_invalid',
  'a DB profile alone cannot bypass the server-owned ERP account type'
);
select throws_ok(
  $$
    select public.update_my_employee_contact(
      '{"phone":"+56 9 9999 9999"}'::jsonb
    )
  $$,
  'P0001',
  'erp_profile_context_invalid',
  'forged or non-ERP metadata cannot bypass self-contact authorization'
);

-- `on_leave` retains the exact link and access context but contact mutation is
-- read-only until the employee is active again. Separation deactivates access
-- while retaining an explicitly unlinkable historical identity.
reset role;
update public.employees
set status = 'on_leave'
where id = '9f27a000-0000-4000-8000-000000000205';
select ok(
  (
    select profile.is_active
    from public.user_profiles profile
    where profile.user_id =
      '9f27a000-0000-4000-8000-000000000105'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
  ),
  'on-leave employees retain ERP access'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000105","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000105',
  true
);
select throws_ok(
  $$
    select public.update_my_employee_contact(
      '{"phone":"+56 9 3333 4444"}'::jsonb
    )
  $$,
  'P0001',
  'erp_employee_link_inconsistent',
  'on-leave self contact is deliberately read-only'
);
select is_empty(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000205'
    returning id
  $$,
  'non-manager ERP staff cannot reach their own employee update row'
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27a000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f27a000-0000-4000-8000-000000000101',
  true
);
select lives_ok(
  $$
    update public.employees
    set status = 'inactive'
    where id = '9f27a000-0000-4000-8000-000000000205'
  $$,
  'the tenant principal can directly deactivate lower-authority ERP staff'
);
reset role;
select ok(
  not (
    select profile.is_active
    from public.user_profiles profile
    where profile.user_id =
      '9f27a000-0000-4000-8000-000000000105'
      and profile.tenant_id =
        '9f27a000-0000-4000-8000-000000000001'
  ),
  'inactive employee lifecycle deactivates the linked ERP profile'
);
select is(
  (
    select count(*)::integer
    from public.user_activity_log activity
    where activity.action = 'employee_erp_access_deactivated'
      and activity.user_id =
        '9f27a000-0000-4000-8000-000000000105'
      and activity.details->>'employee_status' = 'inactive'
  ),
  1,
  'employee separation writes one deactivation audit receipt'
);

-- Composite tenant FK rejects a profile-side tenant leak.
select throws_ok(
  $$
    insert into public.user_profiles (
      user_id,
      tenant_id,
      role,
      permissions,
      is_active,
      employee_id
    )
    values (
      '9f27a000-0000-4000-8000-000000000107',
      '9f27a000-0000-4000-8000-000000000002',
      'cashier',
      '{}'::jsonb,
      false,
      '9f27a000-0000-4000-8000-000000000201'
    )
  $$,
  '23503',
  'insert or update on table "user_profiles" violates foreign key constraint "user_profiles_employee_tenant_fkey"',
  'a cross-tenant employee/profile link is rejected by the database'
);

select * from finish();
rollback;
