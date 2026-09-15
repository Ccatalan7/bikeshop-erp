begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- All data is synthetic, rolled back, and dispatch is disabled in this tx.
update public.whatsapp_outbox_runtime set enabled = false;
insert into public.tenants(id, shop_name) values
  ('9f032200-0000-4000-8000-000000000001', 'Outbox Test A'),
  ('9f032200-0000-4000-8000-000000000002', 'Outbox Test B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f032200-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'outbox-test@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f032200-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f032200-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f032200-0000-4000-8000-000000000091', '9f032200-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active)
values ('9f032200-0000-4000-8000-000000000131', '9f032200-0000-4000-8000-000000000001', 'outbox-test', 'Synthetic', true);
insert into public.conversations(id, tenant_id, type, channel, counterparty_type, title, status)
values
  ('9f032200-0000-4000-8000-000000000141', '9f032200-0000-4000-8000-000000000001', 'support', 'whatsapp', 'customer', 'Synthetic', 'active'),
  ('9f032200-0000-4000-8000-000000000142', '9f032200-0000-4000-8000-000000000002', 'support', 'whatsapp', 'customer', 'Foreign', 'active');
create temporary table outbox_test_receipts(kind text, receipt jsonb);
grant all on outbox_test_receipts to authenticated, service_role;
create function pg_temp.outbox_request(p_key text default 'one') returns jsonb
language sql immutable as $$
  select jsonb_build_object('conversationId', '9f032200-0000-4000-8000-000000000141',
    'phoneNumber', '+56911112222', 'phoneNumberId', 'outbox-test', 'type', 'text',
    'text', 'Synthetic message', 'metadata', jsonb_build_object('client_message_id', p_key,
      'external_status', 'read', 'whatsapp_status', 'read'));
$$;

select ok(not has_function_privilege('anon', 'public.enqueue_whatsapp_message_v1(jsonb)', 'execute'), 'anonymous cannot enqueue');
select ok(not has_table_privilege('authenticated', 'public.whatsapp_outbox', 'select'), 'client cannot read private requests/capabilities');
select ok(not has_function_privilege('authenticated', 'public.claim_whatsapp_outbox_v1(uuid,text)', 'execute'), 'client cannot claim jobs');
select ok(not has_function_privilege('authenticated', 'public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)', 'execute'), 'client cannot forge completion');

select set_config('request.jwt.claims', '{"sub":"9f032200-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032200-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok($$insert into outbox_test_receipts values ('first', public.enqueue_whatsapp_message_v1(pg_temp.outbox_request()))$$, 'acceptance does not need a provider response');
select is((select receipt->>'external_status' from outbox_test_receipts where kind = 'first'), 'queued', 'first receipt honestly means queued');
select is((select receipt->>'external_message_id' from outbox_test_receipts where kind = 'first'), null, 'no invented Meta id');
select lives_ok($$insert into outbox_test_receipts values ('repeat', public.enqueue_whatsapp_message_v1(pg_temp.outbox_request()))$$, 'same request is idempotent');
select is((select receipt->>'message_id' from outbox_test_receipts where kind = 'repeat'),
  (select receipt->>'message_id' from outbox_test_receipts where kind = 'first'), 'same durable row on retry');
select throws_ok($$update public.messages set external_status = 'read'
  where id = (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first')$$,
  '42501', 'permission denied for table messages', 'sender cannot forge queued provider receipt');
select throws_ok($$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request() || '{"text":"Changed"}')$$,
  '22023', 'Idempotency key reused for a different message', 'different intent cannot reuse key');
select throws_ok($$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('foreign') || '{"conversationId":"9f032200-0000-4000-8000-000000000142"}')$$,
  '42501', 'Writable WhatsApp conversation required', 'cross-tenant denied');
select throws_ok($$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('phone') || '{"phoneNumber":"+56999998888"}')$$,
  '42501', 'WhatsApp recipient does not match conversation', 'cannot redirect a conversation');
