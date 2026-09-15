-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact catalog/invariant read-back passed.
--
-- Purpose:
--   Introduce the source-neutral supply-need kernel used by workshop parts
--   capture and the intelligent purchasing workspace. A job status may prompt
--   capture through an explicit semantic capability; selecting that status
--   never creates an empty need. All need mutations are tenant-authorized,
--   versioned, replay-safe commands with immutable receipts. Interpretation
--   revisions preserve operator text verbatim and never store model reasoning.
--
-- Forward behavior:
--   Additive tables, indexes, RLS policies, commands and one read model. The
--   only business-row update is an exact, fingerprinted activation of the
--   existing Viñabike REPUESTOS status.
-- Recovery behavior:
--   Leave additive evidence in place and disable
--   job_statuses.prompts_supply_need_capture. No existing job, invoice,
--   inventory, payment or journal row is rewritten.
-- Lock risk:
--   Brief ACCESS EXCLUSIVE locks while adding one boolean column and two
--   tenant/id unique indexes. The migration uses bounded lock and statement
--   timeouts and performs no backfill over mechanic jobs.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

alter table public.job_statuses
  add column if not exists prompts_supply_need_capture boolean not null
    default false;

create unique index if not exists uq_mechanic_jobs_tenant_id_id
  on public.mechanic_jobs(tenant_id, id);
create unique index if not exists uq_mechanic_job_bikes_tenant_id_id
  on public.mechanic_job_bikes(tenant_id, id);
create unique index if not exists uq_product_categories_tenant_id_id
  on public.product_categories(tenant_id, id);

create table if not exists public.supply_needs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  origin_kind text not null check (origin_kind in ('mechanic_job', 'ad_hoc')),
  mechanic_job_id uuid,
  job_bike_id uuid,
  assistant_thread_id uuid references public.assistant_threads(id)
    on delete set null,
  original_description text not null check (
    btrim(original_description) <> ''
    and octet_length(original_description) <= 2000
  ),
  product_id uuid,
  quantity numeric(14,3) not null check (
    quantity > 0 and quantity <= 999999
  ),
  unit text not null default 'unit' check (
    btrim(unit) <> '' and octet_length(unit) <= 32
  ),
  identity_state text not null default 'unresolved' check (
    identity_state in ('unresolved', 'proposed', 'confirmed')
  ),
  supply_state text not null default 'open' check (
    supply_state in (
      'open', 'committed', 'in_purchase', 'received', 'covered', 'cancelled'
    )
  ),
  usage_state text not null default 'pending' check (
    usage_state in ('pending', 'installed', 'reconciled', 'not_applicable')
  ),
  version bigint not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  internal_stock_rejection_reason text,
  internal_stock_rejected_at timestamptz,
  internal_stock_rejected_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  unique (tenant_id, id),
  foreign key (tenant_id, mechanic_job_id)
    references public.mechanic_jobs(tenant_id, id) on delete restrict,
  foreign key (tenant_id, job_bike_id)
    references public.mechanic_job_bikes(tenant_id, id) on delete restrict,
  foreign key (tenant_id, product_id)
    references public.products(tenant_id, id) on delete restrict,
  check (
    (origin_kind = 'mechanic_job' and mechanic_job_id is not null)
    or
    (
      origin_kind = 'ad_hoc'
      and mechanic_job_id is null
      and job_bike_id is null
    )
  ),
  check (job_bike_id is null or origin_kind = 'mechanic_job'),
  check (
    (product_id is null and identity_state in ('unresolved', 'proposed'))
    or (product_id is not null and identity_state = 'confirmed')
  ),
  check (
    (supply_state = 'cancelled'
      and cancelled_at is not null
      and btrim(coalesce(cancellation_reason, '')) <> '')
    or
    (supply_state <> 'cancelled' and cancelled_at is null)
  ),
  constraint supply_needs_internal_stock_rejection_check check (
    (internal_stock_rejection_reason is null
      and internal_stock_rejected_at is null
      and internal_stock_rejected_by is null)
    or
    (btrim(internal_stock_rejection_reason) <> ''
      and internal_stock_rejected_at is not null)
  )
);

