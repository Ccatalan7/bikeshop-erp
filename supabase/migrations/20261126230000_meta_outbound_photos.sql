-- Photos sent from the ERP to Instagram and Messenger (2026-11-26).
--
-- Until today `meta-send` only carried text, and the chat hid the attach
-- button on Instagram and Messenger conversations. A photo now follows the
-- same path as a WhatsApp file: the app reserves it in the private attachment
-- registry and uploads it; the function prepares the send here, hands Meta a
-- short-lived signed link to that object, and on Meta's acceptance the
-- finalizer writes the image bubble and attaches the file to it in one
-- transaction.
--
-- Meta accepts images on both channels as an attachment fetched from a URL;
-- Instagram takes PNG, JPEG and GIF up to 8 MB, so that is the contract on
-- both. The standard 24-hour reply window applies exactly as for text.
--
-- The trusted-transport guard on Meta conversations admitted only outbound
-- text; it now admits the image of an accepted photo attempt, and nothing
-- else. The durable receipts gain the attempt's attachment, so a recovered
-- bubble can say it was a photo.

alter table public.meta_outbound_send_attempts
  add column if not exists attachment_id uuid
    references public.messaging_attachments(id) on delete restrict;

-- One provider attempt per reserved file. A rejected photo starts over with a
-- fresh reservation, never the failed one.
create unique index if not exists meta_outbound_send_attempts_attachment_unique
  on public.meta_outbound_send_attempts (attachment_id)
  where attachment_id is not null;

comment on column public.meta_outbound_send_attempts.attachment_id is
  'The reserved photo this attempt sends instead of text; message_text then holds its file name.';

