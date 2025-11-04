-- Check what FK constraint ACTUALLY exists in the live database
SELECT 
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'mechanic_jobs'::regclass
  AND conname LIKE '%invoice%';