alter table public.supply_needs
  add column if not exists internal_stock_rejection_reason text,
  add column if not exists internal_stock_rejected_at timestamptz,
  add column if not exists internal_stock_rejected_by uuid
    references auth.users(id) on delete set null;

alter table public.supply_needs
  drop constraint if exists supply_needs_internal_stock_rejection_check;
alter table public.supply_needs
  add constraint supply_needs_internal_stock_rejection_check check (
    (internal_stock_rejection_reason is null
      and internal_stock_rejected_at is null
      and internal_stock_rejected_by is null)
    or
    (btrim(internal_stock_rejection_reason) <> ''
      and internal_stock_rejected_at is not null)
  );

create index if not exists idx_supply_needs_job_active
  on public.supply_needs(
    tenant_id, mechanic_job_id, supply_state, updated_at desc, id
  ) where mechanic_job_id is not null;
create index if not exists idx_supply_needs_job_bike_active
  on public.supply_needs(
    tenant_id, job_bike_id, supply_state, updated_at desc, id
  ) where job_bike_id is not null;
create index if not exists idx_supply_needs_product_active
  on public.supply_needs(tenant_id, product_id, supply_state, id)
  where product_id is not null;
create index if not exists idx_supply_needs_attention
  on public.supply_needs(tenant_id, updated_at desc, id)
  where supply_state not in ('covered', 'cancelled');

create table if not exists public.supply_need_interpretation_revisions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  supply_need_id uuid not null,
  revision_no bigint not null check (revision_no > 0),
  source text not null check (source in ('manual', 'ai', 'system')),
  raw_description text not null check (
    btrim(raw_description) <> '' and octet_length(raw_description) <= 2000
  ),
  identity_state text not null check (
    identity_state in ('unresolved', 'proposed', 'confirmed')
  ),
  canonical_product_id uuid,
  proposed_product_id uuid,
  category_id uuid,
  constraints jsonb not null default '[]'::jsonb check (
    jsonb_typeof(constraints) = 'array'
  ),
  clarifications jsonb not null default '[]'::jsonb check (
    jsonb_typeof(clarifications) = 'array'
  ),
  evidence_snapshot jsonb not null default '{}'::jsonb check (
    jsonb_typeof(evidence_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(evidence_snapshot)
  ),
  formula_version text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, supply_need_id, revision_no),
  foreign key (tenant_id, supply_need_id)
    references public.supply_needs(tenant_id, id) on delete restrict,
  foreign key (tenant_id, canonical_product_id)
    references public.products(tenant_id, id) on delete restrict,
  foreign key (tenant_id, proposed_product_id)
    references public.products(tenant_id, id) on delete restrict,
  foreign key (tenant_id, category_id)
    references public.product_categories(tenant_id, id) on delete restrict,
  check (
    (identity_state = 'confirmed' and canonical_product_id is not null
      and proposed_product_id is null)
    or
    (identity_state = 'proposed' and canonical_product_id is null
      and proposed_product_id is not null)
    or
    (identity_state = 'unresolved' and canonical_product_id is null)
  )
);

create index if not exists idx_supply_need_interpretation_revisions_need
  on public.supply_need_interpretation_revisions(
    tenant_id, supply_need_id, revision_no desc
  );

create table if not exists public.supply_need_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  supply_need_id uuid not null,
  action text not null check (action in (
    'created', 'updated', 'cancelled',
    'stock_assigned', 'stock_released', 'stock_reactivated',
    'internal_stock_rejected',
    'purchase_planned', 'received', 'covered'
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
  foreign key (tenant_id, supply_need_id)
    references public.supply_needs(tenant_id, id) on delete restrict
);

alter table public.supply_need_events
  drop constraint if exists supply_need_events_action_check;
alter table public.supply_need_events
  add constraint supply_need_events_action_check check (action in (
    'created', 'updated', 'cancelled',
    'stock_assigned', 'stock_released', 'stock_reactivated',
    'internal_stock_rejected',
    'purchase_planned', 'received', 'covered'
  ));

create index if not exists idx_supply_need_events_need
  on public.supply_need_events(
    tenant_id, supply_need_id, occurred_at desc, id desc
  );

create table if not exists public.job_status_supply_capability_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  status_id uuid not null,
  enabled boolean not null,
  changed boolean not null,
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null check (
    btrim(operation_key) <> '' and octet_length(operation_key) <= 200
  ),
  request_snapshot jsonb not null check (
    jsonb_typeof(request_snapshot) = 'object'
  ),
  response_snapshot jsonb not null check (
    jsonb_typeof(response_snapshot) = 'object'
  ),
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, status_id)
    references public.job_statuses(tenant_id, id) on delete restrict
);

