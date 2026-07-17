-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-16 (America/Los_Angeles)
-- Prevent deleting a linked workshop invoice from Sales from erasing the
-- authoritative mechanic job. Job-originated deletion keeps its existing
-- guarded path and can delete an eligible draft invoice after the job row is
-- removed; posted or paid invoices remain protected by their own guards.
begin;

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_invoice_id_fkey;

alter table public.mechanic_jobs
  add constraint mechanic_jobs_invoice_id_fkey
  foreign key (invoice_id)
  references public.sales_invoices(id)
  on delete restrict;

comment on constraint mechanic_jobs_invoice_id_fkey on public.mechanic_jobs is
  'Canonical job-to-invoice ownership. A linked invoice cannot be deleted from Sales while its mechanic job exists.';

drop trigger if exists trg_delete_invoice_cascade_pega
  on public.sales_invoices;

create or replace function public.guard_final_service_budget_bike_graph()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_locked boolean := false;
begin
  -- The canonical conversion intentionally performs an idempotent
  -- ON CONFLICT update of updated_at on the already-received bicycle. Permit
  -- that no-op while rejecting any business-data change to the frozen graph.
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'updated_at')
       is not distinct from (to_jsonb(old) - 'updated_at') then
    return new;
  end if;

  if tg_op = 'INSERT' and exists (
    select 1
    from public.mechanic_job_bikes existing
    where existing.job_id = new.job_id
      and existing.bike_id = new.bike_id
  ) then
    return new;
  end if;

  if tg_op = 'DELETE' then
    select exists (
      select 1
      from public.mechanic_jobs job
      where job.id = old.job_id
        and job.tenant_id = old.tenant_id
        and job.workflow_kind = 'quotation'
        and job.intake_kind = 'bike'
        and coalesce(job.quotation_status, 'pending') <> 'pending'
    ) into v_locked;
  elsif tg_op = 'INSERT' then
    select exists (
      select 1
      from public.mechanic_jobs job
      where job.id = new.job_id
        and job.tenant_id = new.tenant_id
        and job.workflow_kind = 'quotation'
        and job.intake_kind = 'bike'
        and coalesce(job.quotation_status, 'pending') <> 'pending'
    ) into v_locked;
  else
    select exists (
      select 1
      from public.mechanic_jobs job
      where (
          (job.id = old.job_id and job.tenant_id = old.tenant_id)
          or (job.id = new.job_id and job.tenant_id = new.tenant_id)
        )
        and job.workflow_kind = 'quotation'
        and job.intake_kind = 'bike'
        and coalesce(job.quotation_status, 'pending') <> 'pending'
    ) into v_locked;
  end if;

  if v_locked then
    raise exception 'Las bicicletas y fichas de un presupuesto decidido son inmutables; reabre la propuesta mediante el comando auditado.'
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.guard_final_service_budget_bike_graph()
  from public, anon, authenticated;

drop trigger if exists trg_mechanic_job_bikes_guard_final_service_budget
  on public.mechanic_job_bikes;
create trigger trg_mechanic_job_bikes_guard_final_service_budget
  before insert or update or delete on public.mechanic_job_bikes
  for each row
  execute function public.guard_final_service_budget_bike_graph();

comment on function public.guard_final_service_budget_bike_graph() is
  'Freezes received bicycles, ficha and diagnosis after a service-budget decision while allowing the conversion RPC idempotent upsert.';

commit;
