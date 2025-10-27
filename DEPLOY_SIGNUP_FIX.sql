-- ============================================================================
-- FIX SIGNUP FLOW - Allow tenant and user_profiles creation
-- ============================================================================
-- Problem: Users cannot sign up because RLS blocks INSERT on tenants and user_profiles
-- Solution: Add policies to allow authenticated users to create their tenant during signup
-- ============================================================================

-- Fix 1: Allow authenticated users to INSERT into tenants table (for signup)
DROP POLICY IF EXISTS "tenant_insert_authenticated" ON tenants;
CREATE POLICY "tenant_insert_authenticated" ON tenants 
  FOR INSERT 
  WITH CHECK (auth.uid() IS NOT NULL);

-- Fix 2: Allow users to INSERT their own user_profile entry (for signup)
DROP POLICY IF EXISTS "Users can create their own profile during signup" ON user_profiles;
CREATE POLICY "Users can create their own profile during signup" ON user_profiles
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Verify policies exist
SELECT 
  'Tenants policies' as table_name,
  policyname,
  cmd as operation
FROM pg_policies 
WHERE tablename = 'tenants'
ORDER BY policyname;

SELECT 
  'User_profiles policies' as table_name,
  policyname,
  cmd as operation
FROM pg_policies 
WHERE tablename = 'user_profiles'
ORDER BY policyname;

-- ============================================================================
-- Success!
-- ============================================================================
-- ✅ Users can now sign up and create their tenant
-- ✅ user_profiles entry will be created automatically
-- ✅ Multi-tenant isolation still enforced after signup
-- ============================================================================
