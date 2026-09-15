begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_function(
  'public',
  'switch_worker_to_erp_user',
  array['uuid', 'uuid'],
  'Worker to ERP is one canonical transition command'
);
select has_function(
  'public',
  'switch_erp_user_to_worker',
  array['uuid', 'uuid', 'uuid'],
  'ERP to Worker is one canonical transition command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.switch_worker_to_erp_user(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.switch_erp_user_to_worker(uuid,uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.switch_worker_to_erp_user(uuid,uuid)',
    'EXECUTE'
  ),
  'access transitions are authenticated and database-authorized'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.prepare_worker_transition_credential(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.prepare_worker_transition_credential(uuid,uuid)',
    'EXECUTE'
  ),
  'only the trusted provisioning service prepares Worker credentials'
);
select has_trigger(
  'public',
  'employees',
  'trg_guard_company_principal_employee_link',
  'the company principal can never become an employee login'
);

set local session_replication_role = replica;

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  owner_email,
  is_active
) values (
  '9f27b000-0000-4000-8000-000000000001',
  'Employee Transition Tenant',
  'employee-transition-tenant',
  'transition-owner@example.invalid',
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
) values
  (
    '9f27b000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'transition-owner@example.invalid',
    '',
    now(),
    '{"account_type":"erp_owner","tenant_id":"9f27b000-0000-4000-8000-000000000001","role":"admin"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'historical-erp-one@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27b000-0000-4000-8000-000000000001","role":"mechanic"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000103',
    'authenticated',
    'authenticated',
    'active-erp-two@example.invalid',
    '',
    now(),
    '{"account_type":"erp_staff","tenant_id":"9f27b000-0000-4000-8000-000000000001","role":"mechanic"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000111',
    'authenticated',
    'authenticated',
    'worker-one@worker-login.invalid',
    '',
    now(),
    '{"account_type":"worker_portal","tenant_id":"9f27b000-0000-4000-8000-000000000001","employee_id":"9f27b000-0000-4000-8000-000000000201","role":"worker"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000112',
    'authenticated',
    'authenticated',
    'worker-two@worker-login.invalid',
    '',
    now(),
    '{"account_type":"worker_portal","tenant_id":"9f27b000-0000-4000-8000-000000000001","employee_id":"9f27b000-0000-4000-8000-000000000202","role":"worker"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000113',
    'authenticated',
    'authenticated',
    'worker-three@worker-login.invalid',
    '',
    now(),
    '{"account_type":"worker_portal","tenant_id":"9f27b000-0000-4000-8000-000000000001","employee_id":"9f27b000-0000-4000-8000-000000000203","role":"worker"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000114',
    'authenticated',
    'authenticated',
    'worker-four@worker-login.invalid',
    '',
    now(),
    '{"account_type":"worker_portal","tenant_id":"9f27b000-0000-4000-8000-000000000001","employee_id":"9f27b000-0000-4000-8000-000000000204","role":"worker"}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000115',
    'authenticated',
    'authenticated',
    'worker-three-erp@example.invalid',
    '',
    now(),
    '{}'::jsonb,
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
  job_title,
  status
) values
  (
    '9f27b000-0000-4000-8000-000000000201',
    '9f27b000-0000-4000-8000-000000000001',
    null,
    'TRANSITION-201',
    'Worker',
    'One',
    'Mechanic',
    'active'
  ),
  (
    '9f27b000-0000-4000-8000-000000000202',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000103',
    'TRANSITION-202',
    'ERP',
    'Two',
    'Mechanic',
    'active'
  ),
  (
    '9f27b000-0000-4000-8000-000000000203',
    '9f27b000-0000-4000-8000-000000000001',
    null,
    'TRANSITION-203',
    'Worker',
    'Three',
    'Mechanic',
    'active'
  ),
  (
    '9f27b000-0000-4000-8000-000000000204',
    '9f27b000-0000-4000-8000-000000000001',
    null,
    'TRANSITION-204',
    'Worker',
    'Four',
    'Mechanic',
    'active'
  ),
  (
    '9f27b000-0000-4000-8000-000000000205',
    '9f27b000-0000-4000-8000-000000000001',
    null,
    'TRANSITION-205',
    'Available',
    'Employee',
    'Mechanic',
    'active'
  );

