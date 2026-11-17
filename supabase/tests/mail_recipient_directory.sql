begin;

select plan(19);

-- Correo: la libreta de destinatarios (20261116220000, con logos desde
-- 20261116230000). Proveedores activos con su correo, su vendedor y sus
-- contactos; clientes activos; y a quién ya le escribió el taller desde una
-- casilla encendida. Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b8d10000-0000-4000-8000-000000000001', 'Taller Libreta', 'libreta@example.invalid', 'America/Santiago', true),
  ('b8d10000-0000-4000-8000-000000000002', 'Taller Vecino', 'vecino@example.invalid', 'America/Santiago', true);
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('b8d10000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'duena-libreta@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('b8d10000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'duena-vecino@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('b8d10000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'cuenta-portal@example.invalid', '', now(), '{}', '{}', now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('b8d10000-0000-4000-8000-000000000091', 'b8d10000-0000-4000-8000-000000000001', 'admin', '{}', true),
  ('b8d10000-0000-4000-8000-000000000092', 'b8d10000-0000-4000-8000-000000000002', 'admin', '{}', true);

set local session_replication_role = replica;
insert into public.suppliers (id, tenant_id, name, email, sales_rep_name, sales_rep_email, image_url, is_active) values
  ('b8d10000-0000-4000-8000-000000000011', 'b8d10000-0000-4000-8000-000000000001',
   'Importadora Andina', '  Ventas@Andina.example ', 'Rocío Pérez', 'rocio@andina.example',
   'https://example.invalid/andina.png', true),
  ('b8d10000-0000-4000-8000-000000000012', 'b8d10000-0000-4000-8000-000000000001',
   'Ruedas del Sur', 'contacto@ruedas.example', null, null, null, false),
  ('b8d10000-0000-4000-8000-000000000013', 'b8d10000-0000-4000-8000-000000000001',
   'Frenos Norte', null, null, null, null, true),
  ('b8d10000-0000-4000-8000-000000000014', 'b8d10000-0000-4000-8000-000000000001',
   'Sin Correo', 'escribir por whatsapp', null, null, null, true),
  ('b8d10000-0000-4000-8000-000000000015', 'b8d10000-0000-4000-8000-000000000002',
   'Proveedor Ajeno', 'ajeno@proveedor.example', null, null, null, true);
insert into public.supplier_contacts (id, tenant_id, supplier_id, name, role, email, is_active, deactivated_at) values
  ('b8d10000-0000-4000-8000-000000000021', 'b8d10000-0000-4000-8000-000000000001',
   'b8d10000-0000-4000-8000-000000000013', 'Pedro Soto', 'Vendedor', 'Pedro@Frenos.example', true, null),
  ('b8d10000-0000-4000-8000-000000000022', 'b8d10000-0000-4000-8000-000000000001',
   'b8d10000-0000-4000-8000-000000000013', 'Ana Ruiz', null, 'ana@frenos.example', false, now());
insert into public.customers (id, tenant_id, name, phone, email, is_active) values
  ('b8d10000-0000-4000-8000-000000000031', 'b8d10000-0000-4000-8000-000000000001',
   'Cliente Uno', '+56 9 0000 0031', 'uno@cliente.example', true),
  ('b8d10000-0000-4000-8000-000000000032', 'b8d10000-0000-4000-8000-000000000001',
   'Cliente Dos', '+56 9 0000 0032', 'dos@cliente.example', false),
  ('b8d10000-0000-4000-8000-000000000033', 'b8d10000-0000-4000-8000-000000000001',
   'Pedro Soto', '+56 9 0000 0033', 'pedro@frenos.example', true),
  ('b8d10000-0000-4000-8000-000000000034', 'b8d10000-0000-4000-8000-000000000002',
   'Cliente Ajeno', '+56 9 0000 0034', 'ajeno@cliente.example', true);
insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('b8d10000-0000-4000-8000-000000000001', 'b8d10000-0000-4000-8000-000000000091', 'gmail',
   'taller@libreta.example', 'sintetico', true),
  ('b8d10000-0000-4000-8000-000000000001', 'b8d10000-0000-4000-8000-000000000091', 'zoho',
   'apagada@libreta.example', 'sintetico', true),
  ('b8d10000-0000-4000-8000-000000000002', 'b8d10000-0000-4000-8000-000000000092', 'gmail',
   'taller@vecino.example', 'sintetico', true);
set local session_replication_role = origin;

select public.mail_prepare_tenant_v1('b8d10000-0000-4000-8000-000000000001');
select public.mail_prepare_tenant_v1('b8d10000-0000-4000-8000-000000000002');
update public.mail_mailboxes set is_active = true
 where tenant_id in ('b8d10000-0000-4000-8000-000000000001', 'b8d10000-0000-4000-8000-000000000002');

select public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'taller@libreta.example'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'out-1', 'direction', 'out',
      'from_address', 'taller@libreta.example',
      'to_addresses', jsonb_build_array('nuevo@lejano.example'),
      'cc_addresses', jsonb_build_array('uno@cliente.example'),
      'subject', 'Cotización', 'received_at', now() - interval '3 days'),
    jsonb_build_object('provider_message_id', 'out-2', 'direction', 'out',
      'from_address', 'taller@libreta.example',
      'to_addresses', jsonb_build_array('Nuevo@Lejano.example'),
      'subject', 'Seguimiento', 'received_at', now() - interval '1 day'),
    jsonb_build_object('provider_message_id', 'out-3', 'direction', 'out',
      'from_address', 'taller@libreta.example',
      'to_addresses', jsonb_build_array('bodega@andina.example', 'avisos@bancochile.cl'),
      'subject', 'Pedido', 'received_at', now() - interval '2 days'),
    jsonb_build_object('provider_message_id', 'in-1', 'direction', 'in',
      'from_address', 'nuevo@lejano.example', 'from_name', 'Nuevo Contacto',
      'to_addresses', jsonb_build_array('taller@libreta.example'),
      'subject', 'Re: Cotización', 'received_at', now() - interval '2 days'),
    jsonb_build_object('provider_message_id', 'in-2', 'direction', 'in',
      'from_address', 'desconocido@lejano.example', 'from_name', 'Solo Escribe',
      'to_addresses', jsonb_build_array('taller@libreta.example'),
      'subject', 'Hola', 'received_at', now() - interval '2 days')
  ));
