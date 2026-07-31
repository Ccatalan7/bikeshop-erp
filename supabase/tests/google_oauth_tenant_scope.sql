begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public',
  'google_oauth_generation_heads',
  'OAuth authorization generations have a canonical head'
);
select has_table(
  'public',
  'google_oauth_tenant_connections',
  'OAuth credentials have a canonical tenant-owned store'
);
select has_table(
  'public',
  'google_oauth_tenant_states',
  'OAuth states have a canonical tenant-owned store'
);
select has_table(
  'public',
  'google_merchant_operation_leases',
  'Merchant refresh coordination is durable'
);
select col_is_pk(
  'public',
  'google_oauth_connections',
  'integration_key',
  'the old global key remains available to the deployed legacy function'
);
select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.google_oauth_tenant_connections'::regclass
      and constraint_row.conname =
        'google_oauth_tenant_connections_owner_key'
      and constraint_row.contype = 'u'
  ),
  'the canonical store is unique per tenant and integration'
);
select has_function(
  'public',
  'create_google_oauth_state',
  array[
    'uuid',
    'uuid',
    'text',
    'text',
    'text',
    'timestamp with time zone'
  ],
  'state creation allocates a tenant integration generation'
);
select has_function(
  'public',
  'consume_google_oauth_state',
  array['text'],
  'state consumption is atomic'
);
select has_function(
  'public',
  'commit_google_oauth_connection',
  array[
    'text',
    'uuid',
    'text',
    'bigint',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'text',
    'timestamp with time zone'
  ],
  'credential commit is generation guarded'
);
select has_function(
  'public',
  'refresh_google_oauth_access_token',
  array[
    'uuid',
    'text',
    'text',
    'bigint',
    'bigint',
    'text',
    'text',
    'text',
    'timestamp with time zone'
  ],
  'access-token refresh uses generation and credential-version CAS'
);
select has_function(
  'public',
  'acquire_google_merchant_refresh_lease',
  array['uuid'],
  'Merchant refresh has an atomic durable lease claim'
);
select has_function(
  'public',
  'renew_google_merchant_refresh_lease',
  array['uuid', 'uuid', 'bigint'],
  'Merchant refresh lease can be renewed by its fenced owner'
);
select has_function(
  'public',
  'release_google_merchant_refresh_lease',
  array['uuid', 'uuid', 'bigint'],
  'Merchant refresh lease release is token and fence bound'
);
select has_column(
  'public',
  'google_merchant_operation_leases',
  'lease_fence',
  'Merchant refresh claims have a monotonic fencing value'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.create_google_oauth_state(uuid,uuid,text,text,text,timestamptz)',
    'EXECUTE'
  ),
  'service role can create OAuth state'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_google_oauth_state(uuid,uuid,text,text,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated callers cannot create OAuth state directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.commit_google_oauth_connection(text,uuid,text,bigint,text,text,text,text,text,text,text,timestamptz)',
    'EXECUTE'
  ),
  'service role can commit OAuth credentials'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.commit_google_oauth_connection(text,uuid,text,bigint,text,text,text,text,text,text,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated callers cannot commit OAuth credentials directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.acquire_google_merchant_refresh_lease(uuid)',
    'EXECUTE'
  ),
  'service role can acquire Merchant lease'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.acquire_google_merchant_refresh_lease(uuid)',
    'EXECUTE'
  ),
  'authenticated callers cannot acquire Merchant lease directly'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.renew_google_merchant_refresh_lease(uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'service role can renew a fenced Merchant lease'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.renew_google_merchant_refresh_lease(uuid,uuid,bigint)',
    'EXECUTE'
  ),
  'authenticated callers cannot renew a Merchant lease directly'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.google_oauth_tenant_connections',
    'SELECT'
  ),
  'anonymous callers cannot read canonical credentials'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.google_oauth_tenant_connections',
    'SELECT'
  ),
  'authenticated callers cannot read canonical credentials directly'
);

