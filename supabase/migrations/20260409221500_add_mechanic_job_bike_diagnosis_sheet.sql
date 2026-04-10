alter table public.mechanic_job_bikes
  add column if not exists diagnosis_sheet_key text,
  add column if not exists diagnosis_sheet_data jsonb not null default '{}'::jsonb,
  add column if not exists diagnosis_sheet_updated_at timestamp with time zone;