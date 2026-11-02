begin;

select plan(37);

-- Cotizar pide una cuenta y el cliente elige sus avisos (20261102175500): los
-- datos de contacto salen de la cuenta y la siguen, cada mensaje sale sólo
-- por lo elegido, el cliente cambia sus avisos con su enlace y «Mi cuenta»
-- lista y abre sus cotizaciones.

insert into public.tenants (id, shop_name) values
  ('c0ab0000-0000-4000-8000-000000000001', 'Taller cuentas A');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0ab0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'cuentas-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0ab0000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'ana@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0ab0000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'beto@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0ab0000-0000-4000-8000-000000000094', 'authenticated', 'authenticated',
   'carla@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0ab0000-0000-4000-8000-000000000095', 'authenticated', 'authenticated',
   'dora@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('c0ab0000-0000-4000-8000-000000000091', 'c0ab0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0ab0000-0000-4000-8000-0000000000c1', 'c0ab0000-0000-4000-8000-000000000001',
   'c0ab0000-0000-4000-8000-000000000092', 'Ana', 'ana@example.invalid', '+56922223333', true),
  ('c0ab0000-0000-4000-8000-0000000000c2', 'c0ab0000-0000-4000-8000-000000000001',
   'c0ab0000-0000-4000-8000-000000000093', 'Beto', 'beto@example.invalid', '+56911112222', true),
  ('c0ab0000-0000-4000-8000-0000000000c3', 'c0ab0000-0000-4000-8000-000000000001',
   'c0ab0000-0000-4000-8000-000000000094', 'Carla', 'carla@example.invalid', '+56933334444', true),
  ('c0ab0000-0000-4000-8000-0000000000c4', 'c0ab0000-0000-4000-8000-000000000001',
   'c0ab0000-0000-4000-8000-000000000095', 'Dora', 'dora@example.invalid', null, false);

insert into public.products (
  id, tenant_id, name, sku, price, tax_rate, product_type, is_service, is_active,
  is_published, show_on_website
) values (
  'c0ab0000-0000-4000-8000-000000000011', 'c0ab0000-0000-4000-8000-000000000001',
  'Neumático 29 x 2.25', 'ACC-1', 30000, 19, 'product', false, true, true, true
);
update public.products set inventory_qty = 9, stock_quantity = 9
 where id = 'c0ab0000-0000-4000-8000-000000000011';

-- ---------------------------------------------------------------------------
-- Cada cliente pide desde su cuenta
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('acc.a', public.request_public_customer_quote_v1(
  'c0ab0000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"4c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,
    "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
reset role;

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000093', true);
set local role authenticated;
select set_config('acc.b', public.request_public_customer_quote_v1(
  'c0ab0000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"4c1c2a3b-4d5e-4f60-8a71-000000000002","notify_email":true,"notify_whatsapp":true,
    "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":2}]}')::text, true);
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0ab0000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"4c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,
        "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '42501', 'Quote request belongs to another customer',
  'another account repeating a request key gets no link to that quote');
