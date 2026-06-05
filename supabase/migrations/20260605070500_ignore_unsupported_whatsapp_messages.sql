-- Deployment status: DEPLOYED to production on 2026-06-05 via psql
-- Purpose: Meta can emit companion "unsupported" WhatsApp webhook messages
-- next to real HD photo/media rows. Keep the raw webhook event, but do not
-- create visible chat messages for those companion events.

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
