begin;

select plan(55);

select has_table('public', 'transactional_email_outbox', 'transactional email outbox exists');
select has_table(
  'public',
  'transactional_email_provider_events',
  'provider delivery-event ledger exists'
);
select has_table(
  'public',
  'transactional_email_suppressions',
  'recipient suppression ledger exists'
);
select has_table(
  'public',
  'online_order_access_tokens',
  'hashed guest access-token table exists'
);

insert into public.tenants (
  id,
  shop_name,
  custom_domain,
  owner_email,
  currency,
  timezone
) values (
  '9e140000-0000-4000-8000-000000000001',
  'Transactional Email Test Shop',
  'email-test.example.invalid',
  'support@example.invalid',
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
) values (
  '9e140000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'email-worker-actor@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('tenant_id', '9e140000-0000-4000-8000-000000000001'),
  now(),
  now()
);

-- Production-derived schema clones do not guarantee an auth.users bootstrap
-- trigger. Seed the actor profile explicitly so this fixture is deterministic
-- with or without that environment-specific side effect.
delete from public.user_profiles
where user_id = '9e140000-0000-4000-8000-000000000099';

insert into public.user_profiles (
  user_id,
  tenant_id,
  role,
  permissions,
  is_active
) values (
  '9e140000-0000-4000-8000-000000000099',
  '9e140000-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claim.sub',
  '9e140000-0000-4000-8000-000000000099',
  true
);
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9e140000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
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
  delivery_type,
  internal_notes
) values (
  '9e140000-0000-4000-8000-000000000010',
  '9e140000-0000-4000-8000-000000000001',
  'WEB-EMAIL-TEST-001',
  'customer@example.invalid',
  'Cliente Email Prueba',
  24990,
  24990,
  'pending',
  'pending',
  'mercadopago',
  'pickup',
  'NOTA INTERNA QUE NUNCA DEBE SALIR'
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
  '9e140000-0000-4000-8000-000000000011',
  '9e140000-0000-4000-8000-000000000001',
  '9e140000-0000-4000-8000-000000000010',
  'Producto de prueba',
  'EMAIL-TEST-001',
  1,
  24990,
  24990
);

insert into public.online_order_events (
  id,
  tenant_id,
  order_id,
  event_type,
  from_status,
  to_status,
  from_payment_status,
  to_payment_status,
  changed,
  expected_version,
  result_version,
  operation_key,
  request_snapshot,
  response_snapshot
) values (
  '9e140000-0000-4000-8000-000000000020',
  '9e140000-0000-4000-8000-000000000001',
  '9e140000-0000-4000-8000-000000000010',
  'order_created',
  null,
  'pending',
  null,
  'pending',
  true,
  null,
  0,
  'email-test:order-created',
  '{"source":"pgtap"}'::jsonb,
  '{"changed":true,"status":"pending","payment_status":"pending"}'::jsonb
);

