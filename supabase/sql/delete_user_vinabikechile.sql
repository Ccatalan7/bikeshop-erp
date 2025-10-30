-- Delete user vinabikechile@gmail.com and all associated data
-- This script will:
-- 1. Find the user's tenant_id
-- 2. Delete all tenant data (CASCADE will handle related records)
-- 3. Delete the user from auth.users

DO $$
DECLARE
  v_user_id uuid;
  v_tenant_id uuid;
  v_user_email text := 'vinabikechile@gmail.com';
BEGIN
  -- Find user ID from auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = v_user_email;

  IF v_user_id IS NULL THEN
    RAISE NOTICE 'User % not found', v_user_email;
    RETURN;
  END IF;

  RAISE NOTICE 'Found user: % (ID: %)', v_user_email, v_user_id;

  -- Find tenant ID from user_profiles
  SELECT tenant_id INTO v_tenant_id
  FROM public.user_profiles
  WHERE user_id = v_user_id;

  IF v_tenant_id IS NOT NULL THEN
    RAISE NOTICE 'Found tenant_id: %', v_tenant_id;
    
    -- Delete tenant (CASCADE will delete all related data)
    DELETE FROM public.tenants WHERE id = v_tenant_id;
    RAISE NOTICE 'Deleted tenant and all associated data';
  ELSE
    RAISE NOTICE 'No tenant found for user';
  END IF;

  -- Delete user profile
  DELETE FROM public.user_profiles WHERE user_id = v_user_id;
  RAISE NOTICE 'Deleted user_profile';

  -- Delete user from auth.users (this requires service role)
  DELETE FROM auth.users WHERE id = v_user_id;
  RAISE NOTICE 'Deleted user from auth.users';

  RAISE NOTICE 'Successfully deleted user % and all associated data', v_user_email;
END $$;
