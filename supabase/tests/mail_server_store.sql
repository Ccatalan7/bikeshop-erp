begin;

select no_plan();

-- Correo que trabaja (20261106200000): el correo de las casillas de la empresa
-- se guarda una vez para el equipo, se entiende con reglas seguras y se liga
-- a sus registros. El estado de cada botón se calcula del registro: si alguien
-- ya registró la factura, el gasto o el pago por otro lado, el correo lo dice.
-- Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('a7a00000-0000-4000-8000-000000000001', 'Correo A', 'correo-a@example.invalid', 'America/Santiago', true),
  ('a7a00000-0000-4000-8000-000000000002', 'Correo B', 'correo-b@example.invalid', 'America/Santiago', true);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
  ('a7a00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-correo@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('a7a00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'otra-tienda@example.invalid', '', now(), '{}', '{}', now(), now()),
  ('a7a00000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'cliente-portal@example.invalid', '', now(), '{}', '{}', now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('a7a00000-0000-4000-8000-000000000091', 'a7a00000-0000-4000-8000-000000000001', 'admin', '{}', true),
  ('a7a00000-0000-4000-8000-000000000092', 'a7a00000-0000-4000-8000-000000000002', 'admin', '{}', true);

set local session_replication_role = replica;

insert into public.customers (id, tenant_id, name, phone, email, auth_user_id, is_active) values
  ('a7a00000-0000-4000-8000-000000000011', 'a7a00000-0000-4000-8000-000000000001',
   'Camila Prueba', '+56 9 1111 2222', 'Camila.Prueba@Example.invalid',
   'a7a00000-0000-4000-8000-000000000093', true);

insert into public.suppliers (id, tenant_id, name, rut, website, email, is_active) values
  ('a7a00000-0000-4000-8000-000000000021', 'a7a00000-0000-4000-8000-000000000001',
   'Comercial Ciclo', '76.442.832-3', 'https://www.comercialciclo.cl/', 'contacto@comercialciclo.cl', true),
  ('a7a00000-0000-4000-8000-000000000022', 'a7a00000-0000-4000-8000-000000000001',
   'TeknoBike', null, 'teknobike.cl', null, true),
  ('a7a00000-0000-4000-8000-000000000023', 'a7a00000-0000-4000-8000-000000000001',
   'Starken', null, 'starken.cl', null, true),
  ('a7a00000-0000-4000-8000-000000000024', 'a7a00000-0000-4000-8000-000000000001',
   'MKR Imports', null, 'mkr.cl', 'contacto@mkr.cl', true);

insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, job_type,
  workflow_kind, intake_kind, status, approved_by_customer, client_request, total_cost) values
  ('a7a00000-0000-4000-8000-000000000031', 'a7a00000-0000-4000-8000-000000000001',
   'a7a00000-0000-4000-8000-000000000011', 'PG-90672', 'service', 'service', 'bike',
   'PENDIENTE', false, 'Mantención', 45990);

insert into public.purchase_invoices (id, tenant_id, supplier_id, invoice_number, total, status, created_at) values
  ('a7a00000-0000-4000-8000-000000000041', 'a7a00000-0000-4000-8000-000000000001',
   'a7a00000-0000-4000-8000-000000000021', '52947', 204811, 'paid', '2026-10-30 12:53:33-03');

insert into public.expenses (id, tenant_id, expense_number, supplier_id, supplier_name, document_number, total_amount, created_at) values
  ('a7a00000-0000-4000-8000-000000000051', 'a7a00000-0000-4000-8000-000000000001', 'GS-T1',
   'a7a00000-0000-4000-8000-000000000023', 'Starken', '13710616', 16340, '2026-10-21 10:00:00-03');

-- En modo réplica no corren las llaves foráneas: la cuenta contable no hace falta.
insert into public.payment_methods (id, tenant_id, code, name, is_active, account_id) values
  ('a7a00000-0000-4000-8000-000000000061', 'a7a00000-0000-4000-8000-000000000001', 'transfer-test', 'Transferencia', true,
   'a7a00000-0000-4000-8000-000000000069');
