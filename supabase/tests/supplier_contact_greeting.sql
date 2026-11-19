-- Cómo se saluda a un contacto de proveedor (20261119200000).
--
-- Primer nombre por defecto, dos nombres o un texto propio; el comando que
-- guarda el contacto lo acepta, y cuando no lo trae (una app sin esta versión,
-- «Hacer principal») conserva el que había. Datos inventados.
begin;
select no_plan();

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);

insert into public.tenants (id, shop_name) values
  ('c0a71119-0000-4000-8000-000000000001', 'Saludos Test');
insert into public.suppliers (id, tenant_id, name) values
  (
    'c0a71119-0001-4000-8000-000000000101',
    'c0a71119-0000-4000-8000-000000000001',
    'Distribuidora de Prueba'
  );

-- 1. Las columnas y su valor por defecto.
select has_column('public', 'supplier_contacts', 'greeting_style',
  'a contact stores how it is greeted');
select has_column('public', 'supplier_contacts', 'greeting_custom_name',
  'a contact stores its custom greeting');
select col_default_is('public', 'supplier_contacts', 'greeting_style',
  'first_name'::text, 'the first name is the default greeting');

-- 2. Un contacto nuevo sin saludo queda con el primer nombre.
create temporary table greeting_result (step text, payload jsonb);
insert into greeting_result
select 'new', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  null,
  null,
  'c0a71119-0120-4000-8000-000000000001',
  '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","is_primary":true}'::jsonb
);
select is(
  (select payload->'contact'->>'greeting_style' || '|' ||
          coalesce(payload->'contact'->>'greeting_custom_name', '∅')
     from greeting_result where step = 'new'),
  'first_name|∅',
  'a contact saved without a greeting is greeted by its first name'
);
select ok(
  (select (payload->'contact') ? 'greeting_custom_name'
     from greeting_result where step = 'new'),
  'the returned contact carries its greeting'
);

-- La huella de un pedido sin saludo es la de antes de esta versión: un
-- reintento de una app vieja reconoce su recibo.
select is(
  (select request_fingerprint
     from public.supplier_contact_command_receipts
    where operation_id = 'c0a71119-0120-4000-8000-000000000001'),
  md5(jsonb_build_object(
    'supplier_id', 'c0a71119-0001-4000-8000-000000000101'::uuid,
    'contact_id', null::uuid,
    'expected_updated_at', null::timestamptz,
    'contact', jsonb_build_object(
      'name', 'Ana Lucía Rivas', 'role', null::text,
      'phone', '+56 9 0000 0001', 'email', null::text, 'notes', null::text,
      'is_primary', true
    )
  )::text),
  'a request without greeting keeps the pre-greeting fingerprint'
);

-- 3. Elegir los dos nombres.
insert into greeting_result
select 'two', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000002',
  '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":"two_names"}'::jsonb
);
select is(
  (select greeting_style from public.supplier_contacts
    where supplier_id = 'c0a71119-0001-4000-8000-000000000101'),
  'two_names',
  'the form can choose the two given names'
);

-- 4. Guardar sin saludo —una app vieja, «Hacer principal»— no lo pierde.
insert into greeting_result
select 'keep', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000003',
  '{"name":"Ana Lucía Rivas","role":"Ventas","phone":"+56 9 0000 0001","is_primary":true}'::jsonb
);
select is(
  (select payload->'contact'->>'greeting_style' from greeting_result where step = 'keep'),
  'two_names',
  'a save without greeting keys keeps the chosen greeting'
);

-- 5. Un texto propio: se limpia y se guarda tal cual.
insert into greeting_result
select 'custom', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000004',
  jsonb_build_object(
    'name', 'Ana Lucía Rivas',
    'phone', '+56 9 0000 0001',
    'greeting_style', 'custom',
    'greeting_custom_name', E'  Señora\t  Anita  '
  )
);
select is(
  (select greeting_style || '|' || greeting_custom_name
     from public.supplier_contacts
    where supplier_id = 'c0a71119-0001-4000-8000-000000000101'),
  'custom|Señora Anita',
  'a custom greeting is trimmed to one line with single spaces'
);

-- Sin la clave del texto, el personalizado conserva el que había.
insert into greeting_result
select 'custom-keep', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000005',
  '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":"custom"}'::jsonb
);
select is(
  (select payload->'contact'->>'greeting_custom_name'
     from greeting_result where step = 'custom-keep'),
  'Señora Anita',
  'choosing custom again without the text keeps the saved text'
);

