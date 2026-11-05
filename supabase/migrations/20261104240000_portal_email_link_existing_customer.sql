-- La cuenta del portal se liga por correo a la ficha que el taller ya tenía
-- (2026-11-04).
--
-- provision_current_public_store_customer liga por correo confirmado: si el
-- taller creó al cliente con su correo y después el cliente crea su cuenta,
-- la ficha queda suya. La guardia de identidad (guard_customer_identity_update)
-- no deja que nadie con sesión cambie la cuenta de una ficha, y esa
-- actualización también la frenaba: «Customer tenant and Auth identity are
-- immutable», la entrada fallaba y el portal cerraba la sesión. En producción
-- no le había pasado a nadie (9 fichas con cuenta) pero 74 fichas con correo y
-- sin cuenta iban a fallar en cuanto el cliente la creara: el dueño cuenta con
-- esa vinculación («si un cliente nos deja su email y luego se crea una
-- cuenta con el mismo email, la vinculación se hace automática»).
--
-- La función pone la misma marca privada que el QR (20261104200000) antes de
-- ligar: la guardia la acepta sólo para esta transacción y esta ficha, sin
-- cambiar de tienda. Igual que la versión de producción salvo eso.

CREATE OR REPLACE FUNCTION public.provision_current_public_store_customer(p_tenant_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  auth_user_id_value uuid := auth.uid();
  auth_email text;
  auth_metadata jsonb;
  auth_app_metadata jsonb;
  customer_id_value uuid;
  existing_customer_user_id uuid;
  existing_customer_is_active boolean;
  customer_name_value text;
  preserve_workforce_metadata boolean;
begin
  if auth_user_id_value is null or p_tenant_id is null then
    raise exception 'Authenticated customer and tenant are required'
      using errcode = '42501';
  end if;

  select
    lower(nullif(trim(auth_user.email), '')),
    coalesce(auth_user.raw_user_meta_data, '{}'::jsonb),
    coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
  into auth_email, auth_metadata, auth_app_metadata
  from auth.users auth_user
  where auth_user.id = auth_user_id_value
    and auth_user.email_confirmed_at is not null
  for update;

  if not found or auth_email is null then
    raise exception 'A confirmed Auth email is required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.tenants tenant
    where tenant.id = p_tenant_id
      and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  preserve_workforce_metadata :=
    exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = auth_user_id_value
    )
    or exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.auth_user_id = auth_user_id_value
    )
    or coalesce(auth_app_metadata->>'account_type', '') in (
      'erp_owner',
      'erp_staff',
      'worker_portal'
    )
    or coalesce(auth_app_metadata->>'role', '') in (
      'admin',
      'manager',
      'cashier',
      'mechanic',
      'accountant',
      'worker'
    );

  -- Serialize email-based linking so OAuth callbacks and auth-state retries
  -- cannot create two rows for the same customer/store pair.
  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':' || auth_email, 0)
  );

  select customer.id, customer.auth_user_id, customer.is_active
  into
    customer_id_value,
    existing_customer_user_id,
    existing_customer_is_active
  from public.customers customer
  where customer.tenant_id = p_tenant_id
    and customer.auth_user_id = auth_user_id_value
  limit 1
  for update;

  if customer_id_value is null then
    select customer.id, customer.auth_user_id, customer.is_active
    into
      customer_id_value,
      existing_customer_user_id,
      existing_customer_is_active
    from public.customers customer
    where customer.tenant_id = p_tenant_id
      and lower(customer.email) = auth_email
    limit 1
    for update;
  end if;

  if customer_id_value is not null
     and existing_customer_user_id is not null
     and existing_customer_user_id <> auth_user_id_value then
    raise exception 'Store customer email is already linked to another Auth user'
      using errcode = '23505';
  end if;

  if customer_id_value is not null
     and existing_customer_is_active is not true then
    raise exception 'Customer membership is inactive'
      using errcode = '42501';
  end if;

  customer_name_value := coalesce(
    nullif(trim(auth_metadata->>'full_name'), ''),
    nullif(trim(auth_metadata->>'name'), ''),
    split_part(auth_email, '@', 1)
  );

  if customer_id_value is null then
    insert into public.customers (
      tenant_id,
      auth_user_id,
      name,
      email,
      is_active
    )
    values (
      p_tenant_id,
      auth_user_id_value,
      customer_name_value,
      auth_email,
      true
    )
    returning id into customer_id_value;
  else
    if exists (
      select 1
      from public.customers conflicting_customer
      where conflicting_customer.tenant_id = p_tenant_id
        and lower(conflicting_customer.email) = auth_email
        and conflicting_customer.id <> customer_id_value
    ) then
      raise exception 'Store customer email resolves to conflicting rows'
        using errcode = '23505';
    end if;

    -- Ligar por correo confirmado una ficha que el taller creó antes es la
    -- otra excepción de la guardia de identidad (20261104240000): la marca la
    -- pone esta función, para esta transacción y esta ficha.
    perform set_config(
      'vinabike.portal_claim_relink',
      txid_current()::text || ':' || customer_id_value::text,
      true
    );
    update public.customers
    set auth_user_id = auth_user_id_value,
        email = auth_email,
        name = coalesce(nullif(name, ''), customer_name_value),
        updated_at = now()
    where id = customer_id_value
      and tenant_id = p_tenant_id;
    perform set_config('vinabike.portal_claim_relink', '', true);
  end if;

  update public.online_orders
  set customer_id = customer_id_value,
      updated_at = now()
  where tenant_id = p_tenant_id
    and customer_id is null
    and lower(customer_email) = auth_email;

  -- User metadata is user-editable and therefore display-only. Remove identity
  -- and authorization-shaped keys regardless of whether this is customer-only
  -- or a shared workforce/customer identity.
  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        - 'account_type'
        - 'tenant_id'
        - 'employee_id'
        - 'role'
        - 'permissions'
        - 'customer_id'
        - 'customer_tenant_id'
  where id = auth_user_id_value;

  -- A staff/worker may also shop as a customer. Customer authorization always
  -- comes from public.customers, so never replace the authoritative workforce
  -- account_type, tenant, or role claims for a shared identity.
  if preserve_workforce_metadata then
    update auth.users
    set raw_app_meta_data = coalesce(
          raw_app_meta_data,
          '{}'::jsonb
        ) || jsonb_build_object(
          'customer_memberships',
          coalesce(
            raw_app_meta_data->'customer_memberships',
            '{}'::jsonb
          ) || jsonb_build_object(
            p_tenant_id::text,
            customer_id_value
          )
        )
    where id = auth_user_id_value;
  else
    update auth.users
    set raw_app_meta_data = (
          coalesce(raw_app_meta_data, '{}'::jsonb)
          - 'tenant_id'
          - 'employee_id'
          - 'role'
          - 'permissions'
          - 'customer_id'
          - 'customer_tenant_id'
        )
          || jsonb_build_object(
            'account_type', 'public_store_customer',
            'customer_memberships',
              coalesce(
                raw_app_meta_data->'customer_memberships',
                '{}'::jsonb
              ) || jsonb_build_object(
                p_tenant_id::text,
                customer_id_value
              )
          )
    where id = auth_user_id_value;
  end if;

  return customer_id_value;
end;
$function$;
