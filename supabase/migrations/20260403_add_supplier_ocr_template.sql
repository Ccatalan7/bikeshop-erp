alter table public.suppliers
  add column if not exists ocr_template jsonb not null default '{}'::jsonb;