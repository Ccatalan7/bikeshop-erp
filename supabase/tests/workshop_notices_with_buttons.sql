begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Avisos del taller y pedido de reseña con título, pie y botón
-- (20261107120000). Todo es sintético, a horas fijas del 7 de noviembre de
-- 2026 (Chile, -03) y se deshace al final; el despacho real a Meta queda
-- apagado en la transacción.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b7e00000-0000-4000-8000-000000000001', 'Botones A', 'botones-a@example.invalid', 'America/Santiago', true),
  ('b7e00000-0000-4000-8000-000000000002', 'Botones B', 'botones-b@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('b7e00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-botones@example.invalid', '', now(), '{}', '{}', now(), now()),
  -- La cuenta de Ana en la tienda A.
  ('b7e00000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'ana-botones@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id = 'b7e00000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('b7e00000-0000-4000-8000-000000000091', 'b7e00000-0000-4000-8000-000000000001', 'admin', '{}', true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('b7e00000-0000-4000-8000-000000000131', 'b7e00000-0000-4000-8000-000000000001',
   'botones-test-a', 'Sintético botones', true);

-- La tienda A: su ficha de Google dejó el punto, la dirección y el horario.
-- La B no tiene punto ni horario.
insert into public.website_settings (tenant_id, key, value) values
  ('b7e00000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-botones.example.invalid'),
  ('b7e00000-0000-4000-8000-000000000001', 'store_name', 'Taller Botones'),
  ('b7e00000-0000-4000-8000-000000000001', 'contact_address', 'Calle Uno 123, Local 4, Viña del Mar, Chile'),
  ('b7e00000-0000-4000-8000-000000000001', 'seo_geo_latitude', '-33.025195'),
  ('b7e00000-0000-4000-8000-000000000001', 'seo_geo_longitude', '-71.562306'),
  ('b7e00000-0000-4000-8000-000000000001', 'google_maps_place_id', 'ChIJbotonesDePrueba_1-x'),
  ('b7e00000-0000-4000-8000-000000000001', 'business_hours_json', jsonb_build_object(
    'open_now', false,
    'periods', jsonb_build_array(
      jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1030'), 'close', jsonb_build_object('day', 1, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 2, 'time', '1030'), 'close', jsonb_build_object('day', 2, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 3, 'time', '1030'), 'close', jsonb_build_object('day', 3, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 4, 'time', '1030'), 'close', jsonb_build_object('day', 4, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 5, 'time', '1030'), 'close', jsonb_build_object('day', 5, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 6, 'time', '1030'), 'close', jsonb_build_object('day', 6, 'time', '1530'))))::text),
  ('b7e00000-0000-4000-8000-000000000002', 'store_name', 'Taller B'),
  ('b7e00000-0000-4000-8000-000000000002', 'contact_address', 'Calle Dos 9, Santiago');

insert into public.company_settings (tenant_id, key, value) values
  ('b7e00000-0000-4000-8000-000000000001', 'whatsapp_review_request_enabled', 'true');

-- ---------------------------------------------------------------------------
-- El horario dicho como se dice y el punto del mapa
-- ---------------------------------------------------------------------------

select is(public.workshop_notice_hours_internal('b7e00000-0000-4000-8000-000000000001'),
  'de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30',
  'the days with the same hours are said together, the way a person says them');
select is(public.workshop_notice_hours_internal('b7e00000-0000-4000-8000-000000000002'), null,
  'without hours there is no sentence');

update public.website_settings set value = jsonb_build_object('periods', jsonb_build_array(
    jsonb_build_object('open', jsonb_build_object('day', 2, 'time', '0930'), 'close', jsonb_build_object('day', 2, 'time', '1400')),
    jsonb_build_object('open', jsonb_build_object('day', 3, 'time', '0930'), 'close', jsonb_build_object('day', 3, 'time', '1400')),
    jsonb_build_object('open', jsonb_build_object('day', 4, 'time', '1000'), 'close', jsonb_build_object('day', 4, 'time', '1800')),
    jsonb_build_object('open', jsonb_build_object('day', 6, 'time', '1000'), 'close', jsonb_build_object('day', 6, 'time', '1300')),
    jsonb_build_object('open', jsonb_build_object('day', 0, 'time', '1000'), 'close', jsonb_build_object('day', 0, 'time', '1300'))))::text
 where tenant_id = 'b7e00000-0000-4000-8000-000000000001' and key = 'business_hours_json';
select is(public.workshop_notice_hours_internal('b7e00000-0000-4000-8000-000000000001'),
  'los martes y miércoles de 9:30 a 14:00, los jueves de 10:00 a 18:00 y los sábados y domingos de 10:00 a 13:00',
  'two days in a row, a single day and the weekend read naturally, without a leading zero');

update public.website_settings set value = jsonb_build_object('periods', jsonb_build_array(
    jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1000'), 'close', jsonb_build_object('day', 1, 'time', '1300')),
    jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1500'), 'close', jsonb_build_object('day', 1, 'time', '1900'))))::text
 where tenant_id = 'b7e00000-0000-4000-8000-000000000001' and key = 'business_hours_json';
select is(public.workshop_notice_hours_internal('b7e00000-0000-4000-8000-000000000001'), null,
  'two shifts in one day are not guessed: the notice says it generically');

update public.website_settings set value = 'no es json'
 where tenant_id = 'b7e00000-0000-4000-8000-000000000001' and key = 'business_hours_json';
select is(public.workshop_notice_hours_internal('b7e00000-0000-4000-8000-000000000001'), null,
  'broken hours are no hours');

-- De vuelta al horario de la tienda.
update public.website_settings set value = jsonb_build_object('periods', jsonb_build_array(
    jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1030'), 'close', jsonb_build_object('day', 1, 'time', '1900')),
    jsonb_build_object('open', jsonb_build_object('day', 2, 'time', '1030'), 'close', jsonb_build_object('day', 2, 'time', '1900')),
    jsonb_build_object('open', jsonb_build_object('day', 3, 'time', '1030'), 'close', jsonb_build_object('day', 3, 'time', '1900')),
    jsonb_build_object('open', jsonb_build_object('day', 4, 'time', '1030'), 'close', jsonb_build_object('day', 4, 'time', '1900')),
    jsonb_build_object('open', jsonb_build_object('day', 5, 'time', '1030'), 'close', jsonb_build_object('day', 5, 'time', '1900')),
    jsonb_build_object('open', jsonb_build_object('day', 6, 'time', '1030'), 'close', jsonb_build_object('day', 6, 'time', '1530'))))::text
 where tenant_id = 'b7e00000-0000-4000-8000-000000000001' and key = 'business_hours_json';

select is(public.workshop_notice_location_internal('b7e00000-0000-4000-8000-000000000001'),
  '{"latitude": "-33.025195", "longitude": "-71.562306", "name": "Taller Botones", "address": "Calle Uno 123, Local 4, Viña del Mar"}'::jsonb,
  'the map carries the shop''s point, its name and its address without the country');
select is(public.workshop_notice_location_internal('b7e00000-0000-4000-8000-000000000002'), null,
  'a shop without its point has no map');

-- ---------------------------------------------------------------------------
-- Clientes, bici y trabajos
-- ---------------------------------------------------------------------------

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('b7e00000-0000-4000-8000-000000000011', 'b7e00000-0000-4000-8000-000000000001',
   'Camila Torres Soto', '+56 9 1212 3434', null, null, true),
  ('b7e00000-0000-4000-8000-000000000013', 'b7e00000-0000-4000-8000-000000000001',
   'Ana Con Cuenta', '+56 9 5656 7878', null, 'b7e00000-0000-4000-8000-000000000093', true);

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('b7e00000-0000-4000-8000-000000000041', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000011', 'Trek', 'Marlin 7');

set local session_replication_role = replica;
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, job_type,
  workflow_kind, intake_kind, status, approved_by_customer, client_request, total_cost, created_by) values
  -- R1: Camila deja su Trek.
  ('b7e00000-0000-4000-8000-000000000021', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000011', 'b7e00000-0000-4000-8000-000000000041', 'PG-R1',
   'quotation', 'quotation', 'bike', 'PENDIENTE', false, 'Mantención', 0,
   'b7e00000-0000-4000-8000-000000000091'),
  -- R2: Ana, que ya tiene cuenta, deja una bici.
  ('b7e00000-0000-4000-8000-000000000022', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000013', null, 'PG-R2',
   'quotation', 'quotation', 'bike', 'PENDIENTE', false, null, 0,
   'b7e00000-0000-4000-8000-000000000091'),
  -- Q1: el presupuesto de Camila está listo.
  ('b7e00000-0000-4000-8000-000000000023', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000011', null, 'PG-Q1',
   'quotation', 'quotation', 'bike', 'ESPERANDO_APROBACION', false, null, 59990,
   'b7e00000-0000-4000-8000-000000000091'),
  -- L1: la bici de Camila está lista.
  ('b7e00000-0000-4000-8000-000000000024', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000011', null, 'PG-L1',
   'service', 'service', 'bike', 'FINALIZADO', false, null, 0,
   'b7e00000-0000-4000-8000-000000000091'),
  -- E1: Camila retiró su bici; E2 también, para el pedido de reseña.
  ('b7e00000-0000-4000-8000-000000000025', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000011', null, 'PG-E1',
   'service', 'service', 'bike', 'ENTREGADO', false, null, 0,
   'b7e00000-0000-4000-8000-000000000091');

insert into public.mechanic_job_delivery_events (id, tenant_id, job_id, event_kind, occurred_at,
  recorded_at, actor_id, source, operation_key) values
  ('b7e00000-0000-4000-8000-000000000403', 'b7e00000-0000-4000-8000-000000000001',
   'b7e00000-0000-4000-8000-000000000025', 'delivered', '2026-11-07 11:00:00-03',
   '2026-11-07 11:00:00-03', 'b7e00000-0000-4000-8000-000000000091', 'status_transition', 'botones-e1');

insert into public.mechanic_job_delivery_documents (tenant_id, job_id, delivery_event_id, job_number,
  delivered_at, service_warranty_days, service_warranty_expires_at, parts_warranty_months,
  parts_warranty_expires_at, snapshot) values
  ('b7e00000-0000-4000-8000-000000000001', 'b7e00000-0000-4000-8000-000000000025',
   'b7e00000-0000-4000-8000-000000000403', 'PG-E1', '2026-11-07 11:00:00-03',
   14, '2026-11-21 11:00:00-03', 2, '2027-01-07 11:00:00-03',
   jsonb_build_object('work_performed', 'Cambio de cassette',
     'lines', jsonb_build_array(jsonb_build_object('kind', 'service', 'name', 'Cambio de cassette'))));
set local session_replication_role = origin;

-- Un aviso pendiente de WhatsApp por trabajo, ya vencida su espera.
create temporary table botones_notice (job_id uuid, kind text, notice_id uuid) on commit drop;
select is(public.workshop_notice_enqueue_internal('b7e00000-0000-4000-8000-000000000001',
  job_id, kind, source_id, '2026-11-07 10:00:00-03', 'b7e00000-0000-4000-8000-000000000091', false, true), 1,
  'the ' || kind || ' notice is noted for WhatsApp')
  from (values
    ('b7e00000-0000-4000-8000-000000000021'::uuid, 'received', 'b7e00000-0000-4000-8000-000000000501'::uuid),
    ('b7e00000-0000-4000-8000-000000000022'::uuid, 'received', 'b7e00000-0000-4000-8000-000000000502'::uuid),
    ('b7e00000-0000-4000-8000-000000000023'::uuid, 'quote_ready', 'b7e00000-0000-4000-8000-000000000503'::uuid),
    ('b7e00000-0000-4000-8000-000000000024'::uuid, 'ready', 'b7e00000-0000-4000-8000-000000000504'::uuid),
    ('b7e00000-0000-4000-8000-000000000025'::uuid, 'delivered', 'b7e00000-0000-4000-8000-000000000403'::uuid))
    as source(job_id, kind, source_id);
insert into botones_notice
  select notice.job_id, notice.kind, notice.id from public.workshop_customer_notices notice
   where notice.tenant_id = 'b7e00000-0000-4000-8000-000000000001' and notice.channel = 'whatsapp';

-- ---------------------------------------------------------------------------
-- Mientras Meta revisa las nuevas, salen las de antes
-- ---------------------------------------------------------------------------

select is(public.record_whatsapp_template_reviews_v1('b7e00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'PENDING'),
    jsonb_build_object('name', 'taller_presupuesto_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_presupuesto_v2', 'language', 'es_CL', 'status', 'PENDING'),
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'PENDING'),
    jsonb_build_object('name', 'taller_entregada_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_entregada_v2', 'language', 'es_CL', 'status', 'PENDING'),
    jsonb_build_object('name', 'resena_google_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'resena_google_v2', 'language', 'es_CL', 'status', 'PENDING'))),
  10, 'Meta has the new ones in review');

select is(
  (select string_agg(kind || ':' || public.workshop_notice_template_internal(
      'b7e00000-0000-4000-8000-000000000001', kind, 'bike'), ' | ' order by kind)
     from (values ('received'), ('quote_ready'), ('ready'), ('delivered')) as moment(kind)),
  'delivered:taller_entregada_v1 | quote_ready:taller_presupuesto_v1 | ready:taller_lista_v1 | received:taller_recibida_v1',
  'while the new ones are in review every notice keeps its approved v1');

-- Aprobadas.
select is(public.record_whatsapp_template_reviews_v1('b7e00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_presupuesto_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_presupuesto_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_entregada_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_entregada_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'resena_google_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'resena_google_v2', 'language', 'es_CL', 'status', 'APPROVED'))),
  10, 'Meta approved the new ones');
select is(public.record_whatsapp_template_reviews_v1('b7e00000-0000-4000-8000-000000000002', jsonb_build_array(
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'APPROVED'))),
  2, 'the other shop has both ready templates approved');

select is(
  (select string_agg(kind || ':' || public.workshop_notice_template_internal(
      'b7e00000-0000-4000-8000-000000000001', kind, 'bike'), ' | ' order by kind)
     from (values ('received'), ('quote_ready'), ('ready'), ('delivered')) as moment(kind)),
  'delivered:taller_entregada_v2 | quote_ready:taller_presupuesto_v2 | ready:taller_lista_v2 | received:taller_recibida_v2',
  'once approved every notice goes with its button');
select is(public.workshop_notice_template_internal('b7e00000-0000-4000-8000-000000000002', 'ready', 'bike'),
  'taller_lista_v1', 'a shop without its point on the map keeps the ready notice without a map');

-- ---------------------------------------------------------------------------
-- El envío con botón
-- ---------------------------------------------------------------------------

select is(public.workshop_notice_dispatch_whatsapp_internal(notice_id, '2026-11-07 12:00:00-03', true), 'sent',
  'the ' || kind || ' notice of ' || job_id || ' goes out')
  from botones_notice order by kind, job_id;

create temporary table botones_sent on commit drop as
  select notice.job_id, notice.kind, notice.template_name, outbox.request, message.content
    from botones_notice b
    join public.workshop_customer_notices notice on notice.id = b.notice_id
    join public.whatsapp_outbox outbox on outbox.message_id = notice.message_id
    join public.messages message on message.id = notice.message_id;

select is((select string_agg(kind || ':' || template_name, ' | ' order by kind, job_id) from botones_sent),
  'delivered:taller_entregada_v2 | quote_ready:taller_presupuesto_v2 | ready:taller_lista_v2 | received:taller_recibida_v2 | received:taller_recibida_v2',
  'each notice is recorded with the template it went with');

-- Recibida: cuerpo de tres parámetros y el botón con un código de cuenta.
select is((select content from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000021'),
  'Hola Camila Torres Soto, recibimos tu Trek Marlin 7. Tu número de trabajo es PG-R1 y te avisaremos por aquí cuando esté listo.',
  'the inbox keeps the approved body, with no link in it');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type')
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000021'),
  '["body", "button"]'::jsonb, 'the received notice is a body and its link button');
select is((select request #> '{templateComponents,0,parameters}'
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000021'),
  '[{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "Trek Marlin 7"}, {"type": "text", "text": "PG-R1"}]'::jsonb,
  'the body carries the name, the bike and the job number (the sender shortens the name)');
select is((select (request #>> '{templateComponents,1,sub_type}') || '|' || (request #>> '{templateComponents,1,index}')
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000021'),
  'url|0', 'the button parameter is the suffix of the first link button');
select matches((select request #>> '{templateComponents,1,parameters,0,text}'
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000021'),
  '^[A-Za-z0-9_-]{43}$', 'the suffix is a 43-character code that needs no encoding');
select is((select count(*)::integer from public.customer_portal_claim_codes code
    join botones_sent sent on sent.job_id = code.job_id
   where sent.job_id = 'b7e00000-0000-4000-8000-000000000021'
     and code.purpose = 'reception'
     and code.customer_id = 'b7e00000-0000-4000-8000-000000000011'
     and code.code_sha256 = encode(extensions.digest(convert_to(
           sent.request #>> '{templateComponents,1,parameters,0,text}', 'UTF8'), 'sha256'), 'hex')), 1,
  'the code in the button is the fresh reception claim code of that customer');
select is((select count(*)::integer from public.customer_portal_claim_codes
   where job_id = 'b7e00000-0000-4000-8000-000000000022' and purpose = 'reception'
     and customer_id = 'b7e00000-0000-4000-8000-000000000013'), 1,
  'a customer who already has an account also gets a code: the page sends them to sign in');

-- Presupuesto: dos parámetros y el botón.
select is((select content from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000023'),
  'Hola Camila Torres Soto, el presupuesto de tu trabajo PG-Q1 está listo. Revísalo y respóndenos por aquí para aprobarlo o hacer una consulta.',
  'the quote notice says it is ready and how to answer');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type')
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000023'),
  '["body", "button"]'::jsonb, 'the quote notice is a body and its button');

-- Lista: el mapa arriba, el horario en el texto y el botón.
select is((select content from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000024'),
  'Hola Camila Torres Soto, tu trabajo PG-L1 está listo para retirar. Te esperamos de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30. Si necesitas coordinar el retiro, respóndenos por aquí.',
  'the ready notice says when to come by');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type')
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000024'),
  '["header", "body", "button"]'::jsonb, 'the ready notice is the map, the body and the button');
select is((select request #> '{templateComponents,0,parameters,0}'
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000024'),
  '{"type": "location", "location": {"latitude": "-33.025195", "longitude": "-71.562306", "name": "Taller Botones", "address": "Calle Uno 123, Local 4, Viña del Mar"}}'::jsonb,
  'the map header carries the shop''s point, name and address');

-- Entregada: la garantía en el texto y el botón con un código de entrega.
select is((select content from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000025'),
  'Hola Camila Torres Soto, tu trabajo PG-E1 quedó entregado. La garantía del servicio vale hasta el 21 de noviembre. Gracias por confiar en Viñabike.',
  'the delivery notice says until when the service is covered');
select is((select count(*)::integer from public.customer_portal_claim_codes
   where job_id = 'b7e00000-0000-4000-8000-000000000025' and purpose = 'delivery'), 1,
  'the delivery button carries a delivery claim code');
select is((select request #>> '{metadata,template_purpose}' || '|' || (request #>> '{metadata,source}')
             from botones_sent where job_id = 'b7e00000-0000-4000-8000-000000000025'),
  'workshop_delivered|workshop_notice', 'the sender still shortens the name to the given name');
select is(current_setting('request.jwt.claim.sub', true), '',
  'the dispatch does not leave the sending person as the session');

-- ---------------------------------------------------------------------------
-- El pedido de reseña con botón
-- ---------------------------------------------------------------------------

select is(public.process_whatsapp_review_requests_v1('2026-11-07 15:00:00-03') ->> 'sent', '1',
  'the delivered bike gets its review request');
select is((select m.content from public.whatsapp_review_requests r
    join public.messages m on m.id = r.message_id
   where r.job_id = 'b7e00000-0000-4000-8000-000000000025'),
  'Hola Camila Torres Soto, gracias por elegir Viñabike. Si te gustó el servicio, una reseña en Google nos ayuda mucho.',
  'the review request text has no link in it');
select is((select o.request->'templateComponents' from public.whatsapp_review_requests r
    join public.whatsapp_outbox o on o.message_id = r.message_id
   where r.job_id = 'b7e00000-0000-4000-8000-000000000025'),
  '[{"type": "body", "parameters": [{"type": "text", "text": "Camila Torres Soto"}]}, {"type": "button", "sub_type": "url", "index": "0", "parameters": [{"type": "text", "text": "ChIJbotonesDePrueba_1-x"}]}]'::jsonb,
  'the review button carries the Google place as its suffix');
select is((select o.request->>'templateName' from public.whatsapp_review_requests r
    join public.whatsapp_outbox o on o.message_id = r.message_id
   where r.job_id = 'b7e00000-0000-4000-8000-000000000025'),
  'resena_google_v2', 'the review request goes with the button template once approved');

-- ---------------------------------------------------------------------------
-- Cerradas
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('authenticated', 'public.workshop_notice_hours_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_hours_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_location_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_location_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE'),
  'the helpers are closed to every caller role');

select * from finish();
rollback;
