alter table public.smart_purchase_list
  add column if not exists linked_job_id uuid references public.mechanic_jobs(id) on delete set null,
  add column if not exists linked_job_number text;

create index if not exists idx_smart_purchase_list_linked_job
  on public.smart_purchase_list(linked_job_id);