create index if not exists idx_job_status_supply_capability_events_status
  on public.job_status_supply_capability_events(
    tenant_id, status_id, occurred_at desc, id desc
  );

alter table public.supply_needs enable row level security;
alter table public.supply_need_interpretation_revisions enable row level security;
alter table public.supply_need_events enable row level security;
alter table public.job_status_supply_capability_events enable row level security;

drop policy if exists supply_needs_select on public.supply_needs;
create policy supply_needs_select on public.supply_needs
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists supply_need_interpretation_revisions_select
  on public.supply_need_interpretation_revisions;
create policy supply_need_interpretation_revisions_select
  on public.supply_need_interpretation_revisions
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists supply_need_events_select on public.supply_need_events;
create policy supply_need_events_select on public.supply_need_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists job_status_supply_capability_events_select
  on public.job_status_supply_capability_events;
create policy job_status_supply_capability_events_select
  on public.job_status_supply_capability_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.supply_needs
  from public, anon, authenticated, service_role;
revoke all on public.supply_need_interpretation_revisions
  from public, anon, authenticated, service_role;
revoke all on public.supply_need_events
  from public, anon, authenticated, service_role;
revoke all on public.job_status_supply_capability_events
  from public, anon, authenticated, service_role;
grant select on public.supply_needs to authenticated;
grant select on public.supply_need_interpretation_revisions to authenticated;
grant select on public.supply_need_events to authenticated;
grant select on public.job_status_supply_capability_events to authenticated;

create or replace function public.prevent_supply_kernel_evidence_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Supply kernel evidence is append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_supply_kernel_evidence_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supply_need_interpretation_revisions_immutable
  on public.supply_need_interpretation_revisions;
create trigger trg_supply_need_interpretation_revisions_immutable
  before update or delete on public.supply_need_interpretation_revisions
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

drop trigger if exists trg_supply_need_events_immutable
  on public.supply_need_events;
create trigger trg_supply_need_events_immutable
  before update or delete on public.supply_need_events
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

drop trigger if exists trg_job_status_supply_capability_events_immutable
  on public.job_status_supply_capability_events;
create trigger trg_job_status_supply_capability_events_immutable
  before update or delete on public.job_status_supply_capability_events
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

