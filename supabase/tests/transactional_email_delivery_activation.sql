begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(32);

select has_table(
  'public',
  'transactional_email_worker_runtime',
  'transactional email worker has a fail-closed runtime gate'
);
select has_table(
  'public',
  'transactional_email_delivery_phase_events',
  'delivery phase changes have an append-only audit ledger'
);
select has_function(
  'public',
  'configure_transactional_email_delivery_phase',
  array['uuid', 'text', 'integer'],
  'service-role delivery phase command exists'
);
select has_function(
  'public',
  'claim_transactional_email_outbox_for_tenant',
  array['uuid', 'text', 'text', 'integer', 'integer'],
  'tenant-scoped worker claim exists'
);
select has_function(
  'public',
  'invoke_transactional_email_worker',
  array[]::text[],
  'cron-safe worker invocation exists'
);
select has_trigger(
  'public',
  'transactional_email_delivery_phase_events',
  'trg_transactional_email_delivery_phase_events_immutable',
  'delivery phase evidence is protected by an immutable trigger'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.configure_transactional_email_delivery_phase(uuid,text,integer)',
    'EXECUTE'
  ),
  'service role can invoke the audited delivery phase command'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.configure_transactional_email_delivery_phase(uuid,text,integer)',
    'EXECUTE'
  ),
  'staff clients cannot change the delivery phase'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.claim_transactional_email_outbox_for_tenant(uuid,text,text,integer,integer)',
    'EXECUTE'
  ),
  'Edge service role can claim the tenant-scoped queue'
);
select ok(
  not has_table_privilege(
    'service_role',
    'public.transactional_email_settings',
    'UPDATE'
  ),
  'Edge service role cannot bypass the audited phase command with a direct settings update'
);
select is(
  (select enabled from public.transactional_email_worker_runtime where singleton),
  false,
  'worker is disabled by default'
);
select is(
  (select tenant_id from public.transactional_email_worker_runtime where singleton),
  null::uuid,
  'disabled worker starts without an authorized tenant'
);

insert into public.tenants (id, shop_name, currency, timezone)
values
  (
    '9e230000-0000-4000-8000-000000000001',
    'Transactional Delivery Tenant One',
    'CLP',
    'America/Santiago'
  ),
  (
    '9e230000-0000-4000-8000-000000000002',
    'Transactional Delivery Tenant Two',
    'CLP',
    'America/Santiago'
  );

insert into public.transactional_email_settings (
  tenant_id,
  enabled,
  delivery_mode,
  from_name,
  from_email,
  reply_to_email,
  public_store_url
)
values
  (
    '9e230000-0000-4000-8000-000000000001',
    false,
    'dry_run',
    'Tenant One Sales',
    'sales-one@example.invalid',
    'sales-one@example.invalid',
    'https://one.example.invalid'
  ),
  (
    '9e230000-0000-4000-8000-000000000002',
    false,
    'dry_run',
    'Tenant Two Sales',
    'sales-two@example.invalid',
    'sales-two@example.invalid',
    'https://two.example.invalid'
  );

delete from vault.secrets
where name = 'transactional_email_worker_secret';

select throws_ok(
  $$
    select public.configure_transactional_email_delivery_phase(
      '9e230000-0000-4000-8000-000000000001',
      'unsupported',
      20
    )
  $$,
  'P0001',
  'Unsupported transactional email delivery phase',
  'unsupported delivery phases fail closed'
);
select throws_ok(
  $$
    select public.configure_transactional_email_delivery_phase(
      '9e230000-0000-4000-8000-000000000001',
      'dry_run',
      20
    )
  $$,
  'P0001',
  'Vault secret transactional_email_worker_secret is required before enabling the worker',
  'worker cannot be enabled before its Vault secret exists'
);
select is(
  (select count(*)::integer from public.transactional_email_delivery_phase_events),
  0,
  'failed phase commands leave no false audit evidence'
);

select vault.create_secret(
  'pg-tap-transactional-worker-secret',
  'transactional_email_worker_secret',
  'Transactional email delivery activation pgTAP fixture'
);

select throws_ok(
  $$
    select public.configure_transactional_email_delivery_phase(
      '9e230000-0000-4000-8000-000000000001',
      'send',
      20
    )
  $$,
  'P0001',
  'Transactional email send phase requires prior dry-run activation for the same tenant',
  'send cannot bypass the reviewed dry-run phase'
);

create temp table delivery_phase_result on commit drop as
select public.configure_transactional_email_delivery_phase(
  '9e230000-0000-4000-8000-000000000001',
  'dry_run',
  7
) as payload;

select is(
  (select payload->>'phase' from delivery_phase_result),
  'dry_run',
  'first reviewed phase command enters dry-run'
);
select is(
  (
    select tenant_id
    from public.transactional_email_worker_runtime
    where singleton
  ),
  '9e230000-0000-4000-8000-000000000001'::uuid,
  'runtime records the one tenant it is authorized to process'
);
select is(
  (
    select enabled::text || ':' || delivery_mode || ':' || batch_size::text
    from public.transactional_email_worker_runtime
    where singleton
  ),
  'true:dry_run:7',
  'dry-run activation updates the complete runtime gate'
);
select is(
  (
    select enabled::text || ':' || delivery_mode
    from public.transactional_email_settings
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  ),
  'true:dry_run',
  'tenant sender settings enter dry-run with the worker'
);
select is(
  (
    select from_phase || ':' || to_phase || ':' || to_batch_size::text
    from public.transactional_email_delivery_phase_events
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  ),
  'disabled:dry_run:7',
  'dry-run activation records exact before/after evidence'
);

select set_config('app.public_order_rpc_in_progress', 'true', true);

