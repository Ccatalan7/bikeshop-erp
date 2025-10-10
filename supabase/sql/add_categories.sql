-- Creates inventory categories table and links products.
-- Run this after core_schema.sql in existing environments.

create extension if not exists "pgcrypto";

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  name text not null,
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, name)
);

-- Ensure products reference categories when available.
alter table public.products
  add column if not exists category_id uuid references public.categories(id) on delete set null,
  add column if not exists is_active boolean not null default true,
  add column if not exists additional_images text[] not null default '{}'::text[],
  add column if not exists updated_at timestamptz;

-- Backfill updated_at for existing rows.
update public.products
   set updated_at = coalesce(updated_at, created_at);

alter table public.categories enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'categories'
       and policyname = 'Categories readable by authenticated'
  ) then
    create policy "Categories readable by authenticated"
      on public.categories
      for select
      using (auth.role() = 'authenticated');
  end if;
end;
$$;

notify pgrst, 'reload schema';
