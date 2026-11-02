-- Cotizar pide una cuenta, y el cliente elige por dónde le avisamos
-- (dueño, 2026-11-02; corrige 20261102041700 y 20261102063700).
--
-- «si es necesario que tenga cuenta, no queremos estafadores mandando
-- mierda. Los datos que ingrese a su cuenta, tanto email como número, serán
-- los usados para toda la comunicación que la cotización amerite», y después
-- «no que absolutamente todo vaya al correo y al whatsapp, que sea
-- configurable, que el cliente pueda elegir, si quiero uno u otro o los dos».
--
--   * Pedir una cotización desde el sitio exige haber entrado: sin sesión, o
--     sin la ficha de cliente de la tienda detrás, el comando se niega
--     (`quote_account_required`). El nombre, el correo y el teléfono salen de
--     la cuenta; el pedido ya no trae datos de contacto.
--   * El cliente elige los avisos: correo, WhatsApp o los dos
--     (`notify_email`, `notify_whatsapp`). Cada mensaje sale sólo por lo
--     elegido; ya no hay un correo de respaldo para quien eligió WhatsApp.
--     `preferred_channel` queda calculado (WhatsApp si lo eligió; si no,
--     correo) para lo que sólo necesita un canal principal.
--   * Los datos de contacto de una cotización siguen a la cuenta: si el
--     cliente cambia su nombre o su teléfono en «Mi cuenta», o el equipo
--     corrige su ficha, sus cotizaciones y los mensajes que faltan enviar
--     toman el dato nuevo. Si la cuenta queda sin teléfono, la cotización deja
--     WhatsApp y avisa por correo; el WhatsApp por enviar se omite.
--   * Con el enlace de su cotización, el cliente cambia sus avisos mientras le
--     seguimos escribiendo (`update_public_customer_quote_notify_v1`).
--   * «Mi cuenta» lista sus cotizaciones (`list_my_customer_quotes_v1`) y
--     abre cada una con un enlace nuevo (`open_my_customer_quote_v1`).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. Lo que eligió el cliente
-- ---------------------------------------------------------------------------

alter table public.customer_quotes
  add column if not exists notify_email boolean,
  add column if not exists notify_whatsapp boolean;

-- Lo que hacía la regla anterior: el canal elegido y, si había correo,
-- también el correo.
update public.customer_quotes
   set notify_email = customer_email is not null,
       notify_whatsapp = preferred_channel = 'whatsapp'
 where notify_email is null or notify_whatsapp is null;

alter table public.customer_quotes
  alter column notify_email set not null,
  alter column notify_whatsapp set not null;

alter table public.customer_quotes drop constraint if exists customer_quotes_reachable;
alter table public.customer_quotes drop constraint if exists customer_quotes_channel;
alter table public.customer_quotes drop column if exists preferred_channel;
alter table public.customer_quotes
  add column preferred_channel text generated always as (
    case when notify_whatsapp then 'whatsapp' else 'email' end
  ) stored;

alter table public.customer_quotes
  drop constraint if exists customer_quotes_notify,
  drop constraint if exists customer_quotes_notify_reachable;
alter table public.customer_quotes
  add constraint customer_quotes_notify check (notify_email or notify_whatsapp),
  add constraint customer_quotes_notify_reachable check (
    (not notify_email or customer_email is not null)
    and (not notify_whatsapp or customer_phone is not null)
  );

comment on column public.customer_quotes.notify_email is
  'El cliente pidió los avisos de esta cotización por correo (al correo de su cuenta).';
comment on column public.customer_quotes.notify_whatsapp is
  'El cliente pidió los avisos de esta cotización por WhatsApp (al teléfono de su cuenta).';
comment on column public.customer_quotes.preferred_channel is
  'Calculado: whatsapp si el cliente lo eligió; si no, email. Los mensajes leen notify_email y notify_whatsapp.';

-- ---------------------------------------------------------------------------
-- 2. Piezas internas
-- ---------------------------------------------------------------------------

