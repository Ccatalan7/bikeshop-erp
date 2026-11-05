-- El teléfono también liga la cuenta del portal (2026-11-05).
--
-- El dueño: «lo único que faltaría agregar es que la vinculación sea
-- automática también por número de teléfono. Bidireccional». De las 1.800
-- fichas activas de la tienda, 536 tienen teléfono y 83 correo: el correo ya
-- liga solo (20261104240000), pero casi nadie lo dejó. Ligar por un teléfono
-- que cualquiera puede escribir le mostraría a un extraño los trabajos, la
-- bici y las facturas de otro; por eso el teléfono se confirma antes con un
-- código por WhatsApp (plantilla de autenticación `codigo_verificacion_v1`)
-- y recién entonces liga:
--
-- 1. La cuenta pide el código: `start_customer_phone_verification_internal`,
--    que sólo llama la función `customer-phone-verification` (la que lo manda
--    por WhatsApp). Seis dígitos, 10 minutos, guardado como hash, con límites
--    por cuenta y por número para que nadie llene de mensajes un teléfono
--    ajeno.
-- 2. La cuenta escribe el código: `confirm_customer_phone_verification_v1`.
--    Cinco intentos. El teléfono queda verificado para esa cuenta y, si una
--    sola ficha del taller sin cuenta tiene ese número, la cuenta queda con
--    ella: el mismo paso que el QR (`link_portal_account_to_customer_internal`,
--    que desde aquí usan los dos).
-- 3. Al revés: si el taller crea la ficha después, el portal la liga al
--    entrar (`customer_portal_phone_state_v1`), con el teléfono ya verificado.
--
-- Se enciende por tienda (`customer_portal_phone_verification_enabled` en
-- company_settings) desde Configuración › WhatsApp, cuando Meta ya aprobó la
-- plantilla: antes, cada código saldría y Meta lo rechazaría.

-- ---------------------------------------------------------------------------
-- 1. Lo que el QR ya hacía, en un solo lugar
-- ---------------------------------------------------------------------------

-- Todo lo que apunta a una ficha de cliente, salvo sus direcciones (que se
-- copian al ligar): con algo de esto, la ficha propia de una cuenta no se
-- archiva sola. Lo mismo que revisaba claim_customer_portal_code_v1.
create or replace function public.customer_has_portal_history_internal(
  p_tenant_id uuid,
  p_customer_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.mechanic_jobs job
                  where job.tenant_id = p_tenant_id and job.customer_id = p_customer_id)
      or exists (select 1 from public.sales_invoices invoice
                  where invoice.tenant_id = p_tenant_id and invoice.customer_id = p_customer_id)
      or exists (select 1 from public.online_orders online_order
                  where online_order.tenant_id = p_tenant_id and online_order.customer_id = p_customer_id)
      or exists (select 1 from public.bikes bike
                  where bike.tenant_id = p_tenant_id and bike.customer_id = p_customer_id)
      or exists (select 1 from public.customer_quotes quote
                  where quote.tenant_id = p_tenant_id and quote.customer_id = p_customer_id)
      or exists (select 1 from public.sales_orders sales_order
                  where sales_order.tenant_id = p_tenant_id and sales_order.customer_id = p_customer_id)
      or exists (select 1 from public.orders legacy_order
                  where legacy_order.tenant_id = p_tenant_id and legacy_order.customer_id = p_customer_id)
      or exists (select 1 from public.work_orders work_order
                  where work_order.tenant_id = p_tenant_id and work_order.customer_id = p_customer_id)
      or exists (select 1 from public.vehicles vehicle
                  where vehicle.tenant_id = p_tenant_id and vehicle.customer_id = p_customer_id)
      or exists (select 1 from public.loyalty loyalty_row
                  where loyalty_row.tenant_id = p_tenant_id and loyalty_row.customer_id = p_customer_id)
      or exists (select 1 from public.smart_tasks task
                  where task.tenant_id = p_tenant_id and task.linked_customer_id = p_customer_id)
      or exists (select 1 from public.whatsapp_conversation_bindings binding
                  where binding.tenant_id = p_tenant_id and binding.customer_id = p_customer_id)
      or exists (select 1 from public.workshop_legacy_asset_copies legacy_copy
                  where legacy_copy.tenant_id = p_tenant_id and legacy_copy.customer_id = p_customer_id);