-- 6. Lo que no se acepta.
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    null, null,
    'c0a71119-0120-4000-8000-000000000006',
    '{"name":"Pedro Soto","greeting_style":"custom","greeting_custom_name":"   "}'::jsonb
  )$$,
  '22023',
  'A custom greeting needs the name to use',
  'a custom greeting without text is refused'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    null, null,
    'c0a71119-0120-4000-8000-000000000007',
    '{"name":"Pedro Soto","greeting_style":"nickname"}'::jsonb
  )$$,
  '22023',
  'Contact greeting_style must be first_name, two_names or custom',
  'an unknown greeting style is refused'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    null, null,
    'c0a71119-0120-4000-8000-000000000008',
    jsonb_build_object(
      'name', 'Pedro Soto',
      'greeting_style', 'custom',
      'greeting_custom_name', repeat('a', 61)
    )
  )$$,
  '22023',
  'Contact greeting name must be one short line',
  'a custom greeting longer than 60 characters is refused'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    null, null,
    'c0a71119-0120-4000-8000-000000000009',
    '{"name":"Pedro Soto","greeting_style":2}'::jsonb
  )$$,
  '22023',
  null,
  'a non-text greeting style is refused'
);
select throws_ok(
  $$update public.supplier_contacts
       set greeting_style = 'custom', greeting_custom_name = null
     where supplier_id = 'c0a71119-0001-4000-8000-000000000101'$$,
  '23514',
  null,
  'the table refuses a custom greeting without its text'
);
select throws_ok(
  $$update public.supplier_contacts
       set greeting_style = 'first_name', greeting_custom_name = 'Anita'
     where supplier_id = 'c0a71119-0001-4000-8000-000000000101'$$,
  '23514',
  null,
  'the table refuses a stray custom text under another greeting'
);

-- 7. Volver al primer nombre borra el texto propio; un null explícito
--    también vuelve al primer nombre.
insert into greeting_result
select 'back', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000010',
  '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":null,"greeting_custom_name":"Anita"}'::jsonb
);
select is(
  (select greeting_style || '|' || coalesce(greeting_custom_name, '∅')
     from public.supplier_contacts
    where supplier_id = 'c0a71119-0001-4000-8000-000000000101'),
  'first_name|∅',
  'an explicit null greeting goes back to the first name and drops the text'
);

-- 8. Un reintento con el mismo id devuelve su recibo; con otro saludo, no.
select is(
  public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
    null,
    'c0a71119-0120-4000-8000-000000000002',
    '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":"two_names"}'::jsonb
  )->>'idempotent_replay',
  'true',
  'a lost-ack greeting save replays its receipt'
);
select throws_ok(
  $$select public.save_supplier_contact(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
    null,
    'c0a71119-0120-4000-8000-000000000002',
    '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":"first_name"}'::jsonb
  )$$,
  '23505',
  'Contact operation id was reused with different content',
  'the same operation id with another greeting is refused'
);

-- 9. Desactivar y reactivar no toca el saludo.
insert into greeting_result
select 'two-again', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'new'),
  null,
  'c0a71119-0120-4000-8000-000000000011',
  '{"name":"Ana Lucía Rivas","phone":"+56 9 0000 0001","greeting_style":"two_names"}'::jsonb
);
insert into greeting_result
select 'second', public.save_supplier_contact(
  'c0a71119-0000-4000-8000-000000000001',
  'c0a71119-0001-4000-8000-000000000101',
  null,
  null,
  'c0a71119-0120-4000-8000-000000000012',
  '{"name":"Rocío del Mar Fuentes","phone":"+56 9 0000 0002","greeting_style":"two_names"}'::jsonb
);
select is(
  public.set_supplier_contact_status(
    'c0a71119-0000-4000-8000-000000000001',
    'c0a71119-0001-4000-8000-000000000101',
    (select (payload->'contact'->>'id')::uuid from greeting_result where step = 'second'),
    null,
    'c0a71119-0120-4000-8000-000000000013',
    false
  )->'contact'->>'greeting_style',
  'two_names',
  'deactivating a contact keeps its greeting'
);

select * from finish();
rollback;
