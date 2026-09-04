begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Synthetic, rolled back. Two tenants, one staff user of tenant A.
insert into public.tenants(id, shop_name) values
  ('9f032300-0000-4000-8000-000000000001', 'Inbox Test A'),
  ('9f032300-0000-4000-8000-000000000002', 'Inbox Test B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f032300-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'inbox-test@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f032300-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f032300-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f032300-0000-4000-8000-000000000091', '9f032300-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.conversations(id, tenant_id, type, channel, counterparty_type, title, status, created_by) values
  ('9f032300-0000-4000-8000-000000000141', '9f032300-0000-4000-8000-000000000001', 'support', 'whatsapp', 'customer', 'Mine', 'active', null),
  ('9f032300-0000-4000-8000-000000000142', '9f032300-0000-4000-8000-000000000002', 'support', 'whatsapp', 'customer', 'Foreign', 'active', null);
insert into public.messages(id, conversation_id, tenant_id, sender_id, content, type, metadata, message_direction, external_status)
select gen_random_uuid(), '9f032300-0000-4000-8000-000000000141', '9f032300-0000-4000-8000-000000000001', null,
       'inbound ' || n, 'text', '{}'::jsonb, 'inbound', null
from generate_series(1, 5) as n;
insert into public.messages(id, conversation_id, tenant_id, sender_id, content, type, metadata, message_direction, external_status)
values (gen_random_uuid(), '9f032300-0000-4000-8000-000000000142', '9f032300-0000-4000-8000-000000000002', null,
        'foreign', 'text', '{}'::jsonb, 'inbound', null);

select ok(not has_function_privilege('anon', 'public.inbox_latest_messages_v1(uuid[])', 'execute'), 'anonymous cannot read previews');
select ok(not has_function_privilege('anon', 'public.inbox_unread_counts_v1()', 'execute'), 'anonymous cannot read unread counts');

select set_config('request.jwt.claims', '{"sub":"9f032300-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032300-0000-4000-8000-000000000091', true);
set local role authenticated;
select is((select count(*) from public.inbox_latest_messages_v1(array['9f032300-0000-4000-8000-000000000141', '9f032300-0000-4000-8000-000000000142']::uuid[])
  where conversation_id = '9f032300-0000-4000-8000-000000000141'), 3::bigint, 'three latest rows per readable conversation');
select is((select content from public.inbox_latest_messages_v1(array['9f032300-0000-4000-8000-000000000141']::uuid[]) limit 1), 'inbound 5', 'newest first');
select is((select count(*) from public.inbox_latest_messages_v1(array['9f032300-0000-4000-8000-000000000142']::uuid[])), 0::bigint, 'a foreign tenant conversation yields nothing');
select is((select unread_count from public.conversation_unread_counts where conversation_id = '9f032300-0000-4000-8000-000000000141'), 5, 'staff sees five unread inbound messages through the view');
select is((select count(*) from public.conversation_unread_counts where conversation_id = '9f032300-0000-4000-8000-000000000142'), 0::bigint, 'the view never counts a foreign tenant');
reset role;
update public.conversations set staff_last_read_message_sequence = (select max(message_sequence) from public.messages where conversation_id = '9f032300-0000-4000-8000-000000000141')
 where id = '9f032300-0000-4000-8000-000000000141';
set local role authenticated;
select is((select unread_count from public.conversation_unread_counts where conversation_id = '9f032300-0000-4000-8000-000000000141'), 0, 'the staff read cursor clears the count');
reset role;
select * from finish();
rollback;
