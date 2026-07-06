-- Keep mechanic_jobs.delivered_at aligned with the current delivered status.
-- A job can be moved back from ENTREGADO to FINALIZADO/other states; in that
-- case delivered_at must not keep making the active table treat it as delivered.

create or replace function public.normalize_mechanic_job_lifecycle_timestamps()
returns trigger
language plpgsql
as $$
begin
  if NEW.status = 'ENTREGADO' then
    NEW.delivered_at := coalesce(NEW.delivered_at, now());
    NEW.completed_at := coalesce(NEW.completed_at, NEW.delivered_at, now());
  else
    NEW.delivered_at := null;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_mechanic_jobs_lifecycle_timestamp_guard
  on public.mechanic_jobs;

create trigger trg_mechanic_jobs_lifecycle_timestamp_guard
  before insert or update of status, status_id, completed_at, delivered_at
  on public.mechanic_jobs
  for each row
  execute function public.normalize_mechanic_job_lifecycle_timestamps();

update public.mechanic_jobs
set delivered_at = null
where delivered_at is not null
  and coalesce(status, '') <> 'ENTREGADO';
