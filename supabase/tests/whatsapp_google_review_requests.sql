begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Pedido de reseña de Google después de una entrega. Todo es sintético, se
-- deshace al final y el despacho real a Meta queda apagado en la transacción.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants(id, shop_name) values
  ('9e0e0000-0000-4000-8000-000000000001', 'Review Shop A'),
  ('9e0e0000-0000-4000-8000-000000000002', 'Review Shop B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('9e0e0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'review-admin-a@example.invalid', '', now(), '{}',
   '{"tenant_id":"9e0e0000-0000-4000-8000-000000000001"}', now(), now()),
  ('9e0e0000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'review-admin-b@example.invalid', '', now(), '{}',
   '{"tenant_id":"9e0e0000-0000-4000-8000-000000000002"}', now(), now());
delete from public.user_profiles where user_id in (
  '9e0e0000-0000-4000-8000-000000000091', '9e0e0000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active) values
  ('9e0e0000-0000-4000-8000-000000000091', '9e0e0000-0000-4000-8000-000000000001', 'admin', '{}', true),
  ('9e0e0000-0000-4000-8000-000000000092', '9e0e0000-0000-4000-8000-000000000002', 'admin', '{}', true);

insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active) values
  ('9e0e0000-0000-4000-8000-000000000131', '9e0e0000-0000-4000-8000-000000000001', 'review-test-a', 'Synthetic A', true),
  ('9e0e0000-0000-4000-8000-000000000132', '9e0e0000-0000-4000-8000-000000000002', 'review-test-b', 'Synthetic B', true);

insert into public.company_settings(tenant_id, key, value) values
  ('9e0e0000-0000-4000-8000-000000000001', 'whatsapp_review_request_enabled', 'true');
insert into public.website_settings(tenant_id, key, value) values
  ('9e0e0000-0000-4000-8000-000000000001', 'google_maps_place_id', 'ChIJSyntheticPlaceA01'),
  ('9e0e0000-0000-4000-8000-000000000002', 'google_maps_place_id', 'ChIJSyntheticPlaceB01');

insert into public.customers(id, tenant_id, name, phone) values
  ('9e0e0000-0000-4000-8000-000000000011', '9e0e0000-0000-4000-8000-000000000001', 'María José Rojas Pérez', '+56 9 1111 2222'),
  ('9e0e0000-0000-4000-8000-000000000012', '9e0e0000-0000-4000-8000-000000000001', 'Sin Celular', null),
  ('9e0e0000-0000-4000-8000-000000000013', '9e0e0000-0000-4000-8000-000000000002', 'Cliente Tienda B', '+56 9 3333 4444');

