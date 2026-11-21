begin;

select plan(41);

-- Lo que llega del proveedor se compra directo, con su plazo
-- (20261120210000). Una sola regla decide qué se vende así y cuánto
-- (proveedor con lector: lo que tiene menos 5, menos lo vendido sin llegar,
-- con tope por compra según el precio; lectura de menos de 3 horas). El pedido
-- web marca esas líneas `on_order` y sigue el camino de la etapa 5 sin
-- cotización: al pagar, el PED por proveedor; al llegar, la venta; si no
-- llega, «Anular y devolver» desde Pedidos web.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('d1d10000-0000-4000-8000-000000000001', 'Taller plazo', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d1d10000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-plazo@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"d1d10000-0000-4000-8000-000000000001"}'::jsonb, now(), now());
delete from public.user_profiles where user_id = 'd1d10000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('d1d10000-0000-4000-8000-000000000091', 'd1d10000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

insert into public.suppliers (id, tenant_id, name, rut, sales_rep_name, sales_rep_phone) values
  ('d1d10000-0000-4000-8000-000000000031', 'd1d10000-0000-4000-8000-000000000001',
   'Distribuidor con lector', '76.111.222-3', 'Vendedor Uno', '+56900000001'),
  ('d1d10000-0000-4000-8000-000000000032', 'd1d10000-0000-4000-8000-000000000001',
   'Distribuidor sin lector', '76.333.444-5', null, null);

insert into public.supplier_catalog_feeds (
  id, tenant_id, supplier_id, format, endpoint_template, last_ok_at, last_status
) values (
  'd1d10000-0000-4000-8000-0000000000f1', 'd1d10000-0000-4000-8000-000000000001',
  'd1d10000-0000-4000-8000-000000000031', 'mkr_csv_v1',
  'https://proveedor.example.cl/api/endpoint?token={token}',
  now() - interval '10 minutes', 'ok'
);
insert into public.supplier_catalog_feed_items (
  tenant_id, feed_id, supplier_id, supplier_sku, barcode, name, stock
) values
  ('d1d10000-0000-4000-8000-000000000001', 'd1d10000-0000-4000-8000-0000000000f1',
   'd1d10000-0000-4000-8000-000000000031', 'PRV-1', null, 'Cadena', 40),
  ('d1d10000-0000-4000-8000-000000000001', 'd1d10000-0000-4000-8000-0000000000f1',
   'd1d10000-0000-4000-8000-000000000031', 'PRV-2', null, 'Pedales', 7),
  ('d1d10000-0000-4000-8000-000000000001', 'd1d10000-0000-4000-8000-0000000000f1',
   'd1d10000-0000-4000-8000-000000000031', 'PRV-3', null, 'Kit', 4),
  ('d1d10000-0000-4000-8000-000000000001', 'd1d10000-0000-4000-8000-0000000000f1',
   'd1d10000-0000-4000-8000-000000000031', 'PRV-4', '7800000000004', 'Casco', 100);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, supplier_code, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('d1d10000-0000-4000-8000-000000000011', 'd1d10000-0000-4000-8000-000000000001',
   'Cámara en stock 29', 'PZ-STOCK', null, 5000, 2000, 19, 'product', false, true,
   5, 5, 0, 100, true, true, true, null),
  ('d1d10000-0000-4000-8000-000000000012', 'd1d10000-0000-4000-8000-000000000001',
   'Cadena 12 v', 'PZ-ORD1', 'PRV-1', 20000, 9000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'd1d10000-0000-4000-8000-000000000031'),
  ('d1d10000-0000-4000-8000-000000000013', 'd1d10000-0000-4000-8000-000000000001',
   'Pedales de aluminio', 'PZ-ORD2', 'PRV-2', 30000, 12000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'd1d10000-0000-4000-8000-000000000031'),
  ('d1d10000-0000-4000-8000-000000000014', 'd1d10000-0000-4000-8000-000000000001',
   'Kit tubeless', 'PZ-ORD3', 'PRV-3', 25000, 11000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'd1d10000-0000-4000-8000-000000000031'),
  ('d1d10000-0000-4000-8000-000000000015', 'd1d10000-0000-4000-8000-000000000001',
   'Casco con MIPS', '7800000000004', null, 250000, 150000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'd1d10000-0000-4000-8000-000000000031'),
  ('d1d10000-0000-4000-8000-000000000016', 'd1d10000-0000-4000-8000-000000000001',
   'Llanta 29 sin lector', 'PZ-NOFEED', null, 120000, 60000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'd1d10000-0000-4000-8000-000000000032'),
  ('d1d10000-0000-4000-8000-000000000017', 'd1d10000-0000-4000-8000-000000000001',
   'Agotado sin plazo', 'PZ-OUT', null, 8000, 3000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, null);
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('d1d10000-0000-4000-8000-000000000012', 'd1d10000-0000-4000-8000-000000000001',
   'd1d10000-0000-4000-8000-000000000031', 3, 5),
  ('d1d10000-0000-4000-8000-000000000013', 'd1d10000-0000-4000-8000-000000000001',
   'd1d10000-0000-4000-8000-000000000031', 3, 5),
  ('d1d10000-0000-4000-8000-000000000014', 'd1d10000-0000-4000-8000-000000000001',
   'd1d10000-0000-4000-8000-000000000031', 3, 5),
  ('d1d10000-0000-4000-8000-000000000015', 'd1d10000-0000-4000-8000-000000000001',
   'd1d10000-0000-4000-8000-000000000031', 3, 5),
  ('d1d10000-0000-4000-8000-000000000016', 'd1d10000-0000-4000-8000-000000000001',
   'd1d10000-0000-4000-8000-000000000032', 2, 4);

