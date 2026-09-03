-- Comprobado también en el servidor, no sólo en la pantalla.
--
-- El corte anterior dejó de ofrecer `Elegir producto` y `Agregar al plan` sobre
-- filas que nadie pudo verificar, pero la escritura seguía aceptándolas: el
-- cliente publicado —que sí muestra esos botones— podía confirmar hoy un patín
-- V-Brake para la necesidad real de pastillas BR-MT200. Una compuerta que vive
-- sólo en la UI no es una compuerta.
--
-- `confirm_supply_need_family_choice_v1` rechazaba únicamente `conflict`, que
-- además es una compuerta vacía: el conjunto elegible ya excluye lo
-- contradictorio, así que en la práctica no rechazaba nada. Pasa a lista
-- positiva —`strong`, `weak`, `no_criteria`—, que es el mismo conjunto que el
-- contrato de conteos llama comprobado.
--
-- Y los dos caminos del plan revalidan la identidad vigente bajo el mismo lock
-- que ya toman: una identidad fijada antes —por un cliente anterior, o antes de
-- que el taller precisara los criterios— no puede seguir entrando al plan si
-- hoy el juicio dice que ese producto no está comprobado.
--
-- **El replay idempotente no se toca.** En las tres funciones la revalidación
-- va después del recibo por `operation_key`: una escritura ya hecha se devuelve
-- igual que siempre, sin volver a juzgarla. Reintentar no puede fallar por una
-- regla que no existía cuando se escribió.

-- El estado vigente de un producto frente a los criterios de una necesidad.
--
-- Devuelve el `matchState` actual, o `null` cuando no se puede establecer
-- —sin categoría no hay criterios que juzgar, y ahí el módulo no está
-- afirmando compatibilidad—. Con `p_raise`, rechaza lo que sí se pudo
-- establecer como no comprobado.
create or replace function public.supply_need_choice_is_checked_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid,
  p_product_id uuid,
  p_raise boolean default false
) returns text
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_eligible jsonb;
  v_state text;
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
  select entry.value ->> 'matchState' into v_state
  from jsonb_array_elements(v_eligible -> 'items') entry(value)
  where (entry.value ->> 'productId')::uuid = p_product_id;
  -- Fuera del universo evaluado tampoco hay una afirmación que sostener: la
  -- categoría pudo cambiar después de fijar la identidad.
  if v_state is null then
    return null;
  end if;
  if p_raise and v_state not in ('strong', 'weak', 'no_criteria') then
    raise exception 'El producto no está comprobado contra los criterios de la necesidad.'
      using errcode = '23514';
  end if;
  return v_state;
end;
$function$;

revoke all on function public.supply_need_choice_is_checked_internal_v1(
  uuid, uuid, uuid, boolean
) from public;

