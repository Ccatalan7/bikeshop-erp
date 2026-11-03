begin;

select plan(62);

-- Cotizaciones, etapa 5 (20261103010000): aceptar crea el pedido web con los
-- precios de la oferta, lo que hay se aparta, lo que viene a pedido espera:
-- el pago queda en el pedido, sale un borrador de compra por proveedor y la
-- venta se emite cuando llega todo. Los avisos siguen lo que eligió el
-- cliente.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh):
-- la base local no tiene el núcleo de pedidos, pagos y compras de producción.

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0b50000-0000-4000-8000-000000000001', 'Taller pedidos', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0b50000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0b50000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0b50000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'ana@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0b50000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'beto@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('c0b50000-0000-4000-8000-000000000094', 'authenticated', 'authenticated',
   'carla@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
delete from public.user_profiles where user_id = 'c0b50000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0b50000-0000-4000-8000-000000000091', 'c0b50000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0b50000-0000-4000-8000-0000000000c1', 'c0b50000-0000-4000-8000-000000000001',
   'c0b50000-0000-4000-8000-000000000092', 'Ana Pérez', 'ana@example.invalid', null, true),
  ('c0b50000-0000-4000-8000-0000000000c2', 'c0b50000-0000-4000-8000-000000000001',
   'c0b50000-0000-4000-8000-000000000093', 'Beto Rojas', 'beto@example.invalid', '+56911112222', true),
  ('c0b50000-0000-4000-8000-0000000000c3', 'c0b50000-0000-4000-8000-000000000001',
   'c0b50000-0000-4000-8000-000000000094', 'Carla Soto', 'carla@example.invalid', '+56933334444', true);

insert into public.suppliers (id, tenant_id, name, rut, sales_rep_name, sales_rep_phone) values
  ('c0b50000-0000-4000-8000-000000000031', 'c0b50000-0000-4000-8000-000000000001',
   'Proveedor de neumáticos', '76.111.222-3', 'Vendedor Uno', '+56900000001');

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('c0b50000-0000-4000-8000-000000000011', 'c0b50000-0000-4000-8000-000000000001',
   'Neumático en stock 29 x 2.25', 'Q5-STOCK', 30000, 18000, 19, 'product', false, true,
   5, 5, 0, 100, true, true, true, null),
  ('c0b50000-0000-4000-8000-000000000012', 'c0b50000-0000-4000-8000-000000000001',
   'Neumático a pedido 29 x 2.40', 'Q5-ORDER', 45000, 20000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'c0b50000-0000-4000-8000-000000000031'),
  ('c0b50000-0000-4000-8000-000000000013', 'c0b50000-0000-4000-8000-000000000001',
   'Cámara a pedido 29', 'Q5-TUBE', 6000, 2500, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'c0b50000-0000-4000-8000-000000000031'),
  ('c0b50000-0000-4000-8000-000000000014', 'c0b50000-0000-4000-8000-000000000001',
   'Última unidad', 'Q5-LAST', 10000, 5000, 19, 'product', false, true,
   1, 1, 0, 100, true, true, true, null);
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('c0b50000-0000-4000-8000-000000000012', 'c0b50000-0000-4000-8000-000000000001',
   'c0b50000-0000-4000-8000-000000000031', 3, 5),
  ('c0b50000-0000-4000-8000-000000000013', 'c0b50000-0000-4000-8000-000000000001',
   'c0b50000-0000-4000-8000-000000000031', 2, 4);

