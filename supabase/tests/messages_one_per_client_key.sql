-- Un mensaje por llave del cliente (20261008010000).
--
-- Un envío reintentado con la misma `metadata.client_message_id` no deja dos
-- filas de la misma persona en la misma conversación; otra persona, otra
-- conversación o un mensaje sin llave siguen libres.
begin;
select no_plan();

insert into public.tenants (id, shop_name) values
  ('c11e0000-0000-4000-8000-000000000001', 'Llave del cliente (prueba)');
insert into auth.users (id, email) values
  ('c11e0000-0000-4000-8000-0000000000a1', 'llave-uno@example.test'),
  ('c11e0000-0000-4000-8000-0000000000a2', 'llave-dos@example.test');
insert into public.conversations
  (id, tenant_id, created_by, type, counterparty_type, channel, status) values
  ('c11e0000-0000-4000-8000-0000000000c1',
   'c11e0000-0000-4000-8000-000000000001',
   'c11e0000-0000-4000-8000-0000000000a1',
   'support', 'customer', 'website_portal', 'active'),
  ('c11e0000-0000-4000-8000-0000000000c2',
   'c11e0000-0000-4000-8000-000000000001',
   'c11e0000-0000-4000-8000-0000000000a1',
   'support', 'customer', 'website_portal', 'active');

select has_index(
  'public', 'messages', 'messages_one_per_client_key',
  'messages carry one row per client key'
);

insert into public.messages
  (tenant_id, conversation_id, sender_id, content, type, metadata) values
  ('c11e0000-0000-4000-8000-000000000001',
   'c11e0000-0000-4000-8000-0000000000c1',
   'c11e0000-0000-4000-8000-0000000000a1',
   'Hola', 'text', '{"client_message_id":"web-llave-0001"}');

select throws_ok(
  $$insert into public.messages
      (tenant_id, conversation_id, sender_id, content, type, metadata) values
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Hola', 'text', '{"client_message_id":"web-llave-0001"}')$$,
  '23505',
  null,
  'the same send retried by the same person in the same conversation is refused'
);

select lives_ok(
  $$insert into public.messages
      (tenant_id, conversation_id, sender_id, content, type, metadata) values
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a2',
       'Hola', 'text', '{"client_message_id":"web-llave-0001"}'),
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c2',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Hola', 'text', '{"client_message_id":"web-llave-0001"}')$$,
  'another person, or another conversation, may use the same key'
);

select lives_ok(
  $$insert into public.messages
      (tenant_id, conversation_id, sender_id, content, type, metadata) values
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Otra vez', 'text', '{}'),
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Otra vez', 'text', '{}'),
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Nula', 'text', '{"client_message_id":null}'),
      ('c11e0000-0000-4000-8000-000000000001',
       'c11e0000-0000-4000-8000-0000000000c1',
       'c11e0000-0000-4000-8000-0000000000a1',
       'Nula', 'text', '{"client_message_id":null}')$$,
  'messages without a key, or with a null key, are not constrained'
);

select is(
  (select count(*)::int from public.messages
    where tenant_id = 'c11e0000-0000-4000-8000-000000000001'
      and metadata ->> 'client_message_id' = 'web-llave-0001'),
  3,
  'one row per person and conversation for the retried key'
);

select * from finish();
rollback;
