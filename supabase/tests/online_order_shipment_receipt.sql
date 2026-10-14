-- La boleta del envío registra el despacho (20261013210000), el correo lleva
-- la marca del tema del sitio (20261013220000), su vista previa es el mismo
-- correo (20261013230000) y el costo del envío queda como gasto, con la fecha
-- de admisión revisada (20261014010000), salvo en un pedido de prueba
-- (20261014020000). Datos inventados; todo se deshace al final.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(39);

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

-- El transportista como proveedor, con su nombre corto como alias.
insert into public.suppliers (id, tenant_id, name, rut, aliases) values
  ('96300000-0000-4000-8000-000000000020', '96300000-0000-4000-8000-000000000001',
   'Correos de Chile', '11.111.111-1', array['Correos']);

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
  'admitted_at', now() - interval '2 hours',
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
  not has_function_privilege('anon', 'public.record_online_order_shipment(uuid,bigint,text,jsonb,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.record_online_order_shipment(uuid,bigint,text,jsonb,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.record_online_order_shipment_expense(uuid,jsonb)', 'execute')
  and has_function_privilege('authenticated', 'public.record_online_order_shipment_expense(uuid,jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.online_order_shipment_expense_options(text)', 'execute')
  and has_function_privilege('authenticated', 'public.online_order_shipment_expense_options(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.online_order_shipment_create_expense(public.online_order_shipments,public.online_orders,jsonb,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.online_order_shipment_expense_plan(uuid,text)', 'execute'),
  'only signed-in staff record a shipment or its expense; the planner and the writer stay internal'
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

-- ---------------------------------------------------------------------------
-- El gasto del envío (20261014010000).
-- ---------------------------------------------------------------------------
select is(
  (select (o->>'supplier_name') || '|' || (o->>'supplier_id') || '|' || (o->>'account_code') || '|' ||
          (select code from public.payment_methods where id = (o->>'payment_method_id')::uuid) || '|' ||
          (o->>'document_type') || '|' || jsonb_array_length(o->'payment_methods')
     from (select public.online_order_shipment_expense_options('Correos') as o) options),
  'Correos de Chile|96300000-0000-4000-8000-000000000020|6402|cash|receipt|4',
  'the carrier is found by its alias; the expense goes to transport, paid in cash on a boleta, with the methods that pay out'
);

insert into shipment_ids
select 'order2', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '96300000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'despacho-test-002',
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
select public.confirm_online_order_payment(
  (select id from shipment_ids where name = 'order2'),
  'BANCO-DESPACHO-002',
  clock_timestamp()
);
insert into storage.objects (bucket_id, name)
values (
  'vinabike-files',
  '96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
    || (select id from shipment_ids where name = 'order2')::text || '/boleta.jpg'
);
insert into shipment_values
select 'draft2', (
  (select value::jsonb from shipment_values where name = 'draft')
  || jsonb_build_object(
    'tracking_number', '770000000002',
    'receipt_path', '96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
      || (select id from shipment_ids where name = 'order2')::text || '/boleta.jpg'
  )
)::text;

-- Una boleta con el año mal leído (2026-10-13: «13/10/2020») no pasa.
select throws_ok(
  format(
    $$select public.preview_online_order_shipment_email(%L, %L::jsonb)$$,
    (select id from shipment_ids where name = 'order2'),
    ((select value::jsonb from shipment_values where name = 'draft2')
      || '{"admitted_at": "2020-10-13T17:43:00-03:00"}'::jsonb)::text
  ),
  '22023',
  'La fecha de admisión (13/10/2020 17:43) no calza: es anterior al pedido o futura. Revísala en la boleta.',
  'the preview refuses an admission before the order existed'
);
select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-2020', %L::jsonb)$$,
    (select id from shipment_ids where name = 'order2'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order2')),
    ((select value::jsonb from shipment_values where name = 'draft2')
      || '{"admitted_at": "2020-10-13T17:43:00-03:00"}'::jsonb)::text
  ),
  '22023',
  'La fecha de admisión (13/10/2020 17:43) no calza: es anterior al pedido o futura. Revísala en la boleta.',
  'and so does the registration'
);

-- Si el gasto no se puede registrar, no se registra nada.
select throws_ok(
  format(
    $$select public.record_online_order_shipment(%L, %s, 'despacho-mal-gasto', %L::jsonb, %L::jsonb)$$,
    (select id from shipment_ids where name = 'order2'),
    (select version from public.online_orders where id = (select id from shipment_ids where name = 'order2')),
    (select value from shipment_values where name = 'draft2'),
    jsonb_build_object('payment_method_id', (
      select id from public.payment_methods
       where tenant_id = '96300000-0000-4000-8000-000000000001' and code = 'mercadopago'
    ))::text
  ),
  '22023',
  'Elige con qué se pagó el envío.',
  'a method that only takes money in cannot pay the shipment'
);
select is(
  (select status || '|' || (select count(*) from public.online_order_shipments
                             where order_id = orders.id)::text
     from public.online_orders orders
    where id = (select id from shipment_ids where name = 'order2')),
  'confirmed|0',
  'when the expense fails, the shipment is not registered either'
);

insert into shipment_values
select 'recorded2', public.record_online_order_shipment(
  (select id from shipment_ids where name = 'order2'),
  (select version from public.online_orders where id = (select id from shipment_ids where name = 'order2')),
  'despacho-003',
  (select value::jsonb from shipment_values where name = 'draft2'),
  jsonb_build_object(
    'payment_method_id', (
      select id from public.payment_methods
       where tenant_id = '96300000-0000-4000-8000-000000000001' and code = 'transfer'
    ),
    'document_type', 'invoice',
    'document_number', 'F-0001'
  )
)::text;

