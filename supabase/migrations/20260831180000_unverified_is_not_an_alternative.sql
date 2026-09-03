-- No verificado no es una alternativa, y no es cobertura.
--
-- La categoría define el universo que hay que **revisar**; que una fila
-- sobreviva a él no la convierte en una alternativa. Con `eligible` contando
-- también lo no verificado, la necesidad real de pastillas BR-MT200 anunciaba
-- «49 alternativas internas elegibles» y ofrecía `Elegir producto` sobre
-- patines V-Brake, pastillas Avid/SRAM y metálicas: **47 de esas 49 no tenían
-- un solo criterio establecido** —el catálogo calla, sólo 2 de 49 nombran
-- Shimano—. Y la cobertura decía `full` apoyada en tres productos que nadie
-- pudo verificar, mientras `blocksExternal` decía lo contrario en la misma
-- respuesta.
--
-- Este forward separa las dos cosas en el contrato, que es donde tienen que
-- separarse para que todos los consumidores hereden la corrección:
--
--   eligible  = lo COMPROBADO (`strong` · `weak` · `no_criteria`)
--   reviewed  = el universo revisado, que antes se llamaba `eligible`
--   full/partial/none = cobertura contada SÓLO sobre lo comprobado
--
-- `unverified` ya viajaba aparte y no cambia. Nada se esconde: lo revisado
-- sigue publicándose entero en `orderedItems` con su `matchState`, porque
-- saber cuánto del catálogo está sin fichar es información real.

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
$function$
