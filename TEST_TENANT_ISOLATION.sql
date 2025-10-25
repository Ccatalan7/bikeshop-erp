-- ============================================================================
-- COMPREHENSIVE TENANT ISOLATION DIAGNOSTIC TEST
-- ============================================================================
-- Run this in Supabase SQL Editor while logged in as different users
-- Expected: All tests should show ONLY data for the current user's tenant
-- ============================================================================

-- ============================================================================
-- TEST 1: Verify ALL tables have tenant_id column
-- ============================================================================
-- Expected: 0 rows (all business tables should have tenant_id)
-- ============================================================================

SELECT 
  schemaname,
  tablename,
  'MISSING tenant_id' as issue
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename NOT IN (
    'tenants',
    'schema_migrations',
    '_prisma_migrations'
  )
  AND tablename NOT LIKE 'pg_%'
  AND tablename NOT LIKE 'sql_%'
  AND NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = pg_tables.tablename 
      AND column_name = 'tenant_id'
  )
ORDER BY tablename;

-- ============================================================================
-- TEST 2: Check for NULL tenant_id values
-- ============================================================================
-- Expected: 0 rows (all data must belong to a tenant)
-- ============================================================================

DO $$
DECLARE
  v_table text;
  v_count integer;
  v_sql text;
BEGIN
  RAISE NOTICE '=== Checking for NULL tenant_id values ===';
  
  FOR v_table IN 
    SELECT tablename 
    FROM pg_tables 
    WHERE schemaname = 'public'
      AND EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = tablename 
          AND column_name = 'tenant_id'
      )
  LOOP
    v_sql := format('SELECT COUNT(*) FROM public.%I WHERE tenant_id IS NULL', v_table);
    EXECUTE v_sql INTO v_count;
    
    IF v_count > 0 THEN
      RAISE NOTICE 'Table % has % rows with NULL tenant_id', v_table, v_count;
    END IF;
  END LOOP;
  
  RAISE NOTICE '=== Check complete ===';
END $$;

-- ============================================================================
-- TEST 3: Verify RLS is ENABLED on all tenant tables
-- ============================================================================
-- Expected: All tenant tables should have rowsecurity = true
-- ============================================================================

SELECT 
  schemaname,
  tablename,
  rowsecurity,
  CASE 
    WHEN rowsecurity THEN '✅ RLS Enabled'
    ELSE '❌ RLS DISABLED - CRITICAL SECURITY ISSUE'
  END as status
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename NOT IN ('tenants', 'schema_migrations', '_prisma_migrations')
  AND EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = pg_tables.tablename 
      AND column_name = 'tenant_id'
  )
ORDER BY rowsecurity, tablename;

-- ============================================================================
-- TEST 4: Check for OLD non-tenant-filtered policies
-- ============================================================================
-- Expected: 0 rows (all old policies should be removed)
-- ============================================================================

SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check,
  '❌ OLD POLICY WITHOUT TENANT FILTER' as issue
FROM pg_policies
WHERE schemaname = 'public'
  AND (
    -- Old patterns that don't filter by tenant
    policyname ILIKE '%authenticated%'
    OR policyname ILIKE '%anon%'
    OR (
      qual IS NOT NULL 
      AND qual NOT ILIKE '%tenant_id%'
      AND qual NOT ILIKE '%user_tenant_id%'
      AND tablename NOT IN ('tenants', 'schema_migrations', '_prisma_migrations')
    )
  )
ORDER BY tablename, policyname;

-- ============================================================================
-- TEST 5: Verify NEW tenant-filtered policies exist
-- ============================================================================
-- Expected: Many rows (all tenant tables should have tenant-filtered policies)
-- ============================================================================

SELECT 
  schemaname,
  tablename,
  policyname,
  cmd,
  CASE 
    WHEN qual ILIKE '%user_tenant_id%' OR qual ILIKE '%tenant_id%' THEN '✅ Tenant Filtered'
    ELSE '⚠️ NOT tenant filtered'
  END as filter_status,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = pg_policies.tablename 
      AND column_name = 'tenant_id'
  )
