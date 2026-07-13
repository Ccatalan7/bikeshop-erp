-- ============================================================
-- DEPLOY: Drop mechanic_jobs status CHECK constraint
-- 
-- Purpose: Allow flexible job statuses from job_statuses table
-- Previously: Only allowed 8 hardcoded statuses (PENDIENTE, etc.)
-- Now: Any status from job_statuses table is valid
--
-- Run in Supabase SQL Editor
-- ============================================================

-- Find the constraint name first (will likely be "mechanic_jobs_status_check")
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE conrelid = 'mechanic_jobs'::regclass
AND contype = 'c'
AND conname LIKE '%status%';

-- Drop the check constraint
ALTER TABLE mechanic_jobs DROP CONSTRAINT IF EXISTS mechanic_jobs_status_check;

-- Verify it's gone
SELECT conname, pg_get_constraintdef(c.oid)
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE conrelid = 'mechanic_jobs'::regclass
AND contype = 'c';

-- Done! Custom statuses from job_statuses table will now work.
