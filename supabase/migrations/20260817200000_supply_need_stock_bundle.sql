-- Un solo dueño de ATP, cobertura y bloqueo sobre el conjunto elegible.
--
-- **El defecto que cierra.** La Fase B2 necesita dos lecturas de la misma
-- necesidad: la resolución de stock y, después, las opciones externas. Tal como
-- estaba, cada una habría llamado por su cuenta a
-- `supply_need_eligible_products_internal_v1`, y esa función evalúa **cada
-- predicado contra cada producto** del universo. Dos llamadas serían dos
-- evaluaciones N×M para responder una sola pregunta del operador.
--
-- El bundle resuelve elegibilidad, ATP, cobertura por producto y bloqueo **una
-- vez**, y devuelve el conjunto entero. `get_supply_need_stock_resolution_v1`
-- pasa a hacer sólo lo suyo: paginar y proyectar.
--
-- **El alcance de la garantía es una invocación RPC, no una sesión.** Dentro de
-- una llamada hay exactamente una evaluación técnica. La RPC externa de la fase
-- siguiente llamará al bundle una vez **dentro de su propia invocación**: no
-- reutiliza el resultado de la lectura de stock que la interfaz hizo antes, ni
-- podría —son dos peticiones distintas, y entremedio el inventario se mueve—.
-- Lo que se evita es evaluar dos veces para responder una sola pregunta.
--
-- **La semántica de B1 no cambia.** Ni un umbral, ni un estado, ni una regla:
-- el cuerpo se mueve, no se reescribe. Los 60 pgTAP de
-- `supply_need_family_resolution_b1` son la prueba, y siguen verdes sin tocar
-- una línea.
--
-- **Qué NO entra.** No hay scoring externo, ni preferencia comercial tipada,
-- ni UI. `rank_purchase_candidates_v1` y su kernel quedan intactos.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. El bundle: una evaluación técnica, todo lo que se deriva de ella.
--
-- Devuelve el conjunto **completo** —sin paginar— porque quien pagina es la
-- superficie, no la verdad. Los conteos y el bloqueo se calculan sobre el
-- conjunto entero, nunca sobre una página: un candidato bloqueante en la
-- página tres bloquea igual.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_stock_bundle_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid,
  p_max_universe integer default 400
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_context record;
  v_eligible jsonb;
  v_items jsonb;
  v_total integer;
  v_full_count integer;
  v_partial_count integer;
  v_none_count integer;
  v_unverified_count integer;
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
        'eligible', 0, 'full', 0, 'partial', 0, 'none', 0, 'unverified', 0
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
  select count(*)::integer,
    count(*) filter (where coverage = 'full')::integer,
    count(*) filter (where coverage = 'partial')::integer,
    count(*) filter (where coverage = 'none')::integer,
    count(*) filter (where match_state = 'unverified')::integer,
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
    v_unverified_count, v_family_atp, v_blocking, v_items
  from ranked;

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
      'eligible', v_total,
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
$$;

revoke all on function public.supply_need_stock_bundle_internal_v1(
  uuid, uuid, integer
) from public, anon, authenticated, service_role;

comment on function public.supply_need_stock_bundle_internal_v1(
  uuid, uuid, integer
) is
  'Single owner of ATP, per-product coverage and the external-step block for a supply need, over exactly one technical eligibility evaluation. Returns the whole ordered set; paginating belongs to the surface, and counts and blocking are always computed over the full set.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. La lectura pública se queda con lo suyo: paginar y proyectar.
--
-- Misma firma, mismo contrato de respuesta, misma semántica. Lo único que
-- cambia es de dónde salen los números.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.get_supply_need_stock_resolution_v1(
  p_need_id uuid,
  p_limit integer default 12,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
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
      'hasMore', v_total > p_offset + p_limit
    ),
    'counts', v_bundle -> 'counts',
    'familyAggregateAtp', v_bundle -> 'familyAggregateAtp',
    'familyAggregateProvesCoverage',
      v_bundle -> 'familyAggregateProvesCoverage'
  );
end;
$$;

revoke all on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) to authenticated;

comment on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) is
  'Stock-first resolution for a supply need. Delegates ATP, coverage and blocking to supply_need_stock_bundle_internal_v1 — exactly one technical evaluation per RPC invocation — and owns only pagination and the explicit public envelope, which is projected key by key rather than subtracted from the bundle.';

commit;