select is(
  (select expense.posting_status || '|' || expense.payment_status || '|' || expense.document_type || '|' ||
          expense.document_number || '|' || expense.subtotal::int || '|' || expense.tax_amount::int || '|' ||
          expense.total_amount::int || '|' || expense.balance::int || '|' || expense.supplier_name || '|' ||
          expense.reference || '|' || (select order_status from (select (value::jsonb)->>'order_status' as order_status
                                          from shipment_values where name = 'recorded2') answer)
     from public.expenses expense
     join public.online_order_shipments shipment on shipment.expense_id = expense.id
    where shipment.operation_key = 'despacho-003'),
  (select 'posted|paid|invoice|F-0001|5244|996|6240|0|Correos de Chile|' || order_number || '|shipped'
     from public.online_orders where id = (select id from shipment_ids where name = 'order2')),
  'the shipment and its cost register together: posted and paid like a quick expense, IVA only with an invoice'
);
select is(
  (select string_agg(line.account_code || ':' || line.debit_amount::int || ':' || line.credit_amount::int, ','
                     order by line.debit_amount desc, line.account_code)
     from public.journal_entries entry
     join public.journal_lines line on line.entry_id = entry.id
    where entry.tenant_id = '96300000-0000-4000-8000-000000000001'
      and entry.source_module = 'expenses'
      and entry.source_reference = (select (value::jsonb)->>'expense_number'
                                      from shipment_values where name = 'recorded2')),
  (select '6402:5244:0,2120:996:0,' || account.code || ':0:6240'
     from public.payment_methods method
     join public.accounts account on account.id = method.account_id
    where method.tenant_id = '96300000-0000-4000-8000-000000000001' and method.code = 'transfer'),
  'one entry: transport and IVA against the account it was paid from'
);
select is(
  (select attachment.file_name || '|' || attachment.file_url || '|' || attachment.file_type
     from public.expense_attachments attachment
    where attachment.expense_id = (select (value::jsonb)->>'expense_id'
                                     from shipment_values where name = 'recorded2')::uuid),
  (select 'Boleta de envío ' || order_number || '.jpg|96300000-0000-4000-8000-000000000001/evidence/online_order_shipment/'
          || id::text || '/boleta.jpg|image/jpeg'
     from public.online_orders where id = (select id from shipment_ids where name = 'order2')),
  'the receipt photo is attached to the expense'
);
select is(
  (select expense_number from public.expenses
    where id = (select (value::jsonb)->>'expense_id' from shipment_values where name = 'recorded2')::uuid),
  (select (value::jsonb)->>'expense_number' from shipment_values where name = 'recorded2'),
  'the command answers with the expense it registered'
);
select is(
  (select (select code from public.payment_methods where id = (o->>'payment_method_id')::uuid) || '|' ||
          (o->>'document_type')
     from (select public.online_order_shipment_expense_options('Correos de Chile') as o) options),
  'transfer|invoice',
  'the next shipment with that carrier starts as the last one was paid'
);

-- Un pedido de prueba no mueve la contabilidad (20261014020000).
update public.online_orders set is_test = true
 where id = (select id from shipment_ids where name = 'order');
select throws_ok(
  format(
    $$select public.record_online_order_shipment_expense(%L, %L::jsonb)$$,
    (select id from public.online_order_shipments where operation_key = 'despacho-001'),
    jsonb_build_object('payment_method_id', (
      select id from public.payment_methods
       where tenant_id = '96300000-0000-4000-8000-000000000001' and code = 'cash'
    ))::text
  ),
  '23514',
  'Un pedido de prueba no registra gastos.',
  'a test order''s shipment never becomes an expense'
);
update public.online_orders set is_test = false
 where id = (select id from shipment_ids where name = 'order');

-- Un despacho registrado sin gasto lo recibe después, una sola vez.
insert into shipment_values
select 'later', public.record_online_order_shipment_expense(
  (select id from public.online_order_shipments where operation_key = 'despacho-001'),
  jsonb_build_object('payment_method_id', (
    select id from public.payment_methods
     where tenant_id = '96300000-0000-4000-8000-000000000001' and code = 'cash'
  ), 'document_type', 'receipt')
)::text;
select is(
  (select expense.document_type || '|' || expense.tax_amount::int || '|' || expense.total_amount::int || '|' ||
          line.account_code || '|' || line.tax_rate::int || '|' || expense.payment_status
     from public.online_order_shipments shipment
     join public.expenses expense on expense.id = shipment.expense_id
     join public.expense_lines line on line.expense_id = expense.id
    where shipment.operation_key = 'despacho-001'),
  'receipt|0|6240|6402|0|paid',
  'a shipment registered without its expense gets it later: a boleta is all expense'
);
select is(
  (public.record_online_order_shipment_expense(
     (select id from public.online_order_shipments where operation_key = 'despacho-001'),
     '{}'::jsonb
   )->>'replay')
  || '|' || (select count(*)::text from public.expenses
              where tenant_id = '96300000-0000-4000-8000-000000000001'
                and reference = (select order_number from public.online_orders
                                  where id = (select id from shipment_ids where name = 'order'))),
  'true|1',
  'one expense per shipment: a second request returns the first'
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
select throws_ok(
  format(
    $$select public.record_online_order_shipment_expense(%L, '{}'::jsonb)$$,
    (select id from public.online_order_shipments where operation_key = 'despacho-003')
  ),
  '42501',
  null,
  'another tenant cannot register an expense on the shipment'
);

select * from finish();
rollback;