insert into public.website_settings (tenant_id, key, value) values
  ('d1d10000-0000-4000-8000-000000000001', 'mercadopago_access_token', 'TEST-0000'),
  ('d1d10000-0000-4000-8000-000000000001', 'store_url', 'https://tienda.example.cl'),
  ('d1d10000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('d1d10000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('d1d10000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('d1d10000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Taller plazo'),
  ('d1d10000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0');

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.product_on_order_offer_internal_v1(uuid,uuid[])', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.product_on_order_offer_internal_v1(uuid,uuid[])', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.online_order_on_order_notify_internal(uuid,text,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.online_order_on_order_projection_internal(uuid)', 'EXECUTE'),
  'the rule and the internals are not callable from the API');
select ok(
  has_function_privilege('authenticated', 'public.online_order_on_order_detail_v1(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.online_order_on_order_check_arrivals_v1(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.online_order_on_order_cancel_v1(uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.online_order_on_order_detail_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.online_order_on_order_cancel_v1(uuid,uuid,jsonb)', 'EXECUTE'),
  'the team reads, checks and cancels from Pedidos web; a visitor cannot');

-- ---------------------------------------------------------------------------
-- La regla
-- ---------------------------------------------------------------------------

select is(
  (select string_agg(p.sku || ':' || o.max_quantity || ':' || o.lead_days_min || '-' || o.lead_days_max, ',' order by p.sku)
     from public.product_on_order_offer_internal_v1('d1d10000-0000-4000-8000-000000000001', null) o
     join public.products p on p.id = o.product_id),
  '7800000000004:2:3-5,PZ-NOFEED:3:2-4,PZ-ORD1:5:3-5,PZ-ORD2:2:3-5',
  'sold with a lead time: the supplier''s stock minus 5, capped per purchase by price; 4 with the supplier is not enough; without a reader, only the cap');

update public.supplier_catalog_feeds set last_ok_at = now() - interval '4 hours'
 where id = 'd1d10000-0000-4000-8000-0000000000f1';
select is(
  (select string_agg(p.sku, ',' order by p.sku)
     from public.product_on_order_offer_internal_v1('d1d10000-0000-4000-8000-000000000001', null) o
     join public.products p on p.id = o.product_id),
  'PZ-NOFEED',
  'a reading older than 3 hours stops selling the reader''s products with a lead time');
update public.supplier_catalog_feeds set last_ok_at = now() - interval '10 minutes'
 where id = 'd1d10000-0000-4000-8000-0000000000f1';

select set_config('request.jwt.claims', '{}', true);
set local role anon;
select is(
  public.get_public_sold_out_offers_v1('d1d10000-0000-4000-8000-000000000001', array[
    'd1d10000-0000-4000-8000-000000000012', 'd1d10000-0000-4000-8000-000000000014',
    'd1d10000-0000-4000-8000-000000000017']::uuid[]),
  '{"d1d10000-0000-4000-8000-000000000012":{"mode":"on_order","leadDaysMin":3,"leadDaysMax":5,"maxQuantity":5},
    "d1d10000-0000-4000-8000-000000000014":{"mode":"quote"}}'::jsonb,
  'the store reads the lead time and how many; what the supplier no longer has is quoted; the rest is not offered');
reset role;

select is(
  (select string_agg(p.sku, ',' order by p.sku)
     from unnest(public.catalog_on_order_product_ids_internal_v1('d1d10000-0000-4000-8000-000000000001')) listed(pid)
     join public.products p on p.id = listed.pid),
  '7800000000004,PZ-NOFEED,PZ-ORD1,PZ-ORD2',
  'the listings carry exactly what is sold with a lead time today');

-- ---------------------------------------------------------------------------
-- Diego compra con el carrito: cámara en stock y cadena con plazo, retiro,
-- Mercado Pago.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{}', true);
set local role anon;
select set_config('pz.a', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000001',
    'customer_email', 'diego@example.invalid',
    'customer_name', 'Diego Prueba',
    'customer_address', 'Retiro en tienda',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(
    jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000011', 'quantity', 1),
    jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000012', 'quantity', 2)
  ))::text, true);