-- Lo que el checkout necesita para ofrecer Mercado Pago, transferencia y despacho.
insert into public.website_settings (tenant_id, key, value) values
  ('c0b50000-0000-4000-8000-000000000001', 'mercadopago_access_token', 'TEST-0000'),
  ('c0b50000-0000-4000-8000-000000000001', 'store_url', 'https://tienda.example.cl'),
  ('c0b50000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('c0b50000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('c0b50000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('c0b50000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Taller pedidos'),
  ('c0b50000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0');
insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross, shipping_gross, tax_rate,
  estimated_min_business_days, estimated_max_business_days
) values ('c0b50000-0000-4000-8000-000000000001', 'CL', 0, null, 4990, 19, 2, 4);

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

select ok(
  has_function_privilege('anon', 'public.accept_public_customer_quote_v1(text,jsonb)', 'EXECUTE')
  and has_function_privilege('anon', 'public.open_public_customer_quote_order_v1(text)', 'EXECUTE'),
  'the customer accepts and returns to the order with the link alone');
select ok(
  not has_function_privilege('authenticated', 'public.customer_quote_order_paid_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_order_check_arrivals_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_orders_check_arrivals_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_order_prepare_purchases_internal(uuid)', 'EXECUTE'),
  'the order internals and the arrivals sweep are not callable from the API');
select ok(
  has_function_privilege('authenticated', 'public.customer_quote_order_check_arrivals_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_order_check_arrivals_v1(uuid,uuid)', 'EXECUTE'),
  'the team checks arrivals from the ERP');

-- ---------------------------------------------------------------------------
-- Ana: en stock y a pedido, retiro, Mercado Pago
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('q5.a', public.request_public_customer_quote_v1(
  'c0b50000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,
    "items":[{"product_id":"c0b50000-0000-4000-8000-000000000011","quantity":1},
             {"product_id":"c0b50000-0000-4000-8000-000000000012","quantity":2},
             {"product_id":"c0b50000-0000-4000-8000-000000000013","quantity":1}]}')::text, true);
reset role;
select set_config('q5.qa', current_setting('q5.a')::jsonb ->> 'quote_id', true);
select set_config('q5.ta', current_setting('q5.a')::jsonb ->> 'access_token', true);

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.tmp', public.customer_quote_confirm_line_v1(
  'c0b50000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('q5.qa')::uuid and o.status = 'draft' and l.product_sku = 'Q5-ORDER'),
  '{"availability":"on_order","quantity_offered":2,"unit_price":45000,"lead_days_min":3,"lead_days_max":5,
    "unit_cost_net":25000}')::text, true);
select set_config('q5.tmp', public.customer_quote_confirm_line_v1(
  'c0b50000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('q5.qa')::uuid and o.status = 'draft' and l.product_sku = 'Q5-TUBE'),
  '{"availability":"on_order","quantity_offered":1,"unit_price":6000,"lead_days_min":2,"lead_days_max":4,
    "unit_cost_net":3000}')::text, true);
select set_config('q5.tmp', public.customer_quote_send_offer_v1(
  'c0b50000-0000-4000-8000-000000000001', current_setting('q5.qa')::uuid,
  '5d1c2a3b-4d5e-4f60-8a71-000000000001')::text, true);
reset role;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  format($$select public.respond_public_customer_quote_v1(%L,
    '{"action":"accept","operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000099"}')$$, current_setting('q5.ta')),
  '22023', 'quote_accept_requires_checkout', 'accepting only happens with delivery and payment');
select throws_ok(
  format($$select public.accept_public_customer_quote_v1(%L,
    '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000098","delivery_type":"shipping","payment_method":"transfer"}')$$,
    current_setting('q5.ta')),
  '22023', 'quote_address_required', 'shipping needs an address');
select throws_ok(
  format($$select public.accept_public_customer_quote_v1(%L,
    '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000097","delivery_type":"pickup","payment_method":"cheque"}')$$,
    current_setting('q5.ta')),
  '22023', 'quote_payment_invalid', 'only the store payment methods');
select set_config('q5.ao', public.accept_public_customer_quote_v1(
  current_setting('q5.ta'),
  '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000001","delivery_type":"pickup",
    "payment_method":"mercadopago","customer_notes":"Retiro el sábado"}')::text, true);
select set_config('q5.ao2', public.accept_public_customer_quote_v1(
  current_setting('q5.ta'),
  '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000001","delivery_type":"pickup",
    "payment_method":"mercadopago"}')::text, true);
reset role;
select set_config('q5.oa', current_setting('q5.ao')::jsonb ->> 'order_id', true);

select ok(
  current_setting('q5.ao')::jsonb ->> 'replay' = 'false'
  and length(current_setting('q5.ao')::jsonb ->> 'access_token') >= 40
  and (current_setting('q5.ao')::jsonb ->> 'waiting')::boolean
  and current_setting('q5.ao')::jsonb ->> 'order_number' like 'WEB-%',
  'accepting returns the new order, its access and that it waits for on-order items');
select ok(
  current_setting('q5.ao2')::jsonb ->> 'order_id' = current_setting('q5.oa')
  and current_setting('q5.ao2')::jsonb ->> 'replay' = 'true',
  'the same acceptance again returns the same order');
select is(
  (select o.status || ':' || o.payment_status || ':' || o.payment_method || ':' || o.delivery_type || ':'
          || o.total || ':' || o.shipping_cost || ':' || (o.customer_id = 'c0b50000-0000-4000-8000-0000000000c1')
          || ':' || o.customer_email || ':' || o.customer_notes
     from public.online_orders o where o.id = current_setting('q5.oa')::uuid),
  'pending:pending:mercadopago:pickup:126000.00:0.00:true:ana@example.invalid:Retiro el sábado',
  'the order is the account''s, at the offer''s frozen prices, pending payment');
select is(
  (select string_agg(i.product_sku || ':' || i.fulfillment || ':' || i.quantity || ':' || i.unit_price::integer
                     || ':' || coalesce(i.unit_cost::integer::text, '-') || ':' || coalesce(i.lead_days_min || '-' || i.lead_days_max, '-')
                     || ':' || (i.on_order_supplier_id is not null), ',' order by i.product_sku)
     from public.online_order_items i where i.order_id = current_setting('q5.oa')::uuid),
  'Q5-ORDER:on_order:2:45000:25000:3-5:true,Q5-STOCK:stock:1:30000:18000:-:false,Q5-TUBE:on_order:1:6000:3000:2-4:true',
  'each line says where it comes from: stock now, or the supplier with its cost and lead time');
select is(
  (select string_agg(p.sku || ':' || r.quantity || ':' || r.state, ',')
     from public.online_order_inventory_reservations r
     join public.products p on p.id = r.product_id
    where r.order_id = current_setting('q5.oa')::uuid),
  'Q5-STOCK:1:active',
  'only what is in the shop is reserved; on-order lines wait');
select is(
  (select q.status || ':' || (q.online_order_id = current_setting('q5.oa')::uuid) || ':' || o.status
     from public.customer_quotes q join public.customer_quote_offers o on o.id = q.current_offer_id
    where q.id = current_setting('q5.qa')::uuid),
  'accepted:true:accepted',
  'the quote and its offer are accepted and point at the order');
select is(
  (select count(*)::integer from public.customer_quote_messages
    where quote_id = current_setting('q5.qa')::uuid and kind = 'accepted'),
  0, 'no separate «aceptada» email: the order email is the notice');
select is(
  (select string_agg(message_kind, ',' order by created_at) from public.transactional_email_outbox
    where order_id = current_setting('q5.oa')::uuid),
  'order_received', 'Ana chose email: the order sends its «recibimos tu pedido»');

-- Mercado Pago aprueba el pago.
select set_config('q5.ev', public.record_mercadopago_payment_observation(
  current_setting('q5.oa')::uuid, 'c0b50000-0000-4000-8000-000000000001', 'MP-Q5-ANA',
  'approved', 126000, 'CLP', now() - interval '1 hour', '{}'::jsonb) ->> 'event_id', true);
select set_config('q5.p1', public.process_mercadopago_payment_observation(current_setting('q5.ev')::bigint)::text, true);

select is(
  current_setting('q5.p1')::jsonb ->> 'processing_state' || ':' || (current_setting('q5.p1')::jsonb ->> 'error_code'),
  'action_required:awaiting_on_order_stock',
  'the validated payment waits for the on-order items instead of failing');
select is(
  (select o.payment_status || ':' || o.status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta') || ':' || o.payment_reference
     from public.online_orders o where o.id = current_setting('q5.oa')::uuid),
  'paid:confirmed:sin venta:MP-Q5-ANA',
  'the order is paid and confirmed; the sale waits');
select is(
  (select stock_quantity from public.products where id = 'c0b50000-0000-4000-8000-000000000011'),
  5, 'nothing leaves stock before the sale');
select ok(
  (select r.expires_at > clock_timestamp() + interval '80 days'
     from public.online_order_inventory_reservations r
    where r.order_id = current_setting('q5.oa')::uuid and r.state = 'active'),
  'what is reserved waits up to 90 days instead of the payment window');
select is(
  (select pi.status || ':' || pi.supplier_name || ':' || jsonb_array_length(pi.items) || ':' || pi.subtotal::integer
          || ':' || pi.iva_amount::integer || ':' || pi.total::integer || ':' || (pi.invoice_number like 'PED-%')
     from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('q5.oa')::uuid),
  'draft:Proveedor de neumáticos:2:53000:10070:63070:true',
  'one draft purchase per supplier, at the confirmed costs, in Compras');
select ok(
  (select pi.notes like '%' || (select order_number from public.online_orders where id = current_setting('q5.oa')::uuid) || '%'
          and pi.notes not like '%Ana%'
     from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('q5.oa')::uuid),
  'the supplier document names the order, never the customer');
select is(
  (select count(*)::integer from public.journal_entries
    where tenant_id = 'c0b50000-0000-4000-8000-000000000001'),
  0, 'a draft purchase and a waiting order post nothing');
select is(
  (select string_agg(e.event_type, ',' order by e.id) from public.customer_quote_events e
    where e.quote_id = current_setting('q5.qa')::uuid and e.event_type like 'order_%'),
  'order_paid,order_waiting',
  'the quote history says it was paid and waits for the supplier');
select ok(
  exists (select 1 from public.erp_notifications n
           where n.tenant_id = 'c0b50000-0000-4000-8000-000000000001'
             and n.type = 'customer_quote_order_to_purchase'
             and n.entity_id = current_setting('q5.oa')::uuid and n.read_at is null),
  'the team is told to order from the supplier');
select is(
  (select string_agg(message_kind, ',' order by created_at) from public.transactional_email_outbox
    where order_id = current_setting('q5.oa')::uuid),
  'order_received,payment_confirmed', 'and Ana gets «pago confirmado» by email');

-- Llega el neumático: se aparta; la cámara todavía no.
select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 2, stock_quantity = 2 where id = 'c0b50000-0000-4000-8000-000000000012';
select set_config('request.jwt.claim.role', '', true);
select is(public.customer_quote_orders_check_arrivals_v1(), 1, 'the sweep looks at the order whose product came in');
select is(
  (select string_agg(i.product_sku || ':' || (i.arrived_at is not null), ',' order by i.product_sku)
     from public.online_order_items i
    where i.order_id = current_setting('q5.oa')::uuid and i.fulfillment = 'on_order'),
  'Q5-ORDER:true,Q5-TUBE:false',
  'the arrived tyre is marked; the tube still waits');
select is(
  (select string_agg(p.sku || ':' || r.state, ',' order by p.sku)
     from public.online_order_inventory_reservations r join public.products p on p.id = r.product_id
    where r.order_id = current_setting('q5.oa')::uuid),
  'Q5-ORDER:active,Q5-STOCK:active',
  'the arrived units are set aside for Ana');
select is(
  (select coalesce(sales_invoice_id::text, 'sin venta') from public.online_orders where id = current_setting('q5.oa')::uuid),
  'sin venta', 'with something still missing, no sale yet');

-- Llega la cámara: la venta se emite.
select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 1, stock_quantity = 1 where id = 'c0b50000-0000-4000-8000-000000000013';
select set_config('request.jwt.claim.role', '', true);
select is(public.customer_quote_orders_check_arrivals_v1(), 1, 'the sweep picks the order up again');
select is(
  (select si.status || ':' || si.total::integer || ':' || (si.date::date = current_date)
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('q5.oa')::uuid),
  'paid:126000:true',
  'everything arrived: the sale is issued that day, paid');
select ok(
  (select abs(extract(epoch from (sp.date - (now() - interval '1 hour')))) < 120
     from public.online_orders o join public.sales_payments sp on sp.invoice_id = o.sales_invoice_id
    where o.id = current_setting('q5.oa')::uuid),
  'the payment keeps the date it was received');
select is(
  (select string_agg(sku || ':' || stock_quantity, ',' order by sku) from public.products
    where tenant_id = 'c0b50000-0000-4000-8000-000000000001' and sku in ('Q5-STOCK', 'Q5-ORDER', 'Q5-TUBE')),
  'Q5-ORDER:0,Q5-STOCK:4,Q5-TUBE:0',
  'the sale takes exactly the reserved units');
select is(
  (select string_agg(distinct r.state, ',') from public.online_order_inventory_reservations r
    where r.order_id = current_setting('q5.oa')::uuid),
  'consumed', 'every reservation of the order is consumed by its sale');
select is(
  (select processing_state from public.sales_channel_payment_processing
    where payment_event_id = current_setting('q5.ev')::bigint),
  'processed', 'the Mercado Pago payment that waited is processed with the sale');
select ok(
  (select (si.items @> '[{"product_sku":"Q5-ORDER","cost":25000}]'::jsonb)
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('q5.oa')::uuid),
  'the cost of what came on order is the supplier''s confirmed cost');
select ok(
  exists (select 1 from public.customer_quote_events
           where quote_id = current_setting('q5.qa')::uuid and event_type = 'order_sale_issued')
  and exists (select 1 from public.erp_notifications n
               where n.type = 'customer_quote_order_ready' and n.entity_id = current_setting('q5.oa')::uuid)
  and (select n.read_at is not null from public.erp_notifications n
        where n.type = 'customer_quote_order_to_purchase' and n.entity_id = current_setting('q5.oa')::uuid),
  'the quote says the sale was issued; the team is told to prepare it and the purchase notice closes');

-- El equipo lo deja listo para retiro.
select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.transition_online_order_status(%L::uuid, 'processing',
    (select version from public.online_orders where id = %L::uuid), '5f1c2a3b-4d5e-4f60-8a71-000000000001')$$,
    current_setting('q5.oa'), current_setting('q5.oa')),
  'the team starts preparing it');
select lives_ok(
  format($$select public.transition_online_order_status(%L::uuid, 'ready_for_pickup',
    (select version from public.online_orders where id = %L::uuid), '5f1c2a3b-4d5e-4f60-8a71-000000000002')$$,
    current_setting('q5.oa'), current_setting('q5.oa')),
  'and leaves it ready for pickup');
reset role;
select is(
  (select string_agg(e.event_type, ',' order by e.id) from public.customer_quote_events e
    where e.quote_id = current_setting('q5.qa')::uuid and e.event_type like 'order_%'),
  'order_paid,order_waiting,order_line_arrived,order_line_arrived,order_sale_issued,order_ready',
  'the quote history follows the order to the pickup');
select is(
  (select count(*)::integer from public.customer_quote_messages
    where quote_id = current_setting('q5.qa')::uuid and kind like 'order_%'),
  0, 'Ana did not choose WhatsApp: nothing waits to be sent there');

-- ---------------------------------------------------------------------------
-- Beto: sólo WhatsApp, todo en stock, transferencia
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000093', true);
set local role authenticated;
select set_config('q5.b', public.request_public_customer_quote_v1(
  'c0b50000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5c1c2a3b-4d5e-4f60-8a71-000000000002","notify_whatsapp":true,
    "items":[{"product_id":"c0b50000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
reset role;
select set_config('q5.qb', current_setting('q5.b')::jsonb ->> 'quote_id', true);
select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.tmp', public.customer_quote_send_offer_v1(
  'c0b50000-0000-4000-8000-000000000001', current_setting('q5.qb')::uuid,
  '5d1c2a3b-4d5e-4f60-8a71-000000000002')::text, true);
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('q5.bo', public.accept_public_customer_quote_v1(
  current_setting('q5.b')::jsonb ->> 'access_token',
  '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000002","delivery_type":"pickup","payment_method":"transfer"}')::text, true);
reset role;
select set_config('q5.ob', current_setting('q5.bo')::jsonb ->> 'order_id', true);

select is(
  (select o.status || ':' || si.status || ':' || (current_setting('q5.bo')::jsonb ->> 'waiting')
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('q5.ob')::uuid),
  'confirmed:sent:false',
  'all in stock with transfer: the sale is born at once, like any transfer order');
select is(
  (select count(*)::integer from public.transactional_email_outbox where order_id = current_setting('q5.ob')::uuid),
  0, 'Beto did not choose email: his order sends no emails');

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.confirm_online_order_payment(%L::uuid, 'TRF-BETO-1', now())$$, current_setting('q5.ob')),
  'the team confirms the transfer as always');
reset role;
select is(
  (select o.payment_status || ':' || si.status
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('q5.ob')::uuid),
  'paid:paid', 'the sale is paid');
select is(
  (select string_agg(m.kind || ':' || m.channel || ':' || m.state || ':' || m.recipient, ',')
     from public.customer_quote_messages m
    where m.quote_id = current_setting('q5.qb')::uuid and m.kind like 'order_%'),
  'order_paid:whatsapp:needs_staff:+56911112222',
  'Beto chose WhatsApp: «recibimos tu pago» waits for the team to send it');
select is(
  (select count(*)::integer from public.transactional_email_outbox where order_id = current_setting('q5.ob')::uuid),
  0, 'and still no email');

-- ---------------------------------------------------------------------------
-- Carla: a pedido, despacho, transferencia
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000094', true);
set local role authenticated;
select set_config('q5.c', public.request_public_customer_quote_v1(
  'c0b50000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5c1c2a3b-4d5e-4f60-8a71-000000000003","notify_email":true,"notify_whatsapp":true,
    "items":[{"product_id":"c0b50000-0000-4000-8000-000000000012","quantity":1}]}')::text, true);
reset role;
select set_config('q5.qc', current_setting('q5.c')::jsonb ->> 'quote_id', true);
select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.tmp', public.customer_quote_confirm_line_v1(
  'c0b50000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('q5.qc')::uuid and o.status = 'draft' and l.product_sku = 'Q5-ORDER'),
  '{"availability":"on_order","quantity_offered":1,"unit_price":45000,"lead_days_min":3,"lead_days_max":5,
    "unit_cost_net":25000}')::text, true);
select set_config('q5.tmp', public.customer_quote_send_offer_v1(
  'c0b50000-0000-4000-8000-000000000001', current_setting('q5.qc')::uuid,
  '5d1c2a3b-4d5e-4f60-8a71-000000000003')::text, true);
reset role;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  format($$select public.accept_public_customer_quote_v1(%L,
    '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000096","delivery_type":"shipping","payment_method":"transfer",
      "shipping_address_line1":"Calle Uno 123","shipping_city":"Viña del Mar","shipping_state":"Valparaíso",
      "shipping_quote_cost":1000}')$$, current_setting('q5.c')::jsonb ->> 'access_token'),
  '40001', 'Shipping quote changed; refresh checkout before paying',
  'the shipping cost the customer saw has to be the current one');
select set_config('q5.co', public.accept_public_customer_quote_v1(
  current_setting('q5.c')::jsonb ->> 'access_token',
  '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000003","delivery_type":"shipping","payment_method":"transfer",
    "shipping_address_line1":"Calle Uno 123","shipping_city":"Viña del Mar","shipping_state":"Valparaíso",
    "shipping_quote_cost":4990}')::text, true);
reset role;
select set_config('q5.oc', current_setting('q5.co')::jsonb ->> 'order_id', true);

select is(
  (select o.total::integer || ':' || o.shipping_cost::integer || ':' || o.shipping_city || ':' || o.status
          || ':' || coalesce(o.sales_invoice_id::text, 'sin venta')
     from public.online_orders o where o.id = current_setting('q5.oc')::uuid),
  '49990:4990:Viña del Mar:pending:sin venta',
  'with shipping the order carries the current shipping cost; on order, no sale is born yet');

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.confirm_online_order_payment(%L::uuid, 'TRF-CARLA-1', now() - interval '2 hours')$$,
    current_setting('q5.oc')),
  'the team confirms the transfer of an order that waits for the supplier');
