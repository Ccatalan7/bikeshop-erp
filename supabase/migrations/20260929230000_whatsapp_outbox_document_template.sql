-- Una plantilla de WhatsApp con PDF adjunto (`documento_adjunto_v1`) pasa por
-- la misma cola durable que un documento: la reserva privada del archivo se
-- exige, se ata al mensaje y la fila nace como `file`.
--
-- Es la única forma de mandarle un archivo a un cliente o proveedor que no
-- escribió en las últimas 24 h: fuera de esa ventana Meta rechaza un
-- documento suelto, pero acepta una plantilla aprobada con el documento en el
-- encabezado. Qué plantilla lleva archivo lo decide el catálogo del servidor
-- (supabase/functions/_shared/whatsapp_templates.ts); whatsapp-send rechaza un
-- archivo en una plantilla sin encabezado.
--
-- Sólo cambia qué solicitudes reservan adjunto y el tipo de la fila; el resto
-- es la definición vigente en producción (20260903233000).

CREATE OR REPLACE FUNCTION public.enqueue_whatsapp_message_v1(p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_conversation uuid;
  v_channel public.whatsapp_channels%rowtype;
  v_job public.whatsapp_outbox%rowtype;
  v_message public.messages%rowtype;
  v_attachment public.messaging_attachments%rowtype;
  v_key text := nullif(btrim(p_request #>> '{metadata,client_message_id}'), '');
  v_hash text := encode(extensions.digest(p_request::text, 'sha256'), 'hex');
  v_phone text := public.normalize_whatsapp_phone(p_request->>'phoneNumber');
  v_type text := p_request->>'type';
  v_id uuid := gen_random_uuid();
  v_binding jsonb;
  v_metadata jsonb;
  -- Una plantilla con archivo (`documento_adjunto_v1`) trae su PDF reservado
  -- igual que un documento. Qué plantilla lo admite lo decide el catálogo de
  -- whatsapp-send; acá sólo se exige y se ata la reserva.
  v_has_attachment boolean := p_request->>'type' in ('image', 'document', 'audio')
    or (p_request->>'type' = 'template'
      and nullif(p_request->>'attachmentId', '') is not null);
begin
  if not public.messaging_is_staff_in_tenant(v_tenant) then
    raise exception 'Active messaging staff required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_request) is distinct from 'object'
     or octet_length(p_request::text) > 65536
     or v_key is null or length(v_key) > 128
     or v_phone is null or v_phone !~ '^[0-9]{8,15}$'
     or v_type is null or v_type not in ('text', 'template', 'image', 'document', 'audio', 'interactive') then
    raise exception 'Invalid WhatsApp outbox request' using errcode = '22023';
  end if;
  v_conversation := (p_request->>'conversationId')::uuid;
  -- Serialize only the idempotency key, not every message in the conversation.
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || ':' || v_key, 0));
  select * into v_job from public.whatsapp_outbox
  where tenant_id = v_tenant and actor_id = v_actor and client_message_id = v_key;
  if found then
    if v_job.request_hash <> v_hash then
      raise exception 'Idempotency key reused for a different message' using errcode = '22023';
    end if;
    select * into strict v_message from public.messages where id = v_job.message_id;
    return jsonb_build_object('ok', true, 'accepted', true, 'queued', true,
      'message_id', v_message.id, 'external_message_id', v_message.external_message_id,
      'external_status', coalesce(v_message.external_status, v_message.metadata->>'whatsapp_status'),
      'delivery_strategy', v_message.metadata->>'delivery_strategy', 'retry_safe', false);
  end if;

  if v_conversation is null or not public.messaging_can_write_conversation(v_conversation)
     or not exists (select 1 from public.conversations
       where id = v_conversation and tenant_id = v_tenant and channel = 'whatsapp') then
    raise exception 'Writable WhatsApp conversation required' using errcode = '42501';
  end if;
  if (v_type = 'text' and nullif(btrim(p_request->>'text'), '') is null)
     or (v_type = 'template' and nullif(btrim(p_request->>'templateName'), '') is null) then
    raise exception 'Message content is required' using errcode = '22023';
  end if;
  select * into v_channel from public.whatsapp_channels
  where tenant_id = v_tenant and is_active
    and (nullif(p_request->>'phoneNumberId', '') is null
      or phone_number_id = p_request->>'phoneNumberId')
  order by created_at limit 1;
  if not found then
    raise exception 'Active WhatsApp channel required' using errcode = '22023';
  end if;
  -- Existing conversation identity cannot be rebound by changing the request.
  if exists (select 1 from public.whatsapp_conversation_bindings
    where conversation_id = v_conversation
      and (channel_id <> v_channel.id or external_wa_id <> v_phone)) then
    raise exception 'WhatsApp recipient does not match conversation' using errcode = '42501';
  end if;
  -- The binding upkeep (contact name, customer context, participants and the
  -- conversation stamp) costs 150-350 ms of this transaction in production,
  -- and the delivery worker repeats it in the background on every send. On
  -- the acceptance path only the identity matters: a binding of this tenant
  -- that already names this conversation, channel and recipient is proof.
  -- Only a conversation without a binding pays for creating one here.
  if exists (select 1 from public.whatsapp_conversation_bindings
    where tenant_id = v_tenant and conversation_id = v_conversation
      and channel_id = v_channel.id and external_wa_id = v_phone) then
    v_binding := jsonb_build_object('conversation_id', v_conversation);
  else
    v_binding := public.ensure_whatsapp_conversation_binding(
      p_tenant_id => v_tenant, p_channel_id => v_channel.id, p_wa_id => v_phone,
      p_phone_number => v_phone, p_contact_name => p_request->>'contactName',
      p_customer_id => nullif(p_request->>'customerId', '')::uuid,
      p_conversation_id => v_conversation);
  end if;
  if (v_binding->>'conversation_id')::uuid is distinct from v_conversation then
    raise exception 'WhatsApp binding does not match conversation' using errcode = '42501';
  end if;

  -- Do not trust caller-supplied receipt/action/provider fields in the first
  -- durable row. The existing delivery handler reconstructs them later.
  v_metadata := jsonb_build_object('client_message_id', v_key,
    'channel', 'whatsapp', 'provider', 'whatsapp', 'outbound_type', v_type,
    'status', 'queued', 'pending', false, 'server_ack_durable', true);
  if nullif(btrim(p_request->>'replyToMessageId'), '') is not null then
    v_metadata := v_metadata || jsonb_build_object(
      'reply_to_external_message_id', btrim(p_request->>'replyToMessageId'));
  end if;
  if v_has_attachment then
    select * into v_attachment from public.messaging_attachments
    where id = nullif(p_request->>'attachmentId', '')::uuid
      and tenant_id = v_tenant and conversation_id = v_conversation
      and created_by = v_actor and status = 'reserved' for update;
    if not found then
      raise exception 'Sendable private attachment required' using errcode = '42501';
    end if;
    v_metadata := v_metadata || jsonb_build_object(
      'attachment_id', v_attachment.id, 'storage_bucket', v_attachment.storage_bucket,
      'storage_path', v_attachment.storage_path, 'filename', v_attachment.original_filename,
      'content_type', v_attachment.declared_mime_type, 'size_bytes', v_attachment.size_bytes);
  end if;
  insert into public.messages(id, conversation_id, tenant_id, sender_id, content,
    type, metadata, external_provider, message_direction, external_status)
  values (v_id, v_conversation, v_tenant, v_actor,
    coalesce(nullif(p_request->>'text', ''), nullif(p_request->>'caption', ''),
      p_request->>'templateName', v_attachment.original_filename, ''),
    case when v_type = 'image' then 'image'
      when v_type in ('document', 'audio') or v_attachment.id is not null then 'file'
      else 'text' end,
    v_metadata, 'whatsapp', 'outbound', 'queued');
  if v_attachment.id is not null then
    update public.messaging_attachments set status = 'attached', message_id = v_id,
      attached_at = now(), updated_at = now() where id = v_attachment.id;
  end if;
  insert into public.whatsapp_outbox(message_id, tenant_id, actor_id, client_message_id,
    request, request_hash)
  values (v_id, v_tenant, v_actor, v_key,
    p_request || jsonb_build_object('phoneNumber', v_phone, 'phoneNumberId', v_channel.phone_number_id), v_hash);
  -- pg_net runs after commit. A scheduler outage cannot undo the accepted row.
  begin
    perform public.dispatch_whatsapp_outbox_v1();
  exception when others then
    update public.whatsapp_outbox set last_error = 'dispatch_deferred'
    where message_id = v_id;
  end;
  return jsonb_build_object('ok', true, 'accepted', true, 'queued', true,
    'message_id', v_id, 'external_status', 'queued', 'retry_safe', false);
end;
$function$;
