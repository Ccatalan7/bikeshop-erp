begin;

select plan(18);

-- Qué se cotiza sin stock (20261103070000): la ficha decide (se cotiza, no
-- se ofrece, a pedido) y, si no decide, su marca, de la lista de Ajustes. El
-- sitio lo lee sin el proveedor, la solicitud no acepta más allá del stock lo
-- que no se ofrece, y el equipo cotiza lo que quiera.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0dc0000-0000-4000-8000-000000000001', 'Taller agotados', 'CLP', 'America/Santiago'),
  ('c0dc0000-0000-4000-8000-000000000002', 'Otro taller agotados', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0dc0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-agotados@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0dc0000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0dc0000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'caja-agotados@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0dc0000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0dc0000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'tomas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c0dc0000-0000-4000-8000-000000000091', 'c0dc0000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0dc0000-0000-4000-8000-000000000091', 'c0dc0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('c0dc0000-0000-4000-8000-000000000092', 'c0dc0000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0dc0000-0000-4000-8000-0000000000c1', 'c0dc0000-0000-4000-8000-000000000001',
   'c0dc0000-0000-4000-8000-000000000093', 'Tomás Rivas', 'tomas@example.invalid', null, true);

-- Pedalia es una marca reconocida del catálogo compartido; Ruedex, no; la
-- tercera es de otro taller.
insert into public.product_brands (id, tenant_id, name, is_active) values
  ('c0dc0000-0000-4000-8000-0000000000b1', null, 'Pedalia Agotados', true),
  ('c0dc0000-0000-4000-8000-0000000000b2', null, 'Ruedex Agotados', true),
  ('c0dc0000-0000-4000-8000-0000000000b3', 'c0dc0000-0000-4000-8000-000000000002', 'Ajena Agotados', true);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, brand_id
) values
  -- Sin stock: de la marca de la lista, de otra, con la ficha a favor, con
  -- la ficha en contra, a pedido y sin marca. El último sí tiene stock.
  ('c0dc0000-0000-4000-8000-000000000011', 'c0dc0000-0000-4000-8000-000000000001',
   'Cassette Pedalia 12v', 'AG-1', 89000, 50000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b1'),
  ('c0dc0000-0000-4000-8000-000000000012', 'c0dc0000-0000-4000-8000-000000000001',
   'Pedal Ruedex plástico', 'AG-2', 6000, 2000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b2'),
  ('c0dc0000-0000-4000-8000-000000000013', 'c0dc0000-0000-4000-8000-000000000001',
   'Llanta Ruedex 29 doble pared', 'AG-3', 45000, 25000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b2'),
  ('c0dc0000-0000-4000-8000-000000000014', 'c0dc0000-0000-4000-8000-000000000001',
   'Cadena Pedalia 7v descontinuada', 'AG-4', 9000, 4000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b1'),
  ('c0dc0000-0000-4000-8000-000000000015', 'c0dc0000-0000-4000-8000-000000000001',
   'Neumático Ruedex 29 x 2.40', 'AG-5', 39000, 20000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b2'),
  ('c0dc0000-0000-4000-8000-000000000016', 'c0dc0000-0000-4000-8000-000000000001',
   'Puños sin marca', 'AG-6', 3000, 1000, 19, 'product', false, true, 0, 0, 0, 10, true, true, true,
   null),
  ('c0dc0000-0000-4000-8000-000000000017', 'c0dc0000-0000-4000-8000-000000000001',
   'Cámara Ruedex 29', 'AG-7', 5000, 2000, 19, 'product', false, true, 2, 2, 0, 10, true, true, true,
   'c0dc0000-0000-4000-8000-0000000000b2');
select set_config('request.jwt.claim.role', '', true);

select ok(
  has_function_privilege('anon', 'public.get_public_sold_out_offers_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_sold_out_summary_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_sold_out_summary_v1(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.customer_quote_sold_out_brands', 'INSERT')
  and not has_table_privilege('authenticated', 'public.customer_quote_sold_out_brands', 'DELETE'),
  'the site reads the offers, the team reads the summary, and the brand list changes only by its command');

-- Administración elige las marcas; la caja no; una marca ajena o inventada no.
select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000092', true);
set local role authenticated;
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"sold_out_brand_ids":["c0dc0000-0000-4000-8000-0000000000b1"]}')$$,
  '42501', 'quote_settings_not_allowed', 'the cashier cannot choose the brands');
reset role;

select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
    '{"sold_out_brand_ids":["c0dc0000-0000-4000-8000-0000000000b1"]}') -> 'sold_out_brands',
  '[{"id":"c0dc0000-0000-4000-8000-0000000000b1","name":"Pedalia Agotados"}]'::jsonb,
  'the admin lists a brand that is quoted without stock');
select is(
  public.customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001') ->> 'offer_validity_hours',
  '72', 'choosing brands keeps the other values');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"sold_out_brand_ids":["c0dc0000-0000-4000-8000-0000000000b3"]}')$$,
  '22023', 'quote_settings_invalid', 'another shop''s brand is not one to choose');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"sold_out_brand_ids":["c0dc0000-0000-4000-8000-0000000000ff"]}')$$,
  '22023', 'quote_settings_invalid', 'a brand that does not exist is refused');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"sold_out_brand_ids":"Pedalia"}')$$,
  '22023', 'quote_settings_invalid', 'the list is a list');