insert into public.user_profiles (
  id,
  user_id,
  tenant_id,
  role,
  permissions,
  is_active,
  employee_id
) values
  (
    '9f27b000-0000-4000-8000-000000000301',
    '9f27b000-0000-4000-8000-000000000101',
    '9f27b000-0000-4000-8000-000000000001',
    'admin',
    '{"manage_users":true}'::jsonb,
    true,
    null
  ),
  (
    '9f27b000-0000-4000-8000-000000000302',
    '9f27b000-0000-4000-8000-000000000102',
    '9f27b000-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    false,
    null
  ),
  (
    '9f27b000-0000-4000-8000-000000000303',
    '9f27b000-0000-4000-8000-000000000103',
    '9f27b000-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true,
    '9f27b000-0000-4000-8000-000000000202'
  );

insert into public.employee_portal_accounts (
  id,
  tenant_id,
  employee_id,
  auth_user_id,
  username,
  login_email,
  is_active,
  must_reset_password,
  password_reset_required_at,
  password_credential_issued_at
) values
  (
    '9f27b000-0000-4000-8000-000000000401',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000201',
    '9f27b000-0000-4000-8000-000000000111',
    'worker.one',
    'worker-one@worker-login.invalid',
    true,
    false,
    null,
    null
  ),
  (
    '9f27b000-0000-4000-8000-000000000402',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000202',
    '9f27b000-0000-4000-8000-000000000112',
    'worker.two',
    'worker-two@worker-login.invalid',
    false,
    true,
    now() - interval '1 minute',
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000403',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000203',
    '9f27b000-0000-4000-8000-000000000113',
    'worker.three',
    'worker-three@worker-login.invalid',
    true,
    false,
    null,
    null
  ),
  (
    '9f27b000-0000-4000-8000-000000000404',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000204',
    '9f27b000-0000-4000-8000-000000000114',
    'worker.four',
    'worker-four@worker-login.invalid',
    true,
    false,
    null,
    null
  );

insert into auth.sessions (id, user_id, created_at, updated_at)
values
  (
    '9f27b000-0000-4000-8000-000000000601',
    '9f27b000-0000-4000-8000-000000000111',
    now(),
    now()
  ),
  (
    '9f27b000-0000-4000-8000-000000000602',
    '9f27b000-0000-4000-8000-000000000103',
    now(),
    now()
  );

insert into public.smart_tasks (
  id,
  tenant_id,
  title,
  status,
  priority,
  assigned_to,
  created_by,
  visibility
) values
  (
    '9f27b000-0000-4000-8000-000000000701',
    '9f27b000-0000-4000-8000-000000000001',
    'Worker task that follows the person',
    'pending',
    'normal',
    '9f27b000-0000-4000-8000-000000000111',
    '9f27b000-0000-4000-8000-000000000101',
    'team'
  ),
  (
    '9f27b000-0000-4000-8000-000000000702',
    '9f27b000-0000-4000-8000-000000000001',
    'ERP task that follows the person',
    'in_progress',
    'normal',
    '9f27b000-0000-4000-8000-000000000103',
    '9f27b000-0000-4000-8000-000000000101',
    'team'
  ),
  (
    '9f27b000-0000-4000-8000-000000000703',
    '9f27b000-0000-4000-8000-000000000001',
    'Invitation transition task',
    'pending',
    'normal',
    '9f27b000-0000-4000-8000-000000000113',
    '9f27b000-0000-4000-8000-000000000101',
    'team'
  );

set local session_replication_role = origin;
select set_config(
  'request.jwt.claim.sub',
  '9f27b000-0000-4000-8000-000000000101',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27b000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);

