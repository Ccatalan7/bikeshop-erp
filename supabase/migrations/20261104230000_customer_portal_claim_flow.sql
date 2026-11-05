-- El QR de la cuenta en segundos (2026-11-04).
--
-- El dueño: «lo importante es que el flujo de creación de cliente sea
-- extremadamente intuitivo y fácil… que pueda leer el QR y en cosa de
-- segundos tenga creada la cuenta. Si no, no la usarán». La página del QR
-- (`/cuenta/vincular`) necesita tres cosas que 20261104200000 no tenía:
--
-- 1. Saludar antes de pedir nada: `peek_customer_portal_claim_code_v1` dice,
--    a quien tiene el código y sin cuenta, si sirve, el nombre de pila y qué
--    bici es. Nada más: ni teléfono ni correo. Adivinar un código (256 bits)
--    no es posible, así que no necesita sesión.
-- 2. Ligar aunque el correo se confirme en otro navegador: quien crea la
--    cuenta con correo deja el código en sus metadatos
--    (`vinabike_claim_code`, `vinabike_claim_phone`); la tienda llama a
--    `claim_customer_portal_code_v1` sin código al entrar y la base lo toma
--    de ahí, lo comprueba como cualquier otro y lo borra. Con Google no hace
--    falta: vuelve al mismo navegador.
-- 3. El ERP dibuja el QR de la recepción: `issue_customer_portal_claim_code_v1`
--    devuelve además la dirección de la tienda (`store_url` del editor) y el
--    nombre de pila.

-- El nombre de pila para saludar: la primera palabra, sin gritar.
create or replace function public.customer_first_name_internal(p_name text)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case
    when first_word is null then null
    when first_word = upper(first_word) and length(first_word) > 1
      then upper(left(first_word, 1)) || lower(substr(first_word, 2))
    else first_word
  end
    from (
      select nullif(split_part(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), ' ', 1), '')
        as first_word
    ) name_parts;
$$;

revoke all on function public.customer_first_name_internal(text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Lo que ve quien abre el QR, antes de tener cuenta
-- ---------------------------------------------------------------------------

create or replace function public.peek_customer_portal_claim_code_v1(
  p_tenant_id uuid,
  p_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_code public.customer_portal_claim_codes%rowtype;
  v_customer public.customers%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_bike text;
begin
  if p_tenant_id is null
     or length(coalesce(p_code, '')) < 40
     or length(p_code) > 128 then
    return jsonb_build_object('status', 'invalid');
  end if;

  select * into v_code
    from public.customer_portal_claim_codes code
   where code.tenant_id = p_tenant_id
     and code.code_sha256 = encode(extensions.digest(convert_to(p_code, 'UTF8'), 'sha256'), 'hex');
  if not found or v_code.revoked_at is not null then
    return jsonb_build_object('status', 'invalid');
  end if;

  select * into v_customer
    from public.customers
   where id = v_code.customer_id
     and tenant_id = p_tenant_id;
  if not found or v_customer.is_active is not true then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_customer.auth_user_id is not null then
    -- Ya tiene cuenta: que entre. No se dice cuál.
    return jsonb_build_object('status', 'linked');
  end if;
  if v_code.expires_at <= clock_timestamp() then
    return jsonb_build_object('status', 'expired');
  end if;

  select * into v_job
    from public.mechanic_jobs
   where id = v_code.job_id
     and tenant_id = p_tenant_id;

  select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
    into v_bike
    from public.mechanic_job_bikes job_bike
    join public.bikes bike
      on bike.id = job_bike.bike_id
     and bike.tenant_id = job_bike.tenant_id
   where job_bike.tenant_id = p_tenant_id
     and job_bike.job_id = v_code.job_id
   order by job_bike.order_index, job_bike.created_at
   limit 1;
  if v_bike is null and v_job.bike_id is not null then
    select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
      into v_bike
      from public.bikes bike
     where bike.id = v_job.bike_id
       and bike.tenant_id = p_tenant_id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'status', 'valid',
    'first_name', public.customer_first_name_internal(v_customer.name),
    'purpose', v_code.purpose,
    'job_number', v_job.job_number,
    'bike', v_bike,
    'delivered', coalesce(v_job.status = 'ENTREGADO' or v_job.delivered_at is not null, false),
    'expires_at', v_code.expires_at
  ));
end;
$$;

revoke all on function public.peek_customer_portal_claim_code_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.peek_customer_portal_claim_code_v1(uuid, text)
  to anon, authenticated, service_role;

