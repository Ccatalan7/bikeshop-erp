-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact constraint/function read-back passed.
-- Review-only quantity editing for intelligent purchase plans.
--
-- The command changes only the frozen draft line and its supplier subtotal.
-- It never changes the originating need or creates a purchase, accounting or
-- inventory document.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

alter table public.purchase_plan_events
  drop constraint if exists purchase_plan_events_action_check;
alter table public.purchase_plan_events
  add constraint purchase_plan_events_action_check check (action in (
    'line_prepared', 'line_removed', 'line_quantity_changed',
    'plan_ready', 'plan_cancelled', 'conversion_prepared', 'converted'
  ));

create or replace function public.update_purchase_plan_line_quantity_v1(
  p_plan_id uuid,
  p_expected_plan_version bigint,
  p_line_id uuid,
  p_quantity numeric,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.purchase_plan_events%rowtype;
  v_plan public.purchase_plans%rowtype;
  v_line public.purchase_plan_lines%rowtype;
  v_need public.supply_needs%rowtype;
  v_groups jsonb;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_plan_id is null or p_expected_plan_version is null or p_line_id is null
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'El plan, versión, línea, cantidad y clave son obligatorios.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'plan_id', p_plan_id,
    'expected_plan_version', p_expected_plan_version,
    'line_id', p_line_id,
    'quantity', p_quantity
  );
  select event.* into v_receipt
  from public.purchase_plan_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'line_quantity_changed'
       or v_receipt.plan_id <> p_plan_id
       or v_receipt.line_id <> p_line_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio del plan.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  -- Read the immutable references first, then lock in the same need -> plan ->
  -- line order used by candidate preparation to avoid a concurrent deadlock.
  select line.* into v_line
  from public.purchase_plan_lines line
  where line.tenant_id = v_tenant_id
    and line.plan_id = p_plan_id
    and line.id = p_line_id;
  if not found then
    raise exception 'Línea del plan no encontrada.' using errcode = 'P0002';
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id
    and need.id = v_line.source_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.supply_state <> 'open'
     or v_need.identity_state <> 'confirmed'
     or v_need.product_id is null
     or v_need.product_id <> v_line.product_id then
    raise exception 'La necesidad ya no admite cambios en este plan.'
      using errcode = '55000';
  end if;
  if p_quantity > v_need.quantity then
    raise exception 'La cantidad del plan excede la necesidad pendiente.'
      using errcode = '23514';
  end if;

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

  select line.* into v_line
  from public.purchase_plan_lines line
  where line.tenant_id = v_tenant_id
    and line.plan_id = v_plan.id
    and line.id = p_line_id
  for update;
  if not found then
    raise exception 'Línea del plan no encontrada.' using errcode = 'P0002';
  end if;
  if v_line.state <> 'active' then
    raise exception 'Sólo una línea activa puede cambiar de cantidad.'
      using errcode = '55000';
  end if;
  if v_line.source_need_id <> v_need.id
     or v_line.product_id <> v_need.product_id then
    raise exception 'La línea cambió; vuelve a cargar el plan.'
      using errcode = '40001';
  end if;

  v_changed := v_line.quantity <> p_quantity;
  if v_changed then
    update public.purchase_plan_lines line
    set quantity = p_quantity,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where line.tenant_id = v_tenant_id and line.id = v_line.id
    returning * into v_line;

    update public.purchase_plans plan
    set version = plan.version + 1,
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
    v_tenant_id, v_plan.id, v_line.id, 'line_quantity_changed', v_changed,
    v_actor_id, v_operation_key, v_request, v_response
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.update_purchase_plan_line_quantity_v1(
  uuid, bigint, uuid, numeric, text
) from public, anon, authenticated, service_role;
grant execute on function public.update_purchase_plan_line_quantity_v1(
  uuid, bigint, uuid, numeric, text
) to authenticated;

comment on function public.update_purchase_plan_line_quantity_v1(
  uuid, bigint, uuid, numeric, text
) is
  'Idempotently edits one active review-only plan line within its still-open source need. It creates no purchase or inventory side effect.';

notify pgrst, 'reload schema';

commit;
