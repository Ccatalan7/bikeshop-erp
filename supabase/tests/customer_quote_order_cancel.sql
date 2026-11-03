begin;

select plan(16);

-- Anular y devolver un pedido de cotización pagado que todavía espera
-- (20261103030000). El proveedor no tiene lo que venía a pedido: el equipo
-- devuelve la plata y anota la referencia; el pedido se anula, lo apartado se
-- libera, el borrador de compra que nadie mandó se anula y el cliente recibe
-- los correos de pedido cancelado y de reembolso.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0d70000-0000-4000-8000-000000000001', 'Taller anulaciones', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0d70000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-anula@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d70000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0d70000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'caja-anula@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d70000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0d70000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'dani@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c0d70000-0000-4000-8000-000000000091', 'c0d70000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0d70000-0000-4000-8000-000000000091', 'c0d70000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('c0d70000-0000-4000-8000-000000000092', 'c0d70000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0d70000-0000-4000-8000-0000000000c1', 'c0d70000-0000-4000-8000-000000000001',
   'c0d70000-0000-4000-8000-000000000093', 'Dani Fuentes', 'dani@example.invalid', null, true);

insert into public.suppliers (id, tenant_id, name, rut, sales_rep_name, sales_rep_phone) values
  ('c0d70000-0000-4000-8000-000000000031', 'c0d70000-0000-4000-8000-000000000001',
   'Proveedor sin stock', '76.333.444-5', 'Vendedor Dos', '+56900000002');

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('c0d70000-0000-4000-8000-000000000011', 'c0d70000-0000-4000-8000-000000000001',
   'Cámara en stock 29', 'AN-STOCK', 6000, 2500, 19, 'product', false, true,
   2, 2, 0, 100, true, true, true, null),
  ('c0d70000-0000-4000-8000-000000000012', 'c0d70000-0000-4000-8000-000000000001',
   'Neumático a pedido 29 x 2.60', 'AN-ORDER', 52000, 26000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'c0d70000-0000-4000-8000-000000000031');
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('c0d70000-0000-4000-8000-000000000012', 'c0d70000-0000-4000-8000-000000000001',
   'c0d70000-0000-4000-8000-000000000031', 3, 5);

