begin;

select plan(42);

select has_table(
  'public',
  'tenant_sii_boleta_emission_model_events',
  'verified tenant SII boleta emission-model ledger exists'
);
select is(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.tenant_sii_boleta_emission_model_events'::regclass
  ),
  true,
  'SII emission-model ledger has RLS enabled'
);
select is(
  has_table_privilege(
    'service_role',
    'public.tenant_sii_boleta_emission_model_events',
    'INSERT'
  ),
  false,
  'service role cannot bypass the verified configuration recorder'
);
select is(
  has_function_privilege(
    'service_role',
    'public.record_tenant_sii_boleta_emission_model(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,text,text,text,text,uuid)',
    'EXECUTE'
  ),
  true,
  'service role can record verified SII declaration evidence'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.record_tenant_sii_boleta_emission_model(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,text,text,text,text,uuid)',
    'EXECUTE'
  ),
  false,
  'authenticated callers cannot assert the tenant SII model'
);
select is(
  has_function_privilege(
    'service_role',
    'public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)',
    'EXECUTE'
  ),
  true,
  'service role can execute the hardened official-document recorder'
);
select is(
  public.normalize_chilean_rut('76.211.240-k'),
  '76211240-K',
  'merchant RUT is normalized canonically'
);
select ok(
  public.is_valid_chilean_rut('76.211.240-K'),
  'valid Chilean merchant RUT passes modulo-11 verification'
);
select ok(
  not public.is_valid_chilean_rut('76.211.240-1'),
  'invalid Chilean merchant RUT is rejected'
);

