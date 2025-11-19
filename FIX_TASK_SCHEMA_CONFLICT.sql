-- =================================================================
-- FIX: Remove Old Legacy Task System Conflicts (Nov 18, 2025)
-- =================================================================
-- This script removes the old legacy task triggers that conflict
-- with the new smart tasks system. Run this in Supabase SQL Editor.
-- =================================================================

-- 1. Drop old auto-create triggers
drop trigger if exists trg_auto_create_task_for_item on mechanic_job_items cascade;
drop trigger if exists trg_auto_create_task_for_labor on mechanic_job_labor cascade;
drop trigger if exists trg_sync_tasks_with_job_status on mechanic_jobs cascade;

-- 2. Drop old trigger functions
drop function if exists public.auto_create_task_for_job_item() cascade;
drop function if exists public.auto_create_task_for_job_labor() cascade;
drop function if exists public.sync_tasks_with_job_status() cascade;
drop function if exists public.get_job_task_summary(uuid) cascade;

-- 3. Verify mechanic_job_tasks table has correct schema
-- Check if table has new columns (task_name, is_completed, parent_item_id)
do $$
begin
  -- Add task_name if missing (from old title column)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'task_name'
  ) then
    if exists (
      select 1 from information_schema.columns 
      where table_name = 'mechanic_job_tasks' and column_name = 'title'
    ) then
      -- Migrate title → task_name
      alter table mechanic_job_tasks rename column title to task_name;
      raise notice '✅ Renamed title → task_name';
    else
      -- Add new column
      alter table mechanic_job_tasks add column task_name text;
      update mechanic_job_tasks set task_name = 'Task' where task_name is null;
      alter table mechanic_job_tasks alter column task_name set not null;
      raise notice '✅ Added task_name column';
    end if;
  end if;

  -- Rename parent columns if needed
  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'job_item_id'
  ) then
    alter table mechanic_job_tasks rename column job_item_id to parent_item_id;
    raise notice '✅ Renamed job_item_id → parent_item_id';
  end if;

  if exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'job_labor_id'
  ) then
    alter table mechanic_job_tasks rename column job_labor_id to parent_labor_id;
    raise notice '✅ Renamed job_labor_id → parent_labor_id';
  end if;

  -- Add is_completed if missing (from old status column)
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_job_tasks' and column_name = 'is_completed'
  ) then
    if exists (
      select 1 from information_schema.columns 
      where table_name = 'mechanic_job_tasks' and column_name = 'status'
    ) then
      -- Migrate status → is_completed
      alter table mechanic_job_tasks add column is_completed boolean;
      update mechanic_job_tasks 
        set is_completed = (status = 'completed') 
        where is_completed is null;
      alter table mechanic_job_tasks alter column is_completed set not null;
      alter table mechanic_job_tasks alter column is_completed set default false;
      
      -- Drop old status column
      alter table mechanic_job_tasks drop column if exists status cascade;
      raise notice '✅ Migrated status → is_completed';
    else
      -- Add new column
      alter table mechanic_job_tasks add column is_completed boolean not null default false;
      raise notice '✅ Added is_completed column';
    end if;
  end if;

  -- Drop old columns that don't exist in new schema
  alter table mechanic_job_tasks drop column if exists task_type cascade;
  alter table mechanic_job_tasks drop column if exists priority cascade;
  alter table mechanic_job_tasks drop column if exists assigned_to cascade;
  alter table mechanic_job_tasks drop column if exists assigned_technician_name cascade;
  alter table mechanic_job_tasks drop column if exists estimated_duration_minutes cascade;
  alter table mechanic_job_tasks drop column if exists actual_duration_minutes cascade;
  alter table mechanic_job_tasks drop column if exists started_at cascade;
  alter table mechanic_job_tasks drop column if exists is_auto_generated cascade;
  alter table mechanic_job_tasks drop column if exists completed_by cascade;
  alter table mechanic_job_tasks drop column if exists completed_by_name cascade;
  alter table mechanic_job_tasks drop column if exists completed_by_user_id cascade;
  alter table mechanic_job_tasks drop column if exists notes cascade;

  raise notice '✅ Cleaned up old columns';
end $$;

-- 4. Ensure new smart task columns exist
do $$
begin
  -- Add new smart task columns
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parent_item_id') then
    alter table mechanic_job_tasks add column parent_item_id uuid references mechanic_job_items(id) on delete cascade;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parent_labor_id') then
    alter table mechanic_job_tasks add column parent_labor_id uuid references mechanic_job_labor(id) on delete cascade;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_adhoc') then
    alter table mechanic_job_tasks add column is_adhoc boolean not null default false;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'adhoc_price') then
    alter table mechanic_job_tasks add column adhoc_price numeric(12,2);
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'adhoc_item_id') then
    alter table mechanic_job_tasks add column adhoc_item_id uuid references mechanic_job_items(id) on delete set null;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'is_standalone') then
    alter table mechanic_job_tasks add column is_standalone boolean not null default false;
  end if;
  
  if not exists (select 1 from information_schema.columns where table_name = 'mechanic_job_tasks' and column_name = 'parsed_from_description') then
    alter table mechanic_job_tasks add column parsed_from_description boolean not null default false;
  end if;

  raise notice '✅ Ensured all smart task columns exist';
end $$;

-- 5. Drop and recreate indexes with correct column names
drop index if exists idx_mechanic_job_tasks_item;
drop index if exists idx_mechanic_job_tasks_labor;
drop index if exists idx_mechanic_job_tasks_status;
drop index if exists idx_mechanic_job_tasks_assigned;

create index if not exists idx_mechanic_job_tasks_parent_item 
  on mechanic_job_tasks(parent_item_id) where parent_item_id is not null;
  
create index if not exists idx_mechanic_job_tasks_parent_labor 
  on mechanic_job_tasks(parent_labor_id) where parent_labor_id is not null;
  
create index if not exists idx_mechanic_job_tasks_completed 
  on mechanic_job_tasks(job_id, is_completed);

-- 6. Verification
do $$
declare
  v_column_count integer;
  v_trigger_count integer;
begin
  -- Check columns
  select count(*) into v_column_count
  from information_schema.columns
  where table_name = 'mechanic_job_tasks' 
    and column_name in ('task_name', 'is_completed', 'parent_item_id', 'parent_labor_id', 'is_adhoc');
  
  if v_column_count = 5 then
    raise notice '✅ All required columns exist (task_name, is_completed, parent_item_id, parent_labor_id, is_adhoc)';
  else
    raise warning '⚠️ Missing some required columns (found % of 5)', v_column_count;
  end if;
  
  -- Check old triggers are gone
  select count(*) into v_trigger_count
  from information_schema.triggers
  where trigger_name in ('trg_auto_create_task_for_item', 'trg_auto_create_task_for_labor', 'trg_sync_tasks_with_job_status');
  
  if v_trigger_count = 0 then
    raise notice '✅ Old triggers removed';
  else
    raise warning '⚠️ Some old triggers still exist (% remaining)', v_trigger_count;
  end if;
end $$;

-- =================================================================
-- ✅ DEPLOYMENT COMPLETE
-- =================================================================
-- Now the new smart task system should work without conflicts.
-- Test by adding a product to a pega - it should NOT create old-style tasks.
-- The auto_parse_item_description trigger will create new-style tasks instead.
-- =================================================================
