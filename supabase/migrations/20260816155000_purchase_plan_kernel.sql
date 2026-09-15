-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact ACL/schema read-back passed.
-- Purchase-plan draft kernel for intelligent purchasing.
--
-- A plan is a reviewable decision artifact. Preparing a line never creates a
-- purchase order, invoice, payment, receipt, inventory movement or external
-- supplier action. Candidate economics are frozen at selection time so a
-- later price/history change cannot rewrite the reason behind the decision.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create table if not exists public.purchase_plans (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  title text not null check (
    btrim(title) <> '' and octet_length(title) <= 160
  ),
  state text not null default 'draft' check (
    state in ('draft', 'ready', 'converted', 'cancelled')
  ),
  objective_profile text not null default 'balanced' check (
    objective_profile in ('balanced', 'profitability', 'urgent_local')
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id)
);

create table if not exists public.purchase_plan_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  plan_id uuid not null,
  source_need_id uuid not null,
  candidate_id uuid not null,
  product_id uuid not null,
  supplier_id uuid,
  supplier_name text not null check (
    btrim(supplier_name) <> '' and octet_length(supplier_name) <= 240
  ),
  quantity numeric(14,3) not null check (
    quantity > 0 and quantity <= 999999
  ),
  unit text not null check (btrim(unit) <> '' and octet_length(unit) <= 32),
  currency_code text not null check (
    btrim(currency_code) <> '' and octet_length(currency_code) <= 8
  ),
  landed_unit_cost_net numeric(18,6),
  projected_gross_margin_ratio numeric(12,8),
  supplier_availability text not null default 'unverified' check (
    supplier_availability = 'unverified'
  ),
  evidence_snapshot jsonb not null check (
    jsonb_typeof(evidence_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(evidence_snapshot)
  ),
  state text not null default 'active' check (
    state in ('active', 'removed')
  ),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, plan_id, source_need_id),
  foreign key (tenant_id, plan_id)
    references public.purchase_plans(tenant_id, id) on delete restrict,
  foreign key (tenant_id, source_need_id)
    references public.supply_needs(tenant_id, id) on delete restrict,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id) on delete restrict,
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete restrict
);

create index if not exists idx_purchase_plan_lines_plan_active
  on public.purchase_plan_lines(tenant_id, plan_id, updated_at desc, id)
  where state = 'active';
create index if not exists idx_purchase_plan_lines_need_active
  on public.purchase_plan_lines(tenant_id, source_need_id, updated_at desc)
  where state = 'active';

create table if not exists public.purchase_plan_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  plan_id uuid not null,
  line_id uuid,
  action text not null check (action in (
    'line_prepared', 'line_removed', 'plan_ready', 'plan_cancelled',
    'conversion_prepared', 'converted'
  )),
  changed boolean not null,
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null check (
    btrim(operation_key) <> '' and octet_length(operation_key) <= 200
  ),
  request_snapshot jsonb not null check (
    jsonb_typeof(request_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(request_snapshot)
  ),
  response_snapshot jsonb not null check (
    jsonb_typeof(response_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(response_snapshot)
  ),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, plan_id)
    references public.purchase_plans(tenant_id, id) on delete restrict,
  foreign key (tenant_id, line_id)
    references public.purchase_plan_lines(tenant_id, id) on delete restrict
);

create index if not exists idx_purchase_plan_events_plan
  on public.purchase_plan_events(
    tenant_id, plan_id, occurred_at desc, id desc
  );

alter table public.purchase_plans enable row level security;
alter table public.purchase_plan_lines enable row level security;
alter table public.purchase_plan_events enable row level security;

drop policy if exists purchase_plans_select on public.purchase_plans;
create policy purchase_plans_select on public.purchase_plans
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_plan_lines_select
  on public.purchase_plan_lines;
create policy purchase_plan_lines_select on public.purchase_plan_lines
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_plan_events_select
  on public.purchase_plan_events;
create policy purchase_plan_events_select on public.purchase_plan_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.purchase_plans
  from public, anon, authenticated, service_role;
revoke all on public.purchase_plan_lines
  from public, anon, authenticated, service_role;
revoke all on public.purchase_plan_events
  from public, anon, authenticated, service_role;
grant select on public.purchase_plans to authenticated;
grant select on public.purchase_plan_lines to authenticated;
grant select on public.purchase_plan_events to authenticated;

drop trigger if exists trg_purchase_plan_events_immutable
  on public.purchase_plan_events;
create trigger trg_purchase_plan_events_immutable
  before update or delete on public.purchase_plan_events
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

create or replace view public.purchase_plan_supplier_groups_v1
with (security_invoker = true)
as
select
  plan.tenant_id,
  plan.id as plan_id,
  line.supplier_id,
  line.supplier_name,
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
group by plan.tenant_id, plan.id, line.supplier_id, line.supplier_name,
  line.currency_code;

revoke all on public.purchase_plan_supplier_groups_v1
  from public, anon, authenticated, service_role;
grant select on public.purchase_plan_supplier_groups_v1 to authenticated;

create or replace function public.prepare_purchase_plan_line_v1(
  p_plan_id uuid,
  p_expected_plan_version bigint,
  p_source_need_id uuid,
  p_candidate_id uuid,
  p_quantity numeric,
  p_profile text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
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
    or v_existing.candidate_id <> v_candidate.candidate_id
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
$$;

revoke all on function public.prepare_purchase_plan_line_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_purchase_plan_line_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) to authenticated;

comment on table public.purchase_plans is
  'Reviewable external-purchase draft. It is not an order, invoice, payment, receipt or supplier action.';
comment on table public.purchase_plan_lines is
  'One active candidate per durable supply need, with selection-time economic evidence frozen for audit.';
comment on function public.prepare_purchase_plan_line_v1(
  uuid, bigint, uuid, uuid, numeric, text, text
) is
  'Idempotently prepares or replaces one draft plan line after the stock-first gate; it performs no purchase or inventory side effect.';

notify pgrst, 'reload schema';

commit;
