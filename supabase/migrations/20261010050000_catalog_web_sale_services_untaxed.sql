-- «Vender en la web» enciende un servicio aunque no tenga IVA clasificado.
--
-- La regla de la tienda (`catalog_product_web_block_v1`) pide IVA sólo a lo
-- que pasa por el carrito: un servicio se agenda, no se compra. Pero
-- `catalog_set_web_sale_v1` lo exigía a todo, así que un servicio sin IVA
-- (5 de 67 el 2026-10-10) no se podía encender desde el catálogo y el ERP
-- decía «sin clasificación de IVA» de algo que la tienda sí vendería
-- (revisión de Codex, P1). Mismo criterio que la regla, en el conteo y en la
-- escritura.

create or replace function public.catalog_set_web_sale_v1(
  p_tenant_id uuid,
  p_product_ids uuid[],
  p_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_ids uuid[];
  v_changed integer := 0;
  v_consumables integer := 0;
  v_inactive integer := 0;
  v_untaxed integer := 0;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_on is null then
    raise exception 'catalog_web_sale_missing_value' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct requested.id), '{}'::uuid[])
    into v_ids
    from unnest(coalesce(p_product_ids, '{}'::uuid[])) as requested(id)
   where requested.id is not null;

  if p_on then
    select count(*) filter (where coalesce(p.product_type, 'product') <> 'service'
                              and p.purchase_treatment = 'workshop_consumable'),
           count(*) filter (where not coalesce(p.is_active, false)),
           count(*) filter (where coalesce(p.product_type, 'product') <> 'service'
                              and (p.tax_rate is null or p.tax_rate not in (0, 0.19, 19))
                              and coalesce(p.is_active, false)
                              and p.purchase_treatment is distinct from 'workshop_consumable')
      into v_consumables, v_inactive, v_untaxed
      from public.products p
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids);

    update public.products p
       set is_published = true,
           show_on_website = true,
           updated_at = now()
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids)
       and coalesce(p.is_active, false)
       and not (coalesce(p.product_type, 'product') <> 'service'
                and p.purchase_treatment = 'workshop_consumable')
       and (coalesce(p.product_type, 'product') = 'service'
            or p.tax_rate in (0, 0.19, 19))
       and not (coalesce(p.is_published, false) and coalesce(p.show_on_website, false));
    get diagnostics v_changed = row_count;
  else
    update public.products p
       set is_published = false,
           show_on_website = false,
           updated_at = now()
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids)
       and (coalesce(p.is_published, false) or coalesce(p.show_on_website, false));
    get diagnostics v_changed = row_count;
  end if;

  return jsonb_build_object(
    'changed', v_changed,
    'skipped_consumables', v_consumables,
    'skipped_inactive', v_inactive,
    'skipped_untaxed', v_untaxed
  );
end;
$$;

