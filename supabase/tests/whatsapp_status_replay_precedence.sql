begin;

select plan(9);

insert into public.tenants (id, shop_name)
values ('99999999-9999-4999-8999-999999999999', 'WhatsApp Status Test Tenant');

insert into public.whatsapp_channels (
  id,
  tenant_id,
  phone_number_id,
  business_account_id,
  display_name,
  display_phone_number,
  is_active
)
values (
  '99999999-0001-4999-8999-999999999999',
  '99999999-9999-4999-8999-999999999999',
  'status-test-phone-number',
  'status-test-business',
  'Status Test Channel',
  '+56900000000',
  true
);

insert into public.conversations (
  id,
  tenant_id,
  type,
  title,
  status,
  created_by
)
values (
  '99999999-0002-4999-8999-999999999999',
  '99999999-9999-4999-8999-999999999999',
  'support',
  'WhatsApp status test',
  'active',
  null
);

select is(
  public.record_whatsapp_message_status(
    'status-test-phone-number',
    'wamid.status-precedence-test',
    'delivered',
    '{"status":"delivered","timestamp":"100"}'::jsonb
  )->>'status_applied',
  'false',
  'status webhook before message row is stored but not applied'
);

select is(
  public.record_whatsapp_message_status(
    'status-test-phone-number',
    'wamid.status-precedence-test',
    'sent',
    '{"status":"sent","timestamp":"101"}'::jsonb
  )->>'status',
  'delivered',
  'later sent webhook does not outrank earlier delivered webhook'
);

insert into public.messages (
  id,
  conversation_id,
  tenant_id,
  content,
  type,
  metadata,
  external_provider,
  external_message_id,
  message_direction,
  external_status,
  created_at
)
values (
  '99999999-0003-4999-8999-999999999999',
  '99999999-0002-4999-8999-999999999999',
  '99999999-9999-4999-8999-999999999999',
  'status test outbound',
  'text',
  '{"provider":"whatsapp","channel":"whatsapp"}'::jsonb,
  'whatsapp',
  'wamid.status-precedence-test',
  'outbound',
  'accepted',
  now()
);

select is(
  public.replay_whatsapp_message_status('wamid.status-precedence-test')->>'status',
  'delivered',
  'replay applies strongest stored status after message row exists'
);

select is(
  (select external_status from public.messages where id = '99999999-0003-4999-8999-999999999999'),
  'delivered',
  'message external_status is delivered after replay'
);

select is(
  public.record_whatsapp_message_status(
    'status-test-phone-number',
    'wamid.status-precedence-test',
    'failed',
    '{"status":"failed","timestamp":"102"}'::jsonb
  )->>'status',
  'delivered',
  'a late failed webhook does not downgrade delivered evidence'
);

select is(
  (select external_status from public.messages where id = '99999999-0003-4999-8999-999999999999'),
  'delivered',
  'message projection remains delivered after a late failed webhook'
);

select is(
  public.record_whatsapp_message_status(
    'status-test-phone-number',
    'wamid.status-precedence-test',
    'read',
    '{"status":"read","timestamp":"103"}'::jsonb
  )->>'status',
  'read',
  'read webhook upgrades delivered message to read'
);

select is(
  public.record_whatsapp_message_status(
    'status-test-phone-number',
    'wamid.status-precedence-test',
    'delivered',
    '{"status":"delivered","timestamp":"104"}'::jsonb
  )->>'status',
  'read',
  'later delivered webhook does not downgrade read message'
);

select is(
  (select metadata->>'whatsapp_status' from public.messages where id = '99999999-0003-4999-8999-999999999999'),
  'read',
  'message metadata keeps the strongest WhatsApp status'
);

select * from finish();

rollback;
