-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15.
-- Deployment verification: registered as 20260716010000; 406 jobs and 762
-- invoices preserved; invoice/payment totals, stock, and journal totals
-- unchanged; zero quote invoice links, stock mismatches, or unbalanced journals.
--
-- Purpose:
--   Separate the commercial/workflow state of a workshop job from the physical
--   intake object while keeping job_type as a backwards-compatible facade.
--   Quotations are non-posting documents until an audited conversion command
--   turns the same row into a billable bicycle or component service.
--
-- Forward recovery:
--   The change is additive. An older client can continue reading/writing
--   job_type. If the new client must be rolled back, leave the new columns,
--   immutable events, and conservative review flags in place. The mode trigger
--   keeps job_type synchronized and the quotation invoice guard prevents new
--   accounting/inventory ownership from being attached to a quotation.

begin;

-- ---------------------------------------------------------------------------
-- 1. Orthogonal canonical axes (job_type remains the compatibility facade)
-- ---------------------------------------------------------------------------

alter table public.mechanic_jobs
  add column if not exists workflow_kind text,
  add column if not exists intake_kind text,
  add column if not exists mode_needs_review boolean,
  add column if not exists mode_review_reason text;

comment on column public.mechanic_jobs.workflow_kind is
  'Canonical commercial/workflow axis: service, quotation, or warranty. job_type remains a compatibility facade.';
comment on column public.mechanic_jobs.intake_kind is
  'Canonical physical-intake axis: bike, component, or unspecified. Component means the customer left only the loose component.';
comment on column public.mechanic_jobs.mode_needs_review is
  'Conservative flag for ambiguous legacy or incomplete intake classification. It never guesses a bicycle/component relationship.';
comment on column public.mechanic_jobs.mode_review_reason is
  'Human-readable reason why the mode/intake classification still needs review.';

-- ---------------------------------------------------------------------------
-- 2. Append-only mode and quotation history
-- ---------------------------------------------------------------------------

create table if not exists public.mechanic_job_mode_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  job_id uuid not null references public.mechanic_jobs(id) on delete restrict,
  event_type text not null check (event_type in (
    'classified',
    'review_flagged',
    'quotation_status_changed',
    'converted_to_billable',
    'legacy_quote_invoice_detached'
  )),
  from_job_type text,
  to_job_type text,
  from_workflow_kind text,
  to_workflow_kind text,
  from_intake_kind text,
  to_intake_kind text,
  from_quotation_status text,
  to_quotation_status text,
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  reason text,
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key)
);

create index if not exists idx_mechanic_job_mode_events_job
  on public.mechanic_job_mode_events(tenant_id, job_id, occurred_at desc);
create index if not exists idx_mechanic_job_mode_events_type
  on public.mechanic_job_mode_events(tenant_id, event_type, occurred_at desc);

alter table public.mechanic_job_mode_events enable row level security;

drop policy if exists mechanic_job_mode_events_select
  on public.mechanic_job_mode_events;
create policy mechanic_job_mode_events_select
  on public.mechanic_job_mode_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.mechanic_job_mode_events
  from public, anon, authenticated, service_role;
grant select on public.mechanic_job_mode_events to authenticated;

create or replace function public.prevent_mechanic_job_mode_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Mechanic job mode events are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_mechanic_job_mode_event_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_job_mode_events_immutable
  on public.mechanic_job_mode_events;
create trigger trg_mechanic_job_mode_events_immutable
  before update or delete on public.mechanic_job_mode_events
  for each row execute function public.prevent_mechanic_job_mode_event_mutation();

-- ---------------------------------------------------------------------------
-- 3. Conservative, replay-safe legacy classification
-- ---------------------------------------------------------------------------

-- Frozen immediately before this migration's first deployment window. Never
-- advance this boundary: reapplying core_schema in the future must not treat
-- newly-created operational rows as historical backfill candidates.
create or replace function public.mechanic_job_mode_backfill_eligible(
  p_created_at timestamptz
)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  select coalesce(
    p_created_at < timestamptz '2026-07-16 05:15:00+00',
    false
  );
$$;

revoke all on function public.mechanic_job_mode_backfill_eligible(timestamptz)
  from public, anon, authenticated, service_role;

comment on function public.mechanic_job_mode_backfill_eligible(timestamptz) is
  'Immutable cutoff for the 2026-07-15 mechanic-job mode backfill. Do not move forward on reapplication.';

-- First derive only what the current row graph proves. A quotation is allowed
-- to have no intake object because it can be prepared while the customer is
-- only asking for a price. A service/warranty without a bike or component is
-- deliberately left unspecified and flagged below.
update public.mechanic_jobs job
set workflow_kind = case job.job_type
      when 'quotation' then 'quotation'
      when 'warranty' then 'warranty'
      else 'service'
    end,
    intake_kind = case
      when job.job_type = 'item_service' then 'component'
      when job.subject_id is not null then 'component'
      when job.bike_id is not null
        or exists (
          select 1
          from public.mechanic_job_bikes job_bike
          where job_bike.tenant_id = job.tenant_id
            and job_bike.job_id = job.id
        ) then 'bike'
      else 'unspecified'
    end,
    mode_needs_review = false,
    mode_review_reason = null
where (
  job.workflow_kind is null
  or job.intake_kind is null
  or job.mode_needs_review is null
)
  and public.mechanic_job_mode_backfill_eligible(job.created_at);

