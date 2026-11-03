begin;

select plan(11);

-- La oferta en PDF (20261103050000): la tienda la dibuja con el enlace y el
-- ERP con customer_quote_offer_document_v1, las dos desde la proyección que
-- ve el cliente, ahora con el membrete de la tienda. El pedido que nace al
-- aceptar congela la misma identidad que la cotización muestra.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0d80000-0000-4000-8000-000000000001', 'Taller membrete', 'CLP', 'America/Santiago'),
  ('c0d80000-0000-4000-8000-000000000002', 'Otro taller', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0d80000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-membrete@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d80000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0d80000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'admin-otro@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d80000-0000-4000-8000-000000000002"}'::jsonb, now(), now()),
  ('c0d80000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'pia@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c0d80000-0000-4000-8000-000000000091', 'c0d80000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0d80000-0000-4000-8000-000000000091', 'c0d80000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('c0d80000-0000-4000-8000-000000000092', 'c0d80000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0d80000-0000-4000-8000-0000000000c1', 'c0d80000-0000-4000-8000-000000000001',
   'c0d80000-0000-4000-8000-000000000093', 'Pía Contreras', 'pia@example.invalid', null, true);

insert into public.suppliers (id, tenant_id, name, rut, sales_rep_name, sales_rep_phone) values
  ('c0d80000-0000-4000-8000-000000000031', 'c0d80000-0000-4000-8000-000000000001',
   'Proveedor membrete', '76.555.666-7', 'Vendedor Tres', '+56900000003');

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('c0d80000-0000-4000-8000-000000000011', 'c0d80000-0000-4000-8000-000000000001',
   'Cámara 29 válvula presta', 'ME-STOCK', 6000, 2500, 19, 'product', false, true,
   2, 2, 0, 100, true, true, true, null),
  ('c0d80000-0000-4000-8000-000000000012', 'c0d80000-0000-4000-8000-000000000001',
   'Neumático 29 x 2.40 a pedido', 'ME-ORDER', 48000, 24000, 19, 'product', false, true,
   0, 0, 0, 100, true, true, true, 'c0d80000-0000-4000-8000-000000000031');
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max) values
  ('c0d80000-0000-4000-8000-000000000012', 'c0d80000-0000-4000-8000-000000000001',
   'c0d80000-0000-4000-8000-000000000031', 3, 5);

-- El alta del taller siembra sus ajustes del sitio: se reemplazan los del
-- membrete.
delete from public.website_settings
 where tenant_id = 'c0d80000-0000-4000-8000-000000000001'
   and key in ('store_name', 'business_name', 'store_tagline', 'store_description', 'logo_url',
               'contact_email', 'contact_phone', 'store_url');
insert into public.website_settings (tenant_id, key, value) values
  ('c0d80000-0000-4000-8000-000000000001', 'store_name', 'Bicis del Cerro'),
  ('c0d80000-0000-4000-8000-000000000001', 'store_tagline', 'Taller y tienda en Valparaíso'),
  ('c0d80000-0000-4000-8000-000000000001', 'contact_email', 'hola@example.invalid'),
  ('c0d80000-0000-4000-8000-000000000001', 'contact_phone', '+56 9 1111 2222'),
  ('c0d80000-0000-4000-8000-000000000001', 'store_url', 'https://tienda.example.cl/'),
  ('c0d80000-0000-4000-8000-000000000001', 'payment_transfer_bank_name', 'Banco de prueba'),
  ('c0d80000-0000-4000-8000-000000000001', 'payment_transfer_account_type', 'Cuenta corriente'),
  ('c0d80000-0000-4000-8000-000000000001', 'payment_transfer_account_number', '000123'),
  ('c0d80000-0000-4000-8000-000000000001', 'payment_transfer_account_holder', 'Bicis del Cerro'),
  ('c0d80000-0000-4000-8000-000000000001', 'payment_transfer_rut', '76.000.000-0')
on conflict (tenant_id, key) do update set value = excluded.value;

select ok(
  not has_function_privilege('anon', 'public.storefront_identity_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.storefront_identity_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_offer_document_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_offer_document_v1(uuid, uuid)', 'EXECUTE'),
  'the identity rule is internal and only a signed-in team member reads the document');

select is(
  (select jsonb_build_object(
     'v', i -> 'schemaVersion', 'name', i -> 'displayName', 'tagline', i -> 'tagline',
     'email', i -> 'supportEmail', 'phone', i -> 'supportPhone')
     from (select public.storefront_identity_internal('c0d80000-0000-4000-8000-000000000001') as i) x),
  '{"v":1,"name":"Bicis del Cerro","tagline":"Taller y tienda en Valparaíso",
    "email":"hola@example.invalid","phone":"+56 9 1111 2222"}'::jsonb,
  'the identity is what the store already publishes');

