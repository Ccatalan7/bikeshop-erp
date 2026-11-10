-- A WhatsApp voice note is stored as OGG/Opus, which Apple's players cannot
-- decode. The server stores a WAV twin at `<storage_path>.wav`
-- (supabase/functions/_shared/voice_note_twin.ts) and points the message to it
-- with `playback_storage_path`. The app signs that path with the operator's own
-- session.
--
-- The read policy matched only a registered attachment path, so that signature
-- was always refused. The Mac got nothing to play even when the twin existed
-- (2026-11-09, the first twin the webhook made: «No se pudo cargar»).
--
-- From here, the twin of an attached file is readable by whoever can read the
-- file. Nothing else rides on the rule:
-- - `messaging_attachments_path_check` keeps every registered path to a single
--   extension (`<tenant>/<conversation>/<id>.<ext>`), so `<path>.wav` is never
--   a registered path of its own;
-- - the insert policy lets a user upload only to their reserved path;
-- - therefore only the server can place an object at `<registered path>.wav`.
--
-- The `in (...)` keeps the lookup on the (storage_bucket, storage_path) unique
-- index for both the file and its twin.

create or replace function public.messaging_attachment_storage_can_read(
  p_bucket text,
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_bucket = 'chat-attachments'
    and exists (
      select 1
      from public.messaging_attachments attachment
      join public.conversations conversation
        on conversation.id = attachment.conversation_id
       and conversation.tenant_id = attachment.tenant_id
      where attachment.storage_bucket = p_bucket
        and attachment.storage_path in (
          p_path,
          case when p_path like '%.wav' then left(p_path, -4) end
        )
        and attachment.status = 'attached'
        and public.messaging_can_read_conversation_messages(
          attachment.conversation_id
        )
    );
$$;

comment on function public.messaging_attachment_storage_can_read(text, text) is
  'Storage read policy for chat-attachments: a registered attached file, and its WAV playback twin at <storage_path>.wav, for whoever can read the conversation.';