select lives_ok(
  $$select public.switch_worker_to_erp_user(
    '9f27b000-0000-4000-8000-000000000102',
    '9f27b000-0000-4000-8000-000000000201'
  )$$,
  'an active Worker moves atomically to a historical ERP identity'
);
select is(
  (
    select employee.user_id
    from public.employees employee
    where employee.id = '9f27b000-0000-4000-8000-000000000201'
  ),
  '9f27b000-0000-4000-8000-000000000102'::uuid,
  'the employee points to the reactivated ERP identity'
);
select ok(
  exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = '9f27b000-0000-4000-8000-000000000102'
      and profile.employee_id = '9f27b000-0000-4000-8000-000000000201'
      and profile.is_active is true
  )
  and not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = '9f27b000-0000-4000-8000-000000000201'
      and portal.is_active is true
  ),
  'the ERP link and Worker deactivation commit as one authority change'
);
select is(
  (
    select task.assigned_to
    from public.smart_tasks task
    where task.id = '9f27b000-0000-4000-8000-000000000701'
  ),
  '9f27b000-0000-4000-8000-000000000102'::uuid,
  'open work follows the person from Worker to ERP'
);
select ok(
  exists (
    select 1
    from public.smart_task_events event
    where event.task_id = '9f27b000-0000-4000-8000-000000000701'
      and event.event_type = 'assigned'
      and event.payload->>'source' = 'identity_transition'
      and event.payload->>'transition' = 'worker_to_erp_direct'
  ),
  'Worker to ERP transfer is recorded in the immutable task ledger'
);
select is(
  (
    select count(*)::integer
    from auth.sessions session
    where session.user_id = '9f27b000-0000-4000-8000-000000000111'
  ),
  0,
  'the old Worker sessions are revoked at cut-over'
);

select lives_ok(
  $$select public.switch_erp_user_to_worker(
    '9f27b000-0000-4000-8000-000000000103',
    '9f27b000-0000-4000-8000-000000000202',
    '9f27b000-0000-4000-8000-000000000402'
  )$$,
  'an ERP employee moves atomically to a prepared Worker identity'
);
select ok(
  not exists (
    select 1
    from public.employees employee
    where employee.id = '9f27b000-0000-4000-8000-000000000202'
      and employee.user_id is not null
  )
  and exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = '9f27b000-0000-4000-8000-000000000103'
      and profile.employee_id is null
      and profile.is_active is false
  )
  and exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.id = '9f27b000-0000-4000-8000-000000000402'
      and portal.is_active is true
  ),
  'ERP deactivation, unlink and Worker activation leave one authority'
);
select is(
  (
    select task.assigned_to
    from public.smart_tasks task
    where task.id = '9f27b000-0000-4000-8000-000000000702'
  ),
  '9f27b000-0000-4000-8000-000000000112'::uuid,
  'open work follows the person from ERP to Worker'
);
select ok(
  exists (
    select 1
    from public.smart_task_events event
    where event.task_id = '9f27b000-0000-4000-8000-000000000702'
      and event.payload->>'source' = 'identity_transition'
      and event.payload->>'transition' = 'erp_to_worker'
  ),
  'ERP to Worker transfer is recorded in the task ledger'
);
select lives_ok(
  $$select public.switch_worker_to_erp_user(
    '9f27b000-0000-4000-8000-000000000103',
    '9f27b000-0000-4000-8000-000000000202'
  )$$,
  'the same person can return from Worker to the historical ERP identity'
);
select ok(
  exists (
    select 1
    from public.employees employee
    join public.user_profiles profile
      on profile.user_id = employee.user_id
     and profile.employee_id = employee.id
     and profile.tenant_id = employee.tenant_id
     and profile.is_active is true
    where employee.id = '9f27b000-0000-4000-8000-000000000202'
      and employee.user_id = '9f27b000-0000-4000-8000-000000000103'
  )
  and not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = '9f27b000-0000-4000-8000-000000000202'
      and portal.is_active is true
  ),
  'round-trip recovery restores ERP without a duplicate active identity'
);

