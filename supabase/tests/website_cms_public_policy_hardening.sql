begin;

select no_plan();

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_blocks'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
      and 'public' = any(roles)
  ),
  'website block writes are never granted through PUBLIC policies'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_blocks'
      and policyname = 'website_blocks_update'
      and roles = array['authenticated']::name[]
      and qual = 'can_edit_tenant_settings(tenant_id)'
      and with_check = 'can_edit_tenant_settings(tenant_id)'
  ),
  'website block updates require explicit settings authority on old and new rows'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_pages'
      and policyname = 'website_pages_update'
      and roles = array['authenticated']::name[]
      and qual = 'can_edit_tenant_settings(tenant_id)'
      and with_check = 'can_edit_tenant_settings(tenant_id)'
  ),
  'website page updates use the same settings authority contract'
);

select ok(
  not has_table_privilege('anon', 'public.website_blocks', 'INSERT')
  and not has_table_privilege('anon', 'public.website_blocks', 'UPDATE')
  and not has_table_privilege('anon', 'public.website_blocks', 'DELETE')
  and not has_table_privilege('anon', 'public.website_blocks', 'TRUNCATE'),
  'anonymous visitors have no website block write privileges'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_blocks'
      and policyname = 'website_blocks_select_public'
  ),
  'the duplicate legacy anonymous SELECT policy is absent'
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
    '7e170000-0000-4000-8000-000000000001',
    'Public CMS Policy Tenant A',
    'public-cms-policy-tenant-a',
    'owner-a-public-cms@example.invalid',
    'America/Santiago',
    true
  ),
  (
    '7e170000-0000-4000-8000-000000000002',
    'Public CMS Policy Tenant B',
    'public-cms-policy-tenant-b',
    'owner-b-public-cms@example.invalid',
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
    '7e170000-0000-4000-8000-000000000090',
    'authenticated',
    'authenticated',
    'website-cms-admin@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e170000-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '7e170000-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'website-cms-mechanic@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e170000-0000-4000-8000-000000000001'
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
    '7e170000-0000-4000-8000-000000000090',
    '7e170000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '7e170000-0000-4000-8000-000000000091',
    '7e170000-0000-4000-8000-000000000001',
    'mechanic',
    '{}'::jsonb,
    true
  );

insert into public.website_pages (
  id,
  tenant_id,
  slug,
  title,
  is_published,
  is_home,
  is_system,
  template
)
values
  (
    '7e170000-0000-4000-8000-000000000010',
    '7e170000-0000-4000-8000-000000000001',
    'publicada-prueba',
    'Página publicada de prueba',
    true,
    false,
    false,
    'default'
  ),
  (
    '7e170000-0000-4000-8000-000000000011',
    '7e170000-0000-4000-8000-000000000001',
    'borrador-prueba',
    'Página borrador de prueba',
    false,
    false,
    false,
    'default'
  ),
  (
    '7e170000-0000-4000-8000-000000000012',
    '7e170000-0000-4000-8000-000000000002',
    'publicada-tenant-b',
    'Página pública del tenant B',
    true,
    false,
    false,
    'default'
  ),
  (
    '7e170000-0000-4000-8000-000000000013',
    '7e170000-0000-4000-8000-000000000001',
    'sistema-protegida',
    'Página de sistema protegida',
    true,
    false,
    true,
    'default'
  );

