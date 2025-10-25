-- ============================================================================
-- Check what RLS policies ACTUALLY exist on products table RIGHT NOW
-- ============================================================================

SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd as command,
  qual as using_expression,
  with_check
FROM pg_policies
WHERE tablename = 'products'
ORDER BY policyname;

-- Also check if RLS is enabled
SELECT 
  tablename,
  rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'products';

-- Check what user_tenant_id() returns for you
SELECT 
  'Your tenant_id' as check,
  public.user_tenant_id() as result;

-- Check your JWT
SELECT 
  'JWT tenant_id' as check,
  auth.jwt()->'user_metadata'->>'tenant_id' as result;
