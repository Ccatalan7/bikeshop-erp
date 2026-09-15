-- Comprobada es COMPLETA, no «algo coincide».
--
-- `weak` significa, desde `20260824320000`, que **algo** se estableció y nada
-- de lo que el matcher alcanzó a leer contradice —con el resto de los criterios
-- sin resolver—. Tratarlo como comprobado repetía exactamente el defecto que se
-- vino corrigiendo: la necesidad real de pastillas Shimano BR-MT200, resina y
-- SIN aletas contaba como sus dos alternativas
--
--   AE0094  «Pastilla Freno Shimano METALICA J04C CON DISIPADOR»
--   AE0252  «Pastillas … COPPER CON DISIPADOR … Shimano»
--
-- que contradicen a la vista el compuesto y la ausencia de aletas. Su
-- `matchDetail` lo decía: `brake_system = identity_fallback`, y
-- `compound_type` y `pad_finned` **sin resolver**.
--
-- La regla pasa a ser la misma que el feed del proveedor ya aplica: una
-- alternativa exige **todos** los predicados pedidos probados y ninguno
-- pendiente. La evidencia parcial no desaparece —sigue visible y ordena mejor
-- que lo que nadie pudo leer— pero queda por confirmar, fuera de `eligible`,
-- fuera de la cobertura y fuera de los writers.
--
-- Y `no_criteria` deja de ser un pase libre: sin criterios la categoría **es**
-- toda la especificación, así que sólo cuenta cuando es una **hoja** del árbol
-- del taller. Una categoría con hijas activas agrupa cosas distintas y
-- pertenecer a ella no demuestra nada.
--
-- `matchState` no cambia de valores: sigue sirviendo para ordenar y para decir
-- «algo coincide». Lo que decide ahora es `evidenceComplete`, que viaja por
-- fila para que el cliente no tenga que reconstruirlo.

-- Si el detalle prueba TODOS los criterios pedidos.
--
-- Probado es lo que alguien pudo leer: la ficha del producto o su nombre
-- curado. Un criterio `unresolved` no es una ausencia de problema, es la mitad
-- de la pregunta sin responder.
create or replace function public.supply_need_evidence_is_complete_internal_v1(
  p_detail jsonb
) returns boolean
language sql
immutable
as $function$
  select coalesce(jsonb_array_length(coalesce(p_detail, '[]'::jsonb)), 0) > 0
     and not exists (
       select 1
       from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
       where coalesce(entry.value ->> 'source', 'unresolved')
             not in ('product_spec', 'identity_fallback')
     );
$function$;

revoke all on function public.supply_need_evidence_is_complete_internal_v1(jsonb)
  from public;

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
  v_category_is_leaf boolean;
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
  -- ¿La categoría de esta necesidad es una hoja del árbol del taller?
  -- Sin criterios, la categoría **es** toda la especificación, y sólo una hoja
  -- está lo bastante cerrada para que pertenecer a ella signifique algo. Una
  -- categoría con hijas activas agrupa cosas distintas: ahí «no hay criterios»
  -- no puede convertirse en compatibilidad inventada.
  select not exists (
    select 1 from public.product_categories child
    where child.tenant_id = p_tenant_id
      and child.parent_id = v_context.category_id
      and child.is_active is true
  ) into v_category_is_leaf;

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
      end as coverage,
      -- **Comprobada es COMPLETA, no «algo coincide».** `weak` significaba que
      -- algo se estableció y nada contradijo, con el resto sin resolver; la
      -- necesidad real de pastillas contaba como comprobadas dos filas
      -- `METALICA CON DISIPADOR` que contradicen a la vista el compuesto
      -- orgánico y la ausencia de aletas: sólo el sistema de freno estaba
      -- establecido, por el nombre, y los otros dos criterios seguían sin
      -- resolver. Una alternativa exige **todos** los predicados pedidos
      -- probados; lo parcial sigue visible y ordena mejor, pero por confirmar.
      case
        when evaluated.match_state = 'no_criteria' then v_category_is_leaf
        else public.supply_need_evidence_is_complete_internal_v1(
          evaluated.match_detail
        )
      end as evidence_complete
    from evaluated
  ), ranked as (
    select covered.*,
      covered.coverage = 'full' and covered.evidence_complete
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
          case when covered.evidence_complete then 0 else 1 end,
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
    count(*) filter (where coverage = 'full' and evidence_complete)::integer,
    count(*) filter (where coverage = 'partial' and evidence_complete)::integer,
    count(*) filter (where coverage = 'none' and evidence_complete)::integer,
    count(*) filter (where not evidence_complete)::integer,
    count(*) filter (where evidence_complete)::integer,
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
      'evidenceComplete', evidence_complete,
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

CREATE OR REPLACE FUNCTION public.supply_need_choice_is_checked_internal_v1(p_tenant_id uuid, p_need_id uuid, p_product_id uuid, p_raise boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_eligible jsonb;
  v_state text;
  v_complete boolean;
  v_leaf boolean;
begin
  if p_tenant_id is null or p_need_id is null or p_product_id is null then
    return null;
  end if;
  v_eligible := public.supply_need_eligible_products_internal_v1(
    p_tenant_id, p_need_id
  );
  -- Sin evaluación no hay nada establecido: no se afirma ni se niega.
  if v_eligible ->> 'status' <> 'ok' then
    return null;
  end if;
  -- **Comprobado es completo.** Se pregunta por la evidencia entera, no por el
  -- rótulo: `weak` significaba «algo se estableció» y dejaba pasar una fila con
  -- dos de tres criterios sin resolver.
  select entry.value ->> 'matchState',
    case
      when (entry.value ->> 'matchState') = 'no_criteria' then null
      else public.supply_need_evidence_is_complete_internal_v1(
        entry.value -> 'matchDetail')
    end
  into v_state, v_complete
  from jsonb_array_elements(v_eligible -> 'items') entry(value)
  where (entry.value ->> 'productId')::uuid = p_product_id;
  -- Fuera del universo evaluado tampoco hay una afirmación que sostener: la
  -- categoría pudo cambiar después de fijar la identidad.
  if v_state is null then
    return null;
  end if;
  -- Sin criterios, la categoría es toda la especificación: sólo una hoja del
  -- árbol del taller está lo bastante cerrada para que pertenecer signifique
  -- algo. La misma regla que aplica el conjunto elegible.
  if v_state = 'no_criteria' then
    select not exists (
      select 1
      from public.product_categories child
      join public.supply_need_resolution_context_internal_v1(
        p_tenant_id, p_need_id) ctx on child.parent_id = ctx.category_id
      where child.tenant_id = p_tenant_id and child.is_active is true
    ) into v_leaf;
    v_complete := coalesce(v_leaf, false);
  end if;
  if p_raise and not coalesce(v_complete, false) then
    raise exception 'El producto no está comprobado contra los criterios de la necesidad.'
      using errcode = '23514';
  end if;
  return v_state;
end;
$function$;
