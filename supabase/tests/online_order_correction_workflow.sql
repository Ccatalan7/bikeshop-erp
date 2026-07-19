begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(51);

select has_table(
  'public', 'online_order_corrections',
  'online correction command projection exists'
);
select has_table(
  'public', 'online_order_correction_events',
  'online correction audit events exist'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.request_online_order_correction(uuid,bigint,jsonb,text,text,text)',
    'EXECUTE'
  ),
  'authorized staff can request an online correction'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.authorize_online_order_refund_execution(uuid)',
    'EXECUTE'
  ),
  'provider execution is gated by a strict authenticated preflight'
);
select has_index(
  'public', 'online_order_corrections',
  'uq_online_order_corrections_mp_refund_evidence',
  'Mercado Pago refund evidence identity is unique across corrections'
);
select has_function(
  'public', 'enqueue_partial_online_order_refund_email', array['uuid'],
  'partial refunds have a dedicated idempotent refund_completed outbox command'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.record_online_order_refund_provider_result(uuid,text,text,text,numeric,text,timestamp with time zone,jsonb,text,text,text)',
    'EXECUTE'
  ),
  'service worker can preserve provider refund evidence'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_online_order_refund_provider_result(uuid,text,text,text,numeric,text,timestamp with time zone,jsonb,text,text,text)',
    'EXECUTE'
  ),
  'interactive staff cannot forge Mercado Pago evidence'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.online_order_corrections', 'UPDATE'
  ),
  'staff must use correction commands instead of direct updates'
);

insert into public.tenants(id, shop_name, currency, timezone) values
  ('9e210000-0000-4000-8000-000000000001', 'Online Correction Tenant', 'CLP', 'America/Santiago'),
  ('9e210000-0000-4000-8000-000000000002', 'Online Correction Other', 'CLP', 'America/Santiago');

select lives_ok(
  $$
    insert into public.online_orders(
      id, tenant_id, order_number, customer_email, customer_name,
      subtotal, total, status, payment_status, payment_method
    ) values
      ('9e210000-0000-4000-8000-000000000081',
       '9e210000-0000-4000-8000-000000000001', 'WEB-26-00001',
       'one@example.invalid', 'Tenant One', 1, 1, 'pending', 'pending',
       'mercadopago'),
      ('9e210000-0000-4000-8000-000000000082',
       '9e210000-0000-4000-8000-000000000002', 'WEB-26-00001',
       'two@example.invalid', 'Tenant Two', 1, 1, 'pending', 'pending',
       'mercadopago')
  $$,
  'order numbers are unique per tenant instead of globally'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '9e210000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
    'online-correction@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9e210000-0000-4000-8000-000000000001'),
    now(), now()
  ),
  (
    '9e210000-0000-4000-8000-000000000098', 'authenticated', 'authenticated',
    'online-correction-other@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9e210000-0000-4000-8000-000000000002'),
    now(), now()
  ),
  (
    '9e210000-0000-4000-8000-000000000097', 'authenticated', 'authenticated',
    'online-correction-cashier@example.invalid', '', now(), '{}',
    jsonb_build_object('tenant_id', '9e210000-0000-4000-8000-000000000001'),
    now(), now()
  );

