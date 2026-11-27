-- Photos from the ERP to Instagram and Messenger (2026-11-26).
-- Covers begin_meta_outbound_media_send, the photo branch of
-- finalize_meta_outbound_send and the receipts that say which attempts were
-- photos. Text sends keep their contract; one regression proves it here.
begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('9f261126-0000-4000-8000-000000000001', 'Meta Photo Tenant A');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9f261126-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'meta-photo-staff@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f261126-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f261126-0000-4000-8000-000000000093',
    'authenticated', 'authenticated', 'meta-photo-coworker@example.invalid', '',
    now(), '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f261126-0000-4000-8000-000000000001'),
    now(), now()
  );

delete from public.user_profiles
where user_id in (
  '9f261126-0000-4000-8000-000000000091',
  '9f261126-0000-4000-8000-000000000093'
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    '9f261126-0000-4000-8000-000000000091',
    '9f261126-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f261126-0000-4000-8000-000000000093',
    '9f261126-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  );

insert into public.meta_channels (
  id, tenant_id, provider, external_account_id, display_name, is_active
) values (
  '9f261126-0001-4000-8000-000000000001',
  '9f261126-0000-4000-8000-000000000001',
  'instagram', 'ig-photo-account-a', 'Instagram Fotos A', true
);
select public.mark_meta_channel_subscribed(
  '9f261126-0001-4000-8000-000000000001'
);

select public.ingest_meta_message(
  'instagram',
  'ig-photo-account-a',
  'meta:instagram:message:ig-photo-account-a:mid-photo-in-1',
  'mid-photo-in-1',
  'ig-photo-user-1',
  'Cliente Foto',
  'cliente_foto',
  'text',
  '¿Me mandas una foto del cassette?',
  now() - interval '1 minute',
  '{"message_id":"mid-photo-in-1","message_type":"text"}'::jsonb
);

update public.meta_conversation_bindings
set reply_window_expires_at = now() + interval '23 hours'
where channel_id = '9f261126-0001-4000-8000-000000000001'
  and external_user_id = 'ig-photo-user-1';

create temporary table photo_values (
  key text primary key,
  value text not null
);
grant select, insert on photo_values to authenticated;
insert into photo_values (key, value)
select 'conversation', binding.conversation_id::text
from public.meta_conversation_bindings binding
where binding.channel_id = '9f261126-0001-4000-8000-000000000001'
  and binding.external_user_id = 'ig-photo-user-1';

-- The person who sends reserves the files in the private registry, as the
-- chat does before uploading.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f261126-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '9f261126-0000-4000-8000-000000000091', true
);
insert into photo_values (key, value)
select reservation.key, public.reserve_messaging_attachment(
  (select value::uuid from photo_values where key = 'conversation'),
  reservation.filename,
  reservation.mime,
  reservation.size_bytes
)::text
from (values
  ('jpg', 'cassette.jpg', 'image/jpeg', 2048::bigint),
  ('pdf', 'cotizacion.pdf', 'application/pdf', 1024::bigint),
  ('webp', 'producto.webp', 'image/webp', 1024::bigint),
  ('not_uploaded', 'sin-subir.png', 'image/png', 512::bigint)
) as reservation(key, filename, mime, size_bytes);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f261126-0000-4000-8000-000000000093"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '9f261126-0000-4000-8000-000000000093', true
);
insert into photo_values (key, value)
select 'coworker', public.reserve_messaging_attachment(
  (select value::uuid from photo_values where key = 'conversation'),
  'otra.jpg',
  'image/jpeg',
  1024
)::text;
reset role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Every reservation but one reaches storage.
insert into storage.objects (bucket_id, name, metadata)
select
  'chat-attachments',
  value::jsonb->>'storage_path',
  jsonb_build_object(
    'size', (value::jsonb->>'size_bytes')::bigint,
    'mimetype', value::jsonb->>'content_type'
  )
from photo_values
where key in ('jpg', 'pdf', 'webp', 'coworker');

create function pg_temp.photo_id(p_key text) returns uuid
language sql stable as $$
  select (value::jsonb->>'attachment_id')::uuid
  from photo_values where key = p_key
$$;
create function pg_temp.photo_fingerprint(p_key text) returns text
language sql stable as $$
  select encode(extensions.digest(convert_to(
    (select value from photo_values where key = 'conversation')
      || E'\nattachment:' || pg_temp.photo_id(p_key)::text,
    'UTF8'
  ), 'sha256'), 'hex')
