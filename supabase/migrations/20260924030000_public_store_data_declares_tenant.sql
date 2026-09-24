-- La proyección pública de la tienda declara su tenant.
--
-- Desde 2026-07-31 (04f271d0) la tienda acepta el payload de
-- `get_public_store_data` sólo si trae `tenant_id` igual al tenant pedido
-- (`WebsiteService._validatedPublicStorePayload`), y lo mismo exigen la
-- precarga de `web/index.html` y el worker de caché del borde. La función
-- nunca lo devolvió: cada carga descartaba la precarga y la respuesta directa
-- («La proyección pública no declaró el tenant solicitado») y repetía el
-- trabajo con consultas separadas. En un móvil lento son idas y vueltas de más
-- justo cuando la tienda ya arrancó (medido en producción el 2026-09-24).
--
-- Sólo se agrega `tenant_id` a la respuesta de un tenant activo. Un tenant
-- inactivo sigue sin declararlo: la tienda lo rechaza como antes. El resto de
-- la función queda igual; `create or replace` conserva los permisos.

create or replace function public.get_public_store_data(p_tenant_id uuid)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
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
$function$;