delete from public.user_profiles
where user_id in (
    '9e210000-0000-4000-8000-000000000099',
    '9e210000-0000-4000-8000-000000000098',
    '9e210000-0000-4000-8000-000000000097'
);
insert into public.user_profiles(
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
  (
    '9e210000-0000-4000-8000-000000000099',
    '9e210000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true
  ),
  (
    '9e210000-0000-4000-8000-000000000098',
    '9e210000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true
  ),
  (
    '9e210000-0000-4000-8000-000000000097',
    '9e210000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true
  );

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e210000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9e210000-0000-4000-8000-000000000099',
  true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity,
  min_stock_level, max_stock_level, is_active
) values
  (
    '9e210000-0000-4000-8000-000000000010',
    '9e210000-0000-4000-8000-000000000001',
    'Pastillas de freno', 'CORRECTION-PRODUCT', 1190, 500, 19,
    'product', false, 'inventory', true, 10, 10, 0, 100, true
  ),
  (
    '9e210000-0000-4000-8000-000000000011',
    '9e210000-0000-4000-8000-000000000001',
    'Instalacion', 'CORRECTION-SERVICE', 2380, 0, 19,
    'service', true, 'expense', false, 0, 0, 0, 0, true
  );

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_name, status,
  subtotal, net_amount, iva_amount, total, balance, tax_treatment, items
) values (
  '9e210000-0000-4000-8000-000000000020',
  '9e210000-0000-4000-8000-000000000001',
  'FV-CORRECTION-001', 'Cliente Correccion', 'draft',
  3570, 3000, 570, 3570, 3570, 'tax_included',
  jsonb_build_array(
    jsonb_build_object(
      'line_id', 'correction-product-line',
      'product_id', '9e210000-0000-4000-8000-000000000010',
      'product_name', 'Pastillas de freno',
      'product_sku', 'CORRECTION-PRODUCT',
      'quantity', 1, 'unit_price', 1190, 'price', 1190, 'cost', 500,
      'is_service', false, 'product_type', 'product',
      'purchase_treatment', 'inventory'
    ),
    jsonb_build_object(
      'line_id', 'correction-service-line',
      'product_id', '9e210000-0000-4000-8000-000000000011',
      'product_name', 'Instalacion',
      'product_sku', 'CORRECTION-SERVICE',
      'quantity', 1, 'unit_price', 2380, 'price', 2380, 'cost', 0,
      'is_service', true, 'product_type', 'service',
      'purchase_treatment', 'expense'
    )
  )
);
update public.sales_invoices set status = 'confirmed'
where id = '9e210000-0000-4000-8000-000000000020';

create temp table correction_fixture_ids(
  name text primary key,
  id uuid not null
) on commit drop;
insert into correction_fixture_ids(name, id)
select 'payment_method', id
from public.payment_methods
where tenant_id = '9e210000-0000-4000-8000-000000000001'
  and is_active is true
order by created_at, id limit 1;

insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, idempotency_key,
  amount, tax_treatment, net_amount, iva_amount, date, reference
) values (
  '9e210000-0000-4000-8000-000000000021',
  '9e210000-0000-4000-8000-000000000001',
  '9e210000-0000-4000-8000-000000000020',
  (select id from correction_fixture_ids where name = 'payment_method'),
  'correction-original-payment', 3570, 'tax_included', 3000, 570, now(),
  'MP-CORRECTION-PAYMENT'
);
select public.recalculate_sales_invoice_settlement(
  '9e210000-0000-4000-8000-000000000020'
);

insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, tax_amount, total, status, payment_status, payment_method,
  payment_reference, paid_at, sales_invoice_id
) values (
  '9e210000-0000-4000-8000-000000000030',
  '9e210000-0000-4000-8000-000000000001',
  'WEB-CORRECTION-001', 'customer@example.invalid', 'Cliente Correccion',
  3000, 570, 3570, 'delivered', 'paid', 'mercadopago',
  'MP-CORRECTION-PAYMENT', now(),
  '9e210000-0000-4000-8000-000000000020'
);
insert into public.online_order_items(
  id, tenant_id, order_id, product_id, product_name, product_sku,
  quantity, unit_price, subtotal, unit_cost, tax_rate, is_service,
  purchase_treatment, product_type
) values
  (
    '9e210000-0000-4000-8000-000000000031',
    '9e210000-0000-4000-8000-000000000001',
    '9e210000-0000-4000-8000-000000000030',
    '9e210000-0000-4000-8000-000000000010',
    'Pastillas de freno', 'CORRECTION-PRODUCT', 1, 1190, 1190, 500, 19,
    false, 'inventory', 'product'
  ),
  (
    '9e210000-0000-4000-8000-000000000032',
    '9e210000-0000-4000-8000-000000000001',
    '9e210000-0000-4000-8000-000000000030',
    '9e210000-0000-4000-8000-000000000011',
    'Instalacion', 'CORRECTION-SERVICE', 1, 2380, 2380, 0, 19,
    true, 'expense', 'service'
  );

insert into public.sales_return_control_settings(
  tenant_id, control_mode, activated_at, activated_by
) values (
  '9e210000-0000-4000-8000-000000000001', 'enforce', now(),
  '9e210000-0000-4000-8000-000000000099'
) on conflict (tenant_id) do update set control_mode = 'enforce';
insert into public.sales_credit_note_control_settings(
  tenant_id, control_mode, activated_at, activated_by
) values (
  '9e210000-0000-4000-8000-000000000001', 'enforce', now(),
  '9e210000-0000-4000-8000-000000000099'
) on conflict (tenant_id) do update set control_mode = 'enforce';
insert into public.sales_customer_refund_control_settings(
  tenant_id, control_mode, activated_at, activated_by
) values (
  '9e210000-0000-4000-8000-000000000001', 'enforce', now(),
  '9e210000-0000-4000-8000-000000000099'
) on conflict (tenant_id) do update set control_mode = 'enforce';

