begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(49);

select has_table(
  'public',
  'sales_channel_payment_processing',
  'current provider-payment processing projection exists'
);
select has_table(
  'public',
  'sales_channel_payment_processing_attempts',
  'append-only provider-payment processing attempts exist'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.record_mercadopago_payment_observation(uuid,uuid,text,text,numeric,text,timestamp with time zone,jsonb)',
    'EXECUTE'
  ),
  'service role can durably record a provider observation'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.process_mercadopago_payment_observation(bigint)',
    'EXECUTE'
  ),
  'staff can retry a tenant-scoped processing observation'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.apply_mercadopago_payment_event(uuid,uuid,text,text,numeric,text,timestamp with time zone,jsonb)',
    'EXECUTE'
  ),
  'unsafe single-transaction provider RPC is no longer callable by service role'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.sales_channel_payment_processing',
    'UPDATE'
  ),
  'worker must use the canonical processing RPC instead of mutating state'
);

insert into public.tenants (id, shop_name, currency, timezone)
values
  (
    '9e190000-0000-4000-8000-000000000001',
    'Mercado Pago Two Phase Test',
    'CLP',
    'America/Santiago'
  ),
  (
    '9e190000-0000-4000-8000-000000000002',
    'Foreign Mercado Pago Test',
    'CLP',
    'America/Santiago'
  );

-- Tenant initialization helpers touch transaction-local auth context while
-- seeding. Synthetic stock setup must run with no employee actor.
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  tax_rate,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values (
  '9e190000-0000-4000-8000-000000000010',
  '9e190000-0000-4000-8000-000000000001',
  'Ultima unidad prueba MP',
  'MP-TWO-PHASE-001',
  1190,
  500,
  'product',
  false,
  19,
  true,
  2,
  2,
  0,
  100,
  true,
  true,
  true
);

select set_config('request.jwt.claim.role', '', true);

create temp table mp_two_phase_ids (
  name text primary key,
  order_id uuid,
  event_id bigint
) on commit drop;

insert into mp_two_phase_ids (name, order_id)
select 'first_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e190000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '9e190000-0000-4000-8000-000000000101',
    'customer_email', 'first@example.invalid',
    'customer_name', 'Primer comprador',
    'customer_phone', '+56911111111',
    'customer_address', 'Direccion sintetica 1',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e190000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

insert into mp_two_phase_ids (name, order_id)
select 'second_order', public.create_public_online_order(
  jsonb_build_object(
    'tenant_id', '9e190000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', '9e190000-0000-4000-8000-000000000102',
    'customer_email', 'second@example.invalid',
    'customer_name', 'Segundo comprador',
    'customer_phone', '+56922222222',
    'customer_address', 'Direccion sintetica 2',
    'delivery_type', 'pickup',
    'payment_method', 'mercadopago'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', '9e190000-0000-4000-8000-000000000010',
    'quantity', 1
  ))
);

select is(
  (select count(*)::integer from public.online_orders
    where tenant_id = '9e190000-0000-4000-8000-000000000001'),
  2,
  'two checkouts commit the two available units without overselling'
);

update mp_two_phase_ids
set event_id = (
  public.record_mercadopago_payment_observation(
    order_id,
    '9e190000-0000-4000-8000-000000000001',
    'MP-TWO-PHASE-FIRST',
    'approved',
    1190,
    'CLP',
    '2026-07-18T19:00:00Z',
    jsonb_build_object(
      'operation_number', 'MP-TWO-PHASE-FIRST',
      'status_detail', 'accredited',
      'transaction_amount', 1190,
      'currency_id', 'CLP',
      'card_last_four_digits', '4242',
      'payer_email', 'must-not-persist@example.invalid',
      'access_token', 'must-not-persist'
    )
  )->>'event_id'
)::bigint
where name = 'first_order';