-- Rows can be created between the frozen snapshot cutoff and the first schema
-- deployment. They still need non-NULL values before constraints are enabled,
-- but must never enter the historical event/heuristic backfills below. This is
-- a one-time, NULL-only schema bootstrap using direct facade/graph evidence;
-- after NOT NULL is installed, a future reapplication cannot match any row.
with live_bootstrap as (
  select
    job.id,
    case job.job_type
      when 'quotation' then 'quotation'
      when 'warranty' then 'warranty'
      else 'service'
    end as workflow_kind,
    case
      when job.job_type = 'item_service' then 'component'
      when job.subject_id is not null then 'component'
      when job.bike_id is not null
        or exists (
          select 1
          from public.mechanic_job_bikes job_bike
          where job_bike.tenant_id = job.tenant_id
            and job_bike.job_id = job.id
        ) then 'bike'
      else 'unspecified'
    end as intake_kind
  from public.mechanic_jobs job
  where not public.mechanic_job_mode_backfill_eligible(job.created_at)
    and (
      job.workflow_kind is null
      or job.intake_kind is null
      or job.mode_needs_review is null
    )
)
update public.mechanic_jobs job
set workflow_kind = live.workflow_kind,
    intake_kind = live.intake_kind,
    mode_needs_review = live.workflow_kind in ('service', 'warranty')
      and live.intake_kind = 'unspecified',
    mode_review_reason = case
      when live.workflow_kind in ('service', 'warranty')
        and live.intake_kind = 'unspecified'
        then 'system: falta confirmar bicicleta o componente recibido'
      else null
    end
from live_bootstrap live
where job.id = live.id;

-- A very narrow legacy quotation repair: only a service with no intake object,
-- a quote-specific phrase, and a draft invoice with zero payments, stock
-- movements, or journal entries qualifies. The invoice row is preserved,
-- cancelled as non-actionable evidence, and then detached. No accounting or
-- inventory ledger row is altered.
drop table if exists pg_temp.mechanic_job_quote_backfill_candidates;
create temporary table mechanic_job_quote_backfill_candidates
on commit drop
as
select
  job.id as job_id,
  job.tenant_id,
  job.invoice_id,
  job.job_type,
  job.workflow_kind,
  job.intake_kind,
  false as invoice_cancelled
from public.mechanic_jobs job
join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
where job.deleted_at is null
  and public.mechanic_job_mode_backfill_eligible(job.created_at)
  and job.job_type = 'service'
  and job.workflow_kind = 'service'
  and job.intake_kind = 'unspecified'
  and job.bike_id is null
  and job.subject_id is null
  and not exists (
    select 1 from public.mechanic_job_bikes job_bike
    where job_bike.tenant_id = job.tenant_id
      and job_bike.job_id = job.id
  )
  and lower(invoice.status) in ('draft', 'borrador')
  and coalesce(invoice.paid_amount, 0) = 0
  and not exists (
    select 1 from public.sales_payments payment
    where payment.tenant_id = job.tenant_id
      and payment.invoice_id = invoice.id
      and payment.deleted_at is null
  )
  and not exists (
    select 1 from public.stock_movements movement
    where movement.tenant_id = job.tenant_id
      and movement.source_document_id = invoice.id
      and movement.source_document_type = 'sales_invoice'
  )
  and not exists (
    select 1 from public.journal_entries journal
    where journal.tenant_id = job.tenant_id
      and journal.source_document_id = invoice.id
      and journal.source_document_type = 'sales_invoice'
  )
  and lower(concat_ws(' ', job.subject_notes, job.client_request, job.notes))
      ~ '(cotiz|presupuest|espera[^.]{0,40}(aprob|confirm)|inform[oó][^.]{0,30}precio)';

-- Freeze the candidate job/invoice pair while it is rechecked and detached.
-- A payment FK or invoice posting/status update must wait for this short
-- transaction, so a draft cannot become financially active between the safety
-- proof and the detach/cancel writes.
do $$
begin
  perform 1
  from public.mechanic_jobs job
  join mechanic_job_quote_backfill_candidates candidate
    on candidate.job_id = job.id
   and candidate.tenant_id = job.tenant_id
  join public.sales_invoices invoice
    on invoice.id = candidate.invoice_id
   and invoice.tenant_id = candidate.tenant_id
  for update of job, invoice;
end;
$$;

-- Cancel and revalidate the proven zero-effect invoice first. Only rows
-- returned by this guarded write may proceed to event creation and job detach.
-- If any proof changed after the preview, that candidate remains untouched and
-- will fall through to the explicit review queue below.
with cancelled as (
  update public.sales_invoices invoice
  set status = 'cancelled',
      updated_at = clock_timestamp()
  from mechanic_job_quote_backfill_candidates candidate
  where invoice.id = candidate.invoice_id
    and invoice.tenant_id = candidate.tenant_id
    and lower(invoice.status) in ('draft', 'borrador')
    and coalesce(invoice.paid_amount, 0) = 0
    and not exists (
      select 1 from public.sales_payments payment
      where payment.tenant_id = candidate.tenant_id
        and payment.invoice_id = candidate.invoice_id
        and payment.deleted_at is null
    )
    and not exists (
      select 1 from public.stock_movements movement
      where movement.tenant_id = candidate.tenant_id
        and movement.source_document_type = 'sales_invoice'
        and movement.source_document_id = candidate.invoice_id
    )
    and not exists (
      select 1 from public.journal_entries journal
      where journal.tenant_id = candidate.tenant_id
        and journal.source_document_type = 'sales_invoice'
        and journal.source_document_id = candidate.invoice_id
    )
  returning invoice.id, invoice.tenant_id
)
update mechanic_job_quote_backfill_candidates candidate
set invoice_cancelled = true
from cancelled
where cancelled.id = candidate.invoice_id
  and cancelled.tenant_id = candidate.tenant_id;

