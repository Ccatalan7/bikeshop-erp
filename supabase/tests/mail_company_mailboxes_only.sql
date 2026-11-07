begin;

select no_plan();

-- Correo que trabaja (20261106210000): sólo las casillas de la empresa. Una
-- casilla conectada nace apagada y la enciende el dueño o un administrador;
-- «lo nuestro» sale de las casillas encendidas, no de un dominio fijo.
-- Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7b00000-0000-4000-8000-000000000001', 'Taller Uno', 'uno@example.invalid', 'America/Santiago', true),
  ('a7b00000-0000-4000-8000-000000000002', 'Taller Dos', 'dos@example.invalid', 'America/Santiago', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7b00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-uno@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('a7b00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'mecanico-uno@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('a7b00000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'admin-dos@example.invalid', '', now(), '{}', '{}', now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7b00000-0000-4000-8000-000000000091', 'a7b00000-0000-4000-8000-000000000001', 'admin', '{}', true),
  ('a7b00000-0000-4000-8000-000000000092', 'a7b00000-0000-4000-8000-000000000001', 'mechanic', '{}', true),
  ('a7b00000-0000-4000-8000-000000000093', 'a7b00000-0000-4000-8000-000000000002', 'admin', '{}', true);

set local session_replication_role = replica;
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7b00000-0000-4000-8000-000000000001', 'a7b00000-0000-4000-8000-000000000091', 'zoho',
   'Contacto@Taller-Uno.example', 'sintetico', true),
  ('a7b00000-0000-4000-8000-000000000001', 'a7b00000-0000-4000-8000-000000000092', 'gmail',
   'mecanico.personal@gmail.com', 'sintetico', true);
set local session_replication_role = origin;

select is((public.mail_prepare_tenant_v1('a7b00000-0000-4000-8000-000000000001')->>'new_mailboxes')::int, 2,
  'both connected accounts become mailboxes');
select is((select count(*)::int from public.mail_mailboxes
            where tenant_id = 'a7b00000-0000-4000-8000-000000000001' and is_active), 0,
  'a connected mailbox is born off: nobody''s personal mail is stored for the team');
select is_empty($$select 1 from public.mail_senders
                   where tenant_id = 'a7b00000-0000-4000-8000-000000000001' and party_type = 'own'$$,
  'nothing is ours until a mailbox is turned on');
select is_empty($$select 1 from public.mail_senders where match_value = 'vinabike.cl'
                   and tenant_id = 'a7b00000-0000-4000-8000-000000000001'$$,
  'no shop''s domain is seeded into another tenant');

select set_config('test.casilla_uno',
  (select id::text from public.mail_mailboxes where address = 'contacto@taller-uno.example'), true);

set local role authenticated;

-- Un mecánico del mismo taller no enciende casillas.
select set_config('request.jwt.claims', '{"sub":"a7b00000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7b00000-0000-4000-8000-000000000092', true);
select throws_ok($$select public.mail_set_mailbox_active_v1(current_setting('test.casilla_uno')::uuid, true)$$,
  '42501', 'mail_forbidden', 'a mechanic cannot turn a mailbox on');

-- El administrador de otro taller ni siquiera la encuentra.
select set_config('request.jwt.claims', '{"sub":"a7b00000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7b00000-0000-4000-8000-000000000093', true);
select throws_ok($$select public.mail_set_mailbox_active_v1(current_setting('test.casilla_uno')::uuid, true)$$,
  'P0002', 'mail_mailbox_not_found', 'another shop''s admin cannot see nor turn on the mailbox');

-- El administrador del taller enciende la casilla de la empresa.
select set_config('request.jwt.claims', '{"sub":"a7b00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7b00000-0000-4000-8000-000000000091', true);
select is((public.mail_set_mailbox_active_v1(current_setting('test.casilla_uno')::uuid, true)->>'is_active')::boolean,
  true, 'the admin turns the company mailbox on');
reset role;

select is((select party_type from public.mail_senders
            where tenant_id = 'a7b00000-0000-4000-8000-000000000001'
              and match_type = 'address' and match_value = 'contacto@taller-uno.example'),
  'own', 'its address is ours');
select is((select party_type from public.mail_senders
            where tenant_id = 'a7b00000-0000-4000-8000-000000000001'
              and match_type = 'domain' and match_value = 'taller-uno.example'),
  'own', 'and its own domain too');
select is_empty($$select 1 from public.mail_senders
                   where tenant_id = 'a7b00000-0000-4000-8000-000000000001'
                     and match_value in ('gmail.com', 'mecanico.personal@gmail.com')$$,
  'the personal mailbox stays out, and gmail.com is nobody''s');
select is((select is_active from public.mail_mailboxes where address = 'mecanico.personal@gmail.com'),
  false, 'the personal mailbox stays off');

set local role authenticated;
select is((public.mail_set_mailbox_active_v1(current_setting('test.casilla_uno')::uuid, false)->>'is_active')::boolean,
  false, 'the admin can turn it off again');
reset role;
select is_empty($$select 1 from public.mail_senders
                   where tenant_id = 'a7b00000-0000-4000-8000-000000000001' and party_type = 'own'$$,
  'turning it off takes it out of what is ours');

select ok(not has_function_privilege('anon', 'public.mail_set_mailbox_active_v1(uuid, boolean)', 'EXECUTE'),
  'anonymous callers cannot touch mailboxes');

select * from finish();
rollback;