select is(
  (select payment_status from public.online_orders orders
    join mp_two_phase_ids ids on ids.order_id = orders.id
    where ids.name = 'first_order'),
  'pending',
  'phase 1 does not mutate order payment state or fire sale processing'
);
select is(
  (select sales_invoice_id from public.online_orders orders
    join mp_two_phase_ids ids on ids.order_id = orders.id
    where ids.name = 'first_order'),
  null::uuid,
  'phase 1 creates no invoice'
);
select is(
  (select stock_quantity from public.products
    where id = '9e190000-0000-4000-8000-000000000010'),
  2,
  'phase 1 creates no inventory effect'
);
select is(
  (select outcome from public.sales_channel_payment_events payment_event
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'first_order'),
  'payment_validated',
  'phase 1 records provider validation without claiming sale application'
);
select is(
  (select processing_state from public.sales_channel_payment_processing processing
    join mp_two_phase_ids ids on ids.event_id = processing.payment_event_id
    where ids.name = 'first_order'),
  'pending',
  'new provider observation is durably pending processing'
);
select ok(
  (select not (provider_payload ? 'payer_email')
      and not (provider_payload ? 'access_token')
    from public.sales_channel_payment_events payment_event
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'first_order'),
  'database allow-list strips PII and secrets even from service-role input'
);

select is(
  (
    public.record_mercadopago_payment_observation(
      (select order_id from mp_two_phase_ids where name = 'first_order'),
      '9e190000-0000-4000-8000-000000000001',
      'MP-TWO-PHASE-FIRST',
      'approved',
      1190,
      'CLP',
      '2026-07-18T19:00:00Z',
      '{}'::jsonb
    )->>'replay'
  ),
  'true',
  'lost phase-1 acknowledgement is recovered by the same durable event'
);
select is(
  (select count(*)::integer
    from public.sales_channel_payment_events
    where external_payment_id = 'MP-TWO-PHASE-FIRST'),
  1,
  'phase-1 replay creates no duplicate provider event'
);

select is(
  (
    public.process_mercadopago_payment_observation(
      (select event_id from mp_two_phase_ids where name = 'first_order')
    )->>'processing_state'
  ),
  'processed',
  'first approved payment completes phase 2'
);
select is(
  (select stock_quantity from public.products
    where id = '9e190000-0000-4000-8000-000000000010'),
  1,
  'first phase-2 processing consumes its committed unit exactly once'
);
select ok(
  exists (
    select 1
    from public.online_orders orders
    join mp_two_phase_ids ids on ids.order_id = orders.id
    join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
    join public.sales_payments payment on payment.invoice_id = invoice.id
    where ids.name = 'first_order'
      and orders.payment_status = 'paid'
      and invoice.status = 'paid'
      and payment.idempotency_key = 'mercadopago:MP-TWO-PHASE-FIRST'
      and payment.amount = 1190
      and payment.deleted_at is null
  ),
  'processed payment links paid order, settled invoice, and exact provider payment'
);

select is(
  (
    public.process_mercadopago_payment_observation(
      (select event_id from mp_two_phase_ids where name = 'first_order')
    )->>'replay'
  ),
  'true',
  'lost phase-2 acknowledgement replays without reposting effects'
);
select is(
  (select attempt_count from public.sales_channel_payment_processing processing
    join mp_two_phase_ids ids on ids.event_id = processing.payment_event_id
    where ids.name = 'first_order'),
  1,
  'successful phase-2 replay does not create another attempt'
);

-- Model the real late-provider exception: the second checkout originally held
-- a valid commitment, but its payment window elapsed before Mercado Pago sent
-- the approved observation. Once the commitment is terminal, another channel
-- may consume the remaining physical unit; payment truth must then survive as
-- action_required without inventing an invoice or negative stock.
update public.online_order_inventory_reservations reservation
   set reserved_at = clock_timestamp() - interval '2 minutes',
       expires_at = clock_timestamp() - interval '1 minute'
 where reservation.order_id = (
   select order_id from mp_two_phase_ids where name = 'second_order'
 )
   and reservation.state = 'active';

select is(
  public.expire_online_order_inventory_reservations(
    '9e190000-0000-4000-8000-000000000001',
    100
  ),
  1,
  'expired payment window terminalizes the second order commitment'
);

update public.products
   set stock_quantity = 0,
       inventory_qty = 0
 where id = '9e190000-0000-4000-8000-000000000010';

select is(
  (select state from public.online_order_inventory_reservations
    where order_id = (
      select order_id from mp_two_phase_ids where name = 'second_order'
    )),
  'expired',
  'late-payment setup retains explicit terminal reservation evidence'
);