insert into public.mechanic_job_mode_events (
  tenant_id,
  job_id,
  event_type,
  from_job_type,
  to_job_type,
  from_workflow_kind,
  to_workflow_kind,
  from_intake_kind,
  to_intake_kind,
  invoice_id,
  reason,
  operation_key,
  metadata
)
select
  candidate.tenant_id,
  candidate.job_id,
  'legacy_quote_invoice_detached',
  candidate.job_type,
  'quotation',
  candidate.workflow_kind,
  'quotation',
  candidate.intake_kind,
  'unspecified',
  candidate.invoice_id,
  'Clasificación retroactiva conservadora: cotización explícita sin recepción de bicicleta o componente.',
  'mode-backfill:legacy-quote:' || candidate.job_id,
  jsonb_build_object(
    'invoice_preserved', true,
    'invoice_cancelled', true,
    'invoice_detach_guard', jsonb_build_object(
      'draft_only', true,
      'zero_payments', true,
      'zero_stock_movements', true,
      'zero_journals', true
    )
  )
from mechanic_job_quote_backfill_candidates candidate
where candidate.invoice_cancelled
on conflict (tenant_id, operation_key) do nothing;

update public.mechanic_jobs job
set job_type = 'quotation',
    workflow_kind = 'quotation',
    intake_kind = 'unspecified',
    quotation_status = coalesce(job.quotation_status, 'pending'),
    requires_approval = true,
    invoice_id = null,
    is_invoiced = false,
    is_paid = false,
    mode_needs_review = false,
    mode_review_reason = null,
    updated_at = clock_timestamp()
from mechanic_job_quote_backfill_candidates candidate
where job.id = candidate.job_id
  and job.tenant_id = candidate.tenant_id
  and candidate.invoice_cancelled;

-- Wheel/component-only work is reclassified only when the job has no bicycle
-- relationship and explicit language that the loose object was received or
-- will be collected. A mere product/service description such as "cambio de
-- neumático" is not proof that the customer left only that component.
drop table if exists pg_temp.mechanic_job_wheel_backfill_candidates;
create temporary table mechanic_job_wheel_backfill_candidates
on commit drop
as
select
  job.id as job_id,
  job.tenant_id,
  job.job_type,
  job.workflow_kind,
  job.intake_kind,
  case
    when lower(concat_ws(' ', job.subject_notes, job.client_request, job.notes))
      ~ 'rueda[[:space:]]+delantera' then 'Rueda delantera'
    when lower(concat_ws(' ', job.subject_notes, job.client_request, job.notes))
      ~ 'rueda[[:space:]]+trasera' then 'Rueda trasera'
    when lower(coalesce(job.subject_notes, '')) ~ '(neum[aá]tico|cubierta)'
      then 'Cubierta / Neumático'
    when lower(coalesce(job.subject_notes, '')) ~ 'c[aá]mara'
      then 'Cámara de neumático'
    when lower(coalesce(job.subject_notes, '')) ~ '(^|[[:space:]])(aro|llanta)([[:space:]]|$)'
      then 'Aro (Rim)'
    else 'Rueda completa'
  end as subject_name
from public.mechanic_jobs job
where job.deleted_at is null
  and public.mechanic_job_mode_backfill_eligible(job.created_at)
  and job.job_type = 'service'
  and job.workflow_kind = 'service'
  and job.intake_kind = 'unspecified'
  and job.bike_id is null
  and job.subject_id is null
  and not exists (
    select 1 from public.mechanic_job_bikes job_bike
    where job_bike.tenant_id = job.tenant_id
      and job_bike.job_id = job.id
  )
  and lower(concat_ws(' ', job.subject_notes, job.client_request, job.notes))
      !~ '(cotiz|presupuest)'
  and lower(concat_ws(' ', job.subject_notes, job.client_request, job.notes)) ~
    '(trae|trajo|dej[oóa]|dejar|entreg[oóa]|recibid[oa]|recibimos|buscar|retirar|retir[oóa])[^.]{0,60}(rueda|neum[aá]tico|cubierta|c[aá]mara|aro|llanta|componente)';

insert into public.mechanic_job_mode_events (
  tenant_id,
  job_id,
  event_type,
  from_job_type,
  to_job_type,
  from_workflow_kind,
  to_workflow_kind,
  from_intake_kind,
  to_intake_kind,
  reason,
  operation_key,
  metadata
)
select
  candidate.tenant_id,
  candidate.job_id,
  'classified',
  candidate.job_type,
  'item_service',
  candidate.workflow_kind,
  'service',
  candidate.intake_kind,
  'component',
  'Clasificación retroactiva conservadora: trabajo explícito sobre rueda o componente de rueda sin bicicleta recibida.',
  'mode-backfill:wheel-component:' || candidate.job_id,
  jsonb_build_object('subject_name', candidate.subject_name)
from mechanic_job_wheel_backfill_candidates candidate
join public.job_subjects subject
  on subject.tenant_id = candidate.tenant_id
 and lower(subject.name) = lower(candidate.subject_name)
on conflict (tenant_id, operation_key) do nothing;

update public.mechanic_jobs job
set job_type = 'item_service',
    workflow_kind = 'service',
    intake_kind = 'component',
    subject_id = subject.id,
    mode_needs_review = false,
    mode_review_reason = null,
    updated_at = clock_timestamp()
from mechanic_job_wheel_backfill_candidates candidate
join public.job_subjects subject
  on subject.tenant_id = candidate.tenant_id
 and lower(subject.name) = lower(candidate.subject_name)
where job.id = candidate.job_id
  and job.tenant_id = candidate.tenant_id;

-- Anything still missing a physical intake classification stays visible and
-- explicitly reviewable. This is the important anti-guessing boundary.
update public.mechanic_jobs job
set mode_needs_review = true,
    mode_review_reason = case
      when job.workflow_kind = 'warranty'
        then 'backfill: garantía sin bicicleta o componente verificable'
      else 'backfill: servicio sin bicicleta o componente verificable'
    end
where job.workflow_kind in ('service', 'warranty')
  and public.mechanic_job_mode_backfill_eligible(job.created_at)
  and job.intake_kind = 'unspecified'
  and not job.mode_needs_review;

