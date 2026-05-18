-- Shared read state for staff-facing support/WhatsApp inboxes.
--
-- Internal chats still use each participant's own last_read_at. Support chats
-- use staff_last_read_at for staff users so one teammate reading a customer
-- thread clears the shared team inbox badge.

begin;

alter table public.conversations
  add column if not exists staff_last_read_at timestamptz;

update public.conversations c
set staff_last_read_at = latest.last_read_at
from (
  select
    cp.conversation_id,
    max(cp.last_read_at) as last_read_at
  from public.conversation_participants cp
  join public.conversations c2 on c2.id = cp.conversation_id
  where c2.type = 'support'
    and exists (
      select 1
      from public.user_profiles up
      where up.user_id = cp.user_id
    )
  group by cp.conversation_id
) latest
where c.id = latest.conversation_id
  and c.type = 'support'
  and (
    c.staff_last_read_at is null
    or c.staff_last_read_at < latest.last_read_at
  );

create or replace view public.conversation_unread_counts as
with participant_scope as (
  select
    cp.conversation_id,
    cp.user_id,
    cp.last_read_at,
    c.type as conversation_type,
    c.staff_last_read_at,
    exists (
      select 1
      from public.user_profiles up
      where up.user_id = cp.user_id
    ) as participant_is_staff
  from public.conversation_participants cp
  join public.conversations c on c.id = cp.conversation_id
)
select
  ps.conversation_id,
  ps.user_id,
  coalesce(count(m.id), 0)::integer as unread_count
from participant_scope ps
left join public.messages m
  on m.conversation_id = ps.conversation_id
  and m.created_at > case
    when ps.conversation_type = 'support' and ps.participant_is_staff then
      greatest(
        coalesce(ps.last_read_at, '1970-01-01'::timestamptz),
        coalesce(ps.staff_last_read_at, '1970-01-01'::timestamptz)
      )
    else coalesce(ps.last_read_at, '1970-01-01'::timestamptz)
  end
  and coalesce(m.type, 'text') <> 'system'
  and case
    when ps.conversation_type = 'support' and ps.participant_is_staff then
      m.message_direction = 'inbound'
      or (
        m.message_direction is null
        and (
          m.sender_id is null
          or not exists (
            select 1
            from public.user_profiles sender_profile
            where sender_profile.user_id = m.sender_id
          )
        )
      )
    else m.sender_id is distinct from ps.user_id
  end
group by ps.conversation_id, ps.user_id;

grant select on public.conversation_unread_counts to authenticated;

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_conversation record;
  v_is_staff boolean := false;
begin
  if v_user_id is null then
    return;
  end if;

  select id, type, tenant_id, created_by
  into v_conversation
  from public.conversations
  where id = p_conversation_id;

  if not found then
    return;
  end if;

  select exists (
    select 1
    from public.user_profiles up
    where up.user_id = v_user_id
  ) into v_is_staff;

  if not (
    v_conversation.created_by = v_user_id
    or exists (
      select 1
      from public.conversation_participants cp
      where cp.conversation_id = p_conversation_id
        and cp.user_id = v_user_id
    )
    or (
      v_conversation.type = 'support'
      and v_is_staff
      and v_conversation.tenant_id = public.user_tenant_id()
    )
  ) then
    raise exception 'Not allowed to mark this conversation as read'
      using errcode = '42501';
  end if;

  update public.conversation_participants
  set last_read_at = v_now
  where conversation_id = p_conversation_id
    and user_id = v_user_id;

  if v_conversation.type = 'support' and v_is_staff then
    update public.conversations
    set staff_last_read_at = v_now
    where id = p_conversation_id;
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'messages'
    ) then
      alter publication supabase_realtime add table public.messages;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'conversations'
    ) then
      alter publication supabase_realtime add table public.conversations;
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'conversation_participants'
    ) then
      alter publication supabase_realtime add table public.conversation_participants;
    end if;
  end if;
end $$;

commit;
