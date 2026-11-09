begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Los avisos con trato humano (20261108210000): nombran la bici en vez del
-- número de trabajo, el presupuesto no dice el monto, y mientras Meta no
-- apruebe una plantilla nueva sale la anterior. Todo es sintético, a horas
-- fijas del 7 de noviembre de 2026 (Chile, -03), y se deshace al final; el
-- despacho real a Meta queda apagado en la transacción.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('d9f00000-0000-4000-8000-000000000001', 'Trato Humano', 'trato-humano@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('d9f00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-trato@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id = 'd9f00000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('d9f00000-0000-4000-8000-000000000091', 'd9f00000-0000-4000-8000-000000000001', 'admin', '{}', true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('d9f00000-0000-4000-8000-000000000131', 'd9f00000-0000-4000-8000-000000000001',
   'trato-test-a', 'Sintético trato', true);

insert into public.company_settings (tenant_id, key, value) values
  ('d9f00000-0000-4000-8000-000000000001', 'workshop_notice_documents_enabled', 'true'),
  ('d9f00000-0000-4000-8000-000000000001', 'whatsapp_review_request_enabled', 'true');

insert into public.website_settings (tenant_id, key, value) values
  ('d9f00000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-trato.example.invalid'),
  ('d9f00000-0000-4000-8000-000000000001', 'store_name', 'Taller Trato'),
  ('d9f00000-0000-4000-8000-000000000001', 'google_maps_place_id', 'ChIJSyntheticPlaceTrato'),
  ('d9f00000-0000-4000-8000-000000000001', 'contact_address', 'Calle Uno 123, Viña del Mar, Chile'),
  ('d9f00000-0000-4000-8000-000000000001', 'seo_geo_latitude', '-33.025195'),
  ('d9f00000-0000-4000-8000-000000000001', 'seo_geo_longitude', '-71.562306'),
  ('d9f00000-0000-4000-8000-000000000001', 'business_hours_json', jsonb_build_object(
    'periods', jsonb_build_array(
      jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1030'), 'close', jsonb_build_object('day', 1, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 2, 'time', '1030'), 'close', jsonb_build_object('day', 2, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 3, 'time', '1030'), 'close', jsonb_build_object('day', 3, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 4, 'time', '1030'), 'close', jsonb_build_object('day', 4, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 5, 'time', '1030'), 'close', jsonb_build_object('day', 5, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 6, 'time', '1030'), 'close', jsonb_build_object('day', 6, 'time', '1530'))))::text);

-- Meta aprobó las nuevas como servicio, y las anteriores siguen aprobadas.
select is(public.record_whatsapp_template_reviews_v1('d9f00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_pdf_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v4', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_entregada_pdf_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'resena_google_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_entregada_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'))),
  10, 'Meta approved the new templates as utility, and the previous ones stay approved');

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('d9f00000-0000-4000-8000-000000000011', 'd9f00000-0000-4000-8000-000000000001',
   'Camila Torres Soto', '+56 9 2323 4545', null, null, true);

set local session_replication_role = replica;
insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('d9f00000-0000-4000-8000-000000000041', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000011', 'Trek', 'Marlin 7');

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, job_type,
  workflow_kind, intake_kind, status, approved_by_customer, quotation_status, client_request,
  total_cost, discount_amount, created_by) values
  -- R1: recién recibida.
  ('d9f00000-0000-4000-8000-000000000021', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000011', 'd9f00000-0000-4000-8000-000000000041', 'PG-R1',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 'Revisar cambios', 0, 0,
   'd9f00000-0000-4000-8000-000000000091'),
  -- Q1: «Presupuestar primero», esperando la aprobación del cliente.
  ('d9f00000-0000-4000-8000-000000000022', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000011', 'd9f00000-0000-4000-8000-000000000041', 'PG-Q1',
   'quotation', 'quotation', 'bike', 'ESPERANDO_APROBACION', false, 'pending', 'Cambia mal',
   59990, 0, 'd9f00000-0000-4000-8000-000000000091'),
  -- L1: terminada, lista para retirar.
  ('d9f00000-0000-4000-8000-000000000023', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000011', 'd9f00000-0000-4000-8000-000000000041', 'PG-L1',
   'service', 'service', 'bike', 'FINALIZADO', false, null, null, 0, 0,
   'd9f00000-0000-4000-8000-000000000091'),
  -- E1: entregada con su comprobante a las 08:00.
  ('d9f00000-0000-4000-8000-000000000024', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000011', 'd9f00000-0000-4000-8000-000000000041', 'PG-E1',
   'service', 'service', 'bike', 'ENTREGADO', true, null, null, 18000, 0,
   'd9f00000-0000-4000-8000-000000000091');

insert into public.mechanic_job_items (id, tenant_id, job_id, product_name, quantity, unit_price,
  total_price, item_type, created_at) values
  ('d9f00000-0000-4000-8000-000000000061', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000022', 'Cambio de cassette 11-46', 1, 39990, 39990,
   'service', '2026-11-07 10:00:00-03'),
  ('d9f00000-0000-4000-8000-000000000062', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000022', 'Cadena 10 velocidades', 1, 20000, 20000,
   'product', '2026-11-07 10:01:00-03');

insert into public.mechanic_job_delivery_events (id, tenant_id, job_id, event_kind, occurred_at,
  recorded_at, actor_id, source, operation_key) values
  ('d9f00000-0000-4000-8000-000000000404', 'd9f00000-0000-4000-8000-000000000001',
   'd9f00000-0000-4000-8000-000000000024', 'delivered', '2026-11-07 08:00:00-03',
   '2026-11-07 08:00:00-03', 'd9f00000-0000-4000-8000-000000000091', 'status_transition', 'trato-e1');

insert into public.mechanic_job_delivery_documents (tenant_id, job_id, delivery_event_id, job_number,
  delivered_at, service_warranty_days, service_warranty_expires_at, parts_warranty_months,
  parts_warranty_expires_at, snapshot) values
  ('d9f00000-0000-4000-8000-000000000001', 'd9f00000-0000-4000-8000-000000000024',
   'd9f00000-0000-4000-8000-000000000404', 'PG-E1', '2026-11-07 08:00:00-03',
   14, '2026-11-21 08:00:00-03', 2, '2027-01-07 08:00:00-03',
   jsonb_build_object('work_performed', 'Cambio de cadena',
     'lines', jsonb_build_array(jsonb_build_object('kind', 'part', 'name', 'Cadena KMC X10'))));
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Las nuevas, apenas Meta las aprueba
-- ---------------------------------------------------------------------------

select is(public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'received', 'bike', false),
  'taller_recibida_v3', 'the received notice prefers the v3');