insert into public.tenants (
  id,
  shop_name,
  subdomain,
  custom_domain,
  is_active
)
values
  (
    '8a410000-0000-4000-8000-000000000001',
    'Google OAuth Tenant A',
    'google-oauth-a',
    'oauth-a.example.com',
    true
  ),
  (
    '8a410000-0000-4000-8000-000000000002',
    'Google OAuth Tenant B',
    'google-oauth-b',
    'oauth-b.example.com',
    true
  ),
  (
    '8a410000-0000-4000-8000-000000000003',
    'Google OAuth Tenant C',
    'google-oauth-c',
    'oauth-c.example.com',
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
    '8a410000-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'google-oauth-a@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '8a410000-0000-4000-8000-000000000092',
    'authenticated',
    'authenticated',
    'google-oauth-b@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '8a410000-0000-4000-8000-000000000093',
    'authenticated',
    'authenticated',
    'google-oauth-c@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '8a410000-0000-4000-8000-000000000094',
    'authenticated',
    'authenticated',
    'google-oauth-employee@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values
  (
    '8a410000-0000-4000-8000-000000000091',
    '8a410000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '8a410000-0000-4000-8000-000000000092',
    '8a410000-0000-4000-8000-000000000002',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '8a410000-0000-4000-8000-000000000093',
    '8a410000-0000-4000-8000-000000000003',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '8a410000-0000-4000-8000-000000000094',
    '8a410000-0000-4000-8000-000000000003',
    'manager',
    '{}'::jsonb,
    true
  );

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

select throws_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('9', 64),
      'sc-domain:oauth-b.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  '22023',
  'Invalid Google OAuth state request',
  'SQL rejects a Search Console site outside the tenant canonical store'
);

select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('a', 64),
      'sc-domain:oauth-a.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'tenant A can start generation one'
);
select is(
  (
    select generation
    from public.google_oauth_tenant_states
    where state_hash = repeat('a', 64)
  ),
  1::bigint,
  'tenant A first state owns generation one'
);
select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000092',
      '8a410000-0000-4000-8000-000000000002',
      'search_console',
      repeat('b', 64),
      'sc-domain:oauth-b.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'tenant B can independently start the same integration'
);
select is(
  (
    select generation
    from public.google_oauth_tenant_states
    where state_hash = repeat('b', 64)
  ),
  1::bigint,
  'tenant B has an independent generation head'
);
select is(
  (
    select count(*)
    from public.google_oauth_tenant_states
    where integration_key = 'search_console'
      and tenant_id in (
        '8a410000-0000-4000-8000-000000000001'::uuid,
        '8a410000-0000-4000-8000-000000000002'::uuid
      )
  ),
  2::bigint,
  'two tenants coexist with the same integration key'
);

select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('c', 64),
      'sc-domain:oauth-a.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'a new start advances tenant A generation'
);
select ok(
  (
    select invalidated_at is not null
    from public.google_oauth_tenant_states
    where state_hash = repeat('a', 64)
  ),
  'a newer start invalidates the prior unconsumed state'
);
select throws_ok(
  $$select public.consume_google_oauth_state(repeat('a', 64))$$,
  '22023',
  'Google OAuth state is invalid, expired, superseded, or already consumed',
  'an invalidated state cannot be consumed'
);
select lives_ok(
  $$select public.consume_google_oauth_state(repeat('c', 64))$$,
  'generation two can be consumed while its callback is in flight'
);