insert into public.mechanic_job_mode_events (
  tenant_id,
  job_id,
  event_type,
  from_job_type,
  to_job_type,
  from_workflow_kind,
  to_workflow_kind,
  from_intake_kind,
  to_intake_kind,
  reason,
  operation_key,
  metadata
)
select
  job.tenant_id,
  job.id,
  'review_flagged',
  job.job_type,
  job.job_type,
  job.workflow_kind,
  job.workflow_kind,
  job.intake_kind,
  job.intake_kind,
  job.mode_review_reason,
  'mode-backfill:review:' || job.id,
  jsonb_build_object('legacy_job_type', job.job_type)
from public.mechanic_jobs job
where job.mode_needs_review
  and public.mechanic_job_mode_backfill_eligible(job.created_at)
on conflict (tenant_id, operation_key) do nothing;

-- Every pre-existing row gets one immutable baseline classification event when
-- it did not already receive a more specific repair/review event.
insert into public.mechanic_job_mode_events (
  tenant_id,
  job_id,
  event_type,
  to_job_type,
  to_workflow_kind,
  to_intake_kind,
  to_quotation_status,
  invoice_id,
  reason,
  operation_key,
  metadata
)
select
  job.tenant_id,
  job.id,
  'classified',
  job.job_type,
  job.workflow_kind,
  job.intake_kind,
  job.quotation_status,
  job.invoice_id,
  'Clasificación inicial derivada del grafo histórico existente.',
  'mode-backfill:baseline:' || job.id,
  jsonb_build_object(
    'mode_needs_review', job.mode_needs_review,
    'has_primary_bike', job.bike_id is not null,
    'has_subject', job.subject_id is not null
  )
from public.mechanic_jobs job
where public.mechanic_job_mode_backfill_eligible(job.created_at)
  and not exists (
  select 1
  from public.mechanic_job_mode_events event
  where event.tenant_id = job.tenant_id
    and event.job_id = job.id
    and event.operation_key like 'mode-backfill:%'
)
on conflict (tenant_id, operation_key) do nothing;

