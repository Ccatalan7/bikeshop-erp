-- Quick check: Verify RLS policies exist for website_pages
-- Run this in Supabase SQL Editor

SELECT 
  policyname,
  cmd,
  qual::text as using_expression
FROM pg_policies
WHERE tablename = 'website_pages'
ORDER BY cmd;
-- Expected: 4 rows (SELECT, INSERT, UPDATE, DELETE)