insert into public.sales_invoices (id, tenant_id, invoice_number, total, balance, customer_id) values
  ('a7a00000-0000-4000-8000-000000000062', 'a7a00000-0000-4000-8000-000000000001', 'V-T1', 45990, 45990,
   'a7a00000-0000-4000-8000-000000000011');

insert into public.email_accounts (tenant_id, user_id, provider, account_email, refresh_token, is_active) values
  ('a7a00000-0000-4000-8000-000000000001', 'a7a00000-0000-4000-8000-000000000091', 'gmail',
   'Correo.Taller@Example.invalid', 'sintetico', true),
  ('a7a00000-0000-4000-8000-000000000002', 'a7a00000-0000-4000-8000-000000000092', 'gmail',
   'otra@example.invalid', 'sintetico', true);

set local session_replication_role = origin;

-- ---------------------------------------------------------------------------
-- La casilla y el directorio salen de lo que ya existe
-- ---------------------------------------------------------------------------

select is((public.mail_prepare_tenant_v1('a7a00000-0000-4000-8000-000000000001')->>'new_mailboxes')::int, 1,
  'the connected Gmail becomes one mailbox of the company');
select is((select address from public.mail_mailboxes where tenant_id = 'a7a00000-0000-4000-8000-000000000001'),
  'correo.taller@example.invalid', 'the address is stored folded');
select is((select party_type || ':' || party_id::text from public.mail_senders
            where tenant_id = 'a7a00000-0000-4000-8000-000000000001' and match_type = 'domain' and match_value = 'comercialciclo.cl'),
  'supplier:a7a00000-0000-4000-8000-000000000021', 'the supplier website becomes its domain');
select is((select party_type || ':' || party_id::text from public.mail_senders
            where tenant_id = 'a7a00000-0000-4000-8000-000000000001' and match_type = 'domain' and match_value = 'starken.cl'),
  'courier:a7a00000-0000-4000-8000-000000000023', 'a courier that is also a supplier keeps both');
select is((select party_type from public.mail_senders
            where tenant_id = 'a7a00000-0000-4000-8000-000000000001' and match_type = 'domain' and match_value = 'bancochile.cl'),
  'bank', 'the banks are seeded');

-- Una casilla nace apagada (20261106210000) y sólo se lee encendida
-- (20261106240000): el dueño la enciende.
update public.mail_mailboxes set is_active = true
 where tenant_id = 'a7a00000-0000-4000-8000-000000000001';

