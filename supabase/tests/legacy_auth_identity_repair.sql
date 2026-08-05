begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public',
  'legacy_auth_identity_repair_receipts',
  'legacy identity repair has an immutable receipt owner'
);
select has_function(
  'public',
  'repair_legacy_accidental_customer_tenant_identity',
  array['text', 'uuid', 'uuid', 'uuid', 'uuid', 'uuid', 'text'],
  'legacy customer tenant repair is one guarded canonical command'
);
select has_function(
  'public',
  'resolve_auth_user_id_by_email',
  array['text'],
  'invitation preflight resolves Auth identity without paging the Auth directory'
);
select has_function(
  'public',
  'lookup_user_invitation_identity',
  array['text'],
  'invitation acceptance resolves whether the destination Auth account exists'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_auth_user_id_by_email(text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.resolve_auth_user_id_by_email(text)',
    'EXECUTE'
  ),
  'only trusted server workflows can resolve an Auth email'
);
select ok(
  has_function_privilege(
    'anon',
    'public.lookup_user_invitation_identity(text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.lookup_user_invitation_identity(text)',
    'EXECUTE'
  ),
  'a valid invitation capability can resolve only its own account mode'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.repair_legacy_accidental_customer_tenant_identity(text,uuid,uuid,uuid,uuid,uuid,text)',
    'EXECUTE'
  ),
  'trusted maintenance may execute the guarded repair'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.repair_legacy_accidental_customer_tenant_identity(text,uuid,uuid,uuid,uuid,uuid,text)',
    'EXECUTE'
  ),
  'ERP clients cannot execute identity repair'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.legacy_auth_identity_repair_receipts',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'
  ),
  'repair evidence is not exposed to application clients'
);
select has_trigger(
  'public',
  'legacy_auth_identity_repair_receipts',
  'trg_guard_legacy_auth_identity_repair_receipt',
  'repair evidence is immutable'
);

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
    '9f284000-0000-4000-8000-000000000001',
    'Canonical Customer Tenant',
    'identity-repair-target',
    'target-owner@example.invalid',
    true
  ),
  (
    '9f284000-0000-4000-8000-000000000002',
    'Accidental Signup Tenant',
    'identity-repair-source',
    'repairable@example.invalid',
    true
  ),
  (
    '9f284000-0000-4000-8000-000000000003',
    'Accidental Tenant With History',
    'identity-repair-blocked',
    'blocked@example.invalid',
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
    '9f284000-0000-4000-8000-000000000101',
    'authenticated',
    'authenticated',
    'repairable@example.invalid',
    '',
    now(),
    jsonb_build_object(
      'provider', 'email',
      'account_type', 'erp_owner',
      'tenant_id', '9f284000-0000-4000-8000-000000000002',
      'role', 'admin'
    ),
    jsonb_build_object(
      'account_type', 'erp_owner',
      'shop_name', 'Accidental Signup Tenant'
    ),
    now(),
    now()
  ),
  (
    '9f284000-0000-4000-8000-000000000102',
    'authenticated',
    'authenticated',
    'blocked@example.invalid',
    '',
    now(),
    jsonb_build_object(
      'provider', 'email',
      'account_type', 'erp_owner',
      'tenant_id', '9f284000-0000-4000-8000-000000000003',
      'role', 'admin'
    ),
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
  is_active
)
values
  (
    '9f284000-0000-4000-8000-000000000201',
    '9f284000-0000-4000-8000-000000000101',
    '9f284000-0000-4000-8000-000000000002',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '9f284000-0000-4000-8000-000000000202',
    '9f284000-0000-4000-8000-000000000102',
    '9f284000-0000-4000-8000-000000000003',
    'admin',
    '{}'::jsonb,
    true
  );

insert into public.customers (
  id,
  tenant_id,
  name,
  email,
  auth_user_id,
  is_active
)
values
  (
    '9f284000-0000-4000-8000-000000000301',
    '9f284000-0000-4000-8000-000000000001',
    'Repairable Customer',
    'repairable@example.invalid',
    '9f284000-0000-4000-8000-000000000101',
    true
  ),
  (
    '9f284000-0000-4000-8000-000000000302',
    '9f284000-0000-4000-8000-000000000001',
    'Blocked Customer',
    'blocked@example.invalid',
    '9f284000-0000-4000-8000-000000000102',
    true
  );

insert into auth.sessions (id, user_id, created_at, updated_at)
values (
  '9f284000-0000-4000-8000-000000000401',
  '9f284000-0000-4000-8000-000000000101',
  now(),
  now()
);

insert into public.user_activity_log (
  id,
  tenant_id,
  user_id,
  action,
  details
)
values (
  '9f284000-0000-4000-8000-000000000501',
  '9f284000-0000-4000-8000-000000000003',
  '9f284000-0000-4000-8000-000000000102',
  'business_history_exists',
  '{}'::jsonb
);

set local session_replication_role = origin;

create temp table successful_repair on commit drop as
select public.repair_legacy_accidental_customer_tenant_identity(
  'test:legacy-customer-identity:repairable',
  '9f284000-0000-4000-8000-000000000002',
  '9f284000-0000-4000-8000-000000000201',
  '9f284000-0000-4000-8000-000000000101',
  '9f284000-0000-4000-8000-000000000001',
  '9f284000-0000-4000-8000-000000000301',
  'Test fixture proves a customer-safe legacy identity repair.'
) as payload;

