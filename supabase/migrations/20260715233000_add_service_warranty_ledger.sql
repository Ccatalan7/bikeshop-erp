-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Deployment verification: 404 immutable deliveries, 405 projected jobs,
-- 7 classified legacy claims, unchanged invoice/payment/stock/journal totals,
-- zero stock drift, zero unbalanced journals, and zero open trace operations.
-- Adds an immutable, server-timestamped delivery and service-warranty ledger.
-- The linked sales invoice remains the sole owner of stock and accounting.
-- Historical delivery/claim data is classified conservatively: no legacy
-- stock, journal, payment, invoice total, or job total is rewritten here.
begin;

alter table public.mechanic_jobs
  add column if not exists status_updated_at timestamptz;

create or replace function public.update_job_status_timestamp()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.status_updated_at := clock_timestamp();
  elsif old.status is distinct from new.status
     or old.status_id is distinct from new.status_id then
    new.status_updated_at := clock_timestamp();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_job_status_timestamp on public.mechanic_jobs;
create trigger trg_job_status_timestamp
  before insert or update of status, status_id on public.mechanic_jobs
  for each row execute function public.update_job_status_timestamp();

update public.mechanic_jobs
set status_updated_at = coalesce(updated_at, created_at, clock_timestamp())
where status_updated_at is null;

-- These lifecycle flags exist in production and in the Flutter contract but
-- were missing from the canonical snapshot/migration chain.
alter table public.job_statuses
  add column if not exists triggers_start boolean not null default false,
  add column if not exists triggers_completion boolean not null default false,
  add column if not exists triggers_delivery boolean not null default false;

update public.job_statuses
set triggers_start = true
where lower(coalesce(code, name, '')) in ('en_curso', 'en curso')
  and not triggers_start;

update public.job_statuses
set triggers_completion = true
where lower(coalesce(code, name, '')) in ('finalizado', 'terminado')
  and not triggers_completion;

update public.job_statuses
set triggers_delivery = true
where lower(coalesce(code, name, '')) = 'entregado'
  and not triggers_delivery;

create table if not exists public.mechanic_job_delivery_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  job_id uuid not null references public.mechanic_jobs(id) on delete restrict,
  event_kind text not null check (event_kind in (
    'delivered', 'redelivered', 'warranty_extended'
  )),
  occurred_at timestamptz not null default clock_timestamp(),
  recorded_at timestamptz not null default clock_timestamp(),
  actor_id uuid references auth.users(id) on delete set null,
  starts_warranty_window boolean not null default false,
  warranty_days_snapshot integer check (
    warranty_days_snapshot is null
    or warranty_days_snapshot between 0 and 365
  ),
  warranty_started_at timestamptz,
  warranty_expires_at timestamptz,
  reason text,
  source text not null check (source in (
    'status_transition', 'legacy_timeline', 'legacy_current_state',
    'manual_extension'
  )),
  source_timeline_id uuid references public.mechanic_job_timeline(id)
    on delete restrict,
  operation_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, operation_key),
  unique (source_timeline_id),
  check (
    not starts_warranty_window
    or (
      warranty_days_snapshot is not null
      and warranty_started_at is not null
      and warranty_expires_at is not null
      and warranty_expires_at >= warranty_started_at
    )
  )
);

create index if not exists idx_mechanic_job_delivery_events_job
  on public.mechanic_job_delivery_events(tenant_id, job_id, occurred_at desc);
create index if not exists idx_mechanic_job_delivery_events_warranty
  on public.mechanic_job_delivery_events(tenant_id, warranty_expires_at)
  where starts_warranty_window;

alter table public.mechanic_job_delivery_events enable row level security;
drop policy if exists mechanic_job_delivery_events_select
  on public.mechanic_job_delivery_events;
create policy mechanic_job_delivery_events_select
  on public.mechanic_job_delivery_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.mechanic_job_delivery_events
  from public, anon, authenticated, service_role;
grant select on public.mechanic_job_delivery_events to authenticated;

create or replace function public.prevent_service_warranty_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Delivery and service-warranty events are append-only'
    using errcode = '55000';
end;
$$;

drop trigger if exists trg_mechanic_job_delivery_events_immutable
  on public.mechanic_job_delivery_events;
create trigger trg_mechanic_job_delivery_events_immutable
  before update or delete on public.mechanic_job_delivery_events
  for each row execute function public.prevent_service_warranty_event_mutation();

create or replace function public.mechanic_job_resolves_delivery(
  p_status text,
  p_status_id uuid
)
returns boolean
language sql
stable
set search_path = public
as $$
  select upper(coalesce(p_status, '')) = 'ENTREGADO'
    or exists (
      select 1
      from public.job_statuses status
      where status.id = p_status_id
        and (
          coalesce(status.triggers_delivery, false)
          or lower(coalesce(status.code, '')) = 'entregado'
        )
    );
$$;

create or replace function public.mechanic_job_resolves_completion(
  p_status text,
  p_status_id uuid
)
returns boolean
language sql
stable
set search_path = public
as $$
  select upper(coalesce(p_status, '')) in ('FINALIZADO', 'ENTREGADO')
    or exists (
      select 1
      from public.job_statuses status
      where status.id = p_status_id
        and (
          coalesce(status.triggers_completion, false)
          or coalesce(status.triggers_delivery, false)
          or lower(coalesce(status.code, '')) in ('finalizado', 'entregado')
        )
    );
$$;

