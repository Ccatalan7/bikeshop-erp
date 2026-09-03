-- La página cuenta lo revisado, no lo comprobado.
--
-- `20260831180000` cambió el significado de `counts.eligible` —pasó a ser lo
-- comprobado— y `get_supply_need_stock_resolution_v1` lo usaba como total de
-- paginación sobre `orderedItems`, que sigue trayendo el conjunto revisado
-- entero. Con eso `hasMore` decía `false` mientras quedaban filas sin verificar
-- por entregar: escondía exactamente el grupo que la pantalla muestra aparte.
--
-- Lo encontró el pgTAP de resolución familiar, no una lectura del código: la
-- prueba de paginación pasó a rojo en cuanto el contrato cambió.

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

  -- **La página cuenta lo REVISADO, que es lo que `orderedItems` trae.**
  -- Desde `20260831180000`, `eligible` significa lo comprobado: paginar con ese
  -- número dejaba `hasMore = false` con filas sin verificar todavía por
  -- entregar, es decir escondía justo el grupo que la pantalla muestra aparte.
  v_total := coalesce(
    (v_bundle -> 'counts' ->> 'reviewed')::integer,
    (v_bundle -> 'counts' ->> 'eligible')::integer
  );
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
$function$;

-- Y la revalidación del camino de candidatos se mueve antes de buscar el
-- candidato: es un problema de la necesidad, no del candidato. Colocada
-- después, una necesidad sin candidatos fallaba por «Candidato no encontrado»
-- y escondía la causa real.

