-- ============================================================
-- MULTI-BIKE SUPPORT FOR MECHANIC JOBS (PEGAS)
-- ============================================================
-- Deploy: Run this in Supabase SQL Editor
-- Date: December 13, 2025
-- 
-- This adds support for multiple bicycles per job/pega.
-- Each bike has its own: diagnosis, work items, notes, costs
-- ============================================================

-- ============================================================
-- TABLE: mechanic_job_bikes
-- Links bikes to jobs with per-bike details
-- ============================================================
create table if not exists mechanic_job_bikes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  job_id uuid not null references mechanic_jobs(id) on delete cascade,
  bike_id uuid not null references bikes(id) on delete cascade,
  order_index integer not null default 0,
  
  -- Per-bike work details (these fields exist on mechanic_jobs but for single bike)
  diagnosis text,
  work_requested text,        -- Solicitud del cliente (per bike)
  work_performed text,        -- Lo que se hizo
  technician_notes text,      -- Notas del técnico
  
  -- Per-bike cost tracking (calculated from items)
  parts_cost numeric(12,2) not null default 0,
  labor_cost numeric(12,2) not null default 0,
  subtotal numeric(12,2) not null default 0,
  
  -- Per-bike flags
  is_warranty_work boolean not null default false,
  requires_approval boolean not null default false,
  approved_by_customer boolean not null default false,
  approved_at timestamp with time zone,
  
  -- Images for this specific bike work
  image_urls text[] not null default array[]::text[],
  
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Add indexes
create index if not exists idx_mechanic_job_bikes_tenant on mechanic_job_bikes(tenant_id);
create index if not exists idx_mechanic_job_bikes_job on mechanic_job_bikes(job_id);
create index if not exists idx_mechanic_job_bikes_bike on mechanic_job_bikes(bike_id);

-- Unique constraint: each bike can only appear once per job
alter table mechanic_job_bikes drop constraint if exists mechanic_job_bikes_job_bike_unique;
alter table mechanic_job_bikes add constraint mechanic_job_bikes_job_bike_unique unique (job_id, bike_id);

-- Enable RLS
alter table mechanic_job_bikes enable row level security;

-- RLS Policies
drop policy if exists "mechanic_job_bikes_select" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_insert" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_update" on mechanic_job_bikes;
drop policy if exists "mechanic_job_bikes_delete" on mechanic_job_bikes;

create policy "mechanic_job_bikes_select" on mechanic_job_bikes
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_insert" on mechanic_job_bikes
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_update" on mechanic_job_bikes
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "mechanic_job_bikes_delete" on mechanic_job_bikes
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- ============================================================
-- UPDATE mechanic_job_items: Add job_bike_id column
-- Links items to specific bikes within a job
-- ============================================================
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_items' and column_name = 'job_bike_id'
  ) then
    alter table mechanic_job_items 
      add column job_bike_id uuid references mechanic_job_bikes(id) on delete cascade;
    raise notice '✅ Added job_bike_id column to mechanic_job_items';
  end if;
  
  -- Add index for faster lookups
  if not exists (
    select 1 from pg_indexes 
    where tablename = 'mechanic_job_items' and indexname = 'idx_mechanic_job_items_job_bike'
  ) then
    create index idx_mechanic_job_items_job_bike on mechanic_job_items(job_bike_id) 
      where job_bike_id is not null;
    raise notice '✅ Added index for job_bike_id';
  end if;
end $$;

-- ============================================================
-- UPDATE mechanic_job_tasks: Add job_bike_id column
-- Links tasks to specific bikes within a job
-- ============================================================
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'job_bike_id'
  ) then
    alter table mechanic_job_tasks 
      add column job_bike_id uuid references mechanic_job_bikes(id) on delete cascade;
    raise notice '✅ Added job_bike_id column to mechanic_job_tasks';
  end if;
end $$;

-- ============================================================
-- FUNCTION: Recalculate per-bike costs
-- Called when items change
-- ============================================================
create or replace function public.recalculate_job_bike_costs()
returns trigger
security definer
language plpgsql
as $$
declare
  v_job_bike_id uuid;
  v_parts_cost numeric(12,2);
  v_labor_cost numeric(12,2);
begin
  -- Get the job_bike_id from the changed item
  if TG_OP = 'DELETE' then
    v_job_bike_id := OLD.job_bike_id;
  else
    v_job_bike_id := NEW.job_bike_id;
  end if;
  
  -- Skip if no job_bike_id (legacy single-bike jobs)
  if v_job_bike_id is null then
    return coalesce(NEW, OLD);
  end if;
  
  -- Calculate costs for this bike
  select 
    coalesce(sum(case when item_type = 'product' then total_price else 0 end), 0),
    coalesce(sum(case when item_type = 'service' then total_price else 0 end), 0)
  into v_parts_cost, v_labor_cost
  from mechanic_job_items
  where job_bike_id = v_job_bike_id;
  
  -- Update the job_bike record
  update mechanic_job_bikes
  set 
    parts_cost = v_parts_cost,
    labor_cost = v_labor_cost,
    subtotal = v_parts_cost + v_labor_cost,
    updated_at = now()
  where id = v_job_bike_id;
  
  return coalesce(NEW, OLD);
end;
$$;

-- Trigger to recalculate bike costs when items change
drop trigger if exists trg_mechanic_job_items_bike_costs on mechanic_job_items;
create trigger trg_mechanic_job_items_bike_costs
  after insert or update or delete on mechanic_job_items
  for each row
  execute function public.recalculate_job_bike_costs();

-- ============================================================
-- Verify deployment
-- ============================================================
do $$
begin
  raise notice '';
  raise notice '✅ Multi-bike support deployed successfully!';
  raise notice '   - mechanic_job_bikes table created';
  raise notice '   - mechanic_job_items.job_bike_id column added';
  raise notice '   - mechanic_job_tasks.job_bike_id column added';
  raise notice '   - RLS policies created';
  raise notice '   - Cost recalculation trigger created';
end $$;
