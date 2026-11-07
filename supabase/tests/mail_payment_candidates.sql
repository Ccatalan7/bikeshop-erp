begin;

select no_plan();

-- Correo que trabaja (20261106250000): a qué cobro corresponde una
-- transferencia. Nombres, montos y documentos son inventados.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7f00000-0000-4000-8000-000000000001', 'Taller Cobros', 'cobros@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7f00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'caja-cobros@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7f00000-0000-4000-8000-000000000091', 'a7f00000-0000-4000-8000-000000000001', 'cashier', '{}', true);

set local session_replication_role = replica;
insert into public.customers (id, tenant_id, name, phone, is_active) values
  ('a7f00000-0000-4000-8000-000000000011', 'a7f00000-0000-4000-8000-000000000001', 'Camila Prueba', '+56 9 0000 0011', true),
  ('a7f00000-0000-4000-8000-000000000012', 'a7f00000-0000-4000-8000-000000000001', 'Rodrigo Otro', '+56 9 0000 0012', true);
insert into public.sales_invoices (id, tenant_id, invoice_number, status, date, total, balance, customer_id) values
  ('a7f00000-0000-4000-8000-000000000071', 'a7f00000-0000-4000-8000-000000000001', 'V-C1', 'confirmed',
   now() - interval '2 days', 45990, 45990, 'a7f00000-0000-4000-8000-000000000011'),
  ('a7f00000-0000-4000-8000-000000000072', 'a7f00000-0000-4000-8000-000000000001', 'V-C2', 'confirmed',
   now() - interval '20 days', 80000, 60000, 'a7f00000-0000-4000-8000-000000000011'),
  ('a7f00000-0000-4000-8000-000000000073', 'a7f00000-0000-4000-8000-000000000001', 'V-C3', 'confirmed',
   now() - interval '1 day', 45990, 45990, 'a7f00000-0000-4000-8000-000000000012'),
  ('a7f00000-0000-4000-8000-000000000074', 'a7f00000-0000-4000-8000-000000000001', 'V-C4', 'paid',
   now() - interval '1 day', 45990, 0, 'a7f00000-0000-4000-8000-000000000011'),
  ('a7f00000-0000-4000-8000-000000000075', 'a7f00000-0000-4000-8000-000000000001', 'V-C5', 'draft',
   now() - interval '1 day', 45990, 45990, 'a7f00000-0000-4000-8000-000000000011');
insert into public.online_orders (id, tenant_id, order_number, customer_name, customer_email, total, status, is_test, created_at) values
  ('a7f00000-0000-4000-8000-000000000081', 'a7f00000-0000-4000-8000-000000000001', 'WEB-C-1',
   'Camila Prueba', 'camila@ejemplo.invalid', 45990, 'pending', false, now() - interval '1 day'),
  ('a7f00000-0000-4000-8000-000000000082', 'a7f00000-0000-4000-8000-000000000001', 'WEB-C-2',
   'Camila Prueba', 'camila@ejemplo.invalid', 45990, 'pending', true, now() - interval '1 day');
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7f00000-0000-4000-8000-000000000001', 'a7f00000-0000-4000-8000-000000000091', 'gmail',
   'caja@taller-cobros.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7f00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true
 where tenant_id = 'a7f00000-0000-4000-8000-000000000001';

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7f00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'con-nombre', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos', 'received_at', now(),
      'body_text', 'Le informamos que Camila Prueba le ha transferido $45.990 , el día de hoy.'),
    jsonb_build_object('provider_message_id', 'sin-nombre', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos', 'received_at', now(),
      'body_text', 'Se ha realizado una transferencia a su cuenta por $45.990 .'),
    jsonb_build_object('provider_message_id', 'otra-persona', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos', 'received_at', now(),
      'body_text', 'Le informamos que Patricia Nadie le ha transferido $45.990 , el día de hoy.'),
    jsonb_build_object('provider_message_id', 'no-es-pago', 'from_address', 'ofertas@marca.example', 'is_bulk', true,
      'subject', 'Ofertas', 'received_at', now())
  ))->>'new', '4', 'four messages enter');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7f00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7f00000-0000-4000-8000-000000000091', true);

-- Con nombre: sólo los cobros de esa persona, el exacto primero
select is((select string_agg(e->>'label', ',' order by ord)
             from jsonb_array_elements(public.mail_payment_candidates_v1(
               (select id from public.mail_messages where provider_message_id = 'con-nombre'))) with ordinality as t(e, ord)),
  'WEB-C-1,V-C1,V-C2', 'the payer''s exact ones, closest in time first, then her larger balance');
select ok(not exists (select 1 from jsonb_array_elements(public.mail_payment_candidates_v1(
            (select id from public.mail_messages where provider_message_id = 'con-nombre'))) e
           where e->>'label' in ('V-C3', 'V-C4', 'V-C5', 'WEB-C-2')),
  'never someone else''s invoice, a paid one, a draft or a test order');
select is((public.mail_payment_candidates_v1(
            (select id from public.mail_messages where provider_message_id = 'con-nombre'))->0->>'named')::boolean,
  true, 'the first one is marked as the payer''s');

-- Sin nombre: sólo los de saldo exacto, para elegir
select is((select string_agg(e->>'label', ',' order by e->>'label')
             from jsonb_array_elements(public.mail_payment_candidates_v1(
               (select id from public.mail_messages where provider_message_id = 'sin-nombre'))) e),
  'V-C1,V-C3,WEB-C-1', 'without a name, only exact balances');
select ok(not exists (select 1 from jsonb_array_elements(public.mail_payment_candidates_v1(
            (select id from public.mail_messages where provider_message_id = 'sin-nombre'))) e
           where (e->>'named')::boolean),
  'and none is presented as the payer''s');

-- Un nombre que no es cliente: los exactos, sin decir que son suyos
select is(jsonb_array_length(public.mail_payment_candidates_v1(
            (select id from public.mail_messages where provider_message_id = 'otra-persona'))), 3,
  'an unknown payer falls back to the exact balances');

select is(public.mail_payment_candidates_v1(
            (select id from public.mail_messages where provider_message_id = 'no-es-pago')), '[]'::jsonb,
  'a mail that is not a transfer proposes nothing');
reset role;

select ok(not has_function_privilege('anon', 'public.mail_payment_candidates_v1(uuid)', 'EXECUTE'),
  'anonymous callers cannot ask');

select * from finish();
rollback;