select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('d', 64),
      'sc-domain:oauth-a.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'another start advances tenant A to generation three'
);
select lives_ok(
  $$select public.consume_google_oauth_state(repeat('d', 64))$$,
  'the latest generation can be consumed'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('d', 64),
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      3,
      'sc-domain:oauth-a.example.com',
      'google',
      'tenant-a@example.invalid',
      'access-a3',
      'refresh-a3',
      'Bearer',
      'https://www.googleapis.com/auth/webmasters',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'true',
  'generation three commits tenant A credentials'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('c', 64),
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      2,
      'sc-domain:oauth-a.example.com',
      'google',
      'older-a@example.invalid',
      'access-a2-late',
      'refresh-a2-late',
      'Bearer',
      'https://www.googleapis.com/auth/webmasters',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'false',
  'an out-of-order older callback loses the generation CAS'
);
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and integration_key = 'search_console'
  ),
  'access-a3',
  'the stale callback cannot overwrite the latest credential'
);
select is(
  public.refresh_google_oauth_access_token(
    '8a410000-0000-4000-8000-000000000001',
    'search_console',
    'sc-domain:oauth-a.example.com',
    2,
    1,
    'stale-refresh-access',
    'Bearer',
    'https://www.googleapis.com/auth/webmasters',
    clock_timestamp() + interval '1 hour'
  ),
  false,
  'a refresh based on the prior authorization generation loses CAS'
);
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and integration_key = 'search_console'
  ),
  'access-a3',
  'losing refresh CAS leaves the reconnect token untouched'
);
select is(
  public.refresh_google_oauth_access_token(
    '8a410000-0000-4000-8000-000000000001',
    'search_console',
    'sc-domain:oauth-a.example.com',
    3,
    1,
    'access-a3-refreshed',
    'Bearer',
    'https://www.googleapis.com/auth/webmasters',
    clock_timestamp() + interval '1 hour'
  ),
  true,
  'the exact generation and credential version can refresh'
);
select is(
  (
    select credential_version
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and integration_key = 'search_console'
  ),
  2::bigint,
  'a successful refresh advances the credential CAS version'
);

select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('0', 64),
      'sc-domain:oauth-a.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'tenant A can start a new-account authorization generation'
);
select lives_ok(
  $$select public.consume_google_oauth_state(repeat('0', 64))$$,
  'the new-account generation can be consumed'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('0', 64),
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      4,
      'sc-domain:oauth-a.example.com',
      'google',
      'different-account@example.invalid',
      'different-account-access',
      'refresh-a3',
      'Bearer',
      'https://www.googleapis.com/auth/webmasters',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'false',
  'an account change cannot retain the prior account refresh token'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('0', 64),
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      4,
      'sc-domain:oauth-a.example.com',
      'google',
      'different-account@example.invalid',
      'different-account-access',
      'different-account-refresh',
      'Bearer',
      'https://www.googleapis.com/auth/webmasters',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'true',
  'an account change commits only with a distinct newly issued refresh token'
);

select lives_ok(
  $$select public.consume_google_oauth_state(repeat('b', 64))$$,
  'tenant B consumes its independent state'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('b', 64),
      '8a410000-0000-4000-8000-000000000002',
      'search_console',
      1,
      'sc-domain:oauth-b.example.com',
      'google',
      'tenant-b@example.invalid',
      'access-b1',
      'refresh-b1',
      'Bearer',
      'https://www.googleapis.com/auth/webmasters',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'true',
  'tenant B commits the same integration key independently'
);
select is(
  (
    select count(*)
    from public.google_oauth_tenant_connections
    where integration_key = 'search_console'
      and tenant_id in (
        '8a410000-0000-4000-8000-000000000001'::uuid,
        '8a410000-0000-4000-8000-000000000002'::uuid
      )
  ),
  2::bigint,
  'canonical storage contains two live Search Console tenants'
);

insert into public.google_oauth_states (
  state,
  created_by,
  expires_at
)
values (
  'legacy-cross-window-c',
  '8a410000-0000-4000-8000-000000000093',
  clock_timestamp() + interval '10 minutes'
);
select set_config(
  'test.google_legacy_hash',
  encode(
    extensions.digest(
      convert_to('legacy-cross-window-c', 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  true
);
select lives_ok(
  format(
    'select public.consume_google_oauth_state(%L)',
    current_setting('test.google_legacy_hash')
  ),
  'one old state can cross the deployment boundary'
);
select is(
  (
    select generation
    from public.google_oauth_tenant_states
    where state_hash = current_setting('test.google_legacy_hash')
  ),
  1::bigint,
  'legacy consumption is represented by a canonical generation'
);
select throws_ok(
  format(
    'select public.consume_google_oauth_state(%L)',
    current_setting('test.google_legacy_hash')
  ),
  '22023',
  'Google OAuth state is invalid, expired, superseded, or already consumed',
  'the legacy bridge is still one-time'
);

insert into public.google_oauth_connections (
  integration_key,
  access_token,
  refresh_token,
  updated_by
)
values (
  'legacy_bridge_test',
  'legacy-access-1',
  'legacy-refresh-1',
  '8a410000-0000-4000-8000-000000000093'
);
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000003'
      and integration_key = 'legacy_bridge_test'
  ),
  'legacy-access-1',
  'the old writer mirrors into generation zero before v2 ownership'
);
update public.google_oauth_connections
set access_token = 'legacy-access-2'
where integration_key = 'legacy_bridge_test';
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000003'
      and integration_key = 'legacy_bridge_test'
  ),
  'legacy-access-2',
  'a later old callback can still update an unclaimed bridge row'
);

