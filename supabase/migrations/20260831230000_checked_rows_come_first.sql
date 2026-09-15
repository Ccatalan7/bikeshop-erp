-- Lo comprobado va antes, y la página no puede romper esa separación.
--
-- El orden del conjunto ponía la cobertura por delante del estado de
-- evidencia, así que una fila **sin verificar con existencias** adelantaba a
-- una **comprobada sin stock**. Con la superficie separada por evidencia eso
-- rompe la paginación: en la necesidad real de pastillas BR-MT200 la primera
-- página mostraba UNA de las dos alternativas comprobadas y once sin verificar,
-- y la segunda —Shimano J04C, ATP 0— aparecía recién al pulsar `Ver más`. El
-- título decía «2 alternativas comprobadas» y sólo una estaba a la vista.
--
-- El grupo de evidencia pasa a ser la primera clave. Dentro de cada grupo el
-- orden no cambia: primero lo que cubre, después la fuerza de la evidencia,
-- después el ATP y el nombre.

CREATE OR REPLACE FUNCTION public.supply_need_stock_bundle_internal_v1(p_tenant_id uuid, p_need_id uuid, p_max_universe integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_context record;
  v_eligible jsonb;
  v_items jsonb;
  v_total integer;
  v_full_count integer;
  v_partial_count integer;
  v_none_count integer;
  v_unverified_count integer;
  v_eligible_count integer;
  v_blocking boolean;
  v_family_atp integer;
  v_coverage text;
begin
  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    p_tenant_id, p_need_id
  );

  -- La ÚNICA evaluación técnica de esta llamada.
  v_eligible := public.supply_need_eligible_products_internal_v1(
    p_tenant_id, p_need_id, p_max_universe
  );

  if v_eligible ->> 'status' <> 'ok' then
    return jsonb_build_object(
      'needId', v_context.need_id,
      'needVersion', v_context.need_version,
      'revisionNo', v_context.revision_no,
      'quantity', v_context.quantity,
      'unit', v_context.unit,
      'lane', v_eligible ->> 'lane',
      'status', v_eligible ->> 'status',
      'categoryId', v_eligible -> 'categoryId',
      'universeSize', v_eligible -> 'universeSize',
      'safeLimit', v_eligible -> 'safeLimit',
      'availableFields', coalesce(v_eligible -> 'availableFields', '[]'::jsonb),
      'internalStockRejectionReason', v_context.internal_stock_rejection_reason,
      'coverage', 'none',
      'blocksExternal', false,
      'orderedItems', '[]'::jsonb,
      'counts', jsonb_build_object(
        'eligible', 0, 'reviewed', 0, 'full', 0, 'partial', 0, 'none', 0,
        'unverified', 0
      ),
      'familyAggregateAtp', 0,
      'familyAggregateProvesCoverage', false
    );
  end if;

  -- ATP una sola vez por producto: llamarla dentro de un CASE la evaluaría
  -- tres veces por fila, y es la parte cara de esta lectura.
  with evaluated as (
    select (entry.value ->> 'productId')::uuid as product_id,
      entry.value ->> 'matchState' as match_state,
      entry.value -> 'matchDetail' as match_detail,
      public.inventory_available_quantity_v1(
        p_tenant_id, (entry.value ->> 'productId')::uuid
      ) as atp
    from jsonb_array_elements(v_eligible -> 'items') entry(value)
  ), covered as (
    select evaluated.*,
      case
        when evaluated.atp >= v_context.quantity then 'full'
        when evaluated.atp > 0 then 'partial'
        else 'none'
      end as coverage
    from evaluated
  ), ranked as (
    select covered.*,
      covered.coverage = 'full'
        and covered.match_state in ('strong', 'weak', 'no_criteria')
        as blocks_external,
      row_number() over (
        order by
          -- **La evidencia ordena antes que el stock.** La pantalla separa lo
          -- comprobado de lo que no, así que el orden tiene que respetar esa
          -- separación o la paginación la rompe: con la cobertura primero, una
          -- fila sin verificar con existencias adelantaba a una comprobada sin
          -- stock, y la segunda alternativa comprobada de la necesidad real de
          -- pastillas —Shimano J04C, ATP 0— caía a la página siguiente, detrás
          -- de once filas sin verificar. El operador veía «2 comprobadas» y
          -- sólo una en pantalla.
          case when covered.match_state in ('strong', 'weak', 'no_criteria')
               then 0 else 1 end,
          -- Dentro de cada grupo manda lo de siempre: primero lo que cubre.
          case covered.coverage
            when 'full' then 0 when 'partial' then 1 else 2 end,
          case covered.match_state
            when 'strong' then 0 when 'weak' then 1
            when 'no_criteria' then 2 else 3 end,
          covered.atp desc,
          product.name,
          covered.product_id
      ) as ordinal,
      product.name, product.sku,
      product.image_url_optimized, product.image_url, product.image_urls
    from covered
    join public.products product
      on product.tenant_id = p_tenant_id
     and product.id = covered.product_id
  )
  -- **Elegible es lo COMPROBADO, no lo revisado.** La categoría define el
  -- universo que hay que mirar; que una fila sobreviva a él no la hace una
  -- alternativa. Con `eligible` contando también lo no verificado, la necesidad
  -- de pastillas BR-MT200 anunciaba «49 alternativas internas elegibles» y
  -- ofrecía elegir patines V-Brake y pastillas Avid: 47 de esas 49 no tenían
  -- ni un criterio establecido. Lo revisado se conserva aparte, en `reviewed`,
  -- porque saber cuánto del catálogo está sin fichar sí es información.
  select count(*)::integer,
    count(*) filter (
      where coverage = 'full' and match_state <> 'unverified'
    )::integer,
    count(*) filter (
      where coverage = 'partial' and match_state <> 'unverified'
    )::integer,
    count(*) filter (
      where coverage = 'none' and match_state <> 'unverified'
    )::integer,
    count(*) filter (where match_state = 'unverified')::integer,
    count(*) filter (where match_state <> 'unverified')::integer,
    coalesce(sum(atp), 0)::integer,
    coalesce(bool_or(blocks_external), false),
    -- El conjunto ORDENADO y completo. Paginar es cosa de quien muestra.
    coalesce(jsonb_agg(jsonb_build_object(
      'ordinal', ordinal,
      'productId', product_id,
      'name', name,
      'sku', sku,
      'imageUrlOptimized', nullif(btrim(image_url_optimized), ''),
      'imageUrl', nullif(btrim(image_url), ''),
      'imageUrls', to_jsonb(coalesce(image_urls, array[]::text[])),
      'atp', atp,
      'coverage', coverage,
      'matchState', match_state,
      'matchDetail', match_detail,
      'blocksExternal', blocks_external
    ) order by ordinal), '[]'::jsonb)
  into v_total, v_full_count, v_partial_count, v_none_count,
    v_unverified_count, v_eligible_count, v_family_atp, v_blocking, v_items
  from ranked;

  -- Y la cobertura sale de esos mismos contadores: decir «la bodega cubre esta
  -- necesidad» apoyándose en un producto que nadie pudo verificar es afirmar
  -- lo que no se sabe. Sin nada comprobado, la cobertura es `none` aunque haya
  -- existencias: hay stock de algo, no de esto.
  v_coverage := case
    when v_full_count > 0 then 'full'
    when v_partial_count > 0 then 'partial'
    else 'none'
  end;

  return jsonb_build_object(
    'needId', v_context.need_id,
    'needVersion', v_context.need_version,
    'revisionNo', v_context.revision_no,
    'quantity', v_context.quantity,
    'unit', v_context.unit,
    'lane', v_eligible ->> 'lane',
    'status', 'ok',
    'categoryId', v_eligible -> 'categoryId',
    'universeSize', v_eligible -> 'universeSize',
    'coverage', v_coverage,
    'blocksExternal', v_blocking,
    'internalStockRejectionReason', v_context.internal_stock_rejection_reason,
    'orderedItems', v_items,
    'counts', jsonb_build_object(
      'eligible', v_eligible_count,
      'reviewed', v_total,
      'full', v_full_count,
      'partial', v_partial_count,
      'none', v_none_count,
      'unverified', v_unverified_count
    ),
    -- Informativo. No prueba cobertura: sumar dos variantes distintas es una
    -- decisión del taller, no una propiedad del inventario.
    'familyAggregateAtp', v_family_atp,
    'familyAggregateProvesCoverage', false
  );
end;
$function$;