CREATE OR REPLACE FUNCTION public.confirm_supply_need_family_choice_v1(p_need_id uuid, p_expected_version bigint, p_expected_revision_no bigint, p_product_id uuid, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_context record;
  v_previous public.supply_need_interpretation_revisions%rowtype;
  v_eligible jsonb;
  v_chosen jsonb;
  v_next_revision bigint;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_expected_revision_no is null or p_product_id is null
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La confirmación requiere necesidad, versión, revisión, producto y clave.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'expected_revision_no', p_expected_revision_no,
    'product_id', p_product_id
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'family_choice_confirmed'
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra confirmación.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de confirmar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state <> 'open' then
    raise exception 'La necesidad ya no está abierta.' using errcode = '55000';
  end if;
  if v_need.product_id is not null and v_need.identity_state = 'confirmed' then
    raise exception 'La necesidad ya tiene un producto confirmado.'
      using errcode = '55000';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    v_tenant_id, p_need_id
  );
  if v_context.revision_no is distinct from p_expected_revision_no then
    raise exception 'La interpretación cambió; vuelve a revisar las alternativas.'
      using errcode = '40001';
  end if;

  -- Revalidación bajo el lock: elegibilidad y categoría se comprueban ahora,
  -- no cuando el operador miró la pantalla.
  v_eligible := public.supply_need_eligible_products_internal_v1(
    v_tenant_id, p_need_id
  );
  if v_eligible ->> 'status' <> 'ok' then
    raise exception 'No hay un conjunto elegible para confirmar.'
      using errcode = '55000';
  end if;
  select entry.value into v_chosen
  from jsonb_array_elements(v_eligible -> 'items') entry(value)
  where (entry.value ->> 'productId')::uuid = p_product_id;
  if v_chosen is null then
    raise exception 'El producto no pertenece al conjunto elegible de la necesidad.'
      using errcode = '23514';
  end if;
  -- **Elegir declara que ESTE producto es la necesidad: exige prueba.**
  -- Rechazar sólo `conflict` era una compuerta vacía —el conjunto elegible ya
  -- excluye los contradictorios— y dejaba pasar lo `unverified`: un cliente
  -- publicado anterior, que todavía muestra `Elegir producto` sobre filas sin
  -- verificar, podía confirmar hoy un patín V-Brake para una necesidad de
  -- pastillas. La lista es positiva: sólo entra lo comprobado.
  if v_chosen ->> 'matchState' not in ('strong', 'weak', 'no_criteria') then
    raise exception 'El producto no está comprobado contra los criterios de la necesidad.'
      using errcode = '23514';
  end if;

  select revision.* into v_previous
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id
    and revision.revision_no = v_context.revision_no;

  update public.supply_needs need
  set product_id = p_product_id,
      identity_state = 'confirmed',
      version = need.version + 1,
      updated_by = v_actor_id,
      updated_at = clock_timestamp()
  where need.tenant_id = v_tenant_id and need.id = v_need.id
  returning * into v_need;

  select coalesce(max(revision.revision_no), 0) + 1 into v_next_revision
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = v_need.id;

  insert into public.supply_need_interpretation_revisions (
    tenant_id, supply_need_id, revision_no, source, raw_description,
    identity_state, canonical_product_id, category_id, constraints,
    clarifications, evidence_snapshot, formula_version, created_by
  ) values (
    v_tenant_id, v_need.id, v_next_revision, 'manual',
    coalesce(v_previous.raw_description, v_need.original_description),
    'confirmed', p_product_id,
    -- La procedencia se conserva entera: sin esto, confirmar apagaría la
    -- categoría y los criterios que produjeron la alternativa.
    v_context.category_id,
    coalesce(v_previous.constraints, '[]'::jsonb),
    coalesce(v_previous.clarifications, '[]'::jsonb),
    -- Sólo evidencia estable: por qué este producto era elegible. Nada de
    -- glosas derivadas —ruta de categoría o familia técnica—, que envejecen
    -- al lado de su fuente.
    jsonb_build_object(
      'chosen_from', 'family_alternative',
      'match_state', v_chosen ->> 'matchState',
      'match_detail', coalesce(v_chosen -> 'matchDetail', '[]'::jsonb),
      'from_revision_no', v_context.revision_no
    ),
    'family-choice-v1', v_actor_id
  );

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', true,
    'product_id', p_product_id,
    'match_state', v_chosen ->> 'matchState',
    'revision_no', v_next_revision,
    'from_revision_no', v_context.revision_no,
    -- Un rechazo de familia anterior sigue en pie: la persona ya decidió que
    -- el stock interno no servía, y confirmar cuál era el producto no
    -- reabre esa decisión.
    'internal_stock_rejection_reason', v_need.internal_stock_rejection_reason,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'family_choice_confirmed', true, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$function$;

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
  -- **La identidad confirmada se revalida al planificar, bajo el lock.** Una
  -- identidad fijada antes —por un cliente anterior, o antes de que el taller
  -- precisara los criterios— no puede seguir entrando al plan si hoy el juicio
  -- dice que ese producto no está comprobado.
  perform public.supply_need_choice_is_checked_internal_v1(
    v_tenant_id, p_source_need_id, v_need.product_id, true
  );

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

