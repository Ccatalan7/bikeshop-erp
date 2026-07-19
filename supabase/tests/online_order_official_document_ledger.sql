begin;

select plan(35);

select has_table(
  'public',
  'online_order_official_documents',
  'official online-order document ledger exists'
);
select hasnt_column(
  'public',
  'online_order_official_documents',
  'provider_payload',
  'ledger has no raw provider payload column'
);
select is(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.online_order_official_documents'::regclass
  ),
  true,
  'official document ledger has RLS enabled'
);
select is(
  has_table_privilege(
    'authenticated',
    'public.online_order_official_documents',
    'SELECT'
  ),
  true,
  'authenticated staff can select tenant-scoped official document evidence'
);
select is(
  has_table_privilege(
    'authenticated',
    'public.online_order_official_documents',
    'INSERT'
  ),
  false,
  'authenticated clients cannot forge official documents'
);
select is(
  has_table_privilege(
    'service_role',
    'public.online_order_official_documents',
    'INSERT'
  ),
  false,
  'service role must use the canonical recorder instead of direct insert'
);
select is(
  has_function_privilege(
    'service_role',
    'public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)',
    'EXECUTE'
  ),
  true,
  'service role can execute the idempotent official-document recorder'
);
select is(
  has_function_privilege(
    'authenticated',
    'public.record_online_order_official_document(uuid,uuid,text,text,text,text,numeric,text,timestamp with time zone,text,text,text,text,text,text,text,jsonb,jsonb)',
    'EXECUTE'
  ),
  false,
  'authenticated clients cannot execute the official-document recorder'
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
    '9e150000-0000-4000-8000-000000000001',
    'Official Document Test Shop',
    'official-docs.example.invalid',
    'owner@example.invalid',
    'CLP',
    'America/Santiago'
  ),
  (
    '9e150000-0000-4000-8000-000000000002',
    'Foreign Official Document Shop',
    'foreign-docs.example.invalid',
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
    '9e150000-0000-4000-8000-000000000091',
    'authenticated',
    'authenticated',
    'official-docs-staff@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '9e150000-0000-4000-8000-000000000001'
    ),
    now(),
    now()
  ),
  (
    '9e150000-0000-4000-8000-000000000092',
    'authenticated',
    'authenticated',
    'foreign-docs-staff@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object(
      'tenant_id',
      '9e150000-0000-4000-8000-000000000002'
    ),
    now(),
    now()
  );

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Replace any trigger-created rows with deterministic staff profiles.
delete from public.user_profiles
where user_id in (
  '9e150000-0000-4000-8000-000000000091',
  '9e150000-0000-4000-8000-000000000092'
);

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values
  (
    '9e150000-0000-4000-8000-000000000091',
    '9e150000-0000-4000-8000-000000000001',
    'admin',
    '{}'::jsonb,
    true
  ),
  (
    '9e150000-0000-4000-8000-000000000092',
    '9e150000-0000-4000-8000-000000000002',
    'admin',
    '{}'::jsonb,
    true
  );

