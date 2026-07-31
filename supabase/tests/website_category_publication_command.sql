begin;

select no_plan();

select has_function(
  'public',
  'replace_website_category_visibility',
  array['uuid', 'uuid[]'],
  'website category publication has one canonical transactional command'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.replace_website_category_visibility(uuid,uuid[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.replace_website_category_visibility(uuid,uuid[])',
    'EXECUTE'
  ),
  'only authenticated ERP users can execute the publication command'
);

select ok(
  (
    select procedure_record.prosecdef
      and owner_role.rolname = 'postgres'
      and procedure_record.proconfig =
        array['search_path=pg_catalog, public, pg_temp']::text[]
    from pg_proc procedure_record
    join pg_roles owner_role
      on owner_role.oid = procedure_record.proowner
    where procedure_record.oid =
      'public.replace_website_category_visibility(uuid,uuid[])'::regprocedure
  ),
  'the command has a fixed trusted search path and explicit tenant authorization'
);

insert into public.tenants (id, shop_name)
values
  (
    '7e180000-0000-4000-8000-000000000001',
    'Website publication tenant A'
  ),
  (
    '7e180000-0000-4000-8000-000000000002',
    'Website publication tenant B'
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
values (
  '7e180000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'website-publication@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id',
    '7e180000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
), (
  '7e180000-0000-4000-8000-000000000098',
  'authenticated',
  'authenticated',
  'website-publication-readonly@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id',
    '7e180000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values
  (
    '7e180000-0000-4000-8000-000000000099',
    '7e180000-0000-4000-8000-000000000001',
    'admin'
  ),
  (
    '7e180000-0000-4000-8000-000000000098',
    '7e180000-0000-4000-8000-000000000001',
    'mechanic'
  );

insert into public.product_categories (
  id,
  tenant_id,
  name,
  full_path,
  level,
  show_on_website,
  is_active,
  updated_at
)
values
  (
    '7e180000-0000-4000-8000-000000000010',
    '7e180000-0000-4000-8000-000000000001',
    'Cadenas',
    'Componentes / Transmisión / Cadenas',
    2,
    true,
    true,
    '2026-01-01 00:00:00+00'
  ),
  (
    '7e180000-0000-4000-8000-000000000011',
    '7e180000-0000-4000-8000-000000000001',
    'Cassette',
    'Componentes / Transmisión / Piñones / Cassette',
    3,
    true,
    true,
    '2026-01-01 00:00:00+00'
  ),
  (
    '7e180000-0000-4000-8000-000000000012',
    '7e180000-0000-4000-8000-000000000001',
    'Volantes',
    'Componentes / Transmisión / Volantes',
    2,
    false,
    true,
    '2026-01-01 00:00:00+00'
  ),
  (
    '7e180000-0000-4000-8000-000000000020',
    '7e180000-0000-4000-8000-000000000002',
    'Tenant B',
    'Tenant B',
    0,
    true,
    true,
    '2026-01-01 00:00:00+00'
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e180000-0000-4000-8000-000000000099',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e180000-0000-4000-8000-000000000099',
  true
);

set local role authenticated;

select lives_ok(
  $$select public.replace_website_category_visibility(
    '7e180000-0000-4000-8000-000000000001',
    array[
      '7e180000-0000-4000-8000-000000000010',
      '7e180000-0000-4000-8000-000000000012'
    ]::uuid[]
  )$$,
  'the authenticated tenant replaces its selected set atomically'
);

select is(
  (
    select array_agg(category.id order by category.id)
    from public.product_categories category
    where category.tenant_id = '7e180000-0000-4000-8000-000000000001'
      and category.show_on_website is true
  ),
  array[
    '7e180000-0000-4000-8000-000000000010',
    '7e180000-0000-4000-8000-000000000012'
  ]::uuid[],
  'the command preserves exactly the requested categories without ancestors'
);

select is(
  (
    select category.updated_at
    from public.product_categories category
    where category.id = '7e180000-0000-4000-8000-000000000010'
  ),
  '2026-01-01 00:00:00+00'::timestamptz,
  'an unchanged selected category keeps its prior updated_at'
);

select ok(
  (
    select category.updated_at > '2026-01-01 00:00:00+00'::timestamptz
    from public.product_categories category
    where category.id = '7e180000-0000-4000-8000-000000000011'
  )
  and (
    select category.updated_at > '2026-01-01 00:00:00+00'::timestamptz
    from public.product_categories category
    where category.id = '7e180000-0000-4000-8000-000000000012'
  ),
  'only categories whose publication value changed receive a new timestamp'
);

select ok(
  exists (
    select 1
    from public.user_activity_log activity
    where activity.tenant_id = '7e180000-0000-4000-8000-000000000001'
      and activity.user_id = '7e180000-0000-4000-8000-000000000099'
      and activity.action = 'website_category_publication_replaced'
      and activity.details->'added_ids' = jsonb_build_array(
        '7e180000-0000-4000-8000-000000000012'
      )
      and activity.details->'removed_ids' = jsonb_build_array(
        '7e180000-0000-4000-8000-000000000011'
      )
  ),
  'the command records actor and exact added/removed category evidence'
);

select throws_ok(
  $$select public.replace_website_category_visibility(
    '7e180000-0000-4000-8000-000000000001',
    array['7e180000-0000-4000-8000-000000000020']::uuid[]
  )$$,
  '22023',
  'website_category_publication_invalid_category',
  'a category from another tenant is rejected'
);

select throws_ok(
  $$select public.replace_website_category_visibility(
    '7e180000-0000-4000-8000-000000000002',
    '{}'::uuid[]
  )$$,
  '42501',
  'website_category_publication_tenant_forbidden',
  'the caller cannot replace another tenant publication set'
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e180000-0000-4000-8000-000000000098',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e180000-0000-4000-8000-000000000098',
  true
);
set local role authenticated;

select throws_ok(
  $$select public.replace_website_category_visibility(
    '7e180000-0000-4000-8000-000000000001',
    '{}'::uuid[]
  )$$,
  '42501',
  'website_category_publication_tenant_forbidden',
  'tenant membership without edit_settings cannot change public categories'
);

reset role;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e180000-0000-4000-8000-000000000099',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e180000-0000-4000-8000-000000000099',
  true
);
set local role authenticated;

select is(
  (
    select array_agg(category.id order by category.id)
    from public.product_categories category
    where category.tenant_id = '7e180000-0000-4000-8000-000000000001'
      and category.show_on_website is true
  ),
  array[
    '7e180000-0000-4000-8000-000000000010',
    '7e180000-0000-4000-8000-000000000012'
  ]::uuid[],
  'a rejected replacement leaves the existing public set intact'
);

reset role;

select * from finish();
rollback;