create or replace function public.capture_mechanic_job_delivery_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_delivered boolean := false;
  v_new_delivered boolean;
  v_has_delivery boolean;
  v_occurred_at timestamptz := clock_timestamp();
begin
  if tg_op = 'UPDATE' then
    v_old_delivered := public.mechanic_job_resolves_delivery(
      old.status,
      old.status_id
    );
  end if;

  v_new_delivered := public.mechanic_job_resolves_delivery(
    new.status,
    new.status_id
  );

  if v_old_delivered or not v_new_delivered then
    return new;
  end if;

  select exists (
    select 1
    from public.mechanic_job_delivery_events event
    where event.tenant_id = new.tenant_id
      and event.job_id = new.id
      and event.event_kind in ('delivered', 'redelivered')
  ) into v_has_delivery;

  insert into public.mechanic_job_delivery_events (
    tenant_id,
    job_id,
    event_kind,
    occurred_at,
    actor_id,
    starts_warranty_window,
    warranty_days_snapshot,
    warranty_started_at,
    warranty_expires_at,
    source,
    operation_key,
    metadata
  ) values (
    new.tenant_id,
    new.id,
    case when v_has_delivery then 'redelivered' else 'delivered' end,
    v_occurred_at,
    auth.uid(),
    not v_has_delivery,
    case when v_has_delivery then null else 14 end,
    case when v_has_delivery then null else v_occurred_at end,
    case when v_has_delivery then null else v_occurred_at + interval '14 days' end,
    'status_transition',
    format(
      'delivery:auto:%s:%s:%s',
      new.id,
      txid_current(),
      gen_random_uuid()
    ),
    jsonb_build_object(
      'legacy_status', new.status,
      'custom_status_id', new.status_id,
      'warranty_reset', not v_has_delivery
    )
  );

  return new;
end;
$$;

revoke all on function public.capture_mechanic_job_delivery_event()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_capture_delivery
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_capture_delivery
  after insert or update of status, status_id on public.mechanic_jobs
  for each row execute function public.capture_mechanic_job_delivery_event();

-- Backfill every reliable historical delivery transition. Only the first
-- delivery opens the 14-day window; legacy re-deliveries never silently reset
-- it because the historical reason is unknown.
with historical_delivery as (
  select
    timeline.id as source_timeline_id,
    job.tenant_id,
    job.id as job_id,
    timeline.created_at as occurred_at,
    row_number() over (
      partition by job.id
      order by timeline.created_at, timeline.id
    ) as delivery_sequence,
    count(*) over (partition by job.id) as delivery_count
  from public.mechanic_job_timeline timeline
  join public.mechanic_jobs job on job.id = timeline.job_id
  where timeline.event_type = 'delivered'
     or (
       timeline.event_type in ('status_changed', 'completed')
       and upper(coalesce(timeline.new_value, '')) = 'ENTREGADO'
     )
)
insert into public.mechanic_job_delivery_events (
  tenant_id,
  job_id,
  event_kind,
  occurred_at,
  actor_id,
  starts_warranty_window,
  warranty_days_snapshot,
  warranty_started_at,
  warranty_expires_at,
  source,
  source_timeline_id,
  operation_key,
  metadata
)
select
  historical.tenant_id,
  historical.job_id,
  case when historical.delivery_sequence = 1
    then 'delivered' else 'redelivered' end,
  historical.occurred_at,
  null,
  historical.delivery_sequence = 1,
  case when historical.delivery_sequence = 1 then 14 end,
  case when historical.delivery_sequence = 1 then historical.occurred_at end,
  case when historical.delivery_sequence = 1
    then historical.occurred_at + interval '14 days' end,
  'legacy_timeline',
  historical.source_timeline_id,
  'delivery:legacy-timeline:' || historical.source_timeline_id,
  jsonb_build_object(
    'backfilled', true,
    'delivery_sequence', historical.delivery_sequence,
    'legacy_delivery_count', historical.delivery_count,
    'legacy_ambiguous', historical.delivery_count > 1,
    'warranty_reset', historical.delivery_sequence = 1
  )
from historical_delivery historical
on conflict (source_timeline_id) do nothing;

-- Cover currently delivered jobs whose legacy timeline is incomplete. This is
-- an operational classification only; mechanic_jobs.delivered_at is untouched.
insert into public.mechanic_job_delivery_events (
  tenant_id,
  job_id,
  event_kind,
  occurred_at,
  actor_id,
  starts_warranty_window,
  warranty_days_snapshot,
  warranty_started_at,
  warranty_expires_at,
  source,
  operation_key,
  metadata
)
select
  job.tenant_id,
  job.id,
  'delivered',
  coalesce(job.delivered_at, job.status_updated_at, job.updated_at, job.created_at),
  null,
  true,
  14,
  coalesce(job.delivered_at, job.status_updated_at, job.updated_at, job.created_at),
  coalesce(job.delivered_at, job.status_updated_at, job.updated_at, job.created_at)
    + interval '14 days',
  'legacy_current_state',
  'delivery:legacy-current:' || job.id,
  jsonb_build_object(
    'backfilled', true,
    'timeline_missing', true,
    'timestamp_source', case
      when job.delivered_at is not null then 'delivered_at'
      when job.status_updated_at is not null then 'status_updated_at'
      when job.updated_at is not null then 'updated_at'
      else 'created_at'
    end
  )
