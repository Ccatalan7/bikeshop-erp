-- CRITICAL FIX: Update auth.users metadata with tenant_id
-- This ensures the session has tenant_id without requiring re-login

do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
  v_role text;
begin
  -- Get user and their profile data
  select 
    au.id,
    up.tenant_id,
    up.role
  into v_user_id, v_tenant_id, v_role
  from auth.users au
  join public.user_profiles up on up.user_id = au.id
  where au.email = 'ccatalan.us@gmail.com';

  if v_user_id is null then
    raise exception 'User not found';
  end if;

  if v_tenant_id is null then
    raise exception 'User has no tenant_id in user_profiles - run FIX_USER_TENANT.sql first!';
  end if;

  raise notice '✓ Found user: % with tenant_id: %', v_user_id, v_tenant_id;

  -- Update auth.users app_metadata to include tenant_id and role
  -- This makes it available in the JWT token and session
  update auth.users
  set 
    raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
      'tenant_id', v_tenant_id,
      'role', v_role
    ),
    updated_at = now()
  where id = v_user_id;

  raise notice '✓ Updated auth.users metadata with tenant_id and role';
  raise notice '✓ User must refresh their browser or sign out/in for changes to take effect';
end $$;

-- Verify
select 
  email,
  raw_user_meta_data->>'tenant_id' as user_meta_tenant_id,
  raw_user_meta_data->>'role' as user_meta_role,
  raw_user_meta_data
from auth.users
where email = 'ccatalan.us@gmail.com';