insert into public.google_oauth_connections (
  integration_key,
  access_token,
  refresh_token,
  updated_by,
  tenant_id,
  site_url
)
values (
  'legacy_actor_mismatch_test',
  'actor-a-access',
  'actor-a-refresh',
  '8a410000-0000-4000-8000-000000000091',
  '8a410000-0000-4000-8000-000000000001',
  'sc-domain:oauth-a.example.com'
);
update public.google_oauth_connections
set access_token = 'actor-b-must-not-cross',
    refresh_token = 'actor-b-refresh-must-not-cross',
    updated_by = '8a410000-0000-4000-8000-000000000092'
where integration_key = 'legacy_actor_mismatch_test';
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and integration_key = 'legacy_actor_mismatch_test'
  ),
  'actor-a-access',
  'legacy actor B cannot copy its tokens into tenant A prefilled columns'
);

insert into public.google_oauth_connections (
  integration_key,
  access_token,
  refresh_token,
  updated_by,
  tenant_id,
  site_url
)
values (
  'legacy_employee_without_permission',
  'employee-access',
  'employee-refresh',
  '8a410000-0000-4000-8000-000000000094',
  '8a410000-0000-4000-8000-000000000003',
  'sc-domain:oauth-c.example.com'
);
select is(
  (
    select count(*)
    from public.google_oauth_tenant_connections
    where integration_key = 'legacy_employee_without_permission'
  ),
  0::bigint,
  'an active employee without edit_settings cannot promote legacy tokens'
);

insert into public.google_oauth_connections (
  integration_key,
  access_token,
  refresh_token,
  updated_by,
  tenant_id,
  site_url
)
values (
  'legacy_site_mismatch_test',
  'mismatch-access',
  'mismatch-refresh',
  '8a410000-0000-4000-8000-000000000091',
  '8a410000-0000-4000-8000-000000000001',
  'sc-domain:oauth-b.example.com'
);
select is(
  (
    select count(*)
    from public.google_oauth_tenant_connections
    where integration_key = 'legacy_site_mismatch_test'
  ),
  0::bigint,
  'prefilled legacy site mismatch remains legacy-only'
);

insert into public.google_oauth_states (
  state,
  created_by,
  tenant_id,
  site_url,
  expires_at
)
values (
  'legacy-state-actor-tenant-mismatch',
  '8a410000-0000-4000-8000-000000000091',
  '8a410000-0000-4000-8000-000000000002',
  'sc-domain:oauth-b.example.com',
  clock_timestamp() + interval '10 minutes'
);
select ok(
  (
    select tenant_id is null and site_url is null
    from public.google_oauth_states
    where state = 'legacy-state-actor-tenant-mismatch'
  ),
  'legacy state trigger strips mismatched ownership instead of promoting it'
);
select throws_ok(
  format(
    'select public.consume_google_oauth_state(%L)',
    (
      select state_hash
      from public.google_oauth_states
      where state = 'legacy-state-actor-tenant-mismatch'
    )
  ),
  '22023',
  'Google OAuth state is invalid, expired, superseded, or already consumed',
  'a mismatched legacy state cannot create a canonical generation'
);

