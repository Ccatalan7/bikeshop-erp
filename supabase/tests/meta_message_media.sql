-- A photo sent by Instagram or Messenger reaches the ERP as a file in the
-- private attachment registry, not as the words «Imagen recibida»
-- (2026-11-10). The function claims the message, uploads the file and the
-- database attaches it.
begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('c0a7ed1a-0000-4000-8000-000000000001', 'Meta Media Tenant A'),
  ('c0a7ed1a-0000-4000-8000-000000000002', 'Meta Media Tenant B');

-- Staff of each tenant, to read the stored file as the app does.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'c0a7ed1a-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'media-staff@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', 'c0a7ed1a-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    'c0a7ed1a-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'media-outsider@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', 'c0a7ed1a-0000-4000-8000-000000000002'),
    now(), now()
  );
-- Auth bootstrap triggers can create profiles; replace them with fixtures.
delete from public.user_profiles
where user_id in (
  'c0a7ed1a-0000-4000-8000-000000000091',
  'c0a7ed1a-0000-4000-8000-000000000092'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values
  (
    'c0a7ed1a-0000-4000-8000-000000000091',
    'c0a7ed1a-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    'c0a7ed1a-0000-4000-8000-000000000092',
    'c0a7ed1a-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  );

create or replace function pg_temp.act_as(p_user uuid)
returns void
language sql
as $$
  select set_config(
    'request.jwt.claims',
    case when p_user is null then '{"role":"service_role"}'
      else jsonb_build_object('sub', p_user, 'role', 'authenticated')::text end,
    true
  );
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
$$;

insert into public.meta_channels (
  id, tenant_id, provider, external_account_id, display_name, is_active
) values
  (
    'c0a7ed1a-0001-4000-8000-000000000001',
    'c0a7ed1a-0000-4000-8000-000000000001',
    'instagram', 'ig-media-account-a', 'Instagram Media A', true
  ),
  (
    'c0a7ed1a-0001-4000-8000-000000000002',
    'c0a7ed1a-0000-4000-8000-000000000002',
    'instagram', 'ig-media-account-b', 'Instagram Media B', true
  );

create or replace function pg_temp.receive(
  p_account text, p_mid text, p_user text, p_type text, p_body text,
  p_age interval default interval '1 minute'
)
returns uuid
language sql
as $$
  select (public.ingest_meta_message(
    'instagram', p_account,
    'meta:instagram:message:' || p_account || ':' || p_mid, p_mid,
    p_user, null, null, p_type, p_body, now() - p_age,
    jsonb_build_object('message_id', p_mid, 'message_type', p_type)
  )->>'message_id')::uuid;
$$;

create temporary table received as
select
  pg_temp.receive('ig-media-account-a', 'mid-text', 'ig-media-user-1', 'text', 'Hola') as text_id,
  pg_temp.receive('ig-media-account-a', 'mid-photo', 'ig-media-user-1', 'image', 'Imagen recibida') as photo_id,
  pg_temp.receive('ig-media-account-a', 'mid-voice', 'ig-media-user-1', 'audio', 'Audio recibido') as voice_id,
  pg_temp.receive('ig-media-account-a', 'mid-story', 'ig-media-user-1', 'unsupported', 'Contenido adjunto recibido') as story_id,
  pg_temp.receive('ig-media-account-b', 'mid-photo-b', 'ig-media-user-b', 'image', 'Imagen recibida') as other_tenant_photo_id;

create or replace function pg_temp.store(p_message_id uuid, p_attachment_id uuid, p_extension text, p_mime text, p_size bigint)
returns text
language sql
as $$
  insert into storage.objects (bucket_id, name, metadata)
  select 'chat-attachments',
    message.tenant_id::text || '/' || message.conversation_id::text || '/'
      || p_attachment_id::text || '.' || p_extension,
    jsonb_build_object('size', p_size, 'mimetype', p_mime)
  from public.messages message
  where message.id = p_message_id
  returning name;
$$;

-- 1. Until the file arrives the message is the placeholder it always was.
select is(
  (
    select message.type || ' / ' || message.content || ' / '
      || (message.metadata->>'media_placeholder')
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  'text / Imagen recibida / true',
  'a photo starts as a text placeholder'
);

-- 2. Only messages with a storable file are due.
create temporary table first_claim as
select public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10) as claim;

select is(
  (
    select array_agg(item->>'media_type' order by item->>'media_type')
    from first_claim, jsonb_array_elements(claim->'messages') item
  ),
  array['audio', 'image'],
  'the photo and the voice message are due; the text and the story are not'
);
select is(
  (
    select item - 'conversation_id'
    from first_claim, jsonb_array_elements(claim->'messages') item
    where item->>'media_type' = 'image'
  ),
  jsonb_build_object(
    'message_id', (select photo_id from received),
    'tenant_id', 'c0a7ed1a-0000-4000-8000-000000000001',
    'external_message_id', 'mid-photo',
    'media_type', 'image'
  ),
  'a claim names the message that will own the file and the id Meta knows it by'
);
select is(
  (
    select (item->>'conversation_id')::uuid = message.conversation_id
    from first_claim, jsonb_array_elements(claim->'messages') item
    join public.messages message on message.id = (item->>'message_id')::uuid
    where item->>'media_type' = 'image'
  ),
  true,
  'and its conversation, where the file is stored'
);
select is(
  jsonb_array_length(
    public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10)
      ->'messages'
  ),
  0,
  'a claimed message is not handed out twice'
);
select is(
  public.claim_meta_message_media((select photo_id from received)),
  null,
  'nor to the webhook while the schedule holds it'
);

-- 3. The uploaded file is attached: the message becomes an image bubble.
select pg_temp.store(
  (select photo_id from received),
  'c0a7ed1a-00aa-4000-8000-000000000001', 'jpg', 'image/jpeg', 48211
);
select is(
  public.attach_meta_message_media(
    (select photo_id from received),
    'c0a7ed1a-00aa-4000-8000-000000000001',
    'imagen.jpg', 'jpg', 'image/jpeg', 48211
  )->>'attached',
  'true',
  'an uploaded photo is attached'
);
select is(
  (
    select message.type || ' / ' || message.content
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  'image / Imagen recibida',
  'the message is an image now; its text stays the placeholder apps hide'
);
select is(
  (
    select message.metadata - array[
      'provider', 'meta_channel_id', 'meta_event_id', 'contact_label', 'message_type'
    ]
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  (
    select jsonb_build_object(
      'attachment_id', 'c0a7ed1a-00aa-4000-8000-000000000001',
      'storage_bucket', 'chat-attachments',
      'storage_path', message.tenant_id::text || '/' || message.conversation_id::text
        || '/c0a7ed1a-00aa-4000-8000-000000000001.jpg',
      'filename', 'imagen.jpg',
      'extension', 'jpg',
      'content_type', 'image/jpeg',
      'size_bytes', 48211,
      'attachment_access', 'private_signed_runtime'
    )
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  'its metadata carries the private reference apps already sign, and nothing else new'
);
select is(
  (
    select message.metadata ?| array[
      'url', 'media_url', 'image_url', 'file_url', 'external_message_id',
      'external_user_id', 'external_account_id', 'contact_name', 'username'
    ]
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  false,
  'no URL of Meta and no raw id reaches the message'
);
select is(
  (
    select attachment.status || ' / ' || attachment.declared_mime_type
      || ' / ' || (attachment.created_by is null)::text
    from public.messaging_attachments attachment
    where attachment.message_id = (select photo_id from received)
  ),
  'attached / image/jpeg / true',
  'the registry owns the file, attached to its message'
);
select is(
  (
    select (event.media_attached_at is not null)::text || ' / '
      || coalesce(event.media_error, 'sin motivo')
    from public.meta_webhook_events event
    where event.message_id = (select photo_id from received)
  ),
  'true / sin motivo',
  'the event is settled'
);

-- 4. Whoever can read the conversation can read the file, and nobody else.
create temporary table photo_file as
select message.metadata->>'storage_path' as path
from public.messages message
where message.id = (select photo_id from received);
grant select on photo_file to public;

select pg_temp.act_as('c0a7ed1a-0000-4000-8000-000000000091');
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments', (select path from photo_file)
  ),
  true,
  'staff of the tenant can read the file through the storage policy'
);
select pg_temp.act_as('c0a7ed1a-0000-4000-8000-000000000092');
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments', (select path from photo_file)
  ),
  false,
  'staff of another tenant cannot'
);
select pg_temp.act_as(null);

-- 5. One file per message.
select pg_temp.store(
  (select photo_id from received),
  'c0a7ed1a-00aa-4000-8000-000000000002', 'jpg', 'image/jpeg', 100
);
select is(
  public.attach_meta_message_media(
    (select photo_id from received),
    'c0a7ed1a-00aa-4000-8000-000000000002',
    'imagen.jpg', 'jpg', 'image/jpeg', 100
  ),
  jsonb_build_object('attached', false, 'reason', 'already_attached'),
  'a second file for the same message is refused, so its upload is discarded'
);
select is(
  (
    select count(*)::integer
    from public.messaging_attachments attachment
    where attachment.message_id = (select photo_id from received)
  ),
  1,
  'and the first one stays'
);

-- 6. What is declared must be what was stored.
select throws_ok(
  format(
    $$select public.attach_meta_message_media(%L, 'c0a7ed1a-00aa-4000-8000-000000000003', 'audio.m4a', 'm4a', 'audio/mp4', 9000)$$,
    (select voice_id from received)
  ),
  'P0002',
  null,
  'a file that was never uploaded cannot be attached'
);
select pg_temp.store(
  (select voice_id from received),
  'c0a7ed1a-00aa-4000-8000-000000000003', 'm4a', 'audio/mp4', 9000
);
select throws_ok(
  format(
    $$select public.attach_meta_message_media(%L, 'c0a7ed1a-00aa-4000-8000-000000000003', 'audio.m4a', 'm4a', 'audio/mp4', 9001)$$,
    (select voice_id from received)
  ),
  '23514',
  null,
  'nor one whose stored size differs from the declared one'
);
select throws_ok(
  format(
    $$select public.attach_meta_message_media(%L, 'c0a7ed1a-00aa-4000-8000-000000000003', 'audio.m4a', 'm4a', 'image/jpeg', 9000)$$,
    (select voice_id from received)
  ),
  '23514',
  null,
  'nor one declared as another type'
);
select is(
  (
    select message.type || ' / ' || (message.metadata ? 'attachment_id')::text
    from public.messages message
    where message.id = (select voice_id from received)
  ),
  'text / false',
  'a refused file leaves the message as it was'
);

-- 7. A voice message is a file whose type starts with audio, as from WhatsApp.
select is(
  public.attach_meta_message_media(
    (select voice_id from received),
    'c0a7ed1a-00aa-4000-8000-000000000003',
    'audio.m4a', 'm4a', 'audio/mp4', 9000, true
  )->>'attached',
  'true',
  'an uploaded voice message is attached'
);
select is(
  (
    select message.type || ' / ' || (message.metadata->>'content_type')
      || ' / ' || (message.metadata ? 'playback_storage_path')::text
    from public.messages message
    where message.id = (select voice_id from received)
  ),
  'file / audio/mp4 / false',
  'it is a file with an audio type; a twin that was never stored is not promised'
);

-- 7b. Several files in one message: the first is kept and the bubble says so.
create temporary table album as
select pg_temp.receive(
  'ig-media-account-a', 'mid-album', 'ig-media-user-1', 'image', 'Imagen recibida'
) as message_id;
select pg_temp.store(
  (select message_id from album),
  'c0a7ed1a-00aa-4000-8000-000000000004', 'jpg', 'image/jpeg', 700
);
select public.attach_meta_message_media(
  (select message_id from album),
  'c0a7ed1a-00aa-4000-8000-000000000004',
  'imagen.jpg', 'jpg', 'image/jpeg', 700, false, 2
);
select is(
  (
    select message.metadata->>'caption'
    from public.messages message
    where message.id = (select message_id from album)
  ),
  'Llegaron 3 archivos en este mensaje. Este es el primero; el resto se ve en Instagram.',
  'the operator is told where the other files are'
);
select is(
  (
    select message.metadata ? 'caption'
    from public.messages message
    where message.id = (select photo_id from received)
  ),
  false,
  'a single file has no such note'
);

-- 8. Only inbound Meta messages take a file this way.
select pg_temp.act_as('c0a7ed1a-0000-4000-8000-000000000091');
insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values (
  'c0a7ed1a-00cc-4000-8000-000000000001',
  'c0a7ed1a-0000-4000-8000-000000000001',
  'support', 'website_portal', 'Otra conversación', 'active',
  'c0a7ed1a-0000-4000-8000-000000000091'
);
insert into public.messages (
  id, conversation_id, tenant_id, sender_id, content, type, metadata
) values (
  'c0a7ed1a-00dd-4000-8000-000000000001',
  'c0a7ed1a-00cc-4000-8000-000000000001',
  'c0a7ed1a-0000-4000-8000-000000000001',
  'c0a7ed1a-0000-4000-8000-000000000091',
  'Hola desde el portal', 'text', '{}'::jsonb
);
select pg_temp.act_as(null);
select throws_ok(
  $$select public.attach_meta_message_media(
      'c0a7ed1a-00dd-4000-8000-000000000001',
      'c0a7ed1a-00aa-4000-8000-000000000009',
      'imagen.jpg', 'jpg', 'image/jpeg', 10
    )$$,
  'P0002',
  null,
  'a message that did not come from Meta is refused'
);

-- 9. The webhook claims the message it just stored.
create temporary table fresh as
select pg_temp.receive(
  'ig-media-account-a', 'mid-photo-2', 'ig-media-user-1', 'image', 'Imagen recibida'
) as message_id;

select is(
  public.claim_meta_message_media((select message_id from fresh))->>'external_message_id',
  'mid-photo-2',
  'a fresh photo is claimed by its message'
);
select is(
  public.claim_meta_message_media((select message_id from fresh)),
  null,
  'once'
);
select is(
  public.claim_meta_message_media((select text_id from received)),
  null,
  'a text message has nothing to claim'
);

-- 10. An outage is tried again on the next run; a refusal waits a day.
select is(
  public.fail_meta_message_media((select message_id from fresh), 'download_503', true),
  true,
  'a failure is recorded'
);
select is(
  (
    select event.media_error || ' / ' || event.media_attempts
      || ' / ' || (event.media_checked_at is null)::text
    from public.meta_webhook_events event
    where event.message_id = (select message_id from fresh)
  ),
  'download_503 / 1 / true',
  'an outage keeps its reason and is due again at once'
);
select is(
  jsonb_array_length(
    public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10)
      ->'messages'
  ),
  1,
  'so the schedule picks it up'
);
select public.fail_meta_message_media((select message_id from fresh), 'graph_10', false);
select is(
  jsonb_array_length(
    public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10)
      ->'messages'
  ),
  0,
  'a refusal is not asked again the same day'
);
update public.meta_webhook_events
set media_checked_at = clock_timestamp() - interval '25 hours'
where message_id = (select message_id from fresh);
select is(
  jsonb_array_length(
    public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10)
      ->'messages'
  ),
  1,
  'it is asked again a day later'
);