update mp_two_phase_ids
set event_id = (
  public.record_mercadopago_payment_observation(
    order_id,
    '9e190000-0000-4000-8000-000000000001',
    'MP-TWO-PHASE-SECOND',
    'approved',
    1190,
    'CLP',
    statement_timestamp(),
    jsonb_build_object(
      'operation_number', 'MP-TWO-PHASE-SECOND',
      'status_detail', 'accredited',
      'payment_type_id', 'debit_card',
      'payment_method_id', 'debvisa',
      'authorization_code', 'MP-AUTH-TWO-PHASE',
      'date_approved', to_char(
        statement_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      ),
      'transaction_amount', 1190,
      'currency_id', 'CLP',
      'total_paid_amount', 1190,
      'card_last_four_digits', '4242',
      'mercadopago_payment_voucher', jsonb_build_object(
        'source', 'transaction_details.external_resource_url',
        'availability', 'available',
        'fiscal_validity', 'not_a_tax_document',
        'url', 'https://www.mercadopago.cl/activities/receipt?payment_id=MP-TWO-PHASE-SECOND'
      )
    )
  )->>'event_id'
)::bigint
where name = 'second_order';

select is(
  (
    public.process_mercadopago_payment_observation(
      (select event_id from mp_two_phase_ids where name = 'second_order')
    )->>'processing_state'
  ),
  'action_required',
  'second approved payment preserves an operational exception when stock is gone'
);
select is(
  (select payment_status from public.online_orders orders
    join mp_two_phase_ids ids on ids.order_id = orders.id
    where ids.name = 'second_order'),
  'paid',
  'provider-approved payment remains paid after derived stock processing fails'
);
select is(
  (select sales_invoice_id from public.online_orders orders
    join mp_two_phase_ids ids on ids.order_id = orders.id
    where ids.name = 'second_order'),
  null::uuid,
  'failed sale subtransaction leaves no phantom invoice'
);
select is(
  (select stock_quantity from public.products
    where id = '9e190000-0000-4000-8000-000000000010'),
  0,
  'failed sale subtransaction neither invents nor consumes stock'
);
select ok(
  exists (
    select 1
    from public.sales_channel_payment_events payment_event
    join public.sales_channel_payment_processing processing
      on processing.payment_event_id = payment_event.id
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'second_order'
      and payment_event.outcome = 'payment_validated'
      and processing.processing_state = 'action_required'
      and processing.attempt_count = 1
      and processing.last_error_code is not null
  ),
  'approved provider truth and sanitized action-required evidence both survive'
);
select is(
  (select count(*)::integer
    from public.sales_invoices invoice
    where invoice.reference like 'Pedido online #WEB-%'
      and invoice.customer_name = 'Segundo comprador'),
  0,
  'stock failure rolls back all invoice artifacts for the second order'
);

select is(
  (
    select payment_event.provider_payload
      ->'mercadopago_payment_voucher'->>'availability'
    from public.sales_channel_payment_events payment_event
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'second_order'
  ),
  'available',
  'sanitized provider evidence retains the safe non-fiscal receipt availability'
);

create temp table mp_action_required_non_fiscal_receipt on commit drop as
select public.record_online_order_official_document(
  p_tenant_id => '9e190000-0000-4000-8000-000000000001',
  p_order_id => (
    select order_id from mp_two_phase_ids where name = 'second_order'
  ),
  p_document_kind => 'mercadopago_payment_voucher',
  p_provider => 'mercadopago',
  p_provider_document_id => 'payment:MP-TWO-PHASE-SECOND',
  p_fiscal_validity => 'not_a_tax_document',
  p_amount => 1190,
  p_currency => 'CLP',
  p_issued_at => (
    select payment_event.provider_paid_at
    from public.sales_channel_payment_events payment_event
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'second_order'
  ),
  p_artifact_url => 'https://www.mercadopago.cl/activities/receipt?payment_id=MP-TWO-PHASE-SECOND',
  p_artifact_sha256 => encode(extensions.digest(convert_to(
    'https://www.mercadopago.cl/activities/receipt?payment_id=MP-TWO-PHASE-SECOND',
    'UTF8'
  ), 'sha256'), 'hex'),
  p_status => 'approved',
  p_source_event_key => 'mercadopago_payment_voucher:MP-TWO-PHASE-SECOND',
  p_payment_operation_id => 'MP-TWO-PHASE-SECOND',
  p_metadata => jsonb_build_object(
    'source', 'transaction_details.external_resource_url'
  )
) id;