reset role;
select is((select count(*) from public.whatsapp_outbox where tenant_id = '9f032200-0000-4000-8000-000000000001'), 1::bigint, 'one durable delivery intent');
select is((select metadata->>'whatsapp_status' from public.messages where id = (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first')), null, 'caller cannot forge read receipt');

update public.whatsapp_outbox set state = 'dispatched', attempts = 1,
  token_hash = encode(extensions.digest(repeat('a', 64), 'sha256'), 'hex'), lease_until = now() + interval '2 minutes'
where message_id = (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(public.claim_whatsapp_outbox_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('b', 64)), null, 'wrong capability cannot claim');
select ok(public.claim_whatsapp_outbox_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64)) is not null, 'correct capability claims');
select is(public.claim_whatsapp_outbox_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64)), null, 'capability cannot claim twice');
select throws_ok($$select public.finish_whatsapp_outbox_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64), 'accepted', '{"external_message_id":"wamid.synthetic"}')$$,
  '22023', 'Provider acceptance requires a fenced send and provider id', 'must fence before sending');
select ok(public.start_whatsapp_outbox_send_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64)), 'fences provider send');
select ok(not public.start_whatsapp_outbox_send_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64)), 'second message POST denied');
reset role;
update public.whatsapp_outbox set lease_until = now() - interval '1 second' where tenant_id = '9f032200-0000-4000-8000-000000000001';
select public.recover_whatsapp_outbox_v1();
select is((select state from public.whatsapp_outbox where tenant_id = '9f032200-0000-4000-8000-000000000001'), 'outcome_unknown', 'expired sending is not retried');
select is((select metadata->>'whatsapp_status' from public.messages where id = (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first')), 'outcome_unknown', 'unknown visible in durable row');
select ok(public.finish_whatsapp_outbox_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'first'), repeat('a', 64), 'accepted', '{"external_message_id":"wamid.synthetic"}'), 'late known acceptance reconciles without resend');
select is((select count(*) from public.messages where conversation_id = '9f032200-0000-4000-8000-000000000141'), 1::bigint, 'completion updates rather than inserts');

select set_config('request.jwt.claims', '{"sub":"9f032200-0000-4000-8000-000000000091","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$insert into outbox_test_receipts values ('late', public.enqueue_whatsapp_message_v1(pg_temp.outbox_request()))$$, 'late client retry only reads evidence');
select is((select receipt->>'external_status' from outbox_test_receipts where kind = 'late'), 'accepted', 'late retry does not downgrade to queued');
select lives_ok($$insert into outbox_test_receipts values ('retry', public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('retry') || '{"contactName":"Renamed"}'))$$, 'another legitimate intent is independent');
reset role;
select is((select contact_name from public.whatsapp_conversation_bindings where conversation_id = '9f032200-0000-4000-8000-000000000141'), null,
  'a matching binding proves identity; its upkeep (contact name, contexts) is not on the acceptance path');
update public.whatsapp_outbox set state = 'processing', attempts = 1,
  token_hash = encode(extensions.digest(repeat('c', 64), 'sha256'), 'hex'), lease_until = now() - interval '1 second'
where client_message_id = 'retry' and tenant_id = '9f032200-0000-4000-8000-000000000001';
select public.recover_whatsapp_outbox_v1();
select is((select state from public.whatsapp_outbox where client_message_id = 'retry' and tenant_id = '9f032200-0000-4000-8000-000000000001'), 'queued', 'pre-send crash is safe to retry');
select ok(not public.start_whatsapp_outbox_send_v1((select (receipt->>'message_id')::uuid from outbox_test_receipts where kind = 'retry'), repeat('c', 64)), 'expired worker cannot send after recovery');
update public.conversations set status = 'resolved' where id = '9f032200-0000-4000-8000-000000000141';
set local role authenticated;
select throws_ok($$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('closed'))$$,
  '42501', 'Writable WhatsApp conversation required', 'closed conversation cannot accept another send');
reset role;
select * from finish();
rollback;