select set_config(
  'request.jwt.claim.sub',
  '9e150000-0000-4000-8000-000000000091',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e150000-0000-4000-8000-000000000091',
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
    '9e150000-0000-4000-8000-000000000011',
    '9e150000-0000-4000-8000-000000000001',
    'FV-OFFICIAL-DOC-001',
    'Cliente Documento Oficial',
    '2026-07-18T17:00:00Z',
    'draft',
    24990,
    24990,
    0,
    24990,
    '[]'::jsonb,
    'no_tax',
    24990
  ),
  (
    '9e150000-0000-4000-8000-000000000031',
    '9e150000-0000-4000-8000-000000000001',
    'FV-OFFICIAL-DOC-TRANSFER',
    'Cliente Transferencia',
    '2026-07-18T17:00:00Z',
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
) values
  (
    '9e150000-0000-4000-8000-000000000010',
    '9e150000-0000-4000-8000-000000000001',
    'WEB-OFFICIAL-DOC-001',
    'customer@example.invalid',
    'Cliente Documento Oficial',
    24990,
    24990,
    'confirmed',
    'paid',
    'mercadopago',
    'MP-OFFICIAL-OP-001',
    '2026-07-18T17:55:00Z',
    'pickup',
    '9e150000-0000-4000-8000-000000000011',
    '2026-07-18T17:00:00Z'
  ),
  (
    '9e150000-0000-4000-8000-000000000030',
    '9e150000-0000-4000-8000-000000000001',
    'WEB-OFFICIAL-DOC-TRANSFER',
    'transfer@example.invalid',
    'Cliente Transferencia',
    24990,
    24990,
    'confirmed',
    'paid',
    'transfer',
    'TRANSFER-001',
    '2026-07-18T17:55:00Z',
    'pickup',
    '9e150000-0000-4000-8000-000000000031',
    '2026-07-18T17:00:00Z'
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
) values (
  '9e150000-0000-4000-8000-000000000012',
  '9e150000-0000-4000-8000-000000000001',
  '9e150000-0000-4000-8000-000000000010',
  'Producto documento oficial',
  'DOC-OFFICIAL-001',
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
  '9e150000-0000-4000-8000-000000000001',
  'mercadopago',
  'MP-OFFICIAL-OP-001',
  'approved',
  '9e150000-0000-4000-8000-000000000010',
  '9e150000-0000-4000-8000-000000000011',
  24990,
  'CLP',
  'applied',
  '2026-07-18T18:00:00Z',
  jsonb_build_object(
    'operation_number', 'MP-OFFICIAL-OP-001',
    'status_detail', 'accredited',
    'payment_type_id', 'credit_card',
    'payment_method_id', 'visa',
    'authorization_code', 'MP-AUTH-OFFICIAL-001',
    'date_approved', '2026-07-18T18:00:00Z',
    'transaction_amount', 24990,
    'currency_id', 'CLP',
    'total_paid_amount', 24990,
    'card_last_four_digits', '4242'
  )
);

select public.record_tenant_sii_boleta_emission_model(
  p_tenant_id => '9e150000-0000-4000-8000-000000000001',
  p_model_code => 'no_emito_boleta_pago_electronico',
  p_merchant_tax_id => '76.211.240-K',
  p_merchant_legal_name => 'Official Document Test Shop SpA',
  p_merchant_address => 'Av. Documento 1500, Santiago',
  p_declared_at => '2026-07-18T17:00:00Z',
  p_effective_from => '2026-07-18T17:00:00Z',
  p_verified_at => '2026-07-18T17:10:00Z',
  p_verification_source => 'sii_portal_declaration_receipt',
  p_verification_reference => 'SII-OFFICIAL-DOC-TEST-001',
  p_evidence_artifact_url => 'https://evidence.example.invalid/sii/official-doc-test.pdf',
  p_evidence_artifact_sha256 => repeat('1', 64),
  p_source_event_key => 'sii-official-doc-test-001'
);

create temp table official_voucher_fiscal_evidence on commit drop as
select jsonb_build_object(
  'merchant_tax_id', '76.211.240-K',
  'merchant_legal_name', 'Official Document Test Shop SpA',
  'merchant_address', 'Av. Documento 1500, Santiago',
  'taxable_net_amount', 21000,
  'exempt_amount', 0,
  'vat_rate_percent', 19,
  'vat_amount', 3990,
  'other_amount', 0,
  'terminal_id', 'MP-TERMINAL-OFFICIAL-001',
  'authorization_code', 'MP-AUTH-OFFICIAL-001',
  'fiscal_legend', 'Válido como Boleta'
) evidence;

select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
  ),
  0,
  'approved provider payment alone does not invent a voucher email'
);