$$;

revoke all on function public.customer_has_portal_history_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- La cuenta [p_uid] (correo confirmado [p_email], en minúsculas) queda con la
-- ficha del taller [p_customer_id]: la ficha vacía que el portal le había
-- dejado se suelta y se archiva, sus direcciones se copian y la ficha del
-- taller toma la cuenta y el correo. Devuelve null si quedó ligada, o por qué
-- no (`invalid`, `already_yours`, `linked_elsewhere`, `account_has_history`,
-- `email_in_other_record`). [p_how] va en la nota de la ficha archivada
-- («con el QR», «con su teléfono verificado»). Sólo para la cuenta de la
-- sesión: la membresía la pone provision_current_public_store_customer, que
-- lee auth.uid().
create or replace function public.link_portal_account_to_customer_internal(
  p_tenant_id uuid,
  p_uid uuid,
  p_email text,
  p_customer_id uuid,
  p_phone text,
  p_how text
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
  v_current public.customers%rowtype;
  v_has_current boolean := false;
begin
  if p_uid is null or p_uid is distinct from auth.uid() or p_email is null then
    raise exception 'portal_link_session_required' using errcode = '42501';
  end if;

  select * into v_customer
    from public.customers
   where id = p_customer_id
     and tenant_id = p_tenant_id
   for update;
  if not found or v_customer.is_active is not true then
    return 'invalid';
  elsif v_customer.auth_user_id = p_uid then
    return 'already_yours';
  elsif v_customer.auth_user_id is not null then
    return 'linked_elsewhere';
  end if;

  -- Al crear la cuenta el portal ya pudo dejarle una ficha propia, vacía: se
  -- suelta y se archiva para que la cuenta quede con la del taller.
  select * into v_current
    from public.customers
   where tenant_id = p_tenant_id
     and auth_user_id = p_uid
   for update;
  v_has_current := found;
  if v_has_current
     and public.customer_has_portal_history_internal(p_tenant_id, v_current.id) then
    return 'account_has_history';
  end if;

  if exists (
    select 1 from public.customers other
     where other.tenant_id = p_tenant_id
       and other.id <> v_customer.id
       and (not v_has_current or other.id <> v_current.id)
       and lower(other.email) = p_email
  ) then
    return 'email_in_other_record';
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
             format('Cuenta del portal unida a la ficha %s %s (%s).',
                    v_customer.id, p_how, to_char(clock_timestamp(), 'YYYY-MM-DD'))
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
     set auth_user_id = p_uid,
         email = p_email,
         phone = coalesce(nullif(trim(phone), ''), nullif(trim(p_phone), '')),
         notes = case
           when nullif(trim(email), '') is null or lower(trim(email)) = p_email then notes
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
  return null;
end;
$$;

revoke all on function public.link_portal_account_to_customer_internal(uuid, uuid, text, uuid, text, text)
  from public, anon, authenticated, service_role;

-- El QR, igual que en 20261104230000: lo que liga ahora lo hace el paso
-- compartido. Mismas respuestas, en el mismo orden.
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
    v_outcome := public.link_portal_account_to_customer_internal(
      p_tenant_id, v_uid, v_email, v_customer.id, v_phone_text, 'con el QR'
    );
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

-- ---------------------------------------------------------------------------
-- 2. El teléfono verificado
-- ---------------------------------------------------------------------------

-- Cada código pedido. El código nunca se guarda: sólo su hash con el id.
create table if not exists public.customer_portal_phone_verifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  phone_digits text not null check (phone_digits ~ '^[0-9]{10,15}$'),
  code_sha256 text not null check (code_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts between 0 and 5),
  send_outcome text check (send_outcome in ('sent', 'failed')),
  sent_at timestamptz,
  provider_message_id text,
  send_error text,
  confirmed_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists customer_portal_phone_verifications_account_idx
  on public.customer_portal_phone_verifications (tenant_id, auth_user_id, created_at desc);
create index if not exists customer_portal_phone_verifications_phone_idx
  on public.customer_portal_phone_verifications (tenant_id, phone_digits, created_at desc);

alter table public.customer_portal_phone_verifications enable row level security;
revoke all on table public.customer_portal_phone_verifications from anon, authenticated;
grant all on table public.customer_portal_phone_verifications to service_role;

comment on table public.customer_portal_phone_verifications is
  'Códigos por WhatsApp para confirmar el teléfono de una cuenta del portal (20261105010000). Sólo el hash; nadie los lee desde la app.';

-- El teléfono que cada cuenta confirmó, por tienda.
create table if not exists public.customer_portal_verified_phones (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  phone_digits text not null check (phone_digits ~ '^[0-9]{10,15}$'),
  verified_at timestamptz not null default clock_timestamp(),
  primary key (tenant_id, auth_user_id)
);

alter table public.customer_portal_verified_phones enable row level security;
revoke all on table public.customer_portal_verified_phones from anon, authenticated;
grant all on table public.customer_portal_verified_phones to service_role;

comment on table public.customer_portal_verified_phones is
  'El teléfono que una cuenta del portal confirmó con un código por WhatsApp: con él se liga a su ficha del taller (20261105010000).';

-- «+56 9 1234 5678» para guardar en una ficha; «+56 9 •••• 5678» para decir
-- adónde se mandó el código sin mostrar el número entero.
create or replace function public.customer_phone_display_internal(
  p_digits text,
  p_masked boolean default false
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_digits is null then null
    when p_digits ~ '^569[0-9]{8}$' then
      '+56 9 ' || case when p_masked then '••••' else substr(p_digits, 4, 4) end
        || ' ' || right(p_digits, 4)
    else
      '+' || case when p_masked
        then left(p_digits, 2) || ' •••• ' || right(p_digits, 4)
        else p_digits
      end
  end;
$$;

revoke all on function public.customer_phone_display_internal(text, boolean)
  from public, anon, authenticated, service_role;

-- El número que se puede confirmar, como lo guarda WhatsApp, o null: un móvil
-- chileno (569 y ocho dígitos) o uno extranjero de 10 a 15 dígitos.
create or replace function public.customer_verifiable_phone_internal(p_phone text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when digits is null then null
    when digits like '56%' then case when digits ~ '^569[0-9]{8}$' then digits end
    when digits ~ '^[1-9][0-9]{9,14}$' then digits
  end
  from (select public.normalize_whatsapp_phone(p_phone) as digits) normalized;
$$;

revoke all on function public.customer_verifiable_phone_internal(text)
  from public, anon, authenticated, service_role;

-- La tienda encendió la confirmación del teléfono (Configuración › WhatsApp).
create or replace function public.customer_phone_verification_enabled_internal(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select trim(setting.value) = 'true'
      from public.company_settings setting
     where setting.tenant_id = p_tenant_id
       and setting.key = 'customer_portal_phone_verification_enabled'
     limit 1
  ), false);
$$;

revoke all on function public.customer_phone_verification_enabled_internal(uuid)
  from public, anon, authenticated, service_role;

-- Un código nuevo para [p_auth_user_id]. Sólo la función que lo manda por
-- WhatsApp: el código no vuelve a nadie más. Respuestas: `issued` (con el
-- código, el número y el id), `disabled`, `invalid_phone`, `too_soon`
-- (`retry_after_seconds`) y `too_many_requests`.
create or replace function public.start_customer_phone_verification_internal(
  p_tenant_id uuid,
  p_auth_user_id uuid,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_digits text := public.customer_verifiable_phone_internal(p_phone);
  v_id uuid := gen_random_uuid();
  v_code text;
  v_last timestamptz;
  v_by_account integer;
  v_by_phone integer;
begin
  if p_tenant_id is null or p_auth_user_id is null then
    raise exception 'phone_verification_account_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from auth.users auth_user
     where auth_user.id = p_auth_user_id
       and auth_user.email_confirmed_at is not null
  ) or not exists (
    select 1 from public.tenants tenant
     where tenant.id = p_tenant_id
       and tenant.is_active is true
  ) then
    raise exception 'phone_verification_account_required' using errcode = '42501';
  end if;
  if not public.customer_phone_verification_enabled_internal(p_tenant_id) then
    return jsonb_build_object('status', 'disabled');
  end if;
  if v_digits is null then
    return jsonb_build_object('status', 'invalid_phone');
  end if;

  -- Uno por cuenta a la vez: el siguiente, pasado el minuto.
  perform pg_advisory_xact_lock(
    hashtextextended('customer-phone-verification:' || p_tenant_id::text || ':' || p_auth_user_id::text, 0)
  );
  select max(created_at), count(*)
    into v_last, v_by_account
    from public.customer_portal_phone_verifications verification
   where verification.tenant_id = p_tenant_id
     and verification.auth_user_id = p_auth_user_id
     and verification.created_at > clock_timestamp() - interval '24 hours';
  if v_last > clock_timestamp() - interval '60 seconds' then
    return jsonb_build_object(
      'status', 'too_soon',
      'retry_after_seconds',
      greatest(ceil(extract(epoch from (v_last + interval '60 seconds' - clock_timestamp())))::integer, 1)
    );
  end if;
  select count(*) into v_by_phone
    from public.customer_portal_phone_verifications verification
   where verification.tenant_id = p_tenant_id
     and verification.phone_digits = v_digits
     and verification.created_at > clock_timestamp() - interval '24 hours';
  if v_by_account >= 5 or v_by_phone >= 5 then
    return jsonb_build_object('status', 'too_many_requests');
  end if;

  -- Un código nuevo retira los anteriores.
  update public.customer_portal_phone_verifications
     set expires_at = clock_timestamp()
   where tenant_id = p_tenant_id
     and auth_user_id = p_auth_user_id
     and confirmed_at is null
     and expires_at > clock_timestamp();

  v_code := lpad(
    (('x' || lpad(encode(extensions.gen_random_bytes(4), 'hex'), 16, '0'))::bit(64)::bigint % 1000000)::text,
    6,
    '0'
  );
  insert into public.customer_portal_phone_verifications (
    id, tenant_id, auth_user_id, phone_digits, code_sha256, expires_at
  ) values (
    v_id,
    p_tenant_id,
    p_auth_user_id,
    v_digits,
    encode(extensions.digest(convert_to(v_id::text || ':' || v_code, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '10 minutes'
  );

  return jsonb_build_object(
    'status', 'issued',
    'verification_id', v_id,
    'phone', v_digits,
    'phone_hint', public.customer_phone_display_internal(v_digits, true),
    'code', v_code,
    'expires_at', clock_timestamp() + interval '10 minutes'
  );
end;
$$;

revoke all on function public.start_customer_phone_verification_internal(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.start_customer_phone_verification_internal(uuid, uuid, text)
  to service_role;

-- Lo que respondió WhatsApp. Un código que no salió no se puede confirmar.
create or replace function public.finish_customer_phone_verification_send_internal(
  p_verification_id uuid,
  p_sent boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.customer_portal_phone_verifications
     set send_outcome = case when p_sent then 'sent' else 'failed' end,
         sent_at = case when p_sent then clock_timestamp() end,
         provider_message_id = left(nullif(trim(p_provider_message_id), ''), 200),
         send_error = left(nullif(trim(p_error), ''), 300),
         expires_at = case when p_sent then expires_at else least(expires_at, clock_timestamp()) end
   where id = p_verification_id
     and send_outcome is null;
$$;

revoke all on function public.finish_customer_phone_verification_send_internal(uuid, boolean, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.finish_customer_phone_verification_send_internal(uuid, boolean, text, text)
  to service_role;

-- La ficha del taller que tiene [p_digits], sin cuenta y con algo que mostrar,
-- si es una sola. Varias es un teléfono compartido: no se adivina cuál.
create or replace function public.customer_phone_link_candidate_internal(
  p_tenant_id uuid,
  p_digits text,
  p_except uuid
)
returns table (customer_id uuid, candidates integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with matches as (
    select customer.id
      from public.customers customer
     where customer.tenant_id = p_tenant_id
       and customer.is_active is true
       and customer.auth_user_id is null
       and (p_except is null or customer.id <> p_except)
       and nullif(trim(customer.phone), '') is not null
       and public.normalize_whatsapp_phone(customer.phone) = p_digits
  )
  select (select id from matches limit 1), (select count(*)::integer from matches)
$$;

revoke all on function public.customer_phone_link_candidate_internal(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- La cuenta escribe el código. `linked` (con `first_name`), `verified` (no
-- hay ficha con ese número: la que el taller cree después se liga al entrar),
-- `verified_ambiguous` (varias fichas), `verified_has_history` (la cuenta ya
-- tiene su propio historial; unirlos lo hace el taller), `wrong_code`
-- (`attempts_left`), `expired` y `too_many_attempts`.
create or replace function public.confirm_customer_phone_verification_v1(
  p_tenant_id uuid,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_row public.customer_portal_phone_verifications%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g');
  v_current public.customers%rowtype;
  v_candidate uuid;
  v_candidates integer;
  v_outcome text;
begin
  if v_uid is null then
    raise exception 'phone_verification_account_required' using errcode = '42501';
  end if;
  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'A confirmed Auth email is required' using errcode = '42501';
  end if;

  select * into v_row
    from public.customer_portal_phone_verifications verification
   where verification.tenant_id = p_tenant_id
     and verification.auth_user_id = v_uid
     and verification.confirmed_at is null
     and verification.send_outcome = 'sent'
   order by verification.created_at desc
   limit 1
   for update;
  if not found or v_row.expires_at <= clock_timestamp() then
    return jsonb_build_object('status', 'expired');
  end if;
  if v_row.attempts >= 5 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;
  if length(v_code) <> 6
     or encode(extensions.digest(convert_to(v_row.id::text || ':' || v_code, 'UTF8'), 'sha256'), 'hex')
        <> v_row.code_sha256 then
    update public.customer_portal_phone_verifications
       set attempts = attempts + 1
     where id = v_row.id;
    if v_row.attempts + 1 >= 5 then
      return jsonb_build_object('status', 'too_many_attempts');
    end if;
    return jsonb_build_object('status', 'wrong_code', 'attempts_left', 5 - (v_row.attempts + 1));
  end if;

  update public.customer_portal_phone_verifications
     set confirmed_at = clock_timestamp()
   where id = v_row.id;
  insert into public.customer_portal_verified_phones (tenant_id, auth_user_id, phone_digits, verified_at)
  values (p_tenant_id, v_uid, v_row.phone_digits, clock_timestamp())
  on conflict (tenant_id, auth_user_id) do update
    set phone_digits = excluded.phone_digits,
        verified_at = excluded.verified_at;

  select * into v_current
    from public.customers customer
   where customer.tenant_id = p_tenant_id
     and customer.auth_user_id = v_uid;
  if not found then
    perform public.provision_current_public_store_customer(p_tenant_id);
    select * into v_current
      from public.customers customer
     where customer.tenant_id = p_tenant_id
       and customer.auth_user_id = v_uid;
  end if;

  select candidate.customer_id, candidate.candidates
    into v_candidate, v_candidates
    from public.customer_phone_link_candidate_internal(p_tenant_id, v_row.phone_digits, v_current.id) candidate;

  if v_candidates = 1 then
    v_outcome := public.link_portal_account_to_customer_internal(
      p_tenant_id,
      v_uid,
      v_email,
      v_candidate,
      public.customer_phone_display_internal(v_row.phone_digits),
      'con su teléfono verificado'
    );
    if v_outcome is null then
      return jsonb_build_object(
        'status', 'linked',
        'customer_id', v_candidate,
        'first_name', (select public.customer_first_name_internal(customer.name)
                         from public.customers customer where customer.id = v_candidate)
      );
    end if;
  end if;

  -- Sin ficha que ligar: el número confirmado queda en la ficha de la cuenta
  -- si no tenía uno.
  update public.customers
     set phone = public.customer_phone_display_internal(v_row.phone_digits),
         updated_at = clock_timestamp()
   where id = v_current.id
     and tenant_id = p_tenant_id
     and nullif(trim(phone), '') is null;

  return jsonb_build_object(
    'status',
    case
      when v_candidates = 0 then 'verified'
      when v_candidates > 1 then 'verified_ambiguous'
      else 'verified_has_history'
    end
  );
end;
$$;

revoke all on function public.confirm_customer_phone_verification_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.confirm_customer_phone_verification_v1(uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Al entrar: ligar la ficha que el taller creó después, y qué ofrecer
-- ---------------------------------------------------------------------------

-- Lo que el portal necesita saber del teléfono de la cuenta, y la otra mitad
-- de la vinculación: si la cuenta ya confirmó su teléfono, no tiene historial
-- propio y el taller creó después una sola ficha con ese número, la cuenta
-- queda con ella ahora (`linked_now`). `offer` dice si mostrar «Confirma tu
-- teléfono»: encendido, sin teléfono confirmado y sin historial propio (lo
-- único con que ligar puede servir).
create or replace function public.customer_portal_phone_state_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_enabled boolean;
  v_verified public.customer_portal_verified_phones%rowtype;
  v_has_verified boolean := false;
  v_current public.customers%rowtype;
  v_has_current boolean := false;
  v_has_history boolean := false;
  v_candidate uuid;
  v_candidates integer := 0;
  v_linked boolean := false;
begin
  if v_uid is null then
    raise exception 'phone_verification_account_required' using errcode = '42501';
  end if;
  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    return jsonb_build_object('enabled', false, 'offer', false, 'linked_now', false);
  end if;
  v_enabled := public.customer_phone_verification_enabled_internal(p_tenant_id);

  select * into v_verified
    from public.customer_portal_verified_phones verified
   where verified.tenant_id = p_tenant_id
     and verified.auth_user_id = v_uid;
  v_has_verified := found;

  select * into v_current
    from public.customers customer
   where customer.tenant_id = p_tenant_id
     and customer.auth_user_id = v_uid;
  v_has_current := found;
  if v_has_current then
    v_has_history := public.customer_has_portal_history_internal(p_tenant_id, v_current.id);
  end if;

  if v_has_verified and v_has_current and not v_has_history then
    select candidate.customer_id, candidate.candidates
      into v_candidate, v_candidates
      from public.customer_phone_link_candidate_internal(p_tenant_id, v_verified.phone_digits, v_current.id) candidate;
    if v_candidates = 1
       and public.link_portal_account_to_customer_internal(
             p_tenant_id,
             v_uid,
             v_email,
             v_candidate,
             public.customer_phone_display_internal(v_verified.phone_digits),
             'con su teléfono verificado'
           ) is null then
      v_linked := true;
    end if;
  end if;

  return jsonb_build_object(
    'enabled', v_enabled,
    'offer', v_enabled and not v_has_verified and v_has_current and not v_has_history,
    'linked_now', v_linked,
    'verified_phone',
      case when v_has_verified
        then public.customer_phone_display_internal(v_verified.phone_digits, true)
      end,
    'suggested_phone',
      case when v_has_current and nullif(trim(v_current.phone), '') is not null
        then trim(v_current.phone)
      end
  );
end;
$$;

revoke all on function public.customer_portal_phone_state_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_portal_phone_state_v1(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Lo que ve el taller en Configuración › WhatsApp
-- ---------------------------------------------------------------------------

-- Cuántos códigos salieron, fallaron y se confirmaron en 30 días. Sólo el
-- equipo de la tienda; nunca un número ni un código.
create or replace function public.customer_phone_verification_stats_v1(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when public.is_active_tenant_member(p_tenant_id) then (
    select jsonb_build_object(
      'sent_30d', count(*) filter (where verification.send_outcome = 'sent'),
      'failed_30d', count(*) filter (where verification.send_outcome = 'failed'),
      'confirmed_30d', count(*) filter (where verification.confirmed_at is not null),
      'last_sent_at', max(verification.sent_at)
    )
      from public.customer_portal_phone_verifications verification
     where verification.tenant_id = p_tenant_id
       and verification.created_at > clock_timestamp() - interval '30 days'
  ) end;
$$;

revoke all on function public.customer_phone_verification_stats_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_phone_verification_stats_v1(uuid)
  to authenticated;