select is(
  (select payload->>'success' from successful_repair),
  'true',
  'repair returns a positive receipt'
);
select is(
  (select is_active from public.tenants
   where id = '9f284000-0000-4000-8000-000000000002'),
  false,
  'accidental tenant is archived rather than deleted'
);
select is(
  (select count(*)::integer from public.user_profiles
   where id = '9f284000-0000-4000-8000-000000000201'),
  0,
  'only the corrupt ERP profile is removed'
);
select ok(
  exists (
    select 1
    from public.customers customer
    where customer.id = '9f284000-0000-4000-8000-000000000301'
      and customer.auth_user_id =
        '9f284000-0000-4000-8000-000000000101'
      and customer.is_active is true
  ),
  'the storefront customer membership and history remain intact'
);
select ok(
  (
    select raw_app_meta_data->>'account_type' = 'public_store_customer'
      and raw_app_meta_data->'customer_memberships'->>
        '9f284000-0000-4000-8000-000000000001' =
          '9f284000-0000-4000-8000-000000000301'
      and not raw_app_meta_data ? 'tenant_id'
      and raw_app_meta_data->>'provider' = 'email'
    from auth.users
    where id = '9f284000-0000-4000-8000-000000000101'
  ),
  'Auth authority is rebuilt from DB customer memberships while provider metadata survives'
);
select is(
  (select count(*)::integer from auth.sessions
   where user_id = '9f284000-0000-4000-8000-000000000101'),
  0,
  'stale owner sessions are revoked'
);
select is(
  (select count(*)::integer
   from public.legacy_auth_identity_repair_receipts
   where repair_key = 'test:legacy-customer-identity:repairable'),
  1,
  'one immutable repair receipt is retained'
);

insert into public.user_invitations (
  id,
  tenant_id,
  email,
  role,
  permissions,
  invited_by,
  status,
  expires_at,
  token_hash
)
values
  (
    '9f284000-0000-4000-8000-000000000601',
    '9f284000-0000-4000-8000-000000000001',
    'repairable@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f284000-0000-4000-8000-000000000101',
    'pending',
    now() + interval '1 day',
    encode(
      extensions.digest(
        convert_to(
          'test-invitation-token-for-existing-auth-identity-0001',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  ),
  (
    '9f284000-0000-4000-8000-000000000602',
    '9f284000-0000-4000-8000-000000000001',
    'new-person@example.invalid',
    'cashier',
    '{}'::jsonb,
    '9f284000-0000-4000-8000-000000000101',
    'pending',
    now() + interval '1 day',
    encode(
      extensions.digest(
        convert_to(
          'test-invitation-token-for-new-auth-identity-0000002',
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  );

select is(
  (
    select account_exists
    from public.lookup_user_invitation_identity(
      'test-invitation-token-for-existing-auth-identity-0001'
    )
  ),
  true,
  'an existing storefront customer is sent directly to sign-in'
);
select is(
  (
    select account_exists
    from public.lookup_user_invitation_identity(
      'test-invitation-token-for-new-auth-identity-0000002'
    )
  ),
  false,
  'a genuinely new identity is sent to account creation'
);
select throws_ok(
  $$
    update public.legacy_auth_identity_repair_receipts
    set reason = 'Attempted mutation of immutable repair evidence.'
    where repair_key = 'test:legacy-customer-identity:repairable'
  $$,
  '42501',
  'legacy_auth_identity_repair_receipt_immutable',
  'repair evidence cannot be rewritten'
);
select is(
  (
    public.repair_legacy_accidental_customer_tenant_identity(
      'test:legacy-customer-identity:repairable',
      '9f284000-0000-4000-8000-000000000002',
      '9f284000-0000-4000-8000-000000000201',
      '9f284000-0000-4000-8000-000000000101',
      '9f284000-0000-4000-8000-000000000001',
      '9f284000-0000-4000-8000-000000000301',
      'Test fixture proves a customer-safe legacy identity repair.'
    )->>'replayed'
  ),
  'true',
  'an exact retry replays the same receipt without a second mutation'
);

select throws_ok(
  $$
    select public.repair_legacy_accidental_customer_tenant_identity(
      'test:legacy-customer-identity:blocked',
      '9f284000-0000-4000-8000-000000000003',
      '9f284000-0000-4000-8000-000000000202',
      '9f284000-0000-4000-8000-000000000102',
      '9f284000-0000-4000-8000-000000000001',
      '9f284000-0000-4000-8000-000000000302',
      'Test fixture must retain any tenant with business history.'
    )
  $$,
  'P0001',
  'legacy_tenant_contains_business_data:user_activity_log',
  'any non-seed tenant history blocks the entire repair'
);
select is(
  (select is_active from public.tenants
   where id = '9f284000-0000-4000-8000-000000000003'),
  true,
  'blocked repair leaves the source tenant active'
);
select is(
  (select count(*)::integer from public.user_profiles
   where id = '9f284000-0000-4000-8000-000000000202'),
  1,
  'blocked repair leaves the source profile intact'
);

select * from finish();
rollback;
