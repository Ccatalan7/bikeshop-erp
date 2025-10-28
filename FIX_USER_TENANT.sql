-- FIX: Assign tenant_id to ccatalan.us@gmail.com
-- This user was created BEFORE the multi-tenant trigger was deployed

do $$
declare
  v_user_id uuid;
  v_tenant_id uuid;
  v_has_profile boolean;
begin
  -- Get the user's ID
  select id into v_user_id
  from auth.users
  where email = 'ccatalan.us@gmail.com';

  if v_user_id is null then
    raise exception 'User ccatalan.us@gmail.com not found';
  end if;

  raise notice '✓ Found user ID: %', v_user_id;

  -- Check if user has a profile
  select exists(select 1 from public.user_profiles where user_id = v_user_id)
  into v_has_profile;

  if not v_has_profile then
    raise notice '⚠ User has NO profile entry - creating one';
    
    -- Check if there's an existing tenant
    select id into v_tenant_id
    from public.tenants
    where owner_email = 'ccatalan.us@gmail.com'
    order by created_at desc
    limit 1;

    if v_tenant_id is null then
      -- No tenant exists for this user, check if ANY tenant exists
      select id into v_tenant_id
      from public.tenants
      order by created_at
      limit 1;
    end if;

    if v_tenant_id is null then
      -- No tenants exist at all, create one
      insert into public.tenants (shop_name, subdomain, owner_email, plan, is_active, currency, timezone)
      values ('VinaBike', 'vinabike', 'ccatalan.us@gmail.com', 'free', true, 'CLP', 'America/Santiago')
      returning id into v_tenant_id;
      
      raise notice '✓ Created new tenant: %', v_tenant_id;
    else
      raise notice '✓ Using existing tenant: %', v_tenant_id;
    end if;

    -- Create user_profile
    insert into public.user_profiles (user_id, tenant_id, role, is_active)
    values (v_user_id, v_tenant_id, 'admin', true);
    
    raise notice '✓ Created user_profile with tenant_id: %', v_tenant_id;
  else
    -- Profile exists, check tenant_id
    select tenant_id into v_tenant_id
    from public.user_profiles
    where user_id = v_user_id;

    if v_tenant_id is null then
      raise notice '⚠ Profile exists but tenant_id is NULL - fixing';
      
      -- Find or create tenant
      select id into v_tenant_id
      from public.tenants
      where owner_email = 'ccatalan.us@gmail.com'
      order by created_at desc
      limit 1;

      if v_tenant_id is null then
        select id into v_tenant_id
        from public.tenants
        order by created_at
        limit 1;
      end if;

      if v_tenant_id is null then
        insert into public.tenants (shop_name, subdomain, owner_email, plan, is_active, currency, timezone)
        values ('VinaBike', 'vinabike', 'ccatalan.us@gmail.com', 'free', true, 'CLP', 'America/Santiago')
        returning id into v_tenant_id;
        
        raise notice '✓ Created new tenant: %', v_tenant_id;
      end if;

      -- Update profile with tenant_id
      update public.user_profiles
      set tenant_id = v_tenant_id,
          updated_at = now()
      where user_id = v_user_id;
      
      raise notice '✓ Updated profile with tenant_id: %', v_tenant_id;
    else
      raise notice '✓ User already has tenant_id: %', v_tenant_id;
    end if;
  end if;
end $$;

-- Verify the fix
select 
  '✓ FIX COMPLETE' as status,
  au.email,
  up.tenant_id,
  up.role,
  up.is_active,
  t.shop_name as tenant_name,
  t.subdomain
from auth.users au
join public.user_profiles up on up.user_id = au.id
join public.tenants t on t.id = up.tenant_id
where au.email = 'ccatalan.us@gmail.com';

