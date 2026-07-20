begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(18);

select has_function(
  'public',
  'invoke_push_notification_for_message',
  array[]::text[],
  'push delivery uses a first-party trigger function'
);
select is(
  (
    select routine.prosecdef
      from pg_proc routine
     where routine.oid = 'public.invoke_push_notification_for_message()'::regprocedure
  ),
  true,
  'push trigger function is security definer for Vault and pg_net access'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
      from pg_proc routine
     where routine.oid = 'public.invoke_push_notification_for_message()'::regprocedure
  ),
  'search_path=public, vault, net, pg_catalog',
  'security-definer function has an immutable trusted search path'
);
select has_trigger(
  'public',
  'messages',
  'trg_messages_push_notification',
  'messages queue push delivery through the secured trigger'
);
select is(
  (
    select trigger.tgenabled::text
      from pg_trigger trigger
     where trigger.tgrelid = 'public.messages'::regclass
       and trigger.tgname = 'trg_messages_push_notification'
       and not trigger.tgisinternal
  ),
  'O',
  'secured push trigger is enabled'
);
select is(
  (
    select count(*)::integer
      from pg_trigger trigger
     where trigger.tgrelid = 'public.messages'::regclass
       and trigger.tgname = 'push-on-message'
       and not trigger.tgisinternal
  ),
  0,
  'legacy Dashboard webhook trigger is removed'
);
select is(
  (
    select octet_length(trigger.tgargs)
      from pg_trigger trigger
     where trigger.tgrelid = 'public.messages'::regclass
       and trigger.tgname = 'trg_messages_push_notification'
       and not trigger.tgisinternal
  ),
  0,
  'secured trigger arguments contain no embedded credential'
);
select matches(
  pg_get_functiondef('public.invoke_push_notification_for_message()'::regprocedure),
  'push_notification_webhook_secret',
  'push trigger reads the dedicated Vault secret'
);
select matches(
  pg_get_functiondef('public.invoke_push_notification_for_message()'::regprocedure),
  'x-push-webhook-secret',
  'push trigger sends the dedicated authentication header'
);
select matches(
  pg_get_functiondef('public.invoke_push_notification_for_message()'::regprocedure),
  'net[.]http_post',
  'push trigger queues requests through pg_net'
);
select ok(
  position(
    'Bearer ' in
    pg_get_functiondef('public.invoke_push_notification_for_message()'::regprocedure)
  ) = 0,
  'push trigger function embeds no bearer credential'
);
select ok(
  position(
    'service_role' in
    pg_get_functiondef('public.invoke_push_notification_for_message()'::regprocedure)
  ) = 0,
  'push trigger function embeds no service-role credential'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.invoke_push_notification_for_message()',
    'EXECUTE'
  ),
  'anonymous clients cannot invoke the trigger function'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.invoke_push_notification_for_message()',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the trigger function'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.invoke_push_notification_for_message()',
    'EXECUTE'
  ),
  'service-role clients cannot invoke the trigger function directly'
);

-- Runtime gate: a missing Vault secret skips delivery without converting a
-- committed message into an application-visible save failure.
delete from vault.secrets
where name = 'push_notification_webhook_secret';

create temporary table push_notification_request_snapshot (
  queued_count bigint not null
) on commit drop;

insert into push_notification_request_snapshot (queued_count)
select count(*)::bigint from net.http_request_queue;

insert into public.tenants (id, shop_name)
values (
  '9e240000-0000-4000-8000-000000000010',
  'Push webhook security tenant'
);

insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values (
  '9e240000-0000-4000-8000-000000000011',
  '9e240000-0000-4000-8000-000000000010',
  'support',
  'website_portal',
  'Push webhook security conversation',
  'active',
  null
);

select lives_ok(
  $$
    insert into public.messages (
      id, conversation_id, tenant_id, content
    )
    values (
      '9e240000-0000-4000-8000-000000000001'::uuid,
      '9e240000-0000-4000-8000-000000000011'::uuid,
      '9e240000-0000-4000-8000-000000000010'::uuid,
      'Push webhook security pgTAP fixture'
    )
  $$,
  'a missing push secret never rejects the durable message insert'
);
select is(
  (
    select count(*)::integer
      from public.messages
     where id = '9e240000-0000-4000-8000-000000000001'::uuid
  ),
  1,
  'message remains committed inside the transaction when push is disabled'
);
select is(
  (select count(*)::bigint from net.http_request_queue),
  (select queued_count from push_notification_request_snapshot),
  'missing Vault secret queues no unauthenticated external request'
);

select * from finish();

rollback;
