begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select no_plan();

select has_function(
  'public',
  'load_editor_page_with_blocks',
  array['uuid', 'text'],
  'Website Builder has one canonical authority-bound editor page reader'
);

select function_returns(
  'public',
  'load_editor_page_with_blocks',
  array['uuid', 'text'],
  'jsonb',
  'the editor reader returns one JSON page projection'
);

select ok(
  (
    select procedure_record.prosecdef
      and procedure_record.provolatile = 's'
      and procedure_record.proconfig =
        array['search_path=pg_catalog, public, pg_temp']::text[]
      and owner_role.rolname = 'postgres'
    from pg_proc procedure_record
    join pg_roles owner_role
      on owner_role.oid = procedure_record.proowner
    where procedure_record.oid =
      'public.load_editor_page_with_blocks(uuid,text)'::regprocedure
  ),
  'the editor reader is stable, security definer, postgres-owned, and uses a fixed trusted search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.load_editor_page_with_blocks(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.load_editor_page_with_blocks(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.load_editor_page_with_blocks(uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public',
    'public.load_editor_page_with_blocks(uuid,text)',
    'EXECUTE'
  ),
  'only authenticated ERP callers receive EXECUTE on the editor reader'
);

select ok(
  exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'website_pages'
      and policy.policyname = 'website_pages_select_public'
      and policy.cmd = 'SELECT'
      and policy.roles = array['anon']::name[]
  )
  and exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'website_blocks'
      and policy.policyname = 'public_website_blocks_select'
      and policy.cmd = 'SELECT'
      and policy.roles = array['anon']::name[]
  )
  and exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'website_blocks'
      and policy.policyname = 'public_website_blocks_select_authenticated'
      and policy.cmd = 'SELECT'
      and policy.roles = array['authenticated']::name[]
  ),
  'the three canonical public page/block read policies remain intact'
);

select ok(
  exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'website_pages'
      and policy.policyname = 'website_pages_select'
      and policy.cmd = 'SELECT'
      and policy.roles = array['authenticated']::name[]
      and policy.qual like '%is_published%'
      and policy.qual like '%can_edit_tenant_settings(tenant_id)%'
  ),
  'authenticated page reads expose published rows or rows with explicit editor authority'
);

select ok(
  exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename = 'website_blocks'
      and policy.policyname = 'website_blocks_select'
      and policy.cmd = 'SELECT'
      and policy.roles = array['authenticated']::name[]
      and policy.qual = 'can_edit_tenant_settings(tenant_id)'
  ),
  'the private block read policy requires explicit editor authority'
);

select ok(
  has_table_privilege('anon', 'public.website_pages', 'SELECT')
  and not has_table_privilege('anon', 'public.website_pages', 'INSERT')
  and not has_table_privilege('anon', 'public.website_pages', 'UPDATE')
  and not has_table_privilege('anon', 'public.website_pages', 'DELETE')
  and not has_table_privilege('anon', 'public.website_pages', 'TRUNCATE')
  and not has_table_privilege('anon', 'public.website_pages', 'REFERENCES')
  and not has_table_privilege('anon', 'public.website_pages', 'TRIGGER')
  and has_table_privilege('authenticated', 'public.website_pages', 'SELECT')
  and has_table_privilege('authenticated', 'public.website_pages', 'INSERT')
  and has_table_privilege('authenticated', 'public.website_pages', 'UPDATE')
  and has_table_privilege('authenticated', 'public.website_pages', 'DELETE')
  and not has_table_privilege(
    'authenticated',
    'public.website_pages',
    'TRUNCATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.website_pages',
    'REFERENCES'
  )
  and not has_table_privilege(
    'authenticated',
    'public.website_pages',
    'TRIGGER'
  )
  and has_table_privilege('service_role', 'public.website_pages', 'SELECT')
  and has_table_privilege('service_role', 'public.website_pages', 'INSERT')
  and has_table_privilege('service_role', 'public.website_pages', 'UPDATE')
  and has_table_privilege('service_role', 'public.website_pages', 'DELETE')
  and has_table_privilege('service_role', 'public.website_pages', 'TRUNCATE')
  and has_table_privilege('service_role', 'public.website_pages', 'REFERENCES')
  and has_table_privilege('service_role', 'public.website_pages', 'TRIGGER'),
  'website_pages ACL is anon SELECT, authenticated CRUD, and service_role ALL'
);

