-- Migration: Add Bike Brands & Models System
-- Date: 2025-11-09
-- Description: Creates bike_brands and bike_models tables, updates bikes table with FKs

-- ============================================================================
-- BIKE BRANDS TABLE
-- ============================================================================
create table if not exists bike_brands (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  logo_url text,
  country text,
  website text,
  description text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

create index if not exists idx_bike_brands_tenant on bike_brands(tenant_id);
create index if not exists idx_bike_brands_name on bike_brands(lower(name));
create index if not exists idx_bike_brands_is_active on bike_brands(is_active);

alter table bike_brands enable row level security;

drop policy if exists "bike_brands_select" on bike_brands;
drop policy if exists "bike_brands_insert" on bike_brands;
drop policy if exists "bike_brands_update" on bike_brands;
drop policy if exists "bike_brands_delete" on bike_brands;

create policy "bike_brands_select" on bike_brands
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_brands_insert" on bike_brands
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_brands_update" on bike_brands
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_brands_delete" on bike_brands
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger for updated_at
do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'bike_brands'
     and t.tgname = 'trg_bike_brands_updated_at'
  ) then
    create trigger trg_bike_brands_updated_at
      before update on bike_brands
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- ============================================================================
-- BIKE MODELS TABLE
-- ============================================================================
create table if not exists bike_models (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  brand_id uuid not null references bike_brands(id) on delete cascade,
  name text not null,
  year integer,
  description text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, brand_id, name)
);

create index if not exists idx_bike_models_tenant on bike_models(tenant_id);
create index if not exists idx_bike_models_brand on bike_models(brand_id);
create index if not exists idx_bike_models_name on bike_models(lower(name));
create index if not exists idx_bike_models_is_active on bike_models(is_active);

alter table bike_models enable row level security;

drop policy if exists "bike_models_select" on bike_models;
drop policy if exists "bike_models_insert" on bike_models;
drop policy if exists "bike_models_update" on bike_models;
drop policy if exists "bike_models_delete" on bike_models;

create policy "bike_models_select" on bike_models
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_models_insert" on bike_models
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_models_update" on bike_models
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_models_delete" on bike_models
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Trigger for updated_at
do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = 'bike_models'
     and t.tgname = 'trg_bike_models_updated_at'
  ) then
    create trigger trg_bike_models_updated_at
      before update on bike_models
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- ============================================================================
-- UPDATE BIKES TABLE WITH FOREIGN KEYS
-- ============================================================================
do $$
begin
  -- Add brand_id foreign key
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'brand_id') then
    alter table bikes add column brand_id uuid references bike_brands(id) on delete set null;
  end if;
  
  -- Add model_id foreign key
  if not exists (select 1 from information_schema.columns where table_name = 'bikes' and column_name = 'model_id') then
    alter table bikes add column model_id uuid references bike_models(id) on delete set null;
  end if;
end $$;

-- Add indexes for bikes foreign keys
create index if not exists idx_bikes_brand_id on bikes(brand_id);
create index if not exists idx_bikes_model_id on bikes(model_id);