create or replace function public.begin_meta_outbound_media_send(
  p_actor_id uuid,
  p_conversation_id uuid,
  p_idempotency_key text,
  p_request_fingerprint text,
  p_attachment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_fingerprint text;
  v_conversation public.conversations%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_channel public.meta_channels%rowtype;
  v_attachment public.messaging_attachments%rowtype;
  v_attempt public.meta_outbound_send_attempts%rowtype;
  v_object_metadata jsonb;
  v_object_size bigint;
  v_object_mime text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta send preparation requires service role'
      using errcode = '42501';
  end if;
  if p_actor_id is null
     or p_conversation_id is null
     or p_attachment_id is null
     or nullif(btrim(p_idempotency_key), '') is null
     or length(btrim(p_idempotency_key)) > 200 then
    raise exception 'Valid actor, conversation, idempotency key and attachment are required'
      using errcode = '22023';
  end if;

  -- The same receipt discipline as a text send: the key, the actor, the
  -- conversation and the exact file are one request.
  v_fingerprint := encode(extensions.digest(convert_to(
    p_conversation_id::text || E'\nattachment:' || p_attachment_id::text,
    'UTF8'
  ), 'sha256'), 'hex');
  if lower(coalesce(p_request_fingerprint, '')) is distinct from v_fingerprint then
    raise exception 'Meta send request fingerprint does not match payload'
      using errcode = '23514';
  end if;

  select conversation.* into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id
  for share;
  if not found
     or v_conversation.type <> 'support'
     or v_conversation.channel not in ('instagram', 'facebook_messenger') then
    raise exception 'Meta support conversation not found' using errcode = 'P0002';
  end if;
  if v_conversation.status not in ('pending', 'active') then
    raise exception 'Meta conversation is closed' using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = p_actor_id
      and profile.tenant_id = v_conversation.tenant_id
      and coalesce(profile.is_active, true)
  ) then
    raise exception 'Meta send actor is not active staff in tenant'
      using errcode = '42501';
  end if;

  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.conversation_id = v_conversation.id
    and binding.tenant_id = v_conversation.tenant_id;
  if not found then
    raise exception 'Meta conversation binding not found' using errcode = 'P0002';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = v_binding.channel_id
    and channel.tenant_id = v_binding.tenant_id
    and channel.provider = v_conversation.channel
    and channel.is_active;
  if not found then
    raise exception 'Active Meta channel not found' using errcode = 'P0002';
  end if;
  if v_binding.reply_window_expires_at is null
     or v_binding.reply_window_expires_at <= clock_timestamp()
     or v_binding.reply_window_expires_at >
       clock_timestamp() + interval '24 hours 5 minutes' then
    raise exception 'Meta 24-hour reply window is closed'
      using errcode = 'P0001', hint = 'reply_window_closed';
  end if;

  -- Text and photo sends share one idempotency namespace per tenant.
  perform pg_advisory_xact_lock(hashtextextended(
    v_conversation.tenant_id::text || ':meta_send:' || btrim(p_idempotency_key),
    0
  ));
  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.tenant_id = v_conversation.tenant_id
    and attempt.idempotency_key = btrim(p_idempotency_key)
  for update;

  if found then
    if v_attempt.actor_id is distinct from p_actor_id
       or v_attempt.conversation_id is distinct from p_conversation_id
       or v_attempt.request_fingerprint is distinct from v_fingerprint
       or v_attempt.attachment_id is distinct from p_attachment_id then
      raise exception 'Meta idempotency key belongs to another request'
        using errcode = '23514';
    end if;
    return jsonb_strip_nulls(jsonb_build_object(
      'replayed', true,
      'attempt_id', v_attempt.id,
      'state', v_attempt.state,
      'tenant_id', v_attempt.tenant_id,
      'channel_id', v_attempt.channel_id,
      'binding_id', v_attempt.binding_id,
      'conversation_id', v_attempt.conversation_id,
      'client_message_id', v_attempt.idempotency_key,
      'provider', v_channel.provider,
      'external_account_id', v_channel.external_account_id,
      'external_user_id', v_binding.external_user_id,
      'attachment_id', v_attempt.attachment_id,
      'message_id', v_attempt.message_id,
      'external_message_id', v_attempt.external_message_id,
      'error_code', v_attempt.error_code,
      'error_message', v_attempt.error_message
    ));
  end if;

  -- The file must be this person's reservation in this conversation, still
  -- unsent, at its canonical private path, and already uploaded.
  select attachment.* into v_attachment
  from public.messaging_attachments attachment
  where attachment.id = p_attachment_id
    and attachment.tenant_id = v_conversation.tenant_id
  for update;
  if not found
     or v_attachment.conversation_id is distinct from v_conversation.id
     or v_attachment.created_by is distinct from p_actor_id
     or v_attachment.status <> 'reserved'
     or v_attachment.message_id is not null
     or v_attachment.storage_bucket <> 'chat-attachments'
     or v_attachment.storage_path is distinct from (
       v_conversation.tenant_id::text || '/' || v_conversation.id::text || '/'
         || v_attachment.id::text || '.' || v_attachment.extension
     ) then
    raise exception 'Meta attachment reservation is not sendable'
      using errcode = '23514', hint = 'attachment_not_sendable';
  end if;
  if v_attachment.declared_mime_type not in ('image/jpeg', 'image/png', 'image/gif') then
    raise exception 'Meta only accepts JPG, PNG or GIF photos'
      using errcode = '23514', hint = 'attachment_type_not_supported';
  end if;
  if v_attachment.size_bytes > 8388608 then
    raise exception 'Meta only accepts photos up to 8 MB'
      using errcode = '23514', hint = 'attachment_too_large';
  end if;

  select coalesce(object.metadata, '{}'::jsonb)
  into v_object_metadata
  from storage.objects object
  where object.bucket_id = 'chat-attachments'
    and object.name = v_attachment.storage_path;
  if not found then
    raise exception 'Meta attachment upload is missing'
      using errcode = 'P0002', hint = 'attachment_not_uploaded';
  end if;
  begin
    v_object_size := nullif(v_object_metadata->>'size', '')::bigint;
  exception when invalid_text_representation then
    v_object_size := null;
  end;
  v_object_mime := lower(split_part(coalesce(
    nullif(v_object_metadata->>'mimetype', ''),
    nullif(v_object_metadata->>'contentType', ''),
    ''
  ), ';', 1));
  if v_object_size is distinct from v_attachment.size_bytes
     or v_object_mime is distinct from v_attachment.declared_mime_type then
    raise exception 'Uploaded object does not match its reservation'
      using errcode = '23514', hint = 'attachment_not_sendable';
  end if;

  insert into public.meta_outbound_send_attempts (
    tenant_id,
    actor_id,
    channel_id,
    binding_id,
    conversation_id,
    idempotency_key,
    request_fingerprint,
    message_text,
    attachment_id,
    state
  ) values (
    v_conversation.tenant_id,
    p_actor_id,
    v_channel.id,
    v_binding.id,
    v_conversation.id,
    btrim(p_idempotency_key),
    v_fingerprint,
    v_attachment.original_filename,
    v_attachment.id,
    'prepared'
  ) returning * into v_attempt;

  return jsonb_build_object(
    'replayed', false,
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'tenant_id', v_attempt.tenant_id,
    'channel_id', v_attempt.channel_id,
    'binding_id', v_attempt.binding_id,
    'conversation_id', v_attempt.conversation_id,
    'client_message_id', v_attempt.idempotency_key,
    'provider', v_channel.provider,
    'external_account_id', v_channel.external_account_id,
    'external_user_id', v_binding.external_user_id,
    'reply_window_expires_at', v_binding.reply_window_expires_at,
    'attachment_id', v_attachment.id,
    'storage_bucket', v_attachment.storage_bucket,
    'storage_path', v_attachment.storage_path,
    'content_type', v_attachment.declared_mime_type
  );
