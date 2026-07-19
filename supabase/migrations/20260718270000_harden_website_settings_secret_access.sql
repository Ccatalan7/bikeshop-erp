-- Deployment status: PENDING immediate production rollout.
--
-- An obsolete anonymous SELECT policy named website_settings_select_public
-- used using(true) and therefore OR-ed around the later secret-name filter.
-- Default table grants also left destructive privileges on API roles. Keep
-- public storefront configuration readable, but make sensitive names
-- fail-closed for both current and future keys.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.website_setting_is_sensitive(p_key text)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select lower(btrim(coalesce(p_key, ''))) ~
    '(access[_-]?token|refresh[_-]?token|secret|password|private|credential|api[_-]?key)';
$$;

revoke all on function public.website_setting_is_sensitive(text)
  from public, anon, authenticated, service_role;
grant execute on function public.website_setting_is_sensitive(text)
  to anon, authenticated, service_role;

drop policy if exists website_settings_select_public
  on public.website_settings;
drop policy if exists public_website_settings_select
  on public.website_settings;
drop policy if exists public_website_settings_select_authenticated
  on public.website_settings;
drop policy if exists website_settings_select
  on public.website_settings;

create policy public_website_settings_select
  on public.website_settings
  for select
  to anon
  using (
    tenant_id is not null
    and not public.website_setting_is_sensitive(key)
  );

create policy public_website_settings_select_authenticated
  on public.website_settings
  for select
  to authenticated
  using (
    tenant_id is not null
    and not public.website_setting_is_sensitive(key)
  );

-- Authenticated ERP users may read ordinary settings only for their tenant.
-- The public policy above already permits the non-sensitive projection needed
-- by the storefront, while service_role remains the sole secret reader.
create policy website_settings_select
  on public.website_settings
  for select
  to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and not public.website_setting_is_sensitive(key)
  );

revoke all on table public.website_settings from public, anon, authenticated;
grant select on table public.website_settings to anon;
grant select, insert, update, delete on table public.website_settings
  to authenticated;
grant all on table public.website_settings to service_role;

comment on function public.website_setting_is_sensitive(text) is
  'Fail-closed key classifier preventing public/authenticated reads of provider credentials stored in website_settings.';

commit;
