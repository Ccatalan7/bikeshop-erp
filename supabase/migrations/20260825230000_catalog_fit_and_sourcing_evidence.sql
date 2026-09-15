-- Catálogo completo para calce; historial ERP sólo para evidencia de compra.
--
-- La migración de Zoho dejó una brecha esperable: hay productos reales y
-- comprados antes del ERP que no tienen una factura de compra dentro de este
-- sistema. Excluirlos del flujo de abastecimiento confunde dos preguntas:
--
--   1. ¿Qué producto cumple exactamente lo pedido?     -> ficha/catálogo.
--   2. ¿A quién se lo compramos y a qué costo?         -> evidencia ERP.
--
-- Un producto sin historia sigue siendo elegible y accionable, pero nunca
-- recibe porcentajes, costos, disponibilidad ni una compra inventados. Viaja
-- como "Por cotizar" hasta que una compra real lo promueva automáticamente al
-- carril histórico.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Una línea por producto no tiene candidato histórico ni necesariamente un
-- proveedor. El producto y la necesidad siguen siendo obligatorios.
alter table public.purchase_plan_lines
  alter column candidate_id drop not null,
  alter column supplier_name drop not null;

alter table public.purchase_plan_lines
  add column if not exists evidence_state text;

update public.purchase_plan_lines
set evidence_state = case
  when candidate_id is not null then 'erp_purchase_history'
  else coalesce(nullif(evidence_snapshot ->> 'evidence_state', ''),
    'no_erp_history')
end
where evidence_state is null;

alter table public.purchase_plan_lines
  alter column evidence_state set default 'erp_purchase_history',
  alter column evidence_state set not null;

alter table public.purchase_plan_lines
  drop constraint if exists purchase_plan_lines_evidence_state_check;
alter table public.purchase_plan_lines
  add constraint purchase_plan_lines_evidence_state_check check (
    evidence_state in (
      'erp_purchase_history',
      'fresh_supplier_check',
      'catalog_assignment',
      'no_erp_history'
    )
  );

-- El writer histórico asumía que candidate_id nunca podía ser NULL. Cuando
-- promueve una línea "Por cotizar" a una compra real, `NULL <> uuid` produce
-- NULL (no true): no actualiza la línea y después intenta guardar ese NULL en
-- purchase_plan_events.changed. Reemplazamos sólo esa comparación sobre la
-- definición instalada; si el predecesor no es exactamente el esperado, la
-- migración falla en vez de parchear una función desconocida.
do $$
declare
  v_signature regprocedure :=
    'public.prepare_purchase_plan_line_v1(uuid,bigint,uuid,uuid,numeric,text,text)'::regprocedure;
  v_definition text;
  v_replaced text;
begin
  select pg_get_functiondef(v_signature) into v_definition;
  v_replaced := replace(
    v_definition,
    'v_existing.candidate_id <> v_candidate.candidate_id',
    'v_existing.candidate_id is distinct from v_candidate.candidate_id'
  );
  if v_replaced = v_definition then
    if position(
      'v_existing.candidate_id is distinct from v_candidate.candidate_id'
      in v_definition
    ) = 0 then
      raise exception
        'prepare_purchase_plan_line_v1 no conserva la comparación candidata esperada';
    end if;
    return;
  end if;
  if length(v_definition) - length(replace(
    v_definition,
    'v_existing.candidate_id <> v_candidate.candidate_id',
    ''
  )) <> length('v_existing.candidate_id <> v_candidate.candidate_id') then
    raise exception
      'prepare_purchase_plan_line_v1 contiene más de una comparación candidata';
  end if;
  execute v_replaced;
end;
$$;

-- Un writer histórico que reemplaza una línea "Por cotizar" no debe acordarse
-- de limpiar el estado nuevo: la presencia del candidato es la autoridad.
create or replace function public.purchase_plan_line_evidence_state_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.candidate_id is not null then
    new.evidence_state := 'erp_purchase_history';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_purchase_plan_line_evidence_state
  on public.purchase_plan_lines;
