-- Contactos por proveedor (20260903103000).
--
-- Personas con una principal; desactivar conserva los hilos; `sales_rep_*`
-- es la proyección de la principal; cada hilo de WhatsApp queda atado a su
-- persona por número. Vive en su propio archivo por la misma razón que el
-- comando del vendedor: la batería de la fundación muere antes.
begin;
select no_plan();

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

insert into public.tenants (id, shop_name) values
  ('c0a70903-0000-4000-8000-000000000001', 'Contactos Test');
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'c0a70903-0000-4000-8000-000000000091',
  'authenticated', 'authenticated', 'contacts-staff@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', 'c0a70903-0000-4000-8000-000000000001'),
  now(), now()
);
insert into public.suppliers (id, tenant_id, name, phone) values
  (
    'c0a70903-0001-4000-8000-000000000101',
    'c0a70903-0000-4000-8000-000000000001',
    'Comercial Ciclo (prueba)',
    '+56934867574'
  );

-- 1. Superficie: tabla con RLS, lectura para authenticated, escritura sólo
--    por comandos; recibos privados.
select has_table('public', 'supplier_contacts', 'supplier contacts exist');
select ok(
  has_table_privilege('authenticated', 'public.supplier_contacts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.supplier_contacts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.supplier_contacts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.supplier_contacts', 'DELETE')
  and not has_table_privilege('authenticated', 'public.supplier_contact_command_receipts', 'SELECT'),
  'authenticated reads contacts, writes only through the commands, never sees receipts'
);
select has_column(
  'public', 'whatsapp_conversation_bindings', 'supplier_contact_id',
  'a WhatsApp thread can point at its supplier contact'
);

-- 2. Crear la principal proyecta al vendedor de la ficha.
create temporary table contact_result (payload jsonb);
insert into contact_result
select public.save_supplier_contact(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  null,
  null,
  'c0a70903-0120-4000-8000-000000000001',
  '{"name":" Víctor ","role":"Vendedor","phone":"+56 9 3486 7574","email":null,"is_primary":true}'::jsonb
);
select is(
  (select payload->'contact'->>'name' from contact_result),
  'Víctor',
  'save_supplier_contact trims and returns the saved person'
);
select is(
  (
    select sales_rep_name || '|' || sales_rep_phone || '|' || coalesce(sales_rep_email, '')
    from public.suppliers
    where id = 'c0a70903-0001-4000-8000-000000000101'
  ),
  'Víctor|+56 9 3486 7574|',
  'the primary contact is projected into suppliers.sales_rep_*'
);
select is(
  public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    null,
    null,
    'c0a70903-0120-4000-8000-000000000001',
    '{"name":" Víctor ","role":"Vendedor","phone":"+56 9 3486 7574","email":null,"is_primary":true}'::jsonb
  )->>'idempotent_replay',
  'true',
  'a lost-ack contact save replays its receipt instead of creating a twin'
);
select is(
  (select count(*)::int from public.supplier_contacts
   where supplier_id = 'c0a70903-0001-4000-8000-000000000101'),
  1,
  'the replay created no second contact'
);

-- 3. Una segunda persona, no principal; el mismo número dos veces se rechaza.
insert into contact_result
select public.save_supplier_contact(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  null,
  null,
  'c0a70903-0120-4000-8000-000000000002',
  '{"name":"Fabiola Morales","phone":"+56988155152"}'::jsonb
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    null,
    null,
    'c0a70903-0120-4000-8000-000000000003',
    '{"name":"Otra","phone":"+56 9 8815 5152"}'::jsonb
  )$$,
  '23505',
  'Another contact of this supplier already has that phone',
  'two contacts of one supplier cannot share a number'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    null,
    null,
    'c0a70903-0120-4000-8000-000000000004',
    '{"name":"Sin número","phone":"12345"}'::jsonb
  )$$,
  '22023',
  'Contact phone must have at least 8 digits',
  'a phone that cannot receive a message is rejected'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    null,
    null,
    'c0a70903-0120-4000-8000-000000000005',
    '{"name":"X","password":"no"}'::jsonb
  )$$,
  '22023',
  'Contact must not contain sensitive keys',
  'the command never accepts a secret as a contact field'
);
select is(
  (select sales_rep_name from public.suppliers
   where id = 'c0a70903-0001-4000-8000-000000000101'),
  'Víctor',
  'adding a non-primary person leaves the projection alone'
);

