-- ========================================
-- FIX PROFILE FOR admin@vinabike.cl
-- ========================================
-- This creates a user_profile and tenant for the Vinabike admin user
-- ========================================

DO $$
DECLARE
  v_user_id uuid := 'a406fc72-74e1-4c04-b1b2-e58aba69ba30';
  v_tenant_id uuid;
  v_tenant_name text := 'Vinabike Shop';
  v_subdomain text := 'vinabike';
BEGIN
  -- Check if tenant already exists for Vinabike
  SELECT id INTO v_tenant_id 
  FROM tenants 
  WHERE shop_name = v_tenant_name OR subdomain = v_subdomain
  LIMIT 1;
  
  -- If tenant doesn't exist, create it
  IF v_tenant_id IS NULL THEN
    INSERT INTO tenants (
      shop_name,
      subdomain,
      currency,
      timezone,
      is_active
    )
    VALUES (
      v_tenant_name,
      v_subdomain,
      'CLP',
      'America/Santiago',
      true
    )
    RETURNING id INTO v_tenant_id;
    
    RAISE NOTICE '✅ Created new tenant: % (ID: %)', v_tenant_name, v_tenant_id;
    
    -- Seed foundation data for new tenant
    PERFORM public.seed_chart_of_accounts(v_tenant_id);
    PERFORM public.seed_payment_methods_for_tenant(v_tenant_id);
    PERFORM public.seed_company_settings(v_tenant_id);
    PERFORM public.seed_website_settings(v_tenant_id);
    
    RAISE NOTICE '✅ Seeded foundation data for tenant';
  ELSE
    RAISE NOTICE '✅ Using existing tenant: % (ID: %)', v_tenant_name, v_tenant_id;
  END IF;
  
  -- Create or update user_profile for admin@vinabike.cl
  -- First delete if exists, then insert
  DELETE FROM user_profiles WHERE user_id = v_user_id;
  
  INSERT INTO user_profiles (
    user_id,
    tenant_id,
    role,
    created_at,
    updated_at
  )
  VALUES (
    v_user_id,
    v_tenant_id,
    'admin',
    NOW(),
    NOW()
  );
  
  RAISE NOTICE '✅ Created/updated user_profile for admin@vinabike.cl';
  
  -- Verify the result
  RAISE NOTICE '====================================';
  RAISE NOTICE 'User ID: %', v_user_id;
  RAISE NOTICE 'Email: admin@vinabike.cl';
  RAISE NOTICE 'Tenant ID: %', v_tenant_id;
  RAISE NOTICE 'Tenant Name: %', v_tenant_name;
  RAISE NOTICE 'Subdomain: %', v_subdomain;
  RAISE NOTICE 'Role: admin';
  RAISE NOTICE '====================================';
  
END $$;

-- Verify the fix by selecting the user's data
SELECT 
  u.email,
  up.tenant_id,
  up.role,
  t.shop_name,
  t.subdomain,
  '✅ FIXED' as status
FROM auth.users u
JOIN public.user_profiles up ON up.user_id = u.id
JOIN public.tenants t ON t.id = up.tenant_id
WHERE u.id = 'a406fc72-74e1-4c04-b1b2-e58aba69ba30';