create trigger trg_purchase_plan_line_evidence_state
  before insert or update of candidate_id, evidence_state
  on public.purchase_plan_lines
  for each row execute function public.purchase_plan_line_evidence_state_v1();

-- Fuente pequeña y reutilizable para la lectura de stock y para la UI. El
-- historial tiene prioridad; un chequeo fresco puede introducir un proveedor;
-- la asignación de la ficha sólo dice "proveedor en catálogo".
create or replace function public.product_sourcing_evidence_internal_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
  with requested as (
    select product_id, min(ordinality) as ordinality
    from unnest(coalesce(p_product_ids, array[]::uuid[]))
      with ordinality input(product_id, ordinality)
    where product_id is not null
    group by product_id
  ), facts as (
    select
      requested.ordinality,
      product.id as product_id,
      product.supplier_id as catalog_supplier_id,
      catalog_supplier.name as catalog_supplier_name,
      history.candidate_id,
      history.supplier_id as history_supplier_id,
      history.supplier_name as history_supplier_name,
      history.purchase_count,
      history.last_purchase_at,
      availability.supplier_id as availability_supplier_id,
      availability_supplier.name as availability_supplier_name,
      availability.status as availability_status,
      availability.checked_at as availability_checked_at,
      availability.source_url as availability_source_url,
      availability.price_net as availability_price_net,
      availability.stock_quantity as availability_stock_quantity,
      availability.checked_at >= statement_timestamp() - interval '24 hours'
        as availability_fresh
    from requested
    join public.products product
      on product.tenant_id = p_tenant_id
     and product.id = requested.product_id
     and product.is_active is true
    left join public.suppliers catalog_supplier
      on catalog_supplier.tenant_id = product.tenant_id
     and catalog_supplier.id = product.supplier_id
    left join lateral (
      select
        metric.candidate_id,
        metric.supplier_id,
        metric.supplier_name,
        totals.purchase_count,
        totals.last_purchase_at
      from public.purchase_candidate_metrics_v1 metric
      cross join lateral (
        select
          sum(all_metric.purchase_count)::integer as purchase_count,
          max(all_metric.latest_purchase_at) as last_purchase_at
        from public.purchase_candidate_metrics_v1 all_metric
        where all_metric.tenant_id = p_tenant_id
          and all_metric.product_id = product.id
      ) totals
      where metric.tenant_id = p_tenant_id
        and metric.product_id = product.id
      order by metric.latest_purchase_at desc nulls last,
        metric.purchase_count desc, metric.candidate_id
      limit 1
    ) history on true
    left join lateral (
      select check_row.*
      from public.supplier_availability_checks check_row
      where check_row.tenant_id = p_tenant_id
        and check_row.product_id = product.id
        and check_row.status <> 'probe_missing'
      order by (
        check_row.status = 'available'
        and check_row.checked_at >= statement_timestamp() - interval '24 hours'
      ) desc,
        check_row.checked_at desc, check_row.id desc
      limit 1
    ) availability on true
    left join public.suppliers availability_supplier
      on availability_supplier.tenant_id = p_tenant_id
     and availability_supplier.id = availability.supplier_id
  ), classified as (
    select facts.*,
      case
        when candidate_id is not null then 'erp_purchase_history'
        when availability_fresh is true
          and availability_status = 'available'
          then 'fresh_supplier_check'
        when catalog_supplier_id is not null then 'catalog_assignment'
        else 'no_erp_history'
      end as evidence_state,
      case
        when candidate_id is not null then history_supplier_id
        when availability_fresh is true
          and availability_status = 'available'
          then availability_supplier_id
        else catalog_supplier_id
      end as supplier_id,
      case
        when candidate_id is not null then history_supplier_name
        when availability_fresh is true
          and availability_status = 'available'
          then availability_supplier_name
        else catalog_supplier_name
      end as supplier_name
    from facts
  )
  select jsonb_build_object(
    'asOf', statement_timestamp(),
    'freshnessHours', 24,
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'evidenceState', evidence_state,
      'candidateId', candidate_id,
      'supplierId', supplier_id,
      'supplierName', supplier_name,
      'purchaseCount', coalesce(purchase_count, 0),
      'lastPurchaseAt', last_purchase_at,
      'catalogSupplierId', catalog_supplier_id,
      'catalogSupplierName', catalog_supplier_name,
      'availabilitySupplierId', availability_supplier_id,
      'availabilitySupplierName', availability_supplier_name,
      'availabilityStatus', availability_status,
      'availabilityCheckedAt', availability_checked_at,
      'availabilitySourceUrl', availability_source_url,
      'availabilityPriceNet', availability_price_net,
      'availabilityStockQuantity', availability_stock_quantity,
      'availabilityFresh', coalesce(availability_fresh, false)
    ) order by ordinality), '[]'::jsonb)
  )
  from classified;
