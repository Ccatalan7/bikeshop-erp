begin;

select no_plan();

-- Correo que trabaja (20261106290000): el resumen de la mañana en el celular.
-- Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7a00000-0000-4000-8000-000000000001', 'Taller Mañana', 'manana@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7a00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'caja-manana@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7a00000-0000-4000-8000-000000000091', 'a7a00000-0000-4000-8000-000000000001', 'cashier', '{}', true);

set local session_replication_role = replica;
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7a00000-0000-4000-8000-000000000001', 'a7a00000-0000-4000-8000-000000000091', 'gmail',
   'taller@manana.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7a00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true where tenant_id = 'a7a00000-0000-4000-8000-000000000001';
select public.mail_prepare_tenant_v1('a7a00000-0000-4000-8000-000000000001');

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7a00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Ana left a review for Taller', 'received_at', now() - interval '1 hour')
  ))->>'new', '1', 'a review comes in');

-- El mismo cálculo para Inicio y para el aviso.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7a00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7a00000-0000-4000-8000-000000000091', true);
select set_config('test.inicio', public.mail_morning_summary_v1()::text, true);
reset role;
select is(public.mail_morning_summary_internal('a7a00000-0000-4000-8000-000000000001'),
  current_setting('test.inicio')::jsonb, 'Inicio and the phone read the same summary');
select is((current_setting('test.inicio')::jsonb->>'reviews')::int, 1, 'with the review to thank');

-- El despacho corre a cualquier hora sin fallar; fuera de las 8 o sin
-- secreto no encola nada.
select ok(public.dispatch_mail_morning_summary_v1() >= 0, 'the dispatcher runs');
select ok(public.dispatch_mail_morning_summary_v1() >= 0, 'and runs again without failing');

select ok(not has_function_privilege('authenticated', 'public.mail_morning_summary_internal(uuid)', 'EXECUTE'),
  'staff read the summary only through the checked entry');
select ok(has_function_privilege('service_role', 'public.mail_morning_summary_internal(uuid)', 'EXECUTE'),
  'the push function reads it with the service key');
select ok(not has_function_privilege('authenticated', 'public.dispatch_mail_morning_summary_v1()', 'EXECUTE'),
  'nobody in the app dispatches the summary');
select ok(not has_table_privilege('authenticated', 'public.mail_morning_push_log', 'SELECT'),
  'the dispatch log is not readable from the app');

select * from finish();
rollback;