-- Los datos de contacto de una cuenta, con la misma normalización que un
-- pedido (`customer_quote_contact_internal`); lo que no sirve queda nulo en
-- vez de rechazar, porque el cliente lo corrige en su cuenta, no aquí.
create or replace function public.customer_quote_account_contact_internal(
  p_name text,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v jsonb := public.customer_quote_contact_internal(jsonb_build_object(
    'customer_name', p_name, 'customer_email', p_email, 'customer_phone', p_phone
  ));
  v_name text := btrim(left(coalesce(v ->> 'customer_name', ''), 120));
begin
  return jsonb_build_object(
    'customer_name', case when length(v_name) >= 2 then v_name end,
    'customer_email', case
      when (v ->> 'customer_email') ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
        then v ->> 'customer_email'
    end,
    'customer_phone', case
      when (v ->> 'customer_phone') ~ '^\+?[0-9]{8,15}$' then v ->> 'customer_phone'
    end
  );
end;
$$;

revoke all on function public.customer_quote_account_contact_internal(text, text, text)
  from public, anon, authenticated, service_role;

-- Los avisos pedidos: {notify_email, notify_whatsapp} del pedido. Un pedido
-- que no los trae (el ERP antes del 2026-11-02) avisa sólo por
-- p_fallback_channel.
create or replace function public.customer_quote_notify_choice_internal(
  p_request jsonb,
  p_fallback_channel text
)
returns jsonb
language plpgsql
immutable
as $$
begin
  if p_request ? 'notify_email' or p_request ? 'notify_whatsapp' then
    return jsonb_build_object(
      'notify_email', coalesce(p_request -> 'notify_email' = 'true'::jsonb, false),
      'notify_whatsapp', coalesce(p_request -> 'notify_whatsapp' = 'true'::jsonb, false)
    );
  end if;
  return jsonb_build_object(
    'notify_email', coalesce(p_fallback_channel = 'email', false),
    'notify_whatsapp', coalesce(p_fallback_channel = 'whatsapp', false)
  );
end;
$$;

revoke all on function public.customer_quote_notify_choice_internal(jsonb, text)
  from public, anon, authenticated, service_role;

-- Ningún aviso elegido, o uno sin su dato, se rechaza con su nombre de
-- campo para que el formulario lo marque.
create or replace function public.customer_quote_validate_notify_internal(
  p_contact jsonb,
  p_notify jsonb
)
returns void
language plpgsql
immutable
as $$
declare
  v_email boolean := coalesce((p_notify ->> 'notify_email')::boolean, false);
  v_whatsapp boolean := coalesce((p_notify ->> 'notify_whatsapp')::boolean, false);
  v_field text;
begin
  v_field := case
    when not (v_email or v_whatsapp) then 'notify'
    when v_email and p_contact ->> 'customer_email' is null then 'customer_email'
    when v_whatsapp and p_contact ->> 'customer_phone' is null then 'customer_phone'
  end;
  if v_field is not null then
    raise exception 'quote_contact_invalid' using errcode = '22023', detail = v_field;
  end if;
end;
$$;

revoke all on function public.customer_quote_validate_notify_internal(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. El cliente pide la cotización desde su cuenta
-- ---------------------------------------------------------------------------

create or replace function public.request_public_customer_quote_v1(
  p_tenant_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
  v_key text;
  v_contact jsonb;
  v_notify jsonb;
  v_notes text;
  v_existing public.customer_quotes%rowtype;
  v_quote_id uuid;
  v_number text;
  v_access jsonb;
begin
  if p_tenant_id is null or p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote request' using errcode = '22023';
  end if;
  if not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Invalid tenant_id' using errcode = '22023';
  end if;

  -- Quien cotiza tiene cuenta en esta tienda, activa.
  if auth.uid() is not null then
    select * into v_customer from public.customers c
     where c.tenant_id = p_tenant_id and c.auth_user_id = auth.uid() and c.is_active
     limit 1;
  end if;
  if v_customer.id is null then
    raise exception 'quote_account_required' using errcode = '42501';
  end if;

  v_key := lower(btrim(coalesce(p_request ->> 'request_idempotency_key', '')));
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random request idempotency key is required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':quote:' || v_key, 0));

  select * into v_existing from public.customer_quotes q
   where q.tenant_id = p_tenant_id and q.request_idempotency_key = v_key;
  if found then
    -- La repetición de la misma cuenta devuelve la misma cotización con un
    -- enlace nuevo: el valor del anterior nunca se guardó.
    if v_existing.customer_id is distinct from v_customer.id then
      raise exception 'Quote request belongs to another customer' using errcode = '42501';
    end if;
    v_access := public.customer_quote_issue_token_internal(
      v_existing.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
    );
    return jsonb_build_object(
      'quote_id', v_existing.id, 'quote_number', v_existing.quote_number,
      'access_token', v_access ->> 'token', 'expires_at', v_access ->> 'expires_at',
      'replay', true
    );
  end if;

  v_contact := public.customer_quote_account_contact_internal(
    v_customer.name, v_customer.email, v_customer.phone
  );
  v_notify := public.customer_quote_notify_choice_internal(p_request, null);
  v_notes := nullif(btrim(coalesce(p_request ->> 'customer_notes', '')), '');
  perform public.customer_quote_validate_notify_internal(v_contact, v_notify);
  perform public.customer_quote_validate_contact_internal(v_contact || jsonb_build_object(
    'preferred_channel',
    case when (v_notify ->> 'notify_whatsapp')::boolean then 'whatsapp' else 'email' end,
    'customer_notes', v_notes
  ));

  -- Freno a una cuenta que manda de más: 10 por cuenta al día y 60 por hora
  -- en todo el sitio (un taller recibe unas pocas al día).
  if (select count(*) from public.customer_quotes q
       where q.tenant_id = p_tenant_id and q.source = 'web'
         and q.requested_at > clock_timestamp() - interval '1 hour') >= 60
     or (select count(*) from public.customer_quotes q
          where q.tenant_id = p_tenant_id and q.customer_id = v_customer.id
            and q.requested_at > clock_timestamp() - interval '1 day') >= 10 then
    raise exception 'quote_rate_limited' using errcode = '54000';
  end if;

  v_number := public.customer_quote_next_number_internal(p_tenant_id);
  insert into public.customer_quotes (
    tenant_id, quote_number, status, source, customer_id, customer_name, customer_email,
    customer_phone, notify_email, notify_whatsapp, customer_notes, request_idempotency_key
  ) values (
    p_tenant_id, v_number, 'confirming', 'web', v_customer.id,
    v_contact ->> 'customer_name', v_contact ->> 'customer_email', v_contact ->> 'customer_phone',
    (v_notify ->> 'notify_email')::boolean, (v_notify ->> 'notify_whatsapp')::boolean,
    v_notes, v_key
  ) returning id into v_quote_id;

  perform public.customer_quote_insert_lines_internal(v_quote_id, p_request -> 'items', true);
  perform public.customer_quote_log_internal(
    v_quote_id, 'requested', 'customer', auth.uid(), 'web', null, null,
    jsonb_build_object(
      'lines', (select count(*) from public.customer_quote_lines where quote_id = v_quote_id),
      'notify_email', (v_notify ->> 'notify_email')::boolean,
      'notify_whatsapp', (v_notify ->> 'notify_whatsapp')::boolean
    )
  );
  perform public.customer_quote_prepare_offer_internal(v_quote_id, 'system', null, null, null);
  perform public.customer_quote_notify_internal(
    v_quote_id, 'customer_quote_requested', 'Cotización nueva', 'customer_quote', v_quote_id, 'info'
  );

  v_access := public.customer_quote_issue_token_internal(
    v_quote_id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
  );
  return jsonb_build_object(
    'quote_id', v_quote_id, 'quote_number', v_number,
    'access_token', v_access ->> 'token', 'expires_at', v_access ->> 'expires_at',
    'replay', false
  );
end;
$$;

-- Un visitante sin sesión ya no llega al comando.
revoke all on function public.request_public_customer_quote_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.request_public_customer_quote_v1(uuid, jsonb)
  to authenticated, service_role;

comment on function public.request_public_customer_quote_v1(uuid, jsonb) is
  'El cliente con cuenta pide una cotización desde el sitio: {request_idempotency_key (UUIDv4), notify_email, notify_whatsapp (al menos uno), customer_notes, items: [{product_id, quantity}]}. El nombre, el correo y el teléfono salen de su cuenta. Sin cuenta: quote_account_required. Devuelve el número y un enlace de 60 días (sólo se guarda su huella).';

-- ---------------------------------------------------------------------------
-- 4. El equipo arma una cotización en el ERP
-- ---------------------------------------------------------------------------

create or replace function public.create_staff_customer_quote_v1(
  p_tenant_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_contact jsonb;
  v_notify jsonb;
  v_customer public.customers%rowtype;
  v_conversation uuid := nullif(p_request ->> 'conversation_id', '')::uuid;
  v_quote_id uuid;
  v_number text;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote request' using errcode = '22023';
  end if;
  -- Con una ficha de cliente, lo que no viene en el pedido sale de la ficha.
  if nullif(p_request ->> 'customer_id', '') is not null then
    select * into v_customer from public.customers c
     where c.id = (p_request ->> 'customer_id')::uuid and c.tenant_id = p_tenant_id;
    if not found then
      raise exception 'Customer not found' using errcode = 'P0002';
    end if;
    v_contact := public.customer_quote_contact_internal(p_request || jsonb_build_object(
      'customer_name', coalesce(nullif(btrim(p_request ->> 'customer_name'), ''), v_customer.name),
      'customer_email', coalesce(nullif(btrim(p_request ->> 'customer_email'), ''), v_customer.email),
      'customer_phone', coalesce(nullif(btrim(p_request ->> 'customer_phone'), ''), v_customer.phone)
    ));
  else
    v_contact := public.customer_quote_contact_internal(p_request);
  end if;
  v_notify := public.customer_quote_notify_choice_internal(p_request, v_contact ->> 'preferred_channel');
  perform public.customer_quote_validate_notify_internal(v_contact, v_notify);
  perform public.customer_quote_validate_contact_internal(v_contact || jsonb_build_object(
    'preferred_channel',
    case when (v_notify ->> 'notify_whatsapp')::boolean then 'whatsapp' else 'email' end
  ));
  if v_conversation is not null and not exists (
    select 1 from public.conversations c where c.id = v_conversation and c.tenant_id = p_tenant_id
  ) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;

  v_number := public.customer_quote_next_number_internal(p_tenant_id);
  insert into public.customer_quotes (
    tenant_id, quote_number, status, source, customer_id, customer_name, customer_email,
    customer_phone, notify_email, notify_whatsapp, customer_notes, conversation_id,
    assigned_to, created_by
  ) values (
    p_tenant_id, v_number, 'confirming',
    case when v_conversation is not null then 'whatsapp' else 'staff' end,
    v_customer.id, v_contact ->> 'customer_name', v_contact ->> 'customer_email',
    v_contact ->> 'customer_phone', (v_notify ->> 'notify_email')::boolean,
    (v_notify ->> 'notify_whatsapp')::boolean, v_contact ->> 'customer_notes',
    v_conversation, v_actor, v_actor
  ) returning id into v_quote_id;

  perform public.customer_quote_insert_lines_internal(v_quote_id, p_request -> 'items', false);
  perform public.customer_quote_log_internal(
    v_quote_id, 'requested', 'staff', v_actor, 'erp', null, null,
    jsonb_build_object('lines', (select count(*) from public.customer_quote_lines where quote_id = v_quote_id))
  );
  perform public.customer_quote_prepare_offer_internal(v_quote_id, 'staff', v_actor, null, null);

  return jsonb_build_object('quote_id', v_quote_id, 'quote_number', v_number);
end;
$$;

revoke all on function public.create_staff_customer_quote_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_staff_customer_quote_v1(uuid, jsonb) to authenticated;

comment on function public.create_staff_customer_quote_v1(uuid, jsonb) is
  'Un trabajador arma una cotización en el ERP (mesón, teléfono o desde una conversación de WhatsApp con conversation_id): mismos productos que el sitio; customer_id opcional completa los datos de contacto; notify_email y notify_whatsapp dicen los avisos (sin ellos, sólo preferred_channel).';

-- ---------------------------------------------------------------------------
-- 5. Cada mensaje sale sólo por lo elegido (redefine 20261102063700)
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_enqueue_message_internal(
  p_quote_id uuid,
  p_kind text,
  p_offer_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_count integer := 0;
  v_id uuid;
  v_channels text[];
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    return 0;
  end if;
  v_channels := case
    when p_kind in ('offer', 'reminder') then array_remove(array[
      case when v_quote.notify_whatsapp and v_quote.customer_phone is not null then 'whatsapp' end,
      case when v_quote.notify_email and v_quote.customer_email is not null then 'email' end
    ], null)
    -- «Recibimos» y «aceptada» sólo van por correo: a quien no ha escrito por
    -- WhatsApp no se le puede escribir primero sin plantilla de Meta.
    when v_quote.notify_email and v_quote.customer_email is not null then array['email']
    else array[]::text[]
  end;

  for i in 1 .. coalesce(array_length(v_channels, 1), 0) loop
    insert into public.customer_quote_messages (
      tenant_id, quote_id, offer_id, kind, channel, recipient, state
    ) values (
      v_quote.tenant_id, v_quote.id, p_offer_id, p_kind, v_channels[i],
      case v_channels[i] when 'email' then v_quote.customer_email else v_quote.customer_phone end,
      case v_channels[i] when 'email' then 'pending' else 'needs_staff' end
    )
    on conflict on constraint customer_quote_messages_once do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      perform public.customer_quote_log_internal(
        v_quote.id, 'message_queued', 'system', null, 'system', p_offer_id, null,
        jsonb_build_object('kind', p_kind, 'channel', v_channels[i], 'message_id', v_id)
      );
      if v_channels[i] = 'whatsapp' then
        perform public.customer_quote_notify_internal(
          v_quote.id,
          'customer_quote_whatsapp_pending',
          case p_kind
            when 'reminder' then 'Recordar la oferta por WhatsApp'
            else 'Enviar la oferta por WhatsApp'
          end,
          'customer_quote_message',
          v_id,
          'warning'
        );
      end if;
    end if;
    v_id := null;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.customer_quote_enqueue_message_internal(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Los mensajes que faltan siguen a la cotización; la cotización, a la cuenta
-- ---------------------------------------------------------------------------

-- La historia dice también cuándo el cliente cambió sus avisos y cuándo la
-- cotización tomó datos nuevos de su cuenta.
alter table public.customer_quote_events drop constraint if exists customer_quote_events_type;
alter table public.customer_quote_events add constraint customer_quote_events_type check (
  event_type in (
    'requested', 'offer_prepared', 'offer_revised', 'line_confirmed', 'line_added',
    'supplier_task_opened', 'supplier_task_done', 'offer_sent', 'viewed',
    'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
    'reminder_sent', 'message_queued', 'note', 'notify_changed', 'contact_updated'
  )
);

-- Lo que falta enviar de una cotización, puesto al día con lo que pide ahora:
-- un canal que ya no pidió (o sin su dato) se omite y su aviso al equipo
-- queda leído; lo demás va al dato de ahora; y la oferta vigente llega por lo
-- pedido ahora (lo omitido por un cambio anterior vuelve, lo que falta se crea).
create or replace function public.customer_quote_sync_messages_internal(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_message record;
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    return;
  end if;

  for v_message in
    update public.customer_quote_messages m
       set state = 'skipped',
           last_error = case m.channel
             when 'email' then 'El cliente ya no pidió avisos por correo'
             else 'El cliente ya no pidió avisos por WhatsApp'
           end,
           updated_at = clock_timestamp()
     where m.quote_id = p_quote_id
       and m.state in ('pending', 'needs_staff')
       and not case m.channel
         when 'email' then v_quote.notify_email and v_quote.customer_email is not null
         else v_quote.notify_whatsapp and v_quote.customer_phone is not null
       end
    returning m.id, m.channel
  loop
    if v_message.channel = 'whatsapp' then
      update public.erp_notifications n
         set read_at = coalesce(n.read_at, clock_timestamp())
       where n.tenant_id = v_quote.tenant_id
         and n.type = 'customer_quote_whatsapp_pending'
         and n.entity_type = 'customer_quote_message'
         and n.entity_id = v_message.id;
    end if;
  end loop;

  update public.customer_quote_messages m
     set recipient = case m.channel when 'email' then v_quote.customer_email else v_quote.customer_phone end,
         updated_at = clock_timestamp()
   where m.quote_id = p_quote_id
     and m.state in ('pending', 'needs_staff')
     and m.recipient is distinct from
         case m.channel when 'email' then v_quote.customer_email else v_quote.customer_phone end;

  if v_quote.status = 'offered' and v_quote.current_offer_id is not null then
    for v_message in
      update public.customer_quote_messages m
         set state = case m.channel when 'email' then 'pending' else 'needs_staff' end,
             recipient = case m.channel when 'email' then v_quote.customer_email else v_quote.customer_phone end,
             last_error = null,
             attempt_count = 0,
             available_at = clock_timestamp(),
             updated_at = clock_timestamp()
       where m.quote_id = p_quote_id
         and m.offer_id = v_quote.current_offer_id
         and m.kind in ('offer', 'reminder')
         and m.state = 'skipped'
         and case m.channel
           when 'email' then v_quote.notify_email and v_quote.customer_email is not null
           else v_quote.notify_whatsapp and v_quote.customer_phone is not null
         end
      returning m.id, m.channel
    loop
      if v_message.channel = 'whatsapp' then
        update public.erp_notifications n
           set read_at = null
         where n.tenant_id = v_quote.tenant_id
           and n.type = 'customer_quote_whatsapp_pending'
           and n.entity_type = 'customer_quote_message'
           and n.entity_id = v_message.id;
      end if;
    end loop;
    perform public.customer_quote_enqueue_message_internal(p_quote_id, 'offer', v_quote.current_offer_id);
  end if;
end;
$$;

revoke all on function public.customer_quote_sync_messages_internal(uuid)
  from public, anon, authenticated, service_role;

-- Cuando cambian el nombre, el correo o el teléfono de una cuenta, sus
-- cotizaciones que todavía avisan (no rechazadas ni anuladas) toman el dato
-- nuevo, con su evento en la historia. Un correo que no sirve deja el
-- anterior: es el único canal que siempre tiene una cuenta. Sin teléfono, la
-- cotización deja WhatsApp y avisa por correo (salvo que no tenga correo:
-- entonces conserva lo que tenía).
create or replace function public.customer_quotes_follow_account()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_contact jsonb;
  v_quote public.customer_quotes%rowtype;
  v_name text;
  v_email text;
  v_phone text;
  v_whatsapp boolean;
  v_by_email boolean;
begin
  v_contact := public.customer_quote_account_contact_internal(new.name, new.email, new.phone);
  for v_quote in
    select * from public.customer_quotes q
     where q.customer_id = new.id
       and q.tenant_id = new.tenant_id
       and q.status not in ('rejected', 'cancelled')
     order by q.requested_at
       for update
  loop
    v_name := coalesce(v_contact ->> 'customer_name', v_quote.customer_name);
    v_email := coalesce(v_contact ->> 'customer_email', v_quote.customer_email);
    v_phone := case
      when v_contact ->> 'customer_phone' is not null then v_contact ->> 'customer_phone'
      when v_email is not null then null
      else v_quote.customer_phone
    end;
    v_whatsapp := v_quote.notify_whatsapp and v_phone is not null;
    v_by_email := v_quote.notify_email or (v_quote.notify_whatsapp and not v_whatsapp);
    continue when (v_name, v_email, v_phone, v_by_email, v_whatsapp) is not distinct from
      (v_quote.customer_name, v_quote.customer_email, v_quote.customer_phone,
       v_quote.notify_email, v_quote.notify_whatsapp);

    update public.customer_quotes
       set customer_name = v_name,
           customer_email = v_email,
           customer_phone = v_phone,
           notify_email = v_by_email,
           notify_whatsapp = v_whatsapp
     where id = v_quote.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'contact_updated', 'system', null, 'system', null, null,
      jsonb_build_object(
        'name', v_name is distinct from v_quote.customer_name,
        'email', v_email is distinct from v_quote.customer_email,
        'phone', v_phone is distinct from v_quote.customer_phone,
        'notify_email', v_by_email,
        'notify_whatsapp', v_whatsapp,
        'whatsapp_dropped', v_quote.notify_whatsapp and not v_whatsapp
      )
    );
    perform public.customer_quote_sync_messages_internal(v_quote.id);
  end loop;
  return null;
end;
$$;

revoke all on function public.customer_quotes_follow_account()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customers_quotes_follow_account on public.customers;
create trigger trg_customers_quotes_follow_account
  after update of name, email, phone on public.customers
  for each row
  when (
    old.name is distinct from new.name
    or old.email is distinct from new.email
    or old.phone is distinct from new.phone
  )
  execute function public.customer_quotes_follow_account();

-- El cliente cambia sus avisos desde el enlace de su cotización mientras
-- todavía le escribimos (por confirmar, con oferta, o aceptada).
create or replace function public.update_public_customer_quote_notify_v1(
  p_token text,
  p_notify jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_notify jsonb;
begin
  if p_notify is null or jsonb_typeof(p_notify) <> 'object' then
    raise exception 'Invalid notify choice' using errcode = '22023';
  end if;
  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id
   for update;
  if not found then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;
  if v_quote.status not in ('confirming', 'offered', 'accepted') then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;

  v_notify := public.customer_quote_notify_choice_internal(p_notify, null);
  perform public.customer_quote_validate_notify_internal(
    jsonb_build_object('customer_email', v_quote.customer_email, 'customer_phone', v_quote.customer_phone),
    v_notify
  );
  if (v_notify ->> 'notify_email')::boolean = v_quote.notify_email
     and (v_notify ->> 'notify_whatsapp')::boolean = v_quote.notify_whatsapp then
    return v_notify || jsonb_build_object('changed', false);
  end if;

  update public.customer_quotes
     set notify_email = (v_notify ->> 'notify_email')::boolean,
         notify_whatsapp = (v_notify ->> 'notify_whatsapp')::boolean
   where id = v_quote.id;
  perform public.customer_quote_log_internal(
    v_quote.id, 'notify_changed', 'customer', null, 'web', null, null, v_notify
  );
  perform public.customer_quote_sync_messages_internal(v_quote.id);
  return v_notify || jsonb_build_object('changed', true);
end;
$$;

revoke all on function public.update_public_customer_quote_notify_v1(text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_public_customer_quote_notify_v1(text, jsonb)
  to anon, authenticated, service_role;

comment on function public.update_public_customer_quote_notify_v1(text, jsonb) is
  'El cliente elige otra vez sus avisos con el enlace de su cotización: {notify_email, notify_whatsapp} (al menos uno, cada uno con su dato en la cuenta). Lo que falta enviar se pone al día.';

-- ---------------------------------------------------------------------------
-- 7. Sus cotizaciones en «Mi cuenta»
-- ---------------------------------------------------------------------------

-- Las cotizaciones de la cuenta con sesión, la más reciente primero: lo que
-- la lista de «Mi cuenta» dibuja, sin datos de contacto ni enlaces.
create or replace function public.list_my_customer_quotes_v1(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(mine.item order by mine.requested_at desc), '[]'::jsonb)
    from (
      select q.requested_at, jsonb_strip_nulls(jsonb_build_object(
        'id', q.id,
        'number', q.quote_number,
        'status', q.status,
        'requestedAt', q.requested_at,
        'expiresAt', case when q.status = 'offered' then q.expires_at end,
        'lines', (select count(*) from public.customer_quote_lines l where l.quote_id = q.id),
        'total', (select o.total from public.customer_quote_offers o
                   where o.id = q.current_offer_id and o.status <> 'draft'),
        'notifyEmail', q.notify_email,
        'notifyWhatsapp', q.notify_whatsapp
      )) as item
        from public.customer_quotes q
        join public.customers c on c.id = q.customer_id and c.tenant_id = q.tenant_id
       where q.tenant_id = p_tenant_id
         and auth.uid() is not null
         and c.auth_user_id = auth.uid()
       order by q.requested_at desc
       limit 50
    ) mine;
$$;

revoke all on function public.list_my_customer_quotes_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_my_customer_quotes_v1(uuid) to authenticated, service_role;

comment on function public.list_my_customer_quotes_v1(uuid) is
  'Las cotizaciones del cliente con sesión en esa tienda (hasta 50): número, estado, fecha, vigencia de la oferta, líneas, total enviado y avisos elegidos.';

-- Un enlace nuevo para abrir una cotización propia desde «Mi cuenta»: la
-- página de la cotización lee con él, como con el del correo.
create or replace function public.open_my_customer_quote_v1(p_tenant_id uuid, p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_access jsonb;
begin
  if auth.uid() is null then
    raise exception 'quote_account_required' using errcode = '42501';
  end if;
  select q.* into v_quote
    from public.customer_quotes q
    join public.customers c on c.id = q.customer_id and c.tenant_id = q.tenant_id
   where q.id = p_quote_id
     and q.tenant_id = p_tenant_id
     and c.auth_user_id = auth.uid();
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  v_access := public.customer_quote_issue_token_internal(
    v_quote.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
  );
  return jsonb_build_object(
    'quote_number', v_quote.quote_number,
    'access_token', v_access ->> 'token',
    'expires_at', v_access ->> 'expires_at'
  );
end;
$$;

revoke all on function public.open_my_customer_quote_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.open_my_customer_quote_v1(uuid, uuid) to authenticated, service_role;

comment on function public.open_my_customer_quote_v1(uuid, uuid) is
  'El cliente con sesión abre una de sus cotizaciones: un enlace nuevo de 60 días (sólo se guarda su huella).';

-- ---------------------------------------------------------------------------
-- 8. El cliente y la bandeja leen lo elegido
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_public_projection_internal(p_quote_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with q as (
    select * from public.customer_quotes where id = p_quote_id
  ), offer as (
    select o.* from public.customer_quote_offers o, q
     where o.id = q.current_offer_id
  )
  select jsonb_build_object(
    'quote', (select jsonb_strip_nulls(jsonb_build_object(
      'number', q.quote_number,
      'status', q.status,
      'customerName', q.customer_name,
      'notifyEmail', q.notify_email,
      'notifyWhatsapp', q.notify_whatsapp,
      -- Sólo si la cuenta tiene cada dato, nunca el dato: el enlace se puede
      -- reenviar.
      'canEmail', q.customer_email is not null,
      'canWhatsapp', q.customer_phone is not null,
      'requestedAt', q.requested_at,
      'offeredAt', q.offered_at,
      'expiresAt', q.expires_at,
      'acceptedAt', q.accepted_at,
      'rejectedAt', q.rejected_at,
      'expiredAt', q.expired_at,
      'cancelledAt', q.cancelled_at
    )) from q),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineNo', l.line_no, 'name', l.product_name, 'sku', l.product_sku,
        'quantity', l.quantity, 'kind', l.kind_at_request
      ) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = p_quote_id
    ), '[]'::jsonb),
    'offer', (select jsonb_strip_nulls(jsonb_build_object(
      'id', offer.id,
      'number', offer.offer_no,
      'status', offer.status,
      'sentAt', offer.sent_at,
      'validUntil', offer.valid_until,
      'subtotal', offer.subtotal,
      'taxAmount', offer.tax_amount,
      'total', offer.total,
      'notes', offer.notes_to_customer,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', ol.id, 'lineNo', ol.line_no, 'name', ol.product_name, 'sku', ol.product_sku,
          'quantityRequested', ol.quantity_requested, 'quantity', ol.quantity_offered,
          'availability', ol.availability, 'unitPrice', ol.unit_price,
          'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
          'leadDaysMin', ol.lead_days_min, 'leadDaysMax', ol.lead_days_max,
          'note', ol.customer_note
        )) order by ol.line_no)
          from public.customer_quote_offer_lines ol where ol.offer_id = offer.id
      ), '[]'::jsonb)
    )) from offer where offer.status <> 'draft'),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.event_type, 'at', e.occurred_at) order by e.id)
        from public.customer_quote_events e
       where e.quote_id = p_quote_id
         and e.event_type in ('requested', 'offer_sent', 'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled')
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.customer_quote_public_projection_internal(uuid)
  from public, anon, authenticated, service_role;