insert into public.tenants (
  id,
  shop_name,
  custom_domain,
  owner_email,
  currency,
  timezone
) values
  (
    '9e180000-0000-4000-8000-000000000001',
    'Voucher Fiscal Test Shop',
    'voucher-fiscal.example.invalid',
    'owner@example.invalid',
    'CLP',
    'America/Santiago'
  ),
  (
    '9e180000-0000-4000-8000-000000000002',
    'Foreign Voucher Fiscal Shop',
    'foreign-voucher-fiscal.example.invalid',
    'foreign@example.invalid',
    'CLP',
    'America/Santiago'
  );

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '9e180000-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'voucher-fiscal-staff@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '9e180000-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '9e180000-0000-4000-8000-000000000092',
    'authenticated',
    'authenticated',
    'foreign-voucher-fiscal-staff@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '9e180000-0000-4000-8000-000000000002'
    ),
    now(),
    now()
  );

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Replace any trigger-created rows with deterministic staff profiles.
delete from public.user_profiles
where user_id in (
  '9e180000-0000-4000-8000-000000000091',
  '9e180000-0000-4000-8000-000000000092'
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
  (
    '9e180000-0000-4000-8000-000000000091',
    '9e180000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '9e180000-0000-4000-8000-000000000092',
    '9e180000-0000-4000-8000-000000000002',
    'admin',
    '{}'::jsonb,
    true
  );

select set_config(
  'request.jwt.claim.sub',
  '9e180000-0000-4000-8000-000000000091',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e180000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_name,
  date,
  status,
  subtotal,
  total,
  paid_amount,
  balance,
  items,
  tax_treatment,
  net_amount
) values
(
  '9e180000-0000-4000-8000-000000000011',
  '9e180000-0000-4000-8000-000000000001',
  'FV-VOUCHER-FISCAL-001',
  'Cliente Voucher Fiscal',
  '2026-07-18T16:00:00Z',
  'draft',
  24990,
  24990,
  0,
  24990,
  '[]'::jsonb,
  'no_tax',
  24990
);

select set_config('app.public_order_rpc_in_progress', 'true', true);
insert into public.online_orders (
  id,
  tenant_id,
  order_number,
  customer_email,
  customer_name,
  subtotal,
  total,
  status,
  payment_status,
  payment_method,
  payment_reference,
  paid_at,
  delivery_type,
  sales_invoice_id,
  created_at
) values (
  '9e180000-0000-4000-8000-000000000010',
  '9e180000-0000-4000-8000-000000000001',
  'WEB-VOUCHER-FISCAL-001',
  'customer@example.invalid',
  'Cliente Voucher Fiscal',
  24990,
  24990,
  'confirmed',
  'paid',
  'mercadopago',
  'MP-VOUCHER-FISCAL-OP-001',
  '2026-07-18T17:55:00Z',
  'pickup',
  '9e180000-0000-4000-8000-000000000011',
  '2026-07-18T16:00:00Z'
),
(
  '9e180000-0000-4000-8000-000000000020',
  '9e180000-0000-4000-8000-000000000001',
  'WEB-VOUCHER-FISCAL-002',
  'later-model-customer@example.invalid',
  'Cliente Voucher Modelo Posterior',
  24990,
  24990,
  'confirmed',
  'paid',
  'mercadopago',
  'MP-VOUCHER-FISCAL-OP-002',
  '2026-07-18T18:04:00Z',
  'pickup',
  null,
  '2026-07-18T16:00:00Z'
);
select set_config('app.public_order_rpc_in_progress', '', true);

insert into public.online_order_items (
  id,
  tenant_id,
  order_id,
  product_name,
  product_sku,
  quantity,
  unit_price,
  subtotal
) values
(
  '9e180000-0000-4000-8000-000000000012',
  '9e180000-0000-4000-8000-000000000001',
  '9e180000-0000-4000-8000-000000000010',
  'Producto voucher fiscal',
  'VOUCHER-FISCAL-001',
  1,
  24990,
  24990
);

insert into public.sales_channel_payment_events (
  tenant_id,
  provider,
  external_payment_id,
  provider_status,
  order_id,
  invoice_id,
  amount,
  currency,
  outcome,
  provider_paid_at,
  provider_payload
) values (
  '9e180000-0000-4000-8000-000000000001',
  'mercadopago',
  'MP-VOUCHER-FISCAL-OP-001',
  'approved',
  '9e180000-0000-4000-8000-000000000010',
  '9e180000-0000-4000-8000-000000000011',
  24990,
  'CLP',
  'applied',
  '2026-07-18T18:00:00Z',
  jsonb_build_object(
    'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
    'status_detail', 'accredited',
    'payment_type_id', 'credit_card',
    'payment_method_id', 'visa',
    'authorization_code', 'MP-AUTH-001',
    'date_approved', '2026-07-18T18:00:00Z',
    'transaction_amount', 24990,
    'currency_id', 'CLP',
    'total_paid_amount', 24990,
    'card_last_four_digits', '4242'
  )
),
(
  '9e180000-0000-4000-8000-000000000001',
  'mercadopago',
  'MP-VOUCHER-FISCAL-OP-002',
  'approved',
  '9e180000-0000-4000-8000-000000000020',
  null,
  24990,
  'CLP',
  'payment_validated',
  '2026-07-18T18:05:00Z',
  jsonb_build_object(
    'operation_number', 'MP-VOUCHER-FISCAL-OP-002',
    'status_detail', 'accredited',
    'payment_type_id', 'credit_card',
    'payment_method_id', 'visa',
    'authorization_code', 'MP-AUTH-002',
    'date_approved', '2026-07-18T18:05:00Z',
    'transaction_amount', 24990,
    'currency_id', 'CLP',
    'total_paid_amount', 24990,
    'card_last_four_digits', '4242'
  )
);

create temp table voucher_fiscal_evidence on commit drop as
select jsonb_build_object(
  'merchant_tax_id', '76.211.240-K',
  'merchant_legal_name', 'Voucher Fiscal Test Shop SpA',
  'merchant_address', 'Av. Prueba 123, Santiago',
  'taxable_net_amount', 21000,
  'exempt_amount', 0,
  'vat_rate_percent', 19,
  'vat_amount', 3990,
  'other_amount', 0,
  'terminal_id', 'MP-TERMINAL-001',
  'authorization_code', 'MP-AUTH-001',
  'fiscal_legend', 'Válido como Boleta'
) evidence;

select ok(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'credit_card',
      'authorization_code', 'MP-AUTH-001',
      'date_approved', '2026-07-18T18:00:00Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24990,
      'card_last_four_digits', '4242'
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  'exact eligible-card Payments API evidence can bind a claimed voucher'
);
select is(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'bank_transfer',
      'authorization_code', 'MP-AUTH-001',
      'date_approved', '2026-07-18T18:00:00Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24990,
      'card_last_four_digits', '4242',
      'external_resource_url', 'https://mercadopago.cl/banktransfer/redirect'
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  false,
  'a Fintoc or bank-transfer redirect can never bind a fiscal voucher'
);
select is(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'credit_card',
      'authorization_code', 'DIFFERENT-AUTH',
      'date_approved', '2026-07-18T18:00:00Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24990,
      'card_last_four_digits', '4242'
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  false,
  'voucher authorization must match the provider payment exactly'
);
select is(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'credit_card',
      'authorization_code', 'MP-AUTH-001',
      'date_approved', '2026-07-18T18:00:01Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24990,
      'card_last_four_digits', '4242'
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  false,
  'voucher issue time must equal the provider approval timestamp'
);
select is(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'credit_card',
      'authorization_code', 'MP-AUTH-001',
      'date_approved', '2026-07-18T18:00:00Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24990
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  false,
  'card voucher binding requires the provider last-four evidence'
);
select is(
  public.mercadopago_payment_evidence_matches_voucher(
    jsonb_build_object(
      'operation_number', 'MP-VOUCHER-FISCAL-OP-001',
      'payment_type_id', 'credit_card',
      'authorization_code', 'MP-AUTH-001',
      'date_approved', '2026-07-18T18:00:00Z',
      'transaction_amount', 24990,
      'currency_id', 'CLP',
      'total_paid_amount', 24991,
      'card_last_four_digits', '4242'
    ),
    'MP-VOUCHER-FISCAL-OP-001',
    'MP-AUTH-001',
    24990,
    'CLP',
    '2026-07-18T18:00:00Z'
  ),
  false,
  'provider total paid amount must reconcile with the claimed voucher amount'
);

create function pg_temp.record_test_voucher(
  p_provider_document_id text,
  p_source_event_key text,
  p_evidence jsonb,
  p_issued_at timestamp with time zone default '2026-07-18T18:00:00Z',
  p_artifact_sha256 text default repeat('a', 64),
  p_order_id uuid default '9e180000-0000-4000-8000-000000000010',
  p_payment_operation_id text default 'MP-VOUCHER-FISCAL-OP-001'
)
returns uuid
language sql
as $$
  select public.record_online_order_official_document(
    p_tenant_id => '9e180000-0000-4000-8000-000000000001',
    p_order_id => p_order_id,
    p_document_kind => 'payment_voucher',
    p_provider => 'mercadopago',
    p_provider_document_id => p_provider_document_id,
    p_fiscal_validity => 'voucher_valid_as_boleta',
    p_amount => 24990,
    p_currency => 'CLP',
    p_issued_at => p_issued_at,
    p_artifact_url => 'https://documents.example.invalid/voucher-fiscal.pdf',
    p_artifact_sha256 => p_artifact_sha256,
    p_status => 'approved',
    p_source_event_key => p_source_event_key,
    p_payment_operation_id => p_payment_operation_id,
    p_voucher_fiscal_evidence => p_evidence
  );
$$;

select is(
  (
    select count(*)::integer
    from public.tenant_sii_boleta_emission_model_events
    where tenant_id = '9e180000-0000-4000-8000-000000000001'
  ),
  0,
  'new tenant has no implicit or migration-created SII model configuration'
);

select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-NO-CONFIG',
      'mp-voucher-no-config',
      (select evidence from voucher_fiscal_evidence)
    )
  $$,
  '23514',
  'Tenant has no active verified SII model allowing voucher as boleta',
  'voucher fiscal validity cannot be asserted without verified tenant config'
);