select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'order_received'
  ),
  1,
  'order_created enqueues exactly one order-received message'
);
select is(
  (
    select delivery_mode
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  'dry_run',
  'tenant without explicit send configuration remains dry-run'
);
select is(
  (
    select jsonb_array_length(render_payload->'items')
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  1,
  'immutable render payload includes the complete item snapshot'
);
select is(
  (
    select render_payload#>>'{document,taxStatus}'
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  'not_a_tax_document',
  'order receipt is explicitly stored as non-tax'
);
select is(
  (
    select render_payload#>>'{customer,email}'
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  null,
  'render payload does not duplicate the recipient email into customer content'
);
select is(
  (
    select render_payload->>'internalNotes'
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  null,
  'internal notes never enter the render payload'
);
select is(
  (
    select jsonb_array_length(attachment_manifest)
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  0,
  'internal receipt is not attached as a legal document'
);

select public.enqueue_transactional_email_from_order_event_id(
  '9e140000-0000-4000-8000-000000000020'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_event_id = '9e140000-0000-4000-8000-000000000020'
  ),
  1,
  'replaying the same event preserves one durable outbox row'
);

-- Keep this fixture deterministic even when another local suite has left
-- unrelated outbox rows pending. The production worker intentionally claims a
-- global queue; this test must assert only the row that it created.
select set_config('app.transactional_email_mutation', 'true', true);
update public.transactional_email_outbox
set available_at = '-infinity'::timestamp with time zone
where order_event_id = '9e140000-0000-4000-8000-000000000020';

create temp table claimed_dry_run on commit drop as
select *
from public.claim_transactional_email_outbox('email-worker-dry', 'dry_run', 1, 120);

select is(
  (select count(*)::integer from claimed_dry_run),
  1,
  'dry-run worker claims the pending dry-run row'
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_dry_run)
  ),
  'leased',
  'claim records a recoverable lease'
);
select is(
  (
    select attempt_count
    from public.transactional_email_outbox
    where id = (select id from claimed_dry_run)
  ),
  1,
  'claim increments the durable attempt counter once'
);
select is(
  (
    select count(*)::integer
    from public.claim_transactional_email_outbox(
      'email-worker-other',
      'dry_run',
      10,
      120
    ) other_claim
    where other_claim.id = (select id from claimed_dry_run)
  ),
  0,
  'a concurrent worker cannot reclaim this active lease'
);
select throws_ok(
  format(
    'select public.complete_transactional_email_attempt(%L::uuid,%L,%L::uuid,%L)',
    (select id from claimed_dry_run),
    'email-worker-dry',
    '00000000-0000-4000-8000-000000000001',
    'rendered'
  ),
  '40001',
  'Transactional email lease is stale or belongs to another worker',
  'a stale lease token cannot complete another attempt'
);

select public.complete_transactional_email_attempt(
  (select id from claimed_dry_run),
  'email-worker-dry',
  (select lease_token from claimed_dry_run),
  'rendered',
  null,
  null,
  null,
  null,
  null,
  'Recibimos tu pedido WEB-EMAIL-TEST-001',
  repeat('a', 64),
  repeat('b', 64)
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_dry_run)
  ),
  'rendered',
  'dry-run completion is terminal and visibly rendered'
);
select is(
  (
    select provider_message_id
    from public.transactional_email_outbox
    where id = (select id from claimed_dry_run)
  ),
  null,
  'dry-run rendering invents no provider acknowledgement'
);

insert into public.transactional_email_settings (
  tenant_id,
  enabled,
  delivery_mode,
  from_name,
  from_email,
  reply_to_email,
  public_store_url
) values (
  '9e140000-0000-4000-8000-000000000001',
  true,
  'send',
  'Transactional Email Test Shop',
  'pedidos@example.invalid',
  'support@example.invalid',
  'https://email-test.example.invalid'
);

update public.online_orders
set status = 'confirmed'
where id = '9e140000-0000-4000-8000-000000000010';
update public.online_orders
set status = 'processing'
where id = '9e140000-0000-4000-8000-000000000010';

select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'processing'
  ),
  1,
  'processing transition enqueues its customer milestone once'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox outbox
    join public.online_order_events event on event.id = outbox.order_event_id
    where event.order_id = '9e140000-0000-4000-8000-000000000010'
      and event.to_status = 'confirmed'
  ),
  0,
  'confirmed status alone does not impersonate payment confirmation'
);

select set_config('app.transactional_email_mutation', 'true', true);
update public.transactional_email_outbox
set available_at = '-infinity'::timestamp with time zone
where order_id = '9e140000-0000-4000-8000-000000000010'
  and message_kind = 'processing';

create temp table claimed_send on commit drop as
select *
from public.claim_transactional_email_outbox('email-worker-send', 'send', 1, 120);

select is(
  (select count(*)::integer from claimed_send),
  1,
  'send-mode worker claims only explicitly enabled send rows'
);