reset role;
select set_config('pz.oa', current_setting('pz.a')::jsonb ->> 'order_id', true);

select is(
  (select string_agg(i.product_sku || ':' || i.fulfillment || ':' || i.quantity || ':'
                     || coalesce(i.lead_days_min || '-' || i.lead_days_max, '-') || ':'
                     || coalesce(s.name, '-'), ',' order by i.product_sku)
     from public.online_order_items i
     left join public.suppliers s on s.id = i.on_order_supplier_id
    where i.order_id = current_setting('pz.oa')::uuid),
  'PZ-ORD1:on_order:2:3-5:Distribuidor con lector,PZ-STOCK:stock:1:-:-',
  'each line says where it comes from: the shelf, or the supplier with its lead time');
select is(
  (select string_agg(p.sku || ':' || r.quantity || ':' || r.state, ',')
     from public.online_order_inventory_reservations r
     join public.products p on p.id = r.product_id
    where r.order_id = current_setting('pz.oa')::uuid),
  'PZ-STOCK:1:active',
  'only what is on the shelf is reserved');
select is(
  (select o.status || ':' || o.payment_status || ':' || o.total::integer
     from public.online_orders o where o.id = current_setting('pz.oa')::uuid),
  'pending:pending:45000',
  'the order waits for Mercado Pago at the published prices');

