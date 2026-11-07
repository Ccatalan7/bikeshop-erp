begin;

select no_plan();

-- Correo que trabaja (20261106230000): la bandeja unida o una sola casilla,
-- con sus conteos. Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7d00000-0000-4000-8000-000000000001', 'Taller Casillas', 'casillas@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7d00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-casillas@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7d00000-0000-4000-8000-000000000091', 'a7d00000-0000-4000-8000-000000000001', 'admin', '{}', true);

set local session_replication_role = replica;
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7d00000-0000-4000-8000-000000000001', 'a7d00000-0000-4000-8000-000000000091', 'gmail',
   'taller@gmail.example', 'sintetico', true),
  ('a7d00000-0000-4000-8000-000000000001', 'a7d00000-0000-4000-8000-000000000091', 'zoho',
   'contacto@taller-casillas.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7d00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7d00000-0000-4000-8000-000000000001';

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'taller@gmail.example'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'g-resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Ana left a review for Taller', 'received_at', now() - interval '1 hour'),
    jsonb_build_object('provider_message_id', 'g-promo', 'from_address', 'ofertas@marca.example', 'is_bulk', true,
      'subject', 'Ofertas de temporada', 'received_at', now() - interval '2 hours')
  ))->>'new', '2', 'two messages enter the Gmail mailbox');
select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'contacto@taller-casillas.example'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'z-resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Luis left a review for Taller', 'received_at', now() - interval '3 hours')
  ))->>'new', '1', 'one message enters the Zoho mailbox');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7d00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7d00000-0000-4000-8000-000000000091', true);

select is(jsonb_array_length(public.mail_inbox_v2('today')), 2, 'the merged inbox shows both mailboxes');
select is(jsonb_array_length(public.mail_inbox_v2('today', p_mailbox := 'taller@gmail.example')), 1,
  'one mailbox shows only its own');
select is(public.mail_inbox_v2('today', p_mailbox := 'Contacto@Taller-Casillas.example')->0->>'mailbox',
  'contacto@taller-casillas.example', 'the address is matched folded');
select is(public.mail_inbox_v2('all', p_mailbox := 'nadie@otra.example'), '[]'::jsonb,
  'an address that is not a mailbox of the shop shows nothing');
select is((public.mail_counts_v2()->>'today')::int, 2, 'the merged count');
select is((public.mail_counts_v2('taller@gmail.example')->>'today')::int, 1, 'the count of one mailbox');
select is(jsonb_array_length(public.mail_counts_v2('taller@gmail.example')->'mailboxes'), 2,
  'the selector still lists every mailbox');
reset role;

select ok(not has_function_privilege('anon', 'public.mail_inbox_v2(text, text, text, integer, timestamptz, text)', 'EXECUTE'),
  'anonymous callers cannot read the mail');

select * from finish();
rollback;
