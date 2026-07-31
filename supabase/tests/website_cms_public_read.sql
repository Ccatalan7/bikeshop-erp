begin;

select no_plan();

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'website_blocks'
      and cmd = 'SELECT'
      and 'public' = any(roles)
      and coalesce(qual, '') ilike '%user_profiles%'
  ),
  'anonymous CMS reads never privilege-check user_profiles'
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
values (
  '7e160000-0000-4000-8000-000000000001',
  'Public CMS Policy Test',
  'public-cms-policy-test',
  'owner-public-cms@example.invalid',
  'America/Santiago',
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
values (
  '7e160000-0000-4000-8000-000000000010',
  '7e160000-0000-4000-8000-000000000001',
  'terminos-prueba',
  'Términos de prueba',
  true,
  false,
  false,
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
    '7e160000-0000-4000-8000-000000000020',
    '7e160000-0000-4000-8000-000000000001',
    '7e160000-0000-4000-8000-000000000010',
    'about',
    0,
    true,
    '{"title":"Visible"}'::jsonb
  ),
  (
    '7e160000-0000-4000-8000-000000000021',
    '7e160000-0000-4000-8000-000000000001',
    '7e160000-0000-4000-8000-000000000010',
    'about',
    1,
    false,
    '{"title":"Draft"}'::jsonb
  );

set local session_replication_role = origin;
set local role anon;

select lives_ok(
  $query$
    select page.slug, jsonb_agg(block.block_data)
    from public.website_pages page
    join public.website_blocks block on block.page_id = page.id
    where page.tenant_id = '7e160000-0000-4000-8000-000000000001'
      and page.slug = 'terminos-prueba'
      and page.is_published = true
    group by page.slug
  $query$,
  'anonymous visitors can read a published CMS page with embedded blocks'
);

select is(
  (
    select count(*)
    from public.website_blocks
    where tenant_id = '7e160000-0000-4000-8000-000000000001'
  ),
  1::bigint,
  'anonymous visitors see only visible CMS blocks'
);

reset role;

select * from finish();
rollback;
