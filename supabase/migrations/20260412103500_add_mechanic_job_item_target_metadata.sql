alter table public.mechanic_job_items
  add column if not exists system_key text,
  add column if not exists component_slot_key text,
  add column if not exists location_key text not null default 'none',
  add column if not exists intervention_type text,
  add column if not exists creates_lifecycle boolean not null default false;

create index if not exists idx_mechanic_job_items_system_location
  on public.mechanic_job_items(system_key, location_key)
  where system_key is not null;
