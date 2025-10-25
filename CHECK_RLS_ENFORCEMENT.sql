-- ============================================================================
-- CRITICAL: Check if RLS is actually enforced
-- ============================================================================

-- 1. Is RLS enabled on products?
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'products';

-- 2. What RLS policies exist on products?
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
WHERE tablename = 'products';

-- 3. Test: Can anonymous user see products? (Should be NO)
SET ROLE anon;
SELECT count(*) as anon_can_see FROM products;
RESET ROLE;

-- 4. What does your current session see?
SELECT 
  'Your session' as test,
  auth.uid() as user_id,
  public.user_tenant_id() as tenant_id,
  count(*) as products_visible
FROM products;

-- 5. Check the actual policy definitions
SELECT 
  polname,
  pg_get_expr(polqual, polrelid) as using_expr,
  pg_get_expr(polwithcheck, polrelid) as with_check_expr
FROM pg_policy
WHERE polrelid = 'products'::regclass;

-- ============================================================================
-- EXPECTED RESULTS:
-- - rls_enabled should be TRUE
-- - Should have policies like "products_select", "products_insert", etc.
-- - Anonymous user should see 0 products
-- - Your session should only see products from YOUR tenant
-- ============================================================================
