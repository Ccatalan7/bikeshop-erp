begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('9f212330-0000-4000-8000-000000000001', 'Meta Messaging Tenant A'),
  ('9f212330-0000-4000-8000-000000000002', 'Meta Messaging Tenant B');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9f212330-0000-4000-8000-000000000091',
    'authenticated', 'authenticated', 'meta-staff-a@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f212330-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9f212330-0000-4000-8000-000000000092',
    'authenticated', 'authenticated', 'meta-staff-b@example.invalid', '', now(),
    '{}'::jsonb,
    jsonb_build_object('tenant_id', '9f212330-0000-4000-8000-000000000002'),
    now(), now()
  );

delete from public.user_profiles
where user_id in (
  '9f212330-0000-4000-8000-000000000091',
  '9f212330-0000-4000-8000-000000000092'
);

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values
  (
    '9f212330-0000-4000-8000-000000000091',
    '9f212330-0000-4000-8000-000000000001',
    'admin', '{}'::jsonb, true
  ),
  (
    '9f212330-0000-4000-8000-000000000092',
    '9f212330-0000-4000-8000-000000000002',
    'admin', '{}'::jsonb, true
  );

insert into public.meta_channels (
  id, tenant_id, provider, external_account_id, display_name, is_active
) values
  (
    '9f212330-0001-4000-8000-000000000001',
    '9f212330-0000-4000-8000-000000000001',
    'instagram', 'ig-test-account-a', 'Instagram Test A', true
  ),
  (
    '9f212330-0001-4000-8000-000000000002',
    '9f212330-0000-4000-8000-000000000002',
    'facebook_messenger', 'fb-test-account-b', 'Facebook Test B', true
  );

select has_table('public', 'meta_channels', 'Meta channels are durable');
select has_table(
  'public', 'meta_channel_credentials',
  'Meta Vault credential references are durable'
);
select has_table(
  'public', 'meta_conversation_bindings',
  'Meta contact bindings are durable'
);
select has_table(
  'public', 'meta_webhook_events',
  'Meta webhook evidence is durable'
);
select has_table(
  'public', 'meta_outbound_send_attempts',
  'Meta outbound attempts are durable'
);
select has_table(
  'public', 'meta_oauth_states',
  'Meta OAuth state is durable and one-time'
);
select has_index(
  'public',
  'meta_outbound_send_attempts',
  'idx_meta_attempts_conversation_created',
  'safe receipt hydration has a tenant/conversation/time index'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.meta_channels'::regclass),
  'Meta channels have RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.meta_webhook_events'::regclass),
  'Meta webhook events have RLS enabled'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.meta_channel_credentials', 'SELECT'
  ),
  'authenticated users cannot read Vault credential references'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.meta_outbound_send_attempts', 'SELECT'
  ),
  'authenticated users cannot enumerate raw send attempts'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.meta_conversation_bindings', 'SELECT'
  ),
  'authenticated users cannot enumerate raw Meta contact bindings'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.meta_webhook_events', 'SELECT'
  ),
  'authenticated users cannot enumerate raw Meta webhook evidence'
);
select ok(
  not exists (
    select 1
    from pg_policies policy
    where policy.schemaname = 'public'
      and policy.tablename in (
        'meta_conversation_bindings',
        'meta_webhook_events'
      )
      and 'authenticated' = any(policy.roles)
  ),
  'raw Meta binding and webhook tables expose no authenticated policy'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_meta_channel_access_token(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot obtain Meta access tokens'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.mark_meta_channel_subscribed(uuid)',
    'EXECUTE'
  ),
  'authenticated users cannot forge Meta subscription success'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.list_meta_outbound_send_receipts(uuid)',
    'EXECUTE'
  ),
  'authenticated staff can request safe durable send receipts'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.get_meta_conversation_transport(uuid)',
    'EXECUTE'
  ),
  'authenticated staff can request safe Meta reply-window state'
);
select ok(
  to_regprocedure(
    'public.create_meta_oauth_state(uuid,text,text,timestamp with time zone)'
  ) is null,
  'the ambiguous tenant-inferred OAuth start overload does not exist'
);
select throws_ok(
  $$select public.create_meta_oauth_state(
    '9f212330-0000-4000-8000-000000000091',
    '9f212330-0000-4000-8000-000000000002',
    repeat('a', 64),
    'https://erp.example.invalid/meta-oauth',
    now() + interval '10 minutes'
  )$$,
  '42501',
  'Meta OAuth requires an active admin or manager',
  'OAuth start cannot choose a tenant without exact actor membership'
);
select is(
  public.create_meta_oauth_state(
    '9f212330-0000-4000-8000-000000000091',
    '9f212330-0000-4000-8000-000000000001',
    repeat('b', 64),
    'https://erp.example.invalid/meta-oauth',
    now() + interval '10 minutes'
  )->>'tenant_id',
  '9f212330-0000-4000-8000-000000000001',
  'OAuth state is bound to the explicitly authorized tenant'
);