-- The signed provider event can arrive before the worker persists the API
-- acknowledgement. The webhook must attach provider identity and the worker's
-- exact completion must then replay rather than fail on a stale lease.
select public.record_transactional_email_provider_event(
  'resend',
  'svix-sent-before-completion-001',
  'email_provider_test_001',
  (select id from claimed_send),
  'email.sent',
  '2026-07-18T17:59:00Z',
  repeat('9', 64),
  '{}'::jsonb,
  false
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'submitted',
  'signed sent event can win the worker-completion race safely'
);
select is(
  (
    select provider || ':' || provider_message_id
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'resend:email_provider_test_001',
  'racing webhook persists exact provider identity'
);
select is(
  (
    select lease_owner is null and lease_token is null and lease_expires_at is null
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  true,
  'provider reconciliation clears the completed lease'
);

create temp table replayed_worker_completion on commit drop as
select public.complete_transactional_email_attempt(
  (select id from claimed_send),
  'email-worker-send',
  (select lease_token from claimed_send),
  'submitted',
  'resend',
  'email_provider_test_001',
  null,
  null,
  null,
  (select subject from claimed_send),
  repeat('c', 64),
  repeat('d', 64)
) result;
select is(
  (select (result->>'replay')::boolean from replayed_worker_completion),
  true,
  'worker acknowledgement replays after a racing signed webhook'
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'submitted',
  'provider acknowledgement is stored before delivery evidence'
);
select is(
  (
    select rendered_html_sha256 || ':' || rendered_text_sha256
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  repeat('c', 64) || ':' || repeat('d', 64),
  'racing webhook reconciliation retains the exact rendered content evidence'
);

create temp table conflicting_provider_hint on commit drop as
select public.record_transactional_email_provider_event(
  'resend',
  'svix-conflicting-hint-001',
  'email_provider_other_message',
  (select id from claimed_send),
  'email.sent',
  '2026-07-18T17:59:30Z',
  repeat('8', 64),
  '{}'::jsonb,
  false
) result;
select is(
  (select (result->>'matched')::boolean from conflicting_provider_hint),
  false,
  'conflicting provider identity cannot mutate an outbox row by UUID hint'
);
select is(
  (
    select provider_message_id
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'email_provider_test_001',
  'conflicting UUID hint preserves the original provider identity'
);

select public.record_transactional_email_provider_event(
  'resend',
  'svix-delivered-001',
  'email_provider_test_001',
  (select id from claimed_send),
  'email.delivered',
  '2026-07-18T18:00:00Z',
  repeat('e', 64),
  '{"outboxId":"test"}'::jsonb,
  false
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'delivered',
  'signed provider delivery event advances the outbox to delivered'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_provider_events
    where provider_event_id = 'svix-delivered-001'
  ),
  1,
  'delivery evidence is appended once'
);
select is(
  (
    public.record_transactional_email_provider_event(
      'resend',
      'svix-delivered-001',
      'email_provider_test_001',
      (select id from claimed_send),
      'email.delivered',
      '2026-07-18T18:00:00Z',
      repeat('e', 64),
      '{"outboxId":"test"}'::jsonb,
      false
    )->>'replay'
  )::boolean,
  true,
  'duplicate at-least-once webhook delivery replays idempotently'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_provider_events
    where provider_event_id = 'svix-delivered-001'
  ),
  1,
  'webhook replay creates no duplicate provider event'
);
select throws_ok(
  format(
    'select public.record_transactional_email_provider_event(%L,%L,%L,%L::uuid,%L,%L::timestamptz,%L,%L::jsonb,%L::boolean)',
    'resend',
    'svix-delivered-001',
    'email_provider_test_001',
    (select id from claimed_send),
    'email.delivered',
    '2026-07-18T18:00:00Z',
    repeat('0', 64),
    '{"outboxId":"different-evidence"}',
    false
  ),
  '23000',
  'Transactional email provider event id conflicts with different evidence',
  'a provider event id cannot replay with a different signed payload'
);

-- This message existed before the later hard bounce. It must be suppressed by
-- the provider event itself and remain unclaimable.
insert into public.transactional_email_outbox (
  id,
  tenant_id,
  order_id,
  source_event_key,
  message_kind,
  template_key,
  recipient_email,
  sender_name,
  sender_email,
  reply_to_email,
  subject,
  render_payload,
  idempotency_key,
  delivery_mode,
  available_at
) values (
  '9e140000-0000-4000-8000-000000000070',
  '9e140000-0000-4000-8000-000000000001',
  '9e140000-0000-4000-8000-000000000010',
  'queued-before-hard-bounce',
  'processing',
  'processing',
  'customer@example.invalid',
  'Transactional Email Test Shop',
  'pedidos@example.invalid',
  'support@example.invalid',
  'Queued before hard bounce',
  '{}'::jsonb,
  'queued-before-hard-bounce',
  'send',
  '-infinity'::timestamp with time zone
);

select public.record_transactional_email_provider_event(
  'resend',
  'svix-bounced-001',
  'email_provider_test_001',
  (select id from claimed_send),
  'email.bounced',
  '2026-07-18T18:02:00Z',
  repeat('f', 64),
  '{"reason":"Permanent mailbox rejection"}'::jsonb,
  true
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = (select id from claimed_send)
  ),
  'bounced',
  'permanent bounce overrides an earlier delivered observation'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_suppressions
    where tenant_id = '9e140000-0000-4000-8000-000000000001'
      and lifted_at is null
  ),
  1,
  'hard bounce creates one active recipient suppression'
);
select is(
  (
    select state || ':' || suppression_reason
    from public.transactional_email_outbox
    where id = '9e140000-0000-4000-8000-000000000070'
  ),
  'suppressed:hard_bounce',
  'hard bounce also suppresses messages that were already pending'
);
select is(
  (
    select count(*)::integer
    from public.claim_transactional_email_outbox(
      'email-worker-after-bounce',
      'send',
      20,
      120
    ) claim
    where claim.id = '9e140000-0000-4000-8000-000000000070'
  ),
  0,
  'a pre-queued message cannot be claimed after recipient suppression'
);

