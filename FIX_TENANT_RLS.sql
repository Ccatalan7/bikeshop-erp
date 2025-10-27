-- ============================================================================
-- FIX TENANT RLS POLICIES - Allow users to read their own tenant
-- ============================================================================

-- Drop old policies
DROP POLICY IF EXISTS "tenant_select_own" ON tenants;
DROP POLICY IF EXISTS "tenant_update_own" ON tenants;

-- Recreate with direct user_profiles check (no function call)
CREATE POLICY "tenant_select_own" ON tenants 
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE user_profiles.tenant_id = tenants.id 
        AND user_profiles.user_id = auth.uid()
    )
  );

CREATE POLICY "tenant_update_own" ON tenants 
  FOR UPDATE 
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE user_profiles.tenant_id = tenants.id 
        AND user_profiles.user_id = auth.uid()
    )
  );

-- Verify policies
SELECT 
  policyname,
  cmd as operation,
  qual as using_expression
FROM pg_policies 
WHERE tablename = 'tenants'
ORDER BY policyname;

-- ============================================================================
-- ✅ Done! Users can now read/update their own tenant
-- ============================================================================
