-- Read-back: the private chat bucket must accept the voice-note WAV twin.
-- Divides by the match count, so an absent permission fails at SQL level.
select 1 / (
  select count(*)::int
  from storage.buckets
  where id = 'chat-attachments'
    and 'audio/wav' = any (allowed_mime_types)
) as wav_allowed;
