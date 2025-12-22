-- Enable Realtime for Messaging System
-- Supabase requires explicit addition of tables to the 'supabase_realtime' publication to broadcast events.

begin;

  -- specific tables to broadcast
  alter publication supabase_realtime add table public.messages;
  alter publication supabase_realtime add table public.conversations;
  alter publication supabase_realtime add table public.conversation_participants;

commit;
