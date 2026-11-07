begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Los avisos del taller salen sólo con plantillas que Meta deja como de
-- servicio, `taller_lista_v3` lleva el mapa con palabras de retiro, y la
-- página de avisos ve todas las plantillas del taller (20261107140000). Todo
-- es sintético, a horas fijas del 7 de noviembre de 2026 (Chile, -03) y se
-- deshace al final; el despacho real a Meta queda apagado en la transacción.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('b7e10000-0000-4000-8000-000000000001', 'Servicio A', 'servicio-a@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('b7e10000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-servicio@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id = 'b7e10000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('b7e10000-0000-4000-8000-000000000091', 'b7e10000-0000-4000-8000-000000000001', 'admin', '{}', true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('b7e10000-0000-4000-8000-000000000131', 'b7e10000-0000-4000-8000-000000000001',
   'servicio-test-a', 'Sintético servicio', true);

insert into public.website_settings (tenant_id, key, value) values
  ('b7e10000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-servicio.example.invalid'),
  ('b7e10000-0000-4000-8000-000000000001', 'store_name', 'Taller Servicio'),
  ('b7e10000-0000-4000-8000-000000000001', 'contact_address', 'Calle Uno 123, Viña del Mar, Chile'),
  ('b7e10000-0000-4000-8000-000000000001', 'seo_geo_latitude', '-33.025195'),
  ('b7e10000-0000-4000-8000-000000000001', 'seo_geo_longitude', '-71.562306'),
  ('b7e10000-0000-4000-8000-000000000001', 'business_hours_json', jsonb_build_object(
    'periods', jsonb_build_array(
      jsonb_build_object('open', jsonb_build_object('day', 1, 'time', '1030'), 'close', jsonb_build_object('day', 1, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 2, 'time', '1030'), 'close', jsonb_build_object('day', 2, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 3, 'time', '1030'), 'close', jsonb_build_object('day', 3, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 4, 'time', '1030'), 'close', jsonb_build_object('day', 4, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 5, 'time', '1030'), 'close', jsonb_build_object('day', 5, 'time', '1900')),
      jsonb_build_object('open', jsonb_build_object('day', 6, 'time', '1030'), 'close', jsonb_build_object('day', 6, 'time', '1530'))))::text);

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('b7e10000-0000-4000-8000-000000000011', 'b7e10000-0000-4000-8000-000000000001',
   'Camila Torres Soto', '+56 9 1212 3434', null, null, true);

set local session_replication_role = replica;
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, job_type,
  workflow_kind, intake_kind, status, approved_by_customer, client_request, total_cost, created_by) values
  -- L1: la bici de Camila está lista.
  ('b7e10000-0000-4000-8000-000000000024', 'b7e10000-0000-4000-8000-000000000001',
   'b7e10000-0000-4000-8000-000000000011', null, 'PG-L1',
   'service', 'service', 'bike', 'FINALIZADO', false, null, 0,
   'b7e10000-0000-4000-8000-000000000091');
set local session_replication_role = origin;

select is(public.workshop_notice_enqueue_internal('b7e10000-0000-4000-8000-000000000001',
  'b7e10000-0000-4000-8000-000000000024', 'ready', 'b7e10000-0000-4000-8000-000000000504',
  '2026-11-07 10:00:00-03', 'b7e10000-0000-4000-8000-000000000091', false, true), 1,
  'the ready notice is noted for WhatsApp');

-- ---------------------------------------------------------------------------
-- Una plantilla que Meta deja como publicidad no es un aviso
-- ---------------------------------------------------------------------------

select is(public.record_whatsapp_template_reviews_v1('b7e10000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'MARKETING'),
    jsonb_build_object('name', 'taller_lista_v3', 'language', 'es_CL', 'status', 'PENDING', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'seguimiento_servicio_bicicleta', 'language', 'es_CL', 'status', 'APPROVED',
      'category', 'UTILITY'))),
  5, 'Meta approved the map version as marketing and has the v3 in review');

select is(public.workshop_notice_template_internal('b7e10000-0000-4000-8000-000000000001', 'ready', 'bike'),
  'taller_lista_v1', 'an approved template that Meta keeps as marketing is never a workshop notice');
select is(public.workshop_notice_template_internal('b7e10000-0000-4000-8000-000000000001', 'received', 'bike'),
  'taller_recibida_v2', 'a review without a category still counts as approved');