-- 4. Un hilo de WhatsApp con el número de Fabiola queda atado a ella al
--    nacer; uno con un número desconocido queda sin persona hasta que la
--    persona exista.
insert into public.whatsapp_channels (
  id, tenant_id, phone_number_id, display_name, is_active
) values (
  'c0a70903-0600-4000-8000-000000000601',
  'c0a70903-0000-4000-8000-000000000001',
  'contacts-pgtap-phone-number-id', 'Contactos pgTAP', true
);
insert into public.conversations (
  id, tenant_id, type, channel, title, context_type, context_id, status,
  counterparty_type, created_by
) values
  (
    'c0a70903-0300-4000-8000-000000000301',
    'c0a70903-0000-4000-8000-000000000001',
    'support', 'whatsapp', 'Comercial Ciclo (prueba)', 'supplier',
    'c0a70903-0001-4000-8000-000000000101', 'active', 'supplier',
    'c0a70903-0000-4000-8000-000000000091'
  ),
  (
    'c0a70903-0300-4000-8000-000000000302',
    'c0a70903-0000-4000-8000-000000000001',
    'support', 'whatsapp', 'Comercial Ciclo (prueba)', 'supplier',
    'c0a70903-0001-4000-8000-000000000101', 'active', 'supplier',
    'c0a70903-0000-4000-8000-000000000091'
  ),
  (
    'c0a70903-0300-4000-8000-000000000303',
    'c0a70903-0000-4000-8000-000000000001',
    'support', 'whatsapp', 'Sin contexto', null, null, 'active', 'supplier',
    'c0a70903-0000-4000-8000-000000000091'
  );
insert into public.whatsapp_conversation_bindings (
  id, tenant_id, conversation_id, channel_id, external_wa_id,
  external_phone_number, contact_name
) values
  (
    'c0a70903-0620-4000-8000-000000000621',
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0300-4000-8000-000000000301',
    'c0a70903-0600-4000-8000-000000000601',
    '56988155152', '56988155152', 'Fabiola'
  ),
  (
    'c0a70903-0620-4000-8000-000000000622',
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0300-4000-8000-000000000302',
    'c0a70903-0600-4000-8000-000000000601',
    '56911112222', '56911112222', 'Comercial Ciclo (prueba)'
  ),
  (
    'c0a70903-0620-4000-8000-000000000623',
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0300-4000-8000-000000000303',
    'c0a70903-0600-4000-8000-000000000601',
    '56933334444', '56933334444', 'Macarena'
  );
select is(
  (select contact.name
   from public.whatsapp_conversation_bindings binding
   join public.supplier_contacts contact on contact.id = binding.supplier_contact_id
   where binding.id = 'c0a70903-0620-4000-8000-000000000621'),
  'Fabiola Morales',
  'a new supplier thread is linked to the contact with that number'
);
select is(
  (select supplier_contact_id from public.whatsapp_conversation_bindings
   where id = 'c0a70903-0620-4000-8000-000000000622'),
  null,
  'a thread from an unknown number waits for its person'
);
select ok(
  public.phone_digits_match('569322882127', '+56 32 288 2127')
  and public.phone_digits_match('56934867574', '9 3486 7574')
  and not public.phone_digits_match('56934867574', '56934867575')
  and not public.phone_digits_match('', '56934867574'),
  'numbers match by identical digits or by the same last nine digits'
);

-- 5. Agregar la persona con ese número adopta el hilo; vincular después una
--    conversación al proveedor también lo adopta.
insert into contact_result
select public.save_supplier_contact(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  null,
  null,
  'c0a70903-0120-4000-8000-000000000006',
  '{"name":"Isabel","phone":"+56 9 1111 2222"}'::jsonb
);
select is(
  (select contact.name
   from public.whatsapp_conversation_bindings binding
   join public.supplier_contacts contact on contact.id = binding.supplier_contact_id
   where binding.id = 'c0a70903-0620-4000-8000-000000000622'),
  'Isabel',
  'creating the person with that number adopts the waiting thread'
);
insert into contact_result
select public.save_supplier_contact(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  null,
  null,
  'c0a70903-0120-4000-8000-000000000007',
  '{"name":"Macarena","phone":"+56 9 3333 4444"}'::jsonb
);
update public.conversations
set context_type = 'supplier',
    context_id = 'c0a70903-0001-4000-8000-000000000101'
where id = 'c0a70903-0300-4000-8000-000000000303';
select is(
  (select contact.name
   from public.whatsapp_conversation_bindings binding
   join public.supplier_contacts contact on contact.id = binding.supplier_contact_id
   where binding.id = 'c0a70903-0620-4000-8000-000000000623'),
  'Macarena',
  'linking a conversation to the supplier resolves its thread person'
);