select is(public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'quote_ready', 'bike', true),
  'taller_presupuesto_pdf_v2', 'a quote that can carry its PDF prefers the v2');
select is(public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'quote_ready', 'bike', false),
  'taller_presupuesto_v2', 'a quote without its PDF keeps the button template');
select is(public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'ready', 'bike', false),
  'taller_lista_v4', 'the ready notice prefers the v4 with the map');
select is(public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'delivered', 'bike', true),
  'taller_entregada_pdf_v2', 'the delivery with its receipt prefers the v2');

create temporary table trato_notice (job_id uuid, kind text, notice_id uuid) on commit drop;
select is(public.workshop_notice_enqueue_internal('d9f00000-0000-4000-8000-000000000001',
  job_id, kind, source_id, source_at, 'd9f00000-0000-4000-8000-000000000091', false, true), 1,
  'the ' || kind || ' notice is noted for WhatsApp')
  from (values
    ('d9f00000-0000-4000-8000-000000000021'::uuid, 'received', 'd9f00000-0000-4000-8000-000000000501'::uuid,
     '2026-11-07 11:00:00-03'::timestamptz),
    ('d9f00000-0000-4000-8000-000000000022'::uuid, 'quote_ready', 'd9f00000-0000-4000-8000-000000000502'::uuid,
     '2026-11-07 11:00:00-03'::timestamptz),
    ('d9f00000-0000-4000-8000-000000000023'::uuid, 'ready', 'd9f00000-0000-4000-8000-000000000503'::uuid,
     '2026-11-07 11:00:00-03'::timestamptz),
    ('d9f00000-0000-4000-8000-000000000024'::uuid, 'delivered', 'd9f00000-0000-4000-8000-000000000404'::uuid,
     '2026-11-07 08:00:00-03'::timestamptz))
    as source(job_id, kind, source_id, source_at);
