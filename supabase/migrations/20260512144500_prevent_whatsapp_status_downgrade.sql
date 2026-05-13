create or replace function public.record_whatsapp_message_status(
  p_phone_number_id text,
  p_external_message_id text,
  p_status text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel record;
  v_event_key text;
  v_row_count integer;
  v_job_id uuid;
  v_replay_result jsonb;
  v_message_id uuid;
  v_conversation_id uuid;
begin
  select * into v_channel
  from public.whatsapp_channels
  where phone_number_id = p_phone_number_id
    and is_active = true
  limit 1;

  if not found then
    raise exception 'WhatsApp channel not found for phone_number_id %', p_phone_number_id;
  end if;

  v_event_key := 'status:' || p_external_message_id || ':' || lower(coalesce(p_status, 'unknown')) || ':' || coalesce(p_payload->>'timestamp', '');

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
    'status',
    'system',
    p_payload
  ) on conflict (channel_id, event_key) do nothing;

  get diagnostics v_row_count = row_count;

  v_replay_result := public.replay_whatsapp_message_status(p_external_message_id);
  v_message_id := nullif(v_replay_result->>'message_id', '')::uuid;
  v_conversation_id := nullif(v_replay_result->>'conversation_id', '')::uuid;

  if v_conversation_id is not null and lower(p_status) = 'read' then
    select cc.context_id into v_job_id
    from public.conversation_contexts cc
    where cc.conversation_id = v_conversation_id
      and cc.context_type = 'job'
    order by cc.is_primary desc, cc.added_at asc
    limit 1;

    if v_job_id is not null then
      perform public.log_mechanic_job_timeline(
        v_job_id,
        'whatsapp_read',
        null,
        p_external_message_id,
        'Customer read a WhatsApp message linked to this job'
      );
    end if;
  end if;

  return jsonb_build_object(
    'duplicate', v_row_count = 0,
    'event_key', v_event_key,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id,
    'status', v_replay_result->>'status',
    'status_applied', coalesce((v_replay_result->>'applied')::boolean, false),
    'external_message_id', p_external_message_id
  );
end;
$$;

grant execute on function public.record_whatsapp_message_status(text, text, text, jsonb) to service_role;