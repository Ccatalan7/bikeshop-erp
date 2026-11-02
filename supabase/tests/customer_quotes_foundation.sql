begin;

select plan(65);

-- Cotizaciones de clientes (20261102041700_customer_quotes_foundation): el
-- cliente pide productos en stock y a pedido, la base confirma lo que puede,
-- el equipo confirma el resto con los proveedores y envía una oferta, y el
-- cliente la acepta, la modifica o la rechaza con su enlace.

insert into public.tenants (id, shop_name) values
  ('c0a70000-0000-4000-8000-000000000001', 'Taller cotizaciones A'),
  ('c0a70000-0000-4000-8000-000000000002', 'Taller cotizaciones B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0a70000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'cotizaciones-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0a70000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'cotizaciones-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('c0a70000-0000-4000-8000-000000000091', 'c0a70000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb),
  ('c0a70000-0000-4000-8000-000000000092', 'c0a70000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb);

insert into public.suppliers (id, tenant_id, name, sales_rep_name, sales_rep_phone) values
  ('c0a70000-0000-4000-8000-000000000031', 'c0a70000-0000-4000-8000-000000000001',
   'Proveedor de neumáticos', 'Vendedor Uno', '+56900000001');

insert into public.products (
  id, tenant_id, name, sku, price, tax_rate, product_type, is_service, is_active,
  is_published, show_on_website, supplier_id, supplier_code
) values
  ('c0a70000-0000-4000-8000-000000000011', 'c0a70000-0000-4000-8000-000000000001',
   'Neumático en stock 29 x 2.25', 'QT-STOCK', 30000, 19, 'product', false, true, true, true, null, null),
  ('c0a70000-0000-4000-8000-000000000012', 'c0a70000-0000-4000-8000-000000000001',
   'Neumático a pedido revisado 29 x 2.40', 'QT-ORDER', 45000, 19, 'product', false, true, true, true,
   'c0a70000-0000-4000-8000-000000000031', 'TK-NEU-240'),
  ('c0a70000-0000-4000-8000-000000000013', 'c0a70000-0000-4000-8000-000000000001',
   'Cámara a pedido 29 x 2.10', 'QT-TUBE', 6000, 19, 'product', false, true, true, true,
   'c0a70000-0000-4000-8000-000000000031', 'TK-CAM-29'),
  ('c0a70000-0000-4000-8000-000000000014', 'c0a70000-0000-4000-8000-000000000001',
   'Repuesto sin publicar', 'QT-HIDDEN', 9000, 19, 'product', false, true, false, false, null, null),
  ('c0a70000-0000-4000-8000-000000000015', 'c0a70000-0000-4000-8000-000000000001',
   'Mantención', 'QT-SERVICE', 20000, null, 'service', true, true, true, true, null, null),
  ('c0a70000-0000-4000-8000-000000000016', 'c0a70000-0000-4000-8000-000000000002',
   'Producto del taller B', 'QT-B', 5000, 19, 'product', false, true, true, true, null, null),
  ('c0a70000-0000-4000-8000-000000000017', 'c0a70000-0000-4000-8000-000000000001',
   'Válvula sin proveedor', 'QT-VALVE', 4000, 19, 'product', false, true, true, true, null, null);

update public.products set inventory_qty = 3, stock_quantity = 3
 where id = 'c0a70000-0000-4000-8000-000000000011';

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('c0a70000-0000-4000-8000-000000000012', 'c0a70000-0000-4000-8000-000000000001',
   'c0a70000-0000-4000-8000-000000000031', 3, 5),
  ('c0a70000-0000-4000-8000-000000000013', 'c0a70000-0000-4000-8000-000000000001',
   'c0a70000-0000-4000-8000-000000000031', 2, 4);

-- El portal del proveedor dijo hace una hora que tiene el neumático.
insert into public.supplier_availability_checks (
  tenant_id, supplier_id, product_id, supplier_code, checked_at, status, price_net, stock_quantity
) values (
  'c0a70000-0000-4000-8000-000000000001', 'c0a70000-0000-4000-8000-000000000031',
  'c0a70000-0000-4000-8000-000000000012', 'TK-NEU-240', now() - interval '1 hour',
  'available', 25000, 8
);

-- ---------------------------------------------------------------------------
-- Estructura y permisos
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::integer from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relrowsecurity
      and c.relname in ('customer_quote_settings', 'product_on_order_terms', 'customer_quotes',
                        'customer_quote_lines', 'customer_quote_offers', 'customer_quote_offer_lines',
                        'customer_quote_supplier_tasks', 'customer_quote_events',
                        'customer_quote_access_tokens')),
  9, 'the nine quote tables have row level security');
