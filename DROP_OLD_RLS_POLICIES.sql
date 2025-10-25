-- ============================================================================
-- FIX: Remove conflicting RLS policies that bypass tenant isolation
-- ============================================================================
-- These old policies allow ANY authenticated user to see ALL products
-- They conflict with the tenant-based policies
-- ============================================================================

-- Drop the old "Authenticated products read" policy
DROP POLICY IF EXISTS "Authenticated products read" ON products;

-- Drop the old "Public website products read" policy  
DROP POLICY IF EXISTS "Public website products read" ON products;

-- Drop old authenticated policies for other operations
DROP POLICY IF EXISTS "Authenticated products insert" ON products;
DROP POLICY IF EXISTS "Authenticated products update" ON products;
DROP POLICY IF EXISTS "Authenticated products delete" ON products;

-- Verify only tenant-based policies remain
SELECT 
  policyname,
  pg_get_expr(polqual, polrelid) as using_expression
FROM pg_policy
WHERE polrelid = 'products'::regclass;

-- ============================================================================
-- EXPECTED: Only these policies should remain:
-- - products_select (using: tenant_id = user_tenant_id())
-- - products_insert (using: tenant_id = user_tenant_id())
-- - products_update (using: tenant_id = user_tenant_id())
-- - products_delete (using: tenant_id = user_tenant_id())
-- ============================================================================
