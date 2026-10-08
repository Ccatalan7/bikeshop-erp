begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(12);

select has_function(
  'public',
  'invoke_push_notification_for_conversation_read',
  array[]::text[],
  'the read signal uses a first-party trigger function'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
      from pg_proc routine
     where routine.oid =
       'public.invoke_push_notification_for_conversation_read()'::regprocedure
  ),
  'search_path=public, vault, net, pg_catalog',
  'security-definer function has an immutable trusted search path'
);
select has_trigger(
  'public',
  'conversations',
  'trg_conversations_read_signal',
  'advancing the team read cursor queues the read signal'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.invoke_push_notification_for_conversation_read()',
    'EXECUTE'
  ),
  'clients cannot call the trigger function'
);
select ok(
  position(
    'Bearer ' in pg_get_functiondef(
      'public.invoke_push_notification_for_conversation_read()'::regprocedure
    )
  ) = 0,
  'the function embeds no bearer credential'
);

create temporary table read_signal_queue_snapshot (
  queued_count bigint not null
) on commit drop;

insert into public.tenants (id, shop_name)
values ('9e250000-0000-4000-8000-000000000010', 'Read signal tenant');

insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values
  (
    '9e250000-0000-4000-8000-000000000011',
    '9e250000-0000-4000-8000-000000000010',
    'support', 'whatsapp', 'Read signal supplier', 'active', null
  ),
  (
    '9e250000-0000-4000-8000-000000000012',
    '9e250000-0000-4000-8000-000000000010',
    'internal', 'internal', 'Read signal team chat', 'active', null
  );

-- Without the Vault secret nothing is queued and the read still commits.
delete from vault.secrets where name = 'push_notification_webhook_secret';
insert into read_signal_queue_snapshot
select count(*) from net.http_request_queue;

select lives_ok(
  $$
    update public.conversations
       set staff_last_read_message_sequence = 3
     where id = '9e250000-0000-4000-8000-000000000011'
  $$,
  'a read never fails because the signal is not configured'
);
select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count from read_signal_queue_snapshot),
  'missing Vault secret queues no unauthenticated request'
);

select vault.create_secret(
  'pgtap-read-signal-secret',
  'push_notification_webhook_secret'
);
-- The production endpoint must not receive a fixture: no worker drains the
-- queue inside this rolled-back transaction.
delete from read_signal_queue_snapshot;
insert into read_signal_queue_snapshot
select count(*) from net.http_request_queue;

update public.conversations
   set staff_last_read_message_sequence = 5
 where id = '9e250000-0000-4000-8000-000000000011';

select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count + 1 from read_signal_queue_snapshot),
  'advancing the support read cursor queues one signal'
);
select ok(
  exists (
    select 1
      from net.http_request_queue request
     where convert_from(request.body, 'utf8')::jsonb ->> 'type' = 'READ'
       and convert_from(request.body, 'utf8')::jsonb -> 'record' ->> 'id'
         = '9e250000-0000-4000-8000-000000000011'
       and convert_from(request.body, 'utf8')::jsonb::text
         not like '%pgtap-read-signal-secret%'
  ),
  'the signal names the conversation and carries no secret in its body'
);

update public.conversations
   set staff_last_read_message_sequence = 4
 where id = '9e250000-0000-4000-8000-000000000011';
select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count + 1 from read_signal_queue_snapshot),
  'a cursor that does not advance queues nothing'
);

update public.conversations
   set staff_last_read_message_sequence = 9
 where id = '9e250000-0000-4000-8000-000000000012';
select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count + 1 from read_signal_queue_snapshot),
  'internal chats keep per-person reads and send no team signal'
);

update public.conversations
   set title = 'Renamed'
 where id = '9e250000-0000-4000-8000-000000000011';
select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count + 1 from read_signal_queue_snapshot),
  'other column updates queue nothing'
);

select * from finish();

rollback;