-- La cotización vista con su enlace (redefine 20261102041700): además dice si
-- el cliente puede cambiar sus avisos.
create or replace function public.get_public_customer_quote_v1(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_can_respond boolean;
  v_can_answer boolean;
begin
  v_access := public.customer_quote_token_internal(p_token, 'view_quote');
  if v_access.id is null then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id;
  if not found then
    return null;
  end if;

  -- La primera vista de una oferta enviada queda en la historia.
  if v_quote.status = 'offered' and not exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.event_type = 'viewed' and e.offer_id = v_quote.current_offer_id
  ) then
    perform public.customer_quote_log_internal(
      v_quote.id, 'viewed', 'customer', null, 'web', v_quote.current_offer_id
    );
  end if;

  v_can_answer := v_access.scopes @> array['respond_quote']::text[];
  v_can_respond := v_quote.status = 'offered'
    and v_can_answer
    and v_quote.expires_at > clock_timestamp();

  return public.customer_quote_public_projection_internal(v_quote.id)
    || jsonb_build_object('actions', jsonb_build_object(
      'accept', v_can_respond,
      'requestChanges', v_can_respond,
      'reject', v_can_respond,
      'changeNotify', v_can_answer and v_quote.status in ('confirming', 'offered', 'accepted'),
      'onOrderPrepayPercent', (public.customer_quote_settings_internal(v_quote.tenant_id)).on_order_prepay_percent
    ));
