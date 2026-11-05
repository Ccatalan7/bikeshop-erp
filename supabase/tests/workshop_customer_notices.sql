begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Avisos del taller al cliente (20261105130000): recibida, presupuesto listo,
-- lista para retirar y entregada, por correo y por WhatsApp. Todo es
-- sintético, a horas fijas del 5 de noviembre de 2026 (Chile, -03) y se deshace
-- al final; el despacho real a Meta queda apagado en la transacción.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a5e00000-0000-4000-8000-000000000001', 'Avisos A', 'avisos-a@example.invalid', 'America/Santiago', true),
  ('a5e00000-0000-4000-8000-000000000002', 'Avisos B', 'avisos-b@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a5e00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-a@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('a5e00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'equipo-b@example.invalid', '', now(), '{}', '{}', now(), now()),
  -- La cuenta de Ana en la tienda A.
  ('a5e00000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'ana@example.invalid', '', now(), '{}', '{}', now(), now()),
  -- Una cuenta sin ficha.
  ('a5e00000-0000-4000-8000-000000000094', 'authenticated', 'authenticated',
   'nadie@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id in (
  'a5e00000-0000-4000-8000-000000000091', 'a5e00000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a5e00000-0000-4000-8000-000000000091', 'a5e00000-0000-4000-8000-000000000001', 'admin', '{}', true),
  ('a5e00000-0000-4000-8000-000000000092', 'a5e00000-0000-4000-8000-000000000002', 'admin', '{}', true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('a5e00000-0000-4000-8000-000000000131', 'a5e00000-0000-4000-8000-000000000001', 'avisos-test-a', 'Sintético A', true),
  ('a5e00000-0000-4000-8000-000000000132', 'a5e00000-0000-4000-8000-000000000002', 'avisos-test-b', 'Sintético B', true);

insert into public.transactional_email_settings (
  tenant_id, enabled, delivery_mode, from_name, from_email, reply_to_email, public_store_url
) values (
  'a5e00000-0000-4000-8000-000000000001', true, 'send', 'Avisos A',
  'taller@tienda-a.example.invalid', 'hola@tienda-a.example.invalid', 'https://tienda-a.example.invalid'
);
insert into public.website_settings (tenant_id, key, value) values
  ('a5e00000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-a.example.invalid/');

-- La tienda A los encendió a las 06:00; la B nunca.
insert into public.company_settings (tenant_id, key, value) values
  ('a5e00000-0000-4000-8000-000000000001', 'workshop_notices_started_at', '2026-11-05T09:00:00Z');

-- Lo que Meta dijo: la recepción y la entrega aprobadas; el presupuesto del
-- taller en revisión (sale con la de antes); la bici lista del taller todavía
-- no existe (una bici sale con la de antes; un componente espera).
select is(
  public.record_whatsapp_template_reviews_v1('a5e00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v1', 'language', 'es_CL', 'status', 'APPROVED', 'category', 'UTILITY'),
    jsonb_build_object('name', 'taller_presupuesto_v1', 'language', 'es_CL', 'status', 'PENDING'),
    jsonb_build_object('name', 'taller_entregada_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'seguimiento_presupuesto_bicicleta', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'bicicleta_lista_retiro', 'language', 'es_CL', 'status', 'approved'),
    jsonb_build_object('name', 'Nombre Malo', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'resena_google_v1', 'language', 'es_CL', 'status', 'REJECTED', 'rejected_reason', 'NONE'))),
  6, 'Meta''s list is recorded; a malformed name is ignored');
select is((select status from public.whatsapp_template_reviews
  where tenant_id = 'a5e00000-0000-4000-8000-000000000001' and template_name = 'bicicleta_lista_retiro'),
  'APPROVED', 'the status is kept upper-case whatever Meta wrote');
select is((select rejected_reason from public.whatsapp_template_reviews
  where tenant_id = 'a5e00000-0000-4000-8000-000000000001' and template_name = 'resena_google_v1'),
  null, 'Meta''s NONE is not a rejection reason');

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('a5e00000-0000-4000-8000-000000000011', 'a5e00000-0000-4000-8000-000000000001',
   'María José Rojas Pérez', '+56 9 1111 2222', 'Maria.Rojas@Example.invalid', null, true),
  ('a5e00000-0000-4000-8000-000000000012', 'a5e00000-0000-4000-8000-000000000001',
   'Pedro Sin Correo', '+56 9 3333 4444', null, null, true),
  ('a5e00000-0000-4000-8000-000000000013', 'a5e00000-0000-4000-8000-000000000001',
   'Ana Con Cuenta', '+56 9 5555 6666', 'ana@example.invalid',
   'a5e00000-0000-4000-8000-000000000093', true),
  ('a5e00000-0000-4000-8000-000000000014', 'a5e00000-0000-4000-8000-000000000002',
   'Cliente Tienda B', '+56 9 7777 8888', 'b@example.invalid', null, true);

-- Ana no quiere WhatsApp.
insert into public.customer_workshop_notice_preferences (tenant_id, customer_id, email_enabled, whatsapp_enabled)
values ('a5e00000-0000-4000-8000-000000000001', 'a5e00000-0000-4000-8000-000000000013', true, false);

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('a5e00000-0000-4000-8000-000000000041', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', 'Trek', 'Marlin 7');

-- Trabajos sembrados sin pasar por sus comandos, cada uno ya en el estado
-- de su caso; lo que pasó (creación, cambios de estado, entrega) se siembra
-- después a horas fijas.
set local session_replication_role = replica;
insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, job_type,
  workflow_kind, intake_kind, status, approved_by_customer, client_request, total_cost, created_by) values
  -- N1: recibida a las 11:00, María José, con su bici.
  ('a5e00000-0000-4000-8000-000000000021', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', 'a5e00000-0000-4000-8000-000000000041', 'PG-N1',
   'service', 'service', 'bike', 'PENDIENTE', false, 'Mantención general', 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N2: presupuesto listo a las 11:00 para Pedro, que no dejó correo.
  ('a5e00000-0000-4000-8000-000000000022', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000012', null, 'PG-N2',
   'service', 'service', 'bike', 'ESPERANDO_APROBACION', false, 'Ruido en el pedalier', 45990,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N3: lista a las 11:45, retirada a las 11:50.
  ('a5e00000-0000-4000-8000-000000000023', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', null, 'PG-N3',
   'service', 'service', 'bike', 'ENTREGADO', false, 'Cambio de cadena', 18000,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N4: recibida a las 11:30 para Ana, que tiene cuenta y no quiere WhatsApp.
  ('a5e00000-0000-4000-8000-000000000024', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000013', null, 'PG-N4',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N5: una cotización suelta: no es una bici en el taller.
  ('a5e00000-0000-4000-8000-000000000025', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', null, 'PG-N5',
   'quotation', 'quotation', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N6: creada a las 05:00, antes de encenderlos.
  ('a5e00000-0000-4000-8000-000000000026', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', null, 'PG-N6',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N7: recibida a las 11:59: su espera termina a las 12:01.
  ('a5e00000-0000-4000-8000-000000000027', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', null, 'PG-N7',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N8: una bici lista a las 11:00 para Pedro.
  ('a5e00000-0000-4000-8000-000000000028', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000012', null, 'PG-N8',
   'service', 'service', 'bike', 'FINALIZADO', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N9: un componente listo a las 11:00 para Pedro.
  ('a5e00000-0000-4000-8000-000000000029', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000012', null, 'PG-N9',
   'item_service', 'service', 'component', 'FINALIZADO', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- N10: recibida a las 20:58: de noche no sale y a la mañana ya venció.
  ('a5e00000-0000-4000-8000-000000000030', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000012', null, 'PG-N10',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000091'),
  -- B1: de la tienda que no los encendió.
  ('a5e00000-0000-4000-8000-000000000031', 'a5e00000-0000-4000-8000-000000000002',
   'a5e00000-0000-4000-8000-000000000014', null, 'PG-B1',
   'service', 'service', 'bike', 'PENDIENTE', false, null, 0,
   'a5e00000-0000-4000-8000-000000000092');

insert into public.mechanic_job_creations (id, tenant_id, operation_key, payload_hash, job_id,
  result_snapshot, created_by, completed_at) values
  ('a5e00000-0000-4000-8000-000000000201', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n1', 'h1',
   'a5e00000-0000-4000-8000-000000000021', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 11:00:00-03'),
  ('a5e00000-0000-4000-8000-000000000204', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n4', 'h4',
   'a5e00000-0000-4000-8000-000000000024', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 11:30:00-03'),
  ('a5e00000-0000-4000-8000-000000000205', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n5', 'h5',
   'a5e00000-0000-4000-8000-000000000025', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 11:00:00-03'),
  ('a5e00000-0000-4000-8000-000000000206', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n6', 'h6',
   'a5e00000-0000-4000-8000-000000000026', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 05:00:00-03'),
  ('a5e00000-0000-4000-8000-000000000207', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n7', 'h7',
   'a5e00000-0000-4000-8000-000000000027', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 11:59:00-03'),
  ('a5e00000-0000-4000-8000-000000000210', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n10', 'h10',
   'a5e00000-0000-4000-8000-000000000030', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-05 20:58:00-03'),
  ('a5e00000-0000-4000-8000-000000000211', 'a5e00000-0000-4000-8000-000000000002', 'avisos-b1', 'hb1',
   'a5e00000-0000-4000-8000-000000000031', '{}', 'a5e00000-0000-4000-8000-000000000092', '2026-11-05 11:00:00-03');

insert into public.mechanic_job_status_transitions (id, tenant_id, job_id, occurred_at, from_status,
  to_status, to_phase, to_triggers_completion, to_triggers_delivery, actor_user_id) values
  ('a5e00000-0000-4000-8000-000000000302', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000022', '2026-11-05 11:00:00-03', 'DIAGNOSTICO',
   'ESPERANDO_APROBACION', 'in_progress', false, false, 'a5e00000-0000-4000-8000-000000000091'),
  ('a5e00000-0000-4000-8000-000000000303', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000023', '2026-11-05 11:45:00-03', 'EN_CURSO',
   'FINALIZADO', 'complete', true, false, 'a5e00000-0000-4000-8000-000000000091'),
  ('a5e00000-0000-4000-8000-000000000313', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000023', '2026-11-05 11:50:00-03', 'FINALIZADO',
   'ENTREGADO', 'complete', false, true, 'a5e00000-0000-4000-8000-000000000091'),
  ('a5e00000-0000-4000-8000-000000000308', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000028', '2026-11-05 11:00:00-03', 'EN_CURSO',
   'FINALIZADO', 'complete', true, false, 'a5e00000-0000-4000-8000-000000000091'),
  ('a5e00000-0000-4000-8000-000000000309', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000029', '2026-11-05 11:00:00-03', 'EN_CURSO',
   'FINALIZADO', 'complete', true, false, 'a5e00000-0000-4000-8000-000000000091'),
  -- Un trabajo que pasa de lista a probada no avisa otra vez.
  ('a5e00000-0000-4000-8000-000000000318', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000028', '2026-11-05 11:05:00-03', 'FINALIZADO',
   'PROBADO', 'complete', false, false, 'a5e00000-0000-4000-8000-000000000091');

insert into public.mechanic_job_delivery_events (id, tenant_id, job_id, event_kind, occurred_at,
  recorded_at, actor_id, source, operation_key) values
  ('a5e00000-0000-4000-8000-000000000403', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000023', 'delivered', '2026-11-05 11:50:00-03',
   '2026-11-05 11:50:00-03', 'a5e00000-0000-4000-8000-000000000091', 'status_transition', 'avisos-n3-delivered');

insert into public.mechanic_job_delivery_documents (tenant_id, job_id, delivery_event_id, job_number,
  delivered_at, service_warranty_days, service_warranty_expires_at, parts_warranty_months,
  parts_warranty_expires_at, snapshot) values
  ('a5e00000-0000-4000-8000-000000000001', 'a5e00000-0000-4000-8000-000000000023',
   'a5e00000-0000-4000-8000-000000000403', 'PG-N3', '2026-11-05 11:50:00-03',
   14, '2026-11-19 11:50:00-03', 2, '2027-01-05 11:50:00-03',
   jsonb_build_object('work_performed', 'Cambio de cadena y ajuste de cambios',
     'lines', jsonb_build_array(
       jsonb_build_object('kind', 'service', 'name', 'Ajuste de cambios'),
       jsonb_build_object('kind', 'part', 'name', 'Cadena KMC X11'))));
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- La pasada de mediodía
-- ---------------------------------------------------------------------------

select is(
  public.process_workshop_customer_notices_v1('2026-11-05 12:00:00-03'),
  '{"created": 16, "whatsapp_sent": 4, "skipped": 1, "waiting": 1, "in_hours": true}'::jsonb,
  'the noon pass notes every moment once per channel and sends the WhatsApps that are due');

select is((select count(*)::integer from public.workshop_customer_notices
  where job_id in ('a5e00000-0000-4000-8000-000000000025', 'a5e00000-0000-4000-8000-000000000026')), 0,
  'a standalone quotation and a job created before the switch notice nothing');
select is((select count(*)::integer from public.workshop_customer_notices
  where tenant_id = 'a5e00000-0000-4000-8000-000000000002'), 0,
  'a shop that never switched them on notices nothing');
select is((select count(*)::integer from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000028' and kind = 'ready'), 2,
  'ready and then tested is still one ready notice per channel');

select is((select string_agg(channel || ':' || state || ':' || coalesce(reason, '') || ':' || coalesce(template_name, ''), ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000021'),
  'email:pending:: | whatsapp:sent::taller_recibida_v1',
  'a received bike: the e-mail waits for its worker and the WhatsApp goes with the approved workshop template');
select is((select string_agg(channel || ':' || state || ':' || coalesce(reason, '') || ':' || coalesce(template_name, ''), ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000022'),
  'email:skipped:no_email: | whatsapp:sent::seguimiento_presupuesto_bicicleta',
  'a ready quote without e-mail is skipped there and goes by the older approved template while the new one is in review');
select is((select string_agg(kind || '/' || channel || ':' || state || ':' || coalesce(reason, '') || ':' || coalesce(template_name, ''), ' | ' order by kind, channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000023'),
  'delivered/email:pending:: | delivered/whatsapp:sent::taller_entregada_v1 | ready/email:pending:: | ready/whatsapp:skipped:already_delivered:',
  'a bike picked up before its ready notice is due gets only the delivery notice');
select is((select string_agg(channel || ':' || state || ':' || coalesce(reason, ''), ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000024'),
  'email:pending: | whatsapp:skipped:customer_opted_out',
  'the channel the customer turned off is skipped');
select is((select string_agg(channel || ':' || state || ':' || coalesce(template_name, ''), ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000028'),
  'email:skipped: | whatsapp:sent:bicicleta_lista_retiro',
  'a ready bike goes by the older approved template');
select is((select string_agg(channel || ':' || state, ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000029'),
  'email:skipped | whatsapp:pending',
  'a ready component waits: «tu bicicleta está lista» would be wrong and the workshop template is not approved yet');
select is((select string_agg(channel || ':' || state, ' | ' order by channel)
    from public.workshop_customer_notices where job_id = 'a5e00000-0000-4000-8000-000000000027'),
  'email:pending | whatsapp:pending',
  'a notice still in its waiting minutes stays pending');
select is((select recipient from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000021' and channel = 'email'),
  'maria.rojas@example.invalid', 'the e-mail recipient is normalized');

-- El WhatsApp de la recepción: la cola durable, a nombre de quien creó el
-- trabajo, en la conversación del cliente y con el enlace para crear la cuenta.
select is((select o.request->>'templateName' || '|' || (o.request #>> '{metadata,template_purpose}')
             || '|' || o.actor_id::text || '|' || o.state
     from public.whatsapp_outbox o
     join public.workshop_customer_notices n on n.message_id = o.message_id
    where n.job_id = 'a5e00000-0000-4000-8000-000000000021' and n.channel = 'whatsapp'),
  'taller_recibida_v1|workshop_received|a5e00000-0000-4000-8000-000000000091|queued',
  'the received notice rides the durable outbox as the person who created the job');
select matches((select m.content from public.messages m
     join public.workshop_customer_notices n on n.message_id = m.id
    where n.job_id = 'a5e00000-0000-4000-8000-000000000021' and n.channel = 'whatsapp'),
  '^Hola María José Rojas Pérez, recibimos tu Trek Marlin 7 en Viñabike\. Tu número de trabajo es PG-N1 y aquí puedes seguir su estado: https://tienda-a\.example\.invalid/cuenta/vincular#c=[A-Za-z0-9_-]{43} Te avisaremos por este medio cuando esté listo\.$',
  'the inbox keeps the exact text (the sender shortens the name to the given name): the bike, the job number and the link to create the account');
select is((select count(*)::integer from public.customer_portal_claim_codes
  where job_id = 'a5e00000-0000-4000-8000-000000000021' and purpose = 'reception'
    and customer_id = 'a5e00000-0000-4000-8000-000000000011' and claimed_at is null), 1,
  'the link carries a fresh reception claim code for that customer');
select is((select b.customer_id::text from public.whatsapp_conversation_bindings b
     join public.workshop_customer_notices n on n.tenant_id = b.tenant_id
     join public.messages m on m.id = n.message_id and m.conversation_id = b.conversation_id
    where n.job_id = 'a5e00000-0000-4000-8000-000000000021' and n.channel = 'whatsapp'),
  'a5e00000-0000-4000-8000-000000000011',
  'the message lands in the customer''s own conversation');
select matches((select m.content from public.messages m
     join public.workshop_customer_notices n on n.message_id = m.id
    where n.job_id = 'a5e00000-0000-4000-8000-000000000023' and n.kind = 'delivered'),
  '^Hola María José Rojas Pérez, gracias por retirar tu trabajo PG-N3\. La garantía del servicio vale hasta el 19 de noviembre y tu comprobante está aquí: https://tienda-a\.example\.invalid/cuenta/vincular#c=[A-Za-z0-9_-]{43} Gracias por confiar en Viñabike\.$',
  'the delivery notice says until when the service is covered and links the receipt');
select is((select count(*)::integer from public.customer_portal_claim_codes
  where job_id = 'a5e00000-0000-4000-8000-000000000023' and purpose = 'delivery'), 1,
  'the delivery link is a delivery claim code');
select is(current_setting('request.jwt.claim.sub', true), '',
  'the pass does not leave the sending person as the session');

-- ---------------------------------------------------------------------------
-- Una pasada después: nada se repite y lo que esperaba sale
-- ---------------------------------------------------------------------------

select is(
  public.process_workshop_customer_notices_v1('2026-11-05 12:01:00-03'),
  '{"created": 0, "whatsapp_sent": 1, "skipped": 0, "waiting": 1, "in_hours": true}'::jsonb,
  'a second pass notes nothing again and sends the one whose minutes ran out');
select is((select count(*)::integer from public.whatsapp_outbox o
     join public.messages m on m.id = o.message_id
    where m.tenant_id = 'a5e00000-0000-4000-8000-000000000001'
      and o.request #>> '{metadata,source}' = 'workshop_notice'), 5,
  'exactly five WhatsApp notices were queued for the shop');

-- ---------------------------------------------------------------------------
-- El correo
-- ---------------------------------------------------------------------------

select is(jsonb_array_length(public.claim_workshop_customer_notices_v1(
  'a5e00000-0000-4000-8000-000000000001', 'worker-1', 10, '2026-11-05 12:02:00-03')), 4,
  'the worker takes the four e-mails that still make sense');
select is((select state || ':' || reason from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000023' and kind = 'ready' and channel = 'email'),
  'skipped:already_delivered', 'the ready e-mail of a bike already picked up is skipped at claim time');

-- El contenido de cada correo, reclamado otra vez con su arrendamiento vencido.
update public.workshop_customer_notices
   set lease_until = clock_timestamp() - interval '1 second'
 where tenant_id = 'a5e00000-0000-4000-8000-000000000001' and state = 'sending';
create temporary table claimed_notices on commit drop as
  select value as payload from jsonb_array_elements(public.claim_workshop_customer_notices_v1(
    'a5e00000-0000-4000-8000-000000000001', 'worker-2', 10, '2026-11-05 12:03:00-03'));

select is((select count(*)::integer from claimed_notices), 4, 'an expired lease is claimed again');
select is((select payload #>> '{job,customerName}' || '|' || (payload #>> '{job,item}') || '|' || (payload->>'linkKind')
     from claimed_notices where payload->>'kind' = 'received' and payload #>> '{job,number}' = 'PG-N1'),
  'María José Rojas Pérez|Trek Marlin 7|claim',
  'the received e-mail knows the customer, the bike and links to create the account');
select matches((select payload->>'link' from claimed_notices where payload #>> '{job,number}' = 'PG-N1'),
  '^https://tienda-a\.example\.invalid/cuenta/vincular#c=[A-Za-z0-9_-]{43}$',
  'the e-mail link is a fresh claim link');
select is((select (payload->>'linkKind') || '|' || (payload->>'link')
     from claimed_notices where payload #>> '{job,number}' = 'PG-N4'),
  'portal|https://tienda-a.example.invalid/cuenta/servicios',
  'a customer who already has an account is sent to the workshop page of the portal');
select is((select (payload #>> '{delivery,serviceWarrantyUntil}')::timestamptz || '|' ||
                  (payload #>> '{delivery,partsWarrantyUntil}')::timestamptz || '|' ||
                  (payload #>> '{delivery,workPerformed}')
     from claimed_notices where payload->>'kind' = 'delivered'),
  ('2026-11-19 11:50:00-03'::timestamptz)::text || '|' || ('2027-01-05 11:50:00-03'::timestamptz)::text
    || '|Cambio de cadena y ajuste de cambios',
  'the delivery e-mail carries both warranties because parts were installed');
select is((select (payload #>> '{sender,enabled}') || '|' || (payload #>> '{sender,email}') || '|' ||
                  (payload->>'preferencesLink')
     from claimed_notices limit 1),
  'true|taller@tienda-a.example.invalid|https://tienda-a.example.invalid/cuenta/perfil',
  'the e-mail goes from the shop''s sender and says where to change the notices');

select is(public.complete_workshop_customer_notice_v1(
  (select (payload->>'noticeId')::uuid from claimed_notices where payload #>> '{job,number}' = 'PG-N1'),
  'worker-1', 'sent', 'resend-1'), 'not_leased',
  'a worker that lost its lease cannot close the notice');
select is(public.complete_workshop_customer_notice_v1(
  (select (payload->>'noticeId')::uuid from claimed_notices where payload #>> '{job,number}' = 'PG-N1'),
  'worker-2', 'sent', 'resend-1'), 'sent', 'the worker closes a sent e-mail');
select is(public.complete_workshop_customer_notice_v1(
  (select (payload->>'noticeId')::uuid from claimed_notices where payload #>> '{job,number}' = 'PG-N4'),
  'worker-2', 'retry', null, 'resend 503'), 'pending', 'a transient failure goes back to wait');
select ok((select available_at > clock_timestamp() from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000024' and channel = 'email'),
  'and waits a little before the next try');

-- ---------------------------------------------------------------------------
-- De noche y al día siguiente
-- ---------------------------------------------------------------------------

select is(
  public.process_workshop_customer_notices_v1('2026-11-05 21:05:00-03'),
  '{"created": 2, "whatsapp_sent": 0, "skipped": 0, "waiting": 2, "in_hours": false}'::jsonb,
  'at night the notices are noted but no WhatsApp goes out');
select is(
  public.process_workshop_customer_notices_v1('2026-11-06 09:05:00-03'),
  '{"created": 0, "whatsapp_sent": 0, "skipped": 1, "waiting": 1, "in_hours": true}'::jsonb,
  'in the morning a received notice from the night is too old to send');
select is((select state || ':' || reason from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000030' and channel = 'whatsapp'),
  'skipped:expired', 'it is skipped as expired');
select is(
  public.process_workshop_customer_notices_v1('2026-11-06 11:30:00-03'),
  '{"created": 0, "whatsapp_sent": 0, "skipped": 1, "waiting": 0, "in_hours": true}'::jsonb,
  'a notice that waited a whole day for its template gives up');
select is((select state || ':' || reason from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000029' and channel = 'whatsapp'),
  'skipped:template_not_approved', 'and says why');

-- ---------------------------------------------------------------------------
-- Las plantillas
-- ---------------------------------------------------------------------------

select ok(public.whatsapp_template_approved_internal('a5e00000-0000-4000-8000-000000000001', 'taller_recibida_v1'),
  'an approved template counts');
update public.whatsapp_template_reviews set checked_at = clock_timestamp() - interval '8 days'
 where tenant_id = 'a5e00000-0000-4000-8000-000000000001' and template_name = 'taller_recibida_v1';
select ok(not public.whatsapp_template_approved_internal('a5e00000-0000-4000-8000-000000000001', 'taller_recibida_v1'),
  'an approval nobody checked in a week does not count');
select is(public.record_whatsapp_template_reviews_v1('a5e00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_recibida_v1', 'language', 'es_CL', 'status', 'APPROVED'))), 1,
  'a fresh list is recorded');
select is((select count(*)::integer from public.whatsapp_template_reviews
  where tenant_id = 'a5e00000-0000-4000-8000-000000000001'), 1,
  'a template that left Meta''s list stops counting');
select ok(public.whatsapp_template_approved_internal('a5e00000-0000-4000-8000-000000000001', 'taller_recibida_v1'),
  'and the fresh check counts again');
select throws_ok(
  $$select public.record_whatsapp_template_reviews_v1('a5e00000-0000-4000-8000-000000000001', '{}'::jsonb)$$,
  '22023', 'A tenant and a template list are required', 'a list is required');

-- ---------------------------------------------------------------------------
-- Lo que elige el cliente en su cuenta
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5e00000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a5e00000-0000-4000-8000-000000000093', true);
select is(public.get_my_workshop_notice_preferences_v1('a5e00000-0000-4000-8000-000000000001'),
  '{"status": "linked", "email_enabled": true, "whatsapp_enabled": false, "has_email": true, "has_mobile": true}'::jsonb,
  'Ana sees what she chose and which contact data her record has');
select is(public.set_my_workshop_notice_preferences_v1('a5e00000-0000-4000-8000-000000000001', false, true)
    ->> 'whatsapp_enabled', 'true', 'Ana changes her mind');
select is(public.get_my_workshop_notice_preferences_v1('a5e00000-0000-4000-8000-000000000002'),
  '{"status": "not_linked"}'::jsonb, 'another shop has no record of Ana');
select is_empty($$select 1 from public.customer_workshop_notice_preferences$$,
  'a customer does not read the preferences table directly');
select set_config('request.jwt.claims', '{"sub":"a5e00000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a5e00000-0000-4000-8000-000000000094', true);
select throws_ok(
  $$select public.set_my_workshop_notice_preferences_v1('a5e00000-0000-4000-8000-000000000001', true, true)$$,
  '42501', 'workshop_notice_preferences_not_linked', 'an account without a record cannot choose for anybody');
select is_empty($$select 1 from public.workshop_customer_notices$$,
  'a customer account does not read the notices');
reset role;

select is((select email_enabled::text || '|' || whatsapp_enabled::text
     from public.customer_workshop_notice_preferences
    where customer_id = 'a5e00000-0000-4000-8000-000000000013'),
  'false|true', 'the choice is stored');

-- ---------------------------------------------------------------------------
-- Lo que ve y cambia el equipo
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a5e00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a5e00000-0000-4000-8000-000000000091', true);
select is((select count(*)::integer from public.workshop_customer_notices), 18,
  'the shop''s staff reads its notices');
select is((public.workshop_customer_notice_overview_v1('a5e00000-0000-4000-8000-000000000001')
    -> 'warranty'), '{"service_days": 14, "parts_months": 2}'::jsonb,
  'the overview shows the warranty in force');
select is((public.workshop_customer_notice_overview_v1('a5e00000-0000-4000-8000-000000000001')
    ->> 'can_edit'), 'true', 'and says an admin may change it');
select is((select sum((item->>'count')::integer)::integer
     from jsonb_array_elements(public.workshop_customer_notice_overview_v1(
       'a5e00000-0000-4000-8000-000000000001') -> 'counts') item
    where item->>'state' = 'sent'), 6,
  'and how many notices went out');
select is((public.update_workshop_customer_notice_settings_v1('a5e00000-0000-4000-8000-000000000001',
    '{"whatsapp_enabled": false, "service_warranty_days": 21, "parts_warranty_months": 3}'::jsonb)
    -> 'warranty'), '{"service_days": 21, "parts_months": 3}'::jsonb,
  'an admin changes the warranty');
select is((public.workshop_customer_notice_overview_v1('a5e00000-0000-4000-8000-000000000001')
    ->> 'whatsapp_switch'), 'false', 'and turns WhatsApp off');
select throws_ok(
  $$select public.update_workshop_customer_notice_settings_v1('a5e00000-0000-4000-8000-000000000001', '{"service_warranty_days": 400}'::jsonb)$$,
  '22023', 'workshop_notices_invalid', 'a warranty longer than a year is refused');
select throws_ok(
  $$select public.update_workshop_customer_notice_settings_v1('a5e00000-0000-4000-8000-000000000001', '{"email_enabled": "si"}'::jsonb)$$,
  '22023', 'workshop_notices_invalid', 'a switch is a boolean');

select set_config('request.jwt.claims', '{"sub":"a5e00000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a5e00000-0000-4000-8000-000000000092', true);
select is_empty($$select 1 from public.workshop_customer_notices where tenant_id = 'a5e00000-0000-4000-8000-000000000001'$$,
  'another shop''s staff reads none of them');
select throws_ok(
  $$select public.workshop_customer_notice_overview_v1('a5e00000-0000-4000-8000-000000000001')$$,
  '42501', 'workshop_notices_not_allowed', 'nor its overview');
select throws_ok(
  $$select public.update_workshop_customer_notice_settings_v1('a5e00000-0000-4000-8000-000000000001', '{"email_enabled": false}'::jsonb)$$,
  '42501', 'workshop_notices_not_allowed', 'nor changes its settings');
select is((public.workshop_customer_notice_overview_v1('a5e00000-0000-4000-8000-000000000002')
    ->> 'started_at'), null, 'a shop that never turned them on has no start');
select isnt((public.update_workshop_customer_notice_settings_v1('a5e00000-0000-4000-8000-000000000002',
    '{"email_enabled": true}'::jsonb) ->> 'started_at'), null,
  'turning them on from the card starts them from that moment');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Con WhatsApp apagado, un trabajo nuevo avisa sólo por correo.
set local session_replication_role = replica;
insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, created_by) values
  ('a5e00000-0000-4000-8000-000000000032', 'a5e00000-0000-4000-8000-000000000001',
   'a5e00000-0000-4000-8000-000000000011', 'PG-N11', 'service', 'service', 'bike', 'PENDIENTE',
   'a5e00000-0000-4000-8000-000000000091');
insert into public.mechanic_job_creations (id, tenant_id, operation_key, payload_hash, job_id,
  result_snapshot, created_by, completed_at) values
  ('a5e00000-0000-4000-8000-000000000212', 'a5e00000-0000-4000-8000-000000000001', 'avisos-n11', 'h11',
   'a5e00000-0000-4000-8000-000000000032', '{}', 'a5e00000-0000-4000-8000-000000000091', '2026-11-06 11:00:00-03');
set local session_replication_role = origin;
select is(
  (public.process_workshop_customer_notices_v1('2026-11-06 11:10:00-03') ->> 'created')::integer, 1,
  'with WhatsApp off a new job notes only its e-mail');
select is((select string_agg(channel, ',') from public.workshop_customer_notices
  where job_id = 'a5e00000-0000-4000-8000-000000000032'), 'email', 'by e-mail');

select is((select value from public.company_settings
  where tenant_id = 'a5e00000-0000-4000-8000-000000000001' and key = 'workshop_service_warranty_days'),
  '21', 'the warranty lives in the shop settings the delivery reads');
select is((select service_days || '/' || parts_months from public.workshop_warranty_policy_v1(
  'a5e00000-0000-4000-8000-000000000001')), '21/3', 'and the delivery policy reads it');

select * from finish();
rollback;