select ok(
  (select id is not null from mp_action_required_non_fiscal_receipt),
  'validated paid action-required flow records its provider payment receipt'
);
select ok(
  (
    select document.document_kind = 'mercadopago_payment_voucher'
      and document.fiscal_validity = 'not_a_tax_document'
      and document.artifact_hash_scope = 'reference_url'
      and document.sii_emission_model_event_id is null
      and document.fiscal_legend is null
    from public.online_order_official_documents document
    where document.id = (select id from mp_action_required_non_fiscal_receipt)
  ),
  'provider receipt is immutable but carries no invented SII or boleta evidence'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox outbox
    where outbox.order_id = (
      select order_id from mp_two_phase_ids where name = 'second_order'
    )
      and outbox.message_kind = 'mercadopago_payment_voucher_available'
      and outbox.render_payload->'document'->>'taxStatus' = 'not_a_tax_document'
      and outbox.attachment_manifest = '[]'::jsonb
  ),
  1,
  'ledger trigger enqueues one explicitly non-fiscal receipt email without an invented attachment'
);
select is(
  public.record_online_order_official_document(
    p_tenant_id => '9e190000-0000-4000-8000-000000000001',
    p_order_id => (
      select order_id from mp_two_phase_ids where name = 'second_order'
    ),
    p_document_kind => 'mercadopago_payment_voucher',
    p_provider => 'mercadopago',
    p_provider_document_id => 'payment:MP-TWO-PHASE-SECOND',
    p_fiscal_validity => 'not_a_tax_document',
    p_amount => 1190,
    p_currency => 'CLP',
    p_issued_at => (
      select payment_event.provider_paid_at
      from public.sales_channel_payment_events payment_event
      join mp_two_phase_ids ids on ids.event_id = payment_event.id
      where ids.name = 'second_order'
    ),
    p_artifact_url => 'https://www.mercadopago.cl/activities/receipt?payment_id=MP-TWO-PHASE-SECOND',
    p_artifact_sha256 => encode(extensions.digest(convert_to(
      'https://www.mercadopago.cl/activities/receipt?payment_id=MP-TWO-PHASE-SECOND',
      'UTF8'
    ), 'sha256'), 'hex'),
    p_status => 'approved',
    p_source_event_key => 'mercadopago_payment_voucher:MP-TWO-PHASE-SECOND',
    p_payment_operation_id => 'MP-TWO-PHASE-SECOND'
  ),
  (select id from mp_action_required_non_fiscal_receipt),
  'receipt replay returns the same ledger row and does not duplicate its email'
);
select throws_ok(
  format(
    $sql$
      select public.record_online_order_official_document(
        p_tenant_id => %L::uuid,
        p_order_id => %L::uuid,
        p_document_kind => 'mercadopago_payment_voucher',
        p_provider => 'mercadopago',
        p_provider_document_id => 'payment:MP-TWO-PHASE-SECOND',
        p_fiscal_validity => 'voucher_valid_as_boleta',
        p_amount => 1190,
        p_currency => 'CLP',
        p_issued_at => statement_timestamp(),
        p_artifact_url => 'https://www.mercadopago.cl/activities/receipt',
        p_artifact_sha256 => repeat('a', 64),
        p_status => 'approved',
        p_source_event_key => 'mercadopago_payment_voucher:MP-TWO-PHASE-SECOND',
        p_payment_operation_id => 'MP-TWO-PHASE-SECOND'
      )
    $sql$,
    '9e190000-0000-4000-8000-000000000001',
    (select order_id from mp_two_phase_ids where name = 'second_order')
  ),
  '23514',
  'Mercado Pago payment voucher cannot claim fiscal validity',
  'non-fiscal receipt recorder cannot be relabelled as a boleta'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox outbox
    where outbox.order_id = (
      select order_id from mp_two_phase_ids where name = 'second_order'
    )
      and outbox.message_kind = 'mercadopago_payment_voucher_available'
  ),
  1,
  'receipt recorder replay leaves one idempotent customer email'
);

