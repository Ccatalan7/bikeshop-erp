-- Website navigation: editor-only writes and the default footer seed command.
--
-- This is the part of 20260728223000_harden_website_navigation_seed that
-- production still lacks. That July file was never applied there, and it
-- cannot be applied whole any more: its copy of get_public_store_data(uuid)
-- predates 20260924030000_public_store_data_declares_tenant (applied), and
-- running it would put the July store payload back. The ERP has been calling
-- ensure_default_footer_navigation since July and getting «function does not
-- exist» (found 2026-10-14 comparing the client's 289 RPC names with
-- pg_proc).
--
-- Recovery: restore the tenant-membership policies
-- (tenant_id = (select user_tenant_id())) and drop
-- public.ensure_default_footer_navigation(uuid). Existing navigation rows are
-- unchanged.

begin;

drop policy if exists "website_navigation_insert"
  on public.website_navigation;
drop policy if exists "website_navigation_update"
  on public.website_navigation;
drop policy if exists "website_navigation_delete"
  on public.website_navigation;

create policy "website_navigation_insert"
on public.website_navigation
for insert
to authenticated
with check (public.can_edit_tenant_settings(tenant_id));

create policy "website_navigation_update"
on public.website_navigation
for update
to authenticated
using (public.can_edit_tenant_settings(tenant_id))
with check (public.can_edit_tenant_settings(tenant_id));

create policy "website_navigation_delete"
on public.website_navigation
for delete
to authenticated
using (public.can_edit_tenant_settings(tenant_id));

create or replace function public.ensure_default_footer_navigation(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_links_parent_id uuid := gen_random_uuid();
  v_information_parent_id uuid := gen_random_uuid();
  v_created boolean := false;
  v_items jsonb := '[]'::jsonb;
begin
  if v_caller_id is null
     or p_tenant_id is null
     or public.user_tenant_id() is distinct from p_tenant_id
     or not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'website_navigation_seed_forbidden'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'website_default_footer:' || p_tenant_id::text,
      0
    )
  );

  if not exists (
    select 1
    from public.website_navigation navigation
    where navigation.tenant_id = p_tenant_id
      and navigation.menu_location = 'footer'
  ) then
    insert into public.website_navigation (
      id,
      tenant_id,
      menu_location,
      label,
      link_type,
      link_value,
      open_in_new_tab,
      parent_id,
      order_index,
      is_visible,
      show_on_desktop,
      show_on_mobile
    )
    values
      (
        v_links_parent_id,
        p_tenant_id,
        'footer',
        'Enlaces',
        'action',
        '',
        false,
        null,
        0,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Inicio',
        'page',
        '/tienda',
        false,
        v_links_parent_id,
        0,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Productos',
        'page',
        '/productos',
        false,
        v_links_parent_id,
        1,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Servicios',
        'page',
        '/servicios',
        false,
        v_links_parent_id,
        2,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Contacto',
        'page',
        '/tienda/contacto',
        false,
        v_links_parent_id,
        3,
        true,
        true,
        true
      ),
      (
        v_information_parent_id,
        p_tenant_id,
        'footer',
        'Información',
        'action',
        '',
        false,
        null,
        1,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Sobre Nosotros',
        'page',
        '/nosotros',
        false,
        v_information_parent_id,
        0,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Términos y Condiciones',
        'page',
        '/terminos',
        false,
        v_information_parent_id,
        1,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Política de Privacidad',
        'page',
        '/privacidad',
        false,
        v_information_parent_id,
        2,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Política de Devoluciones',
        'page',
        '/devoluciones',
        false,
        v_information_parent_id,
        3,
        true,
        true,
        true
      ),
      (
        gen_random_uuid(),
        p_tenant_id,
        'footer',
        'Envíos',
        'page',
        '/envios',
        false,
        v_information_parent_id,
        4,
        true,
        true,
        true
      );

    v_created := true;
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(navigation)
      order by
        navigation.parent_id nulls first,
        navigation.order_index,
        navigation.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.website_navigation navigation
  where navigation.tenant_id = p_tenant_id
    and navigation.menu_location = 'footer';

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'created', v_created,
    'items', v_items
  );
end;
$$;

revoke all on function public.ensure_default_footer_navigation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_default_footer_navigation(uuid)
  to authenticated;


commit;