update public.meta_channels
set subscribed_at = now()
where id = '9f212330-0001-4000-8000-000000000001';
select is(
  public.store_meta_channel_credential(
    '9f212330-0000-4000-8000-000000000001',
    'instagram',
    'ig-test-account-a',
    'Instagram Test A',
    'vinabike_test',
    'test-page-token-rotation',
    array['instagram_basic', 'instagram_manage_messages'],
    null
  )->>'credential_stored',
  'true',
  'credential rotation succeeds through the Vault-backed command'
);
select ok(
  (
    select channel.subscribed_at is null
    from public.meta_channels channel
    where channel.id = '9f212330-0001-4000-8000-000000000001'
  ),
  'credential rotation clears stale provider subscription evidence'
);
select ok(
  (public.mark_meta_channel_subscribed(
    '9f212330-0001-4000-8000-000000000001'
  )->>'subscribed_at') is not null,
  'only an explicit successful provider subscription restores evidence'
);

select is(
  public.ingest_meta_message(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:message:ig-test-account-a:mid-in-1',
    'mid-in-1',
    'ig-user-1',
    'Cliente Meta',
    'cliente_meta',
    'text',
    'Hola desde Instagram',
    now() - interval '1 minute',
    '{"message_id":"mid-in-1","message_type":"text"}'::jsonb
  )->>'duplicate',
  'false',
  'signed service ingestion creates the first inbound Meta message'
);

select is(
  public.ingest_meta_message(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:message:ig-test-account-a:mid-in-1',
    'mid-in-1',
    'ig-user-1',
    'Cliente Meta',
    'cliente_meta',
    'text',
    'Hola desde Instagram',
    now() - interval '1 minute',
    '{"message_id":"mid-in-1","message_type":"text"}'::jsonb
  )->>'duplicate',
  'true',
  'inbound webhook replay is idempotent'
);

select is(
  (
    select message.type
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-in-1'
  ),
  'text',
  'inbound Meta text uses the canonical chat text type'
);
select is(
  (
    select (message.metadata ?| array[
      'external_account_id',
      'external_user_id',
      'external_message_id_raw',
      'contact_name',
      'username'
    ])::text
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-in-1'
  ),
  'false',
  'readable inbound message metadata contains no raw Meta identifiers'
);
select is(
  (
    select message.metadata->>'contact_label'
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-in-1'
  ),
  'Instagram • ' || upper(substr(md5('ig-user-1'), 1, 6)),
  'readable inbound message metadata uses a pseudonymous contact label'
);

select is(
  public.ingest_meta_message(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:message:ig-test-account-a:mid-media-1',
    'mid-media-1',
    'ig-user-1',
    null,
    null,
    'image',
    'Imagen recibida',
    now(),
    '{"message_id":"mid-media-1","message_type":"image"}'::jsonb
  )->>'duplicate',
  'false',
  'inbound Meta media placeholder is accepted'
);

select is(
  (
    select message.type || ':' || (message.metadata->>'message_type')
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-media-1'
  ),
  'text:image',
  'remote media remains a text placeholder with provider metadata'
);

select public.ingest_meta_message(
  'instagram', 'ig-test-account-a',
  'meta:instagram:message:ig-test-account-a:mid-anon-a',
  'mid-anon-a', 'ig-anon-a', null, null, 'text', 'Anon A', now(),
  '{"message_id":"mid-anon-a"}'::jsonb
);
select public.ingest_meta_message(
  'instagram', 'ig-test-account-a',
  'meta:instagram:message:ig-test-account-a:mid-anon-b',
  'mid-anon-b', 'ig-anon-b', null, null, 'text', 'Anon B', now(),
  '{"message_id":"mid-anon-b"}'::jsonb
);
select is(
  (
    select count(distinct conversation.title)::integer
    from public.meta_conversation_bindings binding
    join public.conversations conversation on conversation.id = binding.conversation_id
    where binding.channel_id = '9f212330-0001-4000-8000-000000000001'
      and binding.external_user_id in ('ig-anon-a', 'ig-anon-b')
  ),
  2,
  'anonymous Meta contacts receive stable distinguishable pseudonymous titles'
);
select is(
  (
    select count(*)::integer
    from public.meta_conversation_bindings binding
    join public.conversations conversation on conversation.id = binding.conversation_id
    where binding.channel_id = '9f212330-0001-4000-8000-000000000001'
      and binding.external_user_id in ('ig-anon-a', 'ig-anon-b')
      and conversation.title ~ 'ig-anon-[ab]'
  ),
  0,
  'pseudonymous Meta titles never expose raw external user ids'
);