-- Payment evidence and sale fulfillment are separate truths. A complete
-- Mercado Pago voucher can be recorded and delivered while the paid order is
-- action_required, but a Chilean DTE still cannot exist without its invoice.
select public.record_tenant_sii_boleta_emission_model(
  p_tenant_id => '9e190000-0000-4000-8000-000000000001',
  p_model_code => 'no_emito_boleta_pago_electronico',
  p_merchant_tax_id => '76.211.240-K',
  p_merchant_legal_name => 'Mercado Pago Two Phase Test SpA',
  p_merchant_address => 'Av. Prueba 1900, Santiago',
  p_declared_at => statement_timestamp() - interval '2 minutes',
  p_effective_from => statement_timestamp() - interval '2 minutes',
  p_verified_at => statement_timestamp() - interval '1 minute',
  p_verification_source => 'sii_portal_declaration_receipt',
  p_verification_reference => 'SII-MP-TWO-PHASE-001',
  p_evidence_artifact_url => 'https://evidence.example.invalid/sii/mp-two-phase.pdf',
  p_evidence_artifact_sha256 => repeat('1', 64),
  p_source_event_key => 'sii-mp-two-phase-model-001'
);

create temp table mp_action_required_voucher on commit drop as
select public.record_online_order_official_document(
  p_tenant_id => '9e190000-0000-4000-8000-000000000001',
  p_order_id => (
    select order_id from mp_two_phase_ids where name = 'second_order'
  ),
  p_document_kind => 'payment_voucher',
  p_provider => 'mercadopago',
  p_provider_document_id => 'MP-TWO-PHASE-VOUCHER-SECOND',
  p_fiscal_validity => 'voucher_valid_as_boleta',
  p_amount => 1190,
  p_currency => 'CLP',
  p_issued_at => (
    select payment_event.provider_paid_at
    from public.sales_channel_payment_events payment_event
    join mp_two_phase_ids ids on ids.event_id = payment_event.id
    where ids.name = 'second_order'
  ),
  p_artifact_url => 'https://documents.example.invalid/mp/two-phase-second.pdf',
  p_artifact_sha256 => repeat('a', 64),
  p_status => 'approved',
  p_source_event_key => 'mp-two-phase-voucher-second',
  p_payment_operation_id => 'MP-TWO-PHASE-SECOND',
  p_metadata => jsonb_build_object('source', 'mercadopago_webhook'),
  p_voucher_fiscal_evidence => jsonb_build_object(
    'merchant_tax_id', '76.211.240-K',
    'merchant_legal_name', 'Mercado Pago Two Phase Test SpA',
    'merchant_address', 'Av. Prueba 1900, Santiago',
    'taxable_net_amount', 1000,
    'exempt_amount', 0,
    'vat_rate_percent', 19,
    'vat_amount', 190,
    'other_amount', 0,
    'terminal_id', 'MP-TERMINAL-TWO-PHASE',
    'authorization_code', 'MP-AUTH-TWO-PHASE',
    'fiscal_legend', 'Válido como Boleta'
  )
) id;

select ok(
  (select id is not null from mp_action_required_voucher),
  'validated payment can record its official voucher before sale recovery'
);
select ok(
  (
    select document.sales_invoice_id is null
      and document.payment_operation_id = 'MP-TWO-PHASE-SECOND'
      and document.voucher_evidence_fingerprint ~ '^[0-9a-f]{64}$'
    from public.online_order_official_documents document
    where document.id = (select id from mp_action_required_voucher)
  ),
  'action-required voucher preserves provider and fiscal evidence without inventing an invoice'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox outbox
    where outbox.order_id = (
      select order_id from mp_two_phase_ids where name = 'second_order'
    )
      and outbox.message_kind = 'payment_voucher_available'
  ),
  1,
  'complete action-required voucher enqueues its idempotent customer email'
);
select throws_ok(
  format(
    $sql$
      select public.record_online_order_official_document(
        p_tenant_id => %L::uuid,
        p_order_id => %L::uuid,
        p_document_kind => 'tax_document',
        p_provider => 'sii_provider',
        p_provider_document_id => 'DTE-MUST-NOT-EXIST',
        p_fiscal_validity => 'official_chilean_dte',
        p_amount => 1190,
        p_currency => 'CLP',
        p_issued_at => clock_timestamp(),
        p_artifact_url => 'https://documents.example.invalid/dte/must-not-exist.pdf',
        p_artifact_sha256 => repeat('b', 64),
        p_status => 'accepted',
        p_source_event_key => 'dte-must-not-exist',
        p_document_type => 'boleta_electronica',
        p_folio => '190001'
      )
    $sql$,
    '9e190000-0000-4000-8000-000000000001',
    (select order_id from mp_two_phase_ids where name = 'second_order')
  ),
  '23514',
  'Official DTE evidence requires the linked sales invoice',
  'action-required payment cannot invent a Chilean DTE before invoice recovery'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9e190000-0000-4000-8000-000000000098',
  'authenticated',
  'authenticated',
  'mechanic-mp-staff@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '9e190000-0000-4000-8000-000000000001'),
  now(),
  now()
);

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Seed the least-privilege actor explicitly and deterministically.
delete from public.user_profiles
where user_id = '9e190000-0000-4000-8000-000000000098';

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values (
  '9e190000-0000-4000-8000-000000000098',
  '9e190000-0000-4000-8000-000000000001',
  'mechanic',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claim.sub',
  '9e190000-0000-4000-8000-000000000098',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e190000-0000-4000-8000-000000000098',
    'role', 'authenticated'
  )::text,
  true
);

