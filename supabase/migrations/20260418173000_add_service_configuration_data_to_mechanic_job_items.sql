alter table public.mechanic_job_items
  add column if not exists service_configuration_data jsonb;