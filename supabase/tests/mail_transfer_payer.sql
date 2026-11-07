begin;

select no_plan();

-- Correo que trabaja (20261106220000): una transferencia sale «ya pagada» sólo
-- si calzan el monto y el nombre de quien transfiere. Los textos imitan cómo
-- escribe cada banco; los nombres y montos son inventados.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Lo que se lee del aviso, banco por banco
select is(public.mail_extract_facts_internal('Aviso de transferencia de fondos',
  'Te informamos que nuestro(a) cliente ANA PRUEBA SOTO ha efectuado una transferencia', 'a@bancochile.cl')->>'payer',
  'ANA PRUEBA SOTO', 'Banco de Chile: nuestro(a) cliente … ha efectuado');
select is(public.mail_extract_facts_internal('Transferencia',
  'Le informamos que Camila Prueba le ha transferido $45.990 , el día 5 de noviembre de 2026.', 'a@bancochile.cl')->>'payer',
  'Camila Prueba', 'Banco de Chile: … le ha transferido');
select is(public.mail_extract_facts_internal('Transferencia realizada',
  'Le informamos que hoy, 05-11-2026, nuestro(a) cliente Juan Ejemplo Diaz ha instruido una transferencia de fondos a su cuenta',
  'a@cl.bancofalabella.com')->>'payer', 'Juan Ejemplo Diaz', 'Falabella: nuestro(a) cliente … ha instruido');
select is(public.mail_extract_facts_internal('Transferencia de fondos',
  'Te informamos que, con fecha 05/11/2026, nuestro cliente Pedro Ejemplo . realizó una transferencia a tu cuenta.',
  'a@santander.cl')->>'payer', 'Pedro Ejemplo', 'Santander: nuestro cliente … realizó');
select is(public.mail_extract_facts_internal('Aviso de Transferencia de Fondos',
  'De acuerdo con lo instruido por nuestro cliente COMERCIAL PRUEBA Y COMPAÑIA LIMITADA , le informamos que con Fecha: 05',
  'a@santander.cl')->>'payer', 'COMERCIAL PRUEBA Y COMPAÑIA LIMITADA', 'Santander: lo instruido por nuestro cliente …');
select is(public.mail_extract_facts_internal('Transferencia de fondos recibida',
  'Con fecha de hoy 05/11/2026, nuestro cliente el Sr(a) MARIA PRUEBA SILVA ha instruido transferencia de fondos a su cuenta',
  'a@scotiabank.cl')->>'payer', 'MARIA PRUEBA SILVA', 'Scotiabank: el Sr(a) …');
select is(public.mail_extract_facts_internal('Transferencia',
  'Has recibido una transferencia de fondos de Camila Prueba hacia tu cuenta del Banco de Chile', 'a@bci.cl')->>'payer',
  'Camila Prueba', 'BCI: transferencia de fondos de … hacia');
select is(public.mail_extract_facts_internal('Comprobante transferencia de fondos',
  E'Te informamos que has recibido una transferencia de fondos por parte de:\nCamila Prueba Soto , te enviamos los detalles de la transacción.',
  'a@bancoconsorcio.cl')->>'payer', 'Camila Prueba Soto', 'Consorcio: por parte de: … , te enviamos');

-- Quién es quién
select ok(public.mail_names_match_internal('ANA MARIA PRUEBA SOTO', 'Ana Prueba'), 'two shared words are the same person');
select ok(not public.mail_names_match_internal('Ana Soto', 'Juan Soto'), 'one shared surname is not');
select ok(public.mail_names_match_internal('Matías', 'Matias Prueba'), 'the only word of the shorter name is enough');
select ok(not public.mail_names_match_internal(null, 'Ana Prueba'), 'no name never matches');

-- El estado, contra pagos reales
insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7c00000-0000-4000-8000-000000000001', 'Taller Pagos', 'pagos@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7c00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-pagos@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7c00000-0000-4000-8000-000000000091', 'a7c00000-0000-4000-8000-000000000001', 'admin', '{}', true);

