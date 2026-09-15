-- Prueba funcional del ingreso de reacciones de WhatsApp.
--
-- Usa el payload EXACTO que Meta entregó en producción el 2026-08-20 (evento
-- 48048c87-a586-4068-bdae-3c93ecfff902), no uno inventado: la forma del sobre
-- —`message.reaction.emoji` y `message.reaction.message_id`— es justamente lo
-- que nadie estaba leyendo.
--
-- Todo ocurre dentro de una transacción que termina en ROLLBACK.

begin;

do $$
declare
  v_tenant_id uuid;
  v_channel_id uuid;
  v_conversation_id uuid;
  v_target_message_id uuid;
  v_result jsonb;
  v_messages_before integer;
  v_messages_after integer;
  v_emoji text;
  v_reaction_count integer;
begin
  insert into public.tenants (shop_name) values ('Probe Shop')
  returning id into v_tenant_id;

  insert into public.whatsapp_channels (tenant_id, phone_number_id, is_active)
  values (v_tenant_id, '1107058485829123', true)
  returning id into v_channel_id;

  -- `created_by` se rellena solo y apunta a `users`, que este probe no puebla.
  -- El trigger que protege el grafo de inquilinos exige type='support' y
  -- channel='whatsapp' para poder enlazar el canal.
  insert into public.conversations (
    tenant_id, type, counterparty_type, channel, created_by
  )
  values (v_tenant_id, 'support', 'customer', 'whatsapp', null)
  returning id into v_conversation_id;

  insert into public.whatsapp_conversation_bindings (
    tenant_id, conversation_id, channel_id, external_wa_id
  ) values (v_tenant_id, v_conversation_id, v_channel_id, '56976431387');

  -- El mensaje saliente al que se le reacciona.
  insert into public.messages (
    conversation_id, tenant_id, content, type,
    external_provider, external_message_id, message_direction
  ) values (
    v_conversation_id, v_tenant_id,
    'Hola Claudio, buen día.', 'text',
    'whatsapp',
    'wamid.HBgLNTY5NzY0MzEzODcVAgARGBIyNjM3RURFN0E3NjY2RjhDRjYA',
    'outbound'
  ) returning id into v_target_message_id;

  select count(*) into v_messages_before from public.messages;

  -- ---- 1. Llega la reacción ------------------------------------------------
  v_result := public.ingest_whatsapp_inbound_message(
    p_phone_number_id => '1107058485829123',
    p_external_message_id => 'wamid.REACTION_EVENT_1',
    p_wa_id => '56976431387',
    p_phone_number => '+56976431387',
    p_contact_name => 'Claudio Catalán',
    p_message_type => 'reaction',
    p_message_body => 'reaction',
    p_payload => jsonb_build_object(
      'message', jsonb_build_object(
        'id', 'wamid.REACTION_EVENT_1',
        'from', '56976431387',
        'type', 'reaction',
        'reaction', jsonb_build_object(
          'emoji', '👍',
          'message_id',
            'wamid.HBgLNTY5NzY0MzEzODcVAgARGBIyNjM3RURFN0E3NjY2RjhDRjYA'
        )
      )
    )
  );

  select count(*) into v_messages_after from public.messages;

  if v_messages_after <> v_messages_before then
    raise exception 'FALLA: la reacción creó un mensaje (antes=% después=%)',
      v_messages_before, v_messages_after;
  end if;

  select emoji into v_emoji
  from public.message_reactions
  where message_id = v_target_message_id;

  if v_emoji is distinct from '👍' then
    raise exception 'FALLA: la reacción no quedó guardada (emoji=%)', v_emoji;
  end if;

  raise notice 'OK 1/4 · la reacción se guarda y NO crea mensaje';

  -- ---- 2. Cambiarla reemplaza, no acumula ---------------------------------
  v_result := public.ingest_whatsapp_inbound_message(
    p_phone_number_id => '1107058485829123',
    p_external_message_id => 'wamid.REACTION_EVENT_2',
    p_wa_id => '56976431387',
    p_phone_number => '+56976431387',
    p_contact_name => 'Claudio Catalán',
    p_message_type => 'reaction',
    p_message_body => 'reaction',
    p_payload => jsonb_build_object(
      'message', jsonb_build_object(
        'type', 'reaction',
        'reaction', jsonb_build_object(
          'emoji', '❤️',
          'message_id',
            'wamid.HBgLNTY5NzY0MzEzODcVAgARGBIyNjM3RURFN0E3NjY2RjhDRjYA'
        )
      )
    )
  );

  select count(*), max(emoji) into v_reaction_count, v_emoji
  from public.message_reactions
  where message_id = v_target_message_id;

  if v_reaction_count <> 1 or v_emoji is distinct from '❤️' then
    raise exception
      'FALLA: WhatsApp permite una reacción por persona (n=% emoji=%)',
      v_reaction_count, v_emoji;
  end if;

  raise notice 'OK 2/4 · una segunda reacción reemplaza a la primera';

  -- ---- 3. Emoji vacío la quita --------------------------------------------
  v_result := public.ingest_whatsapp_inbound_message(
    p_phone_number_id => '1107058485829123',
    p_external_message_id => 'wamid.REACTION_EVENT_3',
    p_wa_id => '56976431387',
    p_phone_number => '+56976431387',
    p_contact_name => 'Claudio Catalán',
    p_message_type => 'reaction',
    p_message_body => 'reaction',
    p_payload => jsonb_build_object(
      'message', jsonb_build_object(
        'type', 'reaction',
        'reaction', jsonb_build_object(
          'emoji', '',
          'message_id',
            'wamid.HBgLNTY5NzY0MzEzODcVAgARGBIyNjM3RURFN0E3NjY2RjhDRjYA'
        )
      )
    )
  );

  select count(*) into v_reaction_count
  from public.message_reactions
  where message_id = v_target_message_id;

  if v_reaction_count <> 0 then
    raise exception 'FALLA: el emoji vacío debe quitar la reacción (n=%)',
      v_reaction_count;
  end if;

  raise notice 'OK 3/4 · el emoji vacío la retira';

  -- ---- 4. Una reacción a un mensaje que no conocemos no inventa nada -------
  select count(*) into v_messages_before from public.messages;

  v_result := public.ingest_whatsapp_inbound_message(
    p_phone_number_id => '1107058485829123',
    p_external_message_id => 'wamid.REACTION_EVENT_4',
    p_wa_id => '56976431387',
    p_phone_number => '+56976431387',
    p_contact_name => 'Claudio Catalán',
    p_message_type => 'reaction',
    p_message_body => 'reaction',
    p_payload => jsonb_build_object(
      'message', jsonb_build_object(
        'type', 'reaction',
        'reaction', jsonb_build_object(
          'emoji', '👍',
          'message_id', 'wamid.DESCONOCIDO'
        )
      )
    )
  );

  select count(*) into v_messages_after from public.messages;

  if v_messages_after <> v_messages_before then
    raise exception 'FALLA: una reacción huérfana creó un mensaje';
  end if;

  if v_result->>'ignored_reason' is distinct from 'reaction_target_not_found' then
    raise exception 'FALLA: se esperaba reaction_target_not_found, llegó %',
      v_result::text;
  end if;

  raise notice 'OK 4/4 · una reacción huérfana se ignora sin inventar mensaje';
  raise notice 'TODO OK';
end;
$$;

rollback;