from public.mechanic_jobs job
where public.mechanic_job_resolves_delivery(job.status, job.status_id)
  and not exists (
    select 1
    from public.mechanic_job_delivery_events event
    where event.tenant_id = job.tenant_id
      and event.job_id = job.id
      and event.event_kind in ('delivered', 'redelivered')
  )
on conflict (tenant_id, operation_key) do nothing;

drop view if exists public.mechanic_job_service_warranty_view;
create view public.mechanic_job_service_warranty_view
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  job.customer_id,
  job.bike_id,
  job.subject_id,
  job.job_type,
  delivery.first_delivered_at,
  delivery.last_delivered_at,
  delivery.delivery_count,
  delivery.has_ambiguous_legacy_history,
  warranty.id as warranty_event_id,
  warranty.warranty_started_at,
  warranty.warranty_expires_at,
  warranty.warranty_days_snapshot,
  case
    when warranty.warranty_expires_at is null then 'not_started'
    when warranty.warranty_expires_at >= clock_timestamp() then 'active'
    else 'expired'
  end as warranty_state,
  case
    when warranty.warranty_expires_at is null then null
    else greatest(
      ceil(extract(epoch from (
        warranty.warranty_expires_at - clock_timestamp()
      )) / 86400.0),
      0
    )::integer
  end as warranty_days_remaining
from public.mechanic_jobs job
left join lateral (
  select
    min(event.occurred_at) as first_delivered_at,
    max(event.occurred_at) as last_delivered_at,
    count(*)::integer as delivery_count,
    bool_or(coalesce((event.metadata->>'legacy_ambiguous')::boolean, false))
      as has_ambiguous_legacy_history
  from public.mechanic_job_delivery_events event
  where event.tenant_id = job.tenant_id
    and event.job_id = job.id
    and event.event_kind in ('delivered', 'redelivered')
) delivery on true
left join lateral (
  select event.*
  from public.mechanic_job_delivery_events event
  where event.tenant_id = job.tenant_id
    and event.job_id = job.id
    and event.starts_warranty_window
  order by event.occurred_at desc, event.recorded_at desc, event.id desc
  limit 1
) warranty on true;

grant select on public.mechanic_job_service_warranty_view to authenticated;