select lives_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000093',
      '8a410000-0000-4000-8000-000000000003',
      'legacy_bridge_test',
      repeat('e', 64),
      'sc-domain:oauth-c.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  'v2 claims a legacy bridge integration with generation one'
);
select lives_ok(
  $$select public.consume_google_oauth_state(repeat('e', 64))$$,
  'the claimed bridge generation is consumable'
);
select is(
  (
    public.commit_google_oauth_connection(
      repeat('e', 64),
      '8a410000-0000-4000-8000-000000000003',
      'legacy_bridge_test',
      1,
      'sc-domain:oauth-c.example.com',
      'google',
      'tenant-c@example.invalid',
      'canonical-c1',
      'canonical-refresh-c1',
      'Bearer',
      'scope-c',
      clock_timestamp() + interval '1 hour'
    )->>'committed'
  ),
  'true',
  'v2 commits and permanently owns the bridge row'
);
update public.google_oauth_connections
set access_token = 'legacy-must-not-win'
where integration_key = 'legacy_bridge_test';
select is(
  (
    select access_token
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000003'
      and integration_key = 'legacy_bridge_test'
  ),
  'canonical-c1',
  'a legacy callback cannot overwrite a v2-owned connection'
);
select is(
  (
    select generation
    from public.google_oauth_tenant_connections
    where tenant_id = '8a410000-0000-4000-8000-000000000003'
      and integration_key = 'legacy_bridge_test'
  ),
  1::bigint,
  'legacy mirror cannot move or recreate the canonical generation after v2 claim'
);

insert into public.google_oauth_connections (
  integration_key,
  access_token,
  refresh_token
)
values (
  'legacy_ambiguous_test',
  'sentinel-access-token',
  'sentinel-refresh-token'
);
select is(
  (
    select refresh_token
    from public.google_oauth_connections
    where integration_key = 'legacy_ambiguous_test'
  ),
  'sentinel-refresh-token',
  'an unresolved legacy token is preserved byte for byte'
);
select is(
  (
    select count(*)
    from public.google_oauth_tenant_connections
    where integration_key = 'legacy_ambiguous_test'
  ),
  0::bigint,
  'ambiguous legacy ownership is never guessed into canonical storage'
);

-- Exercise the RPC fail-closed behavior even if the production schema normally
-- prevents multiple active profiles.
drop index if exists public.user_profiles_one_active_tenant_per_user_uidx;
insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
)
values (
  '8a410000-0000-4000-8000-000000000091',
  '8a410000-0000-4000-8000-000000000002',
  'admin',
  '{}'::jsonb,
  true
);
select throws_ok(
  $$
    select public.create_google_oauth_state(
      '8a410000-0000-4000-8000-000000000091',
      '8a410000-0000-4000-8000-000000000001',
      'search_console',
      repeat('f', 64),
      'sc-domain:oauth-a.example.com',
      clock_timestamp() + interval '10 minutes'
    )
  $$,
  '42501',
  'Google OAuth requires exactly one active authorized tenant profile',
  'multiple active tenant profiles fail closed'
);
update public.user_profiles
set is_active = false
where user_id = '8a410000-0000-4000-8000-000000000091'
  and tenant_id = '8a410000-0000-4000-8000-000000000002';

insert into public.website_settings (
  tenant_id,
  key,
  value,
  description
)
values
  (
    '8a410000-0000-4000-8000-000000000003',
    'store_url',
    'https://canonical-c.example.com/',
    'Google OAuth canonical store test'
  ),
  (
    '8a410000-0000-4000-8000-000000000003',
    'seo_canonical_url',
    'https://canonical-c.example.com',
    'Google OAuth canonical alias test'
  )
on conflict (tenant_id, key) do update
set value = excluded.value;
select is(
  public.google_oauth_tenant_store_host(
    '8a410000-0000-4000-8000-000000000003'
  ),
  'canonical-c.example.com',
  'SQL derives the OAuth site owner from canonical store_url aliases'
);
select is(
  public.google_oauth_site_matches_tenant(
    '8a410000-0000-4000-8000-000000000003',
    'sc-domain:oauth-c.example.com'
  ),
  false,
  'custom_domain no longer overrides a canonical tenant store_url'
);