-- La ficha decide: se cotiza, no se ofrece, a pedido.
select set_config('ag.tmp', public.set_product_on_order_terms_v1('c0dc0000-0000-4000-8000-000000000001',
  'c0dc0000-0000-4000-8000-000000000013', '{"is_active":false,"quote_when_sold_out":true}')::text, true);
select set_config('ag.tmp', public.set_product_on_order_terms_v1('c0dc0000-0000-4000-8000-000000000001',
  'c0dc0000-0000-4000-8000-000000000014', '{"is_active":false,"quote_when_sold_out":false}')::text, true);
select set_config('ag.tmp', public.set_product_on_order_terms_v1('c0dc0000-0000-4000-8000-000000000001',
  'c0dc0000-0000-4000-8000-000000000015', '{"is_active":true,"lead_days_min":3,"lead_days_max":5}')::text, true);
-- La ficha de la 1.0.45 no manda la decisión: guardar no la borra.
select is(
  public.set_product_on_order_terms_v1('c0dc0000-0000-4000-8000-000000000001',
    'c0dc0000-0000-4000-8000-000000000013', '{"is_active":false}') ->> 'quote_when_sold_out',
  'true', 'saving without the decision keeps it');
select throws_ok(
  $$select public.set_product_on_order_terms_v1('c0dc0000-0000-4000-8000-000000000001',
      'c0dc0000-0000-4000-8000-000000000013', '{"quote_when_sold_out":"sí"}')$$,
  '22023', null, 'the decision is yes, no or the brand');
reset role;

-- Lo que lee el sitio: a pedido con plazo, se cotiza; lo demás no viene.
select is(
  public.get_public_sold_out_offers_v1('c0dc0000-0000-4000-8000-000000000001', array[
    'c0dc0000-0000-4000-8000-000000000011', 'c0dc0000-0000-4000-8000-000000000012',
    'c0dc0000-0000-4000-8000-000000000013', 'c0dc0000-0000-4000-8000-000000000014',
    'c0dc0000-0000-4000-8000-000000000015', 'c0dc0000-0000-4000-8000-000000000016',
    'c0dc0000-0000-4000-8000-000000000017']::uuid[]),
  '{"c0dc0000-0000-4000-8000-000000000011":{"mode":"quote"},
    "c0dc0000-0000-4000-8000-000000000013":{"mode":"quote"},
    "c0dc0000-0000-4000-8000-000000000015":{"mode":"on_order","leadDaysMin":3,"leadDaysMax":5}}'::jsonb,
  'the brand quotes the cassette, the form quotes the rim and turns down the chain, the tyre comes on order');
select is(
  public.get_public_sold_out_offers_v1('c0dc0000-0000-4000-8000-000000000002', array[
    'c0dc0000-0000-4000-8000-000000000011']::uuid[]),
  '{}'::jsonb, 'another shop reads nothing of this one');

select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  public.customer_quote_sold_out_summary_v1('c0dc0000-0000-4000-8000-000000000001') - 'brands',
  '{"sold_out":6,"on_order":1,"quote":2,"none":3,"quoted_by_product":1}'::jsonb,
  'of six sold out, one comes on order, two are quoted (one by its form) and three are not offered');