select throws_ok(
  $$
    select public.record_online_order_official_document(
      p_tenant_id => '9e150000-0000-4000-8000-000000000001',
      p_order_id => '9e150000-0000-4000-8000-000000000010',
      p_document_kind => 'payment_voucher',
      p_provider => 'mercadopago',
      p_provider_document_id => 'MP-VOUCHER-INSECURE',
      p_fiscal_validity => 'voucher_valid_as_boleta',
      p_amount => 24990,
      p_currency => 'CLP',
      p_issued_at => '2026-07-18T18:00:00Z',
      p_artifact_url => 'http://documents.example.invalid/voucher.pdf',
      p_artifact_sha256 => repeat('a', 64),
      p_status => 'approved',
      p_source_event_key => 'mp-event-insecure',
      p_payment_operation_id => 'MP-OFFICIAL-OP-001',
      p_voucher_fiscal_evidence => (
        select evidence from official_voucher_fiscal_evidence
      )
    )
  $$,
  '22023',
  'Official document requires a secure HTTPS artifact URL',
  'insecure artifact URL is rejected before ledger or email mutation'
);

select throws_ok(
  $$
    select public.record_online_order_official_document(
      p_tenant_id => '9e150000-0000-4000-8000-000000000001',
      p_order_id => '9e150000-0000-4000-8000-000000000030',
      p_document_kind => 'payment_voucher',
      p_provider => 'mercadopago',
      p_provider_document_id => 'TRANSFER-IS-NOT-A-VOUCHER',
      p_fiscal_validity => 'voucher_valid_as_boleta',
      p_amount => 24990,
      p_currency => 'CLP',
      p_issued_at => '2026-07-18T18:00:00Z',
      p_artifact_url => 'https://documents.example.invalid/transfer.pdf',
      p_artifact_sha256 => repeat('a', 64),
      p_status => 'approved',
      p_source_event_key => 'transfer-event-invalid-voucher',
      p_payment_operation_id => 'TRANSFER-001',
      p_voucher_fiscal_evidence => (
        select evidence from official_voucher_fiscal_evidence
      )
    )
  $$,
  '23514',
  'Only Mercado Pago orders can record payment vouchers',
  'bank transfer can never be recorded as an official provider voucher'
);

create temp table recorded_voucher on commit drop as
select public.record_online_order_official_document(
  p_tenant_id => '9e150000-0000-4000-8000-000000000001',
  p_order_id => '9e150000-0000-4000-8000-000000000010',
  p_document_kind => 'payment_voucher',
  p_provider => 'mercado_pago',
  p_provider_document_id => 'MP-VOUCHER-001',
  p_fiscal_validity => 'voucher_valid_as_boleta',
  p_amount => 24990,
  p_currency => 'CLP',
  p_issued_at => '2026-07-18T18:00:00Z',
  p_artifact_url => 'https://documents.example.invalid/mp/voucher-001.pdf',
  p_artifact_sha256 => repeat('a', 64),
  p_status => 'approved',
  p_source_event_key => 'mp-voucher-event-001',
  p_payment_operation_id => 'MP-OFFICIAL-OP-001',
  p_metadata => jsonb_build_object(
    'source', 'mercadopago_webhook',
    'provider_event_id', 'provider-event-001',
    'mime_type', 'application/pdf',
    'access_token', 'MUST-NOT-BE-STORED',
    'authorization', 'Bearer MUST-NOT-BE-STORED',
    'raw_response', jsonb_build_object('secret', 'MUST-NOT-BE-STORED')
  ),
  p_voucher_fiscal_evidence => (
    select evidence from official_voucher_fiscal_evidence
  )
) id;

select ok(
  (select id is not null from recorded_voucher),
  'complete official Mercado Pago voucher evidence is recorded'
);
select ok(
  (
    select provider = 'mercadopago'
      and payment_operation_id = 'MP-OFFICIAL-OP-001'
      and amount = 24990
      and currency = 'CLP'
      and status = 'approved'
      and artifact_sha256 = repeat('a', 64)
    from public.online_order_official_documents
    where id = (select id from recorded_voucher)
  ),
  'voucher ledger preserves normalized provider, operation and artifact evidence'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  1,
  'complete voucher evidence enqueues exactly one voucher message'
);
select is(
  (
    select render_payload#>>'{officialPaymentVoucher,fiscalValidity}'
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  'voucher_valid_as_boleta',
  'voucher email payload carries explicit fiscal validity'
);
select is(
  (
    select attachment_manifest#>>'{0,sha256}'
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  repeat('a', 64),
  'voucher email references the immutable artifact hash'
);
select is(
  (
    select metadata->>'source'
    from public.online_order_official_documents
    where id = (select id from recorded_voucher)
  ),
  'mercadopago_webhook',
  'allow-listed non-secret metadata is retained'
);
select is(
  (
    select metadata ?| array['access_token', 'authorization', 'raw_response']
    from public.online_order_official_documents
    where id = (select id from recorded_voucher)
  ),
  false,
  'secret and raw-provider metadata keys are discarded'
);

select is(
  public.record_online_order_official_document(
    p_tenant_id => '9e150000-0000-4000-8000-000000000001',
    p_order_id => '9e150000-0000-4000-8000-000000000010',
    p_document_kind => 'payment_voucher',
    p_provider => 'mercadopago',
    p_provider_document_id => 'MP-VOUCHER-001',
    p_fiscal_validity => 'voucher_valid_as_boleta',
    p_amount => 24990,
    p_currency => 'CLP',
    p_issued_at => '2026-07-18T18:00:00Z',
    p_artifact_url => 'https://documents.example.invalid/mp/voucher-001.pdf',
    p_artifact_sha256 => repeat('a', 64),
    p_status => 'approved',
    p_source_event_key => 'mp-voucher-event-001',
    p_payment_operation_id => 'MP-OFFICIAL-OP-001',
    p_metadata => jsonb_build_object('source', 'retry'),
    p_voucher_fiscal_evidence => (
      select evidence from official_voucher_fiscal_evidence
    )
  )::text,
  (select id::text from recorded_voucher),
  'replaying the same official evidence returns the original ledger row'
);
select is(
  (
    select count(*)::integer
    from public.online_order_official_documents
    where document_kind = 'payment_voucher'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  1,
  'voucher replay creates no duplicate ledger row'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'payment_voucher_available'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  1,
  'voucher replay creates no duplicate email outbox row'
);

select throws_ok(
  $$
    select public.record_online_order_official_document(
      p_tenant_id => '9e150000-0000-4000-8000-000000000001',
      p_order_id => '9e150000-0000-4000-8000-000000000010',
      p_document_kind => 'payment_voucher',
      p_provider => 'mercadopago',
      p_provider_document_id => 'MP-VOUCHER-001',
      p_fiscal_validity => 'voucher_valid_as_boleta',
      p_amount => 24990,
      p_currency => 'CLP',
      p_issued_at => '2026-07-18T18:00:00Z',
      p_artifact_url => 'https://documents.example.invalid/mp/voucher-CHANGED.pdf',
      p_artifact_sha256 => repeat('c', 64),
      p_status => 'approved',
      p_source_event_key => 'mp-voucher-event-001',
      p_payment_operation_id => 'MP-OFFICIAL-OP-001',
      p_voucher_fiscal_evidence => (
        select evidence from official_voucher_fiscal_evidence
      )
    )
  $$,
  '23000',
  'Official document idempotency key conflicts with different evidence',
  'same idempotency identity cannot overwrite different official evidence'
);

select throws_ok(
  $$
    select public.record_online_order_official_document(
      p_tenant_id => '9e150000-0000-4000-8000-000000000001',
      p_order_id => '9e150000-0000-4000-8000-000000000010',
      p_document_kind => 'tax_document',
      p_provider => 'sii_provider',
      p_provider_document_id => 'DTE-INCOMPLETE',
      p_fiscal_validity => 'official_chilean_dte',
      p_amount => 24990,
      p_currency => 'CLP',
      p_issued_at => '2026-07-18T18:05:00Z',
      p_artifact_url => 'https://documents.example.invalid/dte/incomplete.pdf',
      p_artifact_sha256 => repeat('b', 64),
      p_status => 'issued',
      p_source_event_key => 'dte-event-incomplete',
      p_document_type => 'boleta_electronica'
    )
  $$,
  '23514',
  'Official DTE evidence is incomplete',
  'DTE without folio cannot enter the ledger or enqueue email'
);

create temp table recorded_dte on commit drop as
select public.record_online_order_official_document(
  p_tenant_id => '9e150000-0000-4000-8000-000000000001',
  p_order_id => '9e150000-0000-4000-8000-000000000010',
  p_document_kind => 'tax_document',
  p_provider => 'sii_provider',
  p_provider_document_id => 'DTE-BOLETA-001',
  p_fiscal_validity => 'official_chilean_dte',
  p_amount => 24990,
  p_currency => 'CLP',
  p_issued_at => '2026-07-18T18:05:00Z',
  p_artifact_url => 'https://documents.example.invalid/dte/boleta-001.pdf',
  p_artifact_sha256 => repeat('b', 64),
  p_status => 'accepted',
  p_source_event_key => 'dte-event-001',
  p_document_type => 'boleta_electronica',
  p_folio => '123456',
  p_metadata => jsonb_build_object(
    'source', 'dte_provider_webhook',
    'document_series', '39',
    'mime_type', 'application/pdf',
    'api_key', 'MUST-NOT-BE-STORED'
  )
) id;

select ok(
  (select id is not null from recorded_dte),
  'complete issued or accepted Chilean DTE evidence is recorded'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind = 'tax_document_issued'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  1,
  'complete DTE evidence enqueues exactly one tax-document message'
);
select is(
  (
    select render_payload#>>'{officialTaxDocument,documentType}'
    from public.transactional_email_outbox
    where message_kind = 'tax_document_issued'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  'boleta_electronica',
  'DTE email payload includes the official document type'
);
select is(
  (
    select render_payload#>>'{officialTaxDocument,folio}'
    from public.transactional_email_outbox
    where message_kind = 'tax_document_issued'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  '123456',
  'DTE email payload includes the official folio'
);
select is(
  (
    select attachment_manifest#>>'{0,sha256}'
    from public.transactional_email_outbox
    where message_kind = 'tax_document_issued'
      and order_id = '9e150000-0000-4000-8000-000000000010'
  ),
  repeat('b', 64),
  'DTE email references the immutable official artifact hash'
);

select throws_ok(
  format(
    'update public.online_order_official_documents set status = %L where id = %L::uuid',
    'issued',
    (select id from recorded_dte)
  ),
  '55000',
  'Online order official documents are append-only',
  'official document evidence cannot be updated'
);
select throws_ok(
  format(
    'delete from public.online_order_official_documents where id = %L::uuid',
    (select id from recorded_voucher)
  ),
  '55000',
  'Online order official documents are append-only',
  'official document evidence cannot be deleted'
);
select is(
  (
    select count(*)::integer
    from public.online_order_official_documents
    where tenant_id = '9e150000-0000-4000-8000-000000000001'
  ),
  2,
  'only the complete voucher and DTE evidence rows exist'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where message_kind in (
      'payment_voucher_available',
      'tax_document_issued'
    )
  ),
  2,
  'only complete official evidence produced document emails'
);

select set_config(
  'request.jwt.claim.sub',
  '9e150000-0000-4000-8000-000000000091',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e150000-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.online_order_official_documents
  ),
  2,
  'staff can read official document evidence for their own tenant'
);
reset role;

update public.user_profiles
set is_active = false
where user_id = '9e150000-0000-4000-8000-000000000091'
  and tenant_id = '9e150000-0000-4000-8000-000000000001';
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.online_order_official_documents
  ),
  0,
  'inactive former staff cannot read official document evidence'
);
reset role;

select set_config(
  'request.jwt.claim.sub',
  '9e150000-0000-4000-8000-000000000092',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e150000-0000-4000-8000-000000000092',
    'role', 'authenticated'
  )::text,
  true
);
set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.online_order_official_documents
  ),
  0,
  'RLS hides another tenant official document evidence'
);
reset role;

select * from finish();
rollback;