select set_config(
  'test.merchant_lease_a',
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'lease_token'
  ),
  true
);
select ok(
  current_setting('test.merchant_lease_a') ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  'Merchant returns a durable lease token'
);
select ok(
  (
    select lease_fence > 0
    from public.google_merchant_operation_leases
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and operation_key = 'merchant_feed_refresh'
  ),
  'Merchant returns a positive durable fencing value'
);
select set_config(
  'test.merchant_first_fence',
  (
    select lease_fence::text
    from public.google_merchant_operation_leases
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and operation_key = 'merchant_feed_refresh'
  ),
  true
);
select is(
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'reason'
  ),
  'active',
  'a second isolate sees the active durable lease'
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000001',
    '8a410000-0000-4000-8000-000000000999',
    (
      select lease_fence
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000001'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  false,
  'a foreign lease token cannot release the owner lease'
);
select is(
  (
    public.renew_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001',
      current_setting('test.merchant_lease_a')::uuid,
      (
        select lease_fence
        from public.google_merchant_operation_leases
        where tenant_id = '8a410000-0000-4000-8000-000000000001'
          and operation_key = 'merchant_feed_refresh'
      )
    )->>'renewed'
  ),
  'true',
  'the exact fenced owner can renew an unexpired lease'
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000001',
    current_setting('test.merchant_lease_a')::uuid,
    (
      select lease_fence + 1
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000001'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  false,
  'a stale fence cannot release the active lease'
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000001',
    current_setting('test.merchant_lease_a')::uuid,
    (
      select lease_fence
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000001'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  true,
  'the exact lease owner can release it'
);

select set_config(
  'test.merchant_lease_a2',
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'lease_token'
  ),
  true
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000001',
    current_setting('test.merchant_lease_a2')::uuid,
    (
      select lease_fence
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000001'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  true,
  'tenant A releases its second allowed attempt'
);
select set_config(
  'test.merchant_lease_a3',
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'lease_token'
  ),
  true
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000001',
    current_setting('test.merchant_lease_a3')::uuid,
    (
      select lease_fence
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000001'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  true,
  'tenant A releases its third allowed attempt'
);
select is(
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'reason'
  ),
  'rate_limited',
  'the fourth Merchant attempt in one minute is denied durably'
);

select set_config(
  'test.merchant_lease_b',
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000002'
    )->>'lease_token'
  ),
  true
);
select ok(
  current_setting('test.merchant_lease_b') ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  'another tenant has an independent Merchant lease'
);
select is(
  public.release_google_merchant_refresh_lease(
    '8a410000-0000-4000-8000-000000000002',
    current_setting('test.merchant_lease_b')::uuid,
    (
      select lease_fence
      from public.google_merchant_operation_leases
      where tenant_id = '8a410000-0000-4000-8000-000000000002'
        and operation_key = 'merchant_feed_refresh'
    )
  ),
  true,
  'tenant B releases only its own lease'
);

update public.google_merchant_operation_leases
set lease_token = '8a410000-0000-4000-8000-000000000998',
    lease_expires_at = clock_timestamp() - interval '1 second',
    window_started_at = clock_timestamp() - interval '2 minutes',
    window_count = 3
where tenant_id = '8a410000-0000-4000-8000-000000000001'
  and operation_key = 'merchant_feed_refresh';
select set_config(
  'test.merchant_recovered',
  (
    public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )->>'lease_token'
  ),
  true
);
select ok(
  current_setting('test.merchant_recovered') ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  'an expired crashed-isolate lease recovers in a fresh window'
);
select ok(
  (
    select lease_fence >
      current_setting('test.merchant_first_fence')::bigint
    from public.google_merchant_operation_leases
    where tenant_id = '8a410000-0000-4000-8000-000000000001'
      and operation_key = 'merchant_feed_refresh'
  ),
  'a recovered lease advances the fencing value monotonically'
);

select set_config(
  'request.jwt.claims',
  '{"role":"authenticated"}',
  true
);
select throws_ok(
  $$
    select public.acquire_google_merchant_refresh_lease(
      '8a410000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  'Merchant refresh lease requires service role',
  'the lease RPC itself also rejects a non-service caller'
);

select * from finish();
rollback;