create or replace function public.create_supply_need_v1(
  p_origin_kind text,
  p_mechanic_job_id uuid,
  p_job_bike_id uuid,
  p_description text,
  p_product_id uuid,
  p_quantity numeric,
  p_unit text,
  p_assistant_thread_id uuid,
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
  v_origin_kind text := btrim(coalesce(p_origin_kind, ''));
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_event public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_identity_state text;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if v_origin_kind not in ('mechanic_job', 'ad_hoc')
     or p_description is null
     or btrim(p_description) = ''
     or octet_length(p_description) > 2000
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'Los datos de la necesidad no son válidos.'
      using errcode = '22023';
  end if;
  if (v_origin_kind = 'mechanic_job' and p_mechanic_job_id is null)
     or (v_origin_kind = 'ad_hoc'
       and (p_mechanic_job_id is not null or p_job_bike_id is not null))
     or (p_job_bike_id is not null and v_origin_kind <> 'mechanic_job') then
    raise exception 'La procedencia de la necesidad no coincide con su contexto.'
      using errcode = '23514';
  end if;

  v_request := jsonb_build_object(
    'origin_kind', v_origin_kind,
    'mechanic_job_id', p_mechanic_job_id,
    'job_bike_id', p_job_bike_id,
    'description', p_description,
    'product_id', p_product_id,
    'quantity', p_quantity,
    'unit', v_unit,
    'assistant_thread_id', p_assistant_thread_id
  );

  select event.* into v_event
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.action <> 'created'
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra necesidad.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  if v_origin_kind = 'mechanic_job' then
    select job.* into v_job
    from public.mechanic_jobs job
    where job.tenant_id = v_tenant_id
      and job.id = p_mechanic_job_id
      and job.deleted_at is null
    for share;
    if not found then
      raise exception 'Trabajo no encontrado.' using errcode = 'P0002';
    end if;
    if v_job.workflow_kind = 'sale' then
      raise exception 'Una venta sin recepción no usa necesidades de taller.'
        using errcode = '23514';
    end if;
    if p_job_bike_id is not null and not exists (
      select 1 from public.mechanic_job_bikes job_bike
      where job_bike.tenant_id = v_tenant_id
        and job_bike.id = p_job_bike_id
        and job_bike.job_id = v_job.id
    ) then
      raise exception 'La bicicleta no pertenece a este trabajo.'
        using errcode = '23514';
    end if;
  end if;

  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = p_product_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
  ) then
    raise exception 'El producto no existe, está inactivo o no es un repuesto.'
      using errcode = '23514';
  end if;

  if p_assistant_thread_id is not null and not exists (
    select 1 from public.assistant_threads thread
    where thread.tenant_id = v_tenant_id
      and thread.actor_user_id = v_actor_id
      and thread.id = p_assistant_thread_id
      and thread.state <> 'deleted'
  ) then
    raise exception 'La conversación de IA no pertenece a esta sesión.'
      using errcode = '42501';
  end if;

  v_identity_state := case
    when p_product_id is null then 'unresolved'
    else 'confirmed'
  end;

  insert into public.supply_needs (
    tenant_id, origin_kind, mechanic_job_id, job_bike_id,
    assistant_thread_id, original_description, product_id, quantity, unit,
    identity_state, supply_state, usage_state, version,
    created_by, updated_by, created_at, updated_at
  ) values (
    v_tenant_id, v_origin_kind, p_mechanic_job_id, p_job_bike_id,
    p_assistant_thread_id, p_description, p_product_id, p_quantity, v_unit,
    v_identity_state, 'open',
    case when v_origin_kind = 'mechanic_job' then 'pending'
      else 'not_applicable' end,
    1, v_actor_id, v_actor_id, clock_timestamp(), clock_timestamp()
  ) returning * into v_need;

  insert into public.supply_need_interpretation_revisions (
    tenant_id, supply_need_id, revision_no, source, raw_description,
    identity_state, canonical_product_id, constraints, clarifications,
    evidence_snapshot, formula_version, created_by
  ) values (
    v_tenant_id, v_need.id, 1, 'manual', p_description,
    v_identity_state, p_product_id, '[]'::jsonb, '[]'::jsonb,
    '{}'::jsonb, 'manual-v1', v_actor_id
  );

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', true,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );

  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'created', true, v_actor_id, v_operation_key,
    v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

