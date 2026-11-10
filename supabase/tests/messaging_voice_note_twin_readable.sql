-- A voice note's WAV twin (`<storage_path>.wav`, made by the server for
-- Apple's players) is readable by whoever can read the note, and nothing else
-- rides on that rule (2026-11-09).
begin;

select plan(8);

insert into public.tenants (id, shop_name) values
  ('b0ce0000-0000-4000-8000-000000000001', 'Voice Note Twin Tenant'),
  ('b0ce0000-0000-4000-8000-000000000002', 'Voice Note Twin Other Tenant');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    'b0ce0000-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'twin-staff@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', 'b0ce0000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    'b0ce0000-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'twin-outsider@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', 'b0ce0000-0000-4000-8000-000000000002'),
    now(), now()
  );

-- Auth bootstrap triggers can create profiles; replace them with fixtures.
delete from public.user_profiles
where user_id in (
  'b0ce0000-0000-4000-8000-000000000091',
  'b0ce0000-0000-4000-8000-000000000092'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values
  (
    'b0ce0000-0000-4000-8000-000000000091',
    'b0ce0000-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    'b0ce0000-0000-4000-8000-000000000092',
    'b0ce0000-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'b0ce0000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', 'b0ce0000-0000-4000-8000-000000000091', true
);

insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values (
  'b0ce0000-0000-4000-8000-000000000311',
  'b0ce0000-0000-4000-8000-000000000001',
  'support', 'website_portal', 'Voice note', 'active',
  'b0ce0000-0000-4000-8000-000000000091'
);

create temporary table voice_note as
select public.reserve_messaging_attachment(
  'b0ce0000-0000-4000-8000-000000000311',
  'nota.ogg',
  'audio/ogg',
  128
) as reservation;

insert into storage.objects (bucket_id, name, metadata)
select
  'chat-attachments',
  reservation->>'storage_path',
  jsonb_build_object('size', 128, 'mimetype', 'audio/ogg')
from voice_note;

select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note) || '.wav'
  ),
  false,
  'a reserved note that is not attached yet has no readable twin'
);

select public.publish_messaging_attachment(
  (select (reservation->>'attachment_id')::uuid from voice_note),
  null
);

select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note)
  ),
  true,
  'the attached note is readable'
);
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note) || '.wav'
  ),
  true,
  'its WAV twin is readable by whoever can read the note'
);
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note) || '.mp3'
  ),
  false,
  'only the .wav twin rides on the note'
);
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    regexp_replace(
      (select reservation->>'storage_path' from voice_note), '\.ogg$', '.wav'
    )
  ),
  false,
  'a sibling path with another extension is not the twin'
);
select is(
  public.messaging_attachment_storage_can_read(
    'documents',
    (select reservation->>'storage_path' from voice_note) || '.wav'
  ),
  false,
  'the rule holds only in the chat attachment bucket'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'b0ce0000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub', 'b0ce0000-0000-4000-8000-000000000092', true
);

select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note) || '.wav'
  ),
  false,
  'another tenant cannot read the twin'
);
select is(
  public.messaging_attachment_storage_can_read(
    'chat-attachments',
    (select reservation->>'storage_path' from voice_note)
  ),
  false,
  'nor the note'
);

select * from finish();
rollback;
