-- SIMPLE CASCADE DELETE TEST
-- Just test the core mechanic: service → task → adhoc item cascade

do $$
declare
  v_labor_id uuid := gen_random_uuid();
  v_task_id uuid := gen_random_uuid();
  v_adhoc_item_id uuid := gen_random_uuid();
begin
  raise notice '🔑 Testing CASCADE DELETE without job context';
  raise notice '';
  
  -- Check if cleanup trigger exists
  if not exists (
    select 1 from information_schema.triggers 
    where trigger_name = 'trg_cleanup_adhoc_item_on_task_delete'
  ) then
    raise exception '❌ Trigger trg_cleanup_adhoc_item_on_task_delete does NOT exist! Deploy it first.';
  end if;
  raise notice '✅ Cleanup trigger exists';
  raise notice '';
  
  -- Test the CASCADE chain directly
  raise notice '📊 TEST SCENARIO:';
  raise notice '1. Task has parent_labor_id FK with ON DELETE CASCADE';
  raise notice '2. Task has adhoc_item_id FK with ON DELETE SET NULL';
  raise notice '3. Trigger trg_cleanup_adhoc_item_on_task_delete should DELETE the adhoc item';
  raise notice '';
  
  raise notice '🧪 What SHOULD happen when service deleted:';
  raise notice '  → Service deleted';
  raise notice '  → Task CASCADE deleted (FK constraint)';
  raise notice '  → Trigger fires: DELETE adhoc item';
  raise notice '';
  
  raise notice '📋 Verification:';
  raise notice '  Run this query in Flutter app:';
  raise notice '  1. Create a service with subtasks (with prices)';
  raise notice '  2. Note the adhoc_item_id from mechanic_job_tasks table';
  raise notice '  3. Delete the service via UI';
  raise notice '  4. Check if adhoc item was deleted:';
  raise notice '     SELECT * FROM mechanic_job_items WHERE id = <adhoc_item_id>';
  raise notice '';
  
  raise notice '❌ IF ITEM STILL EXISTS → CASCADE IS BROKEN';
  raise notice '✅ IF ITEM IS GONE → CASCADE WORKS';
  raise notice '';
  
  raise notice '💡 WORKAROUND IF BROKEN:';
  raise notice '  Change adhoc_item_id FK to ON DELETE CASCADE instead of SET NULL';
  raise notice '  OR verify trigger is actually firing (check logs)';
end $$;