select ok(
  has_table_privilege('anon', 'public.website_blocks', 'SELECT')
  and not has_table_privilege('anon', 'public.website_blocks', 'INSERT')
  and not has_table_privilege('anon', 'public.website_blocks', 'UPDATE')
  and not has_table_privilege('anon', 'public.website_blocks', 'DELETE')
  and not has_table_privilege('anon', 'public.website_blocks', 'TRUNCATE')
  and not has_table_privilege('anon', 'public.website_blocks', 'REFERENCES')
  and not has_table_privilege('anon', 'public.website_blocks', 'TRIGGER')
  and has_table_privilege('authenticated', 'public.website_blocks', 'SELECT')
  and has_table_privilege('authenticated', 'public.website_blocks', 'INSERT')
  and has_table_privilege('authenticated', 'public.website_blocks', 'UPDATE')
  and has_table_privilege('authenticated', 'public.website_blocks', 'DELETE')
  and not has_table_privilege(
    'authenticated',
    'public.website_blocks',
    'TRUNCATE'
  )
  and not has_table_privilege(
    'authenticated',
    'public.website_blocks',
    'REFERENCES'
  )
  and not has_table_privilege(
    'authenticated',
    'public.website_blocks',
    'TRIGGER'
  )
  and has_table_privilege('service_role', 'public.website_blocks', 'SELECT')
  and has_table_privilege('service_role', 'public.website_blocks', 'INSERT')
  and has_table_privilege('service_role', 'public.website_blocks', 'UPDATE')
  and has_table_privilege('service_role', 'public.website_blocks', 'DELETE')
  and has_table_privilege('service_role', 'public.website_blocks', 'TRUNCATE')
  and has_table_privilege('service_role', 'public.website_blocks', 'REFERENCES')
  and has_table_privilege('service_role', 'public.website_blocks', 'TRIGGER'),
  'website_blocks ACL is anon SELECT, authenticated CRUD, and service_role ALL'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name)
values
  (
    '7e300916-0000-4000-8000-000000000001',
    'Website editor read tenant A'
  ),
  (
    '7e300916-0000-4000-8000-000000000002',
    'Website editor read tenant B'
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
    '7e300916-0000-4000-8000-000000000090',
    'authenticated',
    'authenticated',
    'website-editor-read-admin@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e300916-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '7e300916-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'website-editor-read-mechanic@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e300916-0000-4000-8000-000000000001'
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
    '7e300916-0000-4000-8000-000000000090',
    '7e300916-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '7e300916-0000-4000-8000-000000000091',
    '7e300916-0000-4000-8000-000000000001',
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
  template,
  created_at,
  updated_at
)
values
  (
    '7e300916-0000-4000-8000-000000000010',
    '7e300916-0000-4000-8000-000000000001',
    'home-choice-a',
    'Home choice A',
    false,
    true,
    true,
    'default',
    '2026-07-30 09:16:30+00'::timestamptz,
    '2026-07-30 09:16:30+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000011',
    '7e300916-0000-4000-8000-000000000001',
    'home-choice-b',
    'Home choice B',
    false,
    true,
    true,
    'default',
    '2026-07-30 09:16:30+00'::timestamptz,
    '2026-07-30 09:16:30+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000012',
    '7e300916-0000-4000-8000-000000000001',
    'older-non-home',
    'Older non-home page',
    false,
    false,
    false,
    'default',
    '2026-07-29 09:16:30+00'::timestamptz,
    '2026-07-29 09:16:30+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000013',
    '7e300916-0000-4000-8000-000000000001',
    'public-page',
    'Published page',
    true,
    false,
    false,
    'default',
    '2026-07-30 09:17:00+00'::timestamptz,
    '2026-07-30 09:17:00+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000014',
    '7e300916-0000-4000-8000-000000000001',
    'draft-page',
    'Draft page',
    false,
    false,
    false,
    'landing',
    '2026-07-30 09:18:00+00'::timestamptz,
    '2026-07-30 09:18:00+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000015',
    '7e300916-0000-4000-8000-000000000002',
    'other-tenant',
    'Other tenant draft',
    false,
    true,
    true,
    'default',
    '2026-07-30 09:19:00+00'::timestamptz,
    '2026-07-30 09:19:00+00'::timestamptz
  );