-- 6. Desactivar conserva el hilo y baja la principal; el vendedor de la
--    ficha queda vacío hasta que alguien sea principal otra vez.
create temporary table primary_before as
select id, updated_at
from public.supplier_contacts
where supplier_id = 'c0a70903-0001-4000-8000-000000000101' and is_primary;
insert into contact_result
select public.set_supplier_contact_status(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  (select id from primary_before),
  (select updated_at from primary_before),
  'c0a70903-0120-4000-8000-000000000008',
  false
);
select ok(
  (select not is_active and not is_primary and deactivated_at is not null
   from public.supplier_contacts where id = (select id from primary_before)),
  'deactivating keeps the person, drops primary and stamps when'
);
select is(
  (select sales_rep_phone from public.suppliers
   where id = 'c0a70903-0001-4000-8000-000000000101'),
  null,
  'without an active primary the projection is empty'
);
select is(
  (select count(*)::int from public.whatsapp_conversation_bindings
   where supplier_contact_id is not null
     and tenant_id = 'c0a70903-0000-4000-8000-000000000001'),
  3,
  'deactivating a person touches none of the threads'
);
select throws_ok(
  $$select public.set_supplier_contact_status(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    (select id from primary_before),
    (select updated_at from primary_before),
    'c0a70903-0120-4000-8000-000000000009',
    true
  )$$,
  '40001',
  'Supplier contact changed concurrently',
  'a stale expected updated_at is rejected'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    (select id from primary_before),
    (select updated_at from public.supplier_contacts where id = (select id from primary_before)),
    'c0a70903-0120-4000-8000-000000000010',
    '{"name":"Víctor","is_primary":true}'::jsonb
  )$$,
  '22023',
  'An inactive contact cannot be the primary contact',
  'an inactive person cannot be made the WhatsApp target'
);

-- 7. Promover a Fabiola: la proyección la sigue.
insert into contact_result
select public.save_supplier_contact(
  'c0a70903-0000-4000-8000-000000000001',
  'c0a70903-0001-4000-8000-000000000101',
  (select id from public.supplier_contacts where name = 'Fabiola Morales'),
  (select updated_at from public.supplier_contacts where name = 'Fabiola Morales'),
  'c0a70903-0120-4000-8000-000000000011',
  '{"name":"Fabiola Morales","role":"Ventas","phone":"+56988155152","is_primary":true}'::jsonb
);
select is(
  (select sales_rep_name || '|' || sales_rep_phone from public.suppliers
   where id = 'c0a70903-0001-4000-8000-000000000101'),
  'Fabiola Morales|+56988155152',
  'promoting a person makes her the projected vendor'
);

-- 8. El comando del vendedor sigue vivo y escribe a través de los contactos.
create temporary table supplier_before as
select updated_at from public.suppliers
where id = 'c0a70903-0001-4000-8000-000000000101';
select is(
  public.update_supplier_sales_rep(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    (select updated_at from supplier_before),
    'c0a70903-0130-4000-8000-000000000001',
    '{"name":"Fabiola M.","phone":"+56988155152","email":"fabiola@ciclo.cl"}'::jsonb
  )->'sales_rep',
  '{"name":"Fabiola M.","phone":"+56988155152","email":"fabiola@ciclo.cl"}'::jsonb,
  'the legacy vendor command edits the primary contact'
);
select is(
  (select count(*)::int from public.supplier_contacts
   where supplier_id = 'c0a70903-0001-4000-8000-000000000101'),
  4,
  'editing the vendor through the legacy command creates no extra person'
);
select is(
  public.update_supplier_sales_rep(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000101',
    (select updated_at from public.suppliers
      where id = 'c0a70903-0001-4000-8000-000000000101'),
    'c0a70903-0130-4000-8000-000000000002',
    '{"name":null,"phone":null,"email":null}'::jsonb
  )->'sales_rep',
  '{"name":null,"phone":null,"email":null}'::jsonb,
  'clearing the vendor through the legacy command deactivates the primary, never deletes'
);
select is(
  (select count(*)::int from public.supplier_contacts
   where supplier_id = 'c0a70903-0001-4000-8000-000000000101' and not is_active),
  2,
  'both former primaries are still there, inactive'
);

-- 9. Un proveedor de otro tenant no existe para el comando.
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a70903-0000-4000-8000-000000000001',
    'c0a70903-0001-4000-8000-000000000999',
    null,
    null,
    'c0a70903-0120-4000-8000-000000000012',
    '{"name":"X"}'::jsonb
  )$$,
  'P0002',
  'Supplier not found in tenant',
  'a supplier outside the tenant is not found, never written'
);

select * from finish();
rollback;
