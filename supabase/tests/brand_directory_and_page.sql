begin;

select plan(18);

-- El directorio de marcas y la página de una marca (20261115101500).
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('b7a00000-0000-4000-8000-000000000001', 'Taller directorio de marcas', 'CLP', 'America/Santiago'),
  ('b7a00000-0000-4000-8000-000000000002', 'Otro taller directorio', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b7a00000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'marcas-directorio@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"b7a00000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('b7a00000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'vecino-directorio@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"b7a00000-0000-4000-8000-000000000002"}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'b7a00000-0000-4000-8000-000000000091', 'b7a00000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('b7a00000-0000-4000-8000-000000000091', 'b7a00000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true),
  ('b7a00000-0000-4000-8000-000000000092', 'b7a00000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

insert into public.suppliers (id, tenant_id, name) values
  ('b7a00000-0000-4000-8000-0000000000a1', 'b7a00000-0000-4000-8000-000000000001', 'Norte Directorio (prueba)'),
  ('b7a00000-0000-4000-8000-0000000000a2', 'b7a00000-0000-4000-8000-000000000001', 'Sur Directorio (prueba)'),
  ('b7a00000-0000-4000-8000-0000000000a3', 'b7a00000-0000-4000-8000-000000000002', 'Vecino Directorio (prueba)');

-- Pedalia y Ruedex son del catálogo compartido, Propia es del taller y Ajena
-- es del otro taller.
insert into public.product_brands (id, tenant_id, name, is_active) values
  ('b7a00000-0000-4000-8000-0000000000b1', null, 'Pedalia Directorio', true),
  ('b7a00000-0000-4000-8000-0000000000b2', null, 'Ruedex Directorio', true),
  ('b7a00000-0000-4000-8000-0000000000b3', 'b7a00000-0000-4000-8000-000000000001', 'Propia Directorio', true),
  ('b7a00000-0000-4000-8000-0000000000b4', 'b7a00000-0000-4000-8000-000000000002', 'Ajena Directorio', true);

insert into public.customers (id, tenant_id, name) values
  ('b7a00000-0000-4000-8000-000000000071', 'b7a00000-0000-4000-8000-000000000001', 'Renato Prueba');
insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('b7a00000-0000-4000-8000-000000000072', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000071', 'Trek', 'Marlin 7');

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, brand_id, image_url, image_url_optimized
) values
  -- Se vende y tiene stock: su foto liviana es la que se muestra.
  ('b7a00000-0000-4000-8000-000000000011', 'b7a00000-0000-4000-8000-000000000001',
   'Cámara Pedalia 29', 'DIR-1', 5000, 1000, 19, 'product', false, true, 3, 3, 0, 10, true, true, true,
   'b7a00000-0000-4000-8000-0000000000b1', 'https://example.invalid/p1.jpg', 'https://example.invalid/p1-o.jpg'),
  -- Sin stock, sin foto y fuera de la web.
  ('b7a00000-0000-4000-8000-000000000012', 'b7a00000-0000-4000-8000-000000000001',
   'Neumático Pedalia 27.5', 'DIR-2', 20000, 500, 19, 'product', false, true, 0, 0, 0, 10, true, false, false,
   'b7a00000-0000-4000-8000-0000000000b1', null, null),
  -- Archivado: no se cuenta como producto, pero lo que vendió sí.
  ('b7a00000-0000-4000-8000-000000000013', 'b7a00000-0000-4000-8000-000000000001',
   'Puños Pedalia viejos', 'DIR-3', 3000, 800, 19, 'product', false, true, 0, 0, 0, 10, false, false, false,
   'b7a00000-0000-4000-8000-0000000000b1', 'https://example.invalid/p3.jpg', null),
  ('b7a00000-0000-4000-8000-000000000014', 'b7a00000-0000-4000-8000-000000000001',
   'Neumático Ruedex 29', 'DIR-4', 25000, 2000, 19, 'product', false, true, 2, 2, 0, 10, true, true, true,
   'b7a00000-0000-4000-8000-0000000000b2', 'https://example.invalid/p4.jpg', null),
  ('b7a00000-0000-4000-8000-000000000015', 'b7a00000-0000-4000-8000-000000000001',
   'Pedal Propia', 'DIR-5', 9000, 300, 19, 'product', false, true, 1, 1, 0, 10, true, false, false,
   'b7a00000-0000-4000-8000-0000000000b3', null, null),
  ('b7a00000-0000-4000-8000-000000000016', 'b7a00000-0000-4000-8000-000000000002',
   'Pedal Ajena', 'DIR-6', 9000, 300, 19, 'product', false, true, 9, 9, 0, 10, true, false, false,
   'b7a00000-0000-4000-8000-0000000000b4', null, null);

insert into public.stock_movements (tenant_id, product_id, movement_type, type, quantity, created_at) values
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000011', 'sale', 'OUT', -4, now() - interval '10 days'),
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000011', 'sales_invoice_reversal', 'IN', 1, now() - interval '5 days'),
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000012', 'sale', 'OUT', -1, now() - interval '2 days'),
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000013', 'sales_invoice', 'OUT', -2, now() - interval '40 days'),
  -- Hace más de un año: no cuenta.
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000011', 'sale', 'OUT', -10, now() - interval '13 months'),
  -- Una compra no es una venta.
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000011', 'purchase_receipt', 'IN', 6, now() - interval '20 days'),
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000014', 'sale', 'OUT', -1, now() - interval '1 day'),
  ('b7a00000-0000-4000-8000-000000000002', 'b7a00000-0000-4000-8000-000000000016', 'sale', 'OUT', -5, now() - interval '1 day');

-- Sur trae Pedalia sin habérsela comprado, y es el representante oficial de
-- Ruedex. A Norte se le compró de las dos.
insert into public.supplier_brands (tenant_id, supplier_id, brand_id, official, source, evidence) values
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-0000000000a2', 'b7a00000-0000-4000-8000-0000000000b1', false, 'manual', '{}'::jsonb),
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-0000000000a2', 'b7a00000-0000-4000-8000-0000000000b2', true, 'catalog', '{}'::jsonb);

insert into public.purchase_invoices (
  id, tenant_id, supplier_id, supplier_name, invoice_number, date, status, tax_treatment
) values
  ('b7a00000-0000-4000-8000-000000000051', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-0000000000a1', 'Norte Directorio (prueba)', 'DIR-F1',
   date '2026-10-01', 'received', 'no_tax'),
  ('b7a00000-0000-4000-8000-000000000052', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-0000000000a1', 'Norte Directorio (prueba)', 'DIR-F2',
   date '2026-10-05', 'paid', 'no_tax'),
  -- Un borrador no es una compra.
  ('b7a00000-0000-4000-8000-000000000053', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-0000000000a2', 'Sur Directorio (prueba)', 'DIR-F3',
   date '2026-10-07', 'draft', 'no_tax');
insert into public.purchase_invoice_lines (
  id, tenant_id, purchase_invoice_id, line_number, product_id, description,
  quantity, net_amount, line_kind, line_nature, classification_status, currency_code
) values
  ('b7a00000-0000-4000-8000-000000000061', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000051', 1, 'b7a00000-0000-4000-8000-000000000011',
   'Cámara Pedalia 29', 5, 5000, 'item', 'inventory', 'classified', 'CLP'),
  ('b7a00000-0000-4000-8000-000000000062', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000052', 1, 'b7a00000-0000-4000-8000-000000000014',
   'Neumático Ruedex 29', 2, 4000, 'item', 'inventory', 'classified', 'CLP'),
  ('b7a00000-0000-4000-8000-000000000063', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000053', 1, 'b7a00000-0000-4000-8000-000000000011',
   'Cámara Pedalia 29', 1, 1000, 'item', 'inventory', 'classified', 'CLP');

insert into public.conversations (id, tenant_id, type, channel, counterparty_type, title, status) values
  ('b7a00000-0000-4000-8000-000000000081', 'b7a00000-0000-4000-8000-000000000001',
   'support', 'whatsapp', 'supplier', 'Norte Directorio (prueba)', 'active');
insert into public.messages (id, conversation_id, tenant_id, sender_id, content, type, metadata, message_direction)
values
  ('b7a00000-0000-4000-8000-000000000082', 'b7a00000-0000-4000-8000-000000000081',
   'b7a00000-0000-4000-8000-000000000001', null, 'lista de precios', 'text', '{}'::jsonb, 'inbound'),
  ('b7a00000-0000-4000-8000-000000000085', 'b7a00000-0000-4000-8000-000000000081',
   'b7a00000-0000-4000-8000-000000000001', null, 'otro archivo', 'text', '{}'::jsonb, 'inbound');
insert into public.messaging_attachments (
  id, tenant_id, conversation_id, message_id, storage_bucket, storage_path, original_filename,
  extension, declared_mime_type, size_bytes, status, attached_at
) values
  -- Nombra la marca como palabra entera.
  ('b7a00000-0000-4000-8000-000000000083', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000081', 'b7a00000-0000-4000-8000-000000000082', 'chat-attachments',
   'b7a00000-0000-4000-8000-000000000001/b7a00000-0000-4000-8000-000000000081/b7a00000-0000-4000-8000-000000000083.pdf',
   'LISTA_PEDALIA_DIRECTORIO_OCT_2026.pdf', 'pdf', 'application/pdf', 1200, 'attached', now() - interval '3 days'),
  -- Pegada a otra palabra: no la nombra.
  ('b7a00000-0000-4000-8000-000000000084', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000081', 'b7a00000-0000-4000-8000-000000000085', 'chat-attachments',
   'b7a00000-0000-4000-8000-000000000001/b7a00000-0000-4000-8000-000000000081/b7a00000-0000-4000-8000-000000000084.pdf',
   'pedaliadirectorio.pdf', 'pdf', 'application/pdf', 1200, 'attached', now() - interval '2 days');
select set_config('request.jwt.claim.role', '', true);

insert into public.mechanic_jobs (id, tenant_id, customer_id, bike_id, job_number, created_by) values
  ('b7a00000-0000-4000-8000-000000000041', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000071', 'b7a00000-0000-4000-8000-000000000072',
   'PG-DIR-1', 'b7a00000-0000-4000-8000-000000000091');
insert into public.mechanic_job_bikes (tenant_id, job_id, bike_id) values
  ('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-000000000041',
   'b7a00000-0000-4000-8000-000000000072')
on conflict (job_id, bike_id) do nothing;
insert into public.mechanic_job_items (
  id, tenant_id, job_id, job_bike_id, product_id, product_name, item_type, quantity, unit_price
) values
  ('b7a00000-0000-4000-8000-000000000042', 'b7a00000-0000-4000-8000-000000000001',
   'b7a00000-0000-4000-8000-000000000041',
   (select jb.id from public.mechanic_job_bikes jb
     where jb.job_id = 'b7a00000-0000-4000-8000-000000000041'
       and jb.bike_id = 'b7a00000-0000-4000-8000-000000000072'),
   'b7a00000-0000-4000-8000-000000000011', 'Cámara Pedalia 29', 'product', 1, 5000);

select ok(
  has_function_privilege('authenticated', 'public.brand_directory_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.brand_page_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.brand_directory_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.brand_page_v1(uuid, uuid)', 'EXECUTE'),
  'the team reads brands through the two reads and an anonymous visitor cannot');

select set_config('request.jwt.claims', '{"sub":"b7a00000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b7a00000-0000-4000-8000-000000000092', true);

select throws_ok(
  $$ select public.brand_directory_v1('b7a00000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'another shop cannot read this shop''s brand directory');

select throws_ok(
  $$ select public.brand_page_v1('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-0000000000b1') $$,
  '42501', null,
  'another shop cannot read this shop''s brand page');

select set_config('request.jwt.claims', '{"sub":"b7a00000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'b7a00000-0000-4000-8000-000000000091', true);

create temporary table directory as
select value as entry
  from jsonb_array_elements(public.brand_directory_v1('b7a00000-0000-4000-8000-000000000001'));

select is(
  (select jsonb_agg(entry->>'name' order by entry->>'name' collate "C") from directory),
  '["Pedalia Directorio", "Propia Directorio", "Ruedex Directorio"]'::jsonb,
  'the directory lists the shop''s brands and the shared catalog, never another shop''s');

select is(
  (select jsonb_build_object(
            'products', entry->'products', 'in_stock', entry->'in_stock', 'units', entry->'units',
            'stock_cost', entry->'stock_cost', 'on_web', entry->'on_web', 'shared', entry->'shared')
     from directory where entry->>'name' = 'Pedalia Directorio'),
  '{"products": 2, "in_stock": 1, "units": 3, "stock_cost": 3000, "on_web": 1, "shared": true}'::jsonb,
  'a brand counts its active products, what has stock, its units at cost and what is on the web');

select is(
  (select (entry->>'sold_12m')::numeric from directory where entry->>'name' = 'Pedalia Directorio'),
  6::numeric,
  'sold in twelve months is sales minus voided sales, archived products included, older sales and purchases left out');

select is(
  (select (entry->>'last_sale')::timestamptz::date from directory where entry->>'name' = 'Pedalia Directorio'),
  (now() - interval '2 days')::date,
  'the last sale is the latest sale, not the latest void');

select is(
  (select entry->'images' from directory where entry->>'name' = 'Pedalia Directorio'),
  '["https://example.invalid/p1-o.jpg"]'::jsonb,
  'the photos are the light variant of the best-selling active products that have one');

select is(
  (select jsonb_build_object('name', entry->'supplier'->'name', 'official', entry->'supplier'->'official',
                             'count', entry->'supplier_count')
     from directory where entry->>'name' = 'Pedalia Directorio'),
  '{"name": "Norte Directorio (prueba)", "official": false, "count": 2}'::jsonb,
  'without an official representative the supplier named first is the one we bought from most');

select is(
  (select jsonb_build_object('name', entry->'supplier'->'name', 'official', entry->'supplier'->'official',
                             'count', entry->'supplier_count', 'sold', entry->'sold_12m')
     from directory where entry->>'name' = 'Ruedex Directorio'),
  '{"name": "Sur Directorio (prueba)", "official": true, "count": 2, "sold": 1}'::jsonb,
  'the official representative is named first even when we bought from someone else');

select is(
  (select jsonb_build_object('supplier', entry->'supplier', 'count', entry->'supplier_count',
                             'shared', entry->'shared', 'images', entry->'images')
     from directory where entry->>'name' = 'Propia Directorio'),
  '{"supplier": null, "count": 0, "shared": false, "images": []}'::jsonb,
  'a brand nobody brings says so instead of inventing a supplier');

select is(
  public.brand_page_v1('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-0000000000b4'),
  null,
  'another shop''s brand has no page here');

create temporary table page as
select public.brand_page_v1('b7a00000-0000-4000-8000-000000000001', 'b7a00000-0000-4000-8000-0000000000b1') as p;

select is(
  (select jsonb_build_object('name', p->'brand'->'name', 'shared', p->'brand'->'shared',
                             'products', p->'totals'->'products', 'sold', p->'totals'->'sold_12m')
     from page),
  '{"name": "Pedalia Directorio", "shared": true, "products": 2, "sold": 6}'::jsonb,
  'the page carries the brand and the same totals as the directory');

select is(
  (select jsonb_agg(x->>'sku' order by ordinality)
     from page, jsonb_array_elements(p->'products') with ordinality as t(x, ordinality)),
  '["DIR-1", "DIR-2"]'::jsonb,
  'the page lists the active products, best sellers first');

select is(
  (select jsonb_agg(jsonb_build_object('name', x->'name', 'carries', x->'carries',
                                       'purchases', x->'purchases', 'units', x->'units')
                    order by ordinality)
     from page, jsonb_array_elements(p->'suppliers') with ordinality as t(x, ordinality)),
  '[{"name": "Norte Directorio (prueba)", "carries": false, "purchases": 1, "units": 5},
    {"name": "Sur Directorio (prueba)", "carries": true, "purchases": 0, "units": 0}]'::jsonb,
  'the page names who brings the brand and who we bought it from, draft invoices left out');

select is(
  (select jsonb_build_object('total', p->'jobs'->'total',
                             'number', p->'jobs'->'recent'->0->'job_number',
                             'customer', p->'jobs'->'recent'->0->'customer_name',
                             'bike', p->'jobs'->'recent'->0->'bike',
                             'item', p->'jobs'->'recent'->0->'first_item')
     from page),
  '{"total": 1, "number": "PG-DIR-1", "customer": "Renato Prueba", "bike": "Trek Marlin 7", "item": "Cámara Pedalia 29"}'::jsonb,
  'the page lists the jobs that used the brand''s products, with their customer and bike');

select is(
  (select jsonb_build_object('total', p->'files'->'total',
                             'name', p->'files'->'recent'->0->'original_filename',
                             'from', p->'files'->'recent'->0->'conversations'->'title')
     from page),
  '{"total": 1, "name": "LISTA_PEDALIA_DIRECTORIO_OCT_2026.pdf", "from": "Norte Directorio (prueba)"}'::jsonb,
  'a received file names the brand only when its name holds the brand as whole words');

select is(
  (select p->'files'->'recent'->0->'conversations'->'whatsapp_conversation_bindings' from page),
  '[]'::jsonb,
  'a file keeps the shape the search reads, with an empty list when the chat has no WhatsApp contact');

select * from finish();
rollback;
