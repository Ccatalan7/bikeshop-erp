-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Live verification: migration history registered; column is nullable
-- numeric(8,2) with mechanic_jobs_estimated_duration_hours_valid enforced.
-- Minimal forward-compatible slice extracted from the blocked workshop
-- accounting migration. This file changes no existing job values.
begin;

alter table public.mechanic_jobs
  add column if not exists estimated_duration_hours numeric(8,2);

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_estimated_duration_hours_valid;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_estimated_duration_hours_valid
  check (
    estimated_duration_hours is null
    or estimated_duration_hours between 0 and 10000
  );

comment on column public.mechanic_jobs.estimated_duration_hours is
  'Operational estimate entered in the workshop form. It does not post payroll, revenue, tax, accounting, or inventory.';

commit;
