begin;

select plan(18);

-- Mensajes al cliente de una cotización (20261102063700): cada hito deja su
-- mensaje una vez, el correo lo reclama el worker con un enlace nuevo y el
-- WhatsApp espera al equipo hasta que haya plantilla.

insert into public.tenants (id, shop_name) values
  ('c0a80000-0000-4000-8000-000000000001', 'Taller mensajes A');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'c0a80000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'mensajes-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('c0a80000-0000-4000-8000-000000000091', 'c0a80000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb);

insert into public.transactional_email_settings (
  tenant_id, enabled, delivery_mode, from_name, from_email, reply_to_email, public_store_url
) values (
  'c0a80000-0000-4000-8000-000000000001', true, 'send', 'Ventas Taller', 'ventas@example.invalid',
  'ventas@example.invalid', 'https://tienda.example.invalid'
) on conflict (tenant_id) do update
  set enabled = excluded.enabled, delivery_mode = excluded.delivery_mode,
      from_name = excluded.from_name, from_email = excluded.from_email,
      reply_to_email = excluded.reply_to_email, public_store_url = excluded.public_store_url;

insert into public.products (
  id, tenant_id, name, sku, price, tax_rate, product_type, is_service, is_active,
  is_published, show_on_website
) values (
  'c0a80000-0000-4000-8000-000000000011', 'c0a80000-0000-4000-8000-000000000001',
  'Neumático 29 x 2.25', 'MSG-1', 30000, 19, 'product', false, true, true, true
);
update public.products set inventory_qty = 5, stock_quantity = 5
 where id = 'c0a80000-0000-4000-8000-000000000011';

-- Una por correo y otra por WhatsApp con correo de respaldo.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select set_config('msg.email', public.request_public_customer_quote_v1(
  'c0a80000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5d1c2a3b-4d5e-4f60-8a71-000000000001","customer_name":"Ana",
    "customer_email":"ana@example.invalid","preferred_channel":"email",
    "items":[{"product_id":"c0a80000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
select set_config('msg.wa', public.request_public_customer_quote_v1(
  'c0a80000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5d1c2a3b-4d5e-4f60-8a71-000000000002","customer_name":"Beto",
    "customer_phone":"+56911112222","customer_email":"beto@example.invalid","preferred_channel":"whatsapp",
    "items":[{"product_id":"c0a80000-0000-4000-8000-000000000011","quantity":2}]}')::text, true);
reset role;

select set_config('msg.q1', current_setting('msg.email')::jsonb ->> 'quote_id', true);
select set_config('msg.q2', current_setting('msg.wa')::jsonb ->> 'quote_id', true);

select is(
  (select string_agg(kind || ':' || channel || ':' || state, ',' order by kind)
     from public.customer_quote_messages where quote_id = current_setting('msg.q1')::uuid),
  'received:email:pending', 'a web request queues «Recibimos tu cotización» by email');
select is(
  (select string_agg(kind || ':' || channel || ':' || state, ',' order by kind)
     from public.customer_quote_messages where quote_id = current_setting('msg.q2')::uuid),
  'received:email:pending', 'without a WhatsApp template the acknowledgement goes only by email');

-- El equipo envía las dos ofertas.
select set_config('request.jwt.claims', '{"sub":"c0a80000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a80000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('msg.tmp', public.customer_quote_send_offer_v1(
  'c0a80000-0000-4000-8000-000000000001', current_setting('msg.q1')::uuid,
  '6e1c2a3b-4d5e-4f60-8a71-000000000001')::text, true);
select set_config('msg.tmp', public.customer_quote_send_offer_v1(
  'c0a80000-0000-4000-8000-000000000001', current_setting('msg.q2')::uuid,
  '6e1c2a3b-4d5e-4f60-8a71-000000000002')::text, true);
reset role;

select is(
  (select string_agg(kind || ':' || channel || ':' || state, ',' order by kind, channel)
     from public.customer_quote_messages where quote_id = current_setting('msg.q2')::uuid),
  'offer:email:pending,offer:whatsapp:needs_staff,received:email:pending',
  'a WhatsApp offer waits for the team and goes by email as a backup');
select ok(
  exists (select 1 from public.erp_notifications
           where tenant_id = 'c0a80000-0000-4000-8000-000000000001'
             and type = 'customer_quote_whatsapp_pending'
             and data ->> 'quote_id' = current_setting('msg.q2')),
  'the team is told to send the offer by WhatsApp');

-- El worker reclama los correos con todo lo que dibujan.
select set_config('msg.claim', public.claim_customer_quote_messages_v1(
  'c0a80000-0000-4000-8000-000000000001', 'worker-test', 10)::text, true);
select is(jsonb_array_length(current_setting('msg.claim')::jsonb), 4, 'the four due emails are claimed');
select is(
  (select count(*)::integer from public.customer_quote_messages
    where tenant_id = 'c0a80000-0000-4000-8000-000000000001' and state = 'sending'),
  4, 'claimed emails are leased');
select is(
  jsonb_array_length(public.claim_customer_quote_messages_v1(
    'c0a80000-0000-4000-8000-000000000001', 'worker-other', 10)),
  0, 'a leased email is not claimed twice');

select set_config('msg.offer_payload', (
  select e::text from jsonb_array_elements(current_setting('msg.claim')::jsonb) e
   where e ->> 'kind' = 'offer' and e -> 'quote' ->> 'customerName' = 'Ana'), true);
select ok(
  current_setting('msg.offer_payload')::jsonb ->> 'link'
    ~ '^https://tienda\.example\.invalid/cotizacion#t=[A-Za-z0-9_-]{40,}$',
  'the email carries a fresh link to the quote page, in the fragment');
select is(
  (current_setting('msg.offer_payload')::jsonb -> 'offer' ->> 'total')::integer
    || '|' || (current_setting('msg.offer_payload')::jsonb -> 'sender' ->> 'email')
    || '|' || (current_setting('msg.offer_payload')::jsonb -> 'sender' ->> 'enabled'),
  '30000|ventas@example.invalid|true', 'the offer email has its total and the store sender');
select ok(
  current_setting('msg.offer_payload') not like '%unit_cost%'
  and current_setting('msg.offer_payload') not like '%supplier%',
  'the email never carries supplier or cost');
select ok(
  exists (select 1 from public.customer_quote_access_tokens
           where token_sha256 = encode(extensions.digest(convert_to(
             split_part(current_setting('msg.offer_payload')::jsonb ->> 'link', '#t=', 2), 'UTF8'), 'sha256'), 'hex')),
  'only the link''s hash is stored');

select is(
  public.complete_customer_quote_message_v1(
    (current_setting('msg.offer_payload')::jsonb ->> 'messageId')::uuid, 'worker-test', 'sent', 're_123', null),
  'sent', 'a delivered email is marked sent');
select is(
  public.complete_customer_quote_message_v1(
    (current_setting('msg.offer_payload')::jsonb ->> 'messageId')::uuid, 'worker-test', 'sent', 're_123', null),
  'not_leased', 'completing twice changes nothing');

-- El equipo manda el WhatsApp a mano y lo marca.
select set_config('request.jwt.claims', '{"sub":"c0a80000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a80000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('msg.link', public.customer_quote_issue_link_v1(
  'c0a80000-0000-4000-8000-000000000001', current_setting('msg.q2')::uuid)::text, true);
select set_config('msg.tmp', public.customer_quote_mark_message_sent_v1(
  'c0a80000-0000-4000-8000-000000000001',
  (select id from public.customer_quote_messages
    where quote_id = current_setting('msg.q2')::uuid and channel = 'whatsapp'))::text, true);
reset role;

select ok(
  current_setting('msg.link')::jsonb ->> 'url' ~ '^https://tienda\.example\.invalid/cotizacion#t=',
  'the team gets a fresh link to send by hand');
select is(
  (select state || ':' || provider from public.customer_quote_messages
    where quote_id = current_setting('msg.q2')::uuid and channel = 'whatsapp'),
  'sent:staff', 'the WhatsApp offer sent by the team is marked sent');

-- Una oferta que deja de estar vigente ya no se manda (20261102072900):
-- el cliente rechaza y su WhatsApp «Por enviar» queda omitido.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('msg.q3r', public.request_public_customer_quote_v1(
  'c0a80000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5d1c2a3b-4d5e-4f60-8a71-000000000003","customer_name":"Carla",
    "customer_phone":"+56933334444","preferred_channel":"whatsapp",
    "items":[{"product_id":"c0a80000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
reset role;
select set_config('msg.q3', current_setting('msg.q3r')::jsonb ->> 'quote_id', true);
select set_config('request.jwt.claims', '{"sub":"c0a80000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a80000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('msg.tmp', public.customer_quote_send_offer_v1(
  'c0a80000-0000-4000-8000-000000000001', current_setting('msg.q3')::uuid,
  '6e1c2a3b-4d5e-4f60-8a71-000000000003')::text, true);
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('msg.tmp', public.respond_public_customer_quote_v1(
  current_setting('msg.q3r')::jsonb ->> 'access_token',
  '{"action":"reject","operation_key":"7f1c2a3b-4d5e-4f60-8a71-000000000001"}')::text, true);
reset role;

select is(
  (select state from public.customer_quote_messages
    where quote_id = current_setting('msg.q3')::uuid and channel = 'whatsapp' and kind = 'offer'),
  'skipped', 'a rejected offer is no longer sent by WhatsApp');
select ok(
  (select bool_and(read_at is not null) from public.erp_notifications
    where tenant_id = 'c0a80000-0000-4000-8000-000000000001'
      and type = 'customer_quote_whatsapp_pending'
      and data ->> 'quote_id' = current_setting('msg.q3')),
  'and the team is no longer asked to send it');

-- Un día antes de vencer, la oferta se recuerda una vez.
set local session_replication_role = replica;
update public.customer_quotes
   set expires_at = now() + interval '20 hours', offered_at = now() - interval '2 days'
 where id = current_setting('msg.q1')::uuid;
set local session_replication_role = origin;
select is(public.remind_customer_quote_offers_v1(), 1, 'the reminder goes once, a day before it expires');

select * from finish();
rollback;