end;
$$;

-- Same contract as before for text. A photo attempt writes an image bubble
-- that carries the private file reference, and attaches the reservation to it.
create or replace function public.finalize_meta_outbound_send(
  p_attempt_id uuid,
  p_external_message_id text,
  p_provider_response jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_raw_message_id text := btrim(coalesce(p_external_message_id, ''));
  v_attempt public.meta_outbound_send_attempts%rowtype;
  v_channel public.meta_channels%rowtype;
  v_binding public.meta_conversation_bindings%rowtype;
  v_message public.messages%rowtype;
  v_attachment public.messaging_attachments%rowtype;
  v_reference jsonb := '{}'::jsonb;
  v_canonical_message_id text;
  v_replayed_status text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta send finalization requires service role'
      using errcode = '42501';
  end if;
  if p_attempt_id is null or v_raw_message_id = ''
     or length(v_raw_message_id) > 512 then
    raise exception 'Meta provider message id is required' using errcode = '22023';
  end if;

  select attempt.* into v_attempt
  from public.meta_outbound_send_attempts attempt
  where attempt.id = p_attempt_id
  for update;
  if not found then
    raise exception 'Meta send attempt not found' using errcode = 'P0002';
  end if;
  if v_attempt.state = 'finalized' then
    if v_attempt.external_message_id is distinct from v_raw_message_id then
      raise exception 'Meta attempt already finalized with another provider id'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'replayed', true,
      'attempt_id', v_attempt.id,
      'state', v_attempt.state,
      'message_id', v_attempt.message_id,
      'client_message_id', v_attempt.idempotency_key,
      'external_message_id', v_attempt.external_message_id,
      'external_status', 'accepted'
    );
  end if;
  if v_attempt.state not in ('prepared', 'provider_accepted') then
    raise exception 'Meta send attempt is already terminal'
      using errcode = '23514';
  end if;
  if v_attempt.external_message_id is not null
     and v_attempt.external_message_id is distinct from v_raw_message_id then
    raise exception 'Meta attempt provider id is immutable'
      using errcode = '23514';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = v_attempt.channel_id
    and channel.tenant_id = v_attempt.tenant_id;
  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.id = v_attempt.binding_id
    and binding.tenant_id = v_attempt.tenant_id;
  if v_channel.id is null or v_binding.id is null then
    raise exception 'Meta send attempt dependencies are missing'
      using errcode = '23503';
  end if;

  if v_attempt.attachment_id is not null then
    select attachment.* into v_attachment
    from public.messaging_attachments attachment
    where attachment.id = v_attempt.attachment_id
      and attachment.tenant_id = v_attempt.tenant_id
    for update;
    if not found then
      raise exception 'Meta send attachment is missing' using errcode = '23503';
    end if;
    v_reference := jsonb_build_object(
      'attachment_id', v_attachment.id,
      'storage_bucket', v_attachment.storage_bucket,
      'storage_path', v_attachment.storage_path,
      'filename', v_attachment.original_filename,
      'extension', v_attachment.extension,
      'content_type', v_attachment.declared_mime_type,
      'size_bytes', v_attachment.size_bytes,
      'attachment_access', 'private_signed_runtime'
    );
  end if;

  update public.meta_outbound_send_attempts
  set state = 'provider_accepted',
      external_message_id = v_raw_message_id,
      provider_accepted_at = coalesce(provider_accepted_at, clock_timestamp()),
      provider_response = coalesce(p_provider_response, '{}'::jsonb),
      error_code = null,
      error_message = null,
      updated_at = clock_timestamp()
  where id = v_attempt.id
  returning * into v_attempt;

  v_canonical_message_id := v_attempt.channel_id::text || ':' || v_raw_message_id;
  select message.* into v_message
  from public.messages message
  where message.external_message_id = v_canonical_message_id;

  if found then
    if v_message.tenant_id is distinct from v_attempt.tenant_id
       or v_message.conversation_id is distinct from v_attempt.conversation_id
       or v_message.external_provider is distinct from v_channel.provider
       or v_message.message_direction is distinct from 'outbound' then
      raise exception 'Meta provider message id conflicts with another message'
        using errcode = '23514';
    end if;
  else
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
      external_status,
      created_at
    ) values (
      v_attempt.conversation_id,
      v_attempt.actor_id,
      v_attempt.tenant_id,
      -- A photo goes without a caption: its bubble carries the same filler a
      -- WhatsApp photo without text does, never the file name as a caption.
      case when v_attempt.attachment_id is null
        then v_attempt.message_text
        else 'Imagen enviada'
      end,
      case when v_attempt.attachment_id is null then 'text' else 'image' end,
      jsonb_build_object(
        'provider', v_channel.provider,
        'meta_attempt_id', v_attempt.id,
        'client_message_id', v_attempt.idempotency_key,
        'meta_channel_id', v_attempt.channel_id
      ) || v_reference,
      v_channel.provider,
      v_canonical_message_id,
      'outbound',
      'accepted',
      v_attempt.provider_accepted_at
    ) returning * into v_message;
  end if;

  -- The reservation belongs to this bubble from now on. A file another
  -- message already owns is a conflict, never a silent re-point.
  if v_attempt.attachment_id is not null then
    if v_attachment.message_id is not null
       and v_attachment.message_id is distinct from v_message.id then
      raise exception 'Meta send attachment belongs to another message'
        using errcode = '23514';
    end if;
    if v_attachment.status = 'reserved' then
      update public.messaging_attachments
      set status = 'attached',
          message_id = v_message.id,
          attached_at = clock_timestamp(),
          failed_at = null,
          failure_code = null
      where id = v_attachment.id;
    end if;
  end if;

  -- Echo/read/delivery webhooks can beat the Edge Function's final database
  -- write. Back-link that already durable evidence once the exact provider id
  -- has an authoritative message row.
  update public.meta_webhook_events event
  set conversation_id = v_attempt.conversation_id,
      message_id = v_message.id
  where event.channel_id = v_attempt.channel_id
    and event.external_message_id = v_raw_message_id
    and event.event_type in ('message_echo', 'message_status')
    and (event.conversation_id is null
      or event.conversation_id = v_attempt.conversation_id)
    and (event.message_id is null or event.message_id = v_message.id);

  select case
    when bool_or(event.event_type = 'message_status'
      and event.payload->>'status' = 'read') then 'read'
    when bool_or(event.event_type = 'message_status'
      and event.payload->>'status' = 'delivered') then 'delivered'
    when bool_or(event.event_type = 'message_echo') then 'sent'
    else null
  end into v_replayed_status
  from public.meta_webhook_events event
  where event.channel_id = v_attempt.channel_id
    and event.external_message_id = v_raw_message_id;

  if v_replayed_status is not null
     and public.meta_message_status_rank(v_message.external_status) <
       public.meta_message_status_rank(v_replayed_status) then
    update public.messages
    set external_status = v_replayed_status,
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'meta_status_replayed_at_finalize', true
        )
    where id = v_message.id
    returning * into v_message;
  end if;

  update public.meta_conversation_bindings
  set last_outbound_at = greatest(
        coalesce(last_outbound_at, '-infinity'::timestamptz),
        v_attempt.provider_accepted_at
      ),
      updated_at = clock_timestamp()
  where id = v_attempt.binding_id;

  update public.meta_outbound_send_attempts
  set state = 'finalized',
      message_id = v_message.id,
      finalized_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = v_attempt.id
  returning * into v_attempt;

  return jsonb_build_object(
    'replayed', false,
    'attempt_id', v_attempt.id,
    'state', v_attempt.state,
    'message_id', v_message.id,
    'client_message_id', v_attempt.idempotency_key,
    'external_message_id', v_attempt.external_message_id,
    'external_status', v_message.external_status,
    'conversation_id', v_attempt.conversation_id,
    'tenant_id', v_attempt.tenant_id
  );