$$;
create function pg_temp.begin_photo(
  p_key text,
  p_client_id text,
  p_actor uuid default '9f261126-0000-4000-8000-000000000091'
) returns jsonb
language sql volatile as $$
  select public.begin_meta_outbound_media_send(
    p_actor,
    (select value::uuid from photo_values where key = 'conversation'),
    p_client_id,
    pg_temp.photo_fingerprint(p_key),
    pg_temp.photo_id(p_key)
  )
$$;

select ok(
  not has_function_privilege(
    'authenticated',
    'public.begin_meta_outbound_media_send(uuid,uuid,text,text,uuid)',
    'EXECUTE'
  ),
  'only the send function prepares a photo, never the app directly'
);

select throws_ok(
  format(
    'select public.begin_meta_outbound_media_send(%L,%L,%L,%L,%L)',
    '9f261126-0000-4000-8000-000000000091',
    (select value from photo_values where key = 'conversation'),
    'photo-client-fingerprint',
    repeat('0', 64),
    pg_temp.photo_id('jpg')
  ),
  '23514',
  'Meta send request fingerprint does not match payload',
  'a photo request binds the conversation and the exact file'
);

select throws_ok(
  $$select pg_temp.begin_photo('pdf', 'photo-client-pdf')$$,
  '23514',
  'Meta only accepts JPG, PNG or GIF photos',
  'a PDF never goes to Instagram as a photo'
);

select throws_ok(
  $$select pg_temp.begin_photo('webp', 'photo-client-webp')$$,
  '23514',
  'Meta only accepts JPG, PNG or GIF photos',
  'a WebP reaches the server only after the chat converts it to JPG'
);

select throws_ok(
  $$select pg_temp.begin_photo('coworker', 'photo-client-coworker')$$,
  '23514',
  'Meta attachment reservation is not sendable',
  'nobody sends a file a coworker reserved'
);

select throws_ok(
  $$select pg_temp.begin_photo('not_uploaded', 'photo-client-not-uploaded')$$,
  'P0002',
  'Meta attachment upload is missing',
  'a reservation whose upload never landed is not sent'
);

update public.meta_conversation_bindings
set reply_window_expires_at = now() - interval '1 second'
where channel_id = '9f261126-0001-4000-8000-000000000001'
  and external_user_id = 'ig-photo-user-1';

select throws_ok(
  $$select pg_temp.begin_photo('jpg', 'photo-client-window-closed')$$,
  'P0001',
  'Meta 24-hour reply window is closed',
  'a photo waits for the same 24-hour window as a text'
);

update public.meta_conversation_bindings
set reply_window_expires_at = now() + interval '23 hours'
where channel_id = '9f261126-0001-4000-8000-000000000001'
  and external_user_id = 'ig-photo-user-1';

select is(
  (
    select count(*)::integer
    from public.meta_outbound_send_attempts attempt
    where attempt.conversation_id =
      (select value::uuid from photo_values where key = 'conversation')
  ),
  0,
  'a refused photo leaves no attempt behind'
);

insert into photo_values (key, value)
select 'prepared', pg_temp.begin_photo('jpg', 'photo-client-1')::text;

select is(
  (select value::jsonb->>'replayed' from photo_values where key = 'prepared'),
  'false',
  'a reserved, uploaded JPG inside the window is prepared'
);
select is(
  (select value::jsonb->>'storage_path' from photo_values where key = 'prepared'),
  (select value::jsonb->>'storage_path' from photo_values where key = 'jpg'),
  'the function gets the private path to sign a short link for Meta'
);
select is(
  (select value::jsonb->>'content_type' from photo_values where key = 'prepared'),
  'image/jpeg',
  'the prepared photo carries its type'
);
select is(
  (
    select attempt.attachment_id
    from public.meta_outbound_send_attempts attempt
    where attempt.id =
      (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'prepared')
  ),
  pg_temp.photo_id('jpg'),
  'the attempt records the photo it sends'
);
select is(
  (
    select attempt.message_text
    from public.meta_outbound_send_attempts attempt
    where attempt.id =
      (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'prepared')
  ),
  'cassette.jpg',
  'the attempt names the file it tried'
);