insert into trato_notice
  select notice.job_id, notice.kind, notice.id from public.workshop_customer_notices notice
   where notice.tenant_id = 'd9f00000-0000-4000-8000-000000000001' and notice.channel = 'whatsapp';

select is(public.workshop_notice_dispatch_whatsapp_internal(notice_id, '2026-11-07 12:00:00-03', true), 'sent',
  'the ' || kind || ' notice goes out')
  from trato_notice order by kind;

create temporary table trato_sent on commit drop as
  select t.kind, notice.template_name, outbox.request, message.content
    from trato_notice t
    join public.workshop_customer_notices notice on notice.id = t.notice_id
    join public.whatsapp_outbox outbox on outbox.message_id = notice.message_id
    join public.messages message on message.id = notice.message_id;

select is((select string_agg(kind || ':' || template_name, ' | ' order by kind) from trato_sent),
  'delivered:taller_entregada_pdf_v2 | quote_ready:taller_presupuesto_pdf_v2 | ready:taller_lista_v4 | received:taller_recibida_v3',
  'every notice goes with its new template');

-- Recibida: la bici, no el número.
select is((select content from trato_sent where kind = 'received'),
  'Hola Camila Torres Soto, ya tenemos tu Trek Marlin 7 en el taller. Te iremos contando por aquí cómo va el trabajo, y si te surge cualquier duda, respóndenos en este mismo chat.',
  'the received notice names the bike');
