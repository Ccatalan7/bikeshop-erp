-- FIX: Update only the handle_new_user trigger to set metadata
-- This doesn't touch the accounts table or other risky changes

create or replace function public.handle_new_user()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
  v_tenant_id uuid;
  v_invitation record;
  v_shop_name text;
  v_subdomain text;
  v_subdomain_base text;
  v_counter integer := 1;
begin
  -- Check if user was invited (has pending invitation)
  select * into v_invitation
  from user_invitations
  where email = new.email
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if found then
    -- ========================================================================
    -- SCENARIO: User was invited → Join existing tenant
    -- ========================================================================
    v_tenant_id := v_invitation.tenant_id;
    
    -- Create user_profile entry linking user to tenant
    insert into user_profiles (user_id, tenant_id, role, is_active)
    values (new.id, v_tenant_id, v_invitation.role, true);
    
    -- Update user metadata to include tenant_id and role
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
      'tenant_id', v_tenant_id,
      'role', v_invitation.role
    )
    where id = new.id;
    
    -- Mark invitation as accepted
    update user_invitations
    set status = 'accepted', accepted_at = now()
    where id = v_invitation.id;
    
    raise notice 'User % joined tenant % via invitation', new.email, v_tenant_id;
  else
    -- ========================================================================
    -- SCENARIO: No invitation → Create new tenant (new business owner)
    -- ========================================================================
    
    -- Extract shop name from signup data or email
    v_shop_name := coalesce(
      new.raw_user_meta_data->>'shop_name',
      split_part(new.email, '@', 1) || '''s Shop'
    );
    
    -- Generate base subdomain from shop name or email
    v_subdomain_base := coalesce(
      new.raw_user_meta_data->>'subdomain',
      lower(regexp_replace(split_part(new.email, '@', 1), '[^a-z0-9]', '', 'g'))
    );
    
    v_subdomain := v_subdomain_base;
    
    -- Handle duplicate subdomains by appending counter
    while exists (select 1 from tenants where subdomain = v_subdomain) loop
      v_subdomain := v_subdomain_base || v_counter;
      v_counter := v_counter + 1;
      
      -- Prevent infinite loop
      if v_counter > 100 then
        raise exception 'Could not generate unique subdomain for %', new.email;
      end if;
    end loop;
    
    -- Create new tenant
    insert into tenants (shop_name, subdomain, owner_email, plan, is_active, currency, timezone)
    values (
      v_shop_name,
      v_subdomain,
      new.email,
      'free',  -- Start with free plan
      true,
      'CLP',
      'America/Santiago'
    )
    returning id into v_tenant_id;
    
    -- Create user_profile entry linking user to tenant as admin
    insert into user_profiles (user_id, tenant_id, role, is_active)
    values (new.id, v_tenant_id, 'admin', true);
    
    -- Update user metadata to include tenant_id and role
    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
      'tenant_id', v_tenant_id,
      'role', 'admin'
    )
    where id = new.id;
    
    raise notice 'Created new tenant % for user % with subdomain %', v_tenant_id, new.email, v_subdomain;
  end if;

  return new;
end;
$$;
