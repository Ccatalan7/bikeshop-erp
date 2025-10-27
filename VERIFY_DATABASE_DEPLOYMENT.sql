-- ============================================================================
-- VERIFY DATABASE DEPLOYMENT SUCCESS
-- Run this in Supabase SQL Editor to check if deployment worked
-- ============================================================================

WITH deployment_checks AS (
  SELECT 1 as check_order, 'user_profiles table' as check_name, 
         CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_profiles') 
              THEN '✅ EXISTS' 
              ELSE '❌ MISSING' 
         END as status
  
  UNION ALL
  
  SELECT 2, 'reserved_subdomains table',
         (SELECT COUNT(*)::text || ' rows' FROM reserved_subdomains)
  
  UNION ALL
  
  SELECT 3, 'tenants.custom_domain column',
         CASE WHEN EXISTS (
             SELECT 1 FROM information_schema.columns 
             WHERE table_name = 'tenants' AND column_name = 'custom_domain'
         ) THEN '✅ EXISTS' ELSE '❌ MISSING' END
  
  UNION ALL
  
  SELECT 4, 'user_profiles RLS policies',
         (SELECT COUNT(*)::text || ' policies' FROM pg_policies WHERE tablename = 'user_profiles')
  
  UNION ALL
  
  SELECT 5, 'Public store RLS policies',
         (SELECT COUNT(*)::text || ' policies' FROM pg_policies WHERE policyname LIKE 'public_%')
  
  UNION ALL
  
  SELECT 6, 'Old handle_new_user() trigger',
         CASE WHEN EXISTS (
             SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created'
         ) THEN '⚠️ STILL EXISTS (should be disabled)' 
           ELSE '✅ DISABLED' 
         END
  
  UNION ALL
  
  SELECT 7, 'user_tenant_id() function',
         CASE WHEN EXISTS (
             SELECT 1 FROM pg_proc WHERE proname = 'user_tenant_id'
         ) THEN '✅ EXISTS' ELSE '❌ MISSING' END
  
  UNION ALL
  
  SELECT 8, 'user_tenant_id() test',
         CASE WHEN public.user_tenant_id() IS NULL 
              THEN '✅ Returns NULL (anon user)' 
              ELSE '⚠️ Returns: ' || public.user_tenant_id()::text 
         END
)
SELECT check_order as "#", check_name as "Check", status as "Status"
FROM deployment_checks
ORDER BY check_order;