$$;

revoke all on function public.product_sourcing_evidence_internal_v1(
  uuid, uuid[]
) from public, anon, authenticated, service_role;

create or replace function public.get_product_sourcing_evidence_v1(
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_count integer;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  v_count := coalesce(cardinality(p_product_ids), 0);
  if v_count not between 1 and 12
     or array_position(p_product_ids, null) is not null then
    raise exception 'Invalid product sourcing arguments' using errcode = '22023';
  end if;
  return public.product_sourcing_evidence_internal_v1(
    v_tenant_id, p_product_ids
  );
end;
$$;

revoke all on function public.get_product_sourcing_evidence_v1(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_product_sourcing_evidence_v1(uuid[])
  to authenticated;

-- El mismo envelope de stock, enriquecido en el mismo round trip. v1 queda
-- intacto para clientes instalados; v2 agrega sólo claves por fila.
create or replace function public.get_supply_need_stock_resolution_v2(
  p_need_id uuid,
  p_limit integer default 12,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_base jsonb;
  v_sources jsonb;
  v_items jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  v_base := public.get_supply_need_stock_resolution_v1(
    p_need_id, p_limit, p_offset
  );

  select public.product_sourcing_evidence_internal_v1(
    v_tenant_id,
    coalesce(array_agg((item.value ->> 'productId')::uuid
      order by item.ordinality), array[]::uuid[])
  )
  into v_sources
  from jsonb_array_elements(coalesce(v_base -> 'items', '[]'::jsonb))
    with ordinality item(value, ordinality);

  select coalesce(jsonb_agg(
      item.value || coalesce(source.value - 'productId', '{}'::jsonb)
      order by item.ordinality
    ), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base -> 'items', '[]'::jsonb))
    with ordinality item(value, ordinality)
  left join lateral (
    select source_item.value
    from jsonb_array_elements(coalesce(v_sources -> 'items', '[]'::jsonb))
      source_item(value)
    where source_item.value ->> 'productId' = item.value ->> 'productId'
    limit 1
  ) source on true;

  return jsonb_set(v_base, '{items}', v_items, true)
    || jsonb_build_object(
      'sourcingEvidenceAsOf', v_sources -> 'asOf',
      'sourcingFreshnessHours', v_sources -> 'freshnessHours'
    );
end;
$$;

revoke all on function public.get_supply_need_stock_resolution_v2(
  uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_stock_resolution_v2(
  uuid, integer, integer
) to authenticated;

-- Prepara una línea accionable aunque no exista candidato histórico. Es una
-- cotización pendiente, no una orden ni una afirmación de disponibilidad.
create or replace function public.prepare_purchase_plan_product_v1(
  p_plan_id uuid,
  p_expected_plan_version bigint,
  p_source_need_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_profile text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
set statement_timeout = '9000ms'
as $$
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
$$;

revoke all on function public.prepare_purchase_plan_product_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_purchase_plan_product_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) to authenticated;

-- Agrupar NULL como una decisión visible, no esconderlo ni inventar proveedor.
create or replace view public.purchase_plan_supplier_groups_v1
with (security_invoker = true)
as
select
  plan.tenant_id,
  plan.id as plan_id,
  line.supplier_id,
  coalesce(line.supplier_name, 'Por cotizar') as supplier_name,
  line.currency_code,
  count(*)::integer as line_count,
  sum(line.quantity)::numeric(18,3) as total_units,
  sum(line.quantity * line.landed_unit_cost_net)::numeric(18,4)
    as historical_landed_subtotal_net,
  'unverified'::text as supplier_availability,
  'sum_frozen_line_landed_costs_no_consolidation_saving'::text
    as freight_assumption
from public.purchase_plans plan
join public.purchase_plan_lines line
  on line.tenant_id = plan.tenant_id
 and line.plan_id = plan.id
 and line.state = 'active'
group by plan.tenant_id, plan.id, line.supplier_id,
  coalesce(line.supplier_name, 'Por cotizar'), line.currency_code;

revoke all on public.purchase_plan_supplier_groups_v1
  from public, anon, authenticated, service_role;
grant select on public.purchase_plan_supplier_groups_v1 to authenticated;

-- Cobertura significa calce exacto. Una consulta ampliada sigue siendo una
-- sugerencia útil, pero no completa la línea ni el carro.
create or replace function public.purchase_basket_supplier_coverage_internal_v1(
  p_tenant_id uuid,
  p_queries jsonb,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '12000ms'
as $$
declare
  v_need text;
  v_analysis jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_need_count integer := 0;
  v_items jsonb;
  v_total integer := 0;
  v_leader_id text;
  v_missing text;
  v_complement_name text;
  v_complement_covers text;
begin
  if jsonb_typeof(p_queries) <> 'array'
     or jsonb_array_length(p_queries) < 2
     or jsonb_array_length(p_queries) > 6
     or p_limit not between 1 and 5 then
    raise exception 'Invalid basket arguments' using errcode = '22023';
  end if;

  for v_need in
    select btrim(value #>> '{}')
    from jsonb_array_elements(p_queries) item(value)
    where btrim(coalesce(value #>> '{}', '')) <> ''
  loop
    v_need_count := v_need_count + 1;
    v_analysis := public.purchase_supplier_concentration_internal_v1(
      p_tenant_id, v_need, null, null, 5
    );
    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'need', v_need,
      'items', coalesce(v_analysis -> 'items', '[]'::jsonb)
    ));
  end loop;

  if v_need_count < 2 then
    raise exception 'Invalid basket arguments' using errcode = '22023';
  end if;

  with per_need as (
    select
      row.value ->> 'need' as need,
      supplier.value as supplier,
      coalesce((supplier.value ->> 'scopeRelaxed')::boolean, false) as relaxed
    from jsonb_array_elements(v_rows) row
    cross join lateral jsonb_array_elements(row.value -> 'items') supplier
  ), by_supplier as (
    select supplier ->> 'entityId' as supplier_id,
      max(supplier ->> 'supplierName') as supplier_name,
      count(distinct need) filter (where not relaxed)::integer as covered,
      count(distinct need) filter (where relaxed)::integer as approximate,
      string_agg(distinct need, ', ' order by need)
        filter (where not relaxed) as covered_list,
      string_agg(distinct need, ', ' order by need)
        filter (where relaxed) as approximate_list,
      sum((supplier ->> 'landedSpendNet')::numeric) as spend,
      round(avg((supplier ->> 'spendSharePercent')::numeric), 1) as avg_share,
      max((supplier ->> 'lastPurchaseAt')::timestamptz) as last_at,
      min((supplier ->> 'daysSinceLastPurchase')::integer) as days_since,
      max(supplier ->> 'supplierWebsite') as website,
      bool_or((supplier ->> 'hasPortalAccount')::boolean) as portal,
      max(supplier ->> 'supplierCity') as city,
      max(supplier ->> 'salesRepPhone') as rep_phone,
      max(supplier ->> 'salesRepEmail') as rep_email,
      string_agg(distinct nullif(supplier ->> 'brands', ''), ', '
        order by nullif(supplier ->> 'brands', '')) as brands
    from per_need
    where supplier ->> 'entityId' is not null
    group by 1
  ), ranked as (
    select by_supplier.*,
      row_number() over (
        order by covered desc, approximate desc, spend desc,
          last_at desc nulls last, supplier_id
      )::integer as rank,
      count(*) over ()::integer as supplier_count
    from by_supplier
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', rank,
      'entityId', supplier_id,
      'supplierName', supplier_name,
      'coveredNeeds', covered,
      'totalNeeds', v_need_count,
      'coveredList', covered_list,
      'approximateNeeds', approximate,
      'approximateList', approximate_list,
      'coverageSemantics', 'exact_only',
      'averageSharePercent', avg_share,
      'landedSpendNet', round(spend, 2),
      'lastPurchaseAt', last_at,
      'daysSinceLastPurchase', days_since,
      'brands', brands,
      'supplierWebsite', website,
      'hasPortalAccount', portal,
      'supplierCity', city,
      'salesRepPhone', rep_phone,
      'salesRepEmail', rep_email,
      'supplierAvailability', 'unverified'
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(supplier_count), 0),
    (array_agg(supplier_id order by rank))[1]
  into v_items, v_total, v_leader_id
  from ranked;

  if v_leader_id is not null then
    with per_need as (
      select
        row.value ->> 'need' as need,
        supplier.value as supplier,
        coalesce((supplier.value ->> 'scopeRelaxed')::boolean, false) as relaxed
      from jsonb_array_elements(v_rows) row
      cross join lateral jsonb_array_elements(row.value -> 'items') supplier
    ), leader_needs as (
      select distinct need from per_need
      where supplier ->> 'entityId' = v_leader_id and not relaxed
    ), uncovered as (
      select btrim(item.value #>> '{}') as need
      from jsonb_array_elements(p_queries) item(value)
      where btrim(coalesce(item.value #>> '{}', '')) <> ''
        and btrim(item.value #>> '{}') not in (select need from leader_needs)
    ), helpers as (
      select supplier ->> 'entityId' as supplier_id,
        max(supplier ->> 'supplierName') as supplier_name,
        count(distinct per_need.need)::integer as covered,
        string_agg(distinct per_need.need, ', '
          order by per_need.need) as list,
        sum((supplier ->> 'landedSpendNet')::numeric) as spend
      from per_need
      join uncovered on uncovered.need = per_need.need
      where supplier ->> 'entityId' <> v_leader_id
        and not relaxed
      group by 1
    )
    select
      (select string_agg(need, ', ' order by need) from uncovered),
      (select supplier_name from helpers
        order by covered desc, spend desc limit 1),
      (select list from helpers
        order by covered desc, spend desc limit 1)
    into v_missing, v_complement_name, v_complement_covers;

    if v_missing is not null and jsonb_array_length(v_items) > 0 then
      v_items := jsonb_set(v_items, '{0}',
        (v_items -> 0) || jsonb_build_object(
          'missingList', v_missing,
          'complementSupplierName', v_complement_name,
          'complementCoversList', v_complement_covers
        )
      );
    end if;
  end if;

  select coalesce(jsonb_agg(
      jsonb_build_object(
        'missingList', null,
        'complementSupplierName', null,
        'complementCoversList', null
      ) || item.value
      order by (item.value ->> 'rank')::integer
    ), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(v_items) item(value);

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;

revoke all on function public.purchase_basket_supplier_coverage_internal_v1(
  uuid, jsonb, integer
) from public, anon, authenticated, service_role;

comment on function public.get_product_sourcing_evidence_v1(uuid[]) is
  'Separates catalog eligibility from ERP purchase evidence; no-history products stay visible without invented economics or availability.';
comment on function public.prepare_purchase_plan_product_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) is
  'Idempotently prepares a quote-required line for an exact product with no ERP purchase history; performs no purchase, reservation or supplier action.';


commit;