select public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'apagada@libreta.example'),
  jsonb_build_array(jsonb_build_object('provider_message_id', 'off-1', 'direction', 'out',
    'from_address', 'apagada@libreta.example',
    'to_addresses', jsonb_build_array('oculto@lejano.example'),
    'subject', 'Privado', 'received_at', now() - interval '1 hour')));
select public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where address = 'taller@vecino.example'),
  jsonb_build_array(jsonb_build_object('provider_message_id', 'vec-1', 'direction', 'out',
    'from_address', 'taller@vecino.example',
    'to_addresses', jsonb_build_array('ajeno@b.example'),
    'subject', 'Del vecino', 'received_at', now() - interval '1 hour')));
update public.mail_mailboxes set is_active = false where address = 'apagada@libreta.example';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"b8d10000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b8d10000-0000-4000-8000-000000000091', true);
select set_config('test.libreta', public.mail_recipient_directory_v1()::text, true);

select is(
  (select array_agg(e.value->>'address' order by e.ordinality)
     from jsonb_array_elements(current_setting('test.libreta')::jsonb) with ordinality e),
  array['nuevo@lejano.example', 'avisos@bancochile.cl', 'bodega@andina.example', 'uno@cliente.example',
        'pedro@frenos.example', 'rocio@andina.example', 'ventas@andina.example'],
  'one row per address: the most used first, then named contacts, suppliers and customers');
select is(
  (select e - 'last_used' from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'nuevo@lejano.example'),
  '{"address":"nuevo@lejano.example","name":"Nuevo Contacto","kind":"sent","uses":2}'::jsonb,
  'someone the shop wrote to twice keeps the name of their own reply');
