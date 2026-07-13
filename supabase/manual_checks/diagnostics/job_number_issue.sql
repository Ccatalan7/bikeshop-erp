-- Diagnose job_number duplicate key issue
-- Run this in Supabase SQL Editor

-- 1. Check if trigger exists
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as enabled
FROM pg_trigger
WHERE tgname LIKE '%job_number%'
ORDER BY tgname;

-- 2. Check for duplicate or empty job_numbers
SELECT 
  job_number,
  COUNT(*) as count,
  array_agg(id) as job_ids
FROM mechanic_jobs
GROUP BY job_number
HAVING COUNT(*) > 1 OR job_number IS NULL OR job_number = '';

-- 3. Show all job_numbers to see pattern
SELECT 
  id,
  job_number,
  customer_id,
  bike_id,
  status,
  created_at
FROM mechanic_jobs
ORDER BY created_at DESC
LIMIT 20;

-- 4. Check sequence for job_number generation
SELECT 
  sequencename,
  last_value,
  increment_by
FROM pg_sequences
WHERE sequencename LIKE '%job%';

-- 5. Check trigger function definition
SELECT 
  proname as function_name,
  prosrc as source_code
FROM pg_proc
WHERE proname LIKE '%job_number%';

-- ==========================================
-- POTENTIAL FIXES (run if needed):
-- ==========================================

-- FIX 1: Delete records with NULL or empty job_number
-- DELETE FROM mechanic_jobs WHERE job_number IS NULL OR job_number = '';

-- FIX 2: Update duplicate job_numbers with unique values
-- WITH duplicates AS (
--   SELECT id, job_number, 
--          ROW_NUMBER() OVER (PARTITION BY job_number ORDER BY created_at) as rn
--   FROM mechanic_jobs
--   WHERE job_number IS NOT NULL
-- )
-- UPDATE mechanic_jobs m
-- SET job_number = 'PG-' || LPAD((nextval('mechanic_jobs_job_number_seq'))::text, 5, '0')
-- FROM duplicates d
-- WHERE m.id = d.id AND d.rn > 1;

-- FIX 3: Ensure trigger is enabled
-- ALTER TABLE mechanic_jobs ENABLE TRIGGER trg_generate_mechanic_job_number;
