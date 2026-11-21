-- Cómo se saluda a un cliente (20261121200000).
--
-- La regla de la base es la misma de `contactGreetingName` (los mismos casos
-- que test/unit/contact_greeting_test.dart), el taller la elige en la ficha y
-- el cliente en «Mi cuenta», sólo para su propia ficha. Datos inventados.
begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- La regla
-- ---------------------------------------------------------------------------

select is(public.contact_greeting_name_internal('Ana Lucía Rivas', 'first_name', null), 'Ana',
  'the first name is the first word');
select is(public.contact_greeting_name_internal('  Pedro   Soto ', 'first_name', null), 'Pedro',
  'spaces do not matter');
select is(public.contact_greeting_name_internal('Ana Lucía Rivas', 'two_names', null), 'Ana Lucía',
  'two names');
select is(public.contact_greeting_name_internal('Rocío del Mar Fuentes', 'two_names', null), 'Rocío del Mar',
  'two names keep a «del» between them');
select is(public.contact_greeting_name_internal('Inés de los Ángeles Mora', 'two_names', null),
  'Inés de los Ángeles', 'and «de los»');
select is(public.contact_greeting_name_internal('Tomás De La Cruz Vera', 'two_names', null),
  'Tomás De La Cruz', 'mixed case stays as written');
select is(public.contact_greeting_name_internal('Rosa Delia Paz', 'two_names', null), 'Rosa Delia',
  '«Delia» is a name, not «del»');
select is(public.contact_greeting_name_internal('Inés de los Ángeles Mora', 'second_name', null),
  'Ángeles', 'the second name skips the particles');
select is(public.contact_greeting_name_internal('Ana Lucía Rivas', 'second_name', null), 'Lucía',
  'the second name alone');
select is(public.contact_greeting_name_internal('Yuri', 'second_name', null), 'Yuri',
  'one word is the same with any option');
select is(public.contact_greeting_name_internal('Yuri', 'two_names', null), 'Yuri',
  'also with two names');
select is(public.contact_greeting_name_internal('ana lucía rivas', 'full_name', null), 'Ana Lucía Rivas',
  'the full name, written as a greeting');
select is(public.contact_greeting_name_internal('ANA DE LA FUENTE', 'full_name', null), 'Ana de la Fuente',
  'capitals become a name and «de la» goes in lower case');
select is(public.contact_greeting_name_internal('JOSÉ ÑANCO', 'first_name', null), 'José',
  'accents and ñ survive the case change');
select is(public.contact_greeting_name_internal('McDonald Pérez', 'first_name', null), 'McDonald',
  'a mixed-case name stays as written');
select is(public.contact_greeting_name_internal('Ana Lucía Rivas', 'custom', '  Anita  ' || chr(10)), 'Anita',
  'a custom greeting goes as typed, in one line');
select is(public.contact_greeting_name_internal('Pedro Soto', 'custom', 'don PEDRO'), 'don PEDRO',
  'a custom greeting keeps its case');
select is(public.contact_greeting_name_internal('Pedro Soto', 'custom', '  '), 'Pedro',
  'an empty custom greeting falls back to the first name');
select is(public.contact_greeting_name_internal('   ', 'first_name', null), null,
  'no name, no greeting');
select is(public.contact_greeting_name_internal('Pedro Soto', 'apodo', null), 'Pedro',
  'an unknown style is the first name');

-- ---------------------------------------------------------------------------
-- La ficha
-- ---------------------------------------------------------------------------

