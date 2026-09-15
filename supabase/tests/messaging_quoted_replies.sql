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

insert into public.messages(id, tenant_id, conversation_id, content, type, external_provider,
  external_message_id, message_direction, metadata) values
 ('9f032200-0000-4000-8000-000000000151','9f032200-0000-4000-8000-000000000001',
  '9f032200-0000-4000-8000-000000000141','Original verified text','text','whatsapp','wamid.reply-source','inbound','{"contact_name":"Test"}'),
 ('9f032200-0000-4000-8000-000000000152','9f032200-0000-4000-8000-000000000002',
  '9f032200-0000-4000-8000-000000000142','Foreign text','text','whatsapp','wamid.foreign-source','inbound','{}');
select set_config('request.jwt.claims', '{"sub":"9f032200-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032200-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok($q$insert into outbox_test_receipts values ('reply', public.enqueue_whatsapp_message_v1(
 pg_temp.outbox_request('reply') || '{"replyToMessageId":"wamid.reply-source"}'))$q$, 'quoted reply accepted');
select throws_ok($q$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('foreign') ||
 '{"replyToMessageId":"wamid.foreign-source"}')$q$, '22023', 'Reply target must belong to this conversation', 'cross-tenant quote denied');
select throws_ok($q$select public.enqueue_whatsapp_message_v1(pg_temp.outbox_request('missing') ||
 '{"replyToMessageId":"wamid.missing"}')$q$, '22023', 'Reply target must belong to this conversation', 'unknown outbound quote denied');
reset role;
select is((select metadata #>> '{reply_to,content}' from public.messages where id =
 (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind='reply')),
 'Original verified text', 'first durable queued row already contains canonical quote');
select is((select metadata #>> '{reply_to,sender_name}' from public.messages where id =
 (select (receipt->>'message_id')::uuid from outbox_test_receipts where kind='reply')), 'Test', 'canonical author survives queue');
insert into public.messages(id,tenant_id,conversation_id,content,type,message_direction,metadata) values
 ('9f032200-0000-4000-8000-000000000153','9f032200-0000-4000-8000-000000000001',
 '9f032200-0000-4000-8000-000000000141','Inbound reply','text','inbound',
 '{"raw_payload":{"message":{"context":{"id":"wamid.reply-source"}}}}'),
 ('9f032200-0000-4000-8000-000000000154','9f032200-0000-4000-8000-000000000001',
 '9f032200-0000-4000-8000-000000000141','Old source unavailable','text','inbound',
 '{"raw_payload":{"message":{"context":{"id":"wamid.older-than-history"}}}}'),
 ('9f032200-0000-4000-8000-000000000155','9f032200-0000-4000-8000-000000000001',
 '9f032200-0000-4000-8000-000000000141','Forged snapshot','text','outbound',
 '{"reply_to":{"message_id":"9f032200-0000-4000-8000-000000000151","content":"Forged","sender_name":"Impersonation"}}');
select is((select metadata #>> '{reply_to,content}' from public.messages where id='9f032200-0000-4000-8000-000000000153'),
 'Original verified text', 'inbound context projected');
select is((select metadata #>> '{reply_to,unavailable}' from public.messages where id='9f032200-0000-4000-8000-000000000154'),
 'true', 'missing historical inbound does not lose the incoming message');
select is((select metadata #>> '{reply_to,sender_name}' from public.messages where id='9f032200-0000-4000-8000-000000000155'),
 'Test', 'caller cannot forge the quoted author');
select is((select metadata #>> '{reply_to,content}' from public.messages where id='9f032200-0000-4000-8000-000000000155'),
 'Original verified text', 'caller cannot forge quoted content');

-- Same-tenant, different-conversation references are forbidden as well.
insert into public.conversations(id,tenant_id,type,channel,title,status,created_by)
values ('9f032200-0000-4000-8000-000000000143','9f032200-0000-4000-8000-000000000001',
 'support','website_portal','Native reply test','active','9f032200-0000-4000-8000-000000000091');
insert into public.messages(id,tenant_id,conversation_id,sender_id,content,type,metadata)
values ('9f032200-0000-4000-8000-000000000161','9f032200-0000-4000-8000-000000000001',
 '9f032200-0000-4000-8000-000000000143','9f032200-0000-4000-8000-000000000091','Native original','text','{}');
select throws_ok($q$insert into public.messages(tenant_id,conversation_id,content,type,metadata)
 values ('9f032200-0000-4000-8000-000000000001','9f032200-0000-4000-8000-000000000141',
 'Cross chat','text','{"reply_to":{"message_id":"9f032200-0000-4000-8000-000000000161"}}')$q$,
 '22023','Reply target must belong to this conversation','same-tenant cross-chat quote denied');
create temporary table quoted_attachment as select public.reserve_messaging_attachment(
 '9f032200-0000-4000-8000-000000000143','reply.pdf','application/pdf',128) as reservation;
insert into storage.objects(bucket_id,name,metadata)
select 'chat-attachments',reservation->>'storage_path','{"size":128,"mimetype":"application/pdf"}'::jsonb from quoted_attachment;
alter table quoted_attachment add column publication jsonb;
update quoted_attachment set publication=public.publish_messaging_attachment_reply_v1(
 (reservation->>'attachment_id')::uuid,'Quoted PDF','9f032200-0000-4000-8000-000000000161',null);
select is((select metadata #>> '{reply_to,content}' from public.messages
 where id=(select (publication->>'message_id')::uuid from quoted_attachment)),
 'Native original','native private attachment and quoted reference publish atomically');
select is((select public.publish_messaging_attachment_reply_v1((reservation->>'attachment_id')::uuid,
 'Quoted PDF','9f032200-0000-4000-8000-000000000161',null)->>'changed' from quoted_attachment),
 'false','same attachment reply replay is idempotent');
select throws_ok(format('select public.publish_messaging_attachment_reply_v1(%L::uuid,%L,%L::uuid,null)',
 (select reservation->>'attachment_id' from quoted_attachment),'Changed quote','9f032200-0000-4000-8000-000000000151'),
 '22023','Published attachment reply cannot be changed','published attachment cannot be retargeted by replay');
select ok(not has_function_privilege('anon','public.publish_messaging_attachment_reply_v1(uuid,text,uuid,uuid)','execute'),
 'anonymous cannot publish quoted attachment');

select * from finish();
rollback;