-- 11. Nothing is asked for ever.
update public.meta_webhook_events
set media_attempts = 8,
    media_checked_at = null
where message_id = (select message_id from fresh);
select is(
  jsonb_array_length(
    public.claim_meta_message_media_due('instagram', 'ig-media-account-a', 10)
      ->'messages'
  ),
  0,
  'after eight tries the message keeps its placeholder'
);
select is(
  public.claim_meta_message_media((select message_id from fresh)),
  null,
  'for the webhook too'
);

-- 12. Tenants do not see each other's messages.
select is(
  (
    select array_agg((item->>'message_id')::uuid)
    from jsonb_array_elements(
      public.claim_meta_message_media_due('instagram', 'ig-media-account-b', 10)
        ->'messages'
    ) item
  ),
  array[(select other_tenant_photo_id from received)],
  'a claim returns only the messages of its own channel'
);
select is(
  public.claim_meta_message_media_due('instagram', 'no-such-account', 3)->'messages',
  '[]'::jsonb,
  'an unknown account claims nothing'
);

-- 13. Only the server reaches any of it.
select is(
  has_function_privilege('authenticated', 'public.claim_meta_message_media_due(text,text,integer)', 'execute')
  or has_function_privilege('anon', 'public.claim_meta_message_media_due(text,text,integer)', 'execute')
  or has_function_privilege('authenticated', 'public.claim_meta_message_media(uuid)', 'execute')
  or has_function_privilege('anon', 'public.claim_meta_message_media(uuid)', 'execute')
  or has_function_privilege('authenticated', 'public.attach_meta_message_media(uuid,uuid,text,text,text,bigint,boolean,integer)', 'execute')
  or has_function_privilege('anon', 'public.attach_meta_message_media(uuid,uuid,text,text,text,bigint,boolean,integer)', 'execute')
  or has_function_privilege('authenticated', 'public.fail_meta_message_media(uuid,text,boolean)', 'execute')
  or has_function_privilege('anon', 'public.fail_meta_message_media(uuid,text,boolean)', 'execute'),
  false,
  'no signed-in or anonymous user can claim, attach or fail a message file'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  format(
    $$select public.attach_meta_message_media(%L, 'c0a7ed1a-00aa-4000-8000-000000000009', 'imagen.jpg', 'jpg', 'image/jpeg', 10)$$,
    'c0a7ed1a-00dd-4000-8000-000000000001'
  ),
  '42501',
  null,
  'a signed-in user cannot attach a file to a message'
);
reset role;

select * from finish();
rollback;