CREATE OR REPLACE FUNCTION public.prepare_purchase_plan_line_v1(p_plan_id uuid, p_expected_plan_version bigint, p_source_need_id uuid, p_candidate_id uuid, p_quantity numeric, p_profile text, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.purchase_plan_events%rowtype;
  v_plan public.purchase_plans%rowtype;
  v_need public.supply_needs%rowtype;
  v_candidate public.purchase_candidate_metrics_v1%rowtype;
  v_existing public.purchase_plan_lines%rowtype;
  v_line public.purchase_plan_lines%rowtype;
  v_evidence jsonb;
  v_groups jsonb;
  v_changed boolean;
  v_had_existing boolean := false;
  v_is_new_plan boolean := false;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_source_need_id is null or p_candidate_id is null
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or p_profile not in ('balanced', 'profitability', 'urgent_local')
     or v_operation_key = '' or octet_length(v_operation_key) > 200
     or (p_plan_id is null and p_expected_plan_version is not null)
     or (p_plan_id is not null and p_expected_plan_version is null) then
    raise exception 'Los datos del plan no son válidos.' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'plan_id', p_plan_id,
    'expected_plan_version', p_expected_plan_version,
    'source_need_id', p_source_need_id,
    'candidate_id', p_candidate_id,
    'quantity', p_quantity,
    'profile', p_profile
  );
  select event.* into v_receipt
  from public.purchase_plan_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'line_prepared'
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio del plan.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_source_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.supply_state <> 'open'
     or v_need.identity_state <> 'confirmed'
     or v_need.product_id is null then
    raise exception 'La necesidad no está lista para una alternativa externa.'
      using errcode = '55000';
  end if;
  if p_quantity > v_need.quantity then
    raise exception 'La cantidad del plan excede la necesidad pendiente.'
      using errcode = '23514';
  end if;
  -- **La identidad confirmada se revalida al planificar, bajo el lock.** Una
  -- identidad fijada antes —por un cliente anterior, o antes de que el taller
  -- precisara los criterios— no puede seguir entrando al plan si hoy el juicio
  -- dice que ese producto no está comprobado. Va antes de buscar el candidato:
  -- es un problema de la necesidad, no del candidato, y decirlo primero es más
  -- barato y más claro.
  perform public.supply_need_choice_is_checked_internal_v1(
    v_tenant_id, p_source_need_id, v_need.product_id, true
  );
  if public.inventory_available_quantity_v1(
       v_tenant_id, v_need.product_id
     ) >= v_need.quantity
     and v_need.internal_stock_rejection_reason is null then
    raise exception 'Decide primero si usarás el stock interno disponible.'
      using errcode = '55000';
  end if;

  select candidate.* into v_candidate
  from public.purchase_candidate_metrics_v1 candidate
  where candidate.tenant_id = v_tenant_id
    and candidate.candidate_id = p_candidate_id;
  if not found then
    raise exception 'Candidato de compra no encontrado.' using errcode = 'P0002';
  end if;
  if v_candidate.product_id <> v_need.product_id then
    raise exception 'El candidato no corresponde al producto confirmado.'
      using errcode = '23514';
  end if;

  if p_plan_id is null then
    insert into public.purchase_plans (
      tenant_id, title, state, objective_profile, version,
      created_by, updated_by
    ) values (
      v_tenant_id,
      'Plan de compra ' || public.tenant_business_date(v_tenant_id)::text,
      'draft', p_profile, 1, v_actor_id, v_actor_id
    ) returning * into v_plan;
    v_is_new_plan := true;
  else
    select plan.* into v_plan
    from public.purchase_plans plan
    where plan.tenant_id = v_tenant_id and plan.id = p_plan_id
    for update;
    if not found then
      raise exception 'Plan no encontrado.' using errcode = 'P0002';
    end if;
    if v_plan.state <> 'draft' then
      raise exception 'Sólo un plan borrador puede editarse.' using errcode = '55000';
    end if;
    if v_plan.version <> p_expected_plan_version then
      raise exception 'El plan cambió; vuelve a cargarlo antes de guardar.'
        using errcode = '40001';
    end if;
  end if;

  select line.* into v_existing
  from public.purchase_plan_lines line
  where line.tenant_id = v_tenant_id
    and line.plan_id = v_plan.id
    and line.source_need_id = v_need.id
  for update;
  v_had_existing := found;

  v_evidence := jsonb_build_object(
    'captured_at', clock_timestamp(),
    'ranking_profile', p_profile,
    'ranking_version', 'purchase-ranking-v1',
    'candidate_id', v_candidate.candidate_id,
    'product_id', v_candidate.product_id,
    'supplier_id', v_candidate.supplier_id,
    'supplier_name', v_candidate.supplier_name,
    'currency_code', v_candidate.currency_code,
    'latest_purchase_at', v_candidate.latest_purchase_at,
    'latest_base_unit_cost_net', v_candidate.latest_base_unit_cost_net,
    'latest_allocated_freight_net', v_candidate.latest_allocated_freight_net,
    'latest_landed_unit_cost_net', v_candidate.latest_landed_unit_cost_net,
    'projected_gross_margin_ratio',
      v_candidate.projected_gross_margin_ratio,
    'purchase_count', v_candidate.purchase_count,
    'freight_evidence', v_candidate.latest_freight_evidence_status,
    'supplier_availability', 'unverified',
    'latest_purchase_invoice_id', v_candidate.latest_purchase_invoice_id,
    'latest_purchase_invoice_line_id',
      v_candidate.latest_purchase_invoice_line_id
  );

  v_changed := not v_had_existing
    or v_existing.state <> 'active'
    or v_existing.candidate_id is distinct from v_candidate.candidate_id
    or v_existing.quantity <> p_quantity
    or v_plan.objective_profile <> p_profile;

  if v_existing.id is null then
    insert into public.purchase_plan_lines (
      tenant_id, plan_id, source_need_id, candidate_id, product_id,
      supplier_id, supplier_name, quantity, unit, currency_code,
      landed_unit_cost_net, projected_gross_margin_ratio,
      supplier_availability, evidence_snapshot, state,
      created_by, updated_by
    ) values (
      v_tenant_id, v_plan.id, v_need.id, v_candidate.candidate_id,
      v_candidate.product_id, v_candidate.supplier_id,
      v_candidate.supplier_name, p_quantity, v_need.unit,
      v_candidate.currency_code, v_candidate.latest_landed_unit_cost_net,
      v_candidate.projected_gross_margin_ratio, 'unverified', v_evidence,
      'active', v_actor_id, v_actor_id
    ) returning * into v_line;
  elsif v_changed then
    update public.purchase_plan_lines line
    set candidate_id = v_candidate.candidate_id,
        product_id = v_candidate.product_id,
        supplier_id = v_candidate.supplier_id,
        supplier_name = v_candidate.supplier_name,
        quantity = p_quantity,
        unit = v_need.unit,
        currency_code = v_candidate.currency_code,
        landed_unit_cost_net = v_candidate.latest_landed_unit_cost_net,
        projected_gross_margin_ratio =
          v_candidate.projected_gross_margin_ratio,
        supplier_availability = 'unverified',
        evidence_snapshot = v_evidence,
        state = 'active',
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where line.tenant_id = v_tenant_id and line.id = v_existing.id
    returning * into v_line;
  else
    v_line := v_existing;
  end if;

  if v_changed and not v_is_new_plan then
    update public.purchase_plans plan
    set objective_profile = p_profile,
        version = plan.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where plan.tenant_id = v_tenant_id and plan.id = v_plan.id
    returning * into v_plan;
  end if;

  select coalesce(jsonb_agg(to_jsonb(group_row)
    order by group_row.supplier_name, group_row.currency_code), '[]'::jsonb)
  into v_groups
  from public.purchase_plan_supplier_groups_v1 group_row
  where group_row.tenant_id = v_tenant_id
    and group_row.plan_id = v_plan.id;

  v_response := jsonb_build_object(
    'plan_id', v_plan.id,
    'plan_version', v_plan.version,
    'changed', v_changed,
    'plan', to_jsonb(v_plan),
    'line', to_jsonb(v_line),
    'supplier_groups', v_groups
  );
  insert into public.purchase_plan_events (
    tenant_id, plan_id, line_id, action, changed, actor_id,
    operation_key, request_snapshot, response_snapshot
  ) values (
    v_tenant_id, v_plan.id, v_line.id, 'line_prepared', v_changed,
    v_actor_id, v_operation_key, v_request, v_response
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$function$;
