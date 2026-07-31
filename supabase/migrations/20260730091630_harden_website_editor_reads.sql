-- Deployment status is tracked externally in migration history and the
-- Website Builder refactor plan; never infer live state from this file.
--
-- Forward behavior:
-- - adds one tenant- and authority-bound editor read projection;
-- - adds one tenant- and authority-bound idempotent navigation delete
--   command (42501 without canonical edit authority;
--   deleted/already_absent outcome);
-- - keeps published CMS reads public while restricting private page/block rows
--   to users with the canonical edit_settings authority; and
-- - reduces website_pages/website_blocks table ACLs to the minimum client
--   privileges required by the existing RLS-governed workflows.
--
-- Recovery:
-- - drop public.load_editor_page_with_blocks(uuid, text);
-- - drop public.delete_website_navigation(uuid, uuid);
-- - restore the prior website_pages_select/website_blocks_select definitions
--   and table grants from the immediately preceding production catalog.
-- No row rewrite or backfill is performed by this migration.

begin;

create or replace function public.load_editor_page_with_blocks(
  p_tenant_id uuid,
  p_slug text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_tenant_id uuid := public.user_tenant_id();
  v_normalized_slug text;
  v_page public.website_pages%rowtype;
  v_blocks jsonb;
begin
  if v_caller_id is null
     or p_tenant_id is null
     or v_caller_tenant_id is distinct from p_tenant_id
     or not coalesce(
       public.can_edit_tenant_settings(p_tenant_id),
       false
     ) then
    raise exception 'website_editor_page_read_forbidden'
      using errcode = '42501';
  end if;

  v_normalized_slug := lower(
    btrim(
      regexp_replace(
        btrim(coalesce(p_slug, '')),
        '^/+|/+$',
        '',
        'g'
      )
    )
  );

  if v_normalized_slug = '' then
    select page.*
    into v_page
    from public.website_pages page
    where page.tenant_id = p_tenant_id
    order by
      coalesce(page.is_home, false) desc,
      page.created_at asc,
      page.id asc
    limit 1;
  else
    select page.*
    into v_page
    from public.website_pages page
    where page.tenant_id = p_tenant_id
      and page.slug = v_normalized_slug
    order by page.id asc
    limit 1;
  end if;

  if v_page.id is null then
    return null;
  end if;

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
      order by coalesce(block.order_index, 0), block.id
    ),
    '[]'::jsonb
  )
  into v_blocks
  from public.website_blocks block
  where block.tenant_id = p_tenant_id
    and block.page_id = v_page.id;

  return jsonb_build_object(
    'id', v_page.id,
    'tenant_id', v_page.tenant_id,
    'slug', v_page.slug,
    'title', v_page.title,
    'meta_title', v_page.meta_title,
    'meta_description', v_page.meta_description,
    'meta_keywords', v_page.meta_keywords,
    'og_image_url', v_page.og_image_url,
    'is_published', v_page.is_published,
    'is_home', v_page.is_home,
    'is_system', v_page.is_system,
    'template', v_page.template,
    'published_at', v_page.published_at,
    'created_at', v_page.created_at,
    'updated_at', v_page.updated_at,
    'website_blocks', v_blocks
  );
end;
$$;

comment on function public.load_editor_page_with_blocks(uuid, text) is
  'Authority-bound Website Builder page projection including draft and hidden blocks.';

revoke all on function public.load_editor_page_with_blocks(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.load_editor_page_with_blocks(uuid, text)
  to authenticated;

alter table public.website_pages enable row level security;
alter table public.website_blocks enable row level security;

drop policy if exists "website_pages_select" on public.website_pages;
create policy "website_pages_select"
on public.website_pages
for select
to authenticated
using (
  is_published is true
  or public.can_edit_tenant_settings(tenant_id)
);

drop policy if exists "website_blocks_select" on public.website_blocks;
create policy "website_blocks_select"
on public.website_blocks
for select
to authenticated
using (public.can_edit_tenant_settings(tenant_id));

revoke all on table public.website_pages
  from public, anon, authenticated, service_role;
grant select on table public.website_pages to anon;
grant select, insert, update, delete
  on table public.website_pages
  to authenticated;
grant all on table public.website_pages to service_role;

revoke all on table public.website_blocks
  from public, anon, authenticated, service_role;
grant select on table public.website_blocks to anon;
grant select, insert, update, delete
  on table public.website_blocks
  to authenticated;
grant all on table public.website_blocks to service_role;

-- --------------------------------------------------------------------------
-- Authority-bound, idempotent navigation delete.
--
-- A plain PostgREST DELETE returns no rows: with a stale cached grant, RLS
-- silently filters to 0 rows and the client mistakes "nothing deleted" for
-- success. This command validates the canonical authority INSIDE the same
-- transaction, raises 42501 without it, and reports deleted/already_absent
-- so a retry after a lost response converges without a false success.
-- --------------------------------------------------------------------------
create or replace function public.delete_website_navigation(
  p_tenant_id uuid,
  p_navigation_id uuid
)
returns text
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_tenant_id uuid := public.user_tenant_id();
  v_deleted_id uuid;
begin
  if v_caller_id is null
     or p_tenant_id is null
     or p_navigation_id is null
     or v_caller_tenant_id is distinct from p_tenant_id
     or not coalesce(
       public.can_edit_tenant_settings(p_tenant_id),
       false
     ) then
    raise exception 'website_navigation_delete_forbidden'
      using errcode = '42501';
  end if;

  delete from public.website_navigation nav
  where nav.tenant_id = p_tenant_id
    and nav.id = p_navigation_id
  returning nav.id into v_deleted_id;

  if v_deleted_id is null then
    -- Idempotent retry after a lost response: the row is gone and the
    -- caller may confirm its acknowledgement.
    return 'already_absent';
  end if;
  return 'deleted';
end;
$$;

comment on function public.delete_website_navigation(uuid, uuid) is
  'Authority-bound idempotent Website Builder navigation delete '
  '(42501 without canonical edit authority; deleted/already_absent).';

revoke all on function public.delete_website_navigation(uuid, uuid)
  from public, anon, authenticated, service_role;
-- Only interactive ERP callers: service_role keeps its table-level access
-- and never needs (nor should route through) the identity-bound command.
grant execute on function public.delete_website_navigation(uuid, uuid)
  to authenticated;

commit;