ORDER BY tablename, cmd, policyname;

-- ============================================================================
-- TEST 6: Verify user_tenant_id() function exists and works
-- ============================================================================
-- Expected: Returns the current user's tenant_id (UUID)
-- ============================================================================

SELECT 
  public.user_tenant_id() as current_user_tenant_id,
  auth.uid() as current_user_id,
  auth.email() as current_user_email,
  CASE 
    WHEN public.user_tenant_id() IS NULL THEN '❌ CRITICAL: No tenant assigned to user'
    ELSE '✅ User has tenant'
  END as status;

-- ============================================================================
-- TEST 7: Check user tenant assignment in auth.users
-- ============================================================================
-- Expected: Current user should have tenant_id in raw_app_meta_data
-- ============================================================================

SELECT 
  id,
  email,
  raw_app_meta_data->>'tenant_id' as tenant_id_in_metadata,
  CASE 
    WHEN raw_app_meta_data->>'tenant_id' IS NULL THEN '❌ NO TENANT ASSIGNED'
    ELSE '✅ Tenant assigned'
  END as status
FROM auth.users
WHERE id = auth.uid();

-- ============================================================================
-- TEST 8: RLS POLICY LIVE TEST - Products
-- ============================================================================
-- Run this while logged in as different users
-- Expected: Should ONLY see products for current user's tenant
-- ============================================================================

SELECT 
  'Products visible to current user' as test,
  COUNT(*) as count,
  public.user_tenant_id() as my_tenant_id,
  array_agg(DISTINCT tenant_id) as tenant_ids_in_results,
  CASE 
    WHEN COUNT(DISTINCT tenant_id) = 1 AND (array_agg(DISTINCT tenant_id))[1] = public.user_tenant_id() THEN '✅ CORRECT: Only my tenant data'
    WHEN COUNT(DISTINCT tenant_id) > 1 THEN '❌ CRITICAL: Cross-tenant data leak'
    ELSE '⚠️ Unexpected state'
  END as isolation_status
FROM products;

-- ============================================================================
-- TEST 9: RLS POLICY LIVE TEST - Customers
-- ============================================================================

SELECT 
  'Customers visible to current user' as test,
  COUNT(*) as count,
  public.user_tenant_id() as my_tenant_id,
  array_agg(DISTINCT tenant_id) as tenant_ids_in_results,
  CASE 
    WHEN COUNT(DISTINCT tenant_id) = 1 AND (array_agg(DISTINCT tenant_id))[1] = public.user_tenant_id() THEN '✅ CORRECT: Only my tenant data'
    WHEN COUNT(DISTINCT tenant_id) > 1 THEN '❌ CRITICAL: Cross-tenant data leak'
    ELSE '⚠️ Unexpected state'
  END as isolation_status
FROM customers;

-- ============================================================================
-- TEST 10: RLS POLICY LIVE TEST - Sales Invoices
-- ============================================================================

SELECT 
  'Sales invoices visible to current user' as test,
  COUNT(*) as count,
  public.user_tenant_id() as my_tenant_id,
  array_agg(DISTINCT tenant_id) as tenant_ids_in_results,
  CASE 
    WHEN COUNT(DISTINCT tenant_id) = 1 AND (array_agg(DISTINCT tenant_id))[1] = public.user_tenant_id() THEN '✅ CORRECT: Only my tenant data'
    WHEN COUNT(DISTINCT tenant_id) > 1 THEN '❌ CRITICAL: Cross-tenant data leak'
    ELSE '⚠️ Unexpected state'
  END as isolation_status
FROM sales_invoices;

-- ============================================================================
-- TEST 11: RLS POLICY LIVE TEST - Company Settings
-- ============================================================================

SELECT 
  'Company settings visible to current user' as test,
  COUNT(*) as count,
  public.user_tenant_id() as my_tenant_id,
  array_agg(DISTINCT tenant_id) as tenant_ids_in_results,
  CASE 
    WHEN COUNT(DISTINCT tenant_id) = 1 AND (array_agg(DISTINCT tenant_id))[1] = public.user_tenant_id() THEN '✅ CORRECT: Only my tenant data'
    WHEN COUNT(DISTINCT tenant_id) > 1 THEN '❌ CRITICAL: Cross-tenant data leak'
    ELSE '⚠️ Unexpected state'
  END as isolation_status
