-- ============================================================================
-- Add status_updated_at timestamp to mechanic_jobs
-- ============================================================================
-- This migration adds a timestamp to track when the job status was last changed.
-- This allows the UI to display "last updated" information on status badges.
-- ============================================================================

-- STEP 1: Add status_updated_at column
-- ============================================================================
ALTER TABLE mechanic_jobs ADD COLUMN IF NOT EXISTS status_updated_at TIMESTAMP WITH TIME ZONE;

-- STEP 2: Create trigger to auto-update status_updated_at when status_id changes
-- ============================================================================
CREATE OR REPLACE FUNCTION update_job_status_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  -- Only update timestamp if status_id actually changed
  IF OLD.status_id IS DISTINCT FROM NEW.status_id THEN
    NEW.status_updated_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_job_status_timestamp ON mechanic_jobs;
CREATE TRIGGER trg_job_status_timestamp
  BEFORE UPDATE ON mechanic_jobs
  FOR EACH ROW
  EXECUTE FUNCTION update_job_status_timestamp();

-- STEP 3: Backfill existing jobs
-- ============================================================================
-- Set status_updated_at to updated_at for existing jobs that don't have it set
UPDATE mechanic_jobs 
SET status_updated_at = COALESCE(updated_at, created_at, NOW()) 
WHERE status_updated_at IS NULL;

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
-- Run this in Supabase SQL Editor to deploy the changes.
-- After running: the status_updated_at column will be available and
-- automatically updated whenever a job's status changes.
-- ============================================================================
