-- ============================================================================
-- Add diagnostic deadline columns to mechanic_jobs
-- ============================================================================
-- This migration adds columns for tracking diagnostic deadlines and timestamps.
-- The existing 'deadline' column is used for delivery deadline.
-- ============================================================================

-- STEP 1: Add diagnostic_deadline column (target date for diagnostic)
-- ============================================================================
ALTER TABLE mechanic_jobs ADD COLUMN IF NOT EXISTS diagnostic_deadline TIMESTAMP WITH TIME ZONE;

-- STEP 2: Add diagnostic_sent_at column (actual timestamp when diagnostic was sent)
-- ============================================================================
ALTER TABLE mechanic_jobs ADD COLUMN IF NOT EXISTS diagnostic_sent_at TIMESTAMP WITH TIME ZONE;

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
-- Run this in Supabase SQL Editor to deploy the changes.
-- After running:
--   - diagnostic_deadline: tracks when the diagnostic should be completed
--   - diagnostic_sent_at: tracks when the diagnostic was actually sent
--   - deadline (existing): tracks the delivery deadline
-- ============================================================================