select ok(
  not has_table_privilege('anon', 'public.customer_quotes', 'select')
  and not has_table_privilege('authenticated', 'public.customer_quotes', 'insert')
  and not has_table_privilege('authenticated', 'public.customer_quote_access_tokens', 'select'),
  'anon reads nothing, the team writes only through commands and never reads link hashes');
select ok(
  has_function_privilege('anon', 'public.request_public_customer_quote_v1(uuid,jsonb)', 'execute')
  and has_function_privilege('anon', 'public.respond_public_customer_quote_v1(text,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.customer_quote_send_offer_v1(uuid,uuid,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.customer_quote_prepare_offer_internal(uuid,text,uuid,uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.expire_customer_quote_offers_v1()', 'execute'),
  'the customer reaches only the public commands; internals and expiry are closed');

-- ---------------------------------------------------------------------------
-- El cliente pide la cotización en el sitio
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"no-es-uuid","customer_name":"Ana","customer_email":"ana@example.invalid",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '22023', 'A random request idempotency key is required', 'a request needs a random key');
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-000000000001","customer_name":"Ana",
        "preferred_channel":"email","customer_phone":"912345678",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '22023', 'quote_contact_invalid', 'answering by email needs an email');
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-000000000002","customer_name":"Ana",
        "customer_email":"ana@example.invalid",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000014","quantity":1}]}')$$,
  '22023', 'quote_product_not_available', 'a product the site does not sell cannot be quoted from the site');
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-000000000003","customer_name":"Ana",
        "customer_email":"ana@example.invalid",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000016","quantity":1}]}')$$,
  '22023', 'quote_product_not_available', 'another shop''s product cannot be quoted');
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-000000000004","customer_name":"Ana",
        "customer_email":"ana@example.invalid",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000015","quantity":1}]}')$$,
  '22023', 'quote_product_not_available', 'a workshop service is not quoted as a product');

