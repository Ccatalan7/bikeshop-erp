-- ============================================================================
-- Check RLS Policies on journal_entries and journal_lines
-- ============================================================================

-- Check if RLS is enabled
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('journal_entries', 'journal_lines', 'sales_payments')
ORDER BY tablename;

-- Check RLS policies on journal_entries
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('journal_entries', 'journal_lines')
ORDER BY tablename, policyname;
