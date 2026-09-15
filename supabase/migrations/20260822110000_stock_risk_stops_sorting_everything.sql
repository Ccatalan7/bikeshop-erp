-- El riesgo de inventario vuelve a cortar temprano.
--
-- La versión del 20260822100000 contaba con una función de ventana para poder
-- decir «10 de 1.013». Esa ventana obliga a materializar, ordenar y numerar el
-- conjunto en cada llamada, y con eso el tiempo real medido en los recibos de
-- herramienta pasó de 238-584 ms a 1.126, 2.494 y finalmente 5.003 ms, donde
-- la llamada murió con `tool_source_unavailable` y el asistente respondió «no
-- pude procesar esa solicitud».
--
-- El total sigue viajando: se cuenta con una agregación aparte sobre el mismo
-- CTE ya materializado, que no ordena nada. La página se ordena y se corta con
-- `limit`, como antes del cambio.
--
-- Aprendizaje que vale más que el parche: agregar «cuántos hay en total» a una
-- respuesta paginada no es gratis, y la forma barata de contar no es la que
-- queda a mano.

create or replace function public.assistant_find_inventory_risks_v1(
  p_query text,
  p_risk text,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set statement_timeout to '4500ms'
as $function$
declare
  v_authority record;
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_risk is null
     or p_risk not in ('any', 'low_stock', 'out_of_stock')
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');

  with demanda as materialized (
    -- Lo vendido y lo consumido en taller cuentan igual: las dos cosas sacan
    -- pieza de la bodega. Las facturas anuladas no.
    select linea.product_id, sum(linea.quantity) units
    from (
      select (item ->> 'product_id')::uuid product_id,
        coalesce((item ->> 'quantity')::numeric, 0) quantity
      from public.sales_invoices invoice
        cross join lateral jsonb_array_elements(invoice.items) item
      where invoice.tenant_id = v_authority.tenant_id
        and invoice.voided_at is null
        and invoice.date >= current_date - 90
        and jsonb_typeof(invoice.items) = 'array'
        and (item ->> 'product_id') ~ '^[0-9a-f-]{36}$'
      union all
      select job_item.product_id,
        coalesce(job_item.quantity, 0)
      from public.mechanic_job_items job_item
      where job_item.product_id is not null
        and job_item.created_at >= current_date - 90
    ) linea
    group by linea.product_id
  ), ultimo_proveedor as materialized (
    select distinct on ((item ->> 'product_id')::uuid)
      (item ->> 'product_id')::uuid product_id,
      supplier.name supplier_name
    from public.purchase_invoices invoice
      cross join lateral jsonb_array_elements(invoice.items) item
      left join public.suppliers supplier
        on supplier.id = invoice.supplier_id
       and supplier.tenant_id = invoice.tenant_id
    where invoice.tenant_id = v_authority.tenant_id
      and jsonb_typeof(invoice.items) = 'array'
      and (item ->> 'product_id') ~ '^[0-9a-f-]{36}$'
    order by (item ->> 'product_id')::uuid, invoice.date desc nulls last
  ), candidates as materialized (
    select product.id entity_id, product.name, product.sku,
      coalesce(product.category_name, product.category) category,
      case when coalesce(product.is_set, false)
        then public.get_full_sets_count(product.id)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end stock,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      coalesce(product.is_set, false) is_set,
      product.updated_at,
      concat_ws(' ', product.name, product.sku, product.brand,
        product.category_name, product.category) searchable
    from public.products product
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
      and coalesce(product.track_stock, true) is true
      and coalesce(product.is_service, false) is false
      and coalesce(product.purchase_treatment, 'inventory') = 'inventory'
  ), classified as materialized (
    select candidate.*, 
      case when candidate.stock <= 0 then 'out_of_stock' else 'low_stock' end risk,
      floor(coalesce(demanda.units, 0))::integer sold_recently,
      ultimo_proveedor.supplier_name
    from candidates candidate
      left join demanda on demanda.product_id = candidate.entity_id
      left join ultimo_proveedor on ultimo_proveedor.product_id = candidate.entity_id
    where candidate.stock <= 0 or candidate.stock <= candidate.minimum_stock
  ), matched as materialized (
    select classified.*,
      -- Para llegar al mínimo, o un mes de lo que se movió: lo que sea mayor.
      greatest(
        classified.minimum_stock - classified.stock,
        ceil(classified.sold_recently / 3.0)::integer,
        0
      ) suggested_order
    from classified
    where (p_risk = 'any' or classified.risk = p_risk)
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          classified.searchable
        )) = 0
      ))
  ), page as (
    -- El corte va ANTES de construir el resultado. Contando por ventana, el
    -- plan tenía que materializar, ordenar y numerar las 1.013 filas en cada
    -- llamada; en producción eso subió de ~400 ms a 2.5 s y una llamada murió
    -- a los 5.003 ms con `tool_source_unavailable`. El total se cuenta aparte,
    -- que es una agregación sin orden sobre el mismo CTE ya materializado.
    select matched.entity_id, matched.name, matched.sku, matched.category,
      matched.stock, matched.minimum_stock, matched.risk, matched.is_set,
      matched.updated_at, matched.sold_recently, matched.suggested_order,
      matched.supplier_name
    from matched
    order by
      case when matched.sold_recently > 0 then 0 else 1 end,
      case matched.risk when 'out_of_stock' then 0 else 1 end,
      matched.sold_recently desc,
      matched.stock,
      matched.minimum_stock desc,
      matched.updated_at desc nulls last,
      matched.name,
      matched.entity_id
    limit p_limit
  )
  select
    (
      select coalesce(jsonb_agg(jsonb_build_object(
        'entityId', page.entity_id,
        'name', public.assistant_truncate_utf8_internal_v1(page.name, 160),
        'sku', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(page.sku, ''), 80), ''),
        'category', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(page.category, ''), 100), ''),
        'stock', page.stock,
        'minimumStock', page.minimum_stock,
        'risk', page.risk,
        'isSet', page.is_set,
        'updatedAt', page.updated_at,
        'soldRecently', page.sold_recently,
        'suggestedOrder', page.suggested_order,
        'supplierName', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(page.supplier_name, ''), 120), '')
      )), '[]'::jsonb)
      from page
    ),
    (select count(*) from matched)
  into v_items, v_total;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit, v_total
  );
end;
$function$;
