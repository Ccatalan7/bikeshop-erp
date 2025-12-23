-- RPC to mark a conversation as read using server timestamp
-- This prevents clock skew issues where client time is behind server time

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  update public.conversation_participants
  set last_read_at = now()
  where conversation_id = p_conversation_id
  and user_id = auth.uid();
end;
$$;
