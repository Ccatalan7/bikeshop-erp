-- The store server asks whether the shared shell changed before reading it.
--
-- Every page of vinabike.cl read the whole shell (menus, categories, public
-- settings, shipping tiers: ~200 kB, ~37 kB compressed) and crawlers ask for
-- ~4,400 pages a day: the largest share of the project's egress, for a value
-- that only changes when someone edits the site (2026-10-31). The server
-- keeps the last shell with the stamp this function gave it and asks again
-- at most every few seconds; the answer carries the shell only when the
-- stamp it knows is no longer current.
--
-- Same reads as `get_public_storefront_shell_v1` (security invoker, same
-- grants), so it shows the public key nothing more than the shell does.

create or replace function public.get_public_storefront_shell_if_changed_v1(
  p_tenant_id uuid,
  p_known_stamp text default null
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  with shell as (
    select value, md5(value::text) as stamp
      from (
        select public.get_public_storefront_shell_v1(p_tenant_id) as value
      ) read
  )
  select case
    when p_known_stamp is not null and p_known_stamp = shell.stamp
      then jsonb_build_object('stamp', shell.stamp)
    else jsonb_build_object('stamp', shell.stamp, 'shell', shell.value)
  end
  from shell;
$$;

comment on function public.get_public_storefront_shell_if_changed_v1(uuid, text) is
  'The shared shell of every public page with its stamp (md5 of the shell). When p_known_stamp is still current the answer is only {stamp}: the store server reads the ~200 kB shell only when it changed. Security invoker over get_public_storefront_shell_v1.';

revoke all on function public.get_public_storefront_shell_if_changed_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_storefront_shell_if_changed_v1(uuid, text)
  to anon, authenticated, service_role;