insert into public.website_blocks (
  id,
  tenant_id,
  page_id,
  block_type,
  block_data,
  is_visible,
  order_index,
  created_at,
  updated_at
)
values
  (
    '7e300916-0000-4000-8000-000000000020',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000013',
    'about',
    '{"marker":"published-visible"}'::jsonb,
    true,
    0,
    '2026-07-30 09:20:00+00'::timestamptz,
    '2026-07-30 09:20:00+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000021',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000013',
    'about',
    '{"marker":"published-hidden"}'::jsonb,
    false,
    1,
    '2026-07-30 09:20:01+00'::timestamptz,
    '2026-07-30 09:20:01+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000022',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000014',
    'hero',
    '{"marker":"draft-null-order"}'::jsonb,
    true,
    null,
    '2026-07-30 09:20:02+00'::timestamptz,
    '2026-07-30 09:20:02+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000023',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000014',
    'cta',
    '{"marker":"draft-hidden"}'::jsonb,
    false,
    0,
    '2026-07-30 09:20:03+00'::timestamptz,
    '2026-07-30 09:20:03+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000024',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000014',
    'features',
    '{"marker":"draft-last"}'::jsonb,
    true,
    1,
    '2026-07-30 09:20:04+00'::timestamptz,
    '2026-07-30 09:20:04+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000025',
    '7e300916-0000-4000-8000-000000000002',
    '7e300916-0000-4000-8000-000000000014',
    'text',
    '{"marker":"mismatched-tenant"}'::jsonb,
    true,
    -1,
    '2026-07-30 09:20:05+00'::timestamptz,
    '2026-07-30 09:20:05+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000026',
    '7e300916-0000-4000-8000-000000000001',
    '7e300916-0000-4000-8000-000000000010',
    'text',
    '{"marker":"other-page"}'::jsonb,
    true,
    0,
    '2026-07-30 09:20:06+00'::timestamptz,
    '2026-07-30 09:20:06+00'::timestamptz
  ),
  (
    '7e300916-0000-4000-8000-000000000027',
    '7e300916-0000-4000-8000-000000000002',
    '7e300916-0000-4000-8000-000000000015',
    'text',
    '{"marker":"other-tenant-page"}'::jsonb,
    true,
    0,
    '2026-07-30 09:20:07+00'::timestamptz,
    '2026-07-30 09:20:07+00'::timestamptz
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300916-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300916-0000-4000-8000-000000000090',
  true
);

set local role authenticated;

select lives_ok(
  $$
    select public.load_editor_page_with_blocks(
      '7e300916-0000-4000-8000-000000000001',
      '  ///DrAfT-PaGe///  '
    )
  $$,
  'an authorized admin can read an unpublished page through a normalized slug'
);

select is(
  (
    select result->>'id'
    from (
      select public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        '  ///DrAfT-PaGe///  '
      ) as result
    ) projection
  ),
  '7e300916-0000-4000-8000-000000000014',
  'the normalized slug resolves the exact tenant draft page'
);

select ok(
  (
    select result @> jsonb_build_object(
      'tenant_id',
      '7e300916-0000-4000-8000-000000000001',
      'slug',
      'draft-page',
      'title',
      'Draft page',
      'template',
      'landing',
      'is_published',
      false
    )
    from (
      select public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        '/draft-page/'
      ) as result
    ) projection
  ),
  'the projection includes the canonical website page fields'
);

select is(
  (
    select array_agg(page_key order by page_key)
    from jsonb_object_keys(
      public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        'draft-page'
      )
    ) as page_keys(page_key)
  ),
  array[
    'created_at',
    'id',
    'is_home',
    'is_published',
    'is_system',
    'meta_description',
    'meta_keywords',
    'meta_title',
    'og_image_url',
    'published_at',
    'slug',
    'template',
    'tenant_id',
    'title',
    'updated_at',
    'website_blocks'
  ]::text[],
  'the security-definer page projection exposes only its exact allowlisted keys'
);

select is(
  (
    select array_agg(
      (item.block->>'id')::uuid
      order by item.position
    )
    from jsonb_array_elements(
      public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        'draft-page'
      )->'website_blocks'
    ) with ordinality as item(block, position)
  ),
  array[
    '7e300916-0000-4000-8000-000000000022',
    '7e300916-0000-4000-8000-000000000023',
    '7e300916-0000-4000-8000-000000000024'
  ]::uuid[],
  'editor blocks are complete and ordered by coalesced order_index then id'
);

select is(
  (
    select array_agg(block_key order by block_key)
    from jsonb_object_keys(
      public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        'draft-page'
      )->'website_blocks'->0
    ) as block_keys(block_key)
  ),
  array[
    'block_data',
    'block_type',
    'created_at',
    'id',
    'is_visible',
    'order_index',
    'page_id',
    'tenant_id',
    'updated_at'
  ]::text[],
  'each editor block exposes only its exact allowlisted keys'
);