end;
$$;

-- The guard that admits a row into an Instagram or Messenger conversation
-- only from trusted provider transport. Until today a trusted outbound row had
-- to be a text, so the finalizer's image bubble was refused («Meta
-- conversations require trusted provider transport»). The body is the live
-- one (supabase/sql/core_schema.sql; not the later text kept in
-- 20260721233000, which production never ran) with only the outbound rule
-- widened: an image is trusted when it is the accepted photo attempt's own
-- reserved file.
create or replace function public.enforce_messaging_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_tenant_id uuid;
  v_parent_status text;
  v_parent_type text;
  v_parent_channel text;
  v_resolution_event_capability text;
  v_is_trusted_provider_inbound boolean := false;
  v_is_trusted_meta_inbound boolean := false;
  v_is_trusted_meta_outbound boolean := false;
begin
  if tg_table_name = 'conversations' then
    if tg_op = 'UPDATE' then
      if new.tenant_id is distinct from old.tenant_id then
        raise exception 'Conversation tenant_id is immutable'
          using errcode = '23514';
      end if;
      if new.created_by is distinct from old.created_by then
        raise exception 'Conversation created_by is immutable'
          using errcode = '23514';
      end if;
      if new.channel is distinct from old.channel
         and (
           old.channel in ('instagram', 'facebook_messenger')
           or new.channel in ('instagram', 'facebook_messenger')
         ) then
        raise exception 'Meta conversation channel is immutable'
          using errcode = '23514';
      end if;
    elsif new.tenant_id is null then
      new.tenant_id := public.user_tenant_id();
    end if;

    if new.tenant_id is null then
      raise exception 'Conversation tenant_id is required'
        using errcode = '23502';
    end if;

    if tg_op = 'INSERT'
       and new.channel in ('instagram', 'facebook_messenger')
       and coalesce(auth.jwt()->>'role', auth.role(), '') <> 'service_role' then
      raise exception 'Meta conversations require trusted provider transport'
        using errcode = '42501';
    end if;

    if tg_op = 'INSERT'
       and auth.uid() is not null
       and coalesce(auth.jwt()->>'role', '') = 'authenticated' then
      new.created_by := auth.uid();
    end if;
    return new;
  end if;

  if new.conversation_id is null then
    raise exception '% conversation_id is required', tg_table_name
      using errcode = '23502';
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    select conversation.tenant_id,
           conversation.status,
           conversation.type,
           conversation.channel
    into v_parent_tenant_id,
         v_parent_status,
         v_parent_type,
         v_parent_channel
    from public.conversations conversation
    where conversation.id = new.conversation_id
    for share;
  else
    select conversation.tenant_id,
           conversation.status,
           conversation.type,
           conversation.channel
    into v_parent_tenant_id,
         v_parent_status,
         v_parent_type,
         v_parent_channel
    from public.conversations conversation
    where conversation.id = new.conversation_id;
  end if;

  if v_parent_tenant_id is null then
    raise exception 'Parent conversation not found' using errcode = '23503';
  end if;

  if new.tenant_id is null then
    new.tenant_id := v_parent_tenant_id;
  elsif new.tenant_id is distinct from v_parent_tenant_id then
    raise exception '% tenant_id must match its conversation', tg_table_name
      using errcode = '23514';
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    v_resolution_event_capability := nullif(current_setting(
      'app.messaging_resolution_event_conversation_id',
      true
    ), '');
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT'
     and v_parent_channel in ('instagram', 'facebook_messenger')
     and not coalesce((
       v_resolution_event_capability = new.conversation_id::text
       and new.type = 'system'
       and coalesce(new.metadata, '{}'::jsonb)->>'event' =
         'conversation_resolved'
     ), false) then
    v_is_trusted_meta_inbound := coalesce(
      coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
      and v_parent_type = 'support'
      and new.sender_id is null
      and new.type = 'text'
      and new.external_provider = v_parent_channel
      and new.message_direction = 'inbound'
      and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
      and exists (
        select 1
        from public.meta_webhook_events event
        join public.meta_conversation_bindings binding
          on binding.channel_id = event.channel_id
         and binding.tenant_id = event.tenant_id
         and binding.conversation_id = new.conversation_id
        where event.tenant_id = new.tenant_id
          and event.conversation_id = new.conversation_id
          and event.event_type = 'message'
          and event.direction = 'inbound'
          and event.external_message_id is not null
          and new.external_message_id =
            event.channel_id::text || ':' || event.external_message_id
      ),
      false
    );
    v_is_trusted_meta_outbound := coalesce(
      coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
      and v_parent_type = 'support'
      and v_parent_channel in ('instagram', 'facebook_messenger')
      and new.sender_id is not null
      and new.type in ('text', 'image')
      and new.external_provider = v_parent_channel
      and new.message_direction = 'outbound'
      and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
      and exists (
        select 1
        from public.meta_outbound_send_attempts attempt
        where attempt.id::text = coalesce(new.metadata, '{}'::jsonb)
          ->> 'meta_attempt_id'
          and attempt.tenant_id = new.tenant_id
          and attempt.conversation_id = new.conversation_id
          and attempt.actor_id = new.sender_id
          and attempt.state = 'provider_accepted'
          and new.external_message_id =
            attempt.channel_id::text || ':' || attempt.external_message_id
          -- A text attempt writes its text; a photo attempt writes the image
          -- of its own reserved file, never another (2026-11-26).
          and (
            (attempt.attachment_id is null and new.type = 'text')
            or (
              attempt.attachment_id is not null
              and new.type = 'image'
              and attempt.attachment_id::text =
                coalesce(new.metadata, '{}'::jsonb)->>'attachment_id'
            )
          )
      ),
      false
    );

    if not (v_is_trusted_meta_inbound or v_is_trusted_meta_outbound) then
      raise exception 'Meta conversations require trusted provider transport'
        using errcode = '42501';
    end if;
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT'
     and coalesce(v_parent_status, '') not in ('pending', 'active') then
    v_is_trusted_provider_inbound := coalesce(
      coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
      and v_parent_type = 'support'
      and v_parent_channel = 'whatsapp'
      and new.sender_id is null
      and coalesce(new.type, '') in ('text', 'image', 'file')
      and coalesce(new.external_provider, '') = 'whatsapp'
      and coalesce(new.message_direction, '') = 'inbound'
      and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
      and exists (
        select 1
        from public.whatsapp_webhook_events event
        join public.whatsapp_conversation_bindings binding
          on binding.channel_id = event.channel_id
         and binding.tenant_id = event.tenant_id
         and binding.conversation_id = new.conversation_id
        where event.tenant_id = new.tenant_id
          and event.event_key = 'message:' || new.external_message_id
          and event.event_type = 'message'
          and event.direction = 'inbound'
          and event.payload #>> '{message,id}' = new.external_message_id
      ),
      false
    );

    if not coalesce((
      (
        v_resolution_event_capability = new.conversation_id::text
        and new.type = 'system'
        and coalesce(new.metadata, '{}'::jsonb)->>'event' =
          'conversation_resolved'
      )
      or v_is_trusted_provider_inbound
      or v_is_trusted_meta_inbound
      or v_is_trusted_meta_outbound
    ), false) then
      raise exception 'Conversation is closed to new messages'
        using errcode = '23514';
    end if;
  end if;

  if tg_table_name = 'conversation_contexts' then
    if not public.messaging_context_belongs_to_tenant(
      new.context_type,
      new.context_id,
      v_parent_tenant_id
    ) then
      raise exception 'Messaging context does not belong to the conversation tenant'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- The durable receipts say which attempts were photos, so a recovered bubble
