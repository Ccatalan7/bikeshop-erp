-- La página dice cuántas hay y cuántas muestra.
--
-- El pie del paso «Stock interno» decía «Mostrando 0 de 0 alternativas en
-- bodega» con 124 alternativas cargadas. El sobre `page` publicaba `limit`,
-- `offset` y `hasMore`, pero no `total` ni `returned`, que son justo las dos
-- claves que el cliente lee para escribir esa frase.
--
-- Los dos números ya estaban calculados dentro de la función. Sólo faltaba
-- publicarlos.

begin;

CREATE OR REPLACE FUNCTION public.get_supply_need_stock_resolution_v1(p_need_id uuid, p_limit integer DEFAULT 12, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_bundle jsonb;
  v_items jsonb;
  v_total integer;
begin
  if v_tenant_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 50
     or p_offset is null or p_offset < 0 or p_offset > 5000 then
    raise exception 'Invalid stock resolution bounds' using errcode = '22023';
  end if;

  v_bundle := public.supply_need_stock_bundle_internal_v1(
    v_tenant_id, p_need_id
  );

  -- **El envelope se proyecta clave por clave, nunca restando del bundle.**
  -- La primera versión de este corte devolvía `bundle - 'orderedItems'`, y eso
  -- filtró tres claves que la respuesta no-ok de la Fase B1 no publicaba
  -- —`internalStockRejectionReason`, `familyAggregateAtp` y
  -- `familyAggregateProvesCoverage`—. Una resta hereda en silencio todo lo que
  -- el bundle agregue en el futuro: el contrato público dejaría de estar
  -- escrito en ninguna parte. El bundle puede crecer; esto no.
  if v_bundle ->> 'status' <> 'ok' then
    return jsonb_build_object(
      'needId', v_bundle -> 'needId',
      'needVersion', v_bundle -> 'needVersion',
      'revisionNo', v_bundle -> 'revisionNo',
      'quantity', v_bundle -> 'quantity',
      'unit', v_bundle -> 'unit',
      'lane', v_bundle -> 'lane',
      'status', v_bundle -> 'status',
      'categoryId', v_bundle -> 'categoryId',
      'universeSize', v_bundle -> 'universeSize',
      'safeLimit', v_bundle -> 'safeLimit',
      'availableFields', v_bundle -> 'availableFields',
      'coverage', v_bundle -> 'coverage',
      'blocksExternal', v_bundle -> 'blocksExternal',
      'items', '[]'::jsonb,
      'counts', v_bundle -> 'counts'
    );
  end if;

  v_total := (v_bundle -> 'counts' ->> 'eligible')::integer;
  select coalesce(jsonb_agg(entry.value - 'ordinal'
      order by (entry.value ->> 'ordinal')::integer), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_bundle -> 'orderedItems') entry(value)
  where (entry.value ->> 'ordinal')::integer > p_offset
    and (entry.value ->> 'ordinal')::integer <= p_offset + p_limit;

  -- La rama `ok` tampoco publica `safeLimit` ni `availableFields`: sólo tienen
  -- sentido cuando el universo desbordó y hay algo que refinar.
  return jsonb_build_object(
    'needId', v_bundle -> 'needId',
    'needVersion', v_bundle -> 'needVersion',
    'revisionNo', v_bundle -> 'revisionNo',
    'quantity', v_bundle -> 'quantity',
    'unit', v_bundle -> 'unit',
    'lane', v_bundle -> 'lane',
    'status', v_bundle -> 'status',
    'categoryId', v_bundle -> 'categoryId',
    'universeSize', v_bundle -> 'universeSize',
    'coverage', v_bundle -> 'coverage',
    'blocksExternal', v_bundle -> 'blocksExternal',
    'internalStockRejectionReason',
      v_bundle -> 'internalStockRejectionReason',
    'items', v_items,
    'page', jsonb_build_object(
      'limit', p_limit, 'offset', p_offset,
      -- **Sin `total` ni `returned` la pantalla decía «Mostrando 0 de 0
      -- alternativas en bodega»** teniendo 124: el cliente lee esas dos claves
      -- y, al no venir, las toma como cero. El pie que existe justamente para
      -- avisar que la lista está cortada afirmaba lo contrario de lo que
      -- pasaba.
      --
      -- Los dos números ya estaban calculados acá; sólo no se publicaban.
      'total', v_total,
      'returned', jsonb_array_length(coalesce(v_items, '[]'::jsonb)),
      'hasMore', v_total > p_offset + p_limit
    ),
    'counts', v_bundle -> 'counts',
    'familyAggregateAtp', v_bundle -> 'familyAggregateAtp',
    'familyAggregateProvesCoverage',
      v_bundle -> 'familyAggregateProvesCoverage'
  );
end;
$function$
;

commit;