select ok(
  (
    select bool_or(
      item.block->'block_data'->>'marker' = 'draft-hidden'
      and (item.block->>'is_visible')::boolean is false
    )
    from jsonb_array_elements(
      public.load_editor_page_with_blocks(
        '7e300916-0000-4000-8000-000000000001',
        'draft-page'
      )->'website_blocks'
    ) as item(block)
  ),
  'hidden blocks remain available to the authorized editor'
);

select ok(
  not (
    public.load_editor_page_with_blocks(
      '7e300916-0000-4000-8000-000000000001',
      'draft-page'
    )->'website_blocks'
  ) @> '[{"block_data":{"marker":"mismatched-tenant"}}]'::jsonb,
  'block projection enforces tenant_id and page_id together'
);

select is(
  public.load_editor_page_with_blocks(
    '7e300916-0000-4000-8000-000000000001',
    ' /// '
  )->>'id',
  '7e300916-0000-4000-8000-000000000010',
  'an empty normalized slug chooses home by is_home, created_at, then id'
);

select is(
  public.load_editor_page_with_blocks(
    '7e300916-0000-4000-8000-000000000001',
    '/missing-authorized-page/'
  ),
  null::jsonb,
  'an authorized missing page returns null'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300916-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300916-0000-4000-8000-000000000091',
  true
);

set local role authenticated;

select throws_ok(
  $$
    select public.load_editor_page_with_blocks(
      '7e300916-0000-4000-8000-000000000001',
      'missing-for-mechanic'
    )
  $$,
  '42501',
  'website_editor_page_read_forbidden',
  'tenant membership without edit_settings is rejected before missing-page lookup'
);

select is(
  (
    select count(*)
    from public.website_pages page
    where page.id = '7e300916-0000-4000-8000-000000000013'
  ),
  1::bigint,
  'a mechanic can still read a published website page'
);

select is(
  (
    select count(*)
    from public.website_pages page
    where page.id = '7e300916-0000-4000-8000-000000000014'
  ),
  0::bigint,
  'a mechanic cannot directly read a draft website page'
);

select is(
  (
    select count(*)
    from public.website_blocks block
    where block.id = '7e300916-0000-4000-8000-000000000020'
  ),
  1::bigint,
  'a mechanic can still read a visible block on a published page'
);

select is(
  (
    select count(*)
    from public.website_blocks block
    where block.id in (
      '7e300916-0000-4000-8000-000000000021',
      '7e300916-0000-4000-8000-000000000022',
      '7e300916-0000-4000-8000-000000000023',
      '7e300916-0000-4000-8000-000000000024'
    )
  ),
  0::bigint,
  'a mechanic cannot directly read hidden or draft-page blocks'
);

reset role;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e300916-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e300916-0000-4000-8000-000000000090',
  true
);

set local role authenticated;

select throws_ok(
  $$
    select public.load_editor_page_with_blocks(
      '7e300916-0000-4000-8000-000000000002',
      'other-tenant'
    )
  $$,
  '42501',
  'website_editor_page_read_forbidden',
  'an editor cannot read another tenant even when the page exists'
);

reset role;

update public.user_profiles
set is_active = false
where user_id = '7e300916-0000-4000-8000-000000000090'
  and tenant_id = '7e300916-0000-4000-8000-000000000001';

set local role authenticated;

select throws_ok(
  $$
    select public.load_editor_page_with_blocks(
      '7e300916-0000-4000-8000-000000000001',
      'draft-page'
    )
  $$,
  '42501',
  'website_editor_page_read_forbidden',
  'a remote authority revocation is enforced after an earlier successful read'
);

reset role;

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);

set local role anon;

select is(
  (
    select count(*)
    from public.website_pages page
    where page.id = '7e300916-0000-4000-8000-000000000013'
  ),
  1::bigint,
  'anonymous storefront visitors retain published page access'
);

select is(
  (
    select count(*)
    from public.website_pages page
    where page.id = '7e300916-0000-4000-8000-000000000014'
  ),
  0::bigint,
  'anonymous storefront visitors cannot read draft pages'
);

select is(
  (
    select count(*)
    from public.website_blocks block
    where block.id = '7e300916-0000-4000-8000-000000000020'
  ),
  1::bigint,
  'anonymous storefront visitors retain published visible block access'
);

select is(
  (
    select count(*)
    from public.website_blocks block
    where block.id in (
      '7e300916-0000-4000-8000-000000000021',
      '7e300916-0000-4000-8000-000000000022',
      '7e300916-0000-4000-8000-000000000023',
      '7e300916-0000-4000-8000-000000000024'
    )
  ),
  0::bigint,
  'anonymous storefront visitors cannot read hidden or draft-page blocks'
);

reset role;

select * from finish();

rollback;