reset role;
select is(
  (select o.payment_status || ':' || o.status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta') || ':'
          || o.payment_reference || ':'
          || (select count(*) from public.customer_quote_purchase_orders po where po.online_order_id = o.id)
     from public.online_orders o where o.id = current_setting('q5.oc')::uuid),
  'paid:confirmed:sin venta:TRF-CARLA-1:1',
  'the transfer stays in the order and the supplier draft is ready');
select is(
  (select string_agg(m.kind || ':' || m.channel, ',' order by m.kind)
     from public.customer_quote_messages m
    where m.quote_id = current_setting('q5.qc')::uuid and m.kind like 'order_%'),
  'order_paid:whatsapp', 'Carla chose both: WhatsApp waits for the team, email goes by itself');

select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 1, stock_quantity = 1 where id = 'c0b50000-0000-4000-8000-000000000012';
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.cr', public.customer_quote_order_check_arrivals_v1(
  'c0b50000-0000-4000-8000-000000000001', current_setting('q5.qc')::uuid)::text, true);
reset role;
select is(
  (select si.status || ':' || si.total::integer || ':' || (si.date::date = current_date)
          || ':' || (si.items @> '[{"line_kind":"shipping"}]'::jsonb)
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('q5.oc')::uuid),
  'paid:49990:true:true',
  '«Revisar si llegó» issues the sale with its shipping line, that day');
