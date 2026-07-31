begin;

select no_plan();

select has_function(
  'public',
  'replace_page_blocks',
  array['uuid', 'uuid', 'jsonb'],
  'page blocks have one canonical transactional replacement command'
);

select is(
  (
    select procedure_record.pronargdefaults
    from pg_proc procedure_record
    where procedure_record.oid =
      'public.replace_page_blocks(uuid,uuid,jsonb)'::regprocedure
  ),
  0::smallint,
  'the block payload is mandatory so omission cannot mean destructive empty'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001'::uuid,
      '7e290100-0000-4000-8000-000000000010'::uuid
    )
  $$,
  '42883',
  'function public.replace_page_blocks(uuid, uuid) does not exist',
  'omitting p_blocks is rejected instead of clearing a page'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.replace_page_blocks(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.replace_page_blocks(uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'public',
    'public.replace_page_blocks(uuid,uuid,jsonb)',
    'EXECUTE'
  ),
  'only authenticated ERP users can execute page-block replacement'
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
      'public.replace_page_blocks(uuid,uuid,jsonb)'::regprocedure
  ),
  'the command has a trusted search path and serializes one tenant page'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name)
values
  (
    '7e290100-0000-4000-8000-000000000001',
    'Page blocks tenant A'
  ),
  (
    '7e290100-0000-4000-8000-000000000002',
    'Page blocks tenant B'
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
    '7e290100-0000-4000-8000-000000000090',
    'authenticated',
    'authenticated',
    'page-blocks-admin@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e290100-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '7e290100-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'page-blocks-mechanic@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '7e290100-0000-4000-8000-000000000001'
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
    '7e290100-0000-4000-8000-000000000090',
    '7e290100-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '7e290100-0000-4000-8000-000000000091',
    '7e290100-0000-4000-8000-000000000001',
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
    '7e290100-0000-4000-8000-000000000010',
    '7e290100-0000-4000-8000-000000000001',
    'pagina-a',
    'Pagina A',
    true,
    true,
    true,
    'default'
  ),
  (
    '7e290100-0000-4000-8000-000000000011',
    '7e290100-0000-4000-8000-000000000001',
    'pagina-a-secundaria',
    'Pagina A secundaria',
    true,
    false,
    false,
    'default'
  ),
  (
    '7e290100-0000-4000-8000-000000000012',
    '7e290100-0000-4000-8000-000000000002',
    'pagina-b',
    'Pagina B',
    true,
    true,
    true,
    'default'
  );

insert into public.website_blocks (
  id,
  tenant_id,
  page_id,
  block_type,
  block_data,
  is_visible,
  order_index
)
values
  (
    '7e290100-0000-4000-8000-000000000020',
    '7e290100-0000-4000-8000-000000000001',
    '7e290100-0000-4000-8000-000000000010',
    'about',
    '{"marker":"original-a"}'::jsonb,
    true,
    0
  ),
  (
    '7e290100-0000-4000-8000-000000000021',
    '7e290100-0000-4000-8000-000000000001',
    '7e290100-0000-4000-8000-000000000011',
    'about',
    '{"marker":"secondary-a"}'::jsonb,
    true,
    0
  ),
  (
    '7e290100-0000-4000-8000-000000000022',
    '7e290100-0000-4000-8000-000000000002',
    '7e290100-0000-4000-8000-000000000012',
    'about',
    '{"marker":"original-b"}'::jsonb,
    true,
    0
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e290100-0000-4000-8000-000000000090',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e290100-0000-4000-8000-000000000090',
  true
);

set local role authenticated;

select lives_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[
        {
          "id":"7e290100-0000-4000-8000-000000000030",
          "block_type":"hero",
          "block_data":{"marker":"saved-first"},
          "is_visible":true,
          "order_index":99
        },
        {
          "id":"7e290100-0000-4000-8000-000000000031",
          "block_type":"about",
          "block_data":{"marker":"saved-second"},
          "is_visible":false,
          "order_index":-5
        }
      ]'::jsonb
    )
  $$,
  'an authorized editor replaces one page atomically'
);

select is(
  (
    select array_agg(block.id order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array[
    '7e290100-0000-4000-8000-000000000030',
    '7e290100-0000-4000-8000-000000000031'
  ]::uuid[],
  'provided block IDs are preserved'
);

select is(
  (
    select array_agg(block.order_index order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array[0, 1]::integer[],
  'JSON array ordinal position is the deterministic saved order'
);

select is(
  (
    select block.block_data->>'marker'
    from public.website_blocks block
    where block.id = '7e290100-0000-4000-8000-000000000021'
  ),
  'secondary-a',
  'replacing one page does not change another page in the tenant'
);

select is(
  (
    select block.block_data->>'marker'
    from public.website_blocks block
    where block.id = '7e290100-0000-4000-8000-000000000022'
  ),
  'original-b',
  'replacing one tenant page does not change another tenant'
);

select lives_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000011',
      '[{
        "block_type":"cta",
        "block_data":{"marker":"generated-id"},
        "is_visible":true
      }]'::jsonb
    )
  $$,
  'a new block may omit its ID'
);