select lives_ok(
  $$insert into public.user_invitations (
    id, tenant_id, email, role, permissions, invited_by, employee_id,
    status, expires_at, token_hash, token_issued_at, metadata
  ) values (
    '9f27b000-0000-4000-8000-000000000501',
    '9f27b000-0000-4000-8000-000000000001',
    'worker-three-erp@example.invalid',
    'mechanic',
    '{}'::jsonb,
    '9f27b000-0000-4000-8000-000000000101',
    '9f27b000-0000-4000-8000-000000000203',
    'pending',
    now() + interval '7 days',
    encode(
      extensions.digest(
        convert_to(repeat('token', 8), 'UTF8'),
        'sha256'
      ),
      'hex'
    ),
    now(),
    '{"access_transition":{"kind":"worker_to_erp","employee_id":"9f27b000-0000-4000-8000-000000000203","portal_account_id":"9f27b000-0000-4000-8000-000000000403","worker_auth_user_id":"9f27b000-0000-4000-8000-000000000113"}}'::jsonb
  )$$,
  'a typed ERP invitation may wait beside the exact active Worker identity'
);
select ok(
  public.is_authoritative_worker_portal_identity(
    '9f27b000-0000-4000-8000-000000000113',
    '9f27b000-0000-4000-8000-000000000001',
    '9f27b000-0000-4000-8000-000000000203'
  ),
  'the pending transition does not strand the Worker before acceptance'
);
select set_config(
  'request.jwt.claim.sub',
  '9f27b000-0000-4000-8000-000000000115',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27b000-0000-4000-8000-000000000115","role":"authenticated"}',
  true
);
select lives_ok(
  $$select public.accept_user_invitation(repeat('token', 8))$$,
  'acceptance performs the delayed Worker to ERP cut-over'
);
select ok(
  exists (
    select 1
    from public.employees employee
    join public.user_profiles profile
      on profile.user_id = employee.user_id
     and profile.employee_id = employee.id
     and profile.tenant_id = employee.tenant_id
     and profile.is_active is true
    where employee.id = '9f27b000-0000-4000-8000-000000000203'
      and employee.user_id = '9f27b000-0000-4000-8000-000000000115'
  )
  and not exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.id = '9f27b000-0000-4000-8000-000000000403'
      and portal.is_active is true
  )
  and exists (
    select 1
    from public.user_invitations invitation
    where invitation.id = '9f27b000-0000-4000-8000-000000000501'
      and invitation.status = 'accepted'
      and invitation.accepted_user_id =
        '9f27b000-0000-4000-8000-000000000115'
  ),
  'acceptance links ERP, consumes the invitation and deactivates Worker atomically'
);
select is(
  (
    select task.assigned_to
    from public.smart_tasks task
    where task.id = '9f27b000-0000-4000-8000-000000000703'
  ),
  '9f27b000-0000-4000-8000-000000000115'::uuid,
  'invitation acceptance moves open work to the accepted ERP identity'
);
select set_config(
  'request.jwt.claim.sub',
  '9f27b000-0000-4000-8000-000000000101',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"9f27b000-0000-4000-8000-000000000101","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.user_invitations (
    id, tenant_id, email, role, permissions, invited_by, employee_id,
    status, expires_at, token_hash, token_issued_at, metadata
  ) values (
    '9f27b000-0000-4000-8000-000000000502',
    '9f27b000-0000-4000-8000-000000000001',
    'worker-four-erp@example.invalid',
    'mechanic',
    '{}'::jsonb,
    '9f27b000-0000-4000-8000-000000000101',
    '9f27b000-0000-4000-8000-000000000204',
    'pending',
    now() + interval '7 days',
    repeat('b', 64),
    now(),
    '{}'::jsonb
  )$$,
  'P0001',
  'worker_access_conflict',
  'an untyped invitation cannot overlap an active Worker identity'
);
select throws_ok(
  $$update public.employees
    set user_id = '9f27b000-0000-4000-8000-000000000101'
    where id = '9f27b000-0000-4000-8000-000000000205'$$,
  '42501',
  'principal_owner_protected',
  'the company owner identity never becomes one employee'
);
select throws_ok(
  $$insert into public.employees (
      id, tenant_id, user_id, employee_number,
      first_name, last_name, job_title, status
    ) values (
      '9f27b000-0000-4000-8000-000000000206',
      '9f27b000-0000-4000-8000-000000000001',
      '9f27b000-0000-4000-8000-000000000101',
      'TRANSITION-206',
      'Company',
      'Owner',
      'Owner',
      'active'
    )$$,
  '42501',
  'principal_owner_protected',
  'the company owner identity is rejected during employee creation too'
);

select ok(
  not exists (
    select 1
    from public.employees employee
    join public.employee_portal_accounts portal
      on portal.employee_id = employee.id
     and portal.tenant_id = employee.tenant_id
     and portal.is_active is true
    where employee.tenant_id = '9f27b000-0000-4000-8000-000000000001'
      and employee.user_id is not null
  ),
  'no tested transition leaves simultaneous ERP and Worker authority'
);

select * from finish();
rollback;