create or replace function public.extend_mechanic_job_service_warranty(
  p_job_id uuid,
  p_new_expires_at timestamptz,
  p_reason text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_window public.mechanic_job_delivery_events%rowtype;
  v_event public.mechanic_job_delivery_events%rowtype;
begin
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
  for update;

  if not found then
    raise exception 'Trabajo no encontrado';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'La extensión de garantía requiere una justificación';
  end if;
  if btrim(coalesce(p_operation_key, '')) = '' then
    raise exception 'La extensión de garantía requiere una clave de operación';
  end if;

  select * into v_event
  from public.mechanic_job_delivery_events
  where tenant_id = v_job.tenant_id
    and operation_key = p_operation_key;
  if found then
    return to_jsonb(v_event) || jsonb_build_object('replay', true);
  end if;

  select * into v_window
  from public.mechanic_job_delivery_events
  where tenant_id = v_job.tenant_id
    and job_id = v_job.id
    and starts_warranty_window
  order by occurred_at desc, recorded_at desc, id desc
  limit 1;

  if not found then
    raise exception 'El trabajo no tiene una entrega registrada';
  end if;
  if p_new_expires_at is null
     or p_new_expires_at <= v_window.warranty_expires_at then
    raise exception 'La nueva vigencia debe ser posterior a la actual';
  end if;

  insert into public.mechanic_job_delivery_events (
    tenant_id,
    job_id,
    event_kind,
    occurred_at,
    actor_id,
    starts_warranty_window,
    warranty_days_snapshot,
    warranty_started_at,
    warranty_expires_at,
    reason,
    source,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    'warranty_extended',
    clock_timestamp(),
    auth.uid(),
    true,
    ceil(extract(epoch from (
      p_new_expires_at - v_window.warranty_started_at
    )) / 86400.0)::integer,
    v_window.warranty_started_at,
    p_new_expires_at,
    btrim(p_reason),
    'manual_extension',
    p_operation_key,
    jsonb_build_object(
      'previous_warranty_event_id', v_window.id,
      'previous_expires_at', v_window.warranty_expires_at
    )
  ) returning * into v_event;

  return to_jsonb(v_event) || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.extend_mechanic_job_service_warranty(
  uuid, timestamptz, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.extend_mechanic_job_service_warranty(
  uuid, timestamptz, text, text
) to authenticated;

create table if not exists public.mechanic_job_warranty_claim_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  warranty_job_id uuid not null references public.mechanic_jobs(id)
    on delete restrict,
  source_job_id uuid references public.mechanic_jobs(id) on delete restrict,
  source_delivery_event_id uuid references public.mechanic_job_delivery_events(id)
    on delete restrict,
  event_type text not null check (event_type in ('registration', 'decision')),
  eligibility text not null check (eligibility in (
    'within_window', 'outside_window', 'unknown'
  )),
  warranty_expires_at_snapshot timestamptz,
  outcome text not null check (outcome in (
    'pending', 'covered', 'not_covered'
  )),
  reason text,
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default clock_timestamp(),
  operation_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  unique (tenant_id, operation_key)
);

create index if not exists idx_mechanic_job_warranty_claim_events_job
  on public.mechanic_job_warranty_claim_events(
    tenant_id, warranty_job_id, occurred_at desc
  );
create index if not exists idx_mechanic_job_warranty_claim_events_source
  on public.mechanic_job_warranty_claim_events(
    tenant_id, source_job_id, occurred_at desc
  ) where source_job_id is not null;

alter table public.mechanic_job_warranty_claim_events enable row level security;
drop policy if exists mechanic_job_warranty_claim_events_select
  on public.mechanic_job_warranty_claim_events;
create policy mechanic_job_warranty_claim_events_select
  on public.mechanic_job_warranty_claim_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.mechanic_job_warranty_claim_events
  from public, anon, authenticated, service_role;
grant select on public.mechanic_job_warranty_claim_events to authenticated;

drop trigger if exists trg_mechanic_job_warranty_claim_events_immutable
  on public.mechanic_job_warranty_claim_events;
create trigger trg_mechanic_job_warranty_claim_events_immutable
  before update or delete on public.mechanic_job_warranty_claim_events
  for each row execute function public.prevent_service_warranty_event_mutation();

drop view if exists public.mechanic_job_warranty_claims_view;
create view public.mechanic_job_warranty_claims_view
with (security_invoker = true)
as
select
  warranty_job.tenant_id,
  warranty_job.id as warranty_job_id,
  warranty_job.job_number as warranty_job_number,
  registration.source_job_id,
  source_job.job_number as source_job_number,
  source_job.bike_id as source_bike_id,
  source_job.subject_id as source_subject_id,
  subject.name as source_subject_name,
  registration.source_delivery_event_id,
  registration.eligibility,
  registration.warranty_expires_at_snapshot,
  coalesce(decision.outcome, registration.outcome, 'pending') as outcome,
  decision.reason,
  registration.occurred_at as registered_at,
  decision.occurred_at as decided_at,
  decision.actor_id as decided_by
from public.mechanic_jobs warranty_job
left join lateral (
  select event.*
  from public.mechanic_job_warranty_claim_events event
  where event.tenant_id = warranty_job.tenant_id
    and event.warranty_job_id = warranty_job.id
    and event.event_type = 'registration'
  order by event.occurred_at desc, event.id desc
  limit 1
) registration on true
left join lateral (
  select event.*
  from public.mechanic_job_warranty_claim_events event
  where event.tenant_id = warranty_job.tenant_id
    and event.warranty_job_id = warranty_job.id
    and event.event_type = 'decision'
  order by event.occurred_at desc, event.id desc
  limit 1
) decision on true
left join public.mechanic_jobs source_job
  on source_job.id = registration.source_job_id
 and source_job.tenant_id = warranty_job.tenant_id
left join public.job_subjects subject
  on subject.id = source_job.subject_id
 and subject.tenant_id = warranty_job.tenant_id
where warranty_job.job_type = 'warranty'
   or warranty_job.is_warranty_job;

grant select on public.mechanic_job_warranty_claims_view to authenticated;

create or replace function public.record_service_warranty_trace(
  p_tenant_id uuid,
  p_job_id uuid,
  p_operation_key text,
  p_action text,
  p_before jsonb,
  p_after jsonb,
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_id uuid;
  v_outcome text;
begin
  insert into public.inventory_accounting_operations (
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    before_snapshot,
    after_snapshot,
    context,
    outcome
  ) values (
    p_tenant_id,
    'service_warranty:' || p_operation_key,
    'mechanic_job',
    p_action,
    'mechanic_job',
    p_job_id,
    auth.uid(),
    'service_warranty_rpc',
    p_before,
    p_after,
    coalesce(p_context, '{}'::jsonb) || jsonb_build_object(
      'inventory_owner', 'sales_invoice',
      'accounting_owner', 'sales_invoice'
    ),
    'started'
  )
  on conflict (tenant_id, operation_key) do nothing
  returning id into v_operation_id;

  if v_operation_id is null then
    select id, outcome into v_operation_id, v_outcome
    from public.inventory_accounting_operations
    where tenant_id = p_tenant_id
      and operation_key = 'service_warranty:' || p_operation_key;
    if v_outcome = 'completed' then
      return v_operation_id;
    end if;
  end if;

  if not exists (
    select 1 from public.inventory_accounting_checkpoints
    where operation_id = v_operation_id and phase = 'accepted'
  ) then
    perform public.append_inventory_accounting_checkpoint(
      v_operation_id,
      'accepted',
      'completed',
      'mechanic_job',
      p_job_id,
      jsonb_build_object('action', p_action)
    );
    perform public.append_inventory_accounting_checkpoint(
      v_operation_id,
      'source_snapshotted',
      'completed',
      'mechanic_job',
      p_job_id,
      jsonb_build_object('before', p_before, 'after', p_after)
    );
    perform public.append_inventory_accounting_checkpoint(
      v_operation_id,
      'accounting_planned',
      'completed',
      'mechanic_job',
      p_job_id,
      jsonb_build_object(
        'posting_owner', 'linked_sales_invoice',
        'job_owned_stock_writes', 0,
        'job_owned_journal_writes', 0
      )
    );
  end if;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    p_tenant_id,
    jsonb_build_object(
      'classification_recorded', true,
      'financial_effects_delegated_to_invoice', true
    )
  );
  return v_operation_id;
end;
$$;

revoke all on function public.record_service_warranty_trace(
  uuid, uuid, text, text, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.register_mechanic_job_warranty_claim(
  p_warranty_job_id uuid,
  p_source_job_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_warranty_job public.mechanic_jobs%rowtype;
  v_source_job public.mechanic_jobs%rowtype;
  v_existing public.mechanic_job_warranty_claim_events%rowtype;
  v_delivery public.mechanic_job_delivery_events%rowtype;
  v_event public.mechanic_job_warranty_claim_events%rowtype;
  v_eligibility text;
  v_operation_id uuid;
begin
  if p_warranty_job_id is null or p_source_job_id is null then
    raise exception 'La garantía debe vincularse al trabajo original';
  end if;
  if p_warranty_job_id = p_source_job_id then
    raise exception 'El trabajo de garantía no puede ser su propio origen';
  end if;
  if btrim(coalesce(p_operation_key, '')) = '' then
    raise exception 'La garantía requiere una clave de operación';
  end if;

  select * into v_warranty_job
  from public.mechanic_jobs
  where id = p_warranty_job_id
  for update;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;
  perform public.assert_workshop_rpc_tenant(v_warranty_job.tenant_id);

  select * into v_source_job
  from public.mechanic_jobs
  where id = p_source_job_id
    and tenant_id = v_warranty_job.tenant_id;
  if not found then raise exception 'Trabajo original no encontrado'; end if;

  if v_warranty_job.customer_id is distinct from v_source_job.customer_id then
    raise exception 'La garantía y el trabajo original deben pertenecer al mismo cliente';
  end if;
  if v_warranty_job.bike_id is not null
     and v_source_job.bike_id is not null
     and v_warranty_job.bike_id is distinct from v_source_job.bike_id then
    raise exception 'La bicicleta de garantía no coincide con el trabajo original';
  end if;
  if v_warranty_job.subject_id is not null
     and v_source_job.subject_id is not null
     and v_warranty_job.subject_id is distinct from v_source_job.subject_id then
    raise exception 'El componente de garantía no coincide con el trabajo original';
  end if;

  select * into v_event
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_warranty_job.tenant_id
    and operation_key = p_operation_key;
  if found then
    return to_jsonb(v_event) || jsonb_build_object('replay', true);
  end if;

  select * into v_existing
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_warranty_job.tenant_id
    and warranty_job_id = v_warranty_job.id
    and event_type = 'registration'
  order by occurred_at desc, id desc
  limit 1;

  if found and v_existing.source_job_id is not null then
    if v_existing.source_job_id is distinct from v_source_job.id then
      raise exception 'La garantía ya está vinculada a otro trabajo original';
    end if;
    return to_jsonb(v_existing) || jsonb_build_object('replay', true);
  end if;

  select * into v_delivery
  from public.mechanic_job_delivery_events
  where tenant_id = v_source_job.tenant_id
    and job_id = v_source_job.id
    and starts_warranty_window
  order by occurred_at desc, recorded_at desc, id desc
  limit 1;

  v_eligibility := case
    when v_delivery.id is null then 'unknown'
    when v_delivery.warranty_expires_at >= clock_timestamp() then 'within_window'
    else 'outside_window'
  end;

  insert into public.mechanic_job_warranty_claim_events (
    tenant_id,
    warranty_job_id,
    source_job_id,
    source_delivery_event_id,
    event_type,
    eligibility,
    warranty_expires_at_snapshot,
    outcome,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_warranty_job.tenant_id,
    v_warranty_job.id,
    v_source_job.id,
    v_delivery.id,
    'registration',
    v_eligibility,
    v_delivery.warranty_expires_at,
    'pending',
    auth.uid(),
    p_operation_key,
    jsonb_build_object(
      'source_job_type', v_source_job.job_type,
      'source_bike_id', v_source_job.bike_id,
      'source_subject_id', v_source_job.subject_id
    )
  ) returning * into v_event;

  perform set_config('app.warranty_claim_rpc', 'true', true);
  update public.mechanic_jobs
  set job_type = 'warranty',
      is_warranty_job = true,
      warranty_outcome = 'pending',
      bike_id = coalesce(bike_id, v_source_job.bike_id),
      subject_id = coalesce(subject_id, v_source_job.subject_id),
      updated_at = clock_timestamp()
  where id = v_warranty_job.id;
  perform set_config('app.warranty_claim_rpc', '', true);

  v_operation_id := public.record_service_warranty_trace(
    v_warranty_job.tenant_id,
    v_warranty_job.id,
    p_operation_key,
    'warranty_claim_registered',
    jsonb_build_object('outcome', v_warranty_job.warranty_outcome),
    jsonb_build_object(
      'outcome', 'pending',
      'source_job_id', v_source_job.id,
      'eligibility', v_eligibility
    ),
    jsonb_build_object('claim_event_id', v_event.id)
  );

  return to_jsonb(v_event) || jsonb_build_object(
    'operation_id', v_operation_id,
    'replay', false
  );
exception
  when others then
    perform set_config('app.warranty_claim_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) to authenticated;

create or replace function public.guard_mechanic_job_warranty_decision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.warranty_outcome is distinct from new.warranty_outcome
     and exists (
       select 1
       from public.mechanic_job_warranty_claim_events event
       where event.tenant_id = old.tenant_id
         and event.warranty_job_id = old.id
     )
     and current_setting('app.warranty_claim_rpc', true) <> 'true' then
    raise exception 'Use the service-warranty decision command so the reason and accounting trace are preserved'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_mechanic_jobs_guard_warranty_decision
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_warranty_decision
  before update of warranty_outcome on public.mechanic_jobs
  for each row execute function public.guard_mechanic_job_warranty_decision();

create or replace function public.normalize_covered_warranty_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_covered boolean;
begin
  select exists (
    select 1
    from public.mechanic_jobs job
    where job.tenant_id = new.tenant_id
      and job.invoice_id = new.id
      and job.job_type = 'warranty'
      and job.warranty_outcome = 'covered'
  ) into v_is_covered;

  if not v_is_covered then return new; end if;

  select coalesce(
    jsonb_agg(
      line.value || jsonb_build_object(
        'warranty_reference_unit_price', coalesce(
          nullif(line.value->>'warranty_reference_unit_price', '')::numeric,
          coalesce(nullif(line.value->>'unit_price', '')::numeric, 0)
        ),
        'warranty_reference_line_total', coalesce(
          nullif(line.value->>'warranty_reference_line_total', '')::numeric,
          coalesce(nullif(line.value->>'line_total', '')::numeric, 0)
        ),
        -- Keep the reference unit price on the technical job line. Customer
        -- obligation is represented by line_total/invoice totals, not by
        -- destroying the price needed if coverage is later rejected.
        'unit_price', coalesce(
          nullif(line.value->>'warranty_reference_unit_price', '')::numeric,
          coalesce(nullif(line.value->>'unit_price', '')::numeric, 0)
        ),
        'discount', 0,
        'line_total', 0,
        'covered_service_warranty', true
      )
      order by line.ordinality
    ),
    '[]'::jsonb
  ) into new.items
  from jsonb_array_elements(coalesce(new.items, '[]'::jsonb))
    with ordinality as line(value, ordinality);

  new.subtotal := 0;
  new.net_amount := 0;
  new.iva_amount := 0;
  new.total := 0;
  new.discount_amount := 0;
  new.balance := 0;
  new.tax_treatment := 'no_tax';
  return new;
end;
$$;

revoke all on function public.normalize_covered_warranty_invoice()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sales_invoices_normalize_covered_warranty
  on public.sales_invoices;
create trigger trg_sales_invoices_normalize_covered_warranty
  before update on public.sales_invoices
  for each row execute function public.normalize_covered_warranty_invoice();

create or replace function public.create_service_warranty_cost_journal(
  p_invoice public.sales_invoices
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_total_cost numeric(14,2);
  v_entry_id uuid := gen_random_uuid();
  v_expense_account_id uuid;
  v_inventory_account_id uuid;
  v_operation_id uuid;
  v_operation_text text;
  v_description text;
begin
  if p_invoice.id is null
     or lower(coalesce(p_invoice.status, 'draft')) in (
       'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
       'cancelled','cancelado','cancelada','anulado','anulada'
     ) then
    return;
  end if;

  select * into v_job
  from public.mechanic_jobs
  where tenant_id = p_invoice.tenant_id
    and invoice_id = p_invoice.id
    and job_type = 'warranty'
    and warranty_outcome = 'covered';
  if not found then return; end if;

  if exists (
    select 1 from public.journal_entries entry
    where entry.tenant_id = p_invoice.tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference = p_invoice.invoice_number
  ) then
    return;
  end if;

  select coalesce(sum(
    case
      when coalesce((item->>'is_service')::boolean, false) then 0
      when coalesce(nullif(item->>'item_type', ''), 'product') <> 'product' then 0
      when coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')
        = 'workshop_consumable' then 0
      else coalesce(nullif(item->>'quantity', '')::numeric, 0)
        * coalesce(nullif(item->>'cost', '')::numeric, 0)
    end
  ), 0)
  into v_total_cost
  from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item;

  v_total_cost := round(coalesce(v_total_cost, 0), 2);
  if v_total_cost <= 0 then return; end if;

  v_expense_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '5115',
    'Garantías de Servicio Técnico',
    'expense',
    'operatingExpense',
    'Costo de repuestos asumido por garantías de servicio técnico',
    null
  );
  v_inventory_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Inventario disponible para la venta',
    null
  );

  v_operation_text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  if v_operation_text ~* '^[0-9a-f-]{36}$' then
    v_operation_id := v_operation_text::uuid;
  end if;

  v_description := format(
    'Garantía cubierta %s - trabajo %s',
    p_invoice.invoice_number,
    v_job.job_number
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    operation_id,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    p_invoice.tenant_id,
    public.get_next_document_number(p_invoice.tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, clock_timestamp()),
    v_description,
    'warranty',
    'sales_invoices',
    p_invoice.invoice_number,
    'posted',
    v_total_cost,
    v_total_cost,
    v_operation_id,
    clock_timestamp(),
    clock_timestamp()
  );

  insert into public.journal_lines (
    tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) values (
    p_invoice.tenant_id, v_entry_id, v_expense_account_id, '5115',
    'Garantías de Servicio Técnico', v_description, v_total_cost, 0,
    clock_timestamp(), clock_timestamp()
  ), (
    p_invoice.tenant_id, v_entry_id, v_inventory_account_id, '1105',
    'Inventarios', v_description, 0, v_total_cost,
    clock_timestamp(), clock_timestamp()
  );
end;
$$;

revoke all on function public.create_service_warranty_cost_journal(
  public.sales_invoices
) from public, anon, authenticated, service_role;

create or replace function public.handle_service_warranty_invoice_posting()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.create_service_warranty_cost_journal(new);
  return new;
end;
$$;

revoke all on function public.handle_service_warranty_invoice_posting()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_trg_sales_invoices_service_warranty_journal
  on public.sales_invoices;
create trigger zz_trg_sales_invoices_service_warranty_journal
  after insert or update on public.sales_invoices
  for each row execute function public.handle_service_warranty_invoice_posting();

create or replace function public.sync_covered_warranty_invoice_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_complete boolean := false;
  v_new_complete boolean;
  v_invoice public.sales_invoices%rowtype;
  v_operation_text text;
  v_operation_id uuid;
begin
  if new.job_type <> 'warranty'
     or new.warranty_outcome <> 'covered'
     or new.invoice_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_old_complete := public.mechanic_job_resolves_completion(
      old.status,
      old.status_id
    );
  end if;
  v_new_complete := public.mechanic_job_resolves_completion(
    new.status,
    new.status_id
  );

  if v_new_complete then
    update public.sales_invoices invoice
    set status = 'confirmed', updated_at = clock_timestamp()
    where invoice.id = new.invoice_id
      and invoice.tenant_id = new.tenant_id
      and lower(invoice.status) in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
      )
    returning invoice.* into v_invoice;

    -- This update is intentionally nested under the job transition. The
    -- legacy generic invoice trigger exits at trigger depth > 1, so invoke the
    -- same invoice-owned writers explicitly. Both are idempotent by invoice
    -- reference and keep the job itself free of stock/accounting writes.
    if v_invoice.id is not null then
      perform public.consume_sales_invoice_inventory(v_invoice);
      perform public.create_service_warranty_cost_journal(v_invoice);

      -- The generic completion trigger intentionally skips nested invoice
      -- updates. Close the invoice-owned trace here after the explicit writers
      -- have attached their stock movement and warranty-cost journal to it.
      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = new.tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            new.tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'posted'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  elsif v_old_complete then
    select * into v_invoice
    from public.sales_invoices invoice
    where invoice.id = new.invoice_id
      and invoice.tenant_id = new.tenant_id
      and lower(invoice.status) not in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      )
    for update;

    if v_invoice.id is not null then
      update public.sales_invoices
      set status = case when upper(coalesce(new.status, '')) = 'CANCELADO'
        then 'cancelled' else 'draft' end,
        updated_at = clock_timestamp()
      where id = v_invoice.id;

      -- Start the nested invoice trace before restoring stock. The invoice
      -- update removes the current warranty journal through its own posting
      -- handler; the explicit restore remains invoice-owned and idempotent.
      perform public.restore_sales_invoice_inventory(v_invoice);
      delete from public.journal_entries
      where tenant_id = v_invoice.tenant_id
        and source_module = 'sales_invoices'
        and source_reference = v_invoice.invoice_number;

      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = new.tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            new.tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'reversed'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.sync_covered_warranty_invoice_lifecycle()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_covered_warranty_invoice_lifecycle
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_covered_warranty_invoice_lifecycle
  after insert or update of status, status_id on public.mechanic_jobs
  for each row execute function public.sync_covered_warranty_invoice_lifecycle();

create or replace function public.decide_mechanic_job_warranty_claim(
  p_warranty_job_id uuid,
  p_outcome text,
  p_reason text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_registration public.mechanic_job_warranty_claim_events%rowtype;
  v_event public.mechanic_job_warranty_claim_events%rowtype;
  v_invoice_id uuid;
  v_operation_id uuid;
begin
  if p_outcome not in ('pending', 'covered', 'not_covered') then
    raise exception 'Resultado de garantía inválido';
  end if;
  if btrim(coalesce(p_operation_key, '')) = '' then
    raise exception 'La decisión de garantía requiere una clave de operación';
  end if;

  select * into v_job
  from public.mechanic_jobs
  where id = p_warranty_job_id
  for update;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select * into v_event
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_job.tenant_id
    and operation_key = p_operation_key;
  if found then
    return to_jsonb(v_event) || jsonb_build_object('replay', true);
  end if;

  select * into v_registration
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_job.tenant_id
    and warranty_job_id = v_job.id
    and event_type = 'registration'
  order by occurred_at desc, id desc
  limit 1;
  if not found then
    raise exception 'Primero vincula la garantía con el trabajo original';
  end if;

  if p_outcome = 'covered'
     and v_registration.eligibility <> 'within_window'
     and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Aceptar una garantía fuera de plazo o sin fecha requiere justificación';
  end if;
  if p_outcome = 'not_covered'
     and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Rechazar una garantía requiere una justificación';
  end if;
  if p_outcome = 'covered'
     and v_job.invoice_id is not null
     and exists (
       select 1
       from public.sales_payments payment
       where payment.tenant_id = v_job.tenant_id
         and payment.invoice_id = v_job.invoice_id
         and payment.deleted_at is null
         and coalesce(payment.amount, 0) > 0
     ) then
    raise exception 'No se puede marcar como cubierta una garantía con pagos vigentes; primero revierte o reembolsa el pago desde la factura';
  end if;

  insert into public.mechanic_job_warranty_claim_events (
    tenant_id,
    warranty_job_id,
    source_job_id,
    source_delivery_event_id,
    event_type,
    eligibility,
    warranty_expires_at_snapshot,
    outcome,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    v_registration.source_job_id,
    v_registration.source_delivery_event_id,
    'decision',
    v_registration.eligibility,
    v_registration.warranty_expires_at_snapshot,
    p_outcome,
    nullif(btrim(coalesce(p_reason, '')), ''),
    auth.uid(),
    p_operation_key,
    jsonb_build_object('previous_outcome', v_job.warranty_outcome)
  ) returning * into v_event;

  -- Reversing a previously covered decision first returns the internal invoice
  -- to a non-posted state. The canonical invoice trigger restores inventory and
  -- removes the warranty-cost journal before billable prices are rebuilt.
  if v_job.warranty_outcome = 'covered'
     and p_outcome <> 'covered'
     and v_job.invoice_id is not null then
    update public.sales_invoices
    set status = 'draft', updated_at = clock_timestamp()
    where id = v_job.invoice_id
      and tenant_id = v_job.tenant_id
      and lower(status) not in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      );
  end if;

  perform set_config('app.warranty_claim_rpc', 'true', true);
  update public.mechanic_jobs
  set warranty_outcome = p_outcome,
      is_warranty_job = true,
      updated_at = clock_timestamp()
  where id = v_job.id;
  perform set_config('app.warranty_claim_rpc', '', true);

  select invoice_id into v_invoice_id
  from public.mechanic_jobs
  where id = v_job.id;

  if v_invoice_id is null then
    v_invoice_id := public.create_invoice_from_mechanic_job(v_job.id);
    if v_invoice_id is not null then
      perform public.sync_job_to_invoice(v_job.id);
    end if;
  else
    perform public.sync_job_to_invoice(v_job.id);
  end if;

  if p_outcome = 'covered'
     and public.mechanic_job_resolves_completion(v_job.status, v_job.status_id)
     and v_invoice_id is not null then
    update public.sales_invoices
    set status = 'confirmed', updated_at = clock_timestamp()
    where id = v_invoice_id
      and tenant_id = v_job.tenant_id
      and lower(status) in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
      );
  end if;

  v_operation_id := public.record_service_warranty_trace(
    v_job.tenant_id,
    v_job.id,
    p_operation_key,
    'warranty_claim_decided',
    jsonb_build_object('outcome', v_job.warranty_outcome),
    jsonb_build_object(
      'outcome', p_outcome,
      'eligibility', v_registration.eligibility,
      'reason', nullif(btrim(coalesce(p_reason, '')), ''),
      'invoice_id', v_invoice_id
    ),
    jsonb_build_object('claim_event_id', v_event.id)
  );

  return to_jsonb(v_event) || jsonb_build_object(
    'invoice_id', v_invoice_id,
    'operation_id', v_operation_id,
    'replay', false
  );
