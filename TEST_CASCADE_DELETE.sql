-- TEST CASCADE DELETE CHAIN
-- This script tests what happens when you delete a service with tasks
-- Simplified: Use existing job to avoid trigger complexity

-- Deprecated (Nov 19, 2025)
-- mechanic_job_labor table no longer exists; cascade testing now lives in
-- the mechanic_job_items-only workflow.

DO $$
BEGIN
  RAISE NOTICE 'TEST_CASCADE_DELETE.sql is obsolete: mechanic_job_labor no longer exists.';
END $$;
