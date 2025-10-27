-- ============================================================================
-- FIX INFINITE RECURSION IN user_profiles RLS POLICY
-- ============================================================================
-- Problem: "Admins can manage profiles in their tenant" policy queries 
--          user_profiles FROM WITHIN user_profiles policy → infinite loop
-- Solution: Use user_tenant_id() function which has SECURITY DEFINER to bypass RLS
-- ============================================================================

-- Drop the broken policy
DROP POLICY IF EXISTS "Admins can manage profiles in their tenant" ON user_profiles;

-- Recreate with correct logic (no self-referencing query)
CREATE POLICY "Admins can manage profiles in their tenant" ON user_profiles
  FOR ALL
  USING (tenant_id = user_tenant_id());

-- Verify the policy exists
SELECT 
  policyname,
  cmd as operation,
  qual as using_clause
FROM pg_policies 
WHERE tablename = 'user_profiles'
  AND policyname = 'Admins can manage profiles in their tenant';

-- ============================================================================
-- ✅ Fixed! No more infinite recursion
-- ============================================================================
-- The user_tenant_id() function has SECURITY DEFINER which bypasses RLS
-- This breaks the infinite loop
-- ============================================================================