create or replace function public.update_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_description text,
  p_product_id uuid,
  p_quantity numeric,
  p_unit text,
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
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_event public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_identity_state text;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_description is null or btrim(p_description) = ''
     or octet_length(p_description) > 2000
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'Los datos de la necesidad no son válidos.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'description', p_description,
    'product_id', p_product_id,
    'quantity', p_quantity,
    'unit', v_unit
  );

  select event.* into v_event
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.action <> 'updated'
       or v_event.supply_need_id <> p_need_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
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
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state in ('covered', 'cancelled') then
    raise exception 'La necesidad ya está cerrada y no puede editarse.'
      using errcode = '55000';
  end if;
  if v_need.supply_state = 'committed'
     and v_need.product_id is distinct from p_product_id then
    raise exception 'Libera primero el stock asignado antes de cambiar el producto.'
      using errcode = '55000';
  end if;

  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = p_product_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
  ) then
    raise exception 'El producto no existe, está inactivo o no es un repuesto.'
      using errcode = '23514';
  end if;

  v_identity_state := case
    when p_product_id is null then 'unresolved'
    else 'confirmed'
  end;
  v_changed := v_need.original_description is distinct from p_description
    or v_need.product_id is distinct from p_product_id
    or v_need.quantity is distinct from p_quantity
    or v_need.unit is distinct from v_unit
    or v_need.identity_state is distinct from v_identity_state;

  if v_changed then
    update public.supply_needs need
    set original_description = p_description,
        product_id = p_product_id,
        quantity = p_quantity,
        unit = v_unit,
        identity_state = v_identity_state,
        internal_stock_rejection_reason = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejection_reason
        end,
        internal_stock_rejected_at = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejected_at
        end,
        internal_stock_rejected_by = case
          when need.product_id is distinct from p_product_id
            or need.quantity is distinct from p_quantity
            then null
          else need.internal_stock_rejected_by
        end,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, constraints, clarifications,
      evidence_snapshot, formula_version, created_by
    ) values (
      v_tenant_id, v_need.id, v_need.version, 'manual', p_description,
      v_identity_state, p_product_id, '[]'::jsonb, '[]'::jsonb,
      '{}'::jsonb, 'manual-v1', v_actor_id
    );
  end if;

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', v_changed,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );

  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

create or replace function public.cancel_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_reason text,
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
  v_reason text := btrim(coalesce(p_reason, ''));
  v_request jsonb;
  v_response jsonb;
  v_event public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or v_reason = '' or octet_length(v_reason) > 500
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La cancelación requiere necesidad, versión y motivo.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'reason', v_reason
  );

  select event.* into v_event
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.action <> 'cancelled'
       or v_event.supply_need_id <> p_need_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra cancelación.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
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
    raise exception 'La necesidad cambió; vuelve a cargarla antes de cancelar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state = 'committed' then
    raise exception 'Libera primero el stock asignado antes de cancelar.'
      using errcode = '55000';
  end if;

  v_changed := v_need.supply_state <> 'cancelled';
  if v_changed then
    update public.supply_needs need
    set supply_state = 'cancelled',
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp(),
        cancelled_at = clock_timestamp(),
        cancelled_by = v_actor_id,
        cancellation_reason = v_reason
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;
  end if;

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', v_changed,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );

  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'cancelled', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