select ok(
  (select (e->>'last_used')::timestamptz between now() - interval '25 hours' and now() - interval '23 hours'
     from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'nuevo@lejano.example'),
  'with the date of the last mail sent to them');
select is(
  (select e - 'last_used' from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'avisos@bancochile.cl'),
  '{"address":"avisos@bancochile.cl","org":"Banco de Chile","kind":"sent","uses":1}'::jsonb,
  'an address the mail already knows by its domain carries that organization');
select is(
  (select e - 'last_used' from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'bodega@andina.example'),
  '{"address":"bodega@andina.example","org":"Importadora Andina","logo":"https://example.invalid/andina.png","kind":"sent","uses":1}'::jsonb,
  'a new address at a supplier domain carries the supplier and its logo');
select is(
  (select e - 'last_used' from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'uno@cliente.example'),
  '{"address":"uno@cliente.example","name":"Cliente Uno","kind":"customer","uses":1}'::jsonb,
  'a customer copied once is still the customer and counts the copy');
select is(
  (select e from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'pedro@frenos.example'),
  '{"address":"pedro@frenos.example","name":"Pedro Soto","org":"Frenos Norte","kind":"supplier","uses":0}'::jsonb,
  'a supplier contact wins over a customer with the same address');
select is(
  (select e from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'rocio@andina.example'),
  '{"address":"rocio@andina.example","name":"Rocío Pérez","org":"Importadora Andina","logo":"https://example.invalid/andina.png","kind":"supplier","uses":0}'::jsonb,
  'the sales rep comes with the supplier and its logo');
select is(
  (select e from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
    where e->>'address' = 'ventas@andina.example'),
  '{"address":"ventas@andina.example","name":"Importadora Andina","logo":"https://example.invalid/andina.png","kind":"supplier","uses":0}'::jsonb,
  'the supplier mail is trimmed and lowercased under the supplier name');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
               where e->>'address' in ('contacto@ruedas.example', 'ana@frenos.example', 'dos@cliente.example')),
  'inactive suppliers, contacts and customers are left out');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
               where e->>'address' = 'desconocido@lejano.example'),
  'someone who only wrote to the shop is not offered');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
               where e->>'address' = 'oculto@lejano.example'),
  'what was sent from a mailbox that is off stays hidden');
select ok(
  not exists (select 1 from jsonb_array_elements(current_setting('test.libreta')::jsonb) e
               where e->>'address' like 'ajeno@%'),
  'nothing of another shop leaks in');

select set_config('request.jwt.claims', '{"sub":"b8d10000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b8d10000-0000-4000-8000-000000000092', true);
select is(
  (select array_agg(e->>'address' order by e->>'address')
     from jsonb_array_elements(public.mail_recipient_directory_v1()) e),
  array['ajeno@b.example', 'ajeno@cliente.example', 'ajeno@proveedor.example'],
  'the other shop reads only its own book');

select set_config('request.jwt.claims', '{"sub":"b8d10000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b8d10000-0000-4000-8000-000000000093', true);
select throws_ok($$select public.mail_recipient_directory_v1()$$,
  '42501', 'mail_forbidden', 'an account without a shop profile cannot read it');
reset role;

select ok(not has_function_privilege('anon', 'public.mail_recipient_directory_v1()', 'EXECUTE'),
  'anonymous callers cannot read it');
select ok(has_function_privilege('authenticated', 'public.mail_recipient_directory_v1()', 'EXECUTE'),
  'signed-in callers reach the staff check');
select is((select provolatile::text from pg_proc where oid = 'public.mail_recipient_directory_v1()'::regprocedure),
  's', 'it only reads');
select ok((select prosecdef and proconfig @> array['search_path=pg_catalog, public']
             from pg_proc where oid = 'public.mail_recipient_directory_v1()'::regprocedure),
  'definer with a fixed search path');

select * from finish();
rollback;
