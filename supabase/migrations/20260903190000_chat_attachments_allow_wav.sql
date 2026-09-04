-- Voice notes from WhatsApp arrive as OGG/Opus, which Apple's players cannot
-- decode. The whatsapp-media function keeps the original and stores a small
-- WAV twin next to it for playback; the private bucket has to accept that
-- twin. Idempotent: a bucket that already allows audio/wav is left alone.
update storage.buckets
set allowed_mime_types = array_append(allowed_mime_types, 'audio/wav')
where id = 'chat-attachments'
  and not ('audio/wav' = any (coalesce(allowed_mime_types, '{}'::text[])));