update public.whatsapp_outbox_runtime set enabled = false;
insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('c5a71121-0000-4000-8000-000000000001', 'Saludos A', 'saludos-a@example.invalid', 'America/Santiago', true),
  ('c5a71121-0000-4000-8000-000000000002', 'Saludos B', 'saludos-b@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  -- La cuenta de Ana en la tienda A.
  ('c5a71121-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'ana-saludo@example.invalid', '', now(), '{}', '{}', now(), now()),
  -- Una cuenta sin ficha.
  ('c5a71121-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'nadie-saludo@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id in (
  'c5a71121-0000-4000-8000-000000000091', 'c5a71121-0000-4000-8000-000000000092');

insert into public.customers (id, tenant_id, name, email, auth_user_id, is_active) values
  ('c5a71121-0000-4000-8000-000000000011', 'c5a71121-0000-4000-8000-000000000001',
   'Ana Lucía Rivas', 'ana-saludo@example.invalid', 'c5a71121-0000-4000-8000-000000000091', true),
  ('c5a71121-0000-4000-8000-000000000012', 'c5a71121-0000-4000-8000-000000000002',
   'Ana Lucía Rivas', null, null, true);

select col_default_is('public', 'customers', 'greeting_style', 'first_name'::text,
  'a new customer is greeted by the first name');
insert into public.customers (id, tenant_id, name, is_active) values
  ('c5a71121-0000-4000-8000-000000000013', 'c5a71121-0000-4000-8000-000000000001',
   'MARÍA JOSÉ Lara', true),
  ('c5a71121-0000-4000-8000-000000000014', 'c5a71121-0000-4000-8000-000000000001',
   'Pedro Andrés Soto Pérez', true);
insert into public.customers (id, tenant_id, name, greeting_style, is_active) values
  ('c5a71121-0000-4000-8000-000000000015', 'c5a71121-0000-4000-8000-000000000001',
   'Juan Pablo Vera', 'second_name', true);
select is((select public.customer_greeting_internal(customer) from public.customers customer
    where customer.id = 'c5a71121-0000-4000-8000-000000000013'), 'María José',
  'a new «María José» starts with both names, as the notices always greeted her');
select is((select public.customer_greeting_internal(customer) from public.customers customer
    where customer.id = 'c5a71121-0000-4000-8000-000000000014'), 'Pedro',
  'four words are no longer read as two given names');
select is((select greeting_style from public.customers
    where id = 'c5a71121-0000-4000-8000-000000000015'), 'second_name',
  'a choice made when creating the record is kept');
select is((select public.greeting_name(customer) from public.customers customer
    where customer.id = 'c5a71121-0000-4000-8000-000000000011'), 'Ana',
  'greeting_name reads the record''s choice');
select throws_ok(
  $$update public.customers set greeting_style = 'apodo' where id = 'c5a71121-0000-4000-8000-000000000012'$$,
  '23514', null, 'an unknown style is refused');
select throws_ok(
  $$update public.customers set greeting_style = 'custom' where id = 'c5a71121-0000-4000-8000-000000000012'$$,
  '23514', null, 'a custom greeting needs its text');
select throws_ok(
  $$update public.customers set greeting_custom_name = 'Anita' where id = 'c5a71121-0000-4000-8000-000000000012'$$,
  '23514', null, 'a text without the custom style is refused');
select throws_ok(
  $$update public.customers set greeting_style = 'custom', greeting_custom_name = 'Ani' || chr(10) || 'ta'
     where id = 'c5a71121-0000-4000-8000-000000000012'$$,
  '23514', null, 'a custom greeting is one line');
select lives_ok(
  $$update public.customers set greeting_style = 'two_names' where id = 'c5a71121-0000-4000-8000-000000000012'$$,
  'the shop chooses two names');
select is((select public.customer_greeting_internal(customer) from public.customers customer
    where customer.id = 'c5a71121-0000-4000-8000-000000000012'), 'Ana Lucía',
  'and the record greets with them');
select is(public.customer_greeting_for_internal(
    'c5a71121-0000-4000-8000-000000000002', 'c5a71121-0000-4000-8000-000000000012', 'Otra Persona'),
  'Ana Lucía', 'an order or a quote of a record greets as the record chose');
select is(public.customer_greeting_for_internal(
    'c5a71121-0000-4000-8000-000000000001', 'c5a71121-0000-4000-8000-000000000012', 'Otra Persona'),
  'Otra', 'a record of another shop is not read: the written name''s first word');
select is(public.customer_greeting_for_internal(
    'c5a71121-0000-4000-8000-000000000001', null, 'maría josé lara'),
  'María', 'without a record, the first word of the written name');

-- ---------------------------------------------------------------------------
-- «Mi cuenta»
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c5a71121-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c5a71121-0000-4000-8000-000000000091', true);
select is(public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'second_name', null),
  jsonb_build_object('status', 'linked', 'name', 'Ana Lucía Rivas', 'greeting_style', 'second_name',
    'greeting_custom_name', null, 'greeting', 'Lucía'),
  'Ana chooses her second name');
select is(public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'custom', '  Anita   R. ')
    ->> 'greeting', 'Anita R.', 'or a name of her own, in one line');
select is(public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'first_name', 'Anita')
    ->> 'greeting_custom_name', null, 'a text without the custom style is dropped');
