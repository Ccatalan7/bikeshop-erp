create or replace function public.replay_whatsapp_message_status(
  p_external_message_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event record;
  v_message record;
begin
  select
    lower(coalesce(payload->>'status', split_part(event_key, ':', 3))) as status,
    payload
  into v_event
  from public.whatsapp_webhook_events
  where event_type = 'status'
    and left(event_key, length('status:' || p_external_message_id || ':')) =
      'status:' || p_external_message_id || ':'
  order by
    case lower(coalesce(payload->>'status', split_part(event_key, ':', 3)))
      when 'failed' then 50
      when 'read' then 40
      when 'delivered' then 30
      when 'sent' then 20
      else 10
    end desc,
    coalesce(nullif(payload->>'timestamp', '')::bigint, extract(epoch from created_at)::bigint) desc,
    created_at desc
  limit 1;

  if not found or v_event.status is null or v_event.status = '' then
    return jsonb_build_object(
      'applied', false,
      'reason', 'no_status_event',
      'external_message_id', p_external_message_id
    );
  end if;

  update public.messages
  set external_status = v_event.status,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'whatsapp_status', v_event.status,
        'whatsapp_status_payload', v_event.payload,
        'whatsapp_status_updated_at', now()
      )
  where external_provider = 'whatsapp'
    and external_message_id = p_external_message_id
  returning id, conversation_id into v_message;

  if v_message.id is null then
    return jsonb_build_object(
      'applied', false,
      'reason', 'message_not_found',
      'external_message_id', p_external_message_id,
      'status', v_event.status
    );
  end if;

  return jsonb_build_object(
    'applied', true,
    'message_id', v_message.id,
    'conversation_id', v_message.conversation_id,
    'external_message_id', p_external_message_id,
    'status', v_event.status
  );
end;
$$;

grant execute on function public.replay_whatsapp_message_status(text) to service_role;