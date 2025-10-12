-- ============================================================================
-- Performance Optimization for Journal Entries
-- ============================================================================
-- This migration adds additional indexes and optimizations to improve
-- journal entries loading performance.
--
-- Problem: Loading journal entries was taking 10-15 seconds
-- Solution: Add composite indexes and optimize queries
--
-- Run this in Supabase SQL Editor
-- ============================================================================

-- 1. Add composite index for date + status (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_journal_entries_date_status 
ON public.journal_entries (date DESC, status);

-- 2. Add index on source module/reference for filtering
CREATE INDEX IF NOT EXISTS idx_journal_entries_source 
ON public.journal_entries (source_module, source_reference);

-- 3. Add composite index on entry_id for journal_lines (for efficient joins)
-- This helps when loading lines for multiple entries at once
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry_id_account 
ON public.journal_lines (entry_id, account_code);

-- 4. Add index on type for filtering
CREATE INDEX IF NOT EXISTS idx_journal_entries_type 
ON public.journal_entries (type);

-- 5. Add composite index for common search patterns
CREATE INDEX IF NOT EXISTS idx_journal_entries_date_type 
ON public.journal_entries (date DESC, type);

-- 6. Analyze tables to update statistics for query planner
ANALYZE public.journal_entries;
ANALYZE public.journal_lines;

-- ============================================================================
-- Expected Results:
-- - Journal entries loading should be < 1 second for 100-500 entries
-- - Filtering by type/date should be instant
-- - Loading lines for specific entries should be very fast
-- ============================================================================

-- You can verify indexes with:
-- SELECT indexname, indexdef FROM pg_indexes 
-- WHERE tablename IN ('journal_entries', 'journal_lines');
