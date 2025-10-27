-- ============================================================================
-- CHECK CURRENT SIGNUP STATE
-- ============================================================================
-- This will show us exactly what data exists for the current user
-- ============================================================================

-- Step 1: Find the user
SELECT 
  '1. Auth User' as step,
  id,
  email,
  created_at,
  email_confirmed_at,
  raw_app_meta_data
FROM auth.users
WHERE email = 'ccatalan.us@gmail.com';

-- Step 2: Check if user_profile exists
SELECT 
  '2. User Profile' as step,
  up.id,
  up.user_id,
  up.tenant_id,
  up.role,
  up.created_at
FROM user_profiles up
JOIN auth.users u ON up.user_id = u.id
WHERE u.email = 'ccatalan.us@gmail.com';

-- Step 3: Check if tenant exists
SELECT 
  '3. Tenant' as step,
  t.id,
  t.shop_name,
  t.subdomain,
  t.owner_email,
  t.created_at
FROM tenants t
WHERE t.owner_email = 'ccatalan.us@gmail.com';

-- Step 4: Check what RLS policies exist
SELECT 
  '4. RLS Policies' as step,
  tablename,
  policyname,
  cmd as operation
FROM pg_policies 
WHERE tablename IN ('tenants', 'user_profiles')
ORDER BY tablename, policyname;

-- ============================================================================
-- Expected results:
-- Step 1: Should show 1 user
-- Step 2: Should show 1 user_profile (if signup completed)
-- Step 3: Should show 1 tenant (if signup completed)
-- Step 4: Should show all RLS policies
-- ============================================================================
