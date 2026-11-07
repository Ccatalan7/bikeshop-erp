begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- El presupuesto y el comprobante en PDF arriba del aviso (20261107130000).
-- Todo es sintético, a horas fijas del 7 de noviembre de 2026 (Chile, -03) y
-- se deshace al final; el despacho real a Meta queda apagado.
update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('c8e00000-0000-4000-8000-000000000001', 'Documentos A', 'documentos-a@example.invalid', 'America/Santiago', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('c8e00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-documentos@example.invalid', '', now(), '{}', '{}', now(), now());
delete from public.user_profiles where user_id = 'c8e00000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c8e00000-0000-4000-8000-000000000091', 'c8e00000-0000-4000-8000-000000000001', 'admin', '{}', true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('c8e00000-0000-4000-8000-000000000131', 'c8e00000-0000-4000-8000-000000000001',
   'documentos-test-a', 'Sintético documentos', true);

insert into public.website_settings (tenant_id, key, value) values
  ('c8e00000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-documentos.example.invalid'),
  ('c8e00000-0000-4000-8000-000000000001', 'store_name', 'Taller Documentos');

select is(public.record_whatsapp_template_reviews_v1('c8e00000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'taller_presupuesto_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_presupuesto_v2', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_entregada_pdf_v1', 'language', 'es_CL', 'status', 'APPROVED'),
    jsonb_build_object('name', 'taller_entregada_v2', 'language', 'es_CL', 'status', 'APPROVED'))),
  4, 'Meta approved the PDF and the button versions');

-- ---------------------------------------------------------------------------
-- El monto como se dice
-- ---------------------------------------------------------------------------

select is(public.workshop_notice_money_internal(59990), '$59.990', 'thousands with a dot');
select is(public.workshop_notice_money_internal(1234567.4), '$1.234.567', 'rounded, two dots');
select is(public.workshop_notice_money_internal(0), '$0', 'zero is $0');

-- ---------------------------------------------------------------------------
-- Clientes y trabajos
-- ---------------------------------------------------------------------------

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('c8e00000-0000-4000-8000-000000000011', 'c8e00000-0000-4000-8000-000000000001',
   'Camila Torres Soto', '+56 9 2323 4545', null, null, true);

set local session_replication_role = replica;
insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, approved_by_customer, quotation_status, client_request, diagnosis,
  total_cost, discount_amount, created_by) values
  -- Q1: «Presupuestar primero», esperando la aprobación del cliente.
  ('c8e00000-0000-4000-8000-000000000021', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000011', 'PG-Q1', 'quotation', 'quotation', 'bike',
   'ESPERANDO_APROBACION', false, 'pending', 'Cambia mal los cambios', 'Cassette gastado',
   59990, 0, 'c8e00000-0000-4000-8000-000000000091'),
  -- Q2: un trabajo de servicio esperando aprobación: no se aprueba por WhatsApp.
  ('c8e00000-0000-4000-8000-000000000022', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000011', 'PG-Q2', 'service', 'service', 'bike',
   'ESPERANDO_APROBACION', false, null, null, null,
   15000, 0, 'c8e00000-0000-4000-8000-000000000091'),
  -- E1: entregada con su comprobante.
  ('c8e00000-0000-4000-8000-000000000025', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000011', 'PG-E1', 'service', 'service', 'bike',
   'ENTREGADO', true, null, null, null,
   18000, 0, 'c8e00000-0000-4000-8000-000000000091');

insert into public.mechanic_job_items (id, tenant_id, job_id, product_name, quantity, unit_price,
  total_price, item_type, notes, created_at) values
  ('c8e00000-0000-4000-8000-000000000061', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000021', 'Cambio de cassette 11-46', 1, 39990, 39990,
   'service', 'nota interna que el cliente no ve', '2026-11-07 10:00:00-03'),
  ('c8e00000-0000-4000-8000-000000000062', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000021', 'Cadena 10 velocidades', 1, 20000, 20000,
   'product', null, '2026-11-07 10:01:00-03'),
  ('c8e00000-0000-4000-8000-000000000063', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000022', 'Ajuste de frenos', 1, 15000, 15000,
   'service', null, '2026-11-07 10:02:00-03');