select throws_ok(
  $$
    select public.record_tenant_sii_boleta_emission_model(
      p_tenant_id => '9e180000-0000-4000-8000-000000000001',
      p_model_code => 'no_emito_boleta_pago_electronico',
      p_merchant_tax_id => '76.211.240-1',
      p_merchant_legal_name => 'Voucher Fiscal Test Shop SpA',
      p_merchant_address => 'Av. Prueba 123, Santiago',
      p_declared_at => '2026-07-18T17:00:00Z',
      p_effective_from => '2026-07-18T17:00:00Z',
      p_verified_at => '2026-07-18T17:10:00Z',
      p_verification_source => 'sii_portal_declaration_receipt',
      p_verification_reference => 'SII-DECLARATION-BAD-RUT',
      p_evidence_artifact_url => 'https://evidence.example.invalid/sii/bad-rut.pdf',
      p_evidence_artifact_sha256 => repeat('1', 64),
      p_source_event_key => 'sii-model-bad-rut'
    )
  $$,
  '22023',
  'SII boleta model requires a valid Chilean merchant RUT',
  'invalid merchant RUT cannot enter verified SII configuration'
);

create temp table recorded_sii_model on commit drop as
select public.record_tenant_sii_boleta_emission_model(
  p_tenant_id => '9e180000-0000-4000-8000-000000000001',
  p_model_code => 'no_emito_boleta_pago_electronico',
  p_merchant_tax_id => '76.211.240-k',
  p_merchant_legal_name => 'Voucher Fiscal Test Shop SpA',
  p_merchant_address => 'Av. Prueba 123, Santiago',
  p_declared_at => '2026-07-18T17:00:00Z',
  p_effective_from => '2026-07-18T17:00:00Z',
  p_verified_at => '2026-07-18T17:10:00Z',
  p_verification_source => 'sii_portal_declaration_receipt',
  p_verification_reference => 'SII-DECLARATION-RECEIPT-001',
  p_evidence_artifact_url => 'https://evidence.example.invalid/sii/declaration-001.pdf',
  p_evidence_artifact_sha256 => repeat('1', 64),
  p_source_event_key => 'sii-model-event-001'
) id;

select ok(
  (select id is not null from recorded_sii_model),
  'verified SII declaration evidence is recorded'
);
select ok(
  (
    select model_code = 'no_emito_boleta_pago_electronico'
      and merchant_tax_id = '76211240-K'
      and verification_source = 'sii_portal_declaration_receipt'
      and verification_reference = 'SII-DECLARATION-RECEIPT-001'
      and evidence_artifact_sha256 = repeat('1', 64)
    from public.tenant_sii_boleta_emission_model_events
    where id = (select id from recorded_sii_model)
  ),
  'SII model stores normalized merchant identity and verification provenance'
);
select is(
  public.record_tenant_sii_boleta_emission_model(
    p_tenant_id => '9e180000-0000-4000-8000-000000000001',
    p_model_code => 'no_emito_boleta_pago_electronico',
    p_merchant_tax_id => '76211240-K',
    p_merchant_legal_name => 'Voucher Fiscal Test Shop SpA',
    p_merchant_address => 'Av. Prueba 123, Santiago',
    p_declared_at => '2026-07-18T17:00:00Z',
    p_effective_from => '2026-07-18T17:00:00Z',
    p_verified_at => '2026-07-18T17:10:00Z',
    p_verification_source => 'sii_portal_declaration_receipt',
    p_verification_reference => 'SII-DECLARATION-RECEIPT-001',
    p_evidence_artifact_url => 'https://evidence.example.invalid/sii/declaration-001.pdf',
    p_evidence_artifact_sha256 => repeat('1', 64),
    p_source_event_key => 'sii-model-event-001'
  )::text,
  (select id::text from recorded_sii_model),
  'replaying identical SII declaration evidence returns the original event'
);
select throws_ok(
  $$
    select public.record_tenant_sii_boleta_emission_model(
      p_tenant_id => '9e180000-0000-4000-8000-000000000001',
      p_model_code => 'no_emito_boleta_pago_electronico',
      p_merchant_tax_id => '76211240-K',
      p_merchant_legal_name => 'Voucher Fiscal Test Shop SpA',
      p_merchant_address => 'Changed Address 999',
      p_declared_at => '2026-07-18T17:00:00Z',
      p_effective_from => '2026-07-18T17:00:00Z',
      p_verified_at => '2026-07-18T17:10:00Z',
      p_verification_source => 'sii_portal_declaration_receipt',
      p_verification_reference => 'SII-DECLARATION-RECEIPT-001',
      p_evidence_artifact_url => 'https://evidence.example.invalid/sii/declaration-001.pdf',
      p_evidence_artifact_sha256 => repeat('1', 64),
      p_source_event_key => 'sii-model-event-001'
    )
  $$,
  '23000',
  'SII boleta model idempotency key conflicts with different evidence',
  'SII declaration idempotency key cannot rewrite configuration evidence'
);
select throws_ok(
  format(
    'update public.tenant_sii_boleta_emission_model_events set model_code = %L where id = %L::uuid',
    'siempre_emito_boleta_pago_electronico',
    (select id from recorded_sii_model)
  ),
  '55000',
  'SII boleta emission model events are append-only',
  'verified SII configuration cannot be edited in place'
);

select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-MISSING-FIELD',
      'mp-voucher-missing-field',
      (select evidence - 'authorization_code' from voucher_fiscal_evidence)
    )
  $$,
  '22023',
  'Voucher fiscal evidence fields are incomplete or unsupported',
  'voucher missing a prescribed authorization code is rejected'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-EXTRA-FIELD',
      'mp-voucher-extra-field',
      (select evidence || jsonb_build_object('raw_provider_payload', 'forbidden')
       from voucher_fiscal_evidence)
    )
  $$,
  '22023',
  'Voucher fiscal evidence fields are incomplete or unsupported',
  'voucher fiscal evidence rejects unsupported raw-provider fields'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-WRONG-LEGEND',
      'mp-voucher-wrong-legend',
      (select jsonb_set(evidence, '{fiscal_legend}', '"Boleta"')
       from voucher_fiscal_evidence)
    )
  $$,
  '23514',
  'Voucher merchant, terminal, authorization or fiscal legend is invalid',
  'voucher without the exact fiscal legend is rejected'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-WRONG-MERCHANT',
      'mp-voucher-wrong-merchant',
      (select jsonb_set(evidence, '{merchant_address}', '"Otra dirección 999"')
       from voucher_fiscal_evidence)
    )
  $$,
  '23514',
  'Voucher merchant identity does not match verified SII configuration',
  'voucher merchant identity must match the verified tenant declaration'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-BAD-ARITHMETIC',
      'mp-voucher-bad-arithmetic',
      (select jsonb_set(evidence, '{vat_amount}', '3989')
       from voucher_fiscal_evidence)
    )
  $$,
  '23514',
  'Voucher CLP tax amounts are arithmetically invalid',
  'voucher IVA and total arithmetic must reconcile exactly in CLP'
);

create temp table recorded_voucher on commit drop as
select pg_temp.record_test_voucher(
  'MP-VOUCHER-FISCAL-001',
  'mp-voucher-fiscal-event-001',
  (select evidence from voucher_fiscal_evidence)
) id;

select ok(
  (select id is not null from recorded_voucher),
  'complete voucher with independently verified SII model is recorded'
);
select ok(
  (
    select merchant_tax_id = '76211240-K'
      and merchant_legal_name = 'Voucher Fiscal Test Shop SpA'
      and merchant_address = 'Av. Prueba 123, Santiago'
      and taxable_net_amount = 21000
      and exempt_amount = 0
      and vat_rate_percent = 19
      and vat_amount = 3990
      and other_amount = 0
      and terminal_id = 'MP-TERMINAL-001'
      and authorization_code = 'MP-AUTH-001'
      and fiscal_legend = 'Válido como Boleta'
      and voucher_evidence_fingerprint ~ '^[0-9a-f]{64}$'
    from public.online_order_official_documents
    where id = (select id from recorded_voucher)
  ),
  'voucher ledger stores every prescribed structured fiscal field'
);
select is(
  (
    select sii_emission_model_event_id::text
    from public.online_order_official_documents
    where id = (select id from recorded_voucher)
  ),
  (select id::text from recorded_sii_model),
  'voucher is linked to the authoritative SII model event effective at issue'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
      and order_id = '9e180000-0000-4000-8000-000000000010'
  ),
  1,
  'only complete verified voucher evidence enqueues a voucher email'
);
select is(
  pg_temp.record_test_voucher(
    'MP-VOUCHER-FISCAL-001',
    'mp-voucher-fiscal-event-001',
    (select evidence from voucher_fiscal_evidence)
  )::text,
  (select id::text from recorded_voucher),
  'replaying identical base and fiscal evidence returns the original voucher'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-FISCAL-001',
      'mp-voucher-fiscal-event-001',
      (select jsonb_set(evidence, '{terminal_id}', '"MP-TERMINAL-CHANGED"')
       from voucher_fiscal_evidence)
    )
  $$,
  '23000',
  'Voucher idempotency identity conflicts with different fiscal evidence',
  'voucher replay cannot substitute different structured fiscal evidence'
);

