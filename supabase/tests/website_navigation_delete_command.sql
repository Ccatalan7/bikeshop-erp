begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select no_plan();

-- ---------------------------------------------------------------------------
-- Shape: one authority-bound, idempotent navigation delete command.
-- ---------------------------------------------------------------------------
select has_function(
  'public',
  'delete_website_navigation',
  array['uuid', 'uuid'],
  'Website Builder has one canonical authority-bound navigation delete'
);

select function_returns(
  'public',
  'delete_website_navigation',
  array['uuid', 'uuid'],
  'text',
  'the delete command reports deleted/already_absent'
);

select ok(
  (
    select procedure_record.prosecdef
      and procedure_record.provolatile = 'v'
      and procedure_record.proconfig =
        array['search_path=pg_catalog, public, pg_temp']::text[]
      and owner_role.rolname = 'postgres'
    from pg_proc procedure_record
    join pg_roles owner_role
      on owner_role.oid = procedure_record.proowner
    where procedure_record.oid =
      'public.delete_website_navigation(uuid,uuid)'::regprocedure
  ),
  'the delete command is volatile, security definer, postgres-owned, and uses a fixed trusted search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.delete_website_navigation(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.delete_website_navigation(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.delete_website_navigation(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public',
    'public.delete_website_navigation(uuid,uuid)',
    'EXECUTE'
  ),
  'only interactive authenticated ERP callers receive EXECUTE on the delete command'
);

-- ---------------------------------------------------------------------------
-- Fixtures: two tenants, an admin and a mechanic in tenant A, navigation
-- rows in both tenants.
-- ---------------------------------------------------------------------------
set local session_replication_role = replica;

insert into public.tenants (id, shop_name)
values
  (
    '7e300917-0000-4000-8000-000000000001',
    'Website navigation delete tenant A'
  ),
  (
    '7e300917-0000-4000-8000-000000000002',
    'Website navigation delete tenant B'
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
    '7e300917-0000-4000-8000-000000000090',
    'authenticated',
    'authenticated',
    'website-nav-delete-admin@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e300917-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '7e300917-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'website-nav-delete-mechanic@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e300917-0000-4000-8000-000000000001'
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
    '7e300917-0000-4000-8000-000000000090',
    '7e300917-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '7e300917-0000-4000-8000-000000000091',
    '7e300917-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true
  );

insert into public.website_navigation (
  id,
  tenant_id,
  menu_location,
  label,
  link_type,
  link_value
)
values
  (
    '7e300917-0000-4000-8000-000000000010',
    '7e300917-0000-4000-8000-000000000001',
    'footer',
    'Borrable A',
    'external',
    '/a'
  ),
  (
    '7e300917-0000-4000-8000-000000000011',
    '7e300917-0000-4000-8000-000000000001',
    'footer',
    'Preservado A',
    'external',
    '/a2'
  ),
  (
    '7e300917-0000-4000-8000-000000000020',
    '7e300917-0000-4000-8000-000000000002',
    'footer',
    'Ajeno B',
    'external',
    '/b'
  ),
  (
    '7e300917-0000-4000-8000-000000000030',
    '7e300917-0000-4000-8000-000000000001',
    'footer',
    'Padre A',
    'external',
    '/padre'
  );

insert into public.website_navigation (
  id,
  tenant_id,
  menu_location,
  label,
  link_type,
  link_value,
  parent_id
)
values (
  '7e300917-0000-4000-8000-000000000031',
  '7e300917-0000-4000-8000-000000000001',
  'footer',
  'Hijo A',
  'external',
  '/hijo',
  '7e300917-0000-4000-8000-000000000030'
);

set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Admin of tenant A: deleted, then idempotent already_absent on retry.
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300917-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300917-0000-4000-8000-000000000090',
  true
);
set local role authenticated;