-- A1: entregada a las 08:00 (4 h antes de las 12:00 de la prueba).
-- A2: el mismo cliente, otra bici, entregada a las 08:30.
-- A3: cliente sin celular. A4: entregada hace 1 h (aún no toca).
-- B1: tienda que no encendió el pedido.
insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number, job_type,
  workflow_kind, intake_kind, status, arrival_date) values
  ('9e0e0000-0000-4000-8000-000000000021', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000011', 'PG-REVIEW-A1', 'item_service', 'service', 'component', 'ENTREGADO', '2026-10-06 09:00:00-03'),
  ('9e0e0000-0000-4000-8000-000000000022', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000011', 'PG-REVIEW-A2', 'item_service', 'service', 'component', 'ENTREGADO', '2026-10-06 09:00:00-03'),
  ('9e0e0000-0000-4000-8000-000000000023', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000012', 'PG-REVIEW-A3', 'item_service', 'service', 'component', 'ENTREGADO', '2026-10-06 09:00:00-03'),
  ('9e0e0000-0000-4000-8000-000000000024', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000011', 'PG-REVIEW-A4', 'item_service', 'service', 'component', 'ENTREGADO', '2026-10-06 09:00:00-03'),
  ('9e0e0000-0000-4000-8000-000000000025', '9e0e0000-0000-4000-8000-000000000002', '9e0e0000-0000-4000-8000-000000000013', 'PG-REVIEW-B1', 'item_service', 'service', 'component', 'ENTREGADO', '2026-10-06 09:00:00-03');

insert into public.mechanic_job_delivery_events(id, tenant_id, job_id, event_kind,
  occurred_at, recorded_at, actor_id, source, operation_key) values
  ('9e0e0000-0000-4000-8000-000000000031', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000021', 'delivered', '2026-10-08 08:00:00-03', '2026-10-08 08:00:00-03', '9e0e0000-0000-4000-8000-000000000091', 'status_transition', 'review-test-a1'),
  ('9e0e0000-0000-4000-8000-000000000032', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000022', 'delivered', '2026-10-08 08:30:00-03', '2026-10-08 08:30:00-03', '9e0e0000-0000-4000-8000-000000000091', 'status_transition', 'review-test-a2'),
  ('9e0e0000-0000-4000-8000-000000000033', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000023', 'delivered', '2026-10-08 08:00:00-03', '2026-10-08 08:00:00-03', '9e0e0000-0000-4000-8000-000000000091', 'status_transition', 'review-test-a3'),
  ('9e0e0000-0000-4000-8000-000000000034', '9e0e0000-0000-4000-8000-000000000001', '9e0e0000-0000-4000-8000-000000000024', 'delivered', '2026-10-08 11:00:00-03', '2026-10-08 11:00:00-03', '9e0e0000-0000-4000-8000-000000000091', 'status_transition', 'review-test-a4'),
  ('9e0e0000-0000-4000-8000-000000000035', '9e0e0000-0000-4000-8000-000000000002', '9e0e0000-0000-4000-8000-000000000025', 'delivered', '2026-10-08 08:00:00-03', '2026-10-08 08:00:00-03', '9e0e0000-0000-4000-8000-000000000092', 'status_transition', 'review-test-b1');

-- De noche no sale nada.
select is(
  public.process_whatsapp_review_requests_v1('2026-10-08 03:00:00-03'),
  '{"sent": 0, "skipped": 0, "outside_hours": true}'::jsonb,
  'nobody gets a review request at night');
select is((select count(*)::integer from public.whatsapp_review_requests
  where tenant_id = '9e0e0000-0000-4000-8000-000000000001'), 0,
  'the night pass leaves every delivery for later');

-- A mediodía: A1 sale; A2 es el mismo cliente; A3 no tiene celular; A4 es de
-- hace una hora; B1 es de una tienda que no lo encendió.
select is(
  public.process_whatsapp_review_requests_v1('2026-10-08 12:00:00-03'),
  '{"sent": 1, "skipped": 2}'::jsonb,
  'one request is sent and two are skipped with a reason');
select is((select status || ':' || coalesce(reason, '')
    from public.whatsapp_review_requests
   where job_id = '9e0e0000-0000-4000-8000-000000000021'),
  'sent:', 'the first delivery of the customer is asked');
select is((select status || ':' || reason from public.whatsapp_review_requests
   where job_id = '9e0e0000-0000-4000-8000-000000000022'),
  'skipped:asked_this_year', 'the same customer is not asked twice in a year');
select is((select status || ':' || reason from public.whatsapp_review_requests
   where job_id = '9e0e0000-0000-4000-8000-000000000023'),
  'skipped:no_mobile', 'a customer without a mobile is skipped, not retried');
select is((select count(*)::integer from public.whatsapp_review_requests
   where job_id in ('9e0e0000-0000-4000-8000-000000000024',
                    '9e0e0000-0000-4000-8000-000000000025')), 0,
  'a recent delivery and a shop that did not opt in are left alone');

-- El mensaje entra a la cola durable igual que uno del equipo.
select is((select o.request->>'templateName' || '|' || (o.request->>'templateLanguage')
             || '|' || (o.request #>> '{metadata,template_purpose}')
             || '|' || o.actor_id::text || '|' || o.state
     from public.whatsapp_outbox o
     join public.whatsapp_review_requests r on r.message_id = o.message_id
    where r.job_id = '9e0e0000-0000-4000-8000-000000000021'),
  'resena_google_v1|es_CL|google_review_request|9e0e0000-0000-4000-8000-000000000091|queued',
  'the request rides the durable outbox as the person who delivered the bike');
select is((select o.request #>> '{templateComponents,0,parameters,1,text}'
     from public.whatsapp_outbox o
     join public.whatsapp_review_requests r on r.message_id = o.message_id
    where r.job_id = '9e0e0000-0000-4000-8000-000000000021'),
  'https://search.google.com/local/writereview?placeid=ChIJSyntheticPlaceA01',
  'the review link comes from the site''s Google place');
select is((select m.content from public.messages m
     join public.whatsapp_review_requests r on r.message_id = m.id
    where r.job_id = '9e0e0000-0000-4000-8000-000000000021'),
  'Hola María José Rojas Pérez, ya entregamos tu bicicleta en Viñabike. ¿Cómo te fue con el servicio? Puedes contarnos con una reseña en Google: https://search.google.com/local/writereview?placeid=ChIJSyntheticPlaceA01 Gracias por preferirnos.',
  'the inbox keeps the exact text of the approved template');
select is((select b.customer_id::text from public.whatsapp_conversation_bindings b
     join public.whatsapp_review_requests r on r.tenant_id = b.tenant_id
     join public.messages m on m.id = r.message_id and m.conversation_id = b.conversation_id
    where r.job_id = '9e0e0000-0000-4000-8000-000000000021'),
  '9e0e0000-0000-4000-8000-000000000011',
  'the message lands in the customer''s own WhatsApp conversation');
select is(current_setting('request.jwt.claim.sub', true), '',
  'the pass does not leave the delivering person as the session');

-- Una segunda pasada no repite nada y, una hora después, A4 se omite: su
-- cliente ya recibió el pedido.
select is(
  public.process_whatsapp_review_requests_v1('2026-10-08 12:10:00-03'),
  '{"sent": 0, "skipped": 0}'::jsonb,
  'a second pass sends nothing again');
select is(
  public.process_whatsapp_review_requests_v1('2026-10-08 14:30:00-03'),
  '{"sent": 0, "skipped": 1}'::jsonb,
  'a later delivery of the same customer is skipped');
select is((select count(*)::integer from public.whatsapp_outbox o
     join public.messages m on m.id = o.message_id
    where m.tenant_id = '9e0e0000-0000-4000-8000-000000000001'
      and o.request->>'templateName' = 'resena_google_v1'), 1,
  'exactly one review message was queued for the shop');

-- Nadie del equipo ejecuta el proceso, y cada tienda sólo lee lo suyo.
select ok(not has_function_privilege('authenticated',
  'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE'),
  'staff cannot run the review pass by hand');
select ok(not has_table_privilege('authenticated',
  'public.whatsapp_review_requests', 'INSERT'),
  'staff cannot write review requests');
select set_config('request.jwt.claims',
  '{"sub":"9e0e0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9e0e0000-0000-4000-8000-000000000092', true);
set local role authenticated;
select is((select count(*)::integer from public.whatsapp_review_requests), 0,
  'another shop does not see these requests');
reset role;
select set_config('request.jwt.claims',
  '{"sub":"9e0e0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9e0e0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is((select count(*)::integer from public.whatsapp_review_requests), 4,
  'the shop staff see their own requests and reasons');
reset role;

select * from finish();
rollback;