update public.online_orders
set status = 'ready_for_pickup'
where id = '9e140000-0000-4000-8000-000000000010';

select is(
  (
    select state
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'ready_for_pickup'
  ),
  'suppressed',
  'future milestone is recorded but suppressed after a hard bounce'
);
select is(
  (
    select suppression_reason
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'ready_for_pickup'
  ),
  'hard_bounce',
  'suppressed outbox exposes its exact reason'
);

alter table public.online_orders disable trigger trg_auto_process_paid_online_order;
update public.online_orders
set payment_status = 'paid',
    payment_reference = 'MP-EMAIL-TEST-001',
    paid_at = '2026-07-18T18:05:00Z'
where id = '9e140000-0000-4000-8000-000000000010';
alter table public.online_orders enable trigger trg_auto_process_paid_online_order;

select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'payment_confirmed'
  ),
  1,
  'real payment transition produces one payment-confirmed message'
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'payment_confirmed'
  ),
  'suppressed',
  'payment email also honors the durable suppression list'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'payment_voucher_available'
  ),
  0,
  'payment status does not invent an official operator voucher'
);
select is(
  (
    select count(*)::integer
    from public.transactional_email_outbox
    where order_id = '9e140000-0000-4000-8000-000000000010'
      and message_kind = 'tax_document_issued'
  ),
  0,
  'internal invoice/payment flow does not invent a DTE email'
);

create temp table issued_access_token on commit drop as
select public.issue_online_order_access_token(
  '9e140000-0000-4000-8000-000000000010',
  array['view_order']::text[],
  clock_timestamp() + interval '7 days'
) result;

select is(
  length((select result->>'token' from issued_access_token)),
  43,
  'access-token command returns 256 bits as base64url exactly once'
);
select hasnt_column(
  'public',
  'online_order_access_tokens',
  'token',
  'raw access token is never stored'
);

create temp table public_order_projection on commit drop as
select public.get_public_online_order_by_access_token(
  (select result->>'token' from issued_access_token)
) result;

select is(
  (select result#>>'{order,number}' from public_order_projection),
  'WEB-EMAIL-TEST-001',
  'valid scoped token resolves the redacted order projection'
);
select is(
  (select (result->'order') ? 'customer_email' from public_order_projection),
  false,
  'public token projection exposes no customer email'
);
select is(
  (select (result->'order') ? 'internal_notes' from public_order_projection),
  false,
  'public token projection exposes no internal notes'
);
select is(
  (
    select use_count
    from public.online_order_access_tokens
    where id = ((select result->>'token_id' from issued_access_token))::uuid
  ),
  1::bigint,
  'token use is auditable'
);
select is(
  public.get_public_online_order_by_access_token(repeat('x', 43)),
  null,
  'unknown token returns no order data'
);

select is(
  has_table_privilege('authenticated', 'public.transactional_email_outbox', 'INSERT'),
  false,
  'authenticated clients cannot forge outbox rows'
);
select is(
  has_table_privilege('authenticated', 'public.transactional_email_outbox', 'UPDATE'),
  false,
  'authenticated clients cannot mutate delivery state'
);
select is(
  has_table_privilege('authenticated', 'public.transactional_email_outbox', 'SELECT'),
  true,
  'authenticated staff can read their tenant communication evidence through RLS'
);

select * from finish();
rollback;
