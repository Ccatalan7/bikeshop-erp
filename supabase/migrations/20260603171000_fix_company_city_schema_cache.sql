-- Fix missing city column in the live companies table and reload PostgREST's
-- schema cache so company profile saves can see the column immediately.
-- Deployment status: DEPLOYED on 2026-06-03 to linked Supabase project xzdvtzdqjeyqxnkqprtf.
-- Deployment verification: city_columns=1; pg_notify('pgrst','reload schema') returned successfully.

alter table public.companies
  add column if not exists city text;

select pg_notify('pgrst', 'reload schema');