insert into public.website_settings (tenant_id, key, value) values
  ('c0d70000-0000-4000-8000-000000000001', 'store_url', 'https://tienda.example.cl'),
  ('c0d70000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('c0d70000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('c0d70000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('c0d70000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Taller anulaciones'),
  ('c0d70000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0');

select ok(
  not has_function_privilege('anon', 'public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)', 'EXECUTE'),
  'only a signed-in team member can cancel and refund');

-- Dani pide la cotización, el equipo confirma y la envía, Dani acepta con
-- transferencia y el equipo confirma el abono.
select set_config('request.jwt.claims', '{"sub":"c0d70000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d70000-0000-4000-8000-000000000093', true);
set local role authenticated;
select set_config('an.q', public.request_public_customer_quote_v1(
  'c0d70000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"6c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,"notify_whatsapp":false,
    "items":[{"product_id":"c0d70000-0000-4000-8000-000000000011","quantity":1},
             {"product_id":"c0d70000-0000-4000-8000-000000000012","quantity":1}]}')::text, true);
reset role;
select set_config('an.qid', current_setting('an.q')::jsonb ->> 'quote_id', true);

select set_config('request.jwt.claims', '{"sub":"c0d70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('an.tmp', public.customer_quote_confirm_line_v1(
  'c0d70000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('an.qid')::uuid and o.status = 'draft' and l.product_sku = 'AN-ORDER'),
  '{"availability":"on_order","quantity_offered":1,"unit_price":52000,"lead_days_min":3,"lead_days_max":5,
    "unit_cost_net":26000}')::text, true);
select set_config('an.tmp', public.customer_quote_send_offer_v1(
  'c0d70000-0000-4000-8000-000000000001', current_setting('an.qid')::uuid,
  '6d1c2a3b-4d5e-4f60-8a71-000000000001')::text, true);
reset role;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('an.o', public.accept_public_customer_quote_v1(
  current_setting('an.q')::jsonb ->> 'access_token',
  '{"operation_key":"6e1c2a3b-4d5e-4f60-8a71-000000000001","delivery_type":"pickup","payment_method":"transfer"}')::text,
  true);
reset role;
select set_config('an.oid', current_setting('an.o')::jsonb ->> 'order_id', true);

select set_config('request.jwt.claims', '{"sub":"c0d70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('an.tmp', coalesce(public.confirm_online_order_payment(
  current_setting('an.oid')::uuid, 'TRF-DANI-1', now() - interval '1 hour')::text, ''), true);
reset role;

select is(
  (select o.payment_status || ':' || o.status || ':' || coalesce(o.sales_invoice_id::text, 'sin venta') || ':'
          || (select pi.status from public.customer_quote_purchase_orders po
                join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
               where po.online_order_id = o.id) || ':'
          || (select string_agg(r.state, ',') from public.online_order_inventory_reservations r
               where r.order_id = o.id)
     from public.online_orders o where o.id = current_setting('an.oid')::uuid),
  'paid:confirmed:sin venta:draft:active',
  'paid and waiting: the tube is reserved and the supplier draft is ready');

-- La caja no mueve plata.
select set_config('request.jwt.claims', '{"sub":"c0d70000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d70000-0000-4000-8000-000000000092', true);
set local role authenticated;
select throws_ok(
  format($$select public.customer_quote_order_cancel_v1('c0d70000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"6f1c2a3b-4d5e-4f60-8a71-000000000009","reason":"El proveedor no lo tiene","refund_reference":"DEV-1"}')$$,
    current_setting('an.qid')),
  '42501', 'quote_refund_not_allowed', 'a cashier cannot refund');
reset role;

select set_config('request.jwt.claims', '{"sub":"c0d70000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d70000-0000-4000-8000-000000000091', true);
set local role authenticated;
select throws_ok(
  format($$select public.customer_quote_order_cancel_v1('c0d70000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"6f1c2a3b-4d5e-4f60-8a71-000000000008","reason":"El proveedor no lo tiene"}')$$,
    current_setting('an.qid')),
  '22023', 'quote_refund_reference_required', 'the refund is recorded with its reference');
select set_config('an.c', public.customer_quote_order_cancel_v1(
  'c0d70000-0000-4000-8000-000000000001', current_setting('an.qid')::uuid,
  '{"operation_key":"6f1c2a3b-4d5e-4f60-8a71-000000000001","reason":"El proveedor no tiene la medida",
    "refund_reference":"DEV-DANI-1"}')::text, true);
select set_config('an.c2', public.customer_quote_order_cancel_v1(
  'c0d70000-0000-4000-8000-000000000001', current_setting('an.qid')::uuid,
  '{"operation_key":"6f1c2a3b-4d5e-4f60-8a71-000000000001","reason":"El proveedor no tiene la medida",
    "refund_reference":"DEV-DANI-1"}')::text, true);
select throws_ok(
  format($$select public.customer_quote_order_cancel_v1('c0d70000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"6f1c2a3b-4d5e-4f60-8a71-000000000002","reason":"Otra vez","refund_reference":"DEV-2"}')$$,
    current_setting('an.qid')),
  '55000', 'quote_order_already_cancelled', 'a cancelled order is not refunded twice');
reset role;

select is(
  (select o.status || ':' || o.payment_status || ':' || o.refund_amount::integer || ':'
          || (o.refunded_at is not null) || ':' || o.cancelled_reason
     from public.online_orders o where o.id = current_setting('an.oid')::uuid),
  'cancelled:refunded:58000:true:El proveedor no tiene la medida',
  'the order is cancelled and its whole total is recorded as returned');
select is(
  (select string_agg(distinct r.state, ',') from public.online_order_inventory_reservations r
    where r.order_id = current_setting('an.oid')::uuid),
  'released', 'the reserved tube goes back to the shelf');
select is(
  (select inventory_qty::integer from public.products where id = 'c0d70000-0000-4000-8000-000000000011'),
  2, 'no stock ever left: there was no sale');
select is(
  (select pi.status from public.customer_quote_purchase_orders po
     join public.purchase_invoices pi on pi.id = po.purchase_invoice_id
    where po.online_order_id = current_setting('an.oid')::uuid),
  'cancelled', 'the supplier draft nobody sent is cancelled');
select is(
  (select count(*)::integer from public.journal_entries
    where tenant_id = 'c0d70000-0000-4000-8000-000000000001'),
  0, 'nothing reaches the books: the payment was never a sale');
select is(
  (select string_agg(event_type, ',' order by id) from public.customer_quote_events
    where quote_id = current_setting('an.qid')::uuid and event_type like 'order_%'),
  'order_waiting,order_paid,order_cancelled,order_refunded',
  'the history shows the wait, the payment, the cancellation and the refund once');
select is(
  (select e.detail ->> 'reference' || ':' || (e.detail ->> 'amount')::numeric::integer || ':'
          || (e.detail ->> 'purchases_cancelled')
     from public.customer_quote_events e
    where e.quote_id = current_setting('an.qid')::uuid and e.event_type = 'order_refunded'),
  'DEV-DANI-1:58000:1', 'the refund keeps its reference, amount and what it cancelled');
select is(
  (select string_agg(message_kind, ',' order by created_at) from public.transactional_email_outbox
    where order_id = current_setting('an.oid')::uuid and message_kind in ('cancelled', 'refund_completed')),
  'cancelled,refund_completed', 'Dani is told the order was cancelled and the money returned');
select is(
  public.customer_quote_order_waiting_internal(current_setting('an.oid')::uuid),
  false, 'a cancelled order waits for nothing');
select is(
  (current_setting('an.c2')::jsonb ->> 'replay') || ':' || (current_setting('an.c')::jsonb -> 'order' ->> 'status'),
  'true:cancelled', 'a retry with the same key returns what was done');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select ok(
  (public.get_public_customer_quote_v1(current_setting('an.q')::jsonb ->> 'access_token') -> 'history')
    @> '[{"type":"order_refunded"}]'::jsonb,
  'Dani sees in the quote that the payment was returned (20261103040000)');
reset role;

select * from finish();
rollback;
