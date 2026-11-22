begin;

select no_plan();

-- El pedido abierto de un proveedor sale solo en la mañana, con su PDF
-- (20261122030000). Todo es sintético y a horas fijas de noviembre y
-- diciembre de 2026 (Chile, -03); el despacho real a Meta queda apagado.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

update public.whatsapp_outbox_runtime set enabled = false;

insert into public.tenants (id, shop_name, currency, timezone) values
  ('e2e30000-0000-4000-8000-000000000001', 'Taller de la mañana', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2e30000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-manana@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"e2e30000-0000-4000-8000-000000000001"}'::jsonb, now(), now());
delete from public.user_profiles where user_id = 'e2e30000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('e2e30000-0000-4000-8000-000000000091', 'e2e30000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active) values
  ('e2e30000-0000-4000-8000-000000000131', 'e2e30000-0000-4000-8000-000000000001',
   'manana-test', 'Sintético mañana', true);

select is(public.record_whatsapp_template_reviews_v1('e2e30000-0000-4000-8000-000000000001', jsonb_build_array(
    jsonb_build_object('name', 'documento_adjunto_v1', 'language', 'es_CL', 'status', 'APPROVED'))),
  1, 'Meta approved the document template');

-- A: con el celular de su vendedor y «Cómo saludarle» en su contacto.
-- B: sin celular.
insert into public.suppliers (id, tenant_id, name, rut, legal_name, sales_rep_name, sales_rep_phone, payment_terms) values
  ('e2e30000-0000-4000-8000-000000000031', 'e2e30000-0000-4000-8000-000000000001',
   'Distribuidor de la mañana', '76.555.666-7', 'Distribuidora La Mañana Ltda.',
   'Álvaro Curín Soto', '+56 9 1234 5678', 'net30'),
  ('e2e30000-0000-4000-8000-000000000032', 'e2e30000-0000-4000-8000-000000000001',
   'Distribuidor sin celular', null, null, null, null, 'prepaid');

-- El contacto principal es el vendedor de la ficha (lo proyecta
-- `trg_supplier_contacts_project_primary`): su celular es el del proveedor.
insert into public.supplier_contacts (tenant_id, supplier_id, name, phone, is_primary, is_active, greeting_style, greeting_custom_name)
values ('e2e30000-0000-4000-8000-000000000001', 'e2e30000-0000-4000-8000-000000000031',
        'Álvaro Curín Soto', '+56 9 1234 5678', true, true, 'custom', 'Álvaro');

insert into public.supplier_catalog_feeds (
  id, tenant_id, supplier_id, format, endpoint_template, last_ok_at, last_status
) values
  ('e2e30000-0000-4000-8000-0000000000f1', 'e2e30000-0000-4000-8000-000000000001',
   'e2e30000-0000-4000-8000-000000000031', 'mkr_csv_v1',
   'https://proveedor.example.cl/api/endpoint?token={token}', now() - interval '10 minutes', 'ok'),
  ('e2e30000-0000-4000-8000-0000000000f2', 'e2e30000-0000-4000-8000-000000000001',
   'e2e30000-0000-4000-8000-000000000032', 'mkr_csv_v1',
   'https://otro.example.cl/api/endpoint?token={token}', now() - interval '10 minutes', 'ok');
