begin;

-- Block 2a (2026-09-16): ERP notifications and messaging change signals are
-- emitted by triggers as tenant-private Broadcast rows (realtime.messages)
-- instead of being observed through postgres_changes subscriptions.
-- Requires migration 20260916010000 applied to the fixture.

select plan(13);

insert into public.tenants (id, shop_name)
values ('99999999-2000-4999-8999-999999999999', 'Broadcast Test Tenant');

insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('99999999-2091-4999-8999-999999999999', 'authenticated', 'authenticated',
   'broadcast-staff@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id = '99999999-2091-4999-8999-999999999999';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('99999999-2091-4999-8999-999999999999', '99999999-2000-4999-8999-999999999999', 'admin', '{}', true);

-- Supabase manages daily realtime.messages partitions in hosted environments;
-- the local Realtime container only created them while it ran (2026-08-08 to
-- 2026-08-12 on the 2026-09-16 fixture), and realtime.send swallows the
-- "no partition" error as a WARNING. Create the current day's partition
-- inside the fixture transaction so it rolls back with the test.
do $$
begin
  if to_regclass('realtime.messages') is not null then
    begin
      execute format(
        'create table realtime.%I partition of realtime.messages '
        'for values from (%L) to (%L)',
        'messages_broadcast_test_' || pg_backend_pid()::text,
        date_trunc('day', current_timestamp),
        date_trunc('day', current_timestamp) + interval '1 day'
      );
    exception
      when duplicate_table or invalid_object_definition then
        null;
    end;
  end if;
end
$$;

select has_trigger('public', 'erp_notifications', 'trg_erp_notifications_broadcast',
  'erp_notifications rows are broadcast by trigger');
select has_trigger('public', 'messages', 'trg_messages_broadcast',
  'messages rows are broadcast by trigger');
select has_trigger('public', 'conversations', 'trg_conversations_broadcast',
  'conversations rows are broadcast by trigger');
select has_trigger('public', 'conversation_participants', 'trg_conversation_participants_broadcast',
  'conversation_participants rows are broadcast by trigger');

-- A notification without a recipient reaches the tenant ':all' topic with
-- the full row, exactly what postgres_changes used to deliver.
insert into public.erp_notifications (id, tenant_id, type, title, severity)
values ('99999999-2001-4999-8999-999999999999', '99999999-2000-4999-8999-999999999999',
        'test_broadcast', 'Aviso de prueba', 'info');

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'erp-notifications:99999999-2000-4999-8999-999999999999:all'
      and extension = 'broadcast'
      and event = 'changed'
      and payload ->> 'operation' = 'insert'
      and payload -> 'record' ->> 'id' = '99999999-2001-4999-8999-999999999999'
      and payload -> 'record' ->> 'title' = 'Aviso de prueba'
  ),
  1,
  'an insert without recipient is broadcast once to the tenant all-topic with its row'
);

update public.erp_notifications
set read_at = now()
where id = '99999999-2001-4999-8999-999999999999';

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'erp-notifications:99999999-2000-4999-8999-999999999999:all'
      and payload ->> 'operation' = 'update'
      and payload -> 'record' ->> 'read_at' is not null
  ),
  1,
  'an update is broadcast with the updated row'
);

-- A notification with a recipient reaches only that recipient's topic.
-- Fixtures older than the recipient_user_id column skip this check visibly.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'erp_notifications'
      and column_name = 'recipient_user_id'
  ) then
    insert into public.erp_notifications (id, tenant_id, type, title, severity, recipient_user_id)
    values ('99999999-2002-4999-8999-999999999999', '99999999-2000-4999-8999-999999999999',
            'test_broadcast', 'Aviso personal', 'info', '99999999-2091-4999-8999-999999999999');
  end if;
end
$$;

select case
  when exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'erp_notifications'
      and column_name = 'recipient_user_id'
  ) then is(
    (
      select count(*)::integer
      from realtime.messages
      where payload -> 'record' ->> 'id' = '99999999-2002-4999-8999-999999999999'
        and topic = 'erp-notifications:99999999-2000-4999-8999-999999999999:99999999-2091-4999-8999-999999999999'
    ),
    1,
    'a notification with a recipient is broadcast to that recipient topic only'
  )
  else skip('recipient_user_id column absent on this fixture', 1)
end;

select is(
  (
    select count(*)::integer
    from realtime.messages
    where payload -> 'record' ->> 'id' = '99999999-2002-4999-8999-999999999999'
      and topic like '%:all'
  ),
  0,
  'a notification with a recipient never reaches the all-topic'
);

-- Messaging: payload-minimal signals on the tenant topic.
insert into public.conversations (id, tenant_id, type, title, status, created_by)
values ('99999999-2010-4999-8999-999999999999', '99999999-2000-4999-8999-999999999999',
        'support', 'Broadcast test', 'active', null);

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'messaging:99999999-2000-4999-8999-999999999999'
      and payload ->> 'table' = 'conversations'
      and payload ->> 'operation' = 'insert'
      and payload ->> 'conversation_id' = '99999999-2010-4999-8999-999999999999'
  ),
  1,
  'a new conversation is signalled on the tenant messaging topic'
);

insert into public.messages (id, conversation_id, tenant_id, content, type, metadata, created_at)
values ('99999999-2011-4999-8999-999999999999', '99999999-2010-4999-8999-999999999999',
        '99999999-2000-4999-8999-999999999999', 'contenido que no debe viajar', 'text', '{}'::jsonb, now());

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'messaging:99999999-2000-4999-8999-999999999999'
      and payload ->> 'table' = 'messages'
      and payload ->> 'operation' = 'insert'
      and payload ->> 'message_id' = '99999999-2011-4999-8999-999999999999'
      and payload ->> 'conversation_id' = '99999999-2010-4999-8999-999999999999'
  ),
  1,
  'a new message is signalled with its ids'
);

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'messaging:99999999-2000-4999-8999-999999999999'
      and (payload ? 'content' or payload ? 'sender_id' or payload::text like '%contenido que no debe viajar%')
  ),
  0,
  'message content and sender never travel through the broadcast payload'
);

update public.messages
set external_status = 'delivered'
where id = '99999999-2011-4999-8999-999999999999';

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'messaging:99999999-2000-4999-8999-999999999999'
      and payload ->> 'table' = 'messages'
      and payload ->> 'operation' = 'update'
      and payload ->> 'external_status' = 'delivered'
  ),
  1,
  'a delivery status change is signalled with the new status'
);

insert into public.conversation_participants (conversation_id, tenant_id, user_id)
values ('99999999-2010-4999-8999-999999999999', '99999999-2000-4999-8999-999999999999',
        '99999999-2091-4999-8999-999999999999');

select is(
  (
    select count(*)::integer
    from realtime.messages
    where topic = 'messaging:99999999-2000-4999-8999-999999999999'
      and payload ->> 'table' = 'conversation_participants'
      and payload ->> 'operation' = 'insert'
      and payload ->> 'conversation_id' = '99999999-2010-4999-8999-999999999999'
      and not (payload ? 'user_id')
  ),
  1,
  'a participant change is signalled by conversation without the participant identity'
);

select * from finish();
rollback;
