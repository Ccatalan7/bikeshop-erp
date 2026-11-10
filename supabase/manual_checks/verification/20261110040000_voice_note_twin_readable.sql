-- Read-back for 20261110040000_voice_note_twin_readable: a staff reader of
-- the tenant can sign the newest stored voice note's WAV twin, as the app
-- does, and the rule lets nothing else through. Plain SQL; it fails with
-- «division by zero» when the invariant is missing.

select set_config(
  'request.jwt.claims',
  json_build_object(
    'sub', (
      select profile.user_id::text
      from public.user_profiles profile
      where profile.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and profile.is_active
        and profile.role = 'admin'
      order by profile.created_at
      limit 1
    ),
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  (current_setting('request.jwt.claims')::json)->>'sub',
  true
);

with note as (
  select
    attachment.storage_path,
    message.metadata->>'playback_storage_path' as twin_path
  from public.messaging_attachments attachment
  join public.messages message
    on message.id = attachment.message_id
   and message.tenant_id = attachment.tenant_id
  where attachment.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and attachment.status = 'attached'
    and message.metadata ? 'playback_storage_path'
  order by attachment.attached_at desc
  limit 1
)
select
  twin_path = storage_path || '.wav' as twin_next_to_note,
  public.messaging_attachment_storage_can_read('chat-attachments', storage_path) as note_readable,
  public.messaging_attachment_storage_can_read('chat-attachments', twin_path) as twin_readable,
  public.messaging_attachment_storage_can_read('chat-attachments', storage_path || '.mp3') as other_suffix_readable
from note;

with note as (
  select
    attachment.storage_path,
    message.metadata->>'playback_storage_path' as twin_path
  from public.messaging_attachments attachment
  join public.messages message
    on message.id = attachment.message_id
   and message.tenant_id = attachment.tenant_id
  where attachment.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and attachment.status = 'attached'
    and message.metadata ? 'playback_storage_path'
  order by attachment.attached_at desc
  limit 1
)
select 1 / (
  case when (
    select count(*) = 1
      and bool_and(twin_path = storage_path || '.wav')
      and bool_and(public.messaging_attachment_storage_can_read('chat-attachments', storage_path))
      and bool_and(public.messaging_attachment_storage_can_read('chat-attachments', twin_path))
      and not bool_or(
        public.messaging_attachment_storage_can_read('chat-attachments', storage_path || '.mp3')
      )
    from note
  ) then 1 else 0 end
) as voice_note_twin_is_readable_by_its_readers;
