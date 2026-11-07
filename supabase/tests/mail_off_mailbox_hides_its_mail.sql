begin;

select no_plan();

-- Correo que trabaja (20261106240000): una casilla apagada no se ve, ni en la
-- bandeja ni en los conteos ni por la tabla, y vuelve a verse al encenderla.
-- Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7e00000-0000-4000-8000-000000000001', 'Taller Apagado', 'apagado@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7e00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'duena-apagado@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7e00000-0000-4000-8000-000000000091', 'a7e00000-0000-4000-8000-000000000001', 'admin', '{}', true);

set local session_replication_role = replica;
insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  ('a7e00000-0000-4000-8000-000000000031', 'a7e00000-0000-4000-8000-000000000001',
   'Cliente Sintetico', '+56 9 0000 0031', 'cliente@apagado.example', true);
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7e00000-0000-4000-8000-000000000001', 'a7e00000-0000-4000-8000-000000000091', 'gmail',
   'taller@apagado.example', 'sintetico', true),
  ('a7e00000-0000-4000-8000-000000000001', 'a7e00000-0000-4000-8000-000000000091', 'zoho',
   'personal@apagado.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7e00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7e00000-0000-4000-8000-000000000001';
select set_config('test.personal',
  (select id::text from public.mail_mailboxes where address = 'personal@apagado.example'), true);

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'taller@apagado.example'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 't-resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Ana left a review for Taller', 'received_at', now() - interval '1 hour')
  ))->>'new', '1', 'one message enters the shop mailbox');
select is(public.mail_upsert_messages_v1(
  current_setting('test.personal')::uuid,
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'p-resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Luis left a review for Taller', 'received_at', now() - interval '2 hours'),
    jsonb_build_object('provider_message_id', 'p-cliente', 'from_address', 'cliente@apagado.example',
      'from_name', 'Cliente Sintetico', 'subject', 'Consulta privada', 'received_at', now() - interval '3 hours')
  ))->>'new', '2', 'two messages enter the mailbox that will be turned off');
select set_config('test.privado',
  (select id::text from public.mail_messages where provider_message_id = 'p-cliente'), true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7e00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7e00000-0000-4000-8000-000000000091', true);

-- Encendidas las dos: todo se ve, y cada casilla trae lo suyo para el selector.
select is(jsonb_array_length(public.mail_inbox_v2('today')), 3, 'both mailboxes are in the merged inbox');
select is((public.mail_counts_v2()->>'today')::int, 3, 'the merged count');
select is((select (e->>'today')::int from jsonb_array_elements(public.mail_counts_v2()->'mailboxes') e
            where e->>'address' = 'personal@apagado.example'), 2, 'each mailbox brings its own today count');
select is((select (e->>'today')::int from jsonb_array_elements(public.mail_counts_v2('taller@apagado.example')->'mailboxes') e
            where e->>'address' = 'personal@apagado.example'), 2,
  'the other mailbox keeps its count while one is chosen');
select is((public.mail_counts_v2('nadie@otra.example')->>'today')::int, 0,
  'an address that is not a mailbox counts nothing');
select is(public.mail_link_v1(current_setting('test.privado')::uuid, 'customer',
  'a7e00000-0000-4000-8000-000000000031')->0->>'type', 'customer', 'the private mail is linked to a customer');

-- Apagada la personal: desaparece de todas partes.
select is((public.mail_set_mailbox_active_v1(current_setting('test.personal')::uuid, false)->>'is_active')::boolean,
  false, 'the owner turns the mailbox off');
select is(jsonb_array_length(public.mail_inbox_v2('today')), 1, 'its mail leaves the merged inbox');
select is(jsonb_array_length(public.mail_inbox_v2('all')), 1, 'and every other view');
select is(public.mail_inbox_v2('all', p_mailbox := 'personal@apagado.example'), '[]'::jsonb,
  'choosing it shows nothing');
select is(jsonb_array_length(public.mail_inbox_v1('today')), 1, 'the v1 inbox follows the same rule');
select is((public.mail_counts_v2()->>'today')::int, 1, 'the count drops');
select is(jsonb_array_length(public.mail_counts_v2()->'mailboxes'), 1, 'the selector lists only the mailbox that is on');
select is((public.mail_counts_v1()->>'today')::int, 1, 'the v1 count follows the same rule');
select throws_ok($$select public.mail_message_v1(current_setting('test.privado')::uuid)$$,
  'P0002', 'mail_not_found', 'one of its messages cannot be opened');
select is(public.mail_record_messages_v1('customer', 'a7e00000-0000-4000-8000-000000000031'), '[]'::jsonb,
  'the customer history no longer shows it');
select is(public.mail_mark_v1(array[current_setting('test.privado')::uuid], 'archive'), 0,
  'nobody can act on it');
select throws_ok($$select public.mail_set_kind_v1(current_setting('test.privado')::uuid, 'noise')$$,
  'P0002', 'mail_not_found', 'nor correct its kind');
select throws_ok($$select public.mail_link_v1(current_setting('test.privado')::uuid, 'customer', 'a7e00000-0000-4000-8000-000000000031')$$,
  'P0002', 'mail_not_found', 'nor link it');
select is((select count(*)::int from public.mail_messages), 1, 'the table only shows mail of mailboxes that are on');
select is((select count(*)::int from public.mail_message_links), 0, 'nor the links of the hidden mail');

-- Encendida otra vez: vuelve todo, nada se borró.
select is((public.mail_set_mailbox_active_v1(current_setting('test.personal')::uuid, true)->>'is_active')::boolean,
  true, 'the owner turns it back on');
select is(jsonb_array_length(public.mail_inbox_v2('today')), 3, 'its mail is back');
select is(jsonb_array_length(public.mail_record_messages_v1('customer', 'a7e00000-0000-4000-8000-000000000031')), 1,
  'with its link');
reset role;

select ok(not has_function_privilege('anon', 'public.mail_counts_v2(text)', 'EXECUTE'),
  'anonymous callers cannot read the counts');

select * from finish();
rollback;
