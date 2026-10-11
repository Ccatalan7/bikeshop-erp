-- Destacados: las filas antes que el candado (segunda pasada de Codex,
-- 2026-10-11).
--
-- 20261011040000 tomaba el candado de destacados y después los productos
-- nuevos (FOR SHARE). Quien edita un producto toma primero la fila; si una
-- misma transacción editara un producto y luego reemplazara destacados,
-- podía esperar en cruz con otro reemplazo. Ahora se toman primero todas las
-- filas pedidas, en orden, y después el candado. Lo demás no cambia.
--
-- Aceptado, con su motivo: la política del sitio y la visibilidad de la
-- categoría no se toman; si cambian en ese instante, el destacado entra
-- igual, pero la portada aplica la regla al leer y no lo muestra.

create or replace function public.catalog_replace_featured_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_count integer;
  v_previous uuid[];
  v_name text;
  v_block text;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  -- Primero las filas, después el candado de destacados: el mismo orden que
  -- quien edita un producto, para que dos transacciones no se esperen en
  -- cruz. Los pedidos quedan tomados hasta guardar: nadie los cambia entre
  -- la comprobación y el insert.
  perform 1
     from public.products p
    where p.tenant_id = p_tenant_id
      and p.id = any (coalesce(p_product_ids, '{}'::uuid[]))
    order by p.id
      for share of p;

  perform pg_advisory_xact_lock(hashtextextended('catalog_featured:' || p_tenant_id::text, 0));

  select coalesce(array_agg(f.product_id), '{}'::uuid[])
    into v_previous
    from public.featured_products f
   where f.tenant_id = p_tenant_id;

  select coalesce(nullif(btrim(p.website_name), ''), p.name),
         public.catalog_product_web_block_v1(p, public.catalog_web_policy_v1(p_tenant_id))
    into v_name, v_block
    from unnest(coalesce(p_product_ids, '{}'::uuid[])) with ordinality as requested(id, position)
    join public.products p on p.id = requested.id and p.tenant_id = p_tenant_id
   where requested.id <> all (v_previous)
     and public.catalog_product_web_block_v1(p, public.catalog_web_policy_v1(p_tenant_id)) is not null
   order by requested.position
   limit 1;

  if v_block is not null then
    raise exception 'Ya no se vende en la web: «%» (%). No se agregó a destacados.',
      v_name,
      case v_block
        when 'workshop_consumable' then 'es consumible del taller'
        when 'inactive' then 'está archivado'
        when 'web_off' then 'su venta web está apagada'
        when 'missing_tax' then 'no tiene IVA clasificado'
        when 'missing_price' then 'no tiene precio'
        when 'below_cost' then 'el precio quedó bajo el costo'
        when 'missing_image' then 'no tiene foto'
        when 'missing_web_name' then 'no tiene nombre web'
        when 'missing_description' then 'no tiene descripción'
        when 'missing_brand' then 'no tiene marca'
        when 'category_hidden' then 'su categoría no se muestra en la tienda'
        else 'no cumple la regla de venta'
      end
      using errcode = 'P0001', hint = 'catalog_featured_not_on_sale';
  end if;

  delete from public.featured_products f where f.tenant_id = p_tenant_id;

  insert into public.featured_products (tenant_id, product_id, active, order_index)
  select p_tenant_id, ranked.id, true, (row_number() over (order by ranked.first_position) - 1)::integer
    from (
      select requested.id, min(requested.position) as first_position
        from unnest(coalesce(p_product_ids, '{}'::uuid[])) with ordinality as requested(id, position)
       where requested.id is not null
       group by requested.id
    ) ranked
    join public.products p on p.id = ranked.id and p.tenant_id = p_tenant_id
   where not (coalesce(p.product_type, 'product') <> 'service'
              and p.purchase_treatment = 'workshop_consumable');
  get diagnostics v_count = row_count;

  return jsonb_build_object('featured', v_count);
end;
$$;

revoke all on function public.catalog_replace_featured_v1(uuid, uuid[]) from public, anon;
grant execute on function public.catalog_replace_featured_v1(uuid, uuid[]) to authenticated;