reset role;

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000094', true);
set local role authenticated;
select set_config('acc.c', public.request_public_customer_quote_v1(
  'c0ab0000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"4c1c2a3b-4d5e-4f60-8a71-000000000003","notify_whatsapp":true,
    "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
reset role;

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000095","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000095', true);
set local role authenticated;
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0ab0000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"4c1c2a3b-4d5e-4f60-8a71-000000000004","notify_email":true,
        "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '42501', 'quote_account_required', 'an inactive account cannot ask for a quote');
reset role;

select set_config('acc.qa', current_setting('acc.a')::jsonb ->> 'quote_id', true);
select set_config('acc.qb', current_setting('acc.b')::jsonb ->> 'quote_id', true);
select set_config('acc.qc', current_setting('acc.c')::jsonb ->> 'quote_id', true);

select is(
  (select string_agg(customer_name || ':' || notify_email || ':' || notify_whatsapp || ':' || preferred_channel,
                     ',' order by customer_name)
     from public.customer_quotes where tenant_id = 'c0ab0000-0000-4000-8000-000000000001'),
  'Ana:true:false:email,Beto:true:true:whatsapp,Carla:false:true:whatsapp',
  'each quote keeps what its customer chose; the main channel is computed');
select is(
  (select string_agg(q.customer_name || ':' || m.kind || ':' || m.channel, ',' order by q.customer_name, m.channel)
     from public.customer_quote_messages m
     join public.customer_quotes q on q.id = m.quote_id
    where q.tenant_id = 'c0ab0000-0000-4000-8000-000000000001'),
  'Ana:received:email,Beto:received:email',
  '«Recibimos» goes by email only to who asked for email');

-- El equipo envía las tres ofertas (todo está en stock).
select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('acc.tmp', public.customer_quote_send_offer_v1(
  'c0ab0000-0000-4000-8000-000000000001', current_setting('acc.qa')::uuid,
  '4d1c2a3b-4d5e-4f60-8a71-000000000001')::text, true);
select set_config('acc.tmp', public.customer_quote_send_offer_v1(
  'c0ab0000-0000-4000-8000-000000000001', current_setting('acc.qb')::uuid,
  '4d1c2a3b-4d5e-4f60-8a71-000000000002')::text, true);
select set_config('acc.tmp', public.customer_quote_send_offer_v1(
  'c0ab0000-0000-4000-8000-000000000001', current_setting('acc.qc')::uuid,
  '4d1c2a3b-4d5e-4f60-8a71-000000000003')::text, true);
reset role;

select is(
  (select string_agg(q.customer_name || ':' || m.channel || ':' || m.state || ':' || m.recipient, ','
                     order by q.customer_name, m.channel)
     from public.customer_quote_messages m
     join public.customer_quotes q on q.id = m.quote_id
    where q.tenant_id = 'c0ab0000-0000-4000-8000-000000000001' and m.kind = 'offer'),
  'Ana:email:pending:ana@example.invalid,Beto:email:pending:beto@example.invalid,'
    || 'Beto:whatsapp:needs_staff:+56911112222,Carla:whatsapp:needs_staff:+56933334444',
  'the offer goes exactly by what each customer chose, to the account''s data');

-- ---------------------------------------------------------------------------
-- Los datos siguen a la cuenta
-- ---------------------------------------------------------------------------

update public.customers set phone = '9 8888 7777'
 where id = 'c0ab0000-0000-4000-8000-0000000000c2';

select is(
  (select customer_phone from public.customer_quotes where id = current_setting('acc.qb')::uuid),
  '+56988887777', 'a new phone in the account reaches the quote, normalized');
select is(
  (select recipient from public.customer_quote_messages
    where quote_id = current_setting('acc.qb')::uuid and kind = 'offer' and channel = 'whatsapp'),
  '+56988887777', 'and the WhatsApp still to send goes to the new phone');
select is(
  (select count(*)::integer from public.customer_quote_events
    where quote_id = current_setting('acc.qb')::uuid and event_type = 'contact_updated'),
  1, 'the history says the quote took the account''s new data');

update public.customers set phone = null
 where id = 'c0ab0000-0000-4000-8000-0000000000c2';

select is(
  (select coalesce(customer_phone, 'none') || '|' || notify_email || '|' || notify_whatsapp || '|' || preferred_channel
     from public.customer_quotes where id = current_setting('acc.qb')::uuid),
  'none|true|false|email', 'without a phone the quote leaves WhatsApp and keeps email');
select is(
  (select state from public.customer_quote_messages
    where quote_id = current_setting('acc.qb')::uuid and kind = 'offer' and channel = 'whatsapp'),
  'skipped', 'the WhatsApp still to send is skipped');
select ok(
  (select bool_and(read_at is not null) from public.erp_notifications
    where tenant_id = 'c0ab0000-0000-4000-8000-000000000001'
      and type = 'customer_quote_whatsapp_pending'
      and data ->> 'quote_id' = current_setting('acc.qb')),
  'and the team is no longer asked to send it');
select is(
  (select count(*)::integer from public.customer_quote_messages
    where quote_id = current_setting('acc.qb')::uuid and kind = 'offer' and channel = 'email'),
  1, 'the email of the offer stays the only one');
select is(
  (select detail ->> 'whatsapp_dropped' from public.customer_quote_events
    where quote_id = current_setting('acc.qb')::uuid and event_type = 'contact_updated'
    order by id desc limit 1),
  'true', 'the history says WhatsApp was dropped for want of a phone');

update public.customers set phone = ''
 where id = 'c0ab0000-0000-4000-8000-0000000000c3';

select is(
  (select notify_email || '|' || notify_whatsapp from public.customer_quotes
    where id = current_setting('acc.qc')::uuid),
  'true|false', 'asked only for WhatsApp and left without a phone, the quote tells by email');
select is(
  (select string_agg(channel || ':' || state || ':' || recipient, ',' order by channel)
     from public.customer_quote_messages
    where quote_id = current_setting('acc.qc')::uuid and kind = 'offer'),
  'email:pending:carla@example.invalid,whatsapp:skipped:+56933334444',
  'so the current offer goes by email instead');

update public.customers set name = 'Ana María'
 where id = 'c0ab0000-0000-4000-8000-0000000000c1';

select is(
  (select customer_name from public.customer_quotes where id = current_setting('acc.qa')::uuid),
  'Ana María', 'a new name in the account reaches the quote');

-- ---------------------------------------------------------------------------
-- El cliente cambia sus avisos con su enlace
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('acc.view', public.get_public_customer_quote_v1(
  current_setting('acc.a')::jsonb ->> 'access_token')::text, true);
select set_config('acc.n1', public.update_public_customer_quote_notify_v1(
  current_setting('acc.a')::jsonb ->> 'access_token', '{"notify_email":true,"notify_whatsapp":true}')::text, true);
reset role;

select is(
  (current_setting('acc.view')::jsonb -> 'actions' ->> 'changeNotify')
    || '|' || (current_setting('acc.view')::jsonb -> 'quote' ->> 'canEmail')
    || '|' || (current_setting('acc.view')::jsonb -> 'quote' ->> 'canWhatsapp')
    || '|' || (current_setting('acc.view')::jsonb -> 'quote' ->> 'notifyWhatsapp'),
  'true|true|true|false', 'the link says what the customer can choose and what they chose');
select ok(
  current_setting('acc.view') not like '%@example.invalid%'
  and current_setting('acc.view') not like '%+569%',
  'the link never shows the account''s email or phone');
select is(
  current_setting('acc.n1')::jsonb ->> 'changed', 'true', 'adding WhatsApp is a change');
select is(
  (select string_agg(channel || ':' || state || ':' || recipient, ',' order by channel)
     from public.customer_quote_messages
    where quote_id = current_setting('acc.qa')::uuid and kind = 'offer'),
  'email:pending:ana@example.invalid,whatsapp:needs_staff:+56922223333',
  'the current offer now also waits to go by WhatsApp');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select set_config('acc.n2', public.update_public_customer_quote_notify_v1(
  current_setting('acc.a')::jsonb ->> 'access_token', '{"notify_email":false,"notify_whatsapp":true}')::text, true);
reset role;

select is(
  (select state from public.customer_quote_messages
    where quote_id = current_setting('acc.qa')::uuid and kind = 'offer' and channel = 'email'),
  'skipped', 'leaving email skips the email still to send');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select set_config('acc.n3', public.update_public_customer_quote_notify_v1(
  current_setting('acc.a')::jsonb ->> 'access_token', '{"notify_email":true,"notify_whatsapp":true}')::text, true);
select set_config('acc.n4', public.update_public_customer_quote_notify_v1(
  current_setting('acc.a')::jsonb ->> 'access_token', '{"notify_email":true,"notify_whatsapp":true}')::text, true);
select throws_ok(
  format($$select public.update_public_customer_quote_notify_v1(%L, '{"notify_email":false,"notify_whatsapp":false}')$$,
         current_setting('acc.a')::jsonb ->> 'access_token'),
  '22023', 'quote_contact_invalid', 'the customer keeps at least one way to be told');
select throws_ok(
  $$select public.update_public_customer_quote_notify_v1(repeat('z', 43), '{"notify_email":true}')$$,
  '42501', 'quote_link_invalid', 'a wrong link changes nothing');
reset role;

select is(
  (select string_agg(channel || ':' || state, ',' order by channel)
     from public.customer_quote_messages
    where quote_id = current_setting('acc.qa')::uuid and kind = 'offer'),
  'email:pending,whatsapp:needs_staff', 'choosing email again brings its message back');
select is(
  current_setting('acc.n4')::jsonb ->> 'changed', 'false', 'the same choice again changes nothing');
select is(
  (select count(*)::integer from public.customer_quote_events
    where quote_id = current_setting('acc.qa')::uuid and event_type = 'notify_changed' and actor_kind = 'customer'),
  3, 'every change of notices is in the history');

-- Carla rechaza: una cotización cerrada no cambia sus avisos.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select set_config('acc.tmp', public.respond_public_customer_quote_v1(
  current_setting('acc.c')::jsonb ->> 'access_token',
  '{"action":"reject","operation_key":"4e1c2a3b-4d5e-4f60-8a71-000000000001"}')::text, true);
select throws_ok(
  format($$select public.update_public_customer_quote_notify_v1(%L, '{"notify_email":true}')$$,
         current_setting('acc.c')::jsonb ->> 'access_token'),
  '55000', 'quote_not_open', 'a rejected quote takes no new notices');
reset role;

-- ---------------------------------------------------------------------------
-- «Mi cuenta» lista y abre las cotizaciones propias
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.list_my_customer_quotes_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.open_my_customer_quote_v1(uuid,uuid)', 'execute')
  and has_function_privilege('anon', 'public.update_public_customer_quote_notify_v1(text,jsonb)', 'execute'),
  'listing and opening need a session; changing notices needs only the link');

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('acc.mine', public.list_my_customer_quotes_v1('c0ab0000-0000-4000-8000-000000000001')::text, true);
select set_config('acc.open', public.open_my_customer_quote_v1(
  'c0ab0000-0000-4000-8000-000000000001', current_setting('acc.qa')::uuid)::text, true);
select throws_ok(
  format($$select public.open_my_customer_quote_v1('c0ab0000-0000-4000-8000-000000000001', %L)$$,
         current_setting('acc.qb')),
  'P0002', 'Quote not found or not accessible', 'another customer''s quote does not open from this account');
reset role;

select is(
  (select string_agg((e ->> 'number') || ':' || (e ->> 'status') || ':' || (e ->> 'lines')
                     || ':' || (e ->> 'total')::numeric::integer, ',')
     from jsonb_array_elements(current_setting('acc.mine')::jsonb) e),
  (select quote_number from public.customer_quotes where id = current_setting('acc.qa')::uuid)
    || ':offered:1:30000',
  'the account lists only its own quotes, with the total sent');
select ok(
  current_setting('acc.mine') not like '%@example.invalid%'
  and current_setting('acc.mine') not like '%access_token%',
  'the list carries no contact data and no links');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('acc.opened', public.get_public_customer_quote_v1(
  current_setting('acc.open')::jsonb ->> 'access_token')::text, true);
reset role;

select is(
  current_setting('acc.opened')::jsonb -> 'quote' ->> 'number',
  current_setting('acc.open')::jsonb ->> 'quote_number',
  'the new link opens the quote page like the one in the email');

-- ---------------------------------------------------------------------------
-- El ERP dice los avisos al armar una cotización
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0ab0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0ab0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('acc.s', public.create_staff_customer_quote_v1(
  'c0ab0000-0000-4000-8000-000000000001',
  '{"customer_name":"Mesón","customer_phone":"+56944445555","customer_email":"meson@example.invalid",
    "notify_whatsapp":true,"notify_email":false,
    "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
select throws_ok(
  $$select public.create_staff_customer_quote_v1('c0ab0000-0000-4000-8000-000000000001',
      '{"customer_name":"Sin teléfono","customer_email":"x@example.invalid","notify_whatsapp":true,
        "items":[{"product_id":"c0ab0000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '22023', 'quote_contact_invalid', 'the counter cannot promise WhatsApp without a phone');
select set_config('acc.inbox', public.customer_quote_inbox_v1('c0ab0000-0000-4000-8000-000000000001')::text, true);
reset role;

select is(
  (select notify_email || '|' || notify_whatsapp || '|' || preferred_channel
     from public.customer_quotes where id = (current_setting('acc.s')::jsonb ->> 'quote_id')::uuid),
  'false|true|whatsapp', 'a counter quote keeps the notices the team set');
select is(
  (select string_agg((e ->> 'customerName') || ':' || (e ->> 'notifyEmail') || ':' || (e ->> 'notifyWhatsapp'),
                     ',' order by e ->> 'customerName')
     from jsonb_array_elements(current_setting('acc.inbox')::jsonb -> 'quotes') e),
  'Ana María:true:true,Beto:true:false,Carla:true:false,Mesón:false:true',
  'the inbox shows each quote''s notices');

-- Una cuenta sin cotizaciones, o una cotización ya rechazada, no cambian.
update public.customers set phone = '+56900000000'
 where id = 'c0ab0000-0000-4000-8000-0000000000c4';
update public.customers set name = 'Carla Ruiz'
 where id = 'c0ab0000-0000-4000-8000-0000000000c3';
select is(
  (select count(*)::integer from public.customer_quote_events e
     join public.customer_quotes q on q.id = e.quote_id
    where q.tenant_id = 'c0ab0000-0000-4000-8000-000000000001' and e.event_type = 'contact_updated'),
  4, 'only quotes of the changed account take new data (two for Beto, one each for Carla and Ana)');
select is(
  (select customer_name from public.customer_quotes where id = current_setting('acc.qc')::uuid),
  'Carla', 'a rejected quote keeps the data it had');

select * from finish();
rollback;
