-- Harden Website Builder navigation ownership and make the default footer seed
-- one authorized, tenant-serialized database command.
--
-- Deployment status: not deployed.
-- Recovery: restore the prior tenant-membership policies and drop
-- public.ensure_default_footer_navigation(uuid). Existing navigation rows are
-- unchanged by this migration.

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

-- Every public-store aggregate carries its owner identity. Clients must reject
-- any cache/prefetch payload whose tenant_id differs from the requested scope.
create or replace function public.get_public_store_data(p_tenant_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  settings_value json;
  blocks_value json;
  home_page_id_value uuid;
begin
  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    return json_build_object(
      'tenant_id', p_tenant_id,
      'settings', '{}'::json,
      'blocks', '[]'::json,
      'home_page_id', null
    );
  end if;

  select page.id
  into home_page_id_value
  from public.website_pages page
  where page.tenant_id = p_tenant_id
    and page.is_home is true
    and page.is_published is true
  order by page.created_at, page.id
  limit 1;

  if home_page_id_value is null then
    select page.id
    into home_page_id_value
    from public.website_pages page
    where page.tenant_id = p_tenant_id
      and page.is_published is true
    order by page.created_at, page.id
    limit 1;
  end if;

  select coalesce(
    json_object_agg(setting.key, setting.value),
    '{}'::json
  )
  into settings_value
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and not public.website_setting_is_sensitive(setting.key);

  select coalesce(
    json_agg(
      json_build_object(
        'id', block.id,
        'block_type', block.block_type,
        'block_data', block.block_data,
        'is_visible', block.is_visible,
        'order_index', block.order_index
      )
      order by block.order_index, block.id
    ),
    '[]'::json
  )
  into blocks_value
  from public.website_blocks block
  where block.tenant_id = p_tenant_id
    and block.page_id = home_page_id_value
    and block.is_visible is true;

  return json_build_object(
    'tenant_id', p_tenant_id,
    'settings', settings_value,
    'blocks', blocks_value,
    'home_page_id', home_page_id_value
  );
end;
$$;

revoke all on function public.get_public_store_data(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_store_data(uuid)
  to anon, authenticated;

commit;