select is(public.record_whatsapp_template_reviews_v1('b7e10000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'MARKETING'),
    jsonb_build_object('name', 'taller_lista_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'MARKETING'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'seguimiento_servicio_bicicleta', 'language', 'es_CL', 'status', 'APPROVED',
      'category', 'UTILITY'))),
  5, 'Meta also files the v3 as marketing');
select is(public.workshop_notice_template_internal('b7e10000-0000-4000-8000-000000000001', 'ready', 'bike'),
  'taller_lista_v1', 'then the ready notice keeps the approved utility v1');

select is(public.record_whatsapp_template_reviews_v1('b7e10000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_lista_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_lista_v2', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'MARKETING'),
    jsonb_build_object('name', 'taller_lista_v3', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_recibida_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'seguimiento_servicio_bicicleta', 'language', 'es_CL', 'status', 'APPROVED',
      'category', 'UTILITY'))),
  5, 'Meta approves the v3 as utility');
select is(public.workshop_notice_template_internal('b7e10000-0000-4000-8000-000000000001', 'ready', 'bike'),
  'taller_lista_v3', 'the ready notice goes with the map once Meta approves the v3 as utility');

-- ---------------------------------------------------------------------------
-- El envío con la v3: el mapa, cuándo retirarla y el botón
-- ---------------------------------------------------------------------------

select is(public.workshop_notice_dispatch_whatsapp_internal(notice.id, '2026-11-07 12:00:00-03', true), 'sent',
  'the ready notice goes out')
  from public.workshop_customer_notices notice
 where notice.tenant_id = 'b7e10000-0000-4000-8000-000000000001'
   and notice.job_id = 'b7e10000-0000-4000-8000-000000000024'
   and notice.channel = 'whatsapp';

create temporary table servicio_sent on commit drop as
  select notice.template_name, outbox.request, message.content
    from public.workshop_customer_notices notice
    join public.whatsapp_outbox outbox on outbox.message_id = notice.message_id
    join public.messages message on message.id = notice.message_id
   where notice.tenant_id = 'b7e10000-0000-4000-8000-000000000001'
     and notice.job_id = 'b7e10000-0000-4000-8000-000000000024'
     and notice.channel = 'whatsapp';

select is((select template_name from servicio_sent), 'taller_lista_v3',
  'the notice is recorded with the v3');
select is((select content from servicio_sent),
  'Hola Camila Torres Soto, tu trabajo PG-L1 está listo. Puedes retirarlo de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30. Si necesitas coordinar el retiro, respóndenos por aquí.',
  'the inbox keeps the v3 text: when to pick it up, not an invitation');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type') from servicio_sent),
  '["header", "body", "button"]'::jsonb, 'the v3 is the map, the body and the account button');
select is((select request #> '{templateComponents,0,parameters,0}' from servicio_sent),
  '{"type": "location", "location": {"latitude": "-33.025195", "longitude": "-71.562306", "name": "Taller Servicio", "address": "Calle Uno 123, Viña del Mar"}}'::jsonb,
  'the map header carries the shop''s point, name and address');
select is((select request #> '{templateComponents,1,parameters}' from servicio_sent),
  '[{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "PG-L1"}, {"type": "text", "text": "de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30"}]'::jsonb,
  'the body carries the name, the job number and the hours');
select matches((select request #>> '{templateComponents,2,parameters,0,text}' from servicio_sent),
  '^[A-Za-z0-9_-]{43}$', 'the button carries the account code');
select is((select request #>> '{metadata,message_category}' from servicio_sent), 'utility',
  'the notice is a utility message');

-- ---------------------------------------------------------------------------
-- La página de avisos ve todas las plantillas del taller
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'b7e10000-0000-4000-8000-000000000091', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', 'b7e10000-0000-4000-8000-000000000091', true);
select is(
  (select string_agg((item->>'name') || ':' || (item->>'status') || ':' || coalesce(item->>'category', '-'),
                     ' | ' order by item->>'name')
     from jsonb_array_elements(
       public.workshop_customer_notice_overview_v1('b7e10000-0000-4000-8000-000000000001')->'templates') item),
  'taller_lista_v1:APPROVED:UTILITY | taller_lista_v2:APPROVED:MARKETING | taller_lista_v3:APPROVED:UTILITY | taller_recibida_v2:APPROVED:-',
  'the notices page reads every workshop template with its category, and no other template');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- Cerrada
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE'),
  'the helper is closed to every caller role');

select * from finish();
rollback;
