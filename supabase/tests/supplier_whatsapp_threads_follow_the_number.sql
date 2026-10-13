-- Un chat de WhatsApp de un proveedor sigue a su número (20261013190000).
-- Números y nombres inventados; todo se deshace al final.
begin;
select plan(25);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('5f710000-0000-4000-8000-000000000001', 'Hilos de proveedor');
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '5f710000-0000-4000-8000-000000000091',
  'authenticated', 'authenticated', 'hilos-staff@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '5f710000-0000-4000-8000-000000000001'),
  now(), now()
);
delete from public.user_profiles
 where user_id = '5f710000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values (
  '5f710000-0000-4000-8000-000000000091',
  '5f710000-0000-4000-8000-000000000001',
  'admin', '{}', true
);
insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active)
values (
  '5f710000-0000-4000-8000-000000000031',
  '5f710000-0000-4000-8000-000000000001',
  'hilos-proveedor-test', 'Sintético', true
);
insert into public.suppliers (id, tenant_id, name, phone) values
  ('5f710000-0000-4000-8000-000000000101', '5f710000-0000-4000-8000-000000000001', 'Proveedor Uno', null),
  ('5f710000-0000-4000-8000-000000000102', '5f710000-0000-4000-8000-000000000001', 'Proveedor Dos', '+56 2 2000 0002');
insert into public.customers (id, tenant_id, name, phone, is_active) values
  ('5f710000-0000-4000-8000-000000000201', '5f710000-0000-4000-8000-000000000001', 'Cliente Sintético', '+56 9 3000 0003', true);

-- Insertar el tenant deja su id en `request.jwt.claim.sub`; el webhook corre
-- como service_role sin usuario.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

create temporary table thread_ids (name text primary key, id uuid);

-- 1. Un número desconocido entra como chat de cliente, y la frontera sigue
--    cerrada para un cambio directo.
insert into thread_ids
select 'unknown', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.1', '56930000001', '56930000001',
  'Vendedor Nuevo', 'text', 'Hola, soy el vendedor nuevo', '{}'::jsonb
)->>'conversation_id')::uuid;
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'unknown')),
  'customer',
  'an unknown number lands in the customer inbox'
);
select throws_ok(
  format(
    $$update public.conversations set counterparty_type = 'supplier' where id = %L$$,
    (select id from thread_ids where name = 'unknown')
  ),
  '23514',
  'Conversation counterparty_type is immutable',
  'the counterparty boundary still rejects a direct change'
);

-- 2. Guardar ese número como contacto del proveedor mueve el chat entero.
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000101',
  null, null,
  '5f710000-0000-4000-8000-000000000501',
  '{"name":"Vendedor Nuevo","phone":"+56 9 3000 0001","is_primary":true}'::jsonb
);
select is(
  (select counterparty_type || '|' || context_type || '|' || context_id::text
     from public.conversations where id = (select id from thread_ids where name = 'unknown')),
  'supplier|supplier|5f710000-0000-4000-8000-000000000101',
  'saving the number on a supplier contact moves the chat to that supplier'
);
select is(
  (select contact.name
     from public.whatsapp_conversation_bindings binding
     join public.supplier_contacts contact on contact.id = binding.supplier_contact_id
    where binding.conversation_id = (select id from thread_ids where name = 'unknown')),
  'Vendedor Nuevo',
  'the thread is tied to the person'
);
select is(
  (select count(*)::int from public.messages where conversation_id = (select id from thread_ids where name = 'unknown')),
  1,
  'the moved chat keeps its messages'
);
select is(
  (select source from public.messaging_counterparty_moves
    where conversation_id = (select id from thread_ids where name = 'unknown')),
  'supplier_contact',
  'the move is recorded with its source'
);
select is(
  (public.ingest_whatsapp_inbound_message(
    'hilos-proveedor-test', 'wamid.hilos.2', '56930000001', '56930000001',
    'Vendedor Nuevo', 'text', 'Te mando la lista', '{}'::jsonb
  )->>'conversation_id')::uuid,
  (select id from thread_ids where name = 'unknown'),
  'the next message from that number lands in the same, now supplier, chat'
);

-- 3. Un número ya registrado abre su chat directo en Proveedores, sea de un
--    contacto o el teléfono de la ficha.
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000102',
  null, null,
  '5f710000-0000-4000-8000-000000000502',
  '{"name":"Vendedora Conocida","phone":"+56 9 3000 0002"}'::jsonb
);
insert into thread_ids
select 'known_contact', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.3', '56930000002', '56930000002',
  'Vendedora', 'text', 'Hola', '{}'::jsonb
)->>'conversation_id')::uuid;
select is(
  (select counterparty_type || '|' || context_id::text
     from public.conversations where id = (select id from thread_ids where name = 'known_contact')),
  'supplier|5f710000-0000-4000-8000-000000000102',
  'a known contact''s first message opens a supplier chat'
);
select isnt(
  (select supplier_contact_id from public.whatsapp_conversation_bindings
    where conversation_id = (select id from thread_ids where name = 'known_contact')),
  null,
  'and the thread is tied to that contact'
);
insert into thread_ids
select 'supplier_phone', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.4', '56220000002', '56220000002',
  null, 'text', 'Mesa central', '{}'::jsonb
)->>'conversation_id')::uuid;
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'supplier_phone')),
  'supplier',
  'the supplier''s own phone also routes to Proveedores'
);

