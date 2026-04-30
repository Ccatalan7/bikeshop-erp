-- Prevent public storefront customer signups from creating ERP tenant accounts.
-- Public customers are linked to the detected storefront tenant through customers.auth_user_id.

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
  v_customer_id uuid;
begin
  -- Public storefront customers are not ERP tenant owners. They belong to the
  -- detected storefront tenant and get a customer profile only.
  if coalesce(new.raw_user_meta_data->>'account_type', '') = 'public_store_customer' then
    begin
      v_tenant_id := nullif(new.raw_user_meta_data->>'customer_tenant_id', '')::uuid;
    exception
      when others then
        raise exception 'Invalid customer_tenant_id for public customer signup';
    end;

    if v_tenant_id is null or not exists (
      select 1 from tenants where id = v_tenant_id and is_active = true
    ) then
      raise exception 'Invalid or inactive storefront tenant for public customer signup';
    end if;

    select id into v_customer_id
    from customers
    where tenant_id = v_tenant_id
      and lower(email) = lower(new.email)
    limit 1;

    if v_customer_id is null then
      insert into customers (
        tenant_id,
        auth_user_id,
        name,
        email,
        phone,
        is_active
      ) values (
        v_tenant_id,
        new.id,
        coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)),
        new.email,
        nullif(new.raw_user_meta_data->>'phone', ''),
        true
      )
      returning id into v_customer_id;
    else
      update customers
      set auth_user_id = new.id,
          name = coalesce(nullif(new.raw_user_meta_data->>'name', ''), name),
          phone = coalesce(nullif(new.raw_user_meta_data->>'phone', ''), phone),
          is_active = true,
          updated_at = now()
      where id = v_customer_id;
    end if;

    update online_orders
    set customer_id = v_customer_id,
        updated_at = now()
    where tenant_id = v_tenant_id
      and customer_id is null
      and lower(customer_email) = lower(new.email);

    update auth.users
    set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
      'customer_id', v_customer_id,
      'customer_tenant_id', v_tenant_id,
      'role', 'customer'
    )
    where id = new.id;

    raise notice 'Created public storefront customer % for tenant %', new.email, v_tenant_id;
    return new;
  end if;

  -- Check if user was invited (has pending invitation)
  -- Use LOWER() for case-insensitive email matching
  select * into v_invitation
  from user_invitations
  where lower(email) = lower(new.email)
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if found then
    -- SCENARIO: User was invited: join existing tenant.
    v_tenant_id := v_invitation.tenant_id;

    begin
      insert into user_profiles (user_id, tenant_id, role, is_active, permissions)
      values (new.id, v_tenant_id, v_invitation.role, true,
        case v_invitation.role
          when 'admin' then '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
          when 'manager' then '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
          when 'cashier' then '{"access_pos": true, "create_invoices": true, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb
          when 'accountant' then '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": true, "manage_users": false, "edit_settings": false}'::jsonb
          when 'mechanic' then '{"access_pos": false, "create_invoices": false, "edit_prices": false, "delete_invoices": false, "access_accounting": false, "manage_users": false, "edit_settings": false}'::jsonb
          else '{}'::jsonb
        end
      );
    exception
      when others then
        raise exception 'Failed to create user_profile: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;

    begin
      update auth.users
      set
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
          'tenant_id', v_tenant_id,
          'role', v_invitation.role
        ),
        email_confirmed_at = now()
      where id = new.id;
    exception
      when others then
        raise warning 'Failed to update user metadata: %', SQLERRM;
    end;

    begin
      update user_invitations
      set status = 'accepted', accepted_at = now()
      where id = v_invitation.id;
    exception
      when others then
        raise warning 'Failed to mark invitation as accepted: %', SQLERRM;
    end;
  else
    -- SCENARIO: No invitation: create new ERP tenant owner.
    v_shop_name := coalesce(
      new.raw_user_meta_data->>'shop_name',
      split_part(new.email, '@', 1) || '''s Shop'
    );

    v_subdomain_base := coalesce(
      new.raw_user_meta_data->>'subdomain',
      lower(regexp_replace(split_part(new.email, '@', 1), '[^a-z0-9]', '', 'g'))
    );

    v_subdomain := v_subdomain_base;

    while exists (select 1 from tenants where subdomain = v_subdomain) loop
      v_subdomain := v_subdomain_base || v_counter;
      v_counter := v_counter + 1;

      if v_counter > 100 then
        raise exception 'Could not generate unique subdomain for %', new.email;
      end if;
    end loop;

    begin
      insert into tenants (shop_name, subdomain, owner_email, plan, is_active, currency, timezone)
      values (
        v_shop_name,
        v_subdomain,
        new.email,
        'free',
        true,
        'CLP',
        'America/Santiago'
      )
      returning id into v_tenant_id;
    exception
      when others then
        raise exception 'Failed to create tenant: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;

    begin
      insert into user_profiles (user_id, tenant_id, role, is_active, permissions)
      values (new.id, v_tenant_id, 'admin', true,
        '{"access_pos": true, "create_invoices": true, "edit_prices": true, "delete_invoices": true, "access_accounting": true, "manage_users": true, "edit_settings": true}'::jsonb
      );
    exception
      when others then
        raise exception 'Failed to create user_profile for new tenant: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    end;

    begin
      update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
        'tenant_id', v_tenant_id,
        'role', 'admin'
      )
      where id = new.id;
    exception
      when others then
        raise warning 'Failed to update user metadata: %', SQLERRM;
    end;
  end if;

  return new;
end;
$$;