insert into public.website_blocks (
  id,
  tenant_id,
  page_id,
  block_type,
  order_index,
  is_visible,
  block_data
)
values
  (
    '7e170000-0000-4000-8000-000000000020',
    '7e170000-0000-4000-8000-000000000001',
    '7e170000-0000-4000-8000-000000000010',
    'about',
    0,
    true,
    '{"marker":"published-visible-a"}'::jsonb
  ),
  (
    '7e170000-0000-4000-8000-000000000021',
    '7e170000-0000-4000-8000-000000000001',
    '7e170000-0000-4000-8000-000000000011',
    'about',
    1,
    true,
    '{"marker":"draft-visible-a"}'::jsonb
  ),
  (
    '7e170000-0000-4000-8000-000000000022',
    '7e170000-0000-4000-8000-000000000001',
    '7e170000-0000-4000-8000-000000000010',
    'about',
    2,
    false,
    '{"marker":"published-hidden-a"}'::jsonb
  ),
  (
    '7e170000-0000-4000-8000-000000000023',
    '7e170000-0000-4000-8000-000000000001',
    null,
    'hero',
    3,
    null,
    '{"marker":"legacy-visible-a"}'::jsonb
  ),
  (
    '7e170000-0000-4000-8000-000000000024',
    '7e170000-0000-4000-8000-000000000002',
    '7e170000-0000-4000-8000-000000000012',
    'about',
    0,
    true,
    '{"marker":"published-visible-b"}'::jsonb
  );

set local session_replication_role = origin;
set local role anon;