-- ---------------------------------------------------------------------------
-- Los correos reales de octubre, sintetizados
-- ---------------------------------------------------------------------------

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7a00000-0000-4000-8000-000000000001'),
  jsonb_build_array(
    jsonb_build_object('provider_message_id', 'm-dte', 'provider_thread_id', 't-dte',
      'from_address', '76442832-3@intercambio.skilldte.cl', 'from_name', 'Comercial Ciclo SpA',
      'subject', 'Documento Tributario Electronico Nro 52947 de Comercial Ciclo SPA',
      'has_attachments', true,
      'attachments', jsonb_build_array(jsonb_build_object('filename', 'DTE_52947.xml', 'mime_type', 'text/xml', 'attachment_id', 'a1')),
      'received_at', '2026-10-19 13:21:25-03'),
    jsonb_build_object('provider_message_id', 'm-dte-new', 'provider_thread_id', 't-dte2',
      'from_address', '76442832-3@intercambio.skilldte.cl',
      'subject', 'Documento Tributario Electronico Nro 52999 de Comercial Ciclo SPA',
      'attachments', jsonb_build_array(jsonb_build_object('filename', 'DTE_52999.xml')),
      'received_at', now() - interval '1 day'),
    jsonb_build_object('provider_message_id', 'm-tekno', 'from_address', 'dteteknobike@desis.cl',
      'subject', 'Envío de Documento Electrónico', 'received_at', now() - interval '2 days'),
    jsonb_build_object('provider_message_id', 'm-flete', 'from_address', 'infodte@starken.cl',
      'subject', 'Starken OF: 279929344  -  Factura Electrónica  : 13710616',
      'received_at', '2026-10-20 14:20:00-03'),
    jsonb_build_object('provider_message_id', 'm-envio', 'from_address', 'notificaciones@starken.cl',
      'subject', 'Envío en camino, realiza el pago ahora', 'body_text', 'Orden de flete N° 279929344. Paga el flete.',
      'received_at', '2026-10-20 10:14:16-03'),
    jsonb_build_object('provider_message_id', 'm-transfer', 'from_address', 'serviciodetransferencias@bancochile.cl',
      'subject', 'Aviso de transferencia de fondos',
      'body_text', E'Le informamos que se ha realizado una transferencia.\nMonto: $45.990\nNombre del originante: Camila Prueba',
      'received_at', now() - interval '2 hours'),
    jsonb_build_object('provider_message_id', 'm-cliente', 'provider_thread_id', 't-cli',
      'from_address', 'camila.prueba@example.invalid', 'from_name', 'Camila Prueba',
      'subject', 'Re: Tu presupuesto está listo', 'body_text', 'Dale, háganlo. ¿Para cuándo estaría?',
      'received_at', now() - interval '1 hour'),
    jsonb_build_object('provider_message_id', 'm-zoho', 'from_address', 'no-reply@zohobooks.com',
      'subject', 'Las existencias de su organización Viñabike han alcanzando el punto de reposición.',
      'received_at', now() - interval '3 hours'),
    jsonb_build_object('provider_message_id', 'm-promo', 'from_address', 'contacto@mkr.cl', 'is_bulk', true,
      'subject', 'Repuestos en oferta: hasta 70% de descuento en mkr.cl', 'received_at', now() - interval '4 hours'),
    jsonb_build_object('provider_message_id', 'm-pedido', 'from_address', 'contacto@mkr.cl', 'is_bulk', true,
      'subject', 'Hemos recibido su pedido #149317 / MKR.cl', 'received_at', now() - interval '5 hours'),
    jsonb_build_object('provider_message_id', 'm-seg', 'from_address', 'no-reply@accounts.google.com',
      'subject', 'Security alert', 'received_at', now() - interval '6 hours'),
    jsonb_build_object('provider_message_id', 'm-resena', 'from_address', 'businessprofile-noreply@google.com',
      'subject', 'Santiago left a review for Viñabike', 'received_at', now() - interval '7 hours'),
    jsonb_build_object('provider_message_id', 'm-pg', 'from_address', 'otra.persona@gmail.com',
      'subject', 'Consulta por PG-90672', 'received_at', now() - interval '8 hours')
  ))->>'new', '13', 'thirteen new messages enter once');

select is(public.mail_upsert_messages_v1(
  (select id from public.mail_mailboxes where tenant_id = 'a7a00000-0000-4000-8000-000000000001'),
  jsonb_build_array(jsonb_build_object('provider_message_id', 'm-zoho', 'from_address', 'no-reply@zohobooks.com',
      'subject', 'Las existencias de su organización Viñabike han alcanzando el punto de reposición.',
      'provider_read', true, 'received_at', now() - interval '3 hours')))->>'updated', '1',
  'a second sync of the same message only refreshes it');

create temp table mail_kinds on commit drop as
  select provider_message_id as pid, kind, sender_party_type, sender_party_id, facts, case_key, archived_at, archive_reason
    from public.mail_messages where tenant_id = 'a7a00000-0000-4000-8000-000000000001';

select is((select kind || '|' || sender_party_id::text || '|' || (facts->>'folio') from mail_kinds where pid = 'm-dte'),
  'supplier_invoice|a7a00000-0000-4000-8000-000000000021|52947',
  'the invoice exchange address carries the supplier RUT');