insert into public.supplier_catalog_feed_items (
  tenant_id, feed_id, supplier_id, supplier_sku, barcode, name, stock
) values
  ('e2e30000-0000-4000-8000-000000000001', 'e2e30000-0000-4000-8000-0000000000f1',
   'e2e30000-0000-4000-8000-000000000031', 'MA-1', null, 'Cadena', 40),
  ('e2e30000-0000-4000-8000-000000000001', 'e2e30000-0000-4000-8000-0000000000f1',
   'e2e30000-0000-4000-8000-000000000031', 'MA-2', null, 'Pedales', 40),
  ('e2e30000-0000-4000-8000-000000000001', 'e2e30000-0000-4000-8000-0000000000f2',
   'e2e30000-0000-4000-8000-000000000032', 'MB-1', null, 'Sillín', 40);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, supplier_code, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('e2e30000-0000-4000-8000-000000000011', 'e2e30000-0000-4000-8000-000000000001',
   'Cadena 12 v', 'MA-CAD', 'MA-1', 20000, 9000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e30000-0000-4000-8000-000000000031'),
  ('e2e30000-0000-4000-8000-000000000012', 'e2e30000-0000-4000-8000-000000000001',
   'Pedales de aluminio', 'MA-PED', 'MA-2', 30000, 12000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e30000-0000-4000-8000-000000000031'),
  ('e2e30000-0000-4000-8000-000000000013', 'e2e30000-0000-4000-8000-000000000001',
   'Sillín de ruta', 'MB-SIL', 'MB-1', 25000, 10000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e30000-0000-4000-8000-000000000032');
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('e2e30000-0000-4000-8000-000000000011', 'e2e30000-0000-4000-8000-000000000001',
   'e2e30000-0000-4000-8000-000000000031', 3, 5),
  ('e2e30000-0000-4000-8000-000000000012', 'e2e30000-0000-4000-8000-000000000001',
   'e2e30000-0000-4000-8000-000000000031', 3, 5),
  ('e2e30000-0000-4000-8000-000000000013', 'e2e30000-0000-4000-8000-000000000001',
   'e2e30000-0000-4000-8000-000000000032', 3, 5);

insert into public.website_settings (tenant_id, key, value) values
  ('e2e30000-0000-4000-8000-000000000001', 'store_url', 'https://tienda-manana.example.invalid'),
  ('e2e30000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('e2e30000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('e2e30000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('e2e30000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Taller mañana'),
  ('e2e30000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0');

-- Una compra por transferencia que el equipo confirma: devuelve el pedido web.
create function pg_temp.buy(p_key text, p_name text, p_items jsonb)
returns uuid
language plpgsql
as $function$
declare
  v_order uuid;
begin
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  v_order := (public.create_public_online_order_with_access(
    jsonb_build_object(
      'tenant_id', 'e2e30000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', p_key,
      'customer_email', lower(p_name) || '@example.invalid',
      'customer_name', p_name || ' Prueba',
      'customer_address', 'Retiro en tienda',
      'delivery_type', 'pickup',
      'payment_method', 'transfer'
    ),
    p_items) ->> 'order_id')::uuid;
  reset role;
  perform set_config('request.jwt.claims',
    '{"sub":"e2e30000-0000-4000-8000-000000000091","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'e2e30000-0000-4000-8000-000000000091', true);
  set local role authenticated;
  perform public.confirm_online_order_payment(v_order, 'TRF-' || p_name, now());
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return v_order;
end;
$function$;

-- El pedido al proveedor de una venta web.
create function pg_temp.ped(p_order uuid)
returns uuid
language sql
as $function$
  select po.purchase_invoice_id from public.customer_quote_purchase_orders po
   where po.online_order_id = p_order;
$function$;

-- La pasada de cada minuto, a una hora de Chile.
create function pg_temp.pass(p_local text)
returns jsonb
language sql
as $function$
  select public.process_supplier_order_dispatches_v1((p_local || ' America/Santiago')::timestamptz);
$function$;

-- ---------------------------------------------------------------------------
-- Días hábiles y la hora de envío
-- ---------------------------------------------------------------------------

select ok(
  not public.chile_business_day_internal('2026-11-21')
  and not public.chile_business_day_internal('2026-11-22')
  and public.chile_business_day_internal('2026-11-23')
  and not public.chile_business_day_internal('2026-12-08')
  and not public.chile_business_day_internal('2027-09-17'),
  'Saturday, Sunday and a national holiday are not business days; a Monday is');

select is(
  public.supplier_order_next_send_at_internal('2026-11-20 18:00 America/Santiago', '09:30'),
  '2026-11-23 09:30 America/Santiago'::timestamptz,
  'what is paid on Friday afternoon leaves on Monday morning');
select is(
  public.supplier_order_next_send_at_internal('2026-12-07 10:00 America/Santiago', '09:30'),
  '2026-12-09 09:30 America/Santiago'::timestamptz,
  'the holiday of 8 December is skipped');
select is(
  public.supplier_order_next_send_at_internal('2026-11-23 09:29 America/Santiago', '09:30'),
  '2026-11-23 09:30 America/Santiago'::timestamptz,
  'what is paid just before the hour still leaves that day');
select is(public.supplier_order_next_send_at_internal(now(), null), null,
  'a supplier without an hour has no automatic send');
select is(
  public.supplier_order_when_text_internal('2026-11-24 09:30 America/Santiago', '2026-11-23 10:00 America/Santiago')
    || ' · ' || public.supplier_order_when_text_internal('2026-11-30 09:30 America/Santiago', '2026-11-27 10:00 America/Santiago'),
  'mañana a las 09:30 · el lunes 30 a las 09:30',
  'when the next one leaves reads as a person says it');
select is(
  (select order_send_time::text from public.suppliers where id = 'e2e30000-0000-4000-8000-000000000031'),
  '09:30:00', 'a supplier sends at 09:30 unless someone changes it');
select throws_ok(
  $$update public.suppliers set order_send_time = '23:00' where id = 'e2e30000-0000-4000-8000-000000000031'$$,
  '23514', null, 'an order never leaves at night');

select ok(
  has_function_privilege('authenticated', 'public.supplier_open_order_schedule_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_open_order_schedule_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.process_supplier_order_dispatches_v1(timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.supplier_order_dispatch_internal(uuid,timestamptz,timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.purchase_order_mark_sent_internal(uuid,uuid)', 'EXECUTE'),
  'the team reads the schedule; only the database sends');

-- ---------------------------------------------------------------------------
-- Diego paga el viernes en la tarde: sale el lunes a las 09:30.
-- ---------------------------------------------------------------------------

select set_config('om.a', pg_temp.buy('8c3d3b4c-5e6f-4071-9b82-000000000001', 'Diego',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e30000-0000-4000-8000-000000000011', 'quantity', 2),
    jsonb_build_object('product_id', 'e2e30000-0000-4000-8000-000000000012', 'quantity', 1)))::text, true);
select set_config('om.ped1', pg_temp.ped(current_setting('om.a')::uuid)::text, true);
update public.purchase_invoices set created_at = '2026-11-20 18:00 America/Santiago'
 where id = current_setting('om.ped1')::uuid;

select is(pg_temp.pass('2026-11-23 09:31') ->> 'queued', '0',
  'while the store has it off, nothing leaves by itself');
select is((select count(*)::integer from public.supplier_order_dispatches
            where tenant_id = 'e2e30000-0000-4000-8000-000000000001'), 0, 'and nothing is recorded');

insert into public.company_settings (tenant_id, key, value)
values ('e2e30000-0000-4000-8000-000000000001', 'supplier_order_auto_send_enabled', 'true');

select is(pg_temp.pass('2026-11-21 10:00') ->> 'queued', '0', 'not on a Saturday');
select is(pg_temp.pass('2026-11-23 09:29') ->> 'queued', '0', 'not before the supplier''s hour');

select set_config('request.jwt.claims', '{"sub":"e2e30000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e30000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  (public.supplier_open_order_schedule_v1('e2e30000-0000-4000-8000-000000000001',
     current_setting('om.ped1')::uuid) ->> 'send_at')::timestamptz,
  '2026-11-23 09:30 America/Santiago'::timestamptz,
  'the assistant says when the open order leaves');
select is(
  (select (p ->> 'send_at')::timestamptz
     from jsonb_array_elements(public.online_order_on_order_detail_v1(
       'e2e30000-0000-4000-8000-000000000001', current_setting('om.a')::uuid) -> 'purchases') p),
  '2026-11-23 09:30 America/Santiago'::timestamptz,
  'and so does the web order');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select is(pg_temp.pass('2026-11-23 09:31') ->> 'queued', '1', 'at 09:30 on Monday it leaves');

create temporary table om_sent as
  select dispatch.*, outbox.request, outbox.actor_id
    from public.supplier_order_dispatches dispatch
    join public.whatsapp_outbox outbox on outbox.message_id = dispatch.message_id
   where dispatch.purchase_invoice_id = current_setting('om.ped1')::uuid;

select is(
  (select state || ':' || order_count || ':' || line_count from om_sent),
  'queued:1:2', 'one dispatch, queued, with its sale and its two lines');
select is(
  (select due_at from om_sent), '2026-11-23 09:30 America/Santiago'::timestamptz,
  'for the Monday 09:30 slot');
select is(
  (select status from public.purchase_invoices where id = current_setting('om.ped1')::uuid),
  'sent', 'the order is «Enviado» as soon as it is queued');
select is(
  (select request ->> 'templateName' || ':' || (request #>> '{templateComponents,0,parameters,0,text}')
     || ':' || (request ->> 'contextType') || ':' || (request #>> '{metadata,source}') from om_sent),
  'documento_adjunto_v1:Álvaro:purchase_order:supplier_order_dispatch',
  'the document template, greeting as the contact sheet says');
select matches((select request ->> 'templateDocumentToken' from om_sent), '^[A-Za-z0-9_-]{43}$',
  'with a one-time code for the PDF');
select is(
  (select request ->> 'caption' from om_sent),
  'Hola Álvaro, te enviamos el documento adjunto desde Viñabike. Si tienes dudas, responde este mensaje.',
  'the text is the approved template''s');
select is(
  (select actor_id from om_sent), 'e2e30000-0000-4000-8000-000000000091'::uuid,
  'it is sent as whoever put the order together');
select is(
  (select c.context_type || ':' || c.context_id
     from om_sent join public.conversations c on c.id = om_sent.conversation_id),
  'supplier:e2e30000-0000-4000-8000-000000000031',
  'without a chat, one is opened with the rep''s phone, bound to the supplier');

-- La tienda dibuja el PDF con el código.
select is(
  (select public.workshop_notice_document_v1(request ->> 'templateDocumentToken') ->> 'kind' from om_sent),
  'supplier_order', 'the code reads as a supplier order');
create temporary table om_doc as
  select public.workshop_notice_document_v1(request ->> 'templateDocumentToken') -> 'document' as document
    from om_sent;
select is(
  (select document ->> 'order_number' from om_doc),
  (select invoice_number from public.purchase_invoices where id = current_setting('om.ped1')::uuid),
  'with the order''s number');
select is(
  (select string_agg((line ->> 'sku') || ':' || (line ->> 'quantity')::numeric::integer, ','
                     order by ordinality)
     from om_doc, jsonb_array_elements(document -> 'lines') with ordinality as l(line, ordinality)),
  'MA-CAD:2,MA-PED:1', 'its lines as saved');
select is(
  (select (document #>> '{supplier,name}') || ' · ' || (document #>> '{supplier,legal_name}') || ' · '
     || (document #>> '{supplier,payment_terms}') || ' · ' || (document #>> '{supplier,contact}') from om_doc),
  'Distribuidor de la mañana · Distribuidora La Mañana Ltda. · net30 · Álvaro Curín Soto · +56 9 1234 5678',
  'and who it is for');
select is(
  (select public.workshop_notice_document_v1(
            case when left(request ->> 'templateDocumentToken', 1) = 'X' then 'Y' else 'X' end
            || substr(request ->> 'templateDocumentToken', 2)) from om_sent),
  null, 'an unknown code says nothing');

select is(pg_temp.pass('2026-11-23 09:32') ->> 'queued', '0', 'it leaves once');

-- La guardia: el asistente que lo tenía abierto no lo reabre.
select set_config('request.jwt.claims', '{"sub":"e2e30000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e30000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_like(
  format($$update public.purchase_invoices set status = 'draft' where id = %L$$, current_setting('om.ped1')),
  'Este pedido ya se le envió al proveedor%',
  'a save from an assistant opened before 09:30 cannot reopen the order that left');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- WhatsApp lo acepta.
update public.whatsapp_outbox set state = 'accepted'
 where message_id = (select message_id from om_sent);
update public.messages set external_status = 'accepted'
 where id = (select message_id from om_sent);
select is(pg_temp.pass('2026-11-23 09:33') ->> 'settled', '1', 'the next pass reads WhatsApp''s answer');
select is(
  (select state from public.supplier_order_dispatches where id = (select id from om_sent)),
  'sent', 'the dispatch is sent');
select is(
  (select n.title || ' | ' || n.body || ' | ' || n.route
     from public.erp_notifications n
    where n.entity_type = 'supplier_order_dispatch' and n.entity_id = (select id from om_sent)),
  'Pedido enviado a Distribuidor de la mañana | '
    || (select invoice_number from public.purchase_invoices where id = current_setting('om.ped1')::uuid)
    || ' · 2 productos. Salió solo a las 09:30 con su PDF. | /purchases/assistant?supplier='
    || 'e2e30000-0000-4000-8000-000000000031&order=' || current_setting('om.ped1'),
  'the team is told it left, and where to see it');

-- ---------------------------------------------------------------------------
-- Renato paga el lunes a las 10:00: va en el pedido del martes. WhatsApp no
-- lo entrega: vuelve a borrador y sale el miércoles.
-- ---------------------------------------------------------------------------

select set_config('om.b', pg_temp.buy('8c3d3b4c-5e6f-4071-9b82-000000000002', 'Renato',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e30000-0000-4000-8000-000000000011', 'quantity', 1)))::text, true);
select set_config('om.ped2', pg_temp.ped(current_setting('om.b')::uuid)::text, true);
update public.purchase_invoices set created_at = '2026-11-23 10:00 America/Santiago'
 where id = current_setting('om.ped2')::uuid;

select isnt(current_setting('om.ped2'), current_setting('om.ped1'),
  'what is paid after the order left opens the next one');
select is(pg_temp.pass('2026-11-23 10:01') ->> 'queued', '0', 'not again on Monday');
select is(pg_temp.pass('2026-11-24 09:31') ->> 'queued', '1', 'it leaves on Tuesday at 09:30');

update public.whatsapp_outbox
   set state = 'failed', last_error = 'synthetic_failure'
 where message_id = (select dispatch.message_id from public.supplier_order_dispatches dispatch
                      where dispatch.purchase_invoice_id = current_setting('om.ped2')::uuid);
update public.messages set external_status = 'failed'
 where id = (select dispatch.message_id from public.supplier_order_dispatches dispatch
              where dispatch.purchase_invoice_id = current_setting('om.ped2')::uuid);
select is(pg_temp.pass('2026-11-24 09:35') ->> 'settled', '1', 'the failure is read');
select is(
  (select dispatch.state || ':' || (dispatch.reason like 'delivery_failed%')::text
     from public.supplier_order_dispatches dispatch
    where dispatch.purchase_invoice_id = current_setting('om.ped2')::uuid),
  'failed:true', 'the dispatch says it did not arrive');
select is(
  (select status || ':' || coalesce(sent_date::text, 'sin fecha')
     from public.purchase_invoices where id = current_setting('om.ped2')::uuid),
  'draft:sin fecha', '«Enviado» stays true: the order is open again');
select is(
  (select n.title || ' | ' || n.body
     from public.erp_notifications n
    where n.entity_type = 'supplier_order_dispatch' and n.type = 'supplier_order_not_sent'
      and n.entity_id = (select dispatch.id from public.supplier_order_dispatches dispatch
                          where dispatch.purchase_invoice_id = current_setting('om.ped2')::uuid)),
  'No salió el pedido a Distribuidor de la mañana | '
    || (select invoice_number from public.purchase_invoices where id = current_setting('om.ped2')::uuid)
    || ': WhatsApp no lo pudo entregar. Mándalo desde «Enviar al proveedor»; si no, sale solo mañana a las 09:30.',
  'the team is told why, and when it leaves by itself');
select is(pg_temp.pass('2026-11-24 11:00') ->> 'queued', '0', 'not again the same day');
select is(pg_temp.pass('2026-11-25 09:31') ->> 'queued', '1', 'on Wednesday at 09:30 it leaves again');
select is(
  (select count(*)::integer from public.supplier_order_dispatches
    where purchase_invoice_id = current_setting('om.ped2')::uuid),
  2, 'two attempts, one per slot');

-- ---------------------------------------------------------------------------
-- Un proveedor sin celular: no sale, y se dice por qué.
-- ---------------------------------------------------------------------------

select set_config('om.c', pg_temp.buy('8c3d3b4c-5e6f-4071-9b82-000000000003', 'Sofía',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e30000-0000-4000-8000-000000000013', 'quantity', 1)))::text, true);
select set_config('om.ped3', pg_temp.ped(current_setting('om.c')::uuid)::text, true);
update public.purchase_invoices set created_at = '2026-11-25 10:00 America/Santiago'
 where id = current_setting('om.ped3')::uuid;

update public.suppliers set order_send_time = null where id = 'e2e30000-0000-4000-8000-000000000032';
select is(pg_temp.pass('2026-11-26 09:31') ->> 'skipped', '0', 'a supplier without an hour is sent by a person');
update public.suppliers set order_send_time = '09:30' where id = 'e2e30000-0000-4000-8000-000000000032';
select is(pg_temp.pass('2026-11-26 21:00') ->> 'skipped', '0', 'a late order never leaves at night');
select is(pg_temp.pass('2026-11-27 09:31') ->> 'skipped', '1', 'the next business morning it is tried');
select is(
  (select dispatch.state || ':' || dispatch.reason || ':' || dispatch.due_at::text
     from public.supplier_order_dispatches dispatch
    where dispatch.purchase_invoice_id = current_setting('om.ped3')::uuid),
  'skipped:no_phone:' || ('2026-11-26 09:30 America/Santiago'::timestamptz)::text,
  'skipped for its missed slot, because the supplier has no phone');
select is(
  (select status from public.purchase_invoices where id = current_setting('om.ped3')::uuid),
  'draft', 'the order stays open');
select is(
  (select n.body from public.erp_notifications n
    where n.type = 'supplier_order_not_sent'
      and n.entity_id = (select dispatch.id from public.supplier_order_dispatches dispatch
                          where dispatch.purchase_invoice_id = current_setting('om.ped3')::uuid)),
  (select invoice_number from public.purchase_invoices where id = current_setting('om.ped3')::uuid)
    || ': el proveedor no tiene el celular de su vendedor en la ficha. Mándalo desde «Enviar al proveedor»; si no, sale solo el lunes 30 a las 09:30.',
  'the notice names what to fix');

-- ---------------------------------------------------------------------------
-- Los feriados que faltan se piden y se recogen.
-- ---------------------------------------------------------------------------

do $$
begin
  if to_regclass('net._http_response') is not null then
    insert into public.chile_public_holiday_requests (request_id, year, requested_at)
    values (-424242, 2028, '2026-11-22 12:00 America/Santiago');
    insert into net._http_response (id, status_code, content, timed_out)
    values (-424242, 200,
      '[{"date":"2028-01-01","localName":"Año Nuevo","global":true},'
      || '{"date":"2028-06-07","localName":"Asalto y Toma del Morro de Arica","global":false},'
      || '{"date":"2027-12-25","localName":"Otro año","global":true}]', false);
  end if;
end
$$;
select ok(
  to_regclass('net._http_response') is null
  or (public.chile_public_holidays_refresh_internal('2026-11-22 12:30 America/Santiago') ->> 'added') = '1',
  'a national holiday of the asked year is added; a regional one or another year''s is not');
select ok(
  to_regclass('net._http_response') is null
  or (exists (select 1 from public.chile_public_holidays where holiday_date = '2028-01-01')
      and not exists (select 1 from public.chile_public_holidays where holiday_date = '2028-06-07')),
  'only what applies to the whole country');

-- ---------------------------------------------------------------------------
-- La hora se ve y se cambia en la ficha (20261122040000).
-- ---------------------------------------------------------------------------

select ok(
  has_function_privilege('authenticated', 'public.supplier_order_send_settings_v1(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.set_supplier_order_send_time_v1(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.set_supplier_order_send_time_v1(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_order_send_settings_v1(uuid,uuid)', 'EXECUTE'),
  'the team reads and changes the hour; a visitor does neither');

select set_config('request.jwt.claims', '{"sub":"e2e30000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e30000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  (select (s ->> 'send_time') || ':' || (s ->> 'sells_on_order') || ':' || (s ->> 'auto_send_enabled')
     from public.supplier_order_send_settings_v1('e2e30000-0000-4000-8000-000000000001',
       'e2e30000-0000-4000-8000-000000000031') s),
  '09:30:true:true', 'the sheet reads the hour, that it sells on order and that sending is on');
select is(
  public.set_supplier_order_send_time_v1('e2e30000-0000-4000-8000-000000000001',
    'e2e30000-0000-4000-8000-000000000031', '10:15') ->> 'send_time',
  '10:15', 'the hour changes');
select throws_like(
  $$select public.set_supplier_order_send_time_v1('e2e30000-0000-4000-8000-000000000001',
      'e2e30000-0000-4000-8000-000000000031', '21:00')$$,
  'El pedido sale entre las 07:00 y las 20:00%', 'never at night');
select throws_like(
  $$select public.set_supplier_order_send_time_v1('e2e30000-0000-4000-8000-000000000001',
      'e2e30000-0000-4000-8000-000000000031', '9.30')$$,
  'La hora va como 09:30.', 'an hour that is not one says how to write it');
select is(
  public.set_supplier_order_send_time_v1('e2e30000-0000-4000-8000-000000000001',
    'e2e30000-0000-4000-8000-000000000031', null) -> 'send_time',
  'null'::jsonb, '«Lo mando yo»: no hour');
select is(
  (select (s -> 'open_order' ->> 'send_at') is null
     from public.supplier_order_send_settings_v1('e2e30000-0000-4000-8000-000000000001',
       'e2e30000-0000-4000-8000-000000000031') s),
  true, 'without an hour the open order does not leave by itself');
select throws_ok(
  $$select public.supplier_order_send_settings_v1('e2e30000-0000-4000-8000-0000000000ff',
      'e2e30000-0000-4000-8000-000000000031')$$,
  '42501', null, 'another shop''s supplier is not readable');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select * from finish();

rollback;
