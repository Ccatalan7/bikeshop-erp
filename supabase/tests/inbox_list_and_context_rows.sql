begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Synthetic, rolled back: tenant A with a staff user, a customer reachable by
-- phone, an open job with a bike; tenant B with a conversation of its own.
insert into public.tenants(id, shop_name) values
  ('9f032400-0000-4000-8000-000000000001', 'Inbox Rows A'),
  ('9f032400-0000-4000-8000-000000000002', 'Inbox Rows B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('9f032400-0000-4000-8000-000000000091', 'authenticated', 'authenticated', 'inbox-rows-staff@example.invalid', '', now(), '{}', '{"tenant_id":"9f032400-0000-4000-8000-000000000001"}', now(), now()),
  ('9f032400-0000-4000-8000-000000000092', 'authenticated', 'authenticated', 'inbox-rows-nobody@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id in ('9f032400-0000-4000-8000-000000000091', '9f032400-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f032400-0000-4000-8000-000000000091', '9f032400-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active)
values ('9f032400-0000-4000-8000-000000000131', '9f032400-0000-4000-8000-000000000001', 'inbox-rows-test', 'Synthetic', true);
insert into public.conversations(id, tenant_id, type, channel, counterparty_type, title, status, created_by, last_message_at) values
  ('9f032400-0000-4000-8000-000000000141', '9f032400-0000-4000-8000-000000000001', 'support', 'whatsapp', 'customer', 'Mine', 'active', null, now()),
  ('9f032400-0000-4000-8000-000000000142', '9f032400-0000-4000-8000-000000000002', 'support', 'whatsapp', 'customer', 'Foreign', 'active', null, now());
insert into public.conversation_participants(conversation_id, tenant_id, user_id)
values ('9f032400-0000-4000-8000-000000000141', '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000091');
insert into public.customers(id, tenant_id, name, phone, is_active)
values ('9f032400-0000-4000-8000-000000000201', '9f032400-0000-4000-8000-000000000001', 'Cliente Sintético', '+56 9 1111 2222', true);
insert into public.whatsapp_conversation_bindings(tenant_id, conversation_id, channel_id, external_wa_id, external_phone_number)
values ('9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000141', '9f032400-0000-4000-8000-000000000131', '56911112222', '56911112222');
insert into public.bikes(id, tenant_id, customer_id, brand, model, year)
values ('9f032400-0000-4000-8000-000000000301', '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000201', 'Trek', 'Marlin', 2024);
insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id, job_number, status)
values ('9f032400-0000-4000-8000-000000000401', '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000201', '9f032400-0000-4000-8000-000000000301', 'JOB-SYN-1', 'EN_PROCESO');

select ok(not has_function_privilege('anon', 'public.inbox_conversations_v1(text)', 'execute'), 'anonymous cannot list the inbox');
select ok(not has_function_privilege('anon', 'public.inbox_context_hint_rows_v1(uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])', 'execute'), 'anonymous cannot read hint rows');

select set_config('request.jwt.claims', '{"sub":"9f032400-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032400-0000-4000-8000-000000000091', true);
set local role authenticated;
create temporary table inbox_rows_result as select * from public.inbox_conversations_v1('support') as row;
select is((select count(*) from inbox_rows_result where row->>'id' = '9f032400-0000-4000-8000-000000000141'), 1::bigint, 'staff sees the tenant support conversation');
select is((select count(*) from inbox_rows_result where row->>'id' = '9f032400-0000-4000-8000-000000000142'), 0::bigint, 'a foreign tenant conversation is not listed');
select is((select jsonb_typeof(row->'conversation_participants') from inbox_rows_result where row->>'id' = '9f032400-0000-4000-8000-000000000141'), 'array', 'participants embed keeps the PostgREST shape');
select is((select row#>>'{conversation_participants,0,user_id}' from inbox_rows_result where row->>'id' = '9f032400-0000-4000-8000-000000000141'), '9f032400-0000-4000-8000-000000000091', 'participant user ids are embedded');
create temporary table inbox_hint_bundle as select public.inbox_context_hint_rows_v1(array['9f032400-0000-4000-8000-000000000141', '9f032400-0000-4000-8000-000000000142']::uuid[]) as bundle;
select is((select jsonb_array_length(bundle->'bindings') from inbox_hint_bundle), 1, 'bindings come only for the tenant conversation');
select ok((select bundle->'customers' @> '[{"id":"9f032400-0000-4000-8000-000000000201"}]' from inbox_hint_bundle), 'a customer sharing the thread phone digits is offered');
select ok((select bundle->'mechanic_jobs' @> '[{"id":"9f032400-0000-4000-8000-000000000401"}]' from inbox_hint_bundle), 'the customer job travels with the bundle');
select ok((select bundle->'bikes' @> '[{"id":"9f032400-0000-4000-8000-000000000301"}]' from inbox_hint_bundle), 'the job bike travels with the bundle');
reset role;

select set_config('request.jwt.claims', '{"sub":"9f032400-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f032400-0000-4000-8000-000000000092', true);
set local role authenticated;
select is((select count(*) from public.inbox_conversations_v1(null)), 0::bigint, 'a user without a profile sees nothing');
select is((select jsonb_array_length(public.inbox_context_hint_rows_v1(array['9f032400-0000-4000-8000-000000000141']::uuid[])->'customers')), 0, 'a non-staff user gets an empty bundle');
reset role;
select * from finish();
rollback;