insert into public.mechanic_job_delivery_events (id, tenant_id, job_id, event_kind, occurred_at,
  recorded_at, actor_id, source, operation_key) values
  ('c8e00000-0000-4000-8000-000000000403', 'c8e00000-0000-4000-8000-000000000001',
   'c8e00000-0000-4000-8000-000000000025', 'delivered', '2026-11-07 11:00:00-03',
   '2026-11-07 11:00:00-03', 'c8e00000-0000-4000-8000-000000000091', 'status_transition', 'documentos-e1');

insert into public.mechanic_job_delivery_documents (tenant_id, job_id, delivery_event_id, job_number,
  delivered_at, service_warranty_days, service_warranty_expires_at, parts_warranty_months,
  parts_warranty_expires_at, snapshot) values
  ('c8e00000-0000-4000-8000-000000000001', 'c8e00000-0000-4000-8000-000000000025',
   'c8e00000-0000-4000-8000-000000000403', 'PG-E1', '2026-11-07 11:00:00-03',
   14, '2026-11-21 11:00:00-03', 2, '2027-01-07 11:00:00-03',
   jsonb_build_object('work_performed', 'Cambio de cadena',
     'lines', jsonb_build_array(jsonb_build_object('kind', 'part', 'name', 'Cadena KMC X10'))));
set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- Cuándo un aviso lleva su PDF
-- ---------------------------------------------------------------------------

select is((select public.workshop_notice_quote_total_internal(job) from public.mechanic_jobs job
   where job.id = 'c8e00000-0000-4000-8000-000000000021'), 59990::numeric,
  'the quote total is its lines less the discount');

select ok(not (select public.workshop_notice_document_ready_internal('quote_ready', job)
    from public.mechanic_jobs job where job.id = 'c8e00000-0000-4000-8000-000000000021'),
  'until the store draws them, no notice carries a PDF');

insert into public.company_settings (tenant_id, key, value) values
  ('c8e00000-0000-4000-8000-000000000001', 'workshop_notice_documents_enabled', 'true');

select is((select string_agg(job.job_number || ':' || public.workshop_notice_document_ready_internal(
      case when job.status = 'ENTREGADO' then 'delivered' else 'quote_ready' end, job)::text, ' | '
      order by job.job_number)
    from public.mechanic_jobs job where job.tenant_id = 'c8e00000-0000-4000-8000-000000000001'),
  'PG-E1:true | PG-Q1:true | PG-Q2:false',
  'a pending quotation with lines and a delivery with its receipt carry a PDF; a service job does not');

select is(public.workshop_notice_template_v2_internal('c8e00000-0000-4000-8000-000000000001', 'quote_ready', 'bike', true),
  'taller_presupuesto_pdf_v1', 'a quote that can carry its PDF goes with the PDF template');
select is(public.workshop_notice_template_v2_internal('c8e00000-0000-4000-8000-000000000001', 'quote_ready', 'bike', false),
  'taller_presupuesto_v2', 'otherwise with the button template');
select is(public.workshop_notice_template_internal('c8e00000-0000-4000-8000-000000000001', 'delivered', 'bike'),
  'taller_entregada_v2', 'the plain choice never asks for a PDF');

-- ---------------------------------------------------------------------------
-- El envío
-- ---------------------------------------------------------------------------

create temporary table documentos_notice (job_id uuid, kind text, notice_id uuid) on commit drop;
select is(public.workshop_notice_enqueue_internal('c8e00000-0000-4000-8000-000000000001',
  job_id, kind, source_id, '2026-11-07 11:00:00-03', 'c8e00000-0000-4000-8000-000000000091', false, true), 1,
  'the ' || kind || ' notice is noted for WhatsApp')
  from (values
    ('c8e00000-0000-4000-8000-000000000021'::uuid, 'quote_ready', 'c8e00000-0000-4000-8000-000000000501'::uuid),
    ('c8e00000-0000-4000-8000-000000000022'::uuid, 'quote_ready', 'c8e00000-0000-4000-8000-000000000502'::uuid),
    ('c8e00000-0000-4000-8000-000000000025'::uuid, 'delivered', 'c8e00000-0000-4000-8000-000000000403'::uuid))
    as source(job_id, kind, source_id);