-- Los mismos pedales: hay 7 con el proveedor, se venden 2; pedir 3 no se puede.
select set_config('request.jwt.claims', '{}', true);
set local role anon;
select throws_ok(
  $$select public.create_public_online_order_with_access(
    jsonb_build_object(
      'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000002',
      'customer_email', 'renato@example.invalid', 'customer_name', 'Renato Prueba',
      'customer_address', 'Retiro en tienda', 'delivery_type', 'pickup', 'payment_method', 'mercadopago'),
    jsonb_build_array(jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000013', 'quantity', 3)))$$,
  'P0001', 'Insufficient stock for product Pedales de aluminio',
  'more than the rule lets through is refused as any stock shortage');
select throws_ok(
  $$select public.create_public_online_order_with_access(
    jsonb_build_object(
      'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000003',
      'customer_email', 'renato@example.invalid', 'customer_name', 'Renato Prueba',
      'customer_address', 'Retiro en tienda', 'delivery_type', 'pickup', 'payment_method', 'mercadopago'),
    jsonb_build_array(jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000014', 'quantity', 1)))$$,
  'P0001', 'Insufficient stock for product Kit tubeless',
  'what the supplier does not have enough of cannot be bought with a lead time');
select lives_ok(
  $$select public.create_public_online_order_with_access(
    jsonb_build_object(
      'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
      'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000004',
      'customer_email', 'renato@example.invalid', 'customer_name', 'Renato Prueba',
      'customer_address', 'Retiro en tienda', 'delivery_type', 'pickup', 'payment_method', 'mercadopago'),
    jsonb_build_array(jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000013', 'quantity', 2)))$$,
  'the two the rule allows are bought');
reset role;
select is(
  (select count(*)::integer
     from public.product_on_order_offer_internal_v1('d1d10000-0000-4000-8000-000000000001',
            array['d1d10000-0000-4000-8000-000000000013']::uuid[])),
  0,
  'what was just sold and has not arrived counts against the supplier''s stock: no more pedals');

-- Mercado Pago aprueba el pago de Diego.
select set_config('pz.ev', public.record_mercadopago_payment_observation(
  current_setting('pz.oa')::uuid, 'd1d10000-0000-4000-8000-000000000001', 'MP-PZ-DIEGO',
  'approved', 45000, 'CLP', now() - interval '1 hour', '{}'::jsonb) ->> 'event_id', true);
select set_config('pz.p1', public.process_mercadopago_payment_observation(current_setting('pz.ev')::bigint)::text, true);

select is(
  current_setting('pz.p1')::jsonb ->> 'processing_state' || ':' || (current_setting('pz.p1')::jsonb ->> 'error_code'),
  'action_required:awaiting_on_order_stock',
  'the validated payment waits for what comes from the supplier');
select is(
  (select o.payment_status || ':' || o.status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta')
     from public.online_orders o where o.id = current_setting('pz.oa')::uuid),
  'paid:confirmed:sin venta',
  'the order is paid and confirmed; the sale waits');
select ok(
  (select r.expires_at > clock_timestamp() + interval '80 days'
     from public.online_order_inventory_reservations r
    where r.order_id = current_setting('pz.oa')::uuid and r.state = 'active'),
  'what is on the shelf waits up to 90 days for the rest');
select is(
  (select pi.status || ':' || pi.supplier_name || ':' || jsonb_array_length(pi.items) || ':' || pi.subtotal::integer
          || ':' || (po.quote_id is null) || ':' || (pi.invoice_number like 'PED-%')
     from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('pz.oa')::uuid),
  'draft:Distribuidor con lector:1:18000:true:true',
  'one draft purchase for the supplier at the product''s cost, without a quote');
select ok(
  (select pi.notes = 'Para el pedido ' || o.order_number || '.'
     from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
     join public.online_orders o on o.id = po.online_order_id
    where po.online_order_id = current_setting('pz.oa')::uuid),
  'the supplier document names the order, never the customer');
select is(
  (select n.route || ':' || n.severity || ':' || (n.read_at is null)
     from public.erp_notifications n
    where n.tenant_id = 'd1d10000-0000-4000-8000-000000000001'
      and n.type = 'customer_quote_order_to_purchase'
      and n.entity_id = current_setting('pz.oa')::uuid),
  '/website/orders?order=' || current_setting('pz.oa') || ':warning:true',
  'the team is told to order from the supplier, and the notice opens the web order');

-- El equipo mira el pedido en Pedidos web.
select set_config('request.jwt.claims', '{"sub":"d1d10000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'd1d10000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('pz.d', public.online_order_on_order_detail_v1(
  'd1d10000-0000-4000-8000-000000000001', current_setting('pz.oa')::uuid)::text, true);
select is(
  (select (current_setting('pz.d')::jsonb ->> 'waiting') || ':'
          || jsonb_array_length(current_setting('pz.d')::jsonb -> 'items') || ':'
          || jsonb_array_length(current_setting('pz.d')::jsonb -> 'purchases') || ':'
          || coalesce(current_setting('pz.d')::jsonb ->> 'quote_id', 'sin cotización')),
  'true:2:1:sin cotización',
  'the order, its lines and its supplier purchase, without a quote');
select is(
  (select string_agg(i ->> 'product_sku' || ':' || (i ->> 'fulfillment') || ':' || coalesce(i ->> 'supplier_name', '-'), ','
                     order by i ->> 'product_sku')
     from jsonb_array_elements(current_setting('pz.d')::jsonb -> 'items') i),
  'PZ-ORD1:on_order:Distribuidor con lector,PZ-STOCK:stock:-',
  'each line with where it comes from');
select is(
  public.online_order_on_order_check_arrivals_v1(
    'd1d10000-0000-4000-8000-000000000001', current_setting('pz.oa')::uuid) ->> 'waiting',
  'true',
  '«Revisar si llegó» before it arrives: it still waits');
reset role;

-- Llega la cadena y el equipo aprieta «Revisar si llegó»: se aparta y se
-- emite la venta, también con el pago de Mercado Pago (la guarda de
-- sales_payments no deja estampar el pago con la sesión de una persona: el
-- pago se procesa como lo haría el barrido).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 2, stock_quantity = 2 where id = 'd1d10000-0000-4000-8000-000000000012';
select set_config('request.jwt.claim.role', '', true);
select set_config('request.jwt.claims', '{"sub":"d1d10000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'd1d10000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('pz.arr', public.online_order_on_order_check_arrivals_v1(
  'd1d10000-0000-4000-8000-000000000001', current_setting('pz.oa')::uuid)::text, true);
select ok(
  (current_setting('pz.arr')::jsonb ->> 'invoice_id') is not null
  and (current_setting('pz.arr')::jsonb ->> 'error') is null
  and current_setting('request.jwt.claim.sub') = 'd1d10000-0000-4000-8000-000000000091',
  '«Revisar si llegó» issues the sale with a Mercado Pago payment, and the session stays the team''s');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select is(
  (select si.status || ':' || si.total::integer || ':' || (si.date::date = current_date)
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('pz.oa')::uuid),
  'paid:45000:true',
  'everything arrived: the sale is issued that day, paid');
select is(
  (select string_agg(sku || ':' || stock_quantity, ',' order by sku) from public.products
    where tenant_id = 'd1d10000-0000-4000-8000-000000000001' and sku in ('PZ-STOCK', 'PZ-ORD1')),
  'PZ-ORD1:0,PZ-STOCK:4',
  'the sale takes exactly the reserved units');
select is(
  (select processing_state from public.sales_channel_payment_processing
    where payment_event_id = current_setting('pz.ev')::bigint),
  'processed', 'the Mercado Pago payment that waited is processed with the sale');
select ok(
  exists (select 1 from public.erp_notifications n
           where n.type = 'customer_quote_order_ready' and n.entity_id = current_setting('pz.oa')::uuid
             and n.route = '/website/orders?order=' || current_setting('pz.oa'))
  and (select n.read_at is not null from public.erp_notifications n
        where n.type = 'customer_quote_order_to_purchase' and n.entity_id = current_setting('pz.oa')::uuid),
  'the team is told to prepare it and the purchase notice closes');

-- ---------------------------------------------------------------------------
-- Tomás: el casco, Mercado Pago; llega y el barrido de cada 10 minutos, sin
-- sesión, emite la venta.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('pz.t', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000006',
    'customer_email', 'tomas@example.invalid',
    'customer_name', 'Tomás Prueba',
    'customer_address', 'Retiro en tienda',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(
    jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000015', 'quantity', 1)
  ))::text, true);
reset role;
select set_config('pz.ot', current_setting('pz.t')::jsonb ->> 'order_id', true);
select set_config('pz.evt', public.record_mercadopago_payment_observation(
  current_setting('pz.ot')::uuid, 'd1d10000-0000-4000-8000-000000000001', 'MP-PZ-TOMAS',
  'approved', 250000, 'CLP', now() - interval '30 minutes', '{}'::jsonb) ->> 'event_id', true);
select set_config('pz.pt', public.process_mercadopago_payment_observation(current_setting('pz.evt')::bigint)::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);
update public.products set inventory_qty = 1, stock_quantity = 1 where id = 'd1d10000-0000-4000-8000-000000000015';
select set_config('request.jwt.claim.role', '', true);
select ok(public.customer_quote_orders_check_arrivals_v1() >= 1, 'the sweep picks up a direct order whose product came in');
select is(
  (select si.status || ':' || si.total::integer
     from public.online_orders o join public.sales_invoices si on si.id = o.sales_invoice_id
    where o.id = current_setting('pz.ot')::uuid),
  'paid:250000',
  'the sweep issues its sale, paid');

-- ---------------------------------------------------------------------------
-- Renato: llanta de un proveedor sin lector, transferencia; el proveedor no
-- la tiene y el equipo anula y devuelve.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('pz.b', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', 'd1d10000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '7a1c2a3b-4d5e-4f60-8a71-000000000005',
    'customer_email', 'renato@example.invalid',
    'customer_name', 'Renato Prueba',
    'customer_address', 'Retiro en tienda',
    'delivery_type', 'pickup',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(
    jsonb_build_object('product_id', 'd1d10000-0000-4000-8000-000000000016', 'quantity', 1)
  ))::text, true);
reset role;
select set_config('pz.ob', current_setting('pz.b')::jsonb ->> 'order_id', true);
select is(
  (select o.status || ':' || o.payment_status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta')
     from public.online_orders o where o.id = current_setting('pz.ob')::uuid),
  'pending:pending:sin venta',
  'a transfer for something that comes from the supplier does not create the sale');

select set_config('request.jwt.claims', '{"sub":"d1d10000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'd1d10000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.confirm_online_order_payment(%L::uuid, 'TRF-RENATO-1', now())$$, current_setting('pz.ob')),
  'the team confirms the transfer as always');
reset role;
select is(
  (select o.payment_status || ':' || o.status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta')
     || ':' || o.payment_reference
     from public.online_orders o where o.id = current_setting('pz.ob')::uuid),
  'paid:confirmed:sin venta:TRF-RENATO-1',
  'the transfer stays on the order; the sale waits for the supplier');
select is(
  (select pi.status || ':' || pi.supplier_name || ':' || pi.total::integer
     from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('pz.ob')::uuid),
  'draft:Distribuidor sin lector:71400',
  'the draft purchase goes to the supplier without a reader too');

select set_config('request.jwt.claims', '{"sub":"d1d10000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'd1d10000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_ok(
  format($$select public.online_order_on_order_cancel_v1('d1d10000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"8b1c2a3b-4d5e-4f60-8a71-000000000001","reason":"x","refund_reference":"TRF-DEV-1"}')$$,
    current_setting('pz.ob')),
  '22023', 'quote_cancel_reason_required', 'cancelling asks why');
select set_config('pz.c1', public.online_order_on_order_cancel_v1(
  'd1d10000-0000-4000-8000-000000000001', current_setting('pz.ob')::uuid,
  '{"operation_key":"8b1c2a3b-4d5e-4f60-8a71-000000000002","reason":"El distribuidor no la tenía",
    "refund_reference":"TRF-DEV-1"}'::jsonb)::text, true);
select set_config('pz.c2', public.online_order_on_order_cancel_v1(
  'd1d10000-0000-4000-8000-000000000001', current_setting('pz.ob')::uuid,
  '{"operation_key":"8b1c2a3b-4d5e-4f60-8a71-000000000002","reason":"El distribuidor no la tenía",
    "refund_reference":"TRF-DEV-1"}'::jsonb)::text, true);
select throws_ok(
  format($$select public.online_order_on_order_cancel_v1('d1d10000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"8b1c2a3b-4d5e-4f60-8a71-000000000003","reason":"Ya tiene venta","refund_reference":"X-1"}')$$,
    current_setting('pz.oa')),
  '55000', 'quote_order_has_sale', 'an order with a sale is refunded in Correcciones');
reset role;
select is(
  (select o.status || ':' || o.payment_status || ':' || o.refund_amount::integer
     from public.online_orders o where o.id = current_setting('pz.ob')::uuid),
  'cancelled:refunded:120000',
  'the order is cancelled and the refund recorded');
select is(
  (select pi.status from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('pz.ob')::uuid),
  'cancelled',
  'the draft nobody sent to the supplier is cancelled');
select ok(
  (current_setting('pz.c1')::jsonb ->> 'replay') = 'false'
  and (current_setting('pz.c2')::jsonb ->> 'replay') = 'true',
  'the same cancellation again returns what was done');
select is(
  (select string_agg(message_kind, ',' order by created_at) from public.transactional_email_outbox
    where order_id = current_setting('pz.ob')::uuid and message_kind in ('cancelled', 'refund_completed')),
  'cancelled,refund_completed',
  'Renato is told the order was cancelled and refunded');

-- Lo cancelado deja de contar contra el stock del proveedor.
select is(
  (select o.max_quantity
     from public.product_on_order_offer_internal_v1('d1d10000-0000-4000-8000-000000000001',
            array['d1d10000-0000-4000-8000-000000000016']::uuid[]) o),
  3,
  'a cancelled order no longer holds the supplier''s units');

-- Una persona de otro taller no lee el pedido.
select set_config('request.jwt.claims', '{"sub":"d1d10000-0000-4000-8000-000000000099","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'd1d10000-0000-4000-8000-000000000099', true);
set local role authenticated;
select throws_ok(
  format($$select public.online_order_on_order_detail_v1('d1d10000-0000-4000-8000-000000000001', %L::uuid)$$,
    current_setting('pz.oa')),
  '42501', null, 'another tenant''s user cannot read the order');
reset role;

select * from finish();
rollback;