select throws_ok(
  format(
    'select public.process_mercadopago_payment_observation(%s)',
    (select event_id from mp_two_phase_ids where name = 'second_order')
  ),
  '42501',
  'Payment observation not found or access denied',
  'mechanic without invoice permission cannot execute sale recovery'
);

set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.sales_channel_payment_processing_attempts
    where tenant_id = '9e190000-0000-4000-8000-000000000001'
  ),
  0,
  'mechanic without financial permission cannot read processing diagnostics'
);
reset role;

update public.user_profiles
set permissions = jsonb_build_object('create_invoices', true)
where user_id = '9e190000-0000-4000-8000-000000000098';

select is(
  (
    public.process_mercadopago_payment_observation(
      (select event_id from mp_two_phase_ids where name = 'first_order')
    )->>'replay'
  ),
  'true',
  'explicit create-invoices permission authorizes a replay-safe recovery command'
);

set local role authenticated;
select cmp_ok(
  (
    select count(*)::integer
    from public.sales_channel_payment_processing_attempts
    where tenant_id = '9e190000-0000-4000-8000-000000000001'
  ),
  '>=',
  2,
  'explicit invoice permission exposes tenant-scoped processing diagnostics'
);
reset role;

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);

update public.products
set inventory_qty = 1,
    stock_quantity = 1
where id = '9e190000-0000-4000-8000-000000000010';

select is(
  (
    public.process_mercadopago_payment_observation(
      (select event_id from mp_two_phase_ids where name = 'second_order')
    )->>'processing_state'
  ),
  'processed',
  'staff/worker retry completes after the stock inconsistency is corrected'
);
select is(
  (select attempt_count from public.sales_channel_payment_processing processing
    join mp_two_phase_ids ids on ids.event_id = processing.payment_event_id
    where ids.name = 'second_order'),
  2,
  'retry preserves both failed and successful attempt milestones'
);
select is(
  (select count(*)::integer
    from public.sales_channel_payment_processing_attempts attempt
    join mp_two_phase_ids ids on ids.event_id = attempt.payment_event_id
    where ids.name = 'second_order'),
  2,
  'attempt ledger contains one action-required and one successful attempt'
);
select is(
  (select stock_quantity from public.products
    where id = '9e190000-0000-4000-8000-000000000010'),
  0,
  'successful retry consumes the restored unit once'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9e190000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'foreign-mp-staff@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '9e190000-0000-4000-8000-000000000002'),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '9e190000-0000-4000-8000-000000000099';

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values (
  '9e190000-0000-4000-8000-000000000099',
  '9e190000-0000-4000-8000-000000000002',
  'admin',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claim.sub',
  '9e190000-0000-4000-8000-000000000099',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e190000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);

select throws_ok(
  format(
    'select public.process_mercadopago_payment_observation(%s)',
    (select event_id from mp_two_phase_ids where name = 'second_order')
  ),
  '42501',
  'Payment observation not found or access denied',
  'staff cannot retry another tenant payment observation'
);

select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);

select is(
  (
    select count(*)::integer
    from public.sales_channel_payment_processing_attempts attempt
    join mp_two_phase_ids ids on ids.event_id = attempt.payment_event_id
    where ids.name = 'second_order'
      and attempt.result_state = 'action_required'
  ),
  1,
  'append-only attempt history retains the original stock-processing failure'
);

select * from finish();
rollback;
