-- ============================================================================
-- DELETE TEST USER AND ALL ASSOCIATED DATA
-- User: ccatalan.us@gmail.com
-- ============================================================================
-- WARNING: This will delete ALL data for this user's tenant!
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Step 1: Find the user and tenant
DO $$
DECLARE
  v_user_id uuid;
  v_tenant_id uuid;
BEGIN
  -- Find user by email
  SELECT id INTO v_user_id 
  FROM auth.users 
  WHERE email = 'ccatalan.us@gmail.com';
  
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'User not found: ccatalan.us@gmail.com';
    RETURN;
  END IF;
  
  RAISE NOTICE 'Found user: %', v_user_id;
  
  -- Find tenant for this user
  SELECT tenant_id INTO v_tenant_id
  FROM public.user_profiles
  WHERE user_id = v_user_id;
  
  IF v_tenant_id IS NULL THEN
    RAISE NOTICE 'No tenant found for user %', v_user_id;
  ELSE
    RAISE NOTICE 'Found tenant: %', v_tenant_id;
  END IF;
  
  -- Step 2: Delete tenant data (CASCADE will handle all related records)
  IF v_tenant_id IS NOT NULL THEN
    RAISE NOTICE 'Deleting tenant % and all its data...', v_tenant_id;
    
    DELETE FROM public.tenants WHERE id = v_tenant_id;
    
    RAISE NOTICE 'Tenant deleted successfully (CASCADE deleted all related data)';
  END IF;
  
  -- Step 3: Delete user profile
  DELETE FROM public.user_profiles WHERE user_id = v_user_id;
  RAISE NOTICE 'User profile deleted';
  
  -- Step 4: Delete auth user
  DELETE FROM auth.users WHERE id = v_user_id;
  RAISE NOTICE 'Auth user deleted';
  
  RAISE NOTICE '✅ User ccatalan.us@gmail.com and all associated data deleted successfully!';
  
END $$;

-- ============================================================================
-- Verify deletion
-- ============================================================================

-- Check if user still exists (should return 0 rows)
SELECT 
  'auth.users' as table_name,
  COUNT(*) as count 
FROM auth.users 
WHERE email = 'ccatalan.us@gmail.com'

UNION ALL

-- Check if user profile still exists (should return 0 rows)
SELECT 
  'user_profiles' as table_name,
  COUNT(*) as count
FROM public.user_profiles up
JOIN auth.users u ON up.user_id = u.id
WHERE u.email = 'ccatalan.us@gmail.com'

UNION ALL

-- Check if tenant still exists (should return 0 rows)
SELECT 
  'tenants' as table_name,
  COUNT(*) as count
FROM public.tenants t
WHERE t.owner_email = 'ccatalan.us@gmail.com';

-- ============================================================================
-- Expected result: All counts should be 0
-- ============================================================================
