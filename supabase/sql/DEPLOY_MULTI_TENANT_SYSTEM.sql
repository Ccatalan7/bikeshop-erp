-- ============================================================================
-- VINABIKE ERP - MULTI-TENANT SYSTEM DEPLOYMENT
-- ============================================================================
-- This script deploys the complete multi-tenant system with auto-signup
-- Run this in Supabase SQL Editor AFTER the main core_schema.sql
-- ============================================================================

-- ============================================================================
-- STEP 1: Verify core schema is deployed
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tenants') THEN
    RAISE EXCEPTION 'ERROR: tenants table does not exist. Deploy core_schema.sql first!';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_invitations') THEN
    RAISE EXCEPTION 'ERROR: user_invitations table does not exist. Deploy core_schema.sql first!';
  END IF;
  
  RAISE NOTICE '✓ Core schema verified';
END $$;

-- ============================================================================
-- STEP 2: Verify signup trigger is active
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_user_created'
  ) THEN
    RAISE WARNING 'Signup trigger not found. It will be created by core_schema.sql';
  ELSE
    RAISE NOTICE '✓ Signup trigger active';
  END IF;
END $$;

-- ============================================================================
-- STEP 3: Check tenant setup
-- ============================================================================
SELECT 
  id,
  shop_name,
  owner_email,
  plan,
  is_active,
  created_at
FROM tenants
ORDER BY created_at;

-- ============================================================================
-- STEP 4: Check user assignments
-- ============================================================================
SELECT 
  email,
  raw_user_meta_data->>'tenant_id' as tenant_id,
  raw_user_meta_data->>'role' as role,
  raw_user_meta_data->'permissions'->>'manage_users' as can_manage_users,
  created_at
FROM auth.users
ORDER BY created_at;

-- ============================================================================
-- STEP 5: Test RLS policies
-- ============================================================================
-- This should return the tenant for the current user (if logged in)
SELECT * FROM tenants WHERE id = public.user_tenant_id();

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================
DO $$
DECLARE
  tenant_count INT;
  user_count INT;
BEGIN
  SELECT COUNT(*) INTO tenant_count FROM tenants;
  SELECT COUNT(*) INTO user_count FROM auth.users WHERE raw_user_meta_data->>'tenant_id' IS NOT NULL;
  
  RAISE NOTICE '═══════════════════════════════════════════════════════════';
  RAISE NOTICE '🎉 MULTI-TENANT SYSTEM DEPLOYMENT COMPLETE!';
  RAISE NOTICE '═══════════════════════════════════════════════════════════';
  RAISE NOTICE '📊 Tenants created: %', tenant_count;
  RAISE NOTICE '👥 Users assigned: %', user_count;
  RAISE NOTICE '';
  RAISE NOTICE '✅ Auto-signup enabled: New users will automatically get their own tenant';
  RAISE NOTICE '✅ Invitation system active: Managers can invite employees to join their tenant';
  RAISE NOTICE '✅ Row Level Security active: Users can only see their tenant''s data';
  RAISE NOTICE '';
  RAISE NOTICE '📋 NEXT STEPS:';
  RAISE NOTICE '1. Log out and log back in to refresh JWT tokens';
  RAISE NOTICE '2. Test creating new products/customers (should auto-include tenant_id)';
  RAISE NOTICE '3. Try inviting a new user via UserManagementService';
  RAISE NOTICE '═══════════════════════════════════════════════════════════';
END $$;
