-- ============================================================
-- FORCE CLEANUP: Remove ALL triggers from mechanic_job_tasks
-- ============================================================
-- HISTORICAL RECOVERY EVIDENCE. core_schema.sql is never deployed. Do not run
-- this file without a newly reviewed incident-specific forward migration.
-- ============================================================

-- Drop every single trigger on mechanic_job_tasks (no exceptions)
-- ============================================================
-- FORCE CLEANUP: Remove ALL triggers from task-related tables
-- ============================================================
-- HISTORICAL RECOVERY EVIDENCE. Inspect live triggers first; any authorized
-- cleanup belongs to a standalone migration with verification and a stamp.
-- ============================================================

-- Drop every single trigger on mechanic_job_tasks (no exceptions)
do $$
declare
  r record;
begin
  raise notice '=== Cleaning up mechanic_job_tasks triggers ===';
  
  for r in (
    select tgname as trigger_name
    from pg_trigger t
    join pg_class c on t.tgrelid = c.oid
    where c.relname = 'mechanic_job_tasks'
      and not t.tgisinternal
  ) loop
    execute format('drop trigger if exists %I on mechanic_job_tasks cascade', r.trigger_name);
    raise notice 'Dropped trigger: %', r.trigger_name;
  end loop;
  
  raise notice '=== Cleaning up mechanic_jobs triggers ===';
  
  for r in (
    select tgname as trigger_name
    from pg_trigger t
    join pg_class c on t.tgrelid = c.oid
    where c.relname = 'mechanic_jobs'
      and not t.tgisinternal
  ) loop
    execute format('drop trigger if exists %I on mechanic_jobs cascade', r.trigger_name);
    raise notice 'Dropped trigger: %', r.trigger_name;
  end loop;
  
  raise notice '=== Cleanup complete ===';
end $$;

-- Verify all triggers are gone
SELECT 
  tgname as trigger_name,
  pg_get_triggerdef(t.oid) as trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'mechanic_job_tasks'
  AND not t.tgisinternal;
-- Expected: 0 rows

-- Show what triggers exist on related tables (for reference)
SELECT 
  c.relname as table_name,
  tgname as trigger_name
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname IN ('mechanic_job_items', 'mechanic_jobs')
  AND not t.tgisinternal
ORDER BY c.relname, tgname;