insert into documentos_notice
  select notice.job_id, notice.kind, notice.id from public.workshop_customer_notices notice
   where notice.tenant_id = 'c8e00000-0000-4000-8000-000000000001' and notice.channel = 'whatsapp';

select is(public.workshop_notice_dispatch_whatsapp_internal(notice_id, '2026-11-07 12:00:00-03', true), 'sent',
  'the ' || kind || ' notice of ' || job_id || ' goes out')
  from documentos_notice order by kind, job_id;

create temporary table documentos_sent on commit drop as
  select notice.job_id, notice.id as notice_id, notice.template_name, outbox.request, message.content
    from documentos_notice d
    join public.workshop_customer_notices notice on notice.id = d.notice_id
    join public.whatsapp_outbox outbox on outbox.message_id = notice.message_id
    join public.messages message on message.id = notice.message_id;

select is((select string_agg(template_name, ' | ' order by template_name) from documentos_sent),
  'taller_entregada_pdf_v1 | taller_presupuesto_pdf_v1 | taller_presupuesto_v2',
  'the quotation and the delivery go with their PDF; the service job with the button');

-- El presupuesto: el monto en el texto, la tarjeta del trabajo y el código.
select is((select content from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000021'),
  'Hola Camila Torres Soto, te enviamos el presupuesto de tu trabajo PG-Q1 por $59.990. ¿Lo apruebas?',
  'the inbox keeps the approved body with the amount');
select is((select request #> '{templateComponents}' from documentos_sent
    where job_id = 'c8e00000-0000-4000-8000-000000000021'),
  '[{"type": "body", "parameters": [{"type": "text", "text": "Camila Torres Soto"}, {"type": "text", "text": "PG-Q1"}, {"type": "text", "text": "$59.990"}]}]'::jsonb,
  'the body carries the name, the job and the amount; the PDF and the replies are added by the sender');
select is((select (request->>'actionType') || '|' || (request->>'actionKind') || '|' || (request->>'actionTargetId')
                  || '|' || (request->>'amount')
             from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000021'),
  'approve_quote|job|c8e00000-0000-4000-8000-000000000021|59990',
  'the quote asks the sender for the approval card of that job, with its amount');
select matches((select request->>'templateDocumentToken' from documentos_sent
    where job_id = 'c8e00000-0000-4000-8000-000000000021'),
  '^[A-Za-z0-9_-]{43}$', 'the PDF code is a 43-character one-time code');
select is((select count(*)::integer from public.workshop_notice_document_tokens token
    join documentos_sent sent on sent.notice_id = token.notice_id
   where sent.job_id = 'c8e00000-0000-4000-8000-000000000021' and token.kind = 'quote'
     and token.token_sha256 = encode(extensions.digest(convert_to(
           sent.request->>'templateDocumentToken', 'UTF8'), 'sha256'), 'hex')), 1,
  'only the fingerprint of the code is kept, tied to its notice');
select ok((select request->'templateDocumentToken' is null and request->'actionType' is null
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000022'),
  'the button version carries neither a PDF code nor an approval card');

-- El comprobante: la garantía en el texto, el botón de la cuenta y el código.
select is((select content from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000025'),
  'Hola Camila Torres Soto, tu trabajo PG-E1 quedó entregado. Te dejamos tu comprobante; la garantía del servicio vale hasta el 21 de noviembre. Gracias por confiar en Viñabike.',
  'the delivery notice says until when the service is covered');
select is((select jsonb_path_query_array(request, '$.templateComponents[*].type')
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000025'),
  '["body", "button"]'::jsonb, 'the receipt notice is a body and its account button');
select matches((select request->>'templateDocumentToken' from documentos_sent
    where job_id = 'c8e00000-0000-4000-8000-000000000025'),
  '^[A-Za-z0-9_-]{43}$', 'the receipt carries its own PDF code');

-- ---------------------------------------------------------------------------
-- Lo que lee la tienda con el código
-- ---------------------------------------------------------------------------

create temporary table documentos_read on commit drop as
  select public.workshop_notice_document_v1(request->>'templateDocumentToken') as answer
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000021';

select is((select answer->>'kind' from documentos_read), 'quote', 'the code opens the quote');
select is((select answer #> '{document,lines}' from documentos_read),
  '[{"kind": "service", "name": "Cambio de cassette 11-46", "quantity": 1, "unit_price": 39990, "total": 39990}, {"kind": "part", "name": "Cadena 10 velocidades", "quantity": 1, "unit_price": 20000, "total": 20000}]'::jsonb,
  'each line with its name, quantity and price, and never its internal note');
select is((select (answer #>> '{document,total}') || '|' || (answer #>> '{document,job_number}') || '|' ||
                  (answer #>> '{document,customer,name}') || '|' || (answer #>> '{document,item}')
             from documentos_read),
  '59990|PG-Q1|Camila Torres Soto|bicicleta', 'the total, the job, the customer and what was left');
select is((select (answer #>> '{document,issued_at}')::timestamptz from documentos_read),
  '2026-11-07 11:00:00-03'::timestamptz, 'the quote is dated when it was ready');
select is((select answer #>> '{document,storefront,schemaVersion}' from documentos_read), '1',
  'with the store identity the shared drawing reads');

select is((select reads from public.workshop_notice_document_tokens token
    join documentos_sent sent on sent.notice_id = token.notice_id
   where sent.job_id = 'c8e00000-0000-4000-8000-000000000021'), 1, 'each read is counted');

select is((select public.workshop_notice_document_v1(request->>'templateDocumentToken') #>> '{document,job_number}'
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000025'),
  'PG-E1', 'the delivery code opens the receipt');
select is((select public.workshop_notice_document_v1(request->>'templateDocumentToken') ->> 'kind'
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000025'),
  'delivery', 'as a delivery document');

select is(public.workshop_notice_document_v1('no-es-un-codigo'), null, 'a malformed code says nothing');
select is(public.workshop_notice_document_v1(repeat('A', 43)), null, 'an unknown code says nothing');

update public.workshop_notice_document_tokens token set reads = 10
  from documentos_sent sent
 where sent.notice_id = token.notice_id and sent.job_id = 'c8e00000-0000-4000-8000-000000000021';
select is((select public.workshop_notice_document_v1(request->>'templateDocumentToken')
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000021'), null,
  'a code read ten times is spent');
update public.workshop_notice_document_tokens token set expires_at = clock_timestamp() - interval '1 second'
  from documentos_sent sent
 where sent.notice_id = token.notice_id and sent.job_id = 'c8e00000-0000-4000-8000-000000000025';
select is((select public.workshop_notice_document_v1(request->>'templateDocumentToken')
    from documentos_sent where job_id = 'c8e00000-0000-4000-8000-000000000025'), null,
  'an expired code says nothing');

-- ---------------------------------------------------------------------------
-- Quién puede llamar
-- ---------------------------------------------------------------------------

select ok(has_function_privilege('anon', 'public.workshop_notice_document_v1(text)', 'EXECUTE'),
  'the store reads the document with its public key and the code');
select ok(not has_function_privilege('authenticated', 'public.workshop_notice_document_token_internal(public.workshop_customer_notices, text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_document_token_internal(public.workshop_customer_notices, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_quote_document_projection_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.job_quote_document_projection_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_template_v2_internal(uuid, text, text, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_document_ready_internal(text, public.mechanic_jobs)', 'EXECUTE'),
  'the helpers are closed to every caller role');
select ok(not has_table_privilege('anon', 'public.workshop_notice_document_tokens', 'SELECT')
  and not has_table_privilege('authenticated', 'public.workshop_notice_document_tokens', 'SELECT'),
  'nobody reads the codes table from outside');

select * from finish();
rollback;
