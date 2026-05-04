-- Fix unread badges for WhatsApp inbound messages.
-- WhatsApp inbound rows may have sender_id = null, and SQL `!=` does not
-- count null as different from the current user. Use the null-safe comparison.

create or replace view public.conversation_unread_counts as
select
  cp.conversation_id,
  cp.user_id,
  coalesce(count(m.id), 0)::integer as unread_count
from public.conversation_participants cp
left join public.messages m
  on m.conversation_id = cp.conversation_id
  and m.created_at > coalesce(cp.last_read_at, '1970-01-01'::timestamptz)
  and m.sender_id is distinct from cp.user_id
group by cp.conversation_id, cp.user_id;

grant select on public.conversation_unread_counts to authenticated;