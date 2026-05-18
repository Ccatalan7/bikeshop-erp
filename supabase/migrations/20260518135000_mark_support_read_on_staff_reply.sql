-- Treat staff replies as shared handling/read events for support inboxes.
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-05-18
-- Deployment verification: live update_conversation_timestamp() updates staff_last_read_at
--
-- If one teammate answers a customer, the team inbox should not keep counting
-- earlier customer messages as unread for everyone else.

begin;

alter table public.conversations
  add column if not exists staff_last_read_at timestamptz;

create or replace function public.update_conversation_timestamp()
returns trigger
language plpgsql
as $$
declare
  v_sender_is_staff boolean := false;
  v_message_direction text := to_jsonb(new)->>'message_direction';
begin
  if new.sender_id is not null then
    select exists (
      select 1
      from public.user_profiles up
      where up.user_id = new.sender_id
    ) into v_sender_is_staff;
  end if;

  update public.conversations
  set last_message_at = new.created_at,
      updated_at = new.created_at,
      staff_last_read_at = case
        when type = 'support'
          and v_sender_is_staff
          and coalesce(new.type, 'text') <> 'system'
          and coalesce(v_message_direction, 'outbound') <> 'inbound'
        then greatest(
          coalesce(staff_last_read_at, '1970-01-01'::timestamptz),
          new.created_at
        )
        else staff_last_read_at
      end
  where id = new.conversation_id;

  return new;
end;
$$;

update public.conversations c
set staff_last_read_at = greatest(
  coalesce(c.staff_last_read_at, '1970-01-01'::timestamptz),
  handled.handled_at
)
from (
  select
    m.conversation_id,
    max(m.created_at) as handled_at
  from public.messages m
  join public.conversations c2 on c2.id = m.conversation_id
  where c2.type = 'support'
    and m.sender_id is not null
    and coalesce(m.type, 'text') <> 'system'
    and coalesce(to_jsonb(m)->>'message_direction', 'outbound') <> 'inbound'
    and exists (
      select 1
      from public.user_profiles up
      where up.user_id = m.sender_id
    )
  group by m.conversation_id
) handled
where c.id = handled.conversation_id
  and c.type = 'support'
  and (
    c.staff_last_read_at is null
    or c.staff_last_read_at < handled.handled_at
  );

commit;
