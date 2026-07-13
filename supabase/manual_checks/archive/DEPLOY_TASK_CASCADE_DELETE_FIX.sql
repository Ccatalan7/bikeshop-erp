-- ============================================================================
-- DEPLOYMENT: Fix Task Cascade Delete to Clean Up Ad-Hoc Items
-- ============================================================================
-- Date: November 18, 2025
-- Purpose: Ensure that when a task is deleted, its linked ad-hoc item is also deleted
--
-- Problem: When deleting a product/service from pega, subtasks are deleted (cascade)
--          but ad-hoc items created by those subtasks remain orphaned in database
--
-- Solution: Add AFTER DELETE trigger on mechanic_job_tasks to clean up adhoc_item_id
--
-- Impact:
--   ✅ Deleting product → deletes subtasks → deletes ad-hoc items
--   ✅ Deleting task → deletes ad-hoc item (if exists)
--   ✅ Deleting pega → deletes all products → deletes all tasks → deletes all ad-hoc items
--   ✅ Proper cascade cleanup throughout the entire hierarchy
-- ============================================================================

-- Function: Cleanup ad-hoc item when task is deleted
create or replace function public.cleanup_adhoc_item_on_task_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- If task had an ad-hoc item linked, delete it
  if OLD.adhoc_item_id is not null then
    delete from mechanic_job_items where id = OLD.adhoc_item_id;
  end if;
  
  return OLD;
end;
$$;

-- Trigger: Execute cleanup on task deletion
drop trigger if exists trg_cleanup_adhoc_item_on_task_delete on mechanic_job_tasks cascade;
create trigger trg_cleanup_adhoc_item_on_task_delete
  after delete on mechanic_job_tasks
  for each row execute procedure public.cleanup_adhoc_item_on_task_delete();

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- After deploying, verify the trigger exists:
--
-- SELECT trigger_name, event_manipulation, event_object_table
-- FROM information_schema.triggers
-- WHERE trigger_name = 'trg_cleanup_adhoc_item_on_task_delete';
--
-- Should return:
-- trigger_name                           | event_manipulation | event_object_table
-- trg_cleanup_adhoc_item_on_task_delete | DELETE             | mechanic_job_tasks
-- ============================================================================

-- ✅ DEPLOYMENT COMPLETE
-- 
-- Now the full cascade works:
-- 1. Delete product from pega → CASCADE deletes tasks (parent_item_id)
-- 2. Delete task → TRIGGER deletes ad-hoc item (adhoc_item_id)
-- 3. Result: Clean deletion with no orphaned data
-- ============================================================================