-- 4. Un chat unido a un cliente no se mueve.
insert into thread_ids
select 'customer', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.5', '56930000003', '56930000003',
  'Cliente', 'text', 'Hola', '{}'::jsonb
)->>'conversation_id')::uuid;
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000101',
  null, null,
  '5f710000-0000-4000-8000-000000000503',
  '{"name":"También cliente","phone":"+56 9 3000 0003"}'::jsonb
);
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'customer')),
  'customer',
  'a chat bound to a customer stays a customer chat'
);
select is(
  (select count(*)::int from public.messaging_counterparty_moves
    where conversation_id = (select id from thread_ids where name = 'customer')),
  0,
  'and no move is recorded for it'
);

-- 4b. Tampoco el de un número que ya es de un cliente registrado después de
--     que empezó el chat: el vínculo no alcanzó a guardar al cliente, pero la
--     persona es cliente (20261013200000).
insert into thread_ids
select 'late_customer', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.7', '56930000005', '56930000005',
  'Cliente tardío', 'text', 'Hola', '{}'::jsonb
)->>'conversation_id')::uuid;
insert into public.customers (id, tenant_id, name, phone, is_active) values
  ('5f710000-0000-4000-8000-000000000202', '5f710000-0000-4000-8000-000000000001', 'Cliente Tardío', '+56 9 3000 0005', true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000101',
  null, null,
  '5f710000-0000-4000-8000-000000000506',
  '{"name":"Cliente y vendedor","phone":"+56 9 3000 0005"}'::jsonb
);
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'late_customer')),
  'customer',
  'a chat whose number belongs to a registered customer stays a customer chat'
);

-- 5. Un número de dos proveedores no es de ninguno.
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000101',
  null, null,
  '5f710000-0000-4000-8000-000000000504',
  '{"name":"Compartido A","phone":"+56 9 3000 0009"}'::jsonb
);
select public.save_supplier_contact(
  '5f710000-0000-4000-8000-000000000001',
  '5f710000-0000-4000-8000-000000000102',
  null, null,
  '5f710000-0000-4000-8000-000000000505',
  '{"name":"Compartido B","phone":"+56 9 3000 0009"}'::jsonb
);
select is(
  (select count(*)::int
     from public.whatsapp_number_supplier('5f710000-0000-4000-8000-000000000001', '56930000009')),
  0,
  'a number shared by two suppliers belongs to neither'
);

-- 6. Desde el chat: «Es de un proveedor».
insert into thread_ids
select 'command', (public.ingest_whatsapp_inbound_message(
  'hilos-proveedor-test', 'wamid.hilos.6', '56930000004', '56930000004',
  'Perfil WhatsApp', 'text', 'Buenas', '{}'::jsonb
)->>'conversation_id')::uuid;
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'command')),
  'customer',
  'an unknown number starts as a customer chat'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '5f710000-0000-4000-8000-000000000091', 'role', 'authenticated')::text,
  true
);
select set_config('request.jwt.claim.sub', '5f710000-0000-4000-8000-000000000091', true);

create temporary table command_result (payload jsonb);
insert into command_result
select public.assign_whatsapp_conversation_to_supplier(
  (select id from thread_ids where name = 'command'),
  '5f710000-0000-4000-8000-000000000101',
  '5f710000-0000-4000-8000-000000000601',
  '{"is_primary":true}'::jsonb
);
select is(
  (select (payload->>'moved')::boolean and (payload->>'contact_created')::boolean from command_result),
  true,
  'the chat command creates the contact and moves the chat'
);
select is(
  (select counterparty_type from public.conversations where id = (select id from thread_ids where name = 'command')),
  'supplier',
  'the chat is now in Proveedores'
);
select is(
  (select name || '|' || phone_digits || '|' || is_primary::text
     from public.supplier_contacts
    where id = (select (payload->>'supplier_contact_id')::uuid from command_result)),
  'Perfil WhatsApp|56930000004|true',
  'the contact takes the WhatsApp profile name and number, as primary when asked'
);
select is(
  (select source from public.messaging_counterparty_moves
    where conversation_id = (select id from thread_ids where name = 'command')),
  'chat_command',
  'the move records that it came from the chat'
);
select is(
  public.assign_whatsapp_conversation_to_supplier(
    (select id from thread_ids where name = 'command'),
    '5f710000-0000-4000-8000-000000000101',
    '5f710000-0000-4000-8000-000000000601',
    '{"is_primary":true}'::jsonb
  )->>'replay',
  'true',
  'repeating the command replays instead of failing'
);
select is(
  (select count(*)::int from public.supplier_contacts
    where supplier_id = '5f710000-0000-4000-8000-000000000101'
      and phone_digits = '56930000004'),
  1,
  'and leaves a single contact'
);
select throws_ok(
  format(
    $$select public.assign_whatsapp_conversation_to_supplier(%L, %L, %L, '{}'::jsonb)$$,
    (select id from thread_ids where name = 'customer'),
    '5f710000-0000-4000-8000-000000000101',
    '5f710000-0000-4000-8000-000000000602'
  ),
  '23514',
  'Este chat está unido a un cliente; no se puede pasar a Proveedores.',
  'the command refuses a chat bound to a customer'
);
select ok(
  not has_function_privilege('anon', 'public.assign_whatsapp_conversation_to_supplier(uuid,uuid,uuid,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.assign_whatsapp_conversation_to_supplier(uuid,uuid,uuid,jsonb)', 'execute'),
  'only signed-in staff can run the command'
);
select ok(
  not has_function_privilege('authenticated', 'public.move_whatsapp_conversation_to_supplier_internal(uuid,uuid,uuid,text)', 'execute')
  and not has_table_privilege('authenticated', 'public.messaging_counterparty_moves', 'select'),
  'the move itself and its log stay internal'
);
select is(
  (select count(*)::int from public.messaging_counterparty_moves
    where tenant_id = '5f710000-0000-4000-8000-000000000001'),
  2,
  'two moves in total: the contact save and the chat command'
);

select * from finish();
rollback;