exception
  when others then
    perform set_config('app.warranty_claim_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.decide_mechanic_job_warranty_claim(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.decide_mechanic_job_warranty_claim(
  uuid, text, text, text
) to authenticated;

-- Legacy claim classification. Source links and financial effects are unknown,
-- so existing outcomes are preserved without guessing or replaying stock.
insert into public.mechanic_job_warranty_claim_events (
  tenant_id,
  warranty_job_id,
  source_job_id,
  source_delivery_event_id,
  event_type,
  eligibility,
  warranty_expires_at_snapshot,
  outcome,
  reason,
  actor_id,
  occurred_at,
  operation_key,
  metadata
)
select
  job.tenant_id,
  job.id,
  null,
  null,
  'registration',
  'unknown',
  null,
  'pending',
  null,
  null,
  coalesce(job.created_at, clock_timestamp()),
  'warranty-claim:legacy-registration:' || job.id,
  jsonb_build_object(
    'backfilled', true,
    'source_link_unknown', true,
    'financial_effects_replayed', false
  )
from public.mechanic_jobs job
where (job.job_type = 'warranty' or job.is_warranty_job)
  and not exists (
    select 1
    from public.mechanic_job_warranty_claim_events event
    where event.tenant_id = job.tenant_id
      and event.warranty_job_id = job.id
      and event.event_type = 'registration'
  )