comment on function public.peek_customer_portal_claim_code_v1(uuid, text) is
  'Quien abre el QR, antes de tener cuenta: si el código sirve, el nombre de pila y qué bici es. Sin teléfono ni correo.';

-- ---------------------------------------------------------------------------
-- 2. El código del ERP, con la dirección de la tienda y el nombre de pila
-- ---------------------------------------------------------------------------

-- Igual que 20261104200000 salvo `store_url` y `customer_first_name`.
create or replace function public.issue_customer_portal_claim_code_v1(
  p_job_id uuid,
  p_purpose text default 'reception'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_raw text;
  v_expires timestamptz := clock_timestamp() + interval '120 days';
begin
  if p_purpose is null or p_purpose not in ('reception', 'delivery', 'manual') then
    raise exception 'Invalid claim-code purpose' using errcode = '22023';
  end if;

  select * into v_job from public.mechanic_jobs where id = p_job_id;
  if not found or not public.is_active_tenant_member(v_job.tenant_id) then
    raise exception 'Job not found or not accessible' using errcode = 'P0002';
  end if;

  select * into v_customer
    from public.customers
   where id = v_job.customer_id
     and tenant_id = v_job.tenant_id;
  if not found or v_customer.is_active is not true then
    return jsonb_build_object('status', 'no_customer');
  end if;
  if v_customer.auth_user_id is not null then
    return jsonb_build_object('status', 'already_linked');
  end if;

  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_portal_claim_codes (
    tenant_id, customer_id, job_id, purpose, code_sha256, expires_at, created_by
  ) values (
    v_job.tenant_id,
    v_customer.id,
    v_job.id,
    p_purpose,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    v_expires,
    auth.uid()
  );

  return jsonb_build_object(
    'status', 'issued',
    'code', v_raw,
    'expires_at', v_expires,
    -- Adonde lleva el QR y a quién saluda: lo que el ERP dibuja en la
    -- recepción, de la misma regla que el comprobante.
    'store_url', (
      select nullif(btrim(setting.value), '')
        from public.website_settings setting
       where setting.tenant_id = v_job.tenant_id
         and setting.key = 'store_url'
    ),
    'customer_first_name', public.customer_first_name_internal(v_customer.name)
  );
end;
$$;

revoke all on function public.issue_customer_portal_claim_code_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.issue_customer_portal_claim_code_v1(uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Ligar con el código o con el que dejó pendiente la cuenta
-- ---------------------------------------------------------------------------

-- Igual que 20261104200000 salvo: sin código toma el pendiente de los
-- metadatos de la propia cuenta (y si no hay, `nothing_pending`, sin contar
-- como intento); el pendiente se borra apenas se usa, sirva o no; y lo ligado
-- devuelve el trabajo y el nombre de pila para la bienvenida.
create or replace function public.claim_customer_portal_code_v1(
  p_tenant_id uuid,
  p_code text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_code public.customer_portal_claim_codes%rowtype;
  v_customer public.customers%rowtype;
  v_current public.customers%rowtype;
  v_has_current boolean := false;
  v_code_text text := nullif(trim(p_code), '');
  v_phone_text text := nullif(trim(p_phone), '');
  v_pending jsonb;
  v_typed_digits text;
  v_record_digits text;
  v_failures integer;
  v_outcome text;
begin
  if v_uid is null then
    raise exception 'claim_account_required' using errcode = '42501';
  end if;

  -- Sin código, el que dejó pendiente la propia cuenta al crearse desde el
  -- QR (`vinabike_claim_code` en sus metadatos): así se liga aunque confirme
  -- el correo en otro navegador. Sigue siendo un código que se comprueba.
  if v_code_text is null then
    select coalesce(auth_user.raw_user_meta_data, '{}'::jsonb) into v_pending
      from auth.users auth_user
     where auth_user.id = v_uid;
    v_code_text := nullif(trim(v_pending ->> 'vinabike_claim_code'), '');
    v_phone_text := coalesce(v_phone_text, nullif(trim(v_pending ->> 'vinabike_claim_phone'), ''));
    if v_code_text is null then
      return jsonb_build_object('status', 'nothing_pending');
    end if;
  end if;
  v_typed_digits := regexp_replace(coalesce(v_phone_text, ''), '[^0-9]', '', 'g');

  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'A confirmed Auth email is required' using errcode = '42501';
  end if;

  select count(*) into v_failures
    from public.customer_portal_claim_attempts attempt
   where attempt.auth_user_id = v_uid
     and attempt.attempted_at > clock_timestamp() - interval '1 hour'
     and attempt.outcome not in ('linked', 'already_yours');
  if v_failures >= 10 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;

  if length(v_code_text) < 40 or length(v_code_text) > 128 then
    v_outcome := 'invalid';
  else
    select * into v_code
      from public.customer_portal_claim_codes code
     where code.tenant_id = p_tenant_id
       and code.code_sha256 = encode(extensions.digest(convert_to(v_code_text, 'UTF8'), 'sha256'), 'hex')
     for update;
    if not found or v_code.revoked_at is not null then
      v_outcome := 'invalid';
    elsif v_code.expires_at <= clock_timestamp() then
      v_outcome := 'expired';
    end if;
  end if;

  if v_outcome is null then
    select * into v_customer
      from public.customers
     where id = v_code.customer_id
       and tenant_id = p_tenant_id
     for update;
    if not found or v_customer.is_active is not true then
      v_outcome := 'invalid';
    elsif v_customer.auth_user_id = v_uid then
      v_outcome := 'already_yours';
    elsif v_customer.auth_user_id is not null then
      v_outcome := 'linked_elsewhere';
    else
      v_record_digits := regexp_replace(coalesce(v_customer.phone, ''), '[^0-9]', '', 'g');
      if length(v_record_digits) >= 8
         and (length(v_typed_digits) < 8
              or right(v_typed_digits, 8) <> right(v_record_digits, 8)) then
        v_outcome := 'phone_mismatch';
      end if;
    end if;
  end if;

  if v_outcome is null then
    -- Al crear la cuenta el portal ya pudo dejarle una ficha propia, vacía:
    -- se suelta y se archiva para que la cuenta quede con la del taller.
    select * into v_current
      from public.customers
     where tenant_id = p_tenant_id
       and auth_user_id = v_uid
     for update;
    v_has_current := found;
    -- Todo lo que apunta a una ficha de cliente, salvo sus direcciones (que
    -- se copian): si la ficha propia tiene algo, no se archiva sola.
    if v_has_current and (
      exists (select 1 from public.mechanic_jobs job
               where job.tenant_id = p_tenant_id and job.customer_id = v_current.id)
      or exists (select 1 from public.sales_invoices invoice
                  where invoice.tenant_id = p_tenant_id and invoice.customer_id = v_current.id)
      or exists (select 1 from public.online_orders online_order
                  where online_order.tenant_id = p_tenant_id and online_order.customer_id = v_current.id)
      or exists (select 1 from public.bikes bike
                  where bike.tenant_id = p_tenant_id and bike.customer_id = v_current.id)
      or exists (select 1 from public.customer_quotes quote
                  where quote.tenant_id = p_tenant_id and quote.customer_id = v_current.id)
      or exists (select 1 from public.sales_orders sales_order
                  where sales_order.tenant_id = p_tenant_id and sales_order.customer_id = v_current.id)
      or exists (select 1 from public.orders legacy_order
                  where legacy_order.tenant_id = p_tenant_id and legacy_order.customer_id = v_current.id)
      or exists (select 1 from public.work_orders work_order
                  where work_order.tenant_id = p_tenant_id and work_order.customer_id = v_current.id)
      or exists (select 1 from public.vehicles vehicle
                  where vehicle.tenant_id = p_tenant_id and vehicle.customer_id = v_current.id)
      or exists (select 1 from public.loyalty loyalty_row
                  where loyalty_row.tenant_id = p_tenant_id and loyalty_row.customer_id = v_current.id)
      or exists (select 1 from public.smart_tasks task
                  where task.tenant_id = p_tenant_id and task.linked_customer_id = v_current.id)
      or exists (select 1 from public.whatsapp_conversation_bindings binding
                  where binding.tenant_id = p_tenant_id and binding.customer_id = v_current.id)
      or exists (select 1 from public.workshop_legacy_asset_copies legacy_copy
                  where legacy_copy.tenant_id = p_tenant_id and legacy_copy.customer_id = v_current.id)
    ) then
      v_outcome := 'account_has_history';
    end if;
  end if;

  if v_outcome is null and exists (
    select 1 from public.customers other
     where other.tenant_id = p_tenant_id
       and other.id <> v_customer.id
       and (not v_has_current or other.id <> v_current.id)
       and lower(other.email) = v_email
  ) then
    v_outcome := 'email_in_other_record';
  end if;

  if v_outcome is not null then
    insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
    values (p_tenant_id, v_uid, v_outcome);
    -- Un código pendiente se usa una vez: si no sirvió, se vuelve a escanear.
    update auth.users
       set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
         - 'vinabike_claim_code' - 'vinabike_claim_phone'
     where id = v_uid
       and coalesce(raw_user_meta_data, '{}'::jsonb) ?| array['vinabike_claim_code', 'vinabike_claim_phone'];
    return jsonb_build_object('status', v_outcome);
  end if;

  if v_has_current then
    -- Lo que alcanzó a guardar en su ficha vacía (direcciones) se copia: la
    -- identidad de una dirección no cambia de cliente
    -- (`guard_customer_address_identity_update`). La principal sigue siendo
    -- principal sólo si la ficha del taller no tenía ninguna.
    insert into public.customer_addresses (
      tenant_id, customer_id, label, recipient_name, phone, street_address,
      street_number, apartment, comuna, city, region, postal_code,
      additional_info, is_default
    )
    select address.tenant_id, v_customer.id, address.label, address.recipient_name,
           address.phone, address.street_address, address.street_number,
           address.apartment, address.comuna, address.city, address.region,
           address.postal_code, address.additional_info,
           address.is_default and not exists (
             select 1 from public.customer_addresses existing
              where existing.tenant_id = p_tenant_id
                and existing.customer_id = v_customer.id
           )
      from public.customer_addresses address
     where address.tenant_id = p_tenant_id
       and address.customer_id = v_current.id;
    perform set_config(
      'vinabike.portal_claim_relink',
      txid_current()::text || ':' || v_current.id::text,
      true
    );
    update public.customers
       set auth_user_id = null,
           email = null,
           is_active = false,
           notes = concat_ws(
             E'\n',
             nullif(notes, ''),
             format('Cuenta del portal unida a la ficha %s con el QR (%s).',
                    v_customer.id, to_char(clock_timestamp(), 'YYYY-MM-DD'))
           ),
           updated_at = clock_timestamp()
     where id = v_current.id
       and tenant_id = p_tenant_id;
  end if;

  perform set_config(
    'vinabike.portal_claim_relink',
    txid_current()::text || ':' || v_customer.id::text,
    true
  );
  update public.customers
     set auth_user_id = v_uid,
         email = v_email,
         phone = coalesce(nullif(trim(phone), ''), v_phone_text),
         notes = case
           when nullif(trim(email), '') is null or lower(trim(email)) = v_email then notes
           else concat_ws(
             E'\n',
             nullif(notes, ''),
             format('Correo anterior a la cuenta del portal: %s (%s).',
                    trim(email), to_char(clock_timestamp(), 'YYYY-MM-DD'))
           )
         end,
         updated_at = clock_timestamp()
   where id = v_customer.id
     and tenant_id = p_tenant_id;
  perform set_config('vinabike.portal_claim_relink', '', true);

  -- La membresía de la cuenta (app_metadata) y los pedidos web de su correo
  -- los pone el mismo camino de siempre.
  perform public.provision_current_public_store_customer(p_tenant_id);

  update public.customer_portal_claim_codes
     set claimed_at = clock_timestamp(),
         claimed_by = v_uid
   where tenant_id = p_tenant_id
     and customer_id = v_customer.id
     and claimed_at is null
     and revoked_at is null;

  insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
  values (p_tenant_id, v_uid, 'linked');
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
       - 'vinabike_claim_code' - 'vinabike_claim_phone'
   where id = v_uid
     and coalesce(raw_user_meta_data, '{}'::jsonb) ?| array['vinabike_claim_code', 'vinabike_claim_phone'];

  return jsonb_build_object(
    'status', 'linked',
    'customer_id', v_customer.id,
    'job_id', v_code.job_id,
    'purpose', v_code.purpose,
    'first_name', public.customer_first_name_internal(v_customer.name)
  );
end;
$$;

revoke all on function public.claim_customer_portal_code_v1(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_customer_portal_code_v1(uuid, text, text)
  to authenticated, service_role;

comment on function public.claim_customer_portal_code_v1(uuid, text, text) is
  'El cliente con cuenta usa el código del QR (o el que dejó pendiente al crearla): su cuenta queda ligada a su ficha del taller, con teléfono que calce si la ficha lo tiene.';