-- The application must never create a local-only phantom row in an active
-- Meta conversation, even if its in-memory channel guard missed hydration.
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000091',
  true
);
select throws_ok(
  format(
    'insert into public.messages (conversation_id,sender_id,tenant_id,content,type,metadata) values (%L,%L,%L,%L,%L,%L::jsonb)',
    (select conversation_id from public.meta_conversation_bindings
      where channel_id = '9f212330-0001-4000-8000-000000000001'
        and external_user_id = 'ig-user-1'),
    '9f212330-0000-4000-8000-000000000091',
    '9f212330-0000-4000-8000-000000000001',
    'phantom local message',
    'text',
    '{}'
  ),
  '42501',
  'Meta conversations require trusted provider transport',
  'active Meta conversations reject authenticated local message inserts'
);
select throws_ok(
  $$insert into public.conversations (
    tenant_id, type, channel, counterparty_type, title, status
  ) values (
    '9f212330-0000-4000-8000-000000000001',
    'support', 'instagram', 'customer', 'Phantom Meta', 'pending'
  )$$,
  '42501',
  'Meta conversations require trusted provider transport',
  'authenticated clients cannot create unbound Meta conversations'
);
insert into public.conversations (
  id, tenant_id, type, channel, counterparty_type, title, status
) values (
  '9f212330-0002-4000-8000-000000000001',
  '9f212330-0000-4000-8000-000000000001',
  'support', 'website_portal', 'customer', 'Website Test', 'pending'
);
select throws_ok(
  $$update public.conversations
    set channel = 'facebook_messenger'
    where id = '9f212330-0002-4000-8000-000000000001'$$,
  '23514',
  'Meta conversation channel is immutable',
  'authenticated clients cannot convert an unbound conversation to Meta'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

create temporary table meta_test_values (
  key text primary key,
  value text not null
);
grant select on meta_test_values to authenticated;
insert into meta_test_values (key, value)
select 'conversation_1', binding.conversation_id::text
from public.meta_conversation_bindings binding
where binding.channel_id = '9f212330-0001-4000-8000-000000000001'
  and binding.external_user_id = 'ig-user-1';

insert into meta_test_values (key, value)
select 'inbound_message_1', message.id::text
from public.messages message
where message.external_message_id =
  '9f212330-0001-4000-8000-000000000001:mid-in-1';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000091',
  true
);
select lives_ok(
  format(
    'select public.mark_conversation_read(%L::uuid,%L::uuid)',
    (select value from meta_test_values where key = 'conversation_1'),
    (select value from meta_test_values where key = 'inbound_message_1')
  ),
  'opening a Meta thread creates its first staff read marker without trigger field errors'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

select is(
  (
    select participant.last_read_message_sequence
    from public.conversation_participants participant
    where participant.conversation_id =
      (select value::uuid from meta_test_values where key = 'conversation_1')
      and participant.user_id =
        '9f212330-0000-4000-8000-000000000091'
  ),
  (
    select message.message_sequence
    from public.messages message
    where message.id =
      (select value::uuid from meta_test_values where key = 'inbound_message_1')
  ),
  'the exact inbound Meta message becomes the participant read cursor'
);
select is(
  (
    select conversation.staff_last_read_message_sequence
    from public.conversations conversation
    where conversation.id =
      (select value::uuid from meta_test_values where key = 'conversation_1')
  ),
  (
    select message.message_sequence
    from public.messages message
    where message.id =
      (select value::uuid from meta_test_values where key = 'inbound_message_1')
  ),
  'the shared staff cursor advances when a Meta thread is visibly read'
);

insert into meta_test_values (key, value)
select 'attempt_1', result->>'attempt_id'
from (
  select public.begin_meta_outbound_send(
    '9f212330-0000-4000-8000-000000000091',
    (select value::uuid from meta_test_values where key = 'conversation_1'),
    'meta-client-1',
    encode(extensions.digest(convert_to(
      (select value from meta_test_values where key = 'conversation_1')
        || E'\nRespuesta Meta 1',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Respuesta Meta 1'
  ) result
) prepared;

select is(
  public.accept_meta_outbound_attempt(
    (select value::uuid from meta_test_values where key = 'attempt_1'),
    'mid-out-1',
    '{"message_id":"mid-out-1"}'::jsonb
  )->>'state',
  'provider_accepted',
  'provider acceptance is durable before message finalization'
);

select is(
  public.finalize_meta_outbound_send(
    (select value::uuid from meta_test_values where key = 'attempt_1'),
    'mid-out-1',
    '{"message_id":"mid-out-1"}'::jsonb
  )->>'state',
  'finalized',
  'provider acceptance finalizes an outbound message atomically'
);

select is(
  (
    select message.metadata->>'client_message_id'
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-out-1'
  ),
  'meta-client-1',
  'durable outbound message retains the exact client idempotency id'
);
select is(
  (
    select (message.metadata ?| array[
      'external_account_id',
      'external_user_id',
      'external_message_id_raw'
    ])::text
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-out-1'
  ),
  'false',
  'readable outbound message metadata contains no raw Meta identifiers'
);

select is(
  public.record_meta_message_status(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:read:mid-out-1',
    'ig-user-1',
    'mid-out-1',
    'read',
    null,
    now(),
    '{"message_id":"mid-out-1","status":"read"}'::jsonb
  )->>'status',
  'read',
  'exact read evidence upgrades the outbound message'
);

select is(
  (
    select message.external_status
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-out-1'
  ),
  'read',
  'outbound delivery projection retains read status'
);

-- Persist an ambiguous provider outcome and prove it remains queryable after
-- optimistic Flutter state is gone.
insert into meta_test_values (key, value)
select 'attempt_unknown', result->>'attempt_id'
from (
  select public.begin_meta_outbound_send(
    '9f212330-0000-4000-8000-000000000091',
    (select value::uuid from meta_test_values where key = 'conversation_1'),
    'meta-client-unknown',
    encode(extensions.digest(convert_to(
      (select value from meta_test_values where key = 'conversation_1')
        || E'\nResultado incierto',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Resultado incierto'
  ) result
) prepared;
select public.mark_meta_outbound_attempt(
  (select value::uuid from meta_test_values where key = 'attempt_unknown'),
  'outcome_unknown',
  'provider_timeout',
  'No response',
  '{}'::jsonb
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000091',
  true
);
select is(
  (
    select receipt.state
    from public.list_meta_outbound_send_receipts(
      (select value::uuid from meta_test_values where key = 'conversation_1')
    ) receipt
    where receipt.client_message_id = 'meta-client-unknown'
  ),
  'outcome_unknown',
  'uncertain send outcome remains visible through a safe durable receipt'
);
select is(
  (
    select transport.provider
    from public.get_meta_conversation_transport(
      (select value::uuid from meta_test_values where key = 'conversation_1')
    ) transport
  ),
  'instagram',
  'safe transport state exposes the provider without external identifiers'
);
select ok(
  (
    select transport.can_reply
      and transport.reply_window_expires_at > now()
    from public.get_meta_conversation_transport(
      (select value::uuid from meta_test_values where key = 'conversation_1')
    ) transport
  ),
  'safe transport state exposes the active reply window'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- A status webhook can beat persistence of the provider-accepted message.
insert into meta_test_values (key, value)
select 'attempt_early', result->>'attempt_id'
from (
  select public.begin_meta_outbound_send(
    '9f212330-0000-4000-8000-000000000091',
    (select value::uuid from meta_test_values where key = 'conversation_1'),
    'meta-client-early',
    encode(extensions.digest(convert_to(
      (select value from meta_test_values where key = 'conversation_1')
        || E'\nEstado temprano',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Estado temprano'
  ) result
) prepared;

select public.record_meta_message_status(
  'instagram',
  'ig-test-account-a',
  'meta:instagram:read:mid-out-early',
  'ig-user-1',
  'mid-out-early',
  'read',
  null,
  now(),
  '{"message_id":"mid-out-early","status":"read"}'::jsonb
);
select public.accept_meta_outbound_attempt(
  (select value::uuid from meta_test_values where key = 'attempt_early'),
  'mid-out-early',
  '{"message_id":"mid-out-early"}'::jsonb
);
select public.finalize_meta_outbound_send(
  (select value::uuid from meta_test_values where key = 'attempt_early'),
  'mid-out-early',
  '{"message_id":"mid-out-early"}'::jsonb
);

select is(
  (
    select message.external_status
    from public.messages message
    where message.external_message_id =
      '9f212330-0001-4000-8000-000000000001:mid-out-early'
  ),
  'read',
  'finalization replays an earlier exact read webhook'
);
select is(
  (
    select count(*)::integer
    from public.meta_webhook_events event
    where event.external_message_id = 'mid-out-early'
      and event.message_id is not null
      and event.conversation_id is not null
  ),
  1,
  'finalization back-links early status evidence to its message and conversation'
);

select is(
  public.ingest_meta_interaction(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:comment:comment-1',
    'comment',
    'ig-user-2',
    'comment-1',
    'media-1',
    'Seguidor',
    '¿Está disponible?',
    'https://www.instagram.com/p/example/',
    now(),
    '{"object_id":"comment-1"}'::jsonb
  )->>'notification_type',
  'meta_instagram_comment',
  'Instagram comments create the stable notification type'
);
select is(
  (
    select count(*)::integer
    from public.erp_notifications notification
    where notification.tenant_id = '9f212330-0000-4000-8000-000000000001'
      and notification.type = 'meta_instagram_comment'
      and notification.entity_type = 'meta_event'
  ),
  1,
  'one durable ERP notification is created for the interaction event'
);
select is(
  (
    select notification.route
    from public.erp_notifications notification
    where notification.tenant_id = '9f212330-0000-4000-8000-000000000001'
      and notification.type = 'meta_instagram_comment'
      and notification.entity_id = (
        select event.id
        from public.meta_webhook_events event
        where event.external_object_id = 'comment-1'
      )
  ),
  'https://www.instagram.com/p/example/',
  'trusted provider permalink becomes the explicit notification route'
);

select public.ingest_meta_interaction(
  'instagram',
  'ig-test-account-a',
  'meta:instagram:comment:comment-evil',
  'comment',
  'ig-user-evil',
  'comment-evil',
  'media-evil',
  'Atacante',
  'Link externo',
  'https://evil.example/instagram/phish',
  now(),
  '{"object_id":"comment-evil","permalink":"https://evil.example/instagram/phish"}'::jsonb
);
select is(
  (
    select notification.route
    from public.erp_notifications notification
    where notification.tenant_id = '9f212330-0000-4000-8000-000000000001'
      and notification.entity_id = (
        select event.id
        from public.meta_webhook_events event
        where event.external_object_id = 'comment-evil'
      )
  ),
  '/chat',
  'untrusted interaction host falls back to the internal chat route'
);
select is(
  (
    select coalesce(event.payload ? 'permalink', false)::text
    from public.meta_webhook_events event
    where event.external_object_id = 'comment-evil'
  ),
  'false',
  'untrusted permalink is removed from durable webhook evidence'
);

select is(
  public.ingest_meta_interaction(
    'facebook_messenger',
    'fb-test-account-b',
    'meta:facebook:comment:comment-removed',
    'comment',
    'fb-user-removed',
    'comment-removed',
    'post-removed',
    'Seguidor',
    'Comentario eliminado',
    'https://www.facebook.com/example/posts/1',
    now(),
    '{"object_id":"comment-removed","verb":"remove"}'::jsonb
  )->>'reason',
  'interaction_not_new',
  'a signed Page remove event is not treated as new customer activity'
);
select is(
  (
    select count(*)::integer
    from public.erp_notifications notification
    where notification.entity_id = (
      select event.id
      from public.meta_webhook_events event
      where event.external_object_id = 'comment-removed'
    )
  ),
  0,
  'a Page remove event creates no misleading new-comment notification'
);

-- Begin while open, archive as staff, then persist the known provider result.
-- The attempt is exact authorization for this accepted-after-archive race.
insert into meta_test_values (key, value)
select 'attempt_archive', result->>'attempt_id'
from (
  select public.begin_meta_outbound_send(
    '9f212330-0000-4000-8000-000000000091',
    (select value::uuid from meta_test_values where key = 'conversation_1'),
    'meta-client-archive',
    encode(extensions.digest(convert_to(
      (select value from meta_test_values where key = 'conversation_1')
        || E'\nAceptado antes de archivar',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Aceptado antes de archivar'
  ) result
) prepared;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000091',
  true
);
select public.archive_conversation(
  (select value::uuid from meta_test_values where key = 'conversation_1')
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

select public.accept_meta_outbound_attempt(
  (select value::uuid from meta_test_values where key = 'attempt_archive'),
  'mid-out-archive',
  '{"message_id":"mid-out-archive"}'::jsonb
);
select is(
  public.finalize_meta_outbound_send(
    (select value::uuid from meta_test_values where key = 'attempt_archive'),
    'mid-out-archive',
    '{"message_id":"mid-out-archive"}'::jsonb
  )->>'state',
  'finalized',
  'known provider acceptance survives a concurrent conversation archive'
);

select isnt(
  public.ingest_meta_message(
    'instagram',
    'ig-test-account-a',
    'meta:instagram:message:ig-test-account-a:mid-after-archive',
    'mid-after-archive',
    'ig-user-1',
    'Cliente Meta',
    'cliente_meta',
    'text',
    'Nuevo caso después del archivo',
    now(),
    '{"message_id":"mid-after-archive","message_type":"text"}'::jsonb
  )->>'conversation_id',
  (select value from meta_test_values where key = 'conversation_1'),
  'new inbound after archive rebinds the contact to a fresh conversation'
);

insert into meta_test_values (key, value)
select 'conversation_current', binding.conversation_id::text
from public.meta_conversation_bindings binding
where binding.channel_id = '9f212330-0001-4000-8000-000000000001'
  and binding.external_user_id = 'ig-user-1';

update public.meta_conversation_bindings
set reply_window_expires_at = now() + interval '30 days'
where channel_id = '9f212330-0001-4000-8000-000000000001'
  and external_user_id = 'ig-user-1';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000091"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000091',
  true
);
select is(
  (
    select transport.can_reply::text
    from public.get_meta_conversation_transport(
      (select value::uuid
       from meta_test_values
       where key = 'conversation_current')
    ) transport
  ),
  'false',
  'safe transport state fails closed for a poisoned future reply window'
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  format(
    'select public.begin_meta_outbound_send(%L,%L,%L,%L,%L)',
    '9f212330-0000-4000-8000-000000000091',
    (select value from meta_test_values where key = 'conversation_current'),
    'meta-client-window-poisoned',
    encode(extensions.digest(convert_to(
      (select value from meta_test_values where key = 'conversation_current')
        || E'\nPoisoned window',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Poisoned window'
  ),
  'P0001',
  'Meta 24-hour reply window is closed',
  'server send preflight rejects an implausibly far-future reply window'
);

update public.meta_conversation_bindings
set reply_window_expires_at = now() - interval '1 second'
where channel_id = '9f212330-0001-4000-8000-000000000001'
  and external_user_id = 'ig-user-1';

select throws_ok(
  format(
    'select public.begin_meta_outbound_send(%L,%L,%L,%L,%L)',
    '9f212330-0000-4000-8000-000000000091',
    (select conversation_id::text from public.meta_conversation_bindings
      where channel_id = '9f212330-0001-4000-8000-000000000001'
        and external_user_id = 'ig-user-1'),
    'meta-client-window-closed',
    encode(extensions.digest(convert_to(
      (select conversation_id::text from public.meta_conversation_bindings
        where channel_id = '9f212330-0001-4000-8000-000000000001'
          and external_user_id = 'ig-user-1')
        || E'\nFuera de ventana',
      'UTF8'
    ), 'sha256'), 'hex'),
    'Fuera de ventana'
  ),
  'P0001',
  'Meta 24-hour reply window is closed',
  'outbound Meta text is rejected after the standard reply window closes'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"9f212330-0000-4000-8000-000000000092"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f212330-0000-4000-8000-000000000092',
  true
);
select throws_ok(
  format(
    'select * from public.list_meta_outbound_send_receipts(%L)',
    (select value from meta_test_values where key = 'conversation_1')
  ),
  '42501',
  'Meta send receipts are not available to this user',
  'another tenant cannot read Meta send receipts'
);
select throws_ok(
  format(
    'select * from public.get_meta_conversation_transport(%L)',
    (select value from meta_test_values where key = 'conversation_1')
  ),
  '42501',
  'Meta conversation transport is not available to this user',
  'another tenant cannot read Meta reply-window state'
);
reset role;

select * from finish();

rollback;