select ok(
  (select abs(extract(epoch from (sp.date - (now() - interval '2 hours')))) < 120
          and sp.reference = 'TRF-CARLA-1'
     from public.online_orders o join public.sales_payments sp on sp.invoice_id = o.sales_invoice_id
    where o.id = current_setting('q5.oc')::uuid),
  'the transfer keeps its date and reference in the sale');

-- ---------------------------------------------------------------------------
-- Lo prometido en stock que se acabó recién
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('q5.d', public.request_public_customer_quote_v1(
  'c0b50000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"5c1c2a3b-4d5e-4f60-8a71-000000000004","notify_email":true,
    "items":[{"product_id":"c0b50000-0000-4000-8000-000000000014","quantity":1}]}')::text, true);
reset role;
select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.tmp', public.customer_quote_send_offer_v1(
  'c0b50000-0000-4000-8000-000000000001', (current_setting('q5.d')::jsonb ->> 'quote_id')::uuid,
  '5d1c2a3b-4d5e-4f60-8a71-000000000004')::text, true);
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 0, stock_quantity = 0 where id = 'c0b50000-0000-4000-8000-000000000014';
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  format($$select public.accept_public_customer_quote_v1(%L,
    '{"operation_key":"5e1c2a3b-4d5e-4f60-8a71-000000000004","delivery_type":"pickup","payment_method":"transfer"}')$$,
    current_setting('q5.d')::jsonb ->> 'access_token'),
  '40001', 'quote_stock_changed', 'what the offer promised in stock and is gone is not sold on order silently');