select is((select kind || '|' || sender_party_id::text from mail_kinds where pid = 'm-tekno'),
  'supplier_invoice|a7a00000-0000-4000-8000-000000000022',
  'a billing service with the supplier name in the address finds TeknoBike');
select is((select kind || '|' || (facts->>'folio') || '|' || case_key from mail_kinds where pid = 'm-flete'),
  'freight_invoice|13710616|flete:279929344', 'a Starken invoice is a freight invoice of its freight order');
select is((select kind || '|' || case_key from mail_kinds where pid = 'm-envio'),
  'shipment|flete:279929344', 'the shipment notice joins the same freight order');
select is((select kind || '|' || (facts->>'amount') || '|' || (facts->>'payer') from mail_kinds where pid = 'm-transfer'),
  'transfer|45990|Camila Prueba', 'a bank notice is a transfer with its amount and payer');
select is((select kind || '|' || sender_party_type from mail_kinds where pid = 'm-cliente'),
  'customer|customer', 'a customer writes from the email on her record');
select is((select kind || '|' || archive_reason from mail_kinds where pid = 'm-zoho'),
  'noise|noise', 'Zoho Books alerts are noise and archive themselves');
select is((select kind from mail_kinds where pid = 'm-promo'), 'promo', 'a supplier newsletter is just a promotion');
select is((select kind from mail_kinds where pid = 'm-pedido'), 'supplier_order', 'an order confirmation from the same supplier is an order');
select is((select kind from mail_kinds where pid = 'm-seg'), 'security', 'a security alert is security');
select is((select kind from mail_kinds where pid = 'm-resena'), 'review', 'a Google review notice is a review');

-- ---------------------------------------------------------------------------
-- Vínculos
-- ---------------------------------------------------------------------------

select is((select string_agg(record_type || ':' || source, ',' order by record_type) from public.mail_message_links l
             join public.mail_messages m on m.id = l.message_id where m.provider_message_id = 'm-dte'),
  'purchase_invoice:document,supplier:sender', 'the invoice links to its supplier and to the purchase already registered');
select is((select string_agg(record_type || ':' || source, ',' order by record_type) from public.mail_message_links l
             join public.mail_messages m on m.id = l.message_id where m.provider_message_id = 'm-flete'),
  'expense:document,supplier:sender', 'the freight invoice links to the expense already registered');
select is((select string_agg(record_type || ':' || source, ',' order by record_type) from public.mail_message_links l
             join public.mail_messages m on m.id = l.message_id where m.provider_message_id = 'm-cliente'),
  'customer:sender,job:sender', 'the customer with one open job: her email belongs to that job');
select is((select record_type || ':' || source || ':' || is_primary::text from public.mail_message_links l
             join public.mail_messages m on m.id = l.message_id where m.provider_message_id = 'm-pg'),
  'job:number:true', 'a job number in the subject links the job');

-- ---------------------------------------------------------------------------
-- El estado se calcula del registro (regla del dueño)
-- ---------------------------------------------------------------------------

select is((select public.mail_message_state_internal(id)->>'done_text' from public.mail_messages where provider_message_id = 'm-dte'),
  'Ya registrada en Compras', 'an invoice registered by hand shows as registered');
select is((select (public.mail_message_state_internal(id)->>'done')::boolean from public.mail_messages where provider_message_id = 'm-dte-new'),
  false, 'an invoice nobody registered is still to do');
select is((select public.mail_message_state_internal(id)->>'done_text' from public.mail_messages where provider_message_id = 'm-flete'),
  'Ya está en Gastos', 'a freight invoice already in Expenses shows as done');
select is((select (public.mail_message_state_internal(id)->>'done')::boolean from public.mail_messages where provider_message_id = 'm-transfer'),
  false, 'a transfer nobody registered is still to do');

