-- Query ACTUAL triggers on mechanic_jobs table RIGHT NOW
SELECT 
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'mechanic_jobs'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- Also check mechanic_job_items
SELECT 
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'mechanic_job_items'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- And mechanic_job_labor
SELECT 
  t.tgname AS trigger_name,
  pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'mechanic_job_labor'
  AND NOT t.tgisinternal
ORDER BY t.tgname;