select is(
  (
    select count(*)
    from public.website_blocks
    where tenant_id = '7e170000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'anonymous visitors see published and standalone legacy blocks only'
);

select ok(
  not exists (
    select 1
    from public.website_blocks
    where block_data->>'marker' in (
      'draft-visible-a',
      'published-hidden-a'
    )
  ),
  'draft-page and hidden block content remain private'
);

select is(
  (
    select count(*)
    from public.website_blocks
    where tenant_id = '7e170000-0000-4000-8000-000000000002'
  ),
  1::bigint,
  'published content remains readable for another public storefront'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e170000-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e170000-0000-4000-8000-000000000090',
  true
);
set local role authenticated;

select isnt_empty(
  $query$
    insert into public.website_pages (
      id,
      tenant_id,
      slug,
      title,
      is_published,
      is_home,
      is_system,
      template
    )
    values (
      '7e170000-0000-4000-8000-000000000030',
      '7e170000-0000-4000-8000-000000000001',
      'admin-crud',
      'Admin CRUD',
      false,
      false,
      false,
      'default'
    )
    returning id
  $query$,
  'an authorized admin can insert a website page'
);

select isnt_empty(
  $query$
    update public.website_pages
    set title = 'Admin CRUD actualizado'
    where id = '7e170000-0000-4000-8000-000000000030'
    returning id
  $query$,
  'an authorized admin can update a website page'
);

select isnt_empty(
  $query$
    insert into public.website_blocks (
      id,
      tenant_id,
      page_id,
      block_type,
      order_index,
      is_visible,
      block_data
    )
    values (
      '7e170000-0000-4000-8000-000000000031',
      '7e170000-0000-4000-8000-000000000001',
      '7e170000-0000-4000-8000-000000000030',
      'about',
      0,
      true,
      '{"marker":"admin-created"}'::jsonb
    )
    returning id
  $query$,
  'an authorized admin can insert a website block'
);

select isnt_empty(
  $query$
    update public.website_blocks
    set block_data = '{"marker":"admin-updated"}'::jsonb
    where id = '7e170000-0000-4000-8000-000000000031'
    returning id
  $query$,
  'an authorized admin can update a website block'
);

select isnt_empty(
  $query$
    delete from public.website_blocks
    where id = '7e170000-0000-4000-8000-000000000031'
    returning id
  $query$,
  'an authorized admin can delete a website block'
);

select isnt_empty(
  $query$
    delete from public.website_pages
    where id = '7e170000-0000-4000-8000-000000000030'
    returning id
  $query$,
  'an authorized admin can delete a non-system website page'
);

select throws_ok(
  $query$
    insert into public.website_pages (
      id,
      tenant_id,
      slug,
      title,
      is_published,
      is_home,
      is_system,
      template
    )
    values (
      '7e170000-0000-4000-8000-000000000032',
      '7e170000-0000-4000-8000-000000000002',
      'cross-tenant-admin',
      'Cross-tenant admin',
      false,
      false,
      false,
      'default'
    )
  $query$,
  '42501',
  'new row violates row-level security policy for table "website_pages"',
  'an authorized admin cannot insert a page for another tenant'
);

select throws_ok(
  $query$
    insert into public.website_blocks (
      id,
      tenant_id,
      page_id,
      block_type,
      order_index,
      is_visible,
      block_data
    )
    values (
      '7e170000-0000-4000-8000-000000000033',
      '7e170000-0000-4000-8000-000000000002',
      '7e170000-0000-4000-8000-000000000012',
      'about',
      1,
      true,
      '{"marker":"cross-tenant-admin"}'::jsonb
    )
  $query$,
  '42501',
  'new row violates row-level security policy for table "website_blocks"',
  'an authorized admin cannot insert a block for another tenant'
);

select is_empty(
  $query$
    update public.website_pages
    set title = 'Cross-tenant update'
    where id = '7e170000-0000-4000-8000-000000000012'
    returning id
  $query$,
  'an authorized admin cannot update another tenant page'
);

select is_empty(
  $query$
    delete from public.website_pages
    where id = '7e170000-0000-4000-8000-000000000012'
    returning id
  $query$,
  'an authorized admin cannot delete another tenant page'
);

select is_empty(
  $query$
    update public.website_blocks
    set block_data = '{"marker":"cross-tenant-update"}'::jsonb
    where id = '7e170000-0000-4000-8000-000000000024'
    returning id
  $query$,
  'an authorized admin cannot update another tenant block'
);

select is_empty(
  $query$
    delete from public.website_blocks
    where id = '7e170000-0000-4000-8000-000000000024'
    returning id
  $query$,
  'an authorized admin cannot delete another tenant block'
);

select is_empty(
  $query$
    delete from public.website_pages
    where id = '7e170000-0000-4000-8000-000000000013'
    returning id
  $query$,
  'even an authorized admin cannot delete a system website page'
);

select is(
  (
    select count(*)
    from public.website_pages
    where id = '7e170000-0000-4000-8000-000000000013'
  ),
  1::bigint,
  'the protected system website page remains present'
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e170000-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e170000-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $query$
    insert into public.website_pages (
      id,
      tenant_id,
      slug,
      title,
      is_published,
      is_home,
      is_system,
      template
    )
    values (
      '7e170000-0000-4000-8000-000000000040',
      '7e170000-0000-4000-8000-000000000001',
      'mechanic-denied',
      'Mechanic denied',
      false,
      false,
      false,
      'default'
    )
  $query$,
  '42501',
  'new row violates row-level security policy for table "website_pages"',
  'tenant membership without edit_settings cannot insert a website page'
);

select throws_ok(
  $query$
    insert into public.website_blocks (
      id,
      tenant_id,
      page_id,
      block_type,
      order_index,
      is_visible,
      block_data
    )
    values (
      '7e170000-0000-4000-8000-000000000041',
      '7e170000-0000-4000-8000-000000000001',
      '7e170000-0000-4000-8000-000000000011',
      'about',
      2,
      true,
      '{"marker":"mechanic-denied"}'::jsonb
    )
  $query$,
  '42501',
  'new row violates row-level security policy for table "website_blocks"',
  'tenant membership without edit_settings cannot insert a website block'
);

select is_empty(
  $query$
    update public.website_pages
    set title = 'Mechanic update'
    where id = '7e170000-0000-4000-8000-000000000011'
    returning id
  $query$,
  'tenant membership without edit_settings cannot update a website page'
);

select is_empty(
  $query$
    delete from public.website_pages
    where id = '7e170000-0000-4000-8000-000000000011'
    returning id
  $query$,
  'tenant membership without edit_settings cannot delete a website page'
);

select is_empty(
  $query$
    update public.website_blocks
    set block_data = '{"marker":"mechanic-update"}'::jsonb
    where id = '7e170000-0000-4000-8000-000000000021'
    returning id
  $query$,
  'tenant membership without edit_settings cannot update a website block'
);

select is_empty(
  $query$
    delete from public.website_blocks
    where id = '7e170000-0000-4000-8000-000000000021'
    returning id
  $query$,
  'tenant membership without edit_settings cannot delete a website block'
);

reset role;

select * from finish();
rollback;
