-- Verify new user setup for current logged-in user
-- Run this AFTER signing up to verify all automatic initialization worked
-- NOTE: Must be run as the authenticated user (not service role)

DO $$
DECLARE
  v_user_id uuid;
  v_tenant_id uuid;
  v_count int;
BEGIN
  -- Get current authenticated user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ No authenticated user found';
    RAISE NOTICE '   Make sure you are logged in (not using service role)';
    RETURN;
  END IF;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'VERIFYING SETUP FOR USER: %', v_user_id;
  RAISE NOTICE '========================================';
  
  -- 1. Check user_profiles
  SELECT tenant_id INTO v_tenant_id
  FROM public.user_profiles
  WHERE user_id = v_user_id;

  IF v_tenant_id IS NULL THEN
    RAISE NOTICE '❌ User profile NOT found';
    RAISE NOTICE '   Make sure user has signed up and profile was created';
    RETURN;
  ELSE
    RAISE NOTICE '✅ User profile found';
    RAISE NOTICE '   User ID: %', v_user_id;
  END IF;

  -- 2. Check user_profiles details
  RAISE NOTICE '✅ User profile found';
  RAISE NOTICE '   Tenant ID: %', v_tenant_id;
  RAISE NOTICE '   Role: %', (SELECT role FROM public.user_profiles WHERE user_id = v_user_id);
  RAISE NOTICE '   Permissions: %', (SELECT permissions FROM public.user_profiles WHERE user_id = v_user_id);
  
  -- Check if permissions are properly set
  SELECT COUNT(*) INTO v_count 
  FROM jsonb_object_keys((SELECT permissions FROM public.user_profiles WHERE user_id = v_user_id));
  
  IF v_count = 0 THEN
    RAISE NOTICE '   ⚠️  Permissions are EMPTY (should have 7 keys for admin)';
  ELSE
    RAISE NOTICE '   ✅ Permissions has % keys', v_count;
    IF v_count < 7 THEN
      RAISE NOTICE '   ⚠️  Expected 7 permission keys, found %', v_count;
    END IF;
  END IF;  -- 3. Check tenant
  SELECT COUNT(*) INTO v_count
  FROM public.tenants
  WHERE id = v_tenant_id;

  IF v_count = 0 THEN
    RAISE NOTICE '❌ Tenant NOT found';
    RETURN;
  ELSE
    RAISE NOTICE '✅ Tenant found';
    RAISE NOTICE '   Shop Name: %', (SELECT shop_name FROM public.tenants WHERE id = v_tenant_id);
    RAISE NOTICE '   Subdomain: %', (SELECT subdomain FROM public.tenants WHERE id = v_tenant_id);
    RAISE NOTICE '   Currency: %', (SELECT currency FROM public.tenants WHERE id = v_tenant_id);
    RAISE NOTICE '   Timezone: %', (SELECT timezone FROM public.tenants WHERE id = v_tenant_id);
  END IF;

  -- 4. Check accounts (should have ~30 accounts)
  SELECT COUNT(*) INTO v_count
  FROM public.accounts
  WHERE tenant_id = v_tenant_id;

  RAISE NOTICE '✅ Accounts: % accounts', v_count;
  IF v_count < 20 THEN
    RAISE NOTICE '   ⚠️  Expected ~30 accounts, found %', v_count;
  END IF;

  -- 5. Check payment methods (should have 4)
  SELECT COUNT(*) INTO v_count
  FROM public.payment_methods
  WHERE tenant_id = v_tenant_id;

  RAISE NOTICE '✅ Payment Methods: % methods', v_count;
  IF v_count < 4 THEN
    RAISE NOTICE '   ⚠️  Expected 4 methods, found %', v_count;
  END IF;

  -- 6. Check company settings (should have ~8 settings)
  SELECT COUNT(*) INTO v_count
  FROM public.company_settings
  WHERE tenant_id = v_tenant_id;

  RAISE NOTICE '✅ Company Settings: % settings', v_count;
  IF v_count < 5 THEN
    RAISE NOTICE '   ⚠️  Expected ~8 settings, found %', v_count;
  END IF;

  -- 7. Check website settings (should have ~7 settings)
  SELECT COUNT(*) INTO v_count
  FROM public.website_settings
  WHERE tenant_id = v_tenant_id;

  RAISE NOTICE '✅ Website Settings: % settings', v_count;
  IF v_count < 5 THEN
    RAISE NOTICE '   ⚠️  Expected ~7 settings, found %', v_count;
  END IF;

  RAISE NOTICE '========================================';
  RAISE NOTICE 'VERIFICATION COMPLETE';
  RAISE NOTICE '========================================';

END $$;

-- Detailed query: Show all setup data for current user
SELECT 
  'PROFILE' as type,
  up.user_id::text as email,
  up.tenant_id::text as id,
  up.role as name,
  up.is_active::text as value
FROM public.user_profiles up
WHERE up.user_id = auth.uid()

UNION ALL

SELECT 
  'PERMISSIONS' as type,
  NULL as email,
  NULL as id,
  key as name,
  value::text as value
FROM public.user_profiles up,
     jsonb_each(up.permissions)
WHERE up.user_id = auth.uid()

UNION ALL

SELECT 
  'TENANT' as type,
  t.shop_name as email,
  t.id::text as id,
  t.subdomain as name,
  t.currency as value
FROM public.tenants t
WHERE t.id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid())

UNION ALL

SELECT 
  'ACCOUNT' as type,
  coa.code as email,
  coa.id::text as id,
  coa.name as name,
  coa.type as value
FROM public.accounts coa
WHERE coa.tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid())
ORDER BY type, email
LIMIT 50;

-- Summary counts
SELECT 
  'Accounts' as item,
  COUNT(*)::text as count
FROM public.accounts
WHERE tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid())

UNION ALL

SELECT 
  'Payment Methods' as item,
  COUNT(*)::text as count
FROM public.payment_methods
WHERE tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid())

UNION ALL

SELECT 
  'Company Settings' as item,
  COUNT(*)::text as count
FROM public.company_settings
WHERE tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid())

UNION ALL

SELECT 
  'Website Settings' as item,
  COUNT(*)::text as count
FROM public.website_settings
WHERE tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE user_id = auth.uid());
