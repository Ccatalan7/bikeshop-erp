alter table public.products
  add column if not exists image_url_optimized text;

alter table public.products
  add column if not exists image_fingerprint jsonb;