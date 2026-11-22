begin;

select plan(32);

-- Un solo pedido abierto por proveedor, que sale de verdad (20261122010000).
-- Cada venta pagada suma sus productos al borrador del proveedor que nadie ha
-- enviado; la base no deja sacarle lo que pagó un cliente ni marcarlo
-- enviado sin comparar lo que salió; lo vendido cuenta contra el stock del
-- proveedor hasta 2 días después de enviado; una venta anulada sale del
-- pedido abierto.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('e2e20000-0000-4000-8000-000000000001', 'Taller pedido abierto', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e2e20000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'equipo-abierto@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"e2e20000-0000-4000-8000-000000000001"}'::jsonb, now(), now());
delete from public.user_profiles where user_id = 'e2e20000-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('e2e20000-0000-4000-8000-000000000091', 'e2e20000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

insert into public.suppliers (id, tenant_id, name, rut, sales_rep_name, sales_rep_phone) values
  ('e2e20000-0000-4000-8000-000000000031', 'e2e20000-0000-4000-8000-000000000001',
   'Distribuidor abierto', '76.555.666-7', 'Vendedor Abierto', '+56 9 1234 5678');

insert into public.supplier_catalog_feeds (
  id, tenant_id, supplier_id, format, endpoint_template, last_ok_at, last_status
) values (
  'e2e20000-0000-4000-8000-0000000000f1', 'e2e20000-0000-4000-8000-000000000001',
  'e2e20000-0000-4000-8000-000000000031', 'mkr_csv_v1',
  'https://proveedor.example.cl/api/endpoint?token={token}',
  now() - interval '10 minutes', 'ok'
);
insert into public.supplier_catalog_feed_items (
  tenant_id, feed_id, supplier_id, supplier_sku, barcode, name, stock
) values
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'AB-1', null, 'Cadena', 40),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'AB-2', null, 'Pedales', 40),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'AB-3', null, 'Kit', 9);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, supplier_code, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('e2e20000-0000-4000-8000-000000000011', 'e2e20000-0000-4000-8000-000000000001',
   'Cadena 12 v', 'OA-CAD', 'AB-1', 20000, 9000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000012', 'e2e20000-0000-4000-8000-000000000001',
   'Pedales de aluminio', 'OA-PED', 'AB-2', 30000, 12000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000013', 'e2e20000-0000-4000-8000-000000000001',
   'Kit tubeless', 'OA-KIT', 'AB-3', 25000, 11000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000014', 'e2e20000-0000-4000-8000-000000000001',
   'Cámara de repuesto', 'OA-CAM', null, 5000, 2000, 19, 'product', false, true,
   5, 5, 0, 100, true, true, true, 'e2e20000-0000-4000-8000-000000000031');
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('e2e20000-0000-4000-8000-000000000011', 'e2e20000-0000-4000-8000-000000000001',
   'e2e20000-0000-4000-8000-000000000031', 3, 5),
  ('e2e20000-0000-4000-8000-000000000012', 'e2e20000-0000-4000-8000-000000000001',
   'e2e20000-0000-4000-8000-000000000031', 3, 5),
  ('e2e20000-0000-4000-8000-000000000013', 'e2e20000-0000-4000-8000-000000000001',
   'e2e20000-0000-4000-8000-000000000031', 3, 5);