select throws_ok(
  $$select public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'custom', '   ')$$,
  '22023', 'customer_greeting_custom_invalid', 'a custom greeting needs its text');
select throws_ok(
  $$select public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'custom', repeat('a', 61))$$,
  '22023', 'customer_greeting_custom_invalid', 'and at most 60 letters');
select throws_ok(
  $$select public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'apodo', null)$$,
  '22023', 'customer_greeting_invalid', 'an unknown style is refused');
select throws_ok(
  $$select public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000002', 'two_names', null)$$,
  '42501', 'customer_greeting_not_linked', 'another shop has no record of Ana');
-- Su ficha también la puede cambiar directo (la guardia la deja), con las
-- mismas reglas de la tabla; el correo sigue siendo del taller.
select lives_ok(
  $$update public.customers set greeting_style = 'two_names', greeting_custom_name = null
     where id = 'c5a71121-0000-4000-8000-000000000011'$$,
  'her own record accepts her greeting');
select throws_ok(
  $$update public.customers set email = 'otro@example.invalid'
     where id = 'c5a71121-0000-4000-8000-000000000011'$$,
  '42501', 'Customer self-service may update profile fields only',
  'but not the fields the shop keeps');
select is((select customer.greeting_name from public.customers customer
    where customer.id = 'c5a71121-0000-4000-8000-000000000011'), 'Ana Lucía',
  'the store header reads greeting_name as a column');
select set_config('request.jwt.claims', '{"sub":"c5a71121-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c5a71121-0000-4000-8000-000000000092', true);
select throws_ok(
  $$select public.set_my_customer_greeting_v1('c5a71121-0000-4000-8000-000000000001', 'two_names', null)$$,
  '42501', 'customer_greeting_not_linked', 'an account without a record chooses for nobody');
reset role;

select is((select greeting_style || '|' || coalesce(greeting_custom_name, '∅')
     from public.customers where id = 'c5a71121-0000-4000-8000-000000000012'),
  'two_names|∅', 'the other shop''s record did not change');
select ok(not has_function_privilege('anon', 'public.set_my_customer_greeting_v1(uuid,text,text)', 'execute'),
  'a visitor without an account cannot call it');

-- ---------------------------------------------------------------------------
-- Lo que sale del servidor
-- ---------------------------------------------------------------------------

select ok(pg_get_functiondef('public.workshop_notice_dispatch_whatsapp_internal'::regproc)
    like '%customer_greeting_internal(v_customer)%greeting_name_source%',
  'the workshop notices greet with the record''s choice and say so to whatsapp-send');
select ok(pg_get_functiondef('public.process_whatsapp_review_requests_v1'::regproc)
    like '%customer_greeting_style%greeting_name_source%',
  'the review request too');
select ok(pg_get_functiondef('public.workshop_notice_email_payload_internal'::regproc)
    like '%customerGreeting%', 'the notice e-mails carry the greeting');
select ok(pg_get_functiondef('public.customer_quote_email_payload_internal'::regproc)
    like '%customerGreeting%', 'the quote e-mails too');
select ok(pg_get_functiondef('public.transactional_email_render_payload'::regproc)
    like '%''greeting'', public.customer_greeting_for_internal%', 'and the order e-mails');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and p.proname <> 'customer_first_name_internal'
      and p.prosrc like '%customer_first_name_internal%'), 0,
  'nothing greets by the first word alone any more');

select * from finish();
rollback;