FROM company_settings;

-- ============================================================================
-- TEST 12: Count policies per table
-- ============================================================================
-- Expected: Each tenant table should have 4-8 policies (SELECT, INSERT, UPDATE, DELETE)
-- ============================================================================

SELECT 
  tablename,
  COUNT(*) as policy_count,
  array_agg(cmd ORDER BY cmd) as commands,
  CASE 
    WHEN COUNT(*) = 0 THEN '❌ NO POLICIES - CRITICAL'
    WHEN COUNT(*) < 4 THEN '⚠️ Missing some CRUD policies'
    ELSE '✅ Has policies'
  END as status
FROM pg_policies
WHERE schemaname = 'public'
  AND EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = pg_policies.tablename 
      AND column_name = 'tenant_id'
  )
GROUP BY tablename
ORDER BY policy_count, tablename;

-- ============================================================================
-- TEST 13: Detailed policy inspection for critical tables
-- ============================================================================

SELECT 
  tablename,
  policyname,
  cmd,
  permissive,
  roles,
  qual as using_expression,
  with_check as with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'products', 'customers', 'sales_invoices', 'company_settings',
    'website_banners', 'featured_products', 'online_orders'
  )
ORDER BY tablename, cmd, policyname;

-- ============================================================================
-- TEST 14: Check if policies are PERMISSIVE or RESTRICTIVE
-- ============================================================================
-- Expected: Most policies should be PERMISSIVE (default)
-- Issue: If there are BOTH permissive and restrictive, need to verify logic
-- ============================================================================

SELECT 
  tablename,
  permissive,
  COUNT(*) as count
FROM pg_policies
WHERE schemaname = 'public'
GROUP BY tablename, permissive
ORDER BY tablename, permissive;

-- ============================================================================
-- SUMMARY QUERY: Overall Tenant Isolation Health Check
-- ============================================================================

SELECT 
  'Tenant Isolation Health Check' as report,
  (
    SELECT COUNT(*) 
    FROM pg_tables 
    WHERE schemaname = 'public'
      AND tablename NOT IN ('tenants', 'schema_migrations', '_prisma_migrations')
      AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = pg_tables.tablename AND column_name = 'tenant_id'
      )
  ) as tables_missing_tenant_id,
  (
    SELECT COUNT(*) 
    FROM pg_tables 
    WHERE schemaname = 'public'
      AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = pg_tables.tablename AND column_name = 'tenant_id')
      AND rowsecurity = false
  ) as tables_with_rls_disabled,
  (
    SELECT COUNT(*) 
    FROM pg_policies 
    WHERE schemaname = 'public'
      AND (policyname ILIKE '%authenticated%' OR qual NOT ILIKE '%tenant_id%')
  ) as old_policies_without_tenant_filter,
  public.user_tenant_id() as current_user_tenant,
  auth.email() as current_user_email;

-- ============================================================================
-- INSTRUCTIONS:
-- ============================================================================
-- 1. Log in to Supabase SQL Editor as ccatalansandoval7@gmail.com
-- 2. Run ALL queries above
-- 3. Check results:
--    - TEST 1: Should be 0 rows
--    - TEST 2: Should show no NULL tenant_id notices
--    - TEST 3: All should show "✅ RLS Enabled"
--    - TEST 4: Should be 0 rows (no old policies)
--    - TEST 5: Should show many tenant-filtered policies
--    - TEST 6: Should return Claudio's tenant_id
--    - TEST 7: Should show tenant_id in metadata
--    - TEST 8-11: Should ALL show "✅ CORRECT: Only my tenant data"
--    - TEST 12: All tables should have 4+ policies
-- 4. Log out and log in as nico.catalan7@gmail.com
-- 5. Run tests 6-11 again
-- 6. Verify you see DIFFERENT tenant_id and DIFFERENT data
-- ============================================================================
