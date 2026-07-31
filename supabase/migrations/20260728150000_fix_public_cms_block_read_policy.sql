-- Deployment status: applied to production on 2026-07-28 and verified with
-- an exact anonymous read-back of `terminos` plus its four visible blocks.
--
-- Public CMS pages embed website_blocks. The legacy tenant-editor SELECT
-- policy was accidentally granted to PUBLIC and referenced user_profiles.
-- PostgreSQL must privilege-check every applicable policy expression, so an
-- anonymous visitor received 42501 before the separate public-visible policy
-- could authorize the row.

begin;

drop policy if exists "website_blocks_select" on public.website_blocks;

create policy "website_blocks_select"
on public.website_blocks
for select
to authenticated
using (tenant_id = public.user_tenant_id());

commit;
