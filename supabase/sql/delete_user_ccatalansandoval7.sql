-- Delete user ccatalansandoval7@gmail.com and all associated data
-- Run this in Supabase SQL Editor with service role permissions

do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
begin
  -- Get user_id from email
  select id into v_user_id
  from auth.users
  where email = 'ccatalansandoval7@gmail.com';
  
  if v_user_id is null then
    raise notice 'User not found with email: ccatalansandoval7@gmail.com';
    return;
  end if;
  
  raise notice 'Found user_id: %', v_user_id;
  
  -- Get tenant_id from user_profiles
  select tenant_id into v_tenant_id
  from user_profiles
  where user_id = v_user_id;
  
  if v_tenant_id is null then
    raise notice 'No tenant found for user, deleting user only';
  else
    raise notice 'Found tenant_id: %', v_tenant_id;
    
    -- Delete ALL tenant data (cascades to all related tables)
    raise notice 'Deleting tenant and all associated data...';
    delete from tenants where id = v_tenant_id;
    raise notice '✅ Tenant and all data deleted';
  end if;
  
  -- Delete user from auth.users (this also cascades to user_profiles if not already deleted)
  raise notice 'Deleting user from auth.users...';
  delete from auth.users where id = v_user_id;
  raise notice '✅ User deleted from auth.users';
  
  raise notice '✅ Complete! User ccatalansandoval7@gmail.com and all data deleted';
end $$;

-- Verify deletion
select 
  (select count(*) from auth.users where email = 'ccatalansandoval7@gmail.com') as users_remaining,
  (select count(*) from user_profiles where user_id in (select id from auth.users where email = 'ccatalansandoval7@gmail.com')) as profiles_remaining;