-- reads «Foto: archivo.jpg» instead of a bare file name. Adding a column to a
-- `returns table` function needs drop and create; both run in this one
-- migration transaction, so readers never see it missing.
drop function if exists public.list_meta_outbound_send_receipts(uuid);
create function public.list_meta_outbound_send_receipts(
  p_conversation_id uuid
)
returns table (
  attempt_id uuid,
  conversation_id uuid,
  actor_id uuid,
  client_message_id text,
  state text,
  message_text text,
  message_id uuid,
  external_message_id text,
  error_code text,
  error_message text,
  provider_accepted_at timestamptz,
  finalized_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  attachment_id uuid
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Meta receipt reader required'
      using errcode = '42501';
  end if;
  select conversation.* into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;
  if not found
     or v_conversation.channel not in ('instagram', 'facebook_messenger')
     or not public.messaging_is_staff_in_tenant(v_conversation.tenant_id)
     or not public.messaging_can_read_conversation_messages(v_conversation.id) then
    raise exception 'Meta send receipts are not available to this user'
      using errcode = '42501';
  end if;

  return query
  select
    attempt.id,
    attempt.conversation_id,
    attempt.actor_id,
    attempt.idempotency_key,
    attempt.state,
    attempt.message_text,
    attempt.message_id,
    attempt.external_message_id,
    attempt.error_code,
    attempt.error_message,
    attempt.provider_accepted_at,
    attempt.finalized_at,
    attempt.created_at,
    attempt.updated_at,
    attempt.attachment_id
  from public.meta_outbound_send_attempts attempt
  where attempt.tenant_id = v_conversation.tenant_id
    and attempt.conversation_id = v_conversation.id
    and (
      attempt.state in ('prepared', 'provider_accepted', 'outcome_unknown')
      or attempt.created_at >= now() - interval '30 days'
    )
  order by attempt.created_at asc, attempt.id asc;
end;
$$;

revoke all on function public.list_meta_outbound_send_receipts(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_meta_outbound_send_receipts(uuid)
  to authenticated;

revoke all on function public.begin_meta_outbound_media_send(
  uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.begin_meta_outbound_media_send(
  uuid, uuid, text, text, uuid
) to service_role;
revoke all on function public.finalize_meta_outbound_send(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.finalize_meta_outbound_send(uuid, text, jsonb)
  to service_role;

comment on function public.begin_meta_outbound_media_send(
  uuid, uuid, text, text, uuid
) is 'Service only: prepares one photo for Instagram or Messenger from a reserved, uploaded JPG, PNG or GIF of up to 8 MB, inside the 24-hour reply window, with the same exact-replay receipt as a text send.';