select is(
  pg_temp.begin_photo('jpg', 'photo-client-1')->>'replayed',
  'true',
  'the same photo with the same key is an exact replay'
);

select throws_ok(
  $$select pg_temp.begin_photo('coworker', 'photo-client-1')$$,
  '23514',
  'Meta idempotency key belongs to another request',
  'a key never moves to another file'
);

select throws_ok(
  $$select pg_temp.begin_photo('jpg', 'photo-client-again')$$,
  '23505',
  null,
  'one reserved photo has one provider attempt'
);

select throws_ok(
  format(
    'select public.begin_meta_outbound_send(%L,%L,%L,%L,%L)',
    '9f261126-0000-4000-8000-000000000091',
    (select value from photo_values where key = 'conversation'),
    'photo-client-1',
    encode(extensions.digest(convert_to(
      (select value from photo_values where key = 'conversation')
        || E'\nTexto con la llave de la foto',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Texto con la llave de la foto'
  ),
  '23514',
  'Meta idempotency key belongs to another request',
  'text and photo sends share one idempotency namespace'
);

select is(
  public.accept_meta_outbound_attempt(
    (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'prepared'),
    'mid-photo-out-1',
    '{"message_id":"mid-photo-out-1"}'::jsonb
  )->>'state',
  'provider_accepted',
  'Meta accepted the photo'
);

insert into photo_values (key, value)
select 'finalized', public.finalize_meta_outbound_send(
  (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'prepared'),
  'mid-photo-out-1',
  '{"message_id":"mid-photo-out-1"}'::jsonb
)::text;

select is(
  (select value::jsonb->>'state' from photo_values where key = 'finalized'),
  'finalized',
  'the accepted photo is finalized'
);

select is(
  (
    select message.type || ' / ' || message.content
    from public.messages message
    where message.id =
      (select (value::jsonb->>'message_id')::uuid from photo_values where key = 'finalized')
  ),
  'image / Imagen enviada',
  'the bubble is an image without the file name as its caption'
);
select is(
  (
    select jsonb_build_object(
      'attachment_id', message.metadata->>'attachment_id',
      'storage_path', message.metadata->>'storage_path',
      'filename', message.metadata->>'filename',
      'access', message.metadata->>'attachment_access',
      'client_message_id', message.metadata->>'client_message_id'
    )
    from public.messages message
    where message.id =
      (select (value::jsonb->>'message_id')::uuid from photo_values where key = 'finalized')
  ),
  jsonb_build_object(
    'attachment_id', pg_temp.photo_id('jpg')::text,
    'storage_path',
      (select value::jsonb->>'storage_path' from photo_values where key = 'jpg'),
    'filename', 'cassette.jpg',
    'access', 'private_signed_runtime',
    'client_message_id', 'photo-client-1'
  ),
  'the bubble carries the private file reference the chat signs at runtime'
);
select is(
  (
    select attachment.status || ' / ' || (attachment.message_id =
      (select (value::jsonb->>'message_id')::uuid from photo_values where key = 'finalized'))::text
    from public.messaging_attachments attachment
    where attachment.id = pg_temp.photo_id('jpg')
  ),
  'attached / true',
  'the reservation belongs to the bubble in the same transaction'
);

select is(
  public.finalize_meta_outbound_send(
    (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'prepared'),
    'mid-photo-out-1',
    '{}'::jsonb
  )->>'replayed',
  'true',
  'finalizing the photo twice replays the receipt'
);
select is(
  (
    select count(*)::integer
    from public.messages message
    where message.metadata->>'attachment_id' = pg_temp.photo_id('jpg')::text
  ),
  1,
  'a replayed finalize writes no second bubble'
);

-- A text after the photo keeps its contract.
insert into photo_values (key, value)
select 'text_prepared', public.begin_meta_outbound_send(
  '9f261126-0000-4000-8000-000000000091',
  (select value::uuid from photo_values where key = 'conversation'),
  'text-client-1',
  encode(extensions.digest(convert_to(
    (select value from photo_values where key = 'conversation')
      || E'\nAhí va la foto del cassette',
    'UTF8'
  ), 'sha256'), 'hex'),
  'Ahí va la foto del cassette'
)::text;
select public.accept_meta_outbound_attempt(
  (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'text_prepared'),
  'mid-text-out-1',
  '{}'::jsonb
);
insert into photo_values (key, value)
select 'text_finalized', public.finalize_meta_outbound_send(
  (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'text_prepared'),
  'mid-text-out-1',
  '{}'::jsonb
)::text;

select is(
  (
    select message.type || ' / ' || message.content || ' / '
      || (message.metadata ? 'attachment_id')::text
    from public.messages message
    where message.id =
      (select (value::jsonb->>'message_id')::uuid from photo_values where key = 'text_finalized')
  ),
  'text / Ahí va la foto del cassette / false',
  'a text still finalizes as plain text'
);

-- The guard admits an outbound image only as the accepted photo attempt's
-- own file: a text attempt never writes one, nor a photo attempt another file.
insert into photo_values (key, value)
select 'text_prepared_2', public.begin_meta_outbound_send(
  '9f261126-0000-4000-8000-000000000091',
  (select value::uuid from photo_values where key = 'conversation'),
  'text-client-2',
  encode(extensions.digest(convert_to(
    (select value from photo_values where key = 'conversation')
      || E'\nOtro texto',
    'UTF8'
  ), 'sha256'), 'hex'),
  'Otro texto'
)::text;
select public.accept_meta_outbound_attempt(
  (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'text_prepared_2'),
  'mid-text-out-2',
  '{}'::jsonb
);
select throws_ok(
  format(
    $sql$insert into public.messages (
      conversation_id, sender_id, tenant_id, content, type, metadata,
      external_provider, external_message_id, message_direction,
      external_status
    ) values (
      %L, '9f261126-0000-4000-8000-000000000091',
      '9f261126-0000-4000-8000-000000000001', 'Imagen enviada', 'image',
      jsonb_build_object('meta_attempt_id', %L, 'attachment_id', %L),
      'instagram', %L, 'outbound', 'accepted'
    )$sql$,
    (select value from photo_values where key = 'conversation'),
    (select value::jsonb->>'attempt_id' from photo_values where key = 'text_prepared_2'),
    pg_temp.photo_id('pdf'),
    '9f261126-0001-4000-8000-000000000001:mid-text-out-2'
  ),
  '42501',
  'Meta conversations require trusted provider transport',
  'a text attempt never writes an image into a Meta conversation'
);

insert into photo_values (key, value)
select 'coworker_prepared', pg_temp.begin_photo(
  'coworker',
  'photo-client-coworker',
  '9f261126-0000-4000-8000-000000000093'
)::text;
select public.accept_meta_outbound_attempt(
  (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'coworker_prepared'),
  'mid-photo-out-2',
  '{}'::jsonb
);
select throws_ok(
  format(
    $sql$insert into public.messages (
      conversation_id, sender_id, tenant_id, content, type, metadata,
      external_provider, external_message_id, message_direction,
      external_status
    ) values (
      %L, '9f261126-0000-4000-8000-000000000093',
      '9f261126-0000-4000-8000-000000000001', 'Imagen enviada', 'image',
      jsonb_build_object('meta_attempt_id', %L, 'attachment_id', %L),
      'instagram', %L, 'outbound', 'accepted'
    )$sql$,
    (select value from photo_values where key = 'conversation'),
    (select value::jsonb->>'attempt_id' from photo_values where key = 'coworker_prepared'),
    pg_temp.photo_id('jpg'),
    '9f261126-0001-4000-8000-000000000001:mid-photo-out-2'
  ),
  '42501',
  'Meta conversations require trusted provider transport',
  'a photo attempt never writes the image of another file'
);
select is(
  public.finalize_meta_outbound_send(
    (select (value::jsonb->>'attempt_id')::uuid from photo_values where key = 'coworker_prepared'),
    'mid-photo-out-2',
    '{}'::jsonb
  )->>'state',
  'finalized',
  'the same attempt finalizes with its own file'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f261126-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub', '9f261126-0000-4000-8000-000000000091', true
);
select is(
  (
    select jsonb_object_agg(receipt.client_message_id, receipt.attachment_id)
    from public.list_meta_outbound_send_receipts(
      (select value::uuid from photo_values where key = 'conversation')
    ) receipt
  ),
  jsonb_build_object(
    'photo-client-1', pg_temp.photo_id('jpg'),
    'text-client-1', null,
    'text-client-2', null,
    'photo-client-coworker', pg_temp.photo_id('coworker')
  ),
  'the receipts say which attempt was a photo'
);
reset role;

select * from finish();

rollback;