create or replace function public.set_job_status_supply_need_capability_v1(
  p_status_id uuid,
  p_enabled boolean,
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
  v_event public.job_status_supply_capability_events%rowtype;
  v_status public.job_statuses%rowtype;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_status_id is null or p_enabled is null
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'El estado, la capacidad y la clave son obligatorios.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'status_id', p_status_id,
    'enabled', p_enabled
  );

  select event.* into v_event
  from public.job_status_supply_capability_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.status_id <> p_status_id
       or v_event.enabled <> p_enabled
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra capacidad.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select status.* into v_status
  from public.job_statuses status
  where status.tenant_id = v_tenant_id and status.id = p_status_id
  for update;
  if not found then
    raise exception 'Estado no encontrado.' using errcode = 'P0002';
  end if;

  v_changed := v_status.prompts_supply_need_capture is distinct from p_enabled;
  if v_changed then
    update public.job_statuses status
    set prompts_supply_need_capture = p_enabled,
        updated_at = clock_timestamp()
    where status.tenant_id = v_tenant_id and status.id = p_status_id
    returning * into v_status;
  end if;

  v_response := jsonb_build_object(
    'status_id', v_status.id,
    'enabled', v_status.prompts_supply_need_capture,
    'changed', v_changed,
    'status', to_jsonb(v_status)
  );

  insert into public.job_status_supply_capability_events (
    tenant_id, status_id, enabled, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_status.id, p_enabled, v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.create_supply_need_v1(
  text, uuid, uuid, text, uuid, numeric, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function public.update_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.cancel_supply_need_v1(
  uuid, bigint, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.set_job_status_supply_need_capability_v1(
  uuid, boolean, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_supply_need_v1(
  text, uuid, uuid, text, uuid, numeric, text, uuid, text
) to authenticated;
grant execute on function public.update_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, text
) to authenticated;
grant execute on function public.cancel_supply_need_v1(
  uuid, bigint, text, text
) to authenticated;
grant execute on function public.set_job_status_supply_need_capability_v1(
  uuid, boolean, text
) to authenticated;

create or replace view public.mechanic_job_supply_attention_v1
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as mechanic_job_id,
  job.status_id,
  coalesce(status.prompts_supply_need_capture, false)
    as prompts_supply_need_capture,
  count(need.id) filter (
    where need.supply_state not in ('covered', 'cancelled')
  )::integer as active_need_count,
  count(need.id) filter (
    where need.supply_state not in ('covered', 'cancelled')
      and need.identity_state <> 'confirmed'
  )::integer as unresolved_identity_count,
  max(need.updated_at) filter (
    where need.supply_state not in ('covered', 'cancelled')
  ) as latest_need_updated_at,
  (
    coalesce(status.prompts_supply_need_capture, false)
    and count(need.id) filter (
      where need.supply_state not in ('covered', 'cancelled')
    ) = 0
  ) as requires_supply_definition
from public.mechanic_jobs job
left join public.job_statuses status
  on status.tenant_id = job.tenant_id and status.id = job.status_id
left join public.supply_needs need
  on need.tenant_id = job.tenant_id and need.mechanic_job_id = job.id
where job.deleted_at is null and job.workflow_kind <> 'sale'
group by job.tenant_id, job.id, job.status_id,
  status.prompts_supply_need_capture;

revoke all on public.mechanic_job_supply_attention_v1
  from public, anon, authenticated, service_role;
grant select on public.mechanic_job_supply_attention_v1 to authenticated;

comment on column public.job_statuses.prompts_supply_need_capture is
  'Semantic status capability. A confirmed transition may invite parts capture; it never creates a supply need by itself.';
comment on table public.supply_needs is
  'Source-neutral durable demand. Identity, supply resolution and workshop use are orthogonal; stock and accounting remain owned by their ledgers.';
comment on table public.supply_need_interpretation_revisions is
  'Append-only typed interpretations that preserve the operator text and evidence without model chain-of-thought.';
comment on view public.mechanic_job_supply_attention_v1 is
  'Derived workshop attention. Repuestos sin definir exists only when the current status prompts capture and no active need exists.';

-- Exact Viñabike activation. This is deliberately not a name/code heuristic:
-- another tenant or another status receives the safe false default.
do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_status_id constant uuid := 'f8574d41-d426-4540-8a34-e81881723738';
  v_status public.job_statuses%rowtype;
  v_request jsonb;
  v_response jsonb;
  v_changed boolean;
begin
  select status.* into v_status
  from public.job_statuses status
  where status.tenant_id = v_tenant_id
    and status.id = v_status_id
    and status.code = 'ESPERANDO_REPUESTOS'
  for update;
  if not found then
    return;
  end if;

  v_changed := not v_status.prompts_supply_need_capture;
  if v_changed then
    update public.job_statuses status
    set prompts_supply_need_capture = true,
        updated_at = clock_timestamp()
    where status.tenant_id = v_tenant_id and status.id = v_status_id
    returning * into v_status;
  end if;

  v_request := jsonb_build_object(
    'status_id', v_status_id,
    'enabled', true,
    'activation_source', 'verified_vinabike_status_2026_08_16'
  );
  v_response := jsonb_build_object(
    'status_id', v_status_id,
    'enabled', true,
    'changed', v_changed,
    'status', to_jsonb(v_status)
  );

  insert into public.job_status_supply_capability_events (
    tenant_id, status_id, enabled, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_status_id, true, v_changed, null,
    'migration:20260816150000:vinabike-parts-status',
    v_request, v_response, clock_timestamp()
  ) on conflict (tenant_id, operation_key) do nothing;
end;
$$;

notify pgrst, 'reload schema';

commit;