set local session_replication_role = replica;
insert into public.customers (id, tenant_id, name, phone, is_active) values
  ('a7c00000-0000-4000-8000-000000000011', 'a7c00000-0000-4000-8000-000000000001', 'Camila Prueba', '+56 9 0000 0001', true),
  ('a7c00000-0000-4000-8000-000000000012', 'a7c00000-0000-4000-8000-000000000001', 'Rodrigo Otro', '+56 9 0000 0002', true);
insert into public.payment_methods (id, tenant_id, code, name, is_active, account_id) values
  ('a7c00000-0000-4000-8000-000000000061', 'a7c00000-0000-4000-8000-000000000001', 'transfer-pagos', 'Transferencia', true,
   'a7c00000-0000-4000-8000-000000000069');
insert into public.sales_invoices (id, tenant_id, invoice_number, total, balance, customer_id) values
  ('a7c00000-0000-4000-8000-000000000071', 'a7c00000-0000-4000-8000-000000000001', 'V-P1', 45990, 0,
   'a7c00000-0000-4000-8000-000000000011'),
  ('a7c00000-0000-4000-8000-000000000072', 'a7c00000-0000-4000-8000-000000000001', 'V-P2', 18000, 0,
   'a7c00000-0000-4000-8000-000000000012');
insert into public.sales_payments (id, tenant_id, invoice_id, amount, date, payment_method_id) values
  ('a7c00000-0000-4000-8000-000000000081', 'a7c00000-0000-4000-8000-000000000001',
   'a7c00000-0000-4000-8000-000000000071', 45990, now() - interval '1 hour', 'a7c00000-0000-4000-8000-000000000061'),
  ('a7c00000-0000-4000-8000-000000000082', 'a7c00000-0000-4000-8000-000000000001',
   'a7c00000-0000-4000-8000-000000000072', 18000, now() - interval '1 hour', 'a7c00000-0000-4000-8000-000000000061');
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7c00000-0000-4000-8000-000000000001', 'a7c00000-0000-4000-8000-000000000091', 'gmail',
   'caja@taller-pagos.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('a7c00000-0000-4000-8000-000000000001');
update public.mail_mailboxes set is_active = true
 where tenant_id = 'a7c00000-0000-4000-8000-000000000001';

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7c00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'p-match', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos',
      'body_text', E'Le informamos que Camila Prueba le ha transferido $45.990 , el día de hoy.',
      'received_at', now() - interval '2 hours'),
    jsonb_build_object('provider_message_id', 'p-otra', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos',
      'body_text', E'Le informamos que Ana Distinta le ha transferido $18.000 , el día de hoy.',
      'received_at', now() - interval '2 hours'),
    jsonb_build_object('provider_message_id', 'p-sin-nombre', 'from_address', 'notificaciones@tenpo.cl',
      'subject', 'Recibiste una transferencia', 'body_text', 'Monto: $45.990',
      'received_at', now() - interval '2 hours')
  ))->>'new', '3', 'three transfer notices enter');

select is((select kind from public.mail_messages where provider_message_id = 'p-match'), 'transfer', 'a bank notice is a transfer');
select is((select public.mail_message_state_internal(id)->>'done' from public.mail_messages where provider_message_id = 'p-match'),
  'true', 'same amount and same name: already paid');
select is((select public.mail_message_state_internal(id)->>'done_text' from public.mail_messages where provider_message_id = 'p-match'),
  'Ya registrado: pago de Camila Prueba', 'and it says whose payment it was');
select is((select public.mail_message_state_internal(id)->>'done' from public.mail_messages where provider_message_id = 'p-otra'),
  'false', 'same amount from somebody else: still to do');
select is((select public.mail_message_state_internal(id)->>'done' from public.mail_messages where provider_message_id = 'p-sin-nombre'),
  'false', 'without the payer''s name it is never assumed paid');
select is((select public.mail_message_state_internal(id)->>'action' from public.mail_messages where provider_message_id = 'p-sin-nombre'),
  'register_payment', 'and it still offers to register it');

select * from finish();
rollback;
