-- Purpose: REPARACIÓN URGENTE. 20260820020000 reescribió
-- `ingest_whatsapp_inbound_message` con una llamada de DIEZ argumentos a
-- `ensure_whatsapp_conversation_binding`, que tiene NUEVE. La firma no existe,
-- así que la función lanzaba excepción y **todo mensaje de texto entrante
-- dejó de llegar**: como el registro del evento crudo ocurre dentro de la misma
-- función, la transacción se deshacía y no quedaba ni rastro en
-- whatsapp_webhook_events. Los eventos de `status` seguían entrando porque usan
-- otra función, lo que hacía parecer que el webhook estaba sano.
--
-- Causa raíz: el argumento de más salió de leer el original con dos rangos de
-- `sed` solapados, contando dos veces la línea del borde. Y el probe de la
-- migración anterior sólo ejercitaba REACCIONES, así que el camino normal
-- —el 99% del tráfico— nunca se probó. El probe ahora cubre texto.

create or replace function public.ingest_whatsapp_inbound_message(
  p_phone_number_id text,
  p_external_message_id text,
  p_wa_id text,
  p_phone_number text,
  p_contact_name text,
  p_message_type text,
  p_message_body text,
  p_payload jsonb default '{}'::jsonb,
  p_context_type text default null,
  p_context_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel record;
  v_customer record;
  v_binding jsonb;
  v_conversation_id uuid;
  v_message_id uuid;
  v_event_key text;
  v_row_count integer;
  v_ui_message_type text;
  v_reaction jsonb;
  v_reaction_emoji text;
  v_reaction_target_wamid text;
  v_target_message record;
  v_reaction_id uuid;
begin
  select * into v_channel
  from public.whatsapp_channels
  where phone_number_id = p_phone_number_id
    and is_active = true
  limit 1;

  if not found then
    raise exception 'WhatsApp channel not found for phone_number_id %', p_phone_number_id;
  end if;

  select id, auth_user_id, tenant_id
    into v_customer
  from public.customers
  where tenant_id = v_channel.tenant_id
    and public.normalize_whatsapp_phone(phone) = public.normalize_whatsapp_phone(p_phone_number)
  order by updated_at desc nulls last, created_at desc
  limit 1;

  v_event_key := 'message:' || p_external_message_id;

  insert into public.whatsapp_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    v_event_key,
    'message',
    'inbound',
    p_payload
  ) on conflict (channel_id, event_key) do nothing;

  get diagnostics v_row_count = row_count;

  if v_row_count = 0 then
    return jsonb_build_object(
      'duplicate', true,
      'event_key', v_event_key,
      'external_message_id', p_external_message_id
    );
  end if;

  if lower(coalesce(p_message_type, '')) = 'unsupported' then
    return jsonb_build_object(
      'duplicate', false,
      'ignored', true,
      'ignored_reason', 'unsupported_whatsapp_message_type',
      'event_key', v_event_key,
      'external_message_id', p_external_message_id,
      'tenant_id', v_channel.tenant_id,
      'channel_id', v_channel.id
    );
  end if;

  -- Una reacción anota un mensaje que ya existe: nunca crea uno. Se resuelve y
  -- se guarda aparte, y se sale antes del INSERT en `messages` — que es
  -- justamente lo que producía el mensaje basura y el no-leído falso.
  if lower(coalesce(p_message_type, '')) = 'reaction' then
    v_reaction := p_payload -> 'message' -> 'reaction';
    v_reaction_emoji := btrim(coalesce(v_reaction ->> 'emoji', ''));
    v_reaction_target_wamid := v_reaction ->> 'message_id';

    if v_reaction_target_wamid is null then
      return jsonb_build_object(
        'duplicate', false,
        'ignored', true,
        'ignored_reason', 'reaction_without_target',
        'event_key', v_event_key,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    select m.id, m.conversation_id, m.tenant_id
      into v_target_message
    from public.messages m
    where m.tenant_id = v_channel.tenant_id
      and m.external_message_id = v_reaction_target_wamid
    limit 1;

    -- Una reacción a un mensaje anterior a esta integración no tiene dónde
    -- colgarse. El evento crudo ya quedó guardado arriba; no se inventa nada.
    if not found then
      return jsonb_build_object(
        'duplicate', false,
        'ignored', true,
        'ignored_reason', 'reaction_target_not_found',
        'event_key', v_event_key,
        'target_external_message_id', v_reaction_target_wamid,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    -- Emoji vacío es cómo WhatsApp dice «quité mi reacción».
    if v_reaction_emoji = '' then
      delete from public.message_reactions
      where message_id = v_target_message.id
        and reactor_key = 'wa:' || coalesce(public.normalize_whatsapp_phone(p_wa_id), '');

      return jsonb_build_object(
        'duplicate', false,
        'reaction', true,
        'reaction_removed', true,
        'message_id', v_target_message.id,
        'conversation_id', v_target_message.conversation_id,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    insert into public.message_reactions (
      tenant_id,
      message_id,
      conversation_id,
      reactor_wa_id,
      reactor_name,
      emoji,
      external_provider,
      external_message_id
    ) values (
      v_target_message.tenant_id,
      v_target_message.id,
      v_target_message.conversation_id,
      public.normalize_whatsapp_phone(p_wa_id),
      p_contact_name,
      v_reaction_emoji,
      'whatsapp',
      p_external_message_id
    )
    on conflict (message_id, reactor_key) do update
      set emoji = excluded.emoji,
          reactor_name = coalesce(excluded.reactor_name, public.message_reactions.reactor_name),
          external_message_id = excluded.external_message_id,
          updated_at = now()
    returning id into v_reaction_id;

    -- Una reacción es tráfico entrante del contacto, así que reabre la ventana
    -- de 24 h igual que cualquier mensaje suyo. No mueve `last_message_at`: no
    -- es un mensaje y no debe reordenar la bandeja.
    update public.whatsapp_conversation_bindings
    set last_inbound_at = now(),
        updated_at = now()
    where tenant_id = v_channel.tenant_id
      and conversation_id = v_target_message.conversation_id;

    return jsonb_build_object(
      'duplicate', false,
      'reaction', true,
      'reaction_id', v_reaction_id,
      'emoji', v_reaction_emoji,
      'message_id', v_target_message.id,
      'conversation_id', v_target_message.conversation_id,
      'tenant_id', v_channel.tenant_id
    );
  end if;

  v_binding := public.ensure_whatsapp_conversation_binding(
    v_channel.tenant_id,
    v_channel.id,
    p_wa_id,
    p_phone_number,
    p_contact_name,
    v_customer.id,
    p_context_type,
    p_context_id,
    null
  );

  v_conversation_id := (v_binding->>'conversation_id')::uuid;

  v_ui_message_type := case lower(coalesce(p_message_type, 'text'))
    when 'image' then 'image'
    when 'document' then 'file'
    when 'audio' then 'file'
    when 'video' then 'file'
    when 'sticker' then 'image'
    when 'interactive' then 'text'
    else 'text'
  end;

  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    metadata,
    external_provider,
    external_message_id,
    message_direction,
    created_at
  ) values (
    v_conversation_id,
    null,
    v_channel.tenant_id,
    coalesce(p_message_body, ''),
    v_ui_message_type,
    jsonb_strip_nulls(jsonb_build_object(
      'provider', 'whatsapp',
      'wa_id', p_wa_id,
      'phone_number', public.normalize_whatsapp_phone(p_phone_number),
      'contact_name', p_contact_name,
      'message_type', p_message_type,
      'raw_payload', p_payload
    )),
    'whatsapp',
    p_external_message_id,
    'inbound',
    now()
  ) returning id into v_message_id;

  update public.whatsapp_conversation_bindings
  set last_inbound_at = now(),
      updated_at = now()
  where id = (v_binding->>'binding_id')::uuid;

  update public.conversations
  set last_message_at = now(),
      updated_at = now(),
      status = case when status = 'pending' then 'active' else status end
  where id = v_conversation_id;

  return jsonb_build_object(
    'duplicate', false,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id,
    'binding_id', (v_binding->>'binding_id')::uuid,
    'customer_id', v_customer.id,
    'tenant_id', v_channel.tenant_id
  );
end;
$$;

grant execute on function public.ingest_whatsapp_inbound_message(
  text, text, text, text, text, text, text, jsonb, text, uuid
) to service_role;