on conflict (tenant_id, operation_key) do nothing;

insert into public.mechanic_job_warranty_claim_events (
  tenant_id,
  warranty_job_id,
  source_job_id,
  source_delivery_event_id,
  event_type,
  eligibility,
  warranty_expires_at_snapshot,
  outcome,
  reason,
  actor_id,
  occurred_at,
  operation_key,
  metadata
)
select
  job.tenant_id,
  job.id,
  null,
  null,
  'decision',
  'unknown',
  null,
  job.warranty_outcome,
  'Decisión histórica preservada; trabajo original no identificado.',
  null,
  coalesce(job.updated_at, job.created_at, clock_timestamp()),
  'warranty-claim:legacy-decision:' || job.id,
  jsonb_build_object(
    'backfilled', true,
    'source_link_unknown', true,
    'financial_effects_replayed', false,
    'preserved_invoice_id', job.invoice_id
  )
from public.mechanic_jobs job
where (job.job_type = 'warranty' or job.is_warranty_job)
  and job.warranty_outcome in ('covered', 'not_covered')
  and not exists (
    select 1
    from public.mechanic_job_warranty_claim_events event
    where event.tenant_id = job.tenant_id
      and event.warranty_job_id = job.id
      and event.event_type = 'decision'
  )
on conflict (tenant_id, operation_key) do nothing;

comment on table public.mechanic_job_delivery_events is
  'Immutable server-side delivery ledger. First delivery freezes the default 14-day service-warranty window; reopening or re-delivery does not erase or silently reset it.';
comment on table public.mechanic_job_warranty_claim_events is
  'Immutable registration and decision history for warranty jobs linked to their original delivered work.';
comment on view public.mechanic_job_service_warranty_view is
  'Current delivery and 14-day service-warranty projection derived from immutable events.';
comment on view public.mechanic_job_warranty_claims_view is
  'Current warranty-claim projection, including source work, eligibility snapshot, decision, reason, and actor.';

commit;