set local session_replication_role = replica;
insert into public.sales_payments (tenant_id, invoice_id, amount, date, payment_method_id, reference) values
  ('a7a00000-0000-4000-8000-000000000001', 'a7a00000-0000-4000-8000-000000000062', 45990, current_date,
   'a7a00000-0000-4000-8000-000000000061', 'pagado por otro lado');
set local session_replication_role = origin;

select is((select public.mail_message_state_internal(id)->>'done_text' from public.mail_messages where provider_message_id = 'm-transfer'),
  'Ya registrado: pago de Camila Prueba', 'when the coworker registers the payment elsewhere, the email shows it done');

-- ---------------------------------------------------------------------------
-- Lo que ve el equipo, y lo que no ve nadie más
-- ---------------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a7a00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7a00000-0000-4000-8000-000000000091', true);

select ok(jsonb_array_length(public.mail_inbox_v1('today')) >= 3, 'Para hoy lists what asks for action');
select ok(not exists (select 1 from jsonb_array_elements(public.mail_inbox_v1('today')) x
                       where x->>'kind' in ('promo', 'noise') or (x->'state'->>'done')::boolean),
  'Para hoy never lists promotions, noise or what was already done');
select ok(exists (select 1 from jsonb_array_elements(public.mail_inbox_v1('archived')) x where x->>'kind' = 'noise'),
  'noise is in the archive');
select is(jsonb_array_length(public.mail_inbox_v1('all', null, '52947')), 1, 'search by folio finds the invoice');
select is((public.mail_counts_v1()->'spaces'->>'facturas')::int, 4, 'the invoices space counts the four documents');
select is(public.mail_mark_v1(array[(select id from public.mail_messages where provider_message_id = 'm-dte-new')], 'done'), 1,
  'a person can mark an item done');
select is((public.mail_message_v1((select id from public.mail_messages where provider_message_id = 'm-dte-new'))->'state'->>'done')::boolean,
  true, 'and it leaves Para hoy');
select is(jsonb_array_length(public.mail_record_messages_v1('job', 'a7a00000-0000-4000-8000-000000000031')), 2,
  'the job history lists its two emails');

select ok(jsonb_array_length(public.mail_link_v1(
    (select id from public.mail_messages where provider_message_id = 'm-promo'),
    'customer', 'a7a00000-0000-4000-8000-000000000011')) >= 1, 'a person links an email by hand');
select is((select source from public.mail_senders where match_type = 'address' and match_value = 'contacto@mkr.cl'
            and tenant_id = 'a7a00000-0000-4000-8000-000000000001'), 'person', 'and the directory learns it');

select throws_ok($$select public.mail_mark_v1(array[gen_random_uuid()], 'explode')$$, '22023', 'mail_bad_operation',
  'an unknown operation is refused');

select set_config('request.jwt.claims', '{"sub":"a7a00000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7a00000-0000-4000-8000-000000000092', true);
select is(jsonb_array_length(public.mail_inbox_v1('all')), 0, 'another shop sees none of these emails');
select is_empty($$select 1 from public.mail_messages$$, 'nor through the table');

select set_config('request.jwt.claims', '{"sub":"a7a00000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'a7a00000-0000-4000-8000-000000000093', true);
select throws_ok($$select public.mail_inbox_v1('all')$$, '42501', 'mail_forbidden', 'a customer portal account cannot read the mail');
select is_empty($$select 1 from public.mail_messages$$, 'nor the table');
reset role;

select ok(not has_function_privilege('authenticated', 'public.mail_upsert_messages_v1(uuid, jsonb)', 'EXECUTE'),
  'only the server writes messages');
select ok(not has_function_privilege('authenticated', 'public.dispatch_mail_sync_v1(text)', 'EXECUTE'),
  'nobody but the scheduler dispatches a sync');
select ok(not has_function_privilege('authenticated', 'public.mail_classify_message_internal(uuid)', 'EXECUTE'),
  'the classifier is internal');

select * from finish();
rollback;