select ok(
  (
    select count(*) = 1 and bool_and(block.id is not null)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000011'
      and block.block_data->>'marker' = 'generated-id'
  ),
  'the command generates an ID for an ID-less new block'
);

select is(
  public.replace_page_blocks(
    '7e290100-0000-4000-8000-000000000001',
    '7e290100-0000-4000-8000-000000000011',
    '[]'::jsonb
  ),
  '[]'::jsonb,
  'an explicit empty array intentionally clears the selected page'
);

select is(
  (
    select count(*)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000011'
  ),
  0::bigint,
  'empty replacement removes no blocks outside the selected page'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000002',
      '7e290100-0000-4000-8000-000000000012',
      '[]'::jsonb
    )
  $$,
  '42501',
  'website_page_blocks_replace_forbidden',
  'an editor cannot replace another tenant page'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000012',
      '[]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_page_not_found',
  'a page ID from another tenant is not a valid page scope'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[{
        "id":"7e290100-0000-4000-8000-000000000022",
        "block_type":"about",
        "block_data":{"marker":"stolen"}
      }]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_id_out_of_scope',
  'an existing block ID cannot move across tenant or page scope'
);

select is(
  (
    select array_agg(block.block_data->>'marker' order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array['saved-first', 'saved-second']::text[],
  'validation failure leaves the current page document unchanged'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '{"not":"an array"}'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_invalid_payload',
  'a non-array payload is rejected before deletion'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[{"block_type":42,"block_data":{}}]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_invalid_payload',
  'block_type must be a JSON string'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[{"block_type":"about","block_data":[]}]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_invalid_payload',
  'block_data must be a JSON object when supplied'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[{"block_type":"about","is_visible":"true"}]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_invalid_payload',
  'is_visible must be a JSON boolean when supplied'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[
        {
          "id":"7e290100-0000-4000-8000-000000000030",
          "block_type":"hero"
        },
        {
          "id":"7e290100-0000-4000-8000-000000000030",
          "block_type":"about"
        }
      ]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_duplicate_id',
  'duplicate block IDs are rejected before replacement'
);

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[{"id":"not-a-uuid","block_type":"about"}]'::jsonb
    )
  $$,
  '22023',
  'website_page_blocks_invalid_id',
  'malformed block IDs are rejected before replacement'
);

select is(
  (
    select array_agg(block.block_data->>'marker' order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array['saved-first', 'saved-second']::text[],
  'all payload validation failures preserve the current page document'
);

reset role;

create function public._test_fail_page_block_insert()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.block_data->>'marker' = 'induced-failure' then
    raise exception 'induced_page_block_failure';
  end if;
  return new;
end;
$$;

create trigger test_fail_page_block_insert
before insert on public.website_blocks
for each row
execute function public._test_fail_page_block_insert();

set local role authenticated;

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[
        {
          "id":"7e290100-0000-4000-8000-000000000040",
          "block_type":"hero",
          "block_data":{"marker":"inserted-before-failure"}
        },
        {
          "id":"7e290100-0000-4000-8000-000000000041",
          "block_type":"about",
          "block_data":{"marker":"induced-failure"}
        }
      ]'::jsonb
    )
  $$,
  'P0001',
  'induced_page_block_failure',
  'an induced insert failure aborts the complete replacement'
);

select is(
  (
    select array_agg(block.id order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array[
    '7e290100-0000-4000-8000-000000000030',
    '7e290100-0000-4000-8000-000000000031'
  ]::uuid[],
  'rollback preserves every original block ID after mid-save failure'
);

select is(
  (
    select array_agg(block.block_data->>'marker' order by block.order_index)
    from public.website_blocks block
    where block.tenant_id = '7e290100-0000-4000-8000-000000000001'
      and block.page_id = '7e290100-0000-4000-8000-000000000010'
  ),
  array['saved-first', 'saved-second']::text[],
  'rollback preserves original block data and order after mid-save failure'
);

reset role;
drop trigger test_fail_page_block_insert on public.website_blocks;
drop function public._test_fail_page_block_insert();

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '7e290100-0000-4000-8000-000000000091',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7e290100-0000-4000-8000-000000000091',
  true
);
set local role authenticated;

select throws_ok(
  $$
    select public.replace_page_blocks(
      '7e290100-0000-4000-8000-000000000001',
      '7e290100-0000-4000-8000-000000000010',
      '[]'::jsonb
    )
  $$,
  '42501',
  'website_page_blocks_replace_forbidden',
  'tenant membership without edit_settings cannot replace public blocks'
);

reset role;

select * from finish();
rollback;
