-- Preserve the authenticated registrant of every new workshop job and copy
-- its tenant-safe display name into the durable notification payload.
--
-- Existing jobs and notifications are deliberately not inferred or backfilled:
-- neither source retained authoritative actor evidence before this migration.
-- Recovery: the additive nullable column may remain in place; disable the
-- created-by trigger and restore the previous notification function if event
-- attribution must be paused. No job, notification, or audit row is deleted.
--
-- Deployment status: pending production deployment and read-back.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table public.mechanic_jobs
  add column if not exists created_by uuid;

alter table public.mechanic_jobs
  alter column created_by set default auth.uid();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.mechanic_jobs'::regclass
      and conname = 'mechanic_jobs_created_by_fkey'
  ) then
    alter table public.mechanic_jobs
      add constraint mechanic_jobs_created_by_fkey
      foreign key (created_by)
      references auth.users(id)
      on delete set null
      not valid;
  end if;
end;
$$;

alter table public.mechanic_jobs
  validate constraint mechanic_jobs_created_by_fkey;

comment on column public.mechanic_jobs.created_by is
  'Authenticated ERP user who registered the job; null only when authoritative legacy or service evidence is unavailable.';

create or replace function public.set_mechanic_job_created_by()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  -- An authenticated caller cannot claim another user's identity. Owner-run
  -- maintenance with no JWT may preserve an explicitly supplied historical
  -- actor, but ordinary client inserts always use the request identity.
  if auth.uid() is not null then
    NEW.created_by := auth.uid();
  end if;

  return NEW;
end;
$$;

revoke all on function public.set_mechanic_job_created_by()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_created_by
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_created_by
  before insert on public.mechanic_jobs
  for each row execute function public.set_mechanic_job_created_by();

create or replace function public.create_mechanic_job_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_customer_name text;
  v_bike_label text;
  v_client_request text;
  v_recorded_by_name text;
  v_body text;
begin
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  select customer.name
    into v_customer_name
  from public.customers customer
  where customer.id = NEW.customer_id
    and customer.tenant_id = NEW.tenant_id;

  select nullif(trim(
           coalesce(bike.brand, '') || ' ' || coalesce(bike.model, '')
           || case
                when nullif(trim(coalesce(bike.color, '')), '') is not null
                  then ' · ' || bike.color
                else ''
              end
         ), '')
    into v_bike_label
  from public.bikes bike
  where bike.id = NEW.bike_id
    and bike.tenant_id = NEW.tenant_id;

  v_client_request := nullif(
    left(coalesce(NEW.client_request, ''), 300),
    ''
  );
  v_recorded_by_name := public.erp_actor_display_name(
    coalesce(NEW.created_by, auth.uid()),
    NEW.tenant_id
  );

  v_body := coalesce(nullif(NEW.job_number, ''), 'Trabajo')
    || ' · '
    || coalesce(nullif(v_customer_name, ''), 'Cliente');

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    NEW.tenant_id,
    'mechanic_job_created',
    'Nuevo trabajo',
    v_body,
    '/taller/pegas?job=' || NEW.id::text,
    'mechanic_job',
    NEW.id,
    'info',
    jsonb_build_object(
      'job_id', NEW.id,
      'job_number', NEW.job_number,
      'customer_id', NEW.customer_id,
      'customer_name', v_customer_name,
      'bike_id', NEW.bike_id,
      'bike_label', v_bike_label,
      'client_request', v_client_request,
      'recorded_by_name', v_recorded_by_name,
      'priority', NEW.priority,
      'status', NEW.status
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return NEW;
end;
$$;

revoke all on function public.create_mechanic_job_erp_notification()
  from public, anon, authenticated, service_role;

commit;
