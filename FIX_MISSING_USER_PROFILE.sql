-- ============================================================================
-- DIAGNOSE MISSING user_profiles ENTRY
-- ============================================================================

-- 1. Check if you have a user account
SELECT 
  'Your user account' as info,
  id,
  email,
  created_at,
  email_confirmed_at
FROM auth.users 
WHERE email = 'ccatalan.us@gmail.com';

-- 2. Check if you have a user_profiles entry (THIS SHOULD BE EMPTY = BUG!)
SELECT 
  'Your user_profiles entry' as info,
  user_id,
  tenant_id,
  role,
  created_at
FROM public.user_profiles
WHERE user_id = (SELECT id FROM auth.users WHERE email = 'ccatalan.us@gmail.com');

-- 3. Check if a tenant was created for you
SELECT 
  'Tenants owned by your email' as info,
  id,
  shop_name,
  subdomain,
  owner_email,
  created_at
FROM public.tenants
WHERE owner_email = 'ccatalan.us@gmail.com';

-- 4. Check ALL user_profiles to see what's there
SELECT 
  'All user_profiles' as info,
  up.user_id,
  u.email,
  up.tenant_id,
  t.shop_name,
  up.role
FROM public.user_profiles up
LEFT JOIN auth.users u ON up.user_id = u.id
LEFT JOIN public.tenants t ON up.tenant_id = t.id
ORDER BY up.created_at DESC;

-- ============================================================================
-- FIX: If Step 2 is empty BUT Step 3 shows a tenant, run this:
-- ============================================================================

-- Get your user_id and tenant_id
DO $$
DECLARE
  v_user_id uuid;
  v_tenant_id uuid;
BEGIN
  -- Get user_id
  SELECT id INTO v_user_id 
  FROM auth.users 
  WHERE email = 'ccatalan.us@gmail.com';
  
  -- Get tenant_id
  SELECT id INTO v_tenant_id
  FROM public.tenants
  WHERE owner_email = 'ccatalan.us@gmail.com'
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ User not found!';
    RETURN;
  END IF;
  
  IF v_tenant_id IS NULL THEN
    RAISE NOTICE '❌ No tenant found for this email!';
    RETURN;
  END IF;
  
  RAISE NOTICE '✅ User ID: %', v_user_id;
  RAISE NOTICE '✅ Tenant ID: %', v_tenant_id;
  
  -- Create the missing user_profiles entry
  INSERT INTO public.user_profiles (user_id, tenant_id, role)
  VALUES (v_user_id, v_tenant_id, 'admin')
  ON CONFLICT (user_id, tenant_id) DO NOTHING;
  
  RAISE NOTICE '✅ Created user_profiles entry!';
  
  -- Verify
  IF EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = v_user_id AND tenant_id = v_tenant_id) THEN
    RAISE NOTICE '✅ Verification: user_profiles entry exists!';
  ELSE
    RAISE NOTICE '❌ Verification failed!';
  END IF;
  
END $$;

-- Verify the fix
SELECT 
  'After fix' as info,
  up.user_id,
  up.tenant_id,
  up.role,
  t.shop_name,
  t.subdomain
FROM public.user_profiles up
JOIN public.tenants t ON up.tenant_id = t.id
WHERE up.user_id = (SELECT id FROM auth.users WHERE email = 'ccatalan.us@gmail.com');
