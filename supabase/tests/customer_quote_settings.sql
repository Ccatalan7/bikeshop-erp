begin;

select plan(13);

-- Ajustes de cotizaciones (20261103060000): los cambia quien cambia los
-- ajustes del taller, cada valor se valida con su nombre, el recordatorio
-- cae antes de vencer y el pago adelantado queda en 100 %. Un cambio vale
-- para la próxima oferta que se envía.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0d90000-0000-4000-8000-000000000001', 'Taller ajustes', 'CLP', 'America/Santiago'),
  ('c0d90000-0000-4000-8000-000000000002', 'Otro taller ajustes', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0d90000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'admin-ajustes@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d90000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0d90000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'caja-ajustes@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d90000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0d90000-0000-4000-8000-000000000094', 'authenticated', 'authenticated',
   'admin-otro-ajustes@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0d90000-0000-4000-8000-000000000002"}'::jsonb, now(), now()),
  ('c0d90000-0000-4000-8000-000000000093', 'authenticated', 'authenticated',
   'rocio@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c0d90000-0000-4000-8000-000000000091', 'c0d90000-0000-4000-8000-000000000092',
  'c0d90000-0000-4000-8000-000000000094');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0d90000-0000-4000-8000-000000000091', 'c0d90000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true),
  ('c0d90000-0000-4000-8000-000000000092', 'c0d90000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true),
  ('c0d90000-0000-4000-8000-000000000094', 'c0d90000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

insert into public.customers (id, tenant_id, auth_user_id, name, email, phone, is_active) values
  ('c0d90000-0000-4000-8000-0000000000c1', 'c0d90000-0000-4000-8000-000000000001',
   'c0d90000-0000-4000-8000-000000000093', 'Rocío Tapia', 'rocio@example.invalid', null, true);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values
  ('c0d90000-0000-4000-8000-000000000011', 'c0d90000-0000-4000-8000-000000000001',
   'Cadena 12 velocidades', 'AJ-CHAIN', 32000, 15000, 19, 'product', false, true,
   3, 3, 0, 100, true, true, true);
select set_config('request.jwt.claim.role', '', true);

select ok(
  has_function_privilege('authenticated', 'public.customer_quote_settings_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_settings_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.update_customer_quote_settings_v1(uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.customer_quote_setting_value_internal(jsonb, text, integer, integer, integer)', 'EXECUTE'),
  'the team reads and changes the settings through its commands only');

-- La caja lee, pero no cambia lo que se le promete al cliente.
select set_config('request.jwt.claims', '{"sub":"c0d90000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d90000-0000-4000-8000-000000000092', true);
set local role authenticated;
select is(
  public.customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001') - 'updated_at',
  '{"offer_validity_hours":72,"reminder_hours_before":24,"on_order_prepay_percent":100,
    "supplier_task_due_hours":24,"supplier_check_fresh_hours":48,"can_edit":false}'::jsonb,
  'without a row the defaults hold, and the cashier cannot change them');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"offer_validity_hours":96}')$$,
  '42501', 'quote_settings_not_allowed', 'the cashier cannot change them');
reset role;

-- Administración sí, valor por valor.
select set_config('request.jwt.claims', '{"sub":"c0d90000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d90000-0000-4000-8000-000000000091', true);
set local role authenticated;
select is(
  public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
    '{"offer_validity_hours":96,"reminder_hours_before":12}') - 'updated_at',
  '{"offer_validity_hours":96,"reminder_hours_before":12,"on_order_prepay_percent":100,
    "supplier_task_due_hours":24,"supplier_check_fresh_hours":48,"can_edit":true}'::jsonb,
  'the admin changes the validity and the reminder; the rest stays');
select is(
  public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
    '{"supplier_task_due_hours":6}') ->> 'offer_validity_hours',
  '96',
  'a later change of one value keeps the others');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"on_order_prepay_percent":50}')$$,
  '22023', 'quote_deposit_unsupported', 'a deposit below 100 % has no path yet');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"reminder_hours_before":96}')$$,
  '22023', 'quote_settings_invalid', 'a reminder that falls on the sending is refused');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"offer_validity_hours":5}')$$,
  '22023', 'quote_settings_invalid', 'a validity under 12 hours is refused');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"offer_validity_hours":"tres días"}')$$,
  '22023', 'quote_settings_invalid', 'a value that is not a number is refused');
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"supplier_check_fresh_hours":12.5}')$$,
  '22023', 'quote_settings_invalid', 'hours are whole');
reset role;

-- Otro taller no lee ni cambia los de este.
select set_config('request.jwt.claims', '{"sub":"c0d90000-0000-4000-8000-000000000094","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d90000-0000-4000-8000-000000000094', true);
set local role authenticated;
select throws_ok(
  $$select public.update_customer_quote_settings_v1('c0d90000-0000-4000-8000-000000000001',
      '{"offer_validity_hours":24}')$$,
  '42501', null, 'another shop cannot change them');
reset role;

-- La próxima oferta vale lo nuevo: Rocío pide una cadena en stock y el
-- equipo envía la oferta.
select set_config('request.jwt.claims', '{"sub":"c0d90000-0000-4000-8000-000000000093","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d90000-0000-4000-8000-000000000093', true);
set local role authenticated;
select set_config('aj.q', public.request_public_customer_quote_v1(
  'c0d90000-0000-4000-8000-000000000001',
  '{"request_idempotency_key":"8c1c2a3b-4d5e-4f60-8a71-000000000001","notify_email":true,"notify_whatsapp":false,
    "items":[{"product_id":"c0d90000-0000-4000-8000-000000000011","quantity":1}]}')::text, true);
reset role;

select set_config('request.jwt.claims', '{"sub":"c0d90000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0d90000-0000-4000-8000-000000000091', true);
set local role authenticated;
select set_config('aj.tmp', public.customer_quote_send_offer_v1(
  'c0d90000-0000-4000-8000-000000000001',
  (current_setting('aj.q')::jsonb ->> 'quote_id')::uuid,
  '8d1c2a3b-4d5e-4f60-8a71-000000000001')::text, true);
reset role;

select is(
  (select round(extract(epoch from (o.valid_until - o.sent_at)) / 3600)::int
     from public.customer_quote_offers o
    where o.quote_id = (current_setting('aj.q')::jsonb ->> 'quote_id')::uuid
      and o.status = 'sent'),
  96,
  'the offer sent after the change holds 96 hours');

select is(
  (select s.updated_by from public.customer_quote_settings s
    where s.tenant_id = 'c0d90000-0000-4000-8000-000000000001'),
  'c0d90000-0000-4000-8000-000000000091'::uuid,
  'the change names who made it');

select * from finish();
rollback;