select is(
  jsonb_array_length(
    public.get_online_order_correction_preview(
      '9e210000-0000-4000-8000-000000000030'
    )->'lines'
  ),
  2,
  'preview uses the exact remaining ERP invoice lines'
);
select ok(
  (public.get_online_order_correction_preview(
    '9e210000-0000-4000-8000-000000000030'
  )->>'controls_ready')::boolean,
  'preview exposes correction control readiness'
);

create temp table correction_request on commit drop as
select public.request_online_order_correction(
  '9e210000-0000-4000-8000-000000000030',
  0,
  jsonb_build_array(
    jsonb_build_object('line_index', 0, 'quantity', 1, 'disposition', 'restock'),
    jsonb_build_object('line_index', 1, 'quantity', 1, 'disposition', 'financial_only')
  ),
  'Cliente devolvio producto y servicio',
  'online-correction-request-001', 'return'
) payload;

select is(
  (select (payload->>'requested_amount')::numeric from correction_request),
  3570::numeric,
  'request amount is derived from the immutable invoice allocation'
);
select is(
  (select payload->>'provider_state' from correction_request),
  'pending',
  'request does not claim that provider money already moved'
);
select is(
  (select count(*)::integer from public.online_order_correction_events
   where event_type = 'requested'),
  1,
  'request appends one immutable audit event'
);
select ok(
  (public.request_online_order_correction(
    '9e210000-0000-4000-8000-000000000030', 0,
    '[{"line_index":1,"quantity":1,"disposition":"financial_only"},
      {"line_index":0,"quantity":1,"disposition":"restock"}]'::jsonb,
    'Cliente devolvio producto y servicio', 'online-correction-request-001',
    'return'
  )->>'replay')::boolean,
  'identical request replay returns the original receipt independent of line order'
);
select throws_ok(
  $$
    select public.request_online_order_correction(
      '9e210000-0000-4000-8000-000000000030', 0,
      '[{"line_index":0,"quantity":1,"disposition":"restock"}]'::jsonb,
      'Different immutable request', 'online-correction-request-001', 'return'
    )
  $$,
  '23000',
  'Correction operation key was reused with different immutable inputs',
  'operation-key collision cannot silently replay a different correction'
);
select is(
  (select count(*)::integer from public.online_order_corrections),
  1,
  'request replay does not create another correction'
);
select is(
  (public.authorize_online_order_refund_execution(
    (select (payload->>'id')::uuid from correction_request)
  )->>'authorized'),
  'true',
  'strict preflight proves controls, money, invoice and stock feasibility'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e210000-0000-4000-8000-000000000097',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '9e210000-0000-4000-8000-000000000097', true);
select throws_ok(
  format(
    'select public.authorize_online_order_refund_execution(%L::uuid)',
    (select payload->>'id' from correction_request)
  ),
  '42501',
  'Correction not found or execution not authorized',
  'cashier read access never authorizes irreversible provider money movement'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e210000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '9e210000-0000-4000-8000-000000000098', true);
select throws_ok(
  $$
    select public.get_online_order_correction_preview(
      '9e210000-0000-4000-8000-000000000030'
    )
  $$,
  '42501',
  'Online order not found or access denied',
  'another tenant cannot inspect correction lines'
);

select set_config(
  'request.jwt.claims', jsonb_build_object('role', 'service_role')::text, true
);
select set_config('request.jwt.claim.sub', '', true);

select is(
  (public.record_online_order_refund_provider_result(
    (select (payload->>'id')::uuid from correction_request),
    'unknown', null, null, null, 'CLP', null, '{}'::jsonb,
    'provider:online-correction:unknown',
    'provider_outcome_unknown', 'No acknowledgement'
  )->>'provider_state'),
  'unknown',
  'lost provider acknowledgement remains explicit and durable'
);
select is(
  (select count(*)::integer from public.sales_returns),
  0,
  'unknown provider outcome applies no stock effect'
);
select is(
  (select count(*)::integer from public.online_order_correction_events
   where event_type = 'provider_unknown'),
  1,
  'unknown provider outcome has an append-only event'
);

create temp table provider_success on commit drop as
select public.record_online_order_refund_provider_result(
  (select (payload->>'id')::uuid from correction_request),
  'succeeded', 'MP-REFUND-CORRECTION-001', 'approved', 3570, 'CLP', now(),
  jsonb_build_object(
    'id', 'MP-REFUND-CORRECTION-001',
    'payment_id', 'MP-CORRECTION-PAYMENT',
    'status', 'approved',
    'amount', 3570,
    'date_created', now(),
    'payer', jsonb_build_object('email', 'must-not-persist@example.invalid'),
    'access_token', 'must-not-persist'
  ),
  'provider:online-correction:succeeded', null, null
) payload;

select is(
  (select payload->>'provider_state' from provider_success),
  'succeeded',
  'approved provider evidence is preserved independently'
);
select is(
  (select payload->>'processing_state' from provider_success),
  'ready_to_apply',
  'approved refund waits for the separate internal transaction'
);
select ok(
  not ((select payload->'provider_evidence' from provider_success) ? 'payer')
  and not ((select payload->'provider_evidence' from provider_success) ? 'access_token'),
  'provider evidence strips payer data and secrets'
);
select throws_ok(
  format(
    'select public.record_online_order_refund_provider_result(%L::uuid,%L,%L,%L,null,%L,null,%L::jsonb,%L,%L,%L)',
    (select payload->>'id' from correction_request),
    'failed', null, 'rejected', 'CLP', '{}',
    'provider:online-correction:late-failure',
    'late_failure', 'Late contradictory response'
  ),
  '23000',
  'Provider refund success is terminal',
  'a late provider failure cannot erase durable refund success'
);
select is(
  (select provider_state from public.online_order_corrections
    where id = (select (payload->>'id')::uuid from correction_request)),
  'succeeded',
  'provider success remains monotonic after a contradictory late result'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e210000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config('request.jwt.claim.sub', '9e210000-0000-4000-8000-000000000099', true);

create temp table applied_correction on commit drop as
select public.apply_online_order_correction(
  (select (payload->>'id')::uuid from correction_request),
  'apply:online-correction-001'
) payload;

select is(
  (select payload->>'processing_state' from applied_correction),
  'applied',
  'verified correction applies successfully'
);
select is(
  (select stock_quantity from public.products
   where id = '9e210000-0000-4000-8000-000000000010'),
  10,
  'physical product is restored to available stock'
);
select is(
  (select inventory_qty from public.products
   where id = '9e210000-0000-4000-8000-000000000010'),
  10,
  'dual stock columns remain synchronized'
);
select is(
  (select count(*)::integer from public.sales_returns),
  1,
  'one physical return header is created'
);
select is(
  (select count(*)::integer from public.sales_return_lines),
  1,
  'service line never becomes a physical stock return'
);
select is(
  (select total_amount from public.sales_credit_notes),
  3570::numeric,
  'one financial credit covers product and service amounts'
);
select is(
  (select amount from public.sales_customer_refunds),
  3570::numeric,
  'refund accounting matches verified provider money exactly'
);
select is(
  (select payment_status from public.online_orders
   where id = '9e210000-0000-4000-8000-000000000030'),
  'refunded',
  'full correction changes only the payment projection to refunded'
);
select is(
  (select status from public.online_orders
   where id = '9e210000-0000-4000-8000-000000000030'),
  'delivered',
  'financial correction does not rewrite the logistical history'
);
select is(
  (select refund_amount from public.online_orders
   where id = '9e210000-0000-4000-8000-000000000030'),
  3570::numeric,
  'order refund projection reconciles to the applied correction'
);
select ok(
  (public.apply_online_order_correction(
    (select (payload->>'id')::uuid from correction_request),
    'apply:online-correction-replay'
  )->>'replay')::boolean,
  'internal correction replay returns the existing receipt'
);
select is(
  (select count(*)::integer from public.sales_returns),
  1,
  'internal replay creates no duplicate return'
);
select is(
  (select count(*)::integer from public.sales_credit_notes),
  1,
  'internal replay creates no duplicate credit note'
);
select is(
  (select count(*)::integer from public.sales_customer_refunds),
  1,
  'internal replay creates no duplicate refund accounting record'
);
select is(
  (select count(*)::integer from public.online_order_correction_events
   where event_type = 'apply_succeeded'),
  1,
  'internal application appends one success event'
);

insert into public.online_orders(
  id, tenant_id, order_number, customer_email, customer_name,
  subtotal, total, status, payment_status, payment_method,
  sales_invoice_id, refund_amount, refunded_at
) values (
  '9e210000-0000-4000-8000-000000000040',
  '9e210000-0000-4000-8000-000000000001',
  'WEB-26-PARTIAL-EMAIL', 'partial-refund@example.invalid',
  'Cliente Reembolso Parcial', 5000, 5000, 'delivered', 'paid', 'transfer',
  '9e210000-0000-4000-8000-000000000020', 1000, now()
);
insert into public.online_order_corrections(
  id, tenant_id, order_id, sales_invoice_id, operation_key,
  expected_order_version, request_lines, reason, requested_amount,
  payment_method_id, provider, correction_intent,
  provider_idempotency_key, provider_state, processing_state,
  provider_refund_id, provider_refund_status, provider_refund_amount,
  provider_refunded_at, provider_evidence,
  sales_credit_note_id, sales_customer_refund_id,
  requested_by, applied_by, applied_at
) select
  '9e210000-0000-4000-8000-000000000041',
  '9e210000-0000-4000-8000-000000000001',
  '9e210000-0000-4000-8000-000000000040',
  '9e210000-0000-4000-8000-000000000020',
  'partial-email-correction-001', 0,
  '[{"line_index":0,"credited_quantity":1,"disposition":"financial_only","net_amount":840,"tax_amount":160,"is_service":false}]'::jsonb,
  'Fixture de email parcial aplicado', 1000,
  (select payment_method_id from public.sales_payments
    where invoice_id = '9e210000-0000-4000-8000-000000000020' limit 1),
  'manual', 'return', 'partial-email-provider-key-001',
  'succeeded', 'applied', 'MANUAL-PARTIAL-EMAIL-001', 'verified', 1000,
  now(), '{"reference":"MANUAL-PARTIAL-EMAIL-001"}'::jsonb,
  (select sales_credit_note_id from public.online_order_corrections
    where id = (select (payload->>'id')::uuid from correction_request)),
  (select sales_customer_refund_id from public.online_order_corrections
    where id = (select (payload->>'id')::uuid from correction_request)),
  '9e210000-0000-4000-8000-000000000099',
  '9e210000-0000-4000-8000-000000000099', now();

create temp table partial_refund_email on commit drop as
select public.enqueue_partial_online_order_refund_email(
  '9e210000-0000-4000-8000-000000000041'
) id;
select ok(
  (select id is not null from partial_refund_email),
  'partial applied correction enqueues a refund_completed email receipt'
);
select is(
  (select concat_ws('|', message_kind,
      render_payload->'order'->>'partialRefund',
      render_payload->'order'->>'refundedAmount',
      render_payload->'order'->>'cumulativeRefundedAmount')
   from public.transactional_email_outbox
   where id = (select id from partial_refund_email)),
  'refund_completed|true|1000.00|1000.00',
  'partial refund email states the correction and cumulative amounts honestly'
);
select public.enqueue_partial_online_order_refund_email(
  '9e210000-0000-4000-8000-000000000041'
);
select is(
  (select count(*)::integer from public.transactional_email_outbox
   where source_event_key =
     'online_order_correction:9e210000-0000-4000-8000-000000000041'),
  1,
  'partial refund email replay is idempotent'
);
select throws_ok(
  format(
    'select public.void_sales_customer_refund(%L::uuid,%L,%L)',
    (select sales_customer_refund_id from public.online_order_corrections
      where id = (select (payload->>'id')::uuid from correction_request)),
    'Out-of-band void attempt', 'online-correction-forbidden-void'
  ),
  '23514',
  'Online-order correction artifacts require a canonical compensation workflow and cannot be voided directly',
  'linked refund accounting cannot be voided outside the canonical correction saga'
);
select is(
  (select status from public.sales_customer_refunds),
  'posted',
  'blocked out-of-band void leaves the applied refund evidence intact'
);
select throws_ok(
  $$
    update public.online_order_correction_events set payload = '{}'::jsonb
  $$,
  '23514',
  'Online order correction events are append-only',
  'correction audit events cannot be rewritten'
);
select throws_ok(
  $$
    update public.online_order_corrections set last_error_message = 'rewrite'
  $$,
  '42501',
  'Online order corrections are command-owned records',
  'correction projection cannot be directly mutated'
);

select * from finish();
rollback;