-- Pía pide la cotización y el equipo la confirma y la envía.
select set_config('request.jwt.claims', '{"sub":"c0d80000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d80000-0000-4000-8000-000000000093', true);
set local role authenticated;
select set_config('me.q', public.request_public_customer_quote_v1(
  'c0d80000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"7c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,"notify_whatsapp":false,
    "items":[{"product_id":"c0d80000-0000-4000-8000-000000000011","quantity":2},
             {"product_id":"c0d80000-0000-4000-8000-000000000012","quantity":1}]}')::text, true);
reset role;
select set_config('me.qid', current_setting('me.q')::jsonb ->> 'quote_id', true);

-- Un borrador todavía no es una oferta: el documento no tiene qué dibujar.
select set_config('request.jwt.claims', '{"sub":"c0d80000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d80000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  public.customer_quote_offer_document_v1('c0d80000-0000-4000-8000-000000000001',
    current_setting('me.qid')::uuid) -> 'offer',
  'null'::jsonb,
  'a draft has no offer in the document');

select set_config('me.tmp', public.customer_quote_confirm_line_v1(
  'c0d80000-0000-4000-8000-000000000001',
  (select l.id from public.customer_quote_offer_lines l
     join public.customer_quote_offers o on o.id = l.offer_id
    where o.quote_id = current_setting('me.qid')::uuid and o.status = 'draft' and l.product_sku = 'ME-ORDER'),
  '{"availability":"on_order","quantity_offered":1,"unit_price":48000,"lead_days_min":3,"lead_days_max":5,
    "unit_cost_net":24000}')::text, true);
select set_config('me.tmp', public.customer_quote_send_offer_v1(
  'c0d80000-0000-4000-8000-000000000001', current_setting('me.qid')::uuid,
  '7d1c2a3b-4d5e-4f60-8a71-000000000001', 'Te lo dejamos montado si quieres.')::text, true);
select set_config('me.doc', public.customer_quote_offer_document_v1(
  'c0d80000-0000-4000-8000-000000000001', current_setting('me.qid')::uuid)::text, true);
reset role;

select is(
  (select jsonb_build_object(
     'store', d #>> '{storefront,displayName}',
     'url', d #>> '{storefront,storeUrl}',
     'phone', d #>> '{storefront,supportPhone}',
     'customer', d #>> '{quote,customerName}',
     'total', (d #>> '{offer,total}')::numeric,
     'notes', d #>> '{offer,notes}',
     'lines', jsonb_array_length(d #> '{offer,lines}'))
     from (select current_setting('me.doc')::jsonb as d) doc),
  '{"store":"Bicis del Cerro","url":"https://tienda.example.cl/","phone":"+56 9 1111 2222",
    "customer":"Pía Contreras","total":60000,"notes":"Te lo dejamos montado si quieres.","lines":2}'::jsonb,
  'the team reads the sent offer with the letterhead and where to accept it');

select ok(
  current_setting('me.doc')::jsonb::text not like '%access_token%'
  and current_setting('me.doc')::jsonb::text not like '%pia@example.invalid%'
  and current_setting('me.doc')::jsonb::text not like '%unit_cost%'
  and current_setting('me.doc')::jsonb::text not like '%Proveedor membrete%',
  'the document carries no link, no account email, no cost and no supplier');

-- El cliente ve lo mismo con su enlace.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('me.pub', public.get_public_customer_quote_v1(
  current_setting('me.q')::jsonb ->> 'access_token')::text, true);
reset role;

select is(
  current_setting('me.pub')::jsonb - 'actions' - 'history',
  current_setting('me.doc')::jsonb - 'history',
  'the customer''s link and the team''s document draw the same offer');

-- Otro taller y la clienta no leen el documento.
select set_config('request.jwt.claims', '{"sub":"c0d80000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d80000-0000-4000-8000-000000000092', true);
set local role authenticated;
select throws_ok(
  format($$select public.customer_quote_offer_document_v1('c0d80000-0000-4000-8000-000000000001', %L::uuid)$$,
    current_setting('me.qid')),
  '42501', null, 'another shop cannot read it naming this shop');
select throws_ok(
  format($$select public.customer_quote_offer_document_v1('c0d80000-0000-4000-8000-000000000002', %L::uuid)$$,
    current_setting('me.qid')),
  'P0002', null, 'nor naming its own shop');
reset role;

select set_config('request.jwt.claims', '{"sub":"c0d80000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d80000-0000-4000-8000-000000000093', true);
set local role authenticated;
select throws_ok(
  format($$select public.customer_quote_offer_document_v1('c0d80000-0000-4000-8000-000000000001', %L::uuid)$$,
    current_setting('me.qid')),
  '42501', null, 'the customer reads it through her link, not as the team');
reset role;

-- Pía acepta: el pedido congela la misma identidad que la cotización mostró.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select set_config('me.o', public.accept_public_customer_quote_v1(
  current_setting('me.q')::jsonb ->> 'access_token',
  '{"operation_key":"7e1c2a3b-4d5e-4f60-8a71-000000000001","delivery_type":"pickup","payment_method":"transfer"}')::text,
  true);
reset role;

select is(
  (select s.identity_snapshot from public.online_order_storefront_snapshots s
    where s.order_id = (current_setting('me.o')::jsonb ->> 'order_id')::uuid),
  public.storefront_identity_internal('c0d80000-0000-4000-8000-000000000001'),
  'the order freezes the identity from the same rule');

select is(
  (select count(*)::int from public.online_order_storefront_snapshots s
    where s.order_id = (current_setting('me.o')::jsonb ->> 'order_id')::uuid),
  1,
  'one snapshot per order, as before');

select * from finish();
rollback;
