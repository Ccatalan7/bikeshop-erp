-- Verification: Check if website_pages table exists in Supabase database
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql

-- 1. Check if table exists
SELECT 
  table_name,
  table_schema
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name = 'website_pages';
-- Expected: 1 row if exists, 0 rows if doesn't exist

-- 2. Check if RLS is enabled
SELECT 
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public' 
  AND tablename = 'website_pages';
-- Expected: rowsecurity = true

-- 3. Check RLS policies
SELECT 
  policyname,
  cmd,
  qual::text as using_expression,
  with_check::text as check_expression
FROM pg_policies
WHERE tablename = 'website_pages'
ORDER BY policyname;
-- Expected: 4 policies (SELECT, INSERT, UPDATE, DELETE)

-- 4. Check if table has data
SELECT 
  COUNT(*) as total_pages,
  COUNT(DISTINCT tenant_id) as unique_tenants
FROM website_pages;
-- Expected: May be 0 rows initially

-- 5. Verify tenant_id column exists
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'website_pages'
ORDER BY ordinal_position;
-- Expected: All columns including tenant_id
