-- Deployment status: DEPLOYED AND VERIFIED in production
-- xzdvtzdqjeyqxnkqprtf on 2026-07-29; registered as 20260729010000.
-- Verification: 29/29 production-derived pgTAP assertions, exact live
-- definition/ACL/history read-back, unchanged page/block aggregates, and DB
-- health.
--
-- Replace one Website Builder page's complete block document in a single
-- tenant-authorized transaction. The prior client path issued DELETE and
-- INSERT as independent PostgREST requests, so an insert failure could leave a
-- published page empty.

begin;

create or replace function public.replace_page_blocks(
  p_tenant_id uuid,
  p_page_id uuid,
  p_blocks jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_caller_id is null
     or p_tenant_id is null
     or p_page_id is null
     or public.user_tenant_id() is distinct from p_tenant_id
     or not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'website_page_blocks_replace_forbidden'
      using errcode = '42501';
  end if;

  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'website_page_blocks_invalid_payload'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'website_page_blocks:' || p_tenant_id::text || ':' || p_page_id::text,
      0
    )
  );

  perform 1
  from public.website_pages page
  where page.id = p_page_id
    and page.tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'website_page_blocks_page_not_found'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_blocks) requested(block)
    where jsonb_typeof(requested.block) <> 'object'
      or jsonb_typeof(requested.block->'block_type') <> 'string'
      or nullif(btrim(requested.block->>'block_type'), '') is null
      or (
        requested.block ? 'block_data'
        and jsonb_typeof(requested.block->'block_data') <> 'object'
      )
      or (
        requested.block ? 'is_visible'
        and jsonb_typeof(requested.block->'is_visible') <> 'boolean'
      )
  ) then
    raise exception 'website_page_blocks_invalid_payload'
      using errcode = '22023';
  end if;

  begin
    if exists (
      select 1
      from (
        select nullif(btrim(requested.block->>'id'), '')::uuid as block_id
        from jsonb_array_elements(p_blocks) requested(block)
      ) parsed
      where parsed.block_id is not null
      group by parsed.block_id
      having count(*) > 1
    ) then
      raise exception 'website_page_blocks_duplicate_id'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from (
        select nullif(btrim(requested.block->>'id'), '')::uuid as block_id
        from jsonb_array_elements(p_blocks) requested(block)
      ) parsed
      join public.website_blocks existing
        on existing.id = parsed.block_id
      where existing.tenant_id is distinct from p_tenant_id
         or existing.page_id is distinct from p_page_id
    ) then
      raise exception 'website_page_blocks_id_out_of_scope'
        using errcode = '22023';
    end if;
  exception
    when invalid_text_representation then
      raise exception 'website_page_blocks_invalid_id'
        using errcode = '22023';
  end;

  -- An empty array intentionally removes every block from this page only.
  delete from public.website_blocks existing
  where existing.tenant_id = p_tenant_id
    and existing.page_id = p_page_id;

  insert into public.website_blocks (
    id,
    tenant_id,
    page_id,
    block_type,
    block_data,
    is_visible,
    order_index,
    updated_at
  )
  select
    coalesce(
      nullif(btrim(requested.block->>'id'), '')::uuid,
      gen_random_uuid()
    ),
    p_tenant_id,
    p_page_id,
    btrim(requested.block->>'block_type'),
    coalesce(requested.block->'block_data', '{}'::jsonb),
    coalesce((requested.block->>'is_visible')::boolean, true),
    (requested.ordinality - 1)::integer,
    clock_timestamp()
  from jsonb_array_elements(p_blocks)
    with ordinality as requested(block, ordinality)
  order by requested.ordinality;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', block.id,
        'tenant_id', block.tenant_id,
        'page_id', block.page_id,
        'block_type', block.block_type,
        'block_data', block.block_data,
        'is_visible', block.is_visible,
        'order_index', block.order_index,
        'created_at', block.created_at,
        'updated_at', block.updated_at
      )
      order by block.order_index, block.id
    ),
    '[]'::jsonb
  )
  into v_result
  from public.website_blocks block
  where block.tenant_id = p_tenant_id
    and block.page_id = p_page_id;

  return v_result;
end;
$$;

comment on function public.replace_page_blocks(uuid, uuid, jsonb) is
  'Atomically replaces the complete ordered block document for one tenant page; p_blocks is required and an explicit empty array intentionally clears that page.';

revoke all on function public.replace_page_blocks(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.replace_page_blocks(uuid, uuid, jsonb)
  to authenticated;

commit;
