-- La boleta del envío registra el despacho (20261013210000), el correo lleva
-- la marca del tema del sitio (20261013220000) y su vista previa es el mismo
-- correo (20261013230000). Datos inventados;
-- todo se deshace al final.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(25);

create temp table shipment_ids (name text primary key, id uuid not null) on commit drop;
create temp table shipment_values (name text primary key, value text not null) on commit drop;

insert into public.tenants (id, shop_name) values
  ('96300000-0000-4000-8000-000000000001', 'Despachos Test'),
  ('96300000-0000-4000-8000-000000000002', 'Despachos Otro');

insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross, shipping_gross,
  tax_rate, estimated_min_business_days, estimated_max_business_days
) values
  ('96300000-0000-4000-8000-000000000001', 'CL', 0, null, 0, 0, 0, 0);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('96300000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
   'despachos@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96300000-0000-4000-8000-000000000001'), now(), now()),
  ('96300000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
   'despachos-otro@example.invalid', '', now(), '{}'::jsonb,
   jsonb_build_object('tenant_id', '96300000-0000-4000-8000-000000000002'), now(), now());

delete from public.user_profiles where user_id in (
  '96300000-0000-4000-8000-000000000099', '96300000-0000-4000-8000-000000000098'
);
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('96300000-0000-4000-8000-000000000099', '96300000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('96300000-0000-4000-8000-000000000098', '96300000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96300000-0000-4000-8000-000000000099', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96300000-0000-4000-8000-000000000099', true);

-- El tema del editor: color ARGB como lo guarda la app y una fuente inválida.
insert into public.website_settings (tenant_id, key, value) values
  ('96300000-0000-4000-8000-000000000001', 'theme_primary_color', '4279385960'),
  ('96300000-0000-4000-8000-000000000001', 'theme_heading_font', 'Oswald'),
  ('96300000-0000-4000-8000-000000000001', 'theme_body_font', 'Barlow;}body{x');

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '96300000-0000-4000-8000-000000000010', '96300000-0000-4000-8000-000000000001',
  'Repuesto de prueba', 'DESPACHO-001', 1190, 990, 400, 19,
  'product', false, 'inventory', true, 10, 10, 0, 100, true, true, true
);

insert into shipment_ids
select 'order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96300000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'despacho-test-001',
    'customer_email', 'cliente-despacho@example.invalid',
    'customer_name', 'Cliente Despacho',
    'customer_address', 'Calle Inventada 123',
    'delivery_type', 'shipping',
    'shipping_address_line1', 'Calle Inventada 123',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '96300000-0000-4000-8000-000000000010', 'quantity', 1
  ))
);
update public.online_orders
   set shipping_city = 'Comuna Inventada'
 where id = (select id from shipment_ids where name = 'order');

select public.confirm_online_order_payment(
  (select id from shipment_ids where name = 'order'),
  'BANCO-DESPACHO-001',
  clock_timestamp()
);

select is(
  (select status || '|' || payment_status from public.online_orders
    where id = (select id from shipment_ids where name = 'order')),
  'confirmed|paid',
  'the fixture order is confirmed and paid, not yet prepared'
);

-- La foto subida a la carpeta del pedido.
insert into storage.objects (bucket_id, name)
values (
  'vinabike-files',
  '96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
    || (select id from shipment_ids where name = 'order')::text || '/boleta.jpg'
);

select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-sin-foto', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order')),
    jsonb_build_object(
      'carrier', 'Correos de Chile', 'tracking_number', '770000000001',
      'receipt_path', '96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
        || (select id from shipment_ids where name = 'order')::text || '/no-existe.jpg'
    )::text
  ),
  '22023',
  'The receipt photo was not uploaded',
  'a receipt that was never uploaded is refused'
);

select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-otra-carpeta', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order')),
    jsonb_build_object(
      'carrier', 'Correos de Chile', 'tracking_number', '770000000001',
      'receipt_path', '96300000-0000-4000-8000-000000000001/evidence/payroll_advance/boleta.jpg'
    )::text
  ),
  '22023',
  'The receipt must live in this order''s evidence folder',
  'a photo outside the order''s folder is refused'
);