select set_config('quote.r1', public.request_public_customer_quote_v1(
  'c0a70000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-0000000000a1","customer_name":"Ana Pérez",
    "customer_phone":"9 1234 5678","preferred_channel":"whatsapp","customer_notes":"Para el sábado",
    "items":[
      {"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":2},
      {"product_id":"c0a70000-0000-4000-8000-000000000012","quantity":1},
      {"product_id":"c0a70000-0000-4000-8000-000000000013","quantity":4},
      {"product_id":"c0a70000-0000-4000-8000-000000000017","quantity":1},
      {"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":1}
    ]}')::text, true);
select set_config('quote.r1_replay', public.request_public_customer_quote_v1(
  'c0a70000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"6f1c2a3b-4d5e-4f60-8a71-0000000000a1","customer_name":"Ana Pérez",
    "customer_phone":"912345678","preferred_channel":"whatsapp",
    "items":[{"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":2}]}')::text, true);

reset role;

select set_config('quote.id', current_setting('quote.r1')::jsonb ->> 'quote_id', true);
select set_config('quote.token', current_setting('quote.r1')::jsonb ->> 'access_token', true);

select matches(current_setting('quote.r1')::jsonb ->> 'quote_number', '^COT-[0-9]{2}-[0-9]{5}$',
  'the quote gets a COT number');
select ok(length(current_setting('quote.token')) >= 40, 'the customer gets a long random link token');
select is(
  current_setting('quote.r1_replay')::jsonb ->> 'quote_id', current_setting('quote.id'),
  'repeating the same request returns the same quote');
select is(
  (select count(*)::integer from public.customer_quotes where tenant_id = 'c0a70000-0000-4000-8000-000000000001'),
  1, 'the repeat did not create a second quote');
select is(
  (select customer_phone || '|' || preferred_channel || '|' || status || '|' || source
     from public.customer_quotes where id = current_setting('quote.id')::uuid),
  '+56912345678|whatsapp|confirming|web',
  'the phone is normalized and the quote waits for confirmation');
select is(
  (select string_agg(product_sku || ':' || quantity || ':' || kind_at_request, ',' order by line_no)
     from public.customer_quote_lines where quote_id = current_setting('quote.id')::uuid),
  'QT-STOCK:3:in_stock,QT-ORDER:1:on_order,QT-TUBE:4:on_order,QT-VALVE:1:to_confirm',
  'repeated products merge and each line records what it was when asked');
select ok(
  exists (select 1 from public.customer_quote_access_tokens a
           where a.quote_id = current_setting('quote.id')::uuid
             and a.token_sha256 = encode(extensions.digest(convert_to(current_setting('quote.token'), 'UTF8'), 'sha256'), 'hex'))
  and not exists (select 1 from public.customer_quote_access_tokens a
                   where a.quote_id = current_setting('quote.id')::uuid
                     and a.token_sha256 = current_setting('quote.token')),
  'only the SHA-256 of the link is stored');

-- El borrador que arma la base sola.
select set_config('quote.offer1', (select id::text from public.customer_quote_offers
  where quote_id = current_setting('quote.id')::uuid and status = 'draft'), true);
select is(
  (select string_agg(product_sku || ':' || availability || ':' || quantity_offered || ':' || coalesce(unit_price::text, '-'),
                     ',' order by line_no)
     from public.customer_quote_offer_lines where offer_id = current_setting('quote.offer1')::uuid),
  'QT-STOCK:in_stock:3:30000,QT-ORDER:on_order:1:45000,QT-TUBE:pending:0:-,QT-VALVE:pending:0:-',
  'stock and a fresh supplier check confirm themselves; the rest waits');
select is(
  (select lead_days_min || '-' || lead_days_max || ':' || unit_cost_net::integer
     from public.customer_quote_offer_lines
    where offer_id = current_setting('quote.offer1')::uuid and product_sku = 'QT-ORDER'),
  '3-5:25000', 'the on-order line carries its lead time and the supplier cost');
select is(
  (select count(*)::integer from public.customer_quote_supplier_tasks
    where offer_id = current_setting('quote.offer1')::uuid and status = 'open'),
  2, 'one task per supplier, and one for the line without a supplier');
select ok(
  (select message_draft like '%4 × Cámara a pedido 29 x 2.10 (código TK-CAM-29)%'
     from public.customer_quote_supplier_tasks
    where offer_id = current_setting('quote.offer1')::uuid
      and supplier_id = 'c0a70000-0000-4000-8000-000000000031'),
  'the supplier task has the message for its sales rep, with the supplier code');
select is(
  (select string_agg(event_type || ':' || actor_kind, ',' order by id)
     from public.customer_quote_events where quote_id = current_setting('quote.id')::uuid),
  'requested:customer,offer_prepared:system,supplier_task_opened:system',
  'the history records the request and the prepared draft');
select is(
  (select route || '|' || severity from public.erp_notifications
    where tenant_id = 'c0a70000-0000-4000-8000-000000000001' and type = 'customer_quote_requested'),
  '/sales/quotes/' || current_setting('quote.id') || '|info',
  'the team gets an ERP notice that opens the quote');

-- ---------------------------------------------------------------------------
-- El enlace del cliente antes de la oferta
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('quote.view0', public.get_public_customer_quote_v1(current_setting('quote.token'))::text, true);
select set_config('quote.bad', coalesce(public.get_public_customer_quote_v1(repeat('x', 43))::text, 'null'), true);
reset role;

select is(
  (current_setting('quote.view0')::jsonb -> 'quote' ->> 'status')
    || '|' || coalesce(current_setting('quote.view0')::jsonb ->> 'offer', 'none')
    || '|' || (current_setting('quote.view0')::jsonb -> 'actions' ->> 'accept'),
  'confirming|none|false', 'before the offer the customer sees the request, not the draft');
select is(current_setting('quote.bad'), 'null', 'an unknown link shows nothing');

-- ---------------------------------------------------------------------------
-- El equipo confirma con los proveedores y envía la oferta
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0a70000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a70000-0000-4000-8000-000000000092', true);
set local role authenticated;
select throws_ok(
  format($$select public.customer_quote_detail_v1('c0a70000-0000-4000-8000-000000000001', %L)$$,
         current_setting('quote.id')),
  '42501', 'Quote not found or not accessible', 'another shop cannot open the quote');
select is(
  (select count(*)::integer from public.customer_quotes),
  0, 'another shop reads no quotes');
reset role;

select set_config('request.jwt.claims', '{"sub":"c0a70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a70000-0000-4000-8000-000000000091', true);
set local role authenticated;

select is(
  (public.customer_quote_inbox_v1('c0a70000-0000-4000-8000-000000000001') -> 'quotes' -> 0 ->> 'openTasks')::integer,
  2, 'the inbox shows the open supplier tasks');
select throws_ok(
  format($$select public.customer_quote_send_offer_v1('c0a70000-0000-4000-8000-000000000001', %L,
           '7a1c2a3b-4d5e-4f60-8a71-000000000001')$$, current_setting('quote.id')),
  '55000', 'quote_lines_pending', 'an offer with pending lines cannot be sent');

-- El proveedor tiene 3 cámaras de las 4: se ofrecen 3.
select set_config('quote.tmp', public.customer_quote_confirm_line_v1(
  'c0a70000-0000-4000-8000-000000000001',
  (select id from public.customer_quote_offer_lines
    where offer_id = current_setting('quote.offer1')::uuid and product_sku = 'QT-TUBE'),
  '{"availability":"on_order","quantity_offered":3,"unit_price":6500,"lead_days_min":2,"lead_days_max":4,
    "unit_cost_net":3800,"customer_note":"El proveedor tiene 3"}')::text, true);
select set_config('quote.tmp', public.customer_quote_confirm_line_v1(
  'c0a70000-0000-4000-8000-000000000001',
  (select id from public.customer_quote_offer_lines
    where offer_id = current_setting('quote.offer1')::uuid and product_sku = 'QT-VALVE'),
  '{"availability":"unavailable","customer_note":"Sin stock en Chile"}')::text, true);

select is(
  (select string_agg(coalesce(s.name, 'sin proveedor') || ':' || t.status, ',' order by s.name nulls last)
     from public.customer_quote_supplier_tasks t
     left join public.suppliers s on s.id = t.supplier_id
    where t.offer_id = current_setting('quote.offer1')::uuid),
  'Proveedor de neumáticos:done,sin proveedor:done',
  'a supplier task closes itself when its lines are confirmed');

select set_config('quote.sent1', public.customer_quote_send_offer_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000002', 'Gracias por cotizar con nosotros')::text, true);
select set_config('quote.sent1_replay', public.customer_quote_send_offer_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000002', 'Gracias por cotizar con nosotros')::text, true);
reset role;

select is(
  (select status || '|' || total::integer || '|' || tax_amount::integer || '|' || subtotal::integer
     from public.customer_quote_offers where id = current_setting('quote.offer1')::uuid),
  'sent|154500|24668|129832',
  'the sent offer freezes totals with IVA included (3 × 30.000 + 45.000 + 3 × 6.500)');
select ok(
  (select q.status = 'offered' and q.current_offer_id = current_setting('quote.offer1')::uuid
          and q.expires_at between now() + interval '71 hours' and now() + interval '73 hours'
     from public.customer_quotes q where q.id = current_setting('quote.id')::uuid),
  'the quote is offered and valid for 72 hours by default');
select is(
  current_setting('quote.sent1_replay')::jsonb ->> 'replay', 'true',
  'sending twice with the same key is one send');
select is(
  (select count(*)::integer from public.customer_quote_events
    where quote_id = current_setting('quote.id')::uuid and event_type = 'offer_sent'),
  1, 'one offer_sent event');
select throws_ok(
  format($$update public.customer_quote_offer_lines set unit_price = 1
            where offer_id = %L and product_sku = 'QT-STOCK'$$, current_setting('quote.offer1')),
  '42501', 'A sent quote offer is frozen', 'the lines of a sent offer cannot be rewritten');
select throws_ok(
  format($$update public.customer_quote_offers set total = 1 where id = %L$$, current_setting('quote.offer1')),
  '42501', 'A sent quote offer is frozen', 'the totals of a sent offer cannot be rewritten');
select throws_ok(
  format($$update public.customer_quote_events set detail = '{}' where quote_id = %L$$, current_setting('quote.id')),
  '42501', 'customer_quote_events is append-only', 'the history cannot be rewritten');

-- ---------------------------------------------------------------------------
-- El cliente ve la oferta y pide cambios
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('quote.view1', public.get_public_customer_quote_v1(current_setting('quote.token'))::text, true);
select set_config('quote.tmp', public.get_public_customer_quote_v1(current_setting('quote.token'))::text, true);
select set_config('quote.changes', public.respond_public_customer_quote_v1(
  current_setting('quote.token'),
  jsonb_build_object('action', 'request_changes', 'operation_key', '8a1c2a3b-4d5e-4f60-8a71-000000000001',
                     'offer_id', current_setting('quote.offer1'), 'note', 'Sólo 2 cámaras',
                     'lines', jsonb_build_array(jsonb_build_object('line_no', 3, 'quantity', 2))))::text, true);
select set_config('quote.changes_replay', public.respond_public_customer_quote_v1(
  current_setting('quote.token'),
  jsonb_build_object('action', 'request_changes', 'operation_key', '8a1c2a3b-4d5e-4f60-8a71-000000000001',
                     'offer_id', current_setting('quote.offer1'), 'note', 'Sólo 2 cámaras',
                     'lines', jsonb_build_array(jsonb_build_object('line_no', 3, 'quantity', 2))))::text, true);
reset role;

select is(
  (current_setting('quote.view1')::jsonb -> 'offer' ->> 'total')::integer
    || '|' || jsonb_array_length(current_setting('quote.view1')::jsonb -> 'offer' -> 'lines')
    || '|' || (current_setting('quote.view1')::jsonb -> 'actions' ->> 'accept'),
  '154500|4|true', 'the customer sees the offer with every line and can answer');
select is(
  (select string_agg(l ->> 'availability' || ':' || (l ->> 'quantityRequested') || '>' || (l ->> 'quantity'), ','
                     order by (l ->> 'lineNo')::integer)
     from jsonb_array_elements(current_setting('quote.view1')::jsonb -> 'offer' -> 'lines') l),
  'in_stock:3>3,on_order:1>1,on_order:4>3,unavailable:1>0',
  'the partial line shows asked versus offered, and the unavailable one shows zero');
select ok(
  current_setting('quote.view1') not like '%unit_cost_net%'
  and current_setting('quote.view1') not like '%unitCost%'
  and current_setting('quote.view1') not like '%Proveedor de neumáticos%'
  and current_setting('quote.view1') not like '%supplier%'
  and current_setting('quote.view1') not like '%staff%',
  'the customer never sees supplier, cost or internal notes');
select is(
  (select count(*)::integer from public.customer_quote_events
    where quote_id = current_setting('quote.id')::uuid and event_type = 'viewed'),
  1, 'the first view of the offer is recorded once');
select is(
  current_setting('quote.changes_replay')::jsonb ->> 'replay', 'true',
  'the same answer twice is one answer');
select is(
  (select string_agg(offer_no || ':' || status, ',' order by offer_no)
     from public.customer_quote_offers where quote_id = current_setting('quote.id')::uuid),
  '1:superseded,2:draft', 'asking for changes replaces the offer with a new draft');
select set_config('quote.offer2', (select id::text from public.customer_quote_offers
  where quote_id = current_setting('quote.id')::uuid and offer_no = 2), true);
select is(
  (select string_agg(product_sku || ':' || availability || ':' || quantity_offered || ':' || unit_price::integer,
                     ',' order by line_no)
     from public.customer_quote_offer_lines where offer_id = current_setting('quote.offer2')::uuid),
  'QT-STOCK:in_stock:3:30000,QT-ORDER:on_order:1:45000,QT-TUBE:on_order:2:6500',
  'what was confirmed and does not grow stays confirmed; the unavailable line leaves');
select is(
  (select count(*)::integer from public.customer_quote_supplier_tasks
    where offer_id = current_setting('quote.offer2')::uuid),
  0, 'nothing to ask the supplier again');
select is(
  (select status from public.customer_quotes where id = current_setting('quote.id')::uuid),
  'confirming', 'the quote goes back to the team');
select ok(
  exists (select 1 from public.erp_notifications
           where tenant_id = 'c0a70000-0000-4000-8000-000000000001'
             and type = 'customer_quote_changes_requested'
             and entity_id = current_setting('quote.offer1')::uuid),
  'the team is told the customer asked for changes');

-- El equipo envía la oferta 2 y el cliente la acepta.
select set_config('request.jwt.claims', '{"sub":"c0a70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('quote.tmp', public.customer_quote_send_offer_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000003')::text, true);
reset role;

select is(
  (select total::integer from public.customer_quote_offers where id = current_setting('quote.offer2')::uuid),
  148000, 'the second offer totals 3 × 30.000 + 45.000 + 2 × 6.500');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  format($$select public.respond_public_customer_quote_v1(%L,
           jsonb_build_object('action', 'accept', 'operation_key', '8a1c2a3b-4d5e-4f60-8a71-000000000002',
                              'offer_id', %L))$$,
         current_setting('quote.token'), current_setting('quote.offer1')),
  '40001', 'quote_offer_outdated', 'accepting an old offer is refused');
select throws_ok(
  $$select public.respond_public_customer_quote_v1(repeat('y', 43),
      '{"action":"accept","operation_key":"8a1c2a3b-4d5e-4f60-8a71-000000000003"}')$$,
  '42501', 'quote_link_invalid', 'a wrong link cannot answer');
select set_config('quote.accept', public.respond_public_customer_quote_v1(
  current_setting('quote.token'),
  jsonb_build_object('action', 'accept', 'operation_key', '8a1c2a3b-4d5e-4f60-8a71-000000000004',
                     'offer_id', current_setting('quote.offer2')))::text, true);
select throws_ok(
  format($$select public.respond_public_customer_quote_v1(%L,
           '{"action":"reject","operation_key":"8a1c2a3b-4d5e-4f60-8a71-000000000005"}')$$,
         current_setting('quote.token')),
  '55000', 'quote_not_open', 'an accepted quote takes no other answer');
reset role;

select is(
  (select q.status || '|' || o.status from public.customer_quotes q
     join public.customer_quote_offers o on o.id = q.current_offer_id
    where q.id = current_setting('quote.id')::uuid),
  'accepted|accepted', 'accepting closes the quote and the offer');
select ok(
  exists (select 1 from public.erp_notifications
           where tenant_id = 'c0a70000-0000-4000-8000-000000000001'
             and type = 'customer_quote_accepted' and severity = 'success'),
  'the team is told the quote was accepted');
select is(
  (select string_agg(event_type, ',' order by id) from public.customer_quote_events
    where quote_id = current_setting('quote.id')::uuid and actor_kind = 'customer'),
  'requested,viewed,changes_requested,offer_prepared,accepted',
  'every customer step is in the history, including the draft their changes started');

-- ---------------------------------------------------------------------------
-- Cotización del mesón: vence, se revisa y se anula
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0a70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_ok(
  $$select public.create_staff_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"customer_name":"Luis","items":[{"product_id":"c0a70000-0000-4000-8000-000000000014","quantity":1}]}')$$,
  '22023', 'quote_contact_invalid', 'a quote needs a way to answer the customer');
select set_config('quote.s1', public.create_staff_customer_quote_v1(
  'c0a70000-0000-4000-8000-000000000001',
  '{"customer_name":"Luis Soto","customer_email":"LUIS@example.invalid",
    "items":[{"product_id":"c0a70000-0000-4000-8000-000000000014","quantity":1}]}')::text, true);
select set_config('quote.s1id', current_setting('quote.s1')::jsonb ->> 'quote_id', true);
select set_config('quote.tmp', public.customer_quote_confirm_line_v1(
  'c0a70000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('quote.s1id')::uuid and o.status = 'draft'),
  '{"availability":"on_order","quantity_offered":1,"lead_days_min":5,"lead_days_max":8}')::text, true);
select set_config('quote.tmp', public.customer_quote_send_offer_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.s1id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000004')::text, true);
reset role;

select is(
  (select source || '|' || customer_email || '|' || preferred_channel || '|' || status
     from public.customer_quotes where id = current_setting('quote.s1id')::uuid),
  'staff|luis@example.invalid|email|offered',
  'the counter can quote an unpublished part, and the email is normalized');
select is(
  (select l.unit_price::integer || '|' || l.lead_days_min || '-' || l.lead_days_max
     from public.customer_quote_offer_lines l
     join public.customer_quotes q on q.current_offer_id = l.offer_id
    where q.id = current_setting('quote.s1id')::uuid),
  '9000|5-8', 'without a price the confirmation uses the published price');

-- Tres días después la oferta vence sola.
set local session_replication_role = replica;
update public.customer_quote_offers set valid_until = now() - interval '1 minute'
 where quote_id = current_setting('quote.s1id')::uuid and status = 'sent';
set local session_replication_role = origin;

select is(public.expire_customer_quote_offers_v1(), 1, 'the expiry job closes one offer');
select is(
  (select q.status || '|' || o.status from public.customer_quotes q
     join public.customer_quote_offers o on o.id = q.current_offer_id
    where q.id = current_setting('quote.s1id')::uuid),
  'expired|expired', 'the quote and its offer are expired');
select is(public.expire_customer_quote_offers_v1(), 0, 'running the job again changes nothing');

select set_config('request.jwt.claims', '{"sub":"c0a70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0a70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('quote.tmp', public.customer_quote_revise_offer_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.s1id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000005')::text, true);
select set_config('quote.cancel', public.customer_quote_cancel_v1(
  'c0a70000-0000-4000-8000-000000000001', current_setting('quote.s1id')::uuid,
  '7a1c2a3b-4d5e-4f60-8a71-000000000006', 'El cliente compró en otro lado')::text, true);
select throws_ok(
  $$select public.set_product_on_order_terms_v1('c0a70000-0000-4000-8000-000000000002',
      'c0a70000-0000-4000-8000-000000000014', '{"lead_days_min":3,"lead_days_max":5}')$$,
  '42501', 'Quote not found or not accessible', 'a user cannot act for another shop');
select set_config('quote.terms', public.set_product_on_order_terms_v1('c0a70000-0000-4000-8000-000000000001',
  'c0a70000-0000-4000-8000-000000000014',
  '{"supplier_id":"c0a70000-0000-4000-8000-000000000031","lead_days_min":4,"lead_days_max":6}')::text, true);
reset role;

select is(
  (select string_agg(offer_no || ':' || status, ',' order by offer_no)
     from public.customer_quote_offers where quote_id = current_setting('quote.s1id')::uuid),
  '1:expired,2:cancelled', 'reopening an expired quote made a new draft, then cancelling closed it');
select is(
  (select status || '|' || closed_reason from public.customer_quotes where id = current_setting('quote.s1id')::uuid),
  'cancelled|El cliente compró en otro lado', 'a cancelled quote keeps its reason');
select is(
  (select string_agg(event_type, ',' order by id) from public.customer_quote_events
    where quote_id = current_setting('quote.s1id')::uuid and actor_kind <> 'customer'),
  'requested,offer_prepared,supplier_task_opened,line_confirmed,supplier_task_done,offer_sent,expired,offer_prepared,offer_revised,cancelled',
  'the counter quote history is complete');
select is(
  current_setting('quote.terms')::jsonb ->> 'lead_days_max', '6', 'a product can be set as sold on order');

-- El sitio pregunta qué se vende a pedido, sin ver al proveedor.
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('quote.public_terms', public.get_public_on_order_terms_v1(
  'c0a70000-0000-4000-8000-000000000001',
  array['c0a70000-0000-4000-8000-000000000011', 'c0a70000-0000-4000-8000-000000000012',
        'c0a70000-0000-4000-8000-000000000013']::uuid[])::text, true);
reset role;

select is(
  current_setting('quote.public_terms')::jsonb,
  '{"c0a70000-0000-4000-8000-000000000012":{"leadDaysMin":3,"leadDaysMax":5},
    "c0a70000-0000-4000-8000-000000000013":{"leadDaysMin":2,"leadDaysMax":4}}'::jsonb,
  'the site learns the lead time of what is sold on order, and nothing about the supplier');

-- ---------------------------------------------------------------------------
-- Freno a formularios automatizados
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select public.request_public_customer_quote_v1(
  'c0a70000-0000-4000-8000-000000000001',
  jsonb_build_object('request_idempotency_key', '9b1c2a3b-4d5e-4f60-8a71-' || lpad(n::text, 12, '0'),
                     'customer_name', 'Robot', 'customer_email', 'robot@example.invalid',
                     'items', jsonb_build_array(jsonb_build_object(
                       'product_id', 'c0a70000-0000-4000-8000-000000000011', 'quantity', 1))))
  from generate_series(1, 10) n;
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0a70000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"9b1c2a3b-4d5e-4f60-8a71-000000000099","customer_name":"Robot",
        "customer_email":"robot@example.invalid",
        "items":[{"product_id":"c0a70000-0000-4000-8000-000000000011","quantity":1}]}')$$,
  '54000', 'quote_rate_limited', 'the eleventh quote of the day from one contact is refused');
reset role;

select * from finish();
rollback;