select is((select request #> '{templateComponents,0,parameters}' from trato_sent where kind = 'received'),
  '[{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}]'::jsonb,
  'its body carries the name and the bike, not the job number');
select matches((select request #>> '{templateComponents,1,parameters,0,text}' from trato_sent where kind = 'received'),
  '^[A-Za-z0-9_-]{43}$', 'its button carries the account code');

-- Presupuesto: sin el monto, con la tarjeta de aprobación y su PDF.
select is((select content from trato_sent where kind = 'quote_ready'),
  'Hola Camila Torres Soto, te dejamos el presupuesto para tu Trek Marlin 7 en el PDF adjunto. Revísalo con calma: si quieres cambiar algo o tienes alguna duda, cuéntanos por aquí y lo conversamos. Si está todo en orden, puedes aprobarlo directamente desde este mensaje.',
  'the quote notice invites to review it calmly, without the amount');
select is((select request #> '{templateComponents}' from trato_sent where kind = 'quote_ready'),
  '[{"type": "body", "parameters": [{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}]}]'::jsonb,
  'the body carries the name and the bike; the PDF and the replies are added by the sender');
select is((select (request->>'actionType') || '|' || (request->>'actionKind') || '|' || (request->>'amount')
             from trato_sent where kind = 'quote_ready'),
  'approve_quote|job|59990', 'the quote still asks the sender for the approval card, with its amount');
select matches((select request->>'templateDocumentToken' from trato_sent where kind = 'quote_ready'),
  '^[A-Za-z0-9_-]{43}$', 'the quote carries its PDF code');

-- Lista: el mapa, la bici y cuándo pasar.
select is((select content from trato_sent where kind = 'ready'),
  'Hola Camila Torres Soto, terminamos el trabajo en tu Trek Marlin 7 y ya está todo listo para el retiro. Puedes pasar de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30. Si necesitas coordinar el retiro, avísanos por aquí.',
  'the ready notice names the bike and when to come');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type') from trato_sent where kind = 'ready'),
  '["header", "body", "button"]'::jsonb, 'the v4 is the map, the body and the account button');
select is((select request #> '{templateComponents,1,parameters}' from trato_sent where kind = 'ready'),
  '[{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}, {"type": "text", "text": "de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30"}]'::jsonb,
  'its body carries the name, the bike and the hours');

-- Entregada: gracias, el comprobante y hasta cuándo cubre la garantía.
select is((select content from trato_sent where kind = 'delivered'),
  'Hola Camila Torres Soto, gracias por dejar tu Trek Marlin 7 en nuestras manos. Te dejamos el comprobante del trabajo: el servicio tiene garantía hasta el 21 de noviembre, así que si antes de esa fecha algo no funciona como debería, escríbenos por aquí y lo revisamos.',
  'the delivery notice thanks and says until when the service is covered');
select is((select request #> '{templateComponents,0,parameters}' from trato_sent where kind = 'delivered'),
  '[{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}, {"type": "text", "text": "21 de noviembre"}]'::jsonb,
  'its body carries the name, the bike and the warranty date');
select matches((select request->>'templateDocumentToken' from trato_sent where kind = 'delivered'),
  '^[A-Za-z0-9_-]{43}$', 'the receipt carries its PDF code');

-- ---------------------------------------------------------------------------
-- La reseña nombra la bici
-- ---------------------------------------------------------------------------

select is(public.process_whatsapp_review_requests_v1('2026-11-07 12:00:00-03'),
  '{"sent": 1, "skipped": 0}'::jsonb, 'the review request goes out four hours after the delivery');
select is((select o.request->>'templateName' from public.whatsapp_outbox o
    join public.whatsapp_review_requests r on r.message_id = o.message_id
   where r.job_id = 'd9f00000-0000-4000-8000-000000000024'),
  'resena_google_v3', 'it goes with the v3');
select is((select m.content from public.messages m
    join public.whatsapp_review_requests r on r.message_id = m.id
   where r.job_id = 'd9f00000-0000-4000-8000-000000000024'),
  'Hola Camila Torres Soto, ojalá estés disfrutando tu Trek Marlin 7. Si quedaste conforme con el servicio, una reseña en Google nos ayuda mucho.',
  'the review request names the bike');
select is((select o.request #> '{templateComponents}' from public.whatsapp_outbox o
    join public.whatsapp_review_requests r on r.message_id = o.message_id
   where r.job_id = 'd9f00000-0000-4000-8000-000000000024'),
  '[{"type": "body", "parameters": [{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}]}, {"type": "button", "index": "0", "sub_type": "url", "parameters": [{"type": "text", "text": "ChIJSyntheticPlaceTrato"}]}]'::jsonb,
  'its body carries the name and the bike, and its button the Google place');

-- ---------------------------------------------------------------------------
-- Mientras Meta revisa las nuevas, salen las anteriores
-- ---------------------------------------------------------------------------

select is(public.record_whatsapp_template_reviews_v1('d9f00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v3', 'language', 'es_CL', 'status', 'PENDING', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_pdf_v2', 'language', 'es_CL', 'status', 'PENDING', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v4', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'MARKETING'),
    jsonb_build_object('name', 'taller_entregada_pdf_v2', 'language', 'es_CL', 'status', 'REJECTED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_entregada_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'))),
  9, 'Meta has some new ones in review, one as marketing and one rejected');
select is(
  public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'received', 'bike', false)
    || ' | ' || public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'quote_ready', 'bike', true)
    || ' | ' || public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'ready', 'bike', false)
    || ' | ' || public.workshop_notice_template_v2_internal('d9f00000-0000-4000-8000-000000000001', 'delivered', 'bike', true),
  'taller_recibida_v2 | taller_presupuesto_pdf_v1 | taller_lista_v3 | taller_entregada_pdf_v1',
  'each notice keeps going with the previous template until Meta approves the new one as utility');

select * from finish();
rollback;