select is(
  (select e from jsonb_array_elements(
     public.customer_quote_sold_out_summary_v1('c0dc0000-0000-4000-8000-000000000001') -> 'brands') e
    where e ->> 'name' = 'Pedalia Agotados'),
  '{"id":"c0dc0000-0000-4000-8000-0000000000b1","name":"Pedalia Agotados","published":2,"sold_out":2,"follows":1,"listed":true}'::jsonb,
  'each brand says what it has published, sold out, how many follow it and whether it is listed');
reset role;

-- El cliente: lo que no se ofrece sin stock no entra; lo que hay, sí.
select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000093', true);
set local role authenticated;
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"8c1c2a3b-4d5e-4f60-8a71-000000000011","notify_email":true,"notify_whatsapp":false,
        "items":[{"product_id":"c0dc0000-0000-4000-8000-000000000012","quantity":1}]}')$$,
  '22023', 'quote_product_not_available', 'a sold-out product that is not offered is not quoted');
select throws_ok(
  $$select public.request_public_customer_quote_v1('c0dc0000-0000-4000-8000-000000000001',
      '{"request_idempotency_key":"8c1c2a3b-4d5e-4f60-8a71-000000000012","notify_email":true,"notify_whatsapp":false,
        "items":[{"product_id":"c0dc0000-0000-4000-8000-000000000017","quantity":3}]}')$$,
  '22023', 'quote_product_not_available', 'nor more of it than the shelf has');
select set_config('ag.q', public.request_public_customer_quote_v1(
  'c0dc0000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"8c1c2a3b-4d5e-4f60-8a71-000000000013","notify_email":true,"notify_whatsapp":false,
    "items":[{"product_id":"c0dc0000-0000-4000-8000-000000000017","quantity":2},
             {"product_id":"c0dc0000-0000-4000-8000-000000000011","quantity":1},
             {"product_id":"c0dc0000-0000-4000-8000-000000000013","quantity":1},
             {"product_id":"c0dc0000-0000-4000-8000-000000000015","quantity":2}]}')::text, true);
reset role;

select is(
  (select string_agg(l.product_sku || ':' || l.kind_at_request, ',' order by l.line_no)
     from public.customer_quote_lines l
    where l.quote_id = (current_setting('ag.q')::jsonb ->> 'quote_id')::uuid),
  'AG-7:in_stock,AG-1:to_confirm,AG-3:to_confirm,AG-5:on_order',
  'what is on the shelf, what is quoted and what comes on order go in one quote');

-- El equipo, en el ERP, cotiza también lo que el sitio no ofrece.
select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000092', true);
set local role authenticated;
select set_config('ag.s', public.create_staff_customer_quote_v1(
  'c0dc0000-0000-4000-8000-000000000001',
  '{"customer_name":"Mesón","customer_email":"meson@example.invalid","notify_email":true,
    "items":[{"product_id":"c0dc0000-0000-4000-8000-000000000012","quantity":1}]}')::text, true);
reset role;
select is(
  (select l.kind_at_request from public.customer_quote_lines l
    where l.quote_id = (current_setting('ag.s')::jsonb ->> 'quote_id')::uuid),
  'to_confirm', 'the counter quotes the plastic pedal anyway');

-- Sacar la marca de la lista la saca del sitio; la decisión de la ficha queda.
select set_config('request.jwt.claims', '{"sub":"c0dc0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0dc0000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('ag.tmp', public.update_customer_quote_settings_v1('c0dc0000-0000-4000-8000-000000000001',
  '{"sold_out_brand_ids":[]}')::text, true);
reset role;
select is(
  public.get_public_sold_out_offers_v1('c0dc0000-0000-4000-8000-000000000001', array[
    'c0dc0000-0000-4000-8000-000000000011', 'c0dc0000-0000-4000-8000-000000000013']::uuid[]),
  '{"c0dc0000-0000-4000-8000-000000000013":{"mode":"quote"}}'::jsonb,
  'without its brand the cassette is no longer offered; the rim keeps its form''s word');

select * from finish();
rollback;
