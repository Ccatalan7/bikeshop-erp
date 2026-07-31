begin;

select no_plan();

select has_function(
  'public',
  'ensure_default_footer_navigation',
  array['uuid'],
  'default footer navigation has one canonical transactional command'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.ensure_default_footer_navigation(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.ensure_default_footer_navigation(uuid)',
    'EXECUTE'
  ),
  'only authenticated ERP users can execute the footer seed command'
);

select ok(
  (
    select procedure_record.prosecdef
      and owner_role.rolname = 'postgres'
      and procedure_record.proconfig =
        array['search_path=pg_catalog, public, pg_temp']::text[]
      and pg_get_functiondef(procedure_record.oid) like
        '%pg_advisory_xact_lock%'
    from pg_proc procedure_record
    join pg_roles owner_role
      on owner_role.oid = procedure_record.proowner
    where procedure_record.oid =
      'public.ensure_default_footer_navigation(uuid)'::regprocedure
  ),
  'the command has a trusted search path and serializes each tenant seed'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_navigation'
      and policyname = 'website_navigation_insert'
      and roles = array['authenticated']::name[]
      and with_check = 'can_edit_tenant_settings(tenant_id)'
  )
  and exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_navigation'
      and policyname = 'website_navigation_update'
      and roles = array['authenticated']::name[]
      and qual = 'can_edit_tenant_settings(tenant_id)'
      and with_check = 'can_edit_tenant_settings(tenant_id)'
  )
  and exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_navigation'
      and policyname = 'website_navigation_delete'
      and roles = array['authenticated']::name[]
      and qual = 'can_edit_tenant_settings(tenant_id)'
  ),
  'all navigation mutations require explicit Website Builder authority'
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
    '7e282300-0000-4000-8000-000000000001',
    'Navigation seed tenant A',
    'navigation-seed-a',
    'navigation-seed-a@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7e282300-0000-4000-8000-000000000002',
    'Navigation seed tenant B',
    'navigation-seed-b',
    'navigation-seed-b@example.invalid',
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
    '7e282300-0000-4000-8000-000000000090',
    'authenticated',
    'authenticated',
    'navigation-seed-admin@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e282300-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '7e282300-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'navigation-seed-mechanic@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e282300-0000-4000-8000-000000000001'
    ),
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
    '7e282300-0000-4000-8000-000000000090',
    '7e282300-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '7e282300-0000-4000-8000-000000000091',
    '7e282300-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e282300-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e282300-0000-4000-8000-000000000090',
  true
);

set local role authenticated;

select is(
  (
    public.ensure_default_footer_navigation(
      '7e282300-0000-4000-8000-000000000001'
    )->>'created'
  )::boolean,
  true,
  'the first authorized call creates the complete footer'
);

select is(
  (
    select count(*)
    from public.website_navigation navigation
    where navigation.tenant_id =
      '7e282300-0000-4000-8000-000000000001'
      and navigation.menu_location = 'footer'
  ),
  11::bigint,
  'the seed creates both parents and all nine children'
);

select is(
  (
    select count(*)
    from public.website_navigation navigation
    where navigation.tenant_id =
      '7e282300-0000-4000-8000-000000000001'
      and navigation.menu_location = 'footer'
      and navigation.parent_id is null
  ),
  2::bigint,
  'the returned footer has exactly two top-level groups'
);

select is(
  (
    select count(*)
    from public.website_navigation child
    left join public.website_navigation parent
      on parent.id = child.parent_id
     and parent.tenant_id = child.tenant_id
    where child.tenant_id =
      '7e282300-0000-4000-8000-000000000001'
      and child.menu_location = 'footer'
      and child.parent_id is not null
      and parent.id is null
  ),
  0::bigint,
  'the one-statement seed cannot leave orphan footer children'
);

select is(
  (
    public.ensure_default_footer_navigation(
      '7e282300-0000-4000-8000-000000000001'
    )->>'created'
  )::boolean,
  false,
  'repeating the command is idempotent'
);

select is(
  jsonb_array_length(
    public.ensure_default_footer_navigation(
      '7e282300-0000-4000-8000-000000000001'
    )->'items'
  ),
  11,
  'an idempotent call returns the existing complete footer'
);

select is(
  (
    public.get_public_store_data(
      '7e282300-0000-4000-8000-000000000001'
    )::jsonb->>'tenant_id'
  ),
  '7e282300-0000-4000-8000-000000000001',
  'the public-store aggregate declares its tenant owner'
);

select throws_ok(
  $$select public.ensure_default_footer_navigation(
    '7e282300-0000-4000-8000-000000000002'
  )$$,
  '42501',
  'website_navigation_seed_forbidden',
  'an editor cannot seed another tenant'
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e282300-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e282300-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.ensure_default_footer_navigation(
    '7e282300-0000-4000-8000-000000000001'
  )$$,
  '42501',
  'website_navigation_seed_forbidden',
  'tenant membership without edit_settings cannot seed public navigation'
);

select throws_ok(
  $$
    insert into public.website_navigation (
      tenant_id,
      menu_location,
      label,
      link_type,
      link_value
    )
    values (
      '7e282300-0000-4000-8000-000000000001',
      'footer',
      'No autorizado',
      'action',
      ''
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "website_navigation"',
  'the hardened insert policy also blocks direct unauthorized writes'
);

reset role;

select * from finish();
rollback;