alter table public.mechanic_jobs
  alter column workflow_kind set default 'service',
  alter column workflow_kind set not null,
  alter column intake_kind set default 'unspecified',
  alter column intake_kind set not null,
  alter column mode_needs_review set default false,
  alter column mode_needs_review set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'mechanic_jobs_workflow_kind_check'
      and conrelid = 'public.mechanic_jobs'::regclass
  ) then
    alter table public.mechanic_jobs
      add constraint mechanic_jobs_workflow_kind_check
      check (workflow_kind in ('service', 'quotation', 'warranty'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'mechanic_jobs_intake_kind_check'
      and conrelid = 'public.mechanic_jobs'::regclass
  ) then
    alter table public.mechanic_jobs
      add constraint mechanic_jobs_intake_kind_check
      check (intake_kind in ('bike', 'component', 'unspecified'));
  end if;
end;
$$;

create index if not exists idx_mechanic_jobs_workflow_intake
  on public.mechanic_jobs(tenant_id, workflow_kind, intake_kind)
  where deleted_at is null;
create index if not exists idx_mechanic_jobs_mode_review
  on public.mechanic_jobs(tenant_id, mode_needs_review, created_at desc)
  where deleted_at is null and mode_needs_review;

-- ---------------------------------------------------------------------------
-- 4. Compatibility normalization, automatic audit, and invoice guard
-- ---------------------------------------------------------------------------

create or replace function public.normalize_mechanic_job_mode_axes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_axes_changed boolean := false;
  v_job_type_changed boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_axes_changed := new.workflow_kind is distinct from old.workflow_kind
      or new.intake_kind is distinct from old.intake_kind;
    v_job_type_changed := new.job_type is distinct from old.job_type;
  end if;

  if tg_op = 'INSERT' then
    if new.job_type in ('quotation', 'warranty', 'item_service') then
      new.workflow_kind := case new.job_type
        when 'quotation' then 'quotation'
        when 'warranty' then 'warranty'
        else 'service'
      end;
      if new.job_type = 'item_service' then
        new.intake_kind := 'component';
      elsif new.intake_kind is null or new.intake_kind = 'unspecified' then
        new.intake_kind := case
          when new.subject_id is not null then 'component'
          when new.bike_id is not null then 'bike'
          else 'unspecified'
        end;
      end if;
    else
      new.workflow_kind := coalesce(new.workflow_kind, 'service');
      -- Columns added by this migration have defaults, so an omitted legacy
      -- intake_kind arrives here as "unspecified" rather than NULL. Prefer the
      -- concrete graph supplied by that same INSERT before flagging review.
      new.intake_kind := case
        when new.intake_kind is null or new.intake_kind = 'unspecified' then case
          when new.subject_id is not null then 'component'
          when new.bike_id is not null then 'bike'
          else 'unspecified'
        end
        else new.intake_kind
      end;
      new.job_type := case
        when new.workflow_kind = 'quotation' then 'quotation'
        when new.workflow_kind = 'warranty' then 'warranty'
        when new.intake_kind = 'component' then 'item_service'
        else 'service'
      end;
    end if;
  elsif v_axes_changed then
    new.job_type := case
      when new.workflow_kind = 'quotation' then 'quotation'
      when new.workflow_kind = 'warranty' then 'warranty'
      when new.intake_kind = 'component' then 'item_service'
      else 'service'
    end;
  elsif v_job_type_changed then
    new.workflow_kind := case new.job_type
      when 'quotation' then 'quotation'
      when 'warranty' then 'warranty'
      else 'service'
    end;
    new.intake_kind := case
      when new.job_type = 'item_service' then 'component'
      when new.subject_id is not null then 'component'
      when new.bike_id is not null then 'bike'
      else new.intake_kind
    end;
  elsif old.bike_id is null
     and new.bike_id is not null
     and new.workflow_kind in ('service', 'warranty')
     and new.intake_kind = 'unspecified' then
    -- Older clients update bike_id without sending the new mode axes or the
    -- unchanged job_type. Treat that concrete graph change exactly like a new
    -- legacy service insert so the row does not remain falsely unresolved.
    new.intake_kind := 'bike';
    new.job_type := case
      when new.workflow_kind = 'warranty' then 'warranty'
      else 'service'
    end;
    new.mode_needs_review := false;
    new.mode_review_reason := null;
  end if;

  if new.workflow_kind in ('service', 'warranty')
     and new.intake_kind = 'unspecified' then
    new.mode_needs_review := true;
    new.mode_review_reason := coalesce(
      nullif(btrim(new.mode_review_reason), ''),
      'system: falta confirmar bicicleta o componente recibido'
    );
  elsif new.intake_kind = 'component'
     and new.subject_id is null
     and nullif(btrim(coalesce(new.subject_notes, '')), '') is null then
    new.mode_needs_review := true;
    new.mode_review_reason := coalesce(
      nullif(btrim(new.mode_review_reason), ''),
      'system: falta identificar el componente recibido'
    );
  elsif new.mode_needs_review
     and coalesce(new.mode_review_reason, '') like 'system:%' then
    new.mode_needs_review := false;
    new.mode_review_reason := null;
  end if;

  if new.workflow_kind = 'quotation' then
    new.quotation_status := coalesce(new.quotation_status, 'pending');
    new.requires_approval := true;
  end if;

  return new;
end;
$$;

revoke all on function public.normalize_mechanic_job_mode_axes()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_normalize_mode_axes
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_normalize_mode_axes
  before insert or update of
    job_type,
    workflow_kind,
    intake_kind,
    bike_id,
    subject_id,
    subject_notes,
    mode_needs_review,
    mode_review_reason
  on public.mechanic_jobs
  for each row execute function public.normalize_mechanic_job_mode_axes();

create or replace function public.guard_mechanic_job_quotation_invoice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.invoice_id is not null
     and (new.workflow_kind = 'quotation' or new.job_type = 'quotation') then
    raise exception 'Una cotización no puede tener factura. Apruébala y conviértela primero.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_mechanic_job_quotation_invoice()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_guard_quotation_invoice
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_quotation_invoice
  before insert or update of invoice_id, workflow_kind, job_type
  on public.mechanic_jobs
  for each row execute function public.guard_mechanic_job_quotation_invoice();

create or replace function public.audit_direct_mechanic_job_mode_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('app.mechanic_job_mode_rpc', true) = 'true' then
    return new;
  end if;

  if old.job_type is distinct from new.job_type
     or old.workflow_kind is distinct from new.workflow_kind
     or old.intake_kind is distinct from new.intake_kind
     or old.quotation_status is distinct from new.quotation_status then
    insert into public.mechanic_job_mode_events (
      tenant_id,
      job_id,
      event_type,
      from_job_type,
      to_job_type,
      from_workflow_kind,
      to_workflow_kind,
      from_intake_kind,
      to_intake_kind,
      from_quotation_status,
      to_quotation_status,
      invoice_id,
      reason,
      actor_id,
      operation_key,
      metadata
    ) values (
      new.tenant_id,
      new.id,
      case
        when old.quotation_status is distinct from new.quotation_status
          and old.job_type is not distinct from new.job_type
          and old.workflow_kind is not distinct from new.workflow_kind
          and old.intake_kind is not distinct from new.intake_kind
          then 'quotation_status_changed'
        else 'classified'
      end,
      old.job_type,
      new.job_type,
      old.workflow_kind,
      new.workflow_kind,
      old.intake_kind,
      new.intake_kind,
      old.quotation_status,
      new.quotation_status,
      new.invoice_id,
      'Cambio registrado por una ruta cliente anterior al comando atómico.',
      auth.uid(),
      'legacy-direct:' || new.id || ':' || txid_current() || ':' ||
        md5(concat_ws('|', clock_timestamp()::text, random()::text)),
      jsonb_build_object('compatibility_path', true)
    );
  end if;
  return new;
end;
$$;

revoke all on function public.audit_direct_mechanic_job_mode_transition()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_audit_direct_mode_transition
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_audit_direct_mode_transition
  after update of job_type, workflow_kind, intake_kind, quotation_status
  on public.mechanic_jobs
  for each row execute function public.audit_direct_mechanic_job_mode_transition();

-- ---------------------------------------------------------------------------
-- 5. Canonical read model and authenticated commands
-- ---------------------------------------------------------------------------

drop view if exists public.mechanic_job_mode_view;
create view public.mechanic_job_mode_view
with (security_invoker = on)
as
select
  job.id as job_id,
  job.tenant_id,
  job.job_number,
  job.customer_id,
  job.job_type,
  job.workflow_kind,
  job.intake_kind,
  job.mode_needs_review,
  job.mode_review_reason,
  job.bike_id,
  job.subject_id,
  job.subject_notes,
  job.invoice_id,
  job.quotation_status,
  job.quotation_valid_until,
  case
    when job.workflow_kind <> 'quotation' then null
    when job.quotation_status = 'pending'
      and job.quotation_valid_until is not null
      and job.quotation_valid_until < clock_timestamp() then 'expired'
    else coalesce(job.quotation_status, 'pending')
  end as effective_quotation_status,
  job.converted_at,
  job.created_at,
  job.updated_at
from public.mechanic_jobs job
where job.deleted_at is null;

grant select on public.mechanic_job_mode_view to authenticated;

comment on view public.mechanic_job_mode_view is
  'Canonical job-mode projection. Expiry is derived from quotation_valid_until without a clock-driven mutable status job.';

-- Preserve the mature invoice builder behind a private implementation name.
-- The historical public RPC is recreated below as a guarded compatibility
-- wrapper, so older clients gain the same invariants as the canonical command
-- without duplicating the invoice construction logic.
do $$
begin
  if to_regprocedure(
    'public.create_invoice_from_mechanic_job_internal(uuid)'
  ) is null then
    if to_regprocedure('public.create_invoice_from_mechanic_job(uuid)') is null then
      raise exception 'Missing workshop invoice builder required by job-mode migration';
    end if;
    alter function public.create_invoice_from_mechanic_job(uuid)
      rename to create_invoice_from_mechanic_job_internal;
  end if;
end;
$$;

revoke all on function public.create_invoice_from_mechanic_job_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_billable_invoice_from_mechanic_job(
  p_job_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_invoice_id uuid;
begin
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Trabajo no encontrado.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  if v_job.workflow_kind = 'quotation' or v_job.job_type = 'quotation' then
    raise exception 'Una cotización no genera factura; primero debe aprobarse y convertirse.'
      using errcode = '23514';
  end if;

  -- Existing historical links may still be synchronized even if their legacy
  -- intake classification awaits review. This command never creates a second
  -- invoice in that branch, preserving normal operations while preventing new
  -- unresolved ownership.
  if v_job.invoice_id is not null then
    return public.create_invoice_from_mechanic_job_internal(v_job.id);
  end if;

  if v_job.mode_needs_review then
    raise exception 'Confirma si se recibió una bicicleta o solo un componente antes de facturar.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'bike'
     and v_job.bike_id is null
     and not exists (
       select 1 from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = v_job.tenant_id
         and job_bike.job_id = v_job.id
     ) then
    raise exception 'El servicio de bicicleta necesita una bicicleta asociada.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'component'
     and v_job.subject_id is null
     and nullif(btrim(coalesce(v_job.subject_notes, '')), '') is null then
    raise exception 'El servicio de componente necesita identificar el componente recibido.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'unspecified' then
    raise exception 'Confirma si se recibió una bicicleta o solo un componente antes de facturar.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind = 'warranty'
     and coalesce(v_job.warranty_outcome, 'pending') = 'pending' then
    raise exception 'La garantía debe resolverse antes de generar su documento interno o factura.'
      using errcode = '23514';
  end if;

  v_invoice_id := public.create_invoice_from_mechanic_job_internal(v_job.id);

  -- Covered warranties are internal zero-customer-balance documents. The
  -- normalizer runs on invoice UPDATE because the job link does not exist at
  -- invoice INSERT time; perform one canonical sync after the initial link so
  -- a newly created covered invoice cannot retain billable totals.
  if v_invoice_id is not null
     and v_job.workflow_kind = 'warranty'
     and v_job.warranty_outcome = 'covered' then
    perform public.sync_job_to_invoice(v_job.id);
  end if;

  return v_invoice_id;
end;
$$;

revoke all on function public.create_billable_invoice_from_mechanic_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_billable_invoice_from_mechanic_job(uuid)
  to authenticated;

create or replace function public.create_invoice_from_mechanic_job(
  p_job_id uuid
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.create_billable_invoice_from_mechanic_job(p_job_id);
$$;

revoke all on function public.create_invoice_from_mechanic_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_invoice_from_mechanic_job(uuid)
  to authenticated;

create or replace function public.transition_mechanic_job_quotation(
  p_job_id uuid,
  p_status text,
  p_reason text default null,
  p_operation_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_request jsonb := jsonb_build_object(
    'status', v_status,
    'reason', v_reason
  );
begin
  if v_status not in ('pending', 'approved', 'rejected', 'expired') then
    raise exception 'Estado de cotización inválido: %', p_status;
  end if;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cotización no encontrada.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select * into v_event
  from public.mechanic_job_mode_events
  where tenant_id = v_job.tenant_id
    and operation_key = v_operation_key;
  if found then
    if v_event.job_id <> v_job.id
       or v_event.event_type <> 'quotation_status_changed'
       or v_event.metadata->'request' is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra transición de trabajo.'
        using errcode = '23505';
    end if;
    return jsonb_build_object(
      'job_id', v_event.job_id,
      'job_type', v_event.to_job_type,
      'workflow_kind', v_event.to_workflow_kind,
      'intake_kind', v_event.to_intake_kind,
      'quotation_status', v_event.to_quotation_status,
      'event_id', v_event.id
    );
  end if;

  if v_job.workflow_kind <> 'quotation' or v_job.job_type <> 'quotation' then
    raise exception 'El trabajo no es una cotización.' using errcode = '23514';
  end if;

  if v_status in ('rejected', 'pending')
     and v_job.quotation_status is distinct from v_status
     and v_reason is null then
    raise exception 'Indica el motivo del cambio de estado de la cotización.'
      using errcode = '23514';
  end if;

  if v_status = 'approved'
     and v_job.quotation_valid_until is not null
     and v_job.quotation_valid_until < clock_timestamp()
     and v_reason is null then
    raise exception 'La cotización venció; registra el motivo para aprobarla fuera de plazo.'
      using errcode = '23514';
  end if;

  if v_status = 'expired'
     and (v_job.quotation_valid_until is null
       or v_job.quotation_valid_until >= clock_timestamp())
     and v_reason is null then
    raise exception 'Solo puede marcarse como vencida anticipadamente con un motivo.'
      using errcode = '23514';
  end if;

  if v_job.quotation_status is not distinct from v_status then
    return jsonb_build_object(
      'job_id', v_job.id,
      'job_type', v_job.job_type,
      'workflow_kind', v_job.workflow_kind,
      'intake_kind', v_job.intake_kind,
      'quotation_status', v_job.quotation_status,
      'event_id', null
    );
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs
  set quotation_status = v_status,
      approved_by_customer = case
        when v_status = 'approved' then true
        when v_status in ('pending', 'rejected', 'expired') then false
        else approved_by_customer
      end,
      approved_at = case
        when v_status = 'approved' then clock_timestamp()
        when v_status in ('pending', 'rejected', 'expired') then null
        else approved_at
      end,
      updated_at = clock_timestamp()
  where id = v_job.id;

  insert into public.mechanic_job_mode_events (
    tenant_id,
    job_id,
    event_type,
    from_job_type,
    to_job_type,
    from_workflow_kind,
    to_workflow_kind,
    from_intake_kind,
    to_intake_kind,
    from_quotation_status,
    to_quotation_status,
    invoice_id,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    'quotation_status_changed',
    v_job.job_type,
    v_job.job_type,
    v_job.workflow_kind,
    v_job.workflow_kind,
    v_job.intake_kind,
    v_job.intake_kind,
    v_job.quotation_status,
    v_status,
    v_job.invoice_id,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'quotation_valid_until', v_job.quotation_valid_until,
      'approved_after_expiry',
        v_status = 'approved'
        and v_job.quotation_valid_until is not null
        and v_job.quotation_valid_until < clock_timestamp(),
      'request', v_request
    )
  ) returning * into v_event;
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  return jsonb_build_object(
    'job_id', v_job.id,
    'job_type', 'quotation',
    'workflow_kind', 'quotation',
    'intake_kind', v_job.intake_kind,
    'quotation_status', v_status,
    'event_id', v_event.id
  );
exception
  when others then
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.transition_mechanic_job_quotation(
  uuid, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.transition_mechanic_job_quotation(
  uuid, text, text, uuid
) to authenticated;

create or replace function public.convert_mechanic_job_to_billable(
  p_job_id uuid,
  p_target_job_type text,
  p_reason text default null,
  p_create_invoice boolean default true,
  p_bike_id uuid default null,
  p_subject_id uuid default null,
  p_operation_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_target_job_type text := lower(btrim(coalesce(p_target_job_type, '')));
  v_target_intake_kind text;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_bike public.bikes%rowtype;
  v_subject public.job_subjects%rowtype;
  v_job_bike_id uuid;
  v_invoice_id uuid;
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_latest_quotation_event public.mechanic_job_mode_events%rowtype;
  v_request jsonb := jsonb_build_object(
    'target_job_type', v_target_job_type,
    'reason', v_reason,
    'create_invoice', coalesce(p_create_invoice, true),
    'bike_id', p_bike_id,
    'subject_id', p_subject_id
  );
begin
  if v_target_job_type not in ('service', 'item_service') then
    raise exception 'El destino debe ser servicio de bicicleta o servicio de componente.';
  end if;
  v_target_intake_kind := case
    when v_target_job_type = 'item_service' then 'component'
    else 'bike'
  end;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cotización no encontrada.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select * into v_event
  from public.mechanic_job_mode_events
  where tenant_id = v_job.tenant_id
    and operation_key = v_operation_key;
  if found then
    if v_event.job_id <> v_job.id
       or v_event.event_type <> 'converted_to_billable'
       or v_event.metadata->'request' is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra transición de trabajo.'
        using errcode = '23505';
    end if;
    return jsonb_build_object(
      'job_id', v_event.job_id,
      'job_type', v_event.to_job_type,
      'workflow_kind', v_event.to_workflow_kind,
      'intake_kind', v_event.to_intake_kind,
      'quotation_status', v_event.to_quotation_status,
      'invoice_id', v_event.invoice_id,
      'event_id', v_event.id
    );
  end if;

  -- A retry can arrive with a fresh client operation key after the original
  -- response was lost. Once the row already matches the requested converted
  -- target, return the committed result instead of creating a second invoice
  -- or event. The immutable conversion event remains the durable receipt.
  if v_job.workflow_kind = 'service'
     and v_job.job_type = v_target_job_type
     and v_job.intake_kind = v_target_intake_kind
     and v_job.converted_at is not null then
    select * into v_event
    from public.mechanic_job_mode_events
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and event_type = 'converted_to_billable'
    order by occurred_at desc, id desc
    limit 1;

    if not found
       or v_event.metadata->'request'->>'target_job_type'
            is distinct from v_target_job_type
       or coalesce(
            (v_event.metadata->'request'->>'create_invoice')::boolean,
            true
          ) is distinct from coalesce(p_create_invoice, true)
       or v_event.metadata->'request'->>'bike_id'
            is distinct from p_bike_id::text
       or v_event.metadata->'request'->>'subject_id'
            is distinct from p_subject_id::text then
      raise exception 'La cotización ya fue convertida con una solicitud diferente.'
        using errcode = '23514';
    end if;

    return jsonb_build_object(
      'job_id', v_job.id,
      'job_type', v_job.job_type,
      'workflow_kind', v_job.workflow_kind,
      'intake_kind', v_job.intake_kind,
      'quotation_status', v_job.quotation_status,
      'invoice_id', v_job.invoice_id,
      'event_id', v_event.id
    );
  end if;

  if v_job.workflow_kind <> 'quotation' or v_job.job_type <> 'quotation' then
    raise exception 'Solo una cotización puede convertirse con este comando.'
      using errcode = '23514';
  end if;
  if coalesce(v_job.quotation_status, 'pending') <> 'approved' then
    raise exception 'La cotización debe estar aprobada antes de convertirse.'
      using errcode = '23514';
  end if;
  if v_job.quotation_valid_until is not null
     and v_job.quotation_valid_until < clock_timestamp() then
    select * into v_latest_quotation_event
    from public.mechanic_job_mode_events
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and event_type = 'quotation_status_changed'
    order by occurred_at desc, id desc
    limit 1;

    if not found
       or v_latest_quotation_event.to_quotation_status <> 'approved'
       or not (
         v_latest_quotation_event.occurred_at <= v_job.quotation_valid_until
         or (
           coalesce(
             (v_latest_quotation_event.metadata->>'approved_after_expiry')::boolean,
             false
           )
           and nullif(btrim(coalesce(v_latest_quotation_event.reason, '')), '')
             is not null
         )
       ) then
      raise exception 'La cotización vencida necesita una aprobación tardía auditada con motivo antes de convertirse.'
        using errcode = '23514';
    end if;
  end if;

  if v_target_job_type = 'service' then
    if p_subject_id is not null then
      raise exception 'Un servicio de bicicleta no acepta un componente suelto como objeto principal.'
        using errcode = '23514';
    end if;

    if p_bike_id is not null then
      select * into v_bike
      from public.bikes
      where id = p_bike_id
        and tenant_id = v_job.tenant_id
        and customer_id = v_job.customer_id;
    elsif v_job.bike_id is not null then
      select * into v_bike
      from public.bikes
      where id = v_job.bike_id
        and tenant_id = v_job.tenant_id
        and customer_id = v_job.customer_id;
    else
      select bike.* into v_bike
      from public.mechanic_job_bikes job_bike
      join public.bikes bike
        on bike.id = job_bike.bike_id
       and bike.tenant_id = job_bike.tenant_id
      where job_bike.tenant_id = v_job.tenant_id
        and job_bike.job_id = v_job.id
        and bike.customer_id = v_job.customer_id
      order by job_bike.order_index, job_bike.created_at, job_bike.id
      limit 1;
    end if;

    if v_bike.id is null then
      raise exception 'Selecciona una bicicleta del mismo cliente antes de convertir la cotización.'
        using errcode = '23514';
    end if;

    insert into public.mechanic_job_bikes (
      tenant_id, job_id, bike_id, order_index, work_requested
    ) values (
      v_job.tenant_id, v_job.id, v_bike.id, 0, v_job.client_request
    )
    on conflict (job_id, bike_id) do update
      set updated_at = excluded.updated_at
    returning id into v_job_bike_id;

    update public.mechanic_job_items
    set job_bike_id = v_job_bike_id,
        updated_at = clock_timestamp()
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and job_bike_id is null;
  else
    if p_bike_id is not null then
      raise exception 'Un servicio de componente no recibe la bicicleta completa.'
        using errcode = '23514';
    end if;

    if p_subject_id is not null then
      select * into v_subject
      from public.job_subjects
      where id = p_subject_id
        and tenant_id = v_job.tenant_id
        and is_active;
    elsif v_job.subject_id is not null then
      select * into v_subject
      from public.job_subjects
      where id = v_job.subject_id
        and tenant_id = v_job.tenant_id;
    end if;

    if v_subject.id is null
       and nullif(btrim(coalesce(v_job.subject_notes, '')), '') is null then
      raise exception 'Selecciona o describe el componente recibido antes de convertir la cotización.'
        using errcode = '23514';
    end if;
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs
  set job_type = v_target_job_type,
      workflow_kind = 'service',
      intake_kind = v_target_intake_kind,
      bike_id = case when v_target_job_type = 'service' then v_bike.id else null end,
      subject_id = case
        when v_target_job_type = 'item_service' then coalesce(v_subject.id, subject_id)
        else null
      end,
      quotation_status = null,
      is_warranty_job = false,
      warranty_outcome = null,
      converted_at = clock_timestamp(),
      approved_by_customer = true,
      approved_at = coalesce(approved_at, clock_timestamp()),
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where id = v_job.id;

  if coalesce(p_create_invoice, true) then
    v_invoice_id := public.create_billable_invoice_from_mechanic_job(v_job.id);
  else
    v_invoice_id := null;
  end if;

  insert into public.mechanic_job_mode_events (
    tenant_id,
    job_id,
    event_type,
    from_job_type,
    to_job_type,
    from_workflow_kind,
    to_workflow_kind,
    from_intake_kind,
    to_intake_kind,
    from_quotation_status,
    to_quotation_status,
    invoice_id,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    'converted_to_billable',
    v_job.job_type,
    v_target_job_type,
    v_job.workflow_kind,
    'service',
    v_job.intake_kind,
    v_target_intake_kind,
    v_job.quotation_status,
    null,
    v_invoice_id,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'quotation_snapshot', jsonb_build_object(
        'valid_until', v_job.quotation_valid_until,
        'total_cost', v_job.total_cost,
        'discount_amount', v_job.discount_amount,
        'tax_treatment', v_job.tax_treatment
      ),
      'bike_id', case when v_bike.id is null then null else v_bike.id end,
      'subject_id', case when v_subject.id is null then null else v_subject.id end,
      'invoice_created', coalesce(p_create_invoice, true),
      'request', v_request
    )
  ) returning * into v_event;
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  return jsonb_build_object(
    'job_id', v_job.id,
    'job_type', v_target_job_type,
    'workflow_kind', 'service',
    'intake_kind', v_target_intake_kind,
    'quotation_status', null,
    'invoice_id', v_invoice_id,
    'event_id', v_event.id
  );
exception
  when others then
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.convert_mechanic_job_to_billable(
  uuid, text, text, boolean, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.convert_mechanic_job_to_billable(
  uuid, text, text, boolean, uuid, uuid, uuid
) to authenticated;

comment on table public.mechanic_job_mode_events is
  'Immutable classification, quotation approval, and conversion history for the orthogonal workshop mode model.';
comment on function public.create_billable_invoice_from_mechanic_job(uuid) is
  'Canonical guarded invoice command for billable workshop modes. Quotations and new unresolved intake ownership are rejected.';
comment on function public.create_invoice_from_mechanic_job(uuid) is
  'Backward-compatible guarded alias for create_billable_invoice_from_mechanic_job; retained for older workshop clients.';
comment on function public.create_invoice_from_mechanic_job_internal(uuid) is
  'Private invoice construction implementation. Invoke through the guarded workshop invoice commands.';
comment on function public.transition_mechanic_job_quotation(uuid, text, text, uuid) is
  'Audited/idempotent quotation status command. Expired approvals require an explicit reason.';
comment on function public.convert_mechanic_job_to_billable(uuid, text, text, boolean, uuid, uuid, uuid) is
  'Atomically converts an approved quotation in place to a bicycle or component service, optionally linking its intake object and creating the invoice.';

commit;