insert into public.website_settings (tenant_id, key, value) values
  ('e2e20000-0000-4000-8000-000000000001', 'store_url', 'https://tienda.example.cl'),
  ('e2e20000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('e2e20000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('e2e20000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('e2e20000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Taller abierto'),
  ('e2e20000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0');

-- Una compra por transferencia que el equipo confirma: devuelve el pedido.
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
      'tenant_id', 'e2e20000-0000-4000-8000-000000000001',
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
    '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
  set local role authenticated;
  perform public.confirm_online_order_payment(v_order, 'TRF-' || p_name, now());
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return v_order;
end;
$function$;

-- Lo que vende hoy con plazo para un producto.
create function pg_temp.offer(p_product uuid)
returns integer
language sql
as $function$
  select coalesce((
    select o.max_quantity
      from public.product_on_order_offer_internal_v1(
        'e2e20000-0000-4000-8000-000000000001', array[p_product]) o
  ), 0);
$function$;

-- Las líneas de un pedido al proveedor, «SKU:cantidad» en su orden.
create function pg_temp.lines(p_invoice uuid)
returns text
language sql
as $function$
  select string_agg((e.value ->> 'product_sku') || ':' || (e.value ->> 'quantity')::numeric::integer, ','
                    order by e.ordinality)
    from public.purchase_invoices pi
    cross join lateral jsonb_array_elements(pi.items) with ordinality e
   where pi.id = p_invoice;
$function$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

select ok(
  has_function_privilege('authenticated', 'public.purchase_order_mark_sent_v1(uuid,uuid,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.purchase_order_supplier_chat_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.purchase_order_mark_sent_v1(uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.purchase_order_supplier_chat_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.supplier_open_order_release_order_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.supplier_open_order_note_internal(uuid)', 'EXECUTE'),
  'the team sends and reads the supplier chat; the internals are not callable');

-- ---------------------------------------------------------------------------
-- Diego paga cadena y kit; una hora después Renato paga cadena y pedales.
-- ---------------------------------------------------------------------------

select set_config('oa.a', pg_temp.buy('7b2c2a3b-4d5e-4f60-8a71-000000000001', 'Diego',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000011', 'quantity', 2),
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000013', 'quantity', 2)))::text, true);
select set_config('oa.ped1', (select po.purchase_invoice_id::text
  from public.customer_quote_purchase_orders po where po.online_order_id = current_setting('oa.a')::uuid), true);

select is(
  pg_temp.lines(current_setting('oa.ped1')::uuid) || ' · '
    || (select pi.status || ':' || pi.subtotal::integer from public.purchase_invoices pi
         where pi.id = current_setting('oa.ped1')::uuid),
  'OA-CAD:2,OA-KIT:2 · draft:40000',
  'the first paid sale opens the supplier''s order');
select is(pg_temp.offer('e2e20000-0000-4000-8000-000000000013'), 2,
  'what was sold and not sent counts against the supplier''s 9 kits: 9 - 5 - 2');

select set_config('oa.b', pg_temp.buy('7b2c2a3b-4d5e-4f60-8a71-000000000002', 'Renato',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000011', 'quantity', 1),
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000012', 'quantity', 1)))::text, true);

select is(
  (select count(distinct po.purchase_invoice_id)::integer || ':' || count(*)::integer
     from public.customer_quote_purchase_orders po
    where po.online_order_id in (current_setting('oa.a')::uuid, current_setting('oa.b')::uuid)),
  '1:2',
  'the second sale joins the same open order instead of opening another');
select is(
  pg_temp.lines(current_setting('oa.ped1')::uuid),
  'OA-CAD:3,OA-KIT:2,OA-PED:1',
  'one line per product: the chain adds up, the pedals are appended');
select is(
  (select pi.subtotal::integer || ':' || pi.iva_amount::integer || ':' || pi.total::integer
     from public.purchase_invoices pi where pi.id = current_setting('oa.ped1')::uuid),
  '61000:11590:72590',
  'the totals follow: each line at its cost');
select is(
  (select pi.notes from public.purchase_invoices pi where pi.id = current_setting('oa.ped1')::uuid),
  (select 'Para los pedidos ' || a.order_number || ' y ' || b.order_number || '.'
     from public.online_orders a, public.online_orders b
    where a.id = current_setting('oa.a')::uuid and b.id = current_setting('oa.b')::uuid),
  'the note names both orders, never the customers');

-- Una venta de hace días sigue contando mientras el pedido no sale.
update public.online_orders set created_at = now() - interval '3 days'
 where id = current_setting('oa.a')::uuid;
select is(pg_temp.offer('e2e20000-0000-4000-8000-000000000013'), 2,
  'an older sale still counts while its supplier order has not gone out');

-- El equipo mira el pedido de Renato: el pedido al proveedor junta dos ventas.
select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  (select (p ->> 'orders') || ':' || (p ->> 'status') || ':' || coalesce(p ->> 'sent_at', 'sin enviar')
     from jsonb_array_elements(public.online_order_on_order_detail_v1(
       'e2e20000-0000-4000-8000-000000000001', current_setting('oa.b')::uuid) -> 'purchases') p),
  '2:draft:sin enviar',
  'the web order shows its supplier order and how many sales it carries');

-- ---------------------------------------------------------------------------
-- La guarda: lo que pagó un cliente no sale de un pedido abierto.
-- ---------------------------------------------------------------------------

select throws_like(
  format($$update public.purchase_invoices
              set items = (select jsonb_agg(e.value) from jsonb_array_elements(items) e
                            where e.value ->> 'product_sku' <> 'OA-PED')
            where id = %L$$, current_setting('oa.ped1')),
  'No se puede sacar Pedales de aluminio de este pedido: lo pagó %',
  'a save from an order opened before a sale cannot drop that sale''s line');
select throws_like(
  format($$update public.purchase_invoices
              set items = (select jsonb_agg(
                                    case when e.value ->> 'product_sku' = 'OA-CAD'
                                         then jsonb_set(e.value, '{quantity}', '2'::jsonb)
                                         else e.value end
                                    order by e.ordinality)
                             from jsonb_array_elements(items) with ordinality e)
            where id = %L$$, current_setting('oa.ped1')),
  'No se puede sacar Cadena 12 v de este pedido: lo pagó %',
  'nor take units from it');
select lives_ok(
  format($$update public.purchase_invoices
              set items = items || '[{"product_id":"e2e20000-0000-4000-8000-000000000014",
                                      "product_name":"Cámara de repuesto","product_sku":"OA-CAM",
                                      "quantity":2,"unit_cost":2000,"iva_rate":0.19}]'::jsonb
            where id = %L$$, current_setting('oa.ped1')),
  'the team can add a restock line to the open order');
select throws_ok(
  format($$update public.purchase_invoices set status = 'sent' where id = %L$$, current_setting('oa.ped1')),
  '55000', 'Actualiza el ERP: este pedido se envía con su PDF desde «Enviar al proveedor».',
  'an old app cannot mark it sent after sending only a greeting');

-- ---------------------------------------------------------------------------
-- Enviar: lo que salió tiene que ser lo que dice el pedido.
-- ---------------------------------------------------------------------------

select throws_ok(
  format($$select public.purchase_order_mark_sent_v1('e2e20000-0000-4000-8000-000000000001', %L,
    '[{"product_id":"e2e20000-0000-4000-8000-000000000011","quantity":3},
      {"product_id":"e2e20000-0000-4000-8000-000000000013","quantity":2},
      {"product_id":"e2e20000-0000-4000-8000-000000000012","quantity":1}]'::jsonb)$$,
    current_setting('oa.ped1')),
  '55000', 'El pedido cambió mientras se enviaba (Cámara de repuesto): vuelve a abrirlo y mándale lo que falta.',
  'what went out without the newest line does not mark the order sent');
select set_config('oa.sent', public.purchase_order_mark_sent_v1('e2e20000-0000-4000-8000-000000000001',
  current_setting('oa.ped1')::uuid,
  '[{"product_id":"e2e20000-0000-4000-8000-000000000011","quantity":3},
    {"product_id":"e2e20000-0000-4000-8000-000000000013","quantity":2},
    {"product_id":"e2e20000-0000-4000-8000-000000000012","quantity":1},
    {"product_id":"e2e20000-0000-4000-8000-000000000014","quantity":2}]'::jsonb)::text, true);
select is(
  (current_setting('oa.sent')::jsonb ->> 'status') || ':' || (current_setting('oa.sent')::jsonb ->> 'replay')
    || ':' || ((current_setting('oa.sent')::jsonb ->> 'sent_date') is not null),
  'sent:false:true',
  'what went out is what the order says: it is sent, with its date');
select is(
  (public.purchase_order_mark_sent_v1('e2e20000-0000-4000-8000-000000000001',
     current_setting('oa.ped1')::uuid, '[]'::jsonb) ->> 'replay'),
  'true',
  'marking it again after a lost answer returns what was done');
reset role;
select is(
  (select count(*)::integer from public.erp_notifications n
    where n.type = 'customer_quote_order_to_purchase'
      and n.entity_id in (current_setting('oa.a')::uuid, current_setting('oa.b')::uuid)
      and n.read_at is null),
  0,
  'the «order from the supplier» notices of both sales close');

-- ---------------------------------------------------------------------------
-- Lo que se paga después abre el pedido siguiente.
-- ---------------------------------------------------------------------------

select set_config('oa.c', pg_temp.buy('7b2c2a3b-4d5e-4f60-8a71-000000000003', 'Tomas',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000013', 'quantity', 1)))::text, true);
select set_config('oa.ped2', (select po.purchase_invoice_id::text
  from public.customer_quote_purchase_orders po where po.online_order_id = current_setting('oa.c')::uuid), true);
select ok(
  current_setting('oa.ped2') <> current_setting('oa.ped1')
  and (select pi.status = 'draft' from public.purchase_invoices pi where pi.id = current_setting('oa.ped2')::uuid),
  'a sale paid after the order went out opens the next one');
select is(pg_temp.offer('e2e20000-0000-4000-8000-000000000013'), 1,
  'sent today still counts (2) and the new open order too (1): 9 - 5 - 3');
update public.purchase_invoices set sent_date = now() - interval '3 days'
 where id = current_setting('oa.ped1')::uuid;
select is(pg_temp.offer('e2e20000-0000-4000-8000-000000000013'), 3,
  'two days after it went out, the supplier''s reading has it: only the open order counts');

select set_config('oa.d', pg_temp.buy('7b2c2a3b-4d5e-4f60-8a71-000000000004', 'Matias',
  jsonb_build_array(
    jsonb_build_object('product_id', 'e2e20000-0000-4000-8000-000000000012', 'quantity', 1)))::text, true);
select is(
  pg_temp.lines(current_setting('oa.ped2')::uuid),
  'OA-KIT:1,OA-PED:1',
  'and the next sale joins it');

-- ---------------------------------------------------------------------------
-- Una venta anulada sale del pedido abierto.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.online_order_on_order_cancel_v1('e2e20000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"8c1c2a3b-4d5e-4f60-8a71-000000000001","reason":"El distribuidor no lo tenía",
      "refund_reference":"TRF-DEV-T"}'::jsonb)$$, current_setting('oa.c')),
  'Tomás''s sale is cancelled and refunded');
reset role;
select is(
  pg_temp.lines(current_setting('oa.ped2')::uuid) || ' · '
    || (select pi.status || ':' || pi.subtotal::integer from public.purchase_invoices pi
         where pi.id = current_setting('oa.ped2')::uuid),
  'OA-PED:1 · draft:12000',
  'its kit leaves the open order; Matías''s pedals stay');
select is(
  (select pi.notes from public.purchase_invoices pi where pi.id = current_setting('oa.ped2')::uuid),
  (select 'Para el pedido ' || d.order_number || '.' from public.online_orders d
    where d.id = current_setting('oa.d')::uuid),
  'the note names only the sale it still carries');
select is(
  (select count(*)::integer from public.customer_quote_purchase_orders po
    where po.online_order_id = current_setting('oa.c')::uuid),
  0,
  'the cancelled sale no longer points to the open order');
select is(pg_temp.offer('e2e20000-0000-4000-8000-000000000013'), 4,
  'a cancelled sale no longer holds the supplier''s kits');

select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.online_order_on_order_cancel_v1('e2e20000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"8c1c2a3b-4d5e-4f60-8a71-000000000002","reason":"Ya no los quiere",
      "refund_reference":"TRF-DEV-M"}'::jsonb)$$, current_setting('oa.d')),
  'Matías''s sale is cancelled too');
reset role;
select is(
  (select pi.status from public.purchase_invoices pi where pi.id = current_setting('oa.ped2')::uuid),
  'cancelled',
  'the last sale of an order nobody sent cancels it, as before');

-- Anular una venta de un pedido ya enviado no lo toca: el equipo avisa.
select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok(
  format($$select public.online_order_on_order_cancel_v1('e2e20000-0000-4000-8000-000000000001', %L::uuid,
    '{"operation_key":"8c1c2a3b-4d5e-4f60-8a71-000000000003","reason":"Se arrepintió",
      "refund_reference":"TRF-DEV-R"}'::jsonb)$$, current_setting('oa.b')),
  'Renato''s sale is cancelled after its order went out');
reset role;
select is(
  pg_temp.lines(current_setting('oa.ped1')::uuid) || ' · '
    || (select pi.status from public.purchase_invoices pi where pi.id = current_setting('oa.ped1')::uuid),
  'OA-CAD:3,OA-KIT:2,OA-PED:1,OA-CAM:2 · sent',
  'what was already sent stays as sent');

-- ---------------------------------------------------------------------------
-- El chat del proveedor.
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  public.purchase_order_supplier_chat_v1('e2e20000-0000-4000-8000-000000000001',
    'e2e20000-0000-4000-8000-000000000031'),
  '{"conversation_id": null, "last_inbound_at": null, "window_open": false}'::jsonb,
  'a supplier without a WhatsApp chat says so');
reset role;

select set_config('request.jwt.claims', '{"sub":"e2e20000-0000-4000-8000-000000000099","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'e2e20000-0000-4000-8000-000000000099', true);
set local role authenticated;
select throws_ok(
  format($$select public.purchase_order_mark_sent_v1('e2e20000-0000-4000-8000-000000000001', %L, '[]'::jsonb)$$,
    current_setting('oa.ped1')),
  '42501', null, 'another tenant''s user cannot mark it');
reset role;

select * from finish();
rollback;
