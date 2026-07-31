-- Deployment status: applied to production on 2026-07-28 and registered as
-- migration 20260728153000. Exact anonymous read-back confirmed the published
-- `terminos` page and its four visible blocks remained available.
--
-- Public visitors may read visible standalone legacy blocks and visible blocks
-- whose canonical website_pages owner is published. Draft-page content must
-- not become public merely because an individual block is marked visible.
--
-- Staff writes remain tenant-scoped through user_tenant_id(). Anonymous
-- visitors have no table-level write capability, so a future permissive policy
-- cannot accidentally widen the public API.

begin;

drop policy if exists "website_blocks_insert" on public.website_blocks;
drop policy if exists "website_blocks_update" on public.website_blocks;
drop policy if exists "website_blocks_delete" on public.website_blocks;
drop policy if exists "public_website_blocks_select" on public.website_blocks;
drop policy if exists "public_website_blocks_select_authenticated"
  on public.website_blocks;
drop policy if exists "website_blocks_select_public" on public.website_blocks;

create policy "website_blocks_insert"
on public.website_blocks
for insert
to authenticated
with check (tenant_id = public.user_tenant_id());

create policy "website_blocks_update"
on public.website_blocks
for update
to authenticated
using (tenant_id = public.user_tenant_id())
with check (tenant_id = public.user_tenant_id());

create policy "website_blocks_delete"
on public.website_blocks
for delete
to authenticated
using (tenant_id = public.user_tenant_id());

create policy "public_website_blocks_select"
on public.website_blocks
for select
to anon
using (
  coalesce(is_visible, true)
  and (
    page_id is null
    or exists (
      select 1
      from public.website_pages page
      where page.id = website_blocks.page_id
        and page.tenant_id = website_blocks.tenant_id
        and page.is_published = true
    )
  )
);

create policy "public_website_blocks_select_authenticated"
on public.website_blocks
for select
to authenticated
using (
  coalesce(is_visible, true)
  and (
    page_id is null
    or exists (
      select 1
      from public.website_pages page
      where page.id = website_blocks.page_id
        and page.tenant_id = website_blocks.tenant_id
        and page.is_published = true
    )
  )
);

revoke insert, update, delete, truncate, references, trigger
  on table public.website_blocks
  from anon;
grant select on table public.website_blocks to anon;

commit;