end;
$$;

revoke all on function public.get_public_customer_quote_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_customer_quote_v1(text)
  to anon, authenticated, service_role;

-- La bandeja (redefine 20261102100000): lo mismo, con los avisos elegidos en
-- vez del canal único. Una cotización del taller no los tiene.
create or replace function public.customer_quote_inbox_v1(
  p_tenant_id uuid,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  return (
    with web as (
      select q.id, q.quote_number as number, q.status, q.source,
             q.customer_name as "customerName",
             q.notify_email as "notifyEmail", q.notify_whatsapp as "notifyWhatsapp",
             q.requested_at as "requestedAt", q.updated_at as "updatedAt",
             q.expires_at as "expiresAt",
             (select count(*) from public.customer_quote_lines l where l.quote_id = q.id) as lines,
             (select o.total from public.customer_quote_offers o where o.id = q.current_offer_id) as total,
             (select count(*) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "openTasks",
             (select min(t.due_at) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "nextDueAt",
             false as converted
        from public.customer_quotes q
       where q.tenant_id = p_tenant_id
    ),
    workshop_jobs as (
      select j.id, j.tenant_id, j.customer_id, j.job_number, j.workflow_kind,
             j.quotation_status, j.quotation_valid_until, j.total_cost,
             j.created_at, j.updated_at,
             (select count(*) from public.mechanic_job_items i
               where i.job_id = j.id and i.tenant_id = j.tenant_id) as item_count
        from public.mechanic_jobs j
       where j.tenant_id = p_tenant_id
         and j.deleted_at is null
         and j.archive_reason is null
         and (
           (j.workflow_kind = 'quotation' and j.intake_kind is distinct from 'bike')
           or exists (
             select 1 from public.mechanic_job_mode_events e
              where e.tenant_id = j.tenant_id and e.job_id = j.id
                and e.event_type = 'converted_to_billable'
                and e.from_workflow_kind = 'quotation'
                and e.from_intake_kind is distinct from 'bike'
           )
         )
    ),
    workshop as (
      select w.id, w.job_number as number,
             case
               when w.workflow_kind is distinct from 'quotation' then 'accepted'
               when w.quotation_status = 'approved' then 'accepted'
               when w.quotation_status = 'rejected' then 'rejected'
               when w.quotation_status = 'expired' then 'expired'
               when w.quotation_valid_until < now() then 'expired'
               when w.item_count = 0 then 'confirming'
               else 'offered'
             end as status,
             'workshop'::text as source,
             coalesce(nullif(btrim(c.name), ''), 'Sin cliente') as "customerName",
             null::boolean as "notifyEmail", null::boolean as "notifyWhatsapp",
             w.created_at as "requestedAt", w.updated_at as "updatedAt",
             case when w.workflow_kind = 'quotation' and w.quotation_status = 'pending'
                  then w.quotation_valid_until end as "expiresAt",
             w.item_count as lines,
             w.total_cost as total,
             0::bigint as "openTasks",
             null::timestamptz as "nextDueAt",
             (w.workflow_kind is distinct from 'quotation') as converted
        from workshop_jobs w
        left join public.customers c on c.id = w.customer_id and c.tenant_id = w.tenant_id
    ),
    all_quotes as (
      select * from web
      union all
      select * from workshop
    )
    select jsonb_build_object(
      'counts', (
        select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
          from (select a.status, count(*) as n from all_quotes a group by a.status) s
      ),
      'quotes', coalesce((
        select jsonb_agg(to_jsonb(r) order by r."updatedAt" desc)
          from (
            select a.* from all_quotes a
             where p_status is null or a.status = p_status
             order by a."updatedAt" desc
             limit greatest(1, least(coalesce(p_limit, 50), 200))
            offset greatest(0, coalesce(p_offset, 0))
          ) r
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.customer_quote_inbox_v1(uuid, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_inbox_v1(uuid, text, integer, integer) to authenticated;

commit;