reset role;
select is(
  (select status from public.customer_quotes where id = (current_setting('q5.d')::jsonb ->> 'quote_id')::uuid),
  'offered', 'the quote stays open to ask for a new offer');

-- ---------------------------------------------------------------------------
-- Lo que leen la tienda y el ERP
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('q5.view', public.get_public_customer_quote_v1(current_setting('q5.ta'))::text, true);
select set_config('q5.open', public.open_public_customer_quote_order_v1(current_setting('q5.ta'))::text, true);
select set_config('q5.orderview', public.get_public_online_order_by_access_token(
  current_setting('q5.open')::jsonb ->> 'access_token')::text, true);
reset role;

select is(
  (current_setting('q5.view')::jsonb #>> '{order,status}') || ':'
    || (current_setting('q5.view')::jsonb #>> '{order,waiting}') || ':'
    || jsonb_array_length(current_setting('q5.view')::jsonb #> '{order,lines}') || ':'
    || (current_setting('q5.view')::jsonb #>> '{actions,openOrder}'),
  'ready_for_pickup:false:3:true',
  'the quote page shows its order, what came on order and how to open it');
select ok(
  current_setting('q5.view') not like '%supplier%'
  and current_setting('q5.view') not like '%25000%'
  and current_setting('q5.view') not like '%access_token%',
  'the quote page never shows the supplier, the cost or an order access');
select ok(
  current_setting('q5.open')::jsonb ->> 'order_id' = current_setting('q5.oa')
  and (current_setting('q5.orderview')::jsonb #>> '{order,quoteNumber}')
      = (select quote_number from public.customer_quotes where id = current_setting('q5.qa')::uuid),
  'the quote link opens its order, which says which quote it came from');
select is(
  (select string_agg((i ->> 'sku') || ':' || (i ->> 'onOrder') || ':' || (i ->> 'arrived'), ',' order by i ->> 'sku')
     from jsonb_array_elements(current_setting('q5.orderview')::jsonb -> 'items') i),
  'Q5-ORDER:true:true,Q5-STOCK:false:false,Q5-TUBE:true:true',
  'the order page knows which lines came on order and that they arrived');

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('q5.detail', public.customer_quote_detail_v1(
  'c0b50000-0000-4000-8000-000000000001', current_setting('q5.qa')::uuid)::text, true);
select set_config('q5.inbox', public.customer_quote_inbox_v1('c0b50000-0000-4000-8000-000000000001')::text, true);
reset role;
select is(
  (current_setting('q5.detail')::jsonb #>> '{order,number}' is not null)::text || ':'
    || (current_setting('q5.detail')::jsonb #>> '{order,invoice_number}' like 'INV-%')::text || ':'
    || (current_setting('q5.detail')::jsonb #>> '{order,purchases,0,status}') || ':'
    || (current_setting('q5.detail')::jsonb #>> '{order,purchases,0,sales_rep_phone}') || ':'
    || (select string_agg(i ->> 'fulfillment', ',' order by i ->> 'product_sku')
          from jsonb_array_elements(current_setting('q5.detail')::jsonb #> '{order,items}') i),
  'true:true:draft:+56900000001:on_order,stock,on_order',
  'the ERP detail shows the order, its sale, the supplier draft and each line''s source');
select is(
  (select r ->> 'orderNumber' is not null
     from jsonb_array_elements(current_setting('q5.inbox')::jsonb -> 'quotes') r
    where r ->> 'id' = current_setting('q5.qa')),
  true, 'the inbox row carries the order number');

select set_config('request.jwt.claims', '{"sub":"c0b50000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0b50000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('q5.mine', public.list_my_customer_quotes_v1('c0b50000-0000-4000-8000-000000000001')::text, true);
reset role;
select ok(
  exists (select 1 from jsonb_array_elements(current_setting('q5.mine')::jsonb) r
           where r ->> 'id' = current_setting('q5.qa') and r ->> 'orderNumber' like 'WEB-%'),
  '«Mi cuenta» shows the order number of an accepted quote');

select * from finish();
rollback;
