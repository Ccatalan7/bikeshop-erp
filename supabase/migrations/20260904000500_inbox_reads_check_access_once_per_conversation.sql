-- The inbox reload paid row-level security per message row: the unread view
-- averaged 4.5 s and the latest-message read 2.1 s (pg_stat_statements,
-- 2026-09-03), because every scanned message re-ran the messaging access
-- functions and their subplans. Both reads now run as security definer and
-- decide access once per conversation with the same predicates; the counting
-- and the per-conversation lookup are plain index scans.
begin;

create or replace function public.inbox_unread_counts_v1()
returns table (conversation_id uuid, user_id uuid, unread_count integer)
language sql stable security definer
set search_path = pg_catalog, public
as $$
  with me as (
    select auth.uid() as user_id
  ),
  -- Same predicate as messaging_is_staff_in_tenant, evaluated once.
  staff_tenants as (
    select profile.tenant_id
    from public.user_profiles profile
    join public.tenants tenant on tenant.id = profile.tenant_id and tenant.is_active is true
    join me on me.user_id = profile.user_id
    where profile.is_active is true
  ),
  participant_scope as (
    select participant.conversation_id,
           participant.user_id,
           participant.last_read_at,
           participant.last_read_message_sequence,
           conversation.type as conversation_type,
           conversation.tenant_id,
           conversation.staff_last_read_at,
           conversation.staff_last_read_message_sequence,
           exists (select 1 from staff_tenants st where st.tenant_id = conversation.tenant_id) as participant_is_staff
    from public.conversation_participants participant
    join public.conversations conversation on conversation.id = participant.conversation_id
    join me on me.user_id = participant.user_id
    where participant.tenant_id = conversation.tenant_id
      and public.messaging_can_access_conversation(conversation.id)
    union all
    select conversation.id as conversation_id,
           me.user_id,
           null::timestamptz as last_read_at,
           null::bigint as last_read_message_sequence,
           conversation.type as conversation_type,
           conversation.tenant_id,
           conversation.staff_last_read_at,
           conversation.staff_last_read_message_sequence,
           true as participant_is_staff
    from public.conversations conversation
    join staff_tenants st on st.tenant_id = conversation.tenant_id
    cross join me
    where conversation.type = 'support'
      and public.messaging_can_read_conversation_messages(conversation.id)
      and not exists (
        select 1 from public.conversation_participants participant
        where participant.conversation_id = conversation.id
          and participant.tenant_id = conversation.tenant_id
          and participant.user_id = me.user_id)
  ),
  marker_scope as (
    select ps.*,
           case when ps.conversation_type = 'support' and ps.participant_is_staff
                then greatest(ps.last_read_message_sequence, ps.staff_last_read_message_sequence)
                else ps.last_read_message_sequence end as read_message_sequence,
           case when ps.conversation_type = 'support' and ps.participant_is_staff
                     and ps.last_read_message_sequence is null and ps.staff_last_read_message_sequence is null
                then greatest(coalesce(ps.last_read_at, '1970-01-01 00:00:00+00'::timestamptz),
                              coalesce(ps.staff_last_read_at, '1970-01-01 00:00:00+00'::timestamptz))
                when ps.conversation_type = 'support' and ps.participant_is_staff
                     and coalesce(ps.staff_last_read_message_sequence, -1::bigint) >= coalesce(ps.last_read_message_sequence, -1::bigint)
                then coalesce(ps.staff_last_read_at, '1970-01-01 00:00:00+00'::timestamptz)
                else coalesce(ps.last_read_at, '1970-01-01 00:00:00+00'::timestamptz) end as read_at
    from participant_scope ps
  )
  select marker.conversation_id,
         marker.user_id,
         coalesce(count(message.id), 0)::integer as unread_count
  from marker_scope marker
  left join public.messages message
    on message.conversation_id = marker.conversation_id
   and message.tenant_id = marker.tenant_id
   and ((marker.read_message_sequence is not null and message.message_sequence > marker.read_message_sequence)
        or (marker.read_message_sequence is null and message.created_at > marker.read_at))
   and coalesce(message.type, 'text') <> 'system'
   and case when marker.conversation_type = 'support' and marker.participant_is_staff
            then message.message_direction = 'inbound'
                 or (message.message_direction is null
                     and (message.sender_id is null
                          or exists (select 1 from public.customers sender_customer
                                     where sender_customer.auth_user_id = message.sender_id
                                       and sender_customer.tenant_id = marker.tenant_id)))
            else message.sender_id is distinct from marker.user_id end
  group by marker.conversation_id, marker.user_id;
$$;
revoke all on function public.inbox_unread_counts_v1() from public, anon;
grant execute on function public.inbox_unread_counts_v1() to authenticated, service_role;

-- Same columns, same rows: installed clients keep selecting the view.
create or replace view public.conversation_unread_counts as
  select conversation_id, user_id, unread_count from public.inbox_unread_counts_v1();
-- The view keeps invoker rights (messaging_access_hardening asserts it); the
-- access decision itself now lives in the definer function it delegates to.
alter view public.conversation_unread_counts set (security_invoker = true);

create or replace function public.inbox_latest_messages_v1(p_conversation_ids uuid[])
returns table (
  id uuid, conversation_id uuid, content text, type text, sender_id uuid,
  created_at timestamptz, message_sequence bigint, metadata jsonb,
  message_direction text, external_status text, external_provider text,
  external_message_id text
)
language sql stable security definer
set search_path = pg_catalog, public
as $$
  -- Three per conversation: the client skips WhatsApp companion rows itself.
  select m.id, m.conversation_id, m.content, m.type, m.sender_id, m.created_at,
         m.message_sequence, m.metadata, m.message_direction, m.external_status,
         m.external_provider, m.external_message_id
  from unnest(coalesce(p_conversation_ids, '{}'::uuid[])) as wanted(conversation_id)
  join public.conversations c on c.id = wanted.conversation_id
  cross join lateral (
    select x.* from public.messages x
    where x.conversation_id = c.id and x.tenant_id = c.tenant_id
    order by x.message_sequence desc nulls last, x.created_at desc nulls last
    limit 3
  ) m
  where auth.uid() is not null
    and cardinality(p_conversation_ids) <= 500
    and public.messaging_can_read_conversation_messages(c.id)
  order by m.conversation_id, m.message_sequence desc nulls last, m.created_at desc nulls last;
$$;
revoke all on function public.inbox_latest_messages_v1(uuid[]) from public, anon;
grant execute on function public.inbox_latest_messages_v1(uuid[]) to authenticated, service_role;

comment on function public.inbox_unread_counts_v1() is
  'Unread counts for auth.uid(); access decided once per conversation with the messaging predicates, counting without per-row RLS.';
comment on function public.inbox_latest_messages_v1(uuid[]) is
  'Latest three messages per readable conversation for inbox previews; access decided once per conversation.';
commit;