create temp table recorded_always_emit_model on commit drop as
select public.record_tenant_sii_boleta_emission_model(
  p_tenant_id => '9e180000-0000-4000-8000-000000000001',
  p_model_code => 'siempre_emito_boleta_pago_electronico',
  p_merchant_tax_id => '76211240-K',
  p_merchant_legal_name => 'Voucher Fiscal Test Shop SpA',
  p_merchant_address => 'Av. Prueba 123, Santiago',
  p_declared_at => '2026-07-18T18:01:00Z',
  p_effective_from => '2026-07-18T18:01:00Z',
  p_verified_at => '2026-07-18T18:02:00Z',
  p_verification_source => 'sii_portal_declaration_receipt',
  p_verification_reference => 'SII-DECLARATION-RECEIPT-002',
  p_evidence_artifact_url => 'https://evidence.example.invalid/sii/declaration-002.pdf',
  p_evidence_artifact_sha256 => repeat('2', 64),
  p_source_event_key => 'sii-model-event-002'
) id;

select ok(
  (select id is not null from recorded_always_emit_model),
  'later verified SII model change is appended as a new event'
);
select throws_ok(
  $$
    select pg_temp.record_test_voucher(
      'MP-VOUCHER-AFTER-MODEL-CHANGE',
      'mp-voucher-after-model-change',
      (select jsonb_set(evidence, '{authorization_code}', '"MP-AUTH-002"')
       from voucher_fiscal_evidence),
      '2026-07-18T18:05:00Z',
      repeat('a', 64),
      '9e180000-0000-4000-8000-000000000020',
      'MP-VOUCHER-FISCAL-OP-002'
    )
  $$,
  '23514',
  'Tenant has no active verified SII model allowing voucher as boleta',
  'latest effective always-emit model blocks later voucher-as-boleta evidence'
);

create temp table recorded_dte on commit drop as
select public.record_online_order_official_document(
  p_tenant_id => '9e180000-0000-4000-8000-000000000001',
  p_order_id => '9e180000-0000-4000-8000-000000000010',
  p_document_kind => 'tax_document',
  p_provider => 'sii_provider',
  p_provider_document_id => 'DTE-VOUCHER-FISCAL-001',
  p_fiscal_validity => 'official_chilean_dte',
  p_amount => 24990,
  p_currency => 'CLP',
  p_issued_at => '2026-07-18T18:05:00Z',
  p_artifact_url => 'https://documents.example.invalid/dte-voucher-fiscal.pdf',
  p_artifact_sha256 => repeat('b', 64),
  p_status => 'accepted',
  p_source_event_key => 'dte-voucher-fiscal-event-001',
  p_document_type => 'boleta_electronica',
  p_folio => '180001'
) id;

select ok(
  (select id is not null from recorded_dte),
  'official DTE recording remains valid without voucher-only evidence'
);
select ok(
  (
    select sii_emission_model_event_id is null
      and merchant_tax_id is null
      and taxable_net_amount is null
      and voucher_evidence_fingerprint is null
    from public.online_order_official_documents
    where id = (select id from recorded_dte)
  ),
  'DTE row remains independent of payment-voucher fiscal fields'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'tax_document_issued'
      and order_id = '9e180000-0000-4000-8000-000000000010'
  ),
  1,
  'DTE evidence still enqueues its independent tax-document email'
);

select set_config(
  'request.jwt.claim.sub',
  '9e180000-0000-4000-8000-000000000091',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e180000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.tenant_sii_boleta_emission_model_events
  ),
  2,
  'active staff can read their tenant SII model provenance'
);
reset role;

update public.user_profiles
set is_active = false
where user_id = '9e180000-0000-4000-8000-000000000091'
  and tenant_id = '9e180000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.tenant_sii_boleta_emission_model_events
  ),
  0,
  'inactive former staff cannot read SII model provenance'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '9e180000-0000-4000-8000-000000000092',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e180000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.tenant_sii_boleta_emission_model_events
  ),
  0,
  'RLS hides another tenant SII model provenance'
);
reset role;

select * from finish();
rollback;
