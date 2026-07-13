-- ============================================================================
-- EMERGENCY: Nuclear drop of ALL task-related triggers and functions
-- ============================================================================
-- Run this IMMEDIATELY in Supabase SQL Editor, then hot reload app

-- 1. Check what triggers exist RIGHT NOW
select 
  event_object_table as table_name,
  trigger_name,
  action_statement
from information_schema.triggers
where event_object_table in ('mechanic_job_items', 'mechanic_jobs')
  and trigger_name like '%task%'
order by event_object_table, trigger_name;

-- 2. FORCE DROP ALL task triggers (even if not found)
drop trigger if exists trg_auto_create_task_for_item on mechanic_job_items cascade;
drop trigger if exists trg_sync_tasks_with_job_status on mechanic_jobs cascade;
drop trigger if exists auto_create_task_for_item on mechanic_job_items cascade;
drop trigger if exists sync_tasks_with_job_status on mechanic_jobs cascade;

-- 3. Drop functions with FORCE (cascade removes all dependencies)
drop function if exists public.auto_create_task_for_job_item() cascade;
drop function if exists public.sync_tasks_with_job_status() cascade;
drop function if exists public.get_job_task_summary(uuid) cascade;

-- 4. Verify triggers are GONE
select 
  event_object_table as table_name,
  trigger_name,
  action_statement
from information_schema.triggers
where event_object_table in ('mechanic_job_items', 'mechanic_jobs')
  and trigger_name like '%task%'
order by event_object_table, trigger_name;

-- Should return ZERO rows if successful

-- 5. Verify new triggers exist
select 
  trigger_name,
  event_object_table,
  action_timing,
  event_manipulation
from information_schema.triggers
where trigger_name in ('trg_auto_parse_item_description')
order by trigger_name;

-- Should show the NEW smart task triggers

-- ============================================================================
-- AFTER RUNNING THIS: Hot reload Flutter app with 'r' command
-- ============================================================================