select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-sin-codigo', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order')),
    jsonb_build_object('carrier', 'Correos de Chile')::text
  ),
  '22023',
  'Indica el número de seguimiento del envío.',
  'a shipment needs its tracking number'
);

insert into shipment_values
select 'draft', jsonb_build_object(
  'carrier', 'Correos de Chile',
  'carrier_code', 'correos_chile',
  'service', 'Paquete Express AM',
  'tracking_number', ' 7700 0000 0001 ',
  'tracking_url', 'https://www.correos.cl/web/guest/seguimiento-en-linea',
  'admitted_at', '2026-10-13T17:43:00-03:00',
  'branch', 'Sucursal Inventada',
  'cost', 6240,
  'receipt_path', '96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
    || (select id from shipment_ids where name = 'order')::text || '/boleta.jpg',
  'extracted', jsonb_build_object('recipient_name', 'CLIENTE DESPACHO'),
  'checks', jsonb_build_object('recipient', 'match')
)::text;

-- La vista previa, antes de registrar: el correo tal como saldría.
insert into shipment_values
select 'preview', public.preview_online_order_shipment_email(
  (select id from shipment_ids where name = 'order'),
  (select value::jsonb from shipment_values where name = 'draft')
)::text;

select is(
  (select (value::jsonb)->>'subject' || '|' || ((value::jsonb)->>'recipient') || '|' ||
          ((value::jsonb)->>'deliveryMode')
     from shipment_values where name = 'preview'),
  (select 'Tu pedido ' || order_number || ' ya fue enviado|cliente-despacho@example.invalid|dry_run'
     from public.online_orders where id = (select id from shipment_ids where name = 'order')),
  'the preview says to whom, with what subject and whether it would really be sent'
);
select is(
  (select count(*)::int from public.online_order_shipments
    where order_id = (select id from shipment_ids where name = 'order'))
  + (select count(*)::int from public.transactional_email_outbox
      where order_id = (select id from shipment_ids where name = 'order')
        and message_kind = 'shipped')
  + (select count(*)::int from public.online_orders
      where id = (select id from shipment_ids where name = 'order') and status <> 'confirmed'),
  0,
  'a preview writes nothing: no receipt, no email, the order is still confirmed'
);

insert into shipment_values
select 'recorded', public.record_online_order_shipment(
  (select id from shipment_ids where name = 'order'),
  (select version from public.online_orders where id = (select id from shipment_ids where name = 'order')),
  'despacho-001',
  (select value::jsonb from shipment_values where name = 'draft')
)::text;

select is(
  (select (value::jsonb)->>'order_status' from shipment_values where name = 'recorded'),
  'shipped',
  'a confirmed order goes straight to shipped with its receipt'
);
select is(
  (select tracking_number || '|' || shipping_carrier || '|' || coalesce(tracking_url, '')
     from public.online_orders where id = (select id from shipment_ids where name = 'order')),
  '770000000001|Correos de Chile|https://www.correos.cl/web/guest/seguimiento-en-linea',
  'the order keeps the tracking number without spaces, the carrier and its page'
);
select is(
  (select count(*)::int from public.online_order_events
    where order_id = (select id from shipment_ids where name = 'order')
      and event_type = 'status_transition' and to_status = 'processing'),
  0,
  'it skips «processing», so the customer does not get two emails'
);
select is(
  (select service || '|' || cost::text || '|' || created_by::text
     from public.online_order_shipments where operation_key = 'despacho-001'),
  'Paquete Express AM|6240.00|96300000-0000-4000-8000-000000000099',
  'the receipt is stored with its service, cost and who registered it'
);