insert into public.online_orders (
  id,
  tenant_id,
  order_number,
  customer_email,
  customer_name,
  total,
  delivery_type
)
values
  (
    '9e230000-0000-4000-8000-000000000010',
    '9e230000-0000-4000-8000-000000000001',
    'WEB-DELIVERY-TENANT-ONE',
    'one-customer@example.invalid',
    'Tenant One Customer',
    1000,
    'pickup'
  ),
  (
    '9e230000-0000-4000-8000-000000000020',
    '9e230000-0000-4000-8000-000000000002',
    'WEB-DELIVERY-TENANT-TWO',
    'two-customer@example.invalid',
    'Tenant Two Customer',
    2000,
    'pickup'
  );

select set_config('app.public_order_rpc_in_progress', '', true);

insert into public.transactional_email_outbox (
  id,
  tenant_id,
  order_id,
  source_event_key,
  message_kind,
  template_key,
  recipient_email,
  subject,
  render_payload,
  idempotency_key,
  delivery_mode,
  available_at
)
values
  (
    '9e230000-0000-4000-8000-000000000011',
    '9e230000-0000-4000-8000-000000000001',
    '9e230000-0000-4000-8000-000000000010',
    'delivery-tenant-one',
    'order_received',
    'order_received',
    'one-customer@example.invalid',
    'Tenant one order received',
    '{}'::jsonb,
    'delivery-tenant-one',
    'dry_run',
    '-infinity'::timestamp with time zone
  ),
  (
    '9e230000-0000-4000-8000-000000000021',
    '9e230000-0000-4000-8000-000000000002',
    '9e230000-0000-4000-8000-000000000020',
    'delivery-tenant-two',
    'order_received',
    'order_received',
    'two-customer@example.invalid',
    'Tenant two order received',
    '{}'::jsonb,
    'delivery-tenant-two',
    'dry_run',
    '-infinity'::timestamp with time zone
  ),
  (
    '9e230000-0000-4000-8000-000000000012',
    '9e230000-0000-4000-8000-000000000001',
    '9e230000-0000-4000-8000-000000000010',
    'delivery-tenant-one-suppressed-before-claim',
    'processing',
    'processing',
    'suppressed-customer@example.invalid',
    'Suppressed tenant one message',
    '{}'::jsonb,
    'delivery-tenant-one-suppressed-before-claim',
    'dry_run',
    '-infinity'::timestamp with time zone
  );

insert into public.transactional_email_suppressions (
  tenant_id,
  normalized_email,
  email_sha256,
  reason
) values (
  '9e230000-0000-4000-8000-000000000001',
  'suppressed-customer@example.invalid',
  encode(
    extensions.digest(
      convert_to('suppressed-customer@example.invalid', 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  'manual'
);

select throws_ok(
  $$
    select *
    from public.claim_transactional_email_outbox_for_tenant(
      '9e230000-0000-4000-8000-000000000002',
      'wrong-tenant-worker',
      'dry_run',
      10,
      120
    )
  $$,
  '42501',
  'Transactional email worker runtime does not authorize this tenant and mode',
  'runtime refuses a claim for any tenant other than the reviewed tenant'
);

create temp table tenant_one_claim on commit drop as
select *
from public.claim_transactional_email_outbox_for_tenant(
  '9e230000-0000-4000-8000-000000000001',
  'tenant-one-worker',
  'dry_run',
  10,
  120
);

select is(
  (select count(*)::integer from tenant_one_claim),
  1,
  'tenant-scoped worker claims its own pending message'
);
select is(
  (select tenant_id from tenant_one_claim),
  '9e230000-0000-4000-8000-000000000001'::uuid,
  'every claimed message belongs to the authorized tenant'
);
select is(
  (
    select state || ':' || suppression_reason
    from public.transactional_email_outbox
    where id = '9e230000-0000-4000-8000-000000000012'
  ),
  'suppressed:manual',
  'tenant claim re-checks suppressions created after enqueue'
);
select is(
  (
    select state
    from public.transactional_email_outbox
    where id = '9e230000-0000-4000-8000-000000000021'
  ),
  'pending',
  'foreign tenant message remains untouched'
);

select public.configure_transactional_email_delivery_phase(
  '9e230000-0000-4000-8000-000000000001',
  'send',
  5
);

select is(
  (
    select enabled::text || ':' || delivery_mode || ':' || batch_size::text
    from public.transactional_email_worker_runtime
    where singleton
  ),
  'true:send:5',
  'send activation changes both runtime mode and reviewed batch size'
);
select is(
  (
    select enabled::text || ':' || delivery_mode
    from public.transactional_email_settings
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  ),
  'true:send',
  'send activation changes the tenant delivery snapshot source'
);

select throws_ok(
  $$
    update public.transactional_email_delivery_phase_events
    set source = 'tampered'
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  $$,
  '55000',
  'Transactional email delivery phase events are append-only',
  'delivery phase audit evidence cannot be rewritten'
);

select public.configure_transactional_email_delivery_phase(
  '9e230000-0000-4000-8000-000000000001',
  'disabled',
  5
);

select is(
  (select enabled from public.transactional_email_worker_runtime where singleton),
  false,
  'disabled phase stops the scheduler gate'
);
select is(
  (
    select enabled::text || ':' || delivery_mode
    from public.transactional_email_settings
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  ),
  'false:dry_run',
  'disabled phase also fail-closes tenant delivery settings'
);
select is(
  (
    select string_agg(from_phase || '>' || to_phase, '|' order by occurred_at, id)
    from public.transactional_email_delivery_phase_events
    where tenant_id = '9e230000-0000-4000-8000-000000000001'
  ),
  'disabled>dry_run|dry_run>send|send>disabled',
  'phase ledger preserves the complete reviewed activation sequence'
);

select * from finish();

rollback;