select is(
  public.delete_website_navigation(
    '7e300917-0000-4000-8000-000000000001',
    '7e300917-0000-4000-8000-000000000010'
  ),
  'deleted',
  'the tenant admin deletes an own navigation row'
);

select is(
  public.delete_website_navigation(
    '7e300917-0000-4000-8000-000000000001',
    '7e300917-0000-4000-8000-000000000010'
  ),
  'already_absent',
  'a retry after a lost response converges idempotently and can confirm'
);

-- Null arguments fail closed with 42501 (never a null-swallowing delete).
select throws_ok(
  $$
    select public.delete_website_navigation(
      null,
      '7e300917-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a null tenant argument raises 42501'
);
select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000001',
      null
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a null navigation argument raises 42501'
);

-- Deleting a parent cascades its children (FK on delete cascade), so no
-- orphan child survives under the tenant.
select is(
  public.delete_website_navigation(
    '7e300917-0000-4000-8000-000000000001',
    '7e300917-0000-4000-8000-000000000030'
  ),
  'deleted',
  'the tenant admin deletes a parent navigation row'
);

set local role postgres;
select is(
  (
    select count(*)::int
    from public.website_navigation
    where id in (
      '7e300917-0000-4000-8000-000000000030',
      '7e300917-0000-4000-8000-000000000031'
    )
  ),
  0,
  'the child cascades with its deleted parent'
);

select is(
  (
    select count(*)::int
    from public.website_navigation
    where id = '7e300917-0000-4000-8000-000000000010'
  ),
  0,
  'the deleted row is gone'
);
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Tenant isolation: the admin of A can never touch tenant B, and the
-- foreign row survives.
-- ---------------------------------------------------------------------------
set local role authenticated;

select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000002',
      '7e300917-0000-4000-8000-000000000020'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a foreign tenant target raises 42501'
);

set local role postgres;
select is(
  (
    select count(*)::int
    from public.website_navigation
    where id = '7e300917-0000-4000-8000-000000000020'
  ),
  1,
  'the foreign tenant row is untouched'
);

-- ---------------------------------------------------------------------------
-- Stale/absent authority (mechanic): 42501 and the row is preserved, so the
-- client keeps its draft and latches/revokes instead of faking success.
-- ---------------------------------------------------------------------------
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300917-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300917-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000001',
      '7e300917-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a caller without canonical edit authority raises 42501 (never a silent zero-row delete)'
);

set local role postgres;
select is(
  (
    select count(*)::int
    from public.website_navigation
    where id = '7e300917-0000-4000-8000-000000000011'
  ),
  1,
  'the row survives a stale-grant attempt: the published link never silently disappears'
);

-- The mechanic is denied by AUTHORITY, even when the target row is already
-- absent: existence can never leak through the authority gate.
select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000001',
      '7e300917-0000-4000-8000-000000000010'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a caller without authority gets 42501 even for an absent row'
);

-- ---------------------------------------------------------------------------
-- Remote revocation: the former admin loses edit authority and the very
-- next call fails closed with 42501.
-- ---------------------------------------------------------------------------
set local role postgres;
update public.user_profiles
set role = 'mechanic'
where user_id = '7e300917-0000-4000-8000-000000000090';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300917-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300917-0000-4000-8000-000000000090',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000001',
      '7e300917-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a REMOTELY revoked authority fails closed on the next delete'
);

set local role postgres;
select is(
  (
    select count(*)::int
    from public.website_navigation
    where tenant_id in (
      '7e300917-0000-4000-8000-000000000001',
      '7e300917-0000-4000-8000-000000000002'
    )
  ),
  2,
  'every remaining row (own tenant and foreign) is intact after all denied attempts'
);

-- ---------------------------------------------------------------------------
-- Anonymous identity: fail closed.
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$
    select public.delete_website_navigation(
      '7e300917-0000-4000-8000-000000000001',
      '7e300917-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'website_navigation_delete_forbidden',
  'a missing auth identity raises 42501'
);

select * from finish();

rollback;