-- El correo «va en camino» cuenta con qué se envió y adónde.
select is(
  (select render_payload->'shipment'->>'trackingNumber' || '|' ||
          (render_payload->'shipment'->>'service') || '|' ||
          (render_payload->'delivery'->>'addressLine1') || '|' ||
          (render_payload->'delivery'->>'city')
     from public.transactional_email_outbox
    where order_id = (select id from shipment_ids where name = 'order')
      and message_kind = 'shipped'),
  '770000000001|Paquete Express AM|Calle Inventada 123|Comuna Inventada',
  'the shipped email carries the shipment and the delivery address'
);
select is(
  (select coalesce(render_payload->'store'->>'brandColor', '') || '|' ||
          coalesce(render_payload->'store'->>'headingFont', '')
     from public.transactional_email_outbox
    where order_id = (select id from shipment_ids where name = 'order')
      and message_kind = 'shipped'),
  '#123F68|Oswald',
  'the email takes the brand color and heading font from the site theme'
);
select is(
  (select render_payload->'store' ? 'bodyFont'
     from public.transactional_email_outbox
    where order_id = (select id from shipment_ids where name = 'order')
      and message_kind = 'shipped'),
  false,
  'a font name that is not a plain name never reaches the email'
);
select is(
  (select count(*)::int from public.transactional_email_outbox
    where order_id = (select id from shipment_ids where name = 'order')
      and message_kind = 'shipped'),
  1,
  'exactly one shipped email is queued'
);

select is(
  public.record_online_order_shipment(
    (select id from shipment_ids where name = 'order'),
    1,
    'despacho-001',
    '{}'::jsonb
  )->>'replay',
  'true',
  'the same operation replays its receipt'
);
select is(
  (select count(*)::int from public.online_order_shipments
    where order_id = (select id from shipment_ids where name = 'order')),
  1,
  'a replay does not duplicate the receipt'
);

select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-002', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order')),
    jsonb_build_object('carrier', 'Starken', 'tracking_number', '123')::text
  ),
  '23514',
  'El pedido ya no espera despacho (está shipped).',
  'a shipped order does not take a second shipment as a new status'
);

select ok(
  has_table_privilege('authenticated', 'public.online_order_shipments', 'select')
  and not has_table_privilege('authenticated', 'public.online_order_shipments', 'insert')
  and not has_table_privilege('authenticated', 'public.online_order_shipments', 'update'),
  'staff read the receipts and write them only through the command'
);
select ok(
  not has_function_privilege('anon', 'public.record_online_order_shipment(uuid,bigint,text,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.record_online_order_shipment(uuid,bigint,text,jsonb)', 'execute'),
  'only signed-in staff can record a shipment'
);

select is(
  (select render_payload from public.transactional_email_outbox
    where order_id = (select id from shipment_ids where name = 'order')
      and message_kind = 'shipped'),
  (select (value::jsonb)->'payload' from shipment_values where name = 'preview'),
  'the email that was queued is exactly the one the preview showed'
);
select throws_ok(
  format(
    $$select public.preview_online_order_shipment_email(%L, %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    jsonb_build_object('carrier', 'Starken', 'tracking_number', '123456')::text
  ),
  '23514',
  'El pedido ya no espera despacho (está shipped).',
  'a shipped order has no shipment email to preview'
);
select ok(
  not has_function_privilege('anon', 'public.preview_online_order_shipment_email(uuid,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.preview_online_order_shipment_email(uuid,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.transactional_email_render_payload(public.online_orders,text,public.online_order_shipments)', 'execute'),
  'only signed-in staff preview, and the payload builder stays internal'
);

-- Otro taller no ve ni registra.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', '96300000-0000-4000-8000-000000000098', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '96300000-0000-4000-8000-000000000098', true);
set local role authenticated;
select is(
  (select count(*)::int from public.online_order_shipments),
  0,
  'another tenant does not see the receipts'
);
reset role;
select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, 99, 'despacho-ajeno', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    jsonb_build_object('carrier', 'Starken', 'tracking_number', '123')::text
  ),
  '42501',
  null,
  'another tenant cannot record a shipment on the order'
);
select throws_ok(
  format(
    $$select public.preview_online_order_shipment_email(%L, %L::jsonb)$$,
    (select id from shipment_ids where name = 'order'),
    jsonb_build_object('carrier', 'Starken', 'tracking_number', '123456')::text
  ),
  '42501',
  null,
  'another tenant cannot preview the order''s email'
);

select * from finish();
rollback;