CREATE OR REPLACE FUNCTION public.prepare_purchase_plan_product_v1(p_plan_id uuid, p_expected_plan_version bigint, p_source_need_id uuid, p_product_id uuid, p_quantity numeric, p_profile text, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
 SET lock_timeout TO '750ms'
 SET statement_timeout TO '9000ms'
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
  v_product public.products%rowtype;
  v_existing public.purchase_plan_lines%rowtype;
  v_line public.purchase_plan_lines%rowtype;
  v_supplier_id uuid;
  v_supplier_name text;
  v_catalog_supplier_name text;
  v_availability public.supplier_availability_checks%rowtype;
  v_availability_supplier_name text;
  v_evidence_state text;
  v_evidence jsonb;
  v_groups jsonb;
  v_currency text;
  v_changed boolean;
  v_had_existing boolean := false;
  v_is_new_plan boolean := false;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_source_need_id is null or p_product_id is null
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
    'product_id', p_product_id,
    'quantity', p_quantity,
    'profile', p_profile,
    'evidence_mode', 'catalog_without_erp_history'
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
     or v_need.product_id is null
     or v_need.product_id <> p_product_id then
    raise exception 'El producto no es la identidad confirmada de la necesidad.'
      using errcode = '23514';
  end if;
  if p_quantity > v_need.quantity then
    raise exception 'La cantidad del plan excede la necesidad pendiente.'
      using errcode = '23514';
  end if;
  -- La misma revalidación que el otro camino del plan: cotizar un producto de
  -- bodega también lo compromete.
  perform public.supply_need_choice_is_checked_internal_v1(
    v_tenant_id, p_source_need_id, p_product_id, true
  );
  if public.inventory_available_quantity_v1(v_tenant_id, p_product_id)
       >= v_need.quantity
     and v_need.internal_stock_rejection_reason is null then
    raise exception 'Decide primero si usarás el stock interno disponible.'
      using errcode = '55000';
  end if;

  select product.* into v_product
  from public.products product
  where product.tenant_id = v_tenant_id
    and product.id = p_product_id
    and product.is_active is true;
  if not found then
    raise exception 'Producto no encontrado.' using errcode = 'P0002';
  end if;

  -- Si ya apareció una factura, esta ruta perdió vigencia. El cliente relee
  -- y el writer histórico reemplaza la misma línea por su unique need_id.
  if exists (
    select 1 from public.purchase_candidate_metrics_v1 candidate
    where candidate.tenant_id = v_tenant_id
      and candidate.product_id = p_product_id
  ) then
    raise exception 'El producto ya tiene historial de compra; vuelve a cargar.'
      using errcode = '40001';
  end if;

  select supplier.name into v_catalog_supplier_name
  from public.suppliers supplier
  where supplier.tenant_id = v_tenant_id
    and supplier.id = v_product.supplier_id;

  select check_row.* into v_availability
  from public.supplier_availability_checks check_row
  where check_row.tenant_id = v_tenant_id
    and check_row.product_id = p_product_id
    and check_row.status <> 'probe_missing'
  order by (
    check_row.status = 'available'
    and check_row.checked_at >= statement_timestamp() - interval '24 hours'
  ) desc,
    check_row.checked_at desc, check_row.id desc
  limit 1;
  if v_availability.id is not null then
    select supplier.name into v_availability_supplier_name
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = v_availability.supplier_id;
  end if;

  if v_availability.id is not null
     and v_availability.status = 'available'
     and v_availability.checked_at >= statement_timestamp() - interval '24 hours'
  then
    v_evidence_state := 'fresh_supplier_check';
    v_supplier_id := v_availability.supplier_id;
    v_supplier_name := v_availability_supplier_name;
  elsif v_product.supplier_id is not null
        and v_catalog_supplier_name is not null then
    v_evidence_state := 'catalog_assignment';
    v_supplier_id := v_product.supplier_id;
    v_supplier_name := v_catalog_supplier_name;
  else
    v_evidence_state := 'no_erp_history';
    v_supplier_id := null;
    v_supplier_name := null;
  end if;

  v_currency := public.tenant_commercial_currency_internal_v1(v_tenant_id);
  v_evidence := jsonb_strip_nulls(jsonb_build_object(
    'captured_at', clock_timestamp(),
    'ranking_profile', p_profile,
    'ranking_version', 'catalog-sourcing-v1',
    'evidence_state', v_evidence_state,
    'product_id', v_product.id,
    'supplier_id', v_supplier_id,
    'supplier_name', v_supplier_name,
    'catalog_supplier_id', v_product.supplier_id,
    'catalog_supplier_name', v_catalog_supplier_name,
    'purchase_count', 0,
    'supplier_availability', 'unverified',
    'availability_status', case when v_availability.id is null
      then null else v_availability.status end,
    'availability_checked_at', case when v_availability.id is null
      then null else v_availability.checked_at end,
    'availability_supplier_id', case when v_availability.id is null
      then null else v_availability.supplier_id end,
    'availability_supplier_name', v_availability_supplier_name,
    'availability_source_url', case when v_availability.id is null
      then null else v_availability.source_url end,
    'availability_price_net', case when v_availability.id is null
      then null else v_availability.price_net end,
    'availability_stock_quantity', case when v_availability.id is null
      then null else v_availability.stock_quantity end
  ));

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

  v_changed := not v_had_existing
    or v_existing.state <> 'active'
    or v_existing.candidate_id is not null
    or v_existing.product_id <> v_product.id
    or v_existing.supplier_id is distinct from v_supplier_id
    or v_existing.supplier_name is distinct from v_supplier_name
    or v_existing.quantity <> p_quantity
    or v_existing.evidence_state <> v_evidence_state
    or v_plan.objective_profile <> p_profile;

  if v_existing.id is null then
    insert into public.purchase_plan_lines (
      tenant_id, plan_id, source_need_id, candidate_id, product_id,
      supplier_id, supplier_name, quantity, unit, currency_code,
      landed_unit_cost_net, projected_gross_margin_ratio,
      supplier_availability, evidence_snapshot, evidence_state, state,
      created_by, updated_by
    ) values (
      v_tenant_id, v_plan.id, v_need.id, null, v_product.id,
      v_supplier_id, v_supplier_name, p_quantity, v_need.unit, v_currency,
      null, null, 'unverified', v_evidence, v_evidence_state, 'active',
      v_actor_id, v_actor_id
    ) returning * into v_line;
  elsif v_changed then
    update public.purchase_plan_lines line
    set candidate_id = null,
        product_id = v_product.id,
        supplier_id = v_supplier_id,
        supplier_name = v_supplier_name,
        quantity = p_quantity,
        unit = v_need.unit,
        currency_code = v_currency,
        landed_unit_cost_net = null,
        projected_gross_margin_ratio = null,
        supplier_availability = 'unverified',
        evidence_snapshot = v_evidence,
        evidence_state = v_evidence_state,
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
