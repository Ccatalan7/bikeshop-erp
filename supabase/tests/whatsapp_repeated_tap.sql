-- A customer who taps the same card button twice repeats the decision that
-- already applied; it is not a refusal (2026-11-08). A different answer after
-- the recorded one is still refused. All data is synthetic and rolled back.
begin;
select plan(9);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name) values
  ('9f032400-0000-4000-8000-000000000001', 'Repeated Tap Test');
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f032400-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'repeated-tap-staff@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f032400-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f032400-0000-4000-8000-000000000091';
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active)
values ('9f032400-0000-4000-8000-000000000091',
  '9f032400-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.customers (id, tenant_id, name, email)
values ('9f032400-0000-4000-8000-000000000111',
  '9f032400-0000-4000-8000-000000000001', 'Repeated Tap Customer',
  'repeated-tap-customer@example.invalid');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, job_type,
  quotation_status, quotation_valid_until, status)
values ('9f032400-0000-4000-8000-000000000215',
  '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000111',
  'TAP-QUOTE', 'quotation', 'pending', now() + interval '7 days', 'PRESUPUESTO');
insert into public.mechanic_job_items (id, tenant_id, job_id, product_name,
  item_type, quantity, unit_price)
values ('9f032400-0000-4000-8000-000000000291',
  '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000215',
  'Servicio cotizado', 'service', 1, 4000);

insert into public.conversations (id, tenant_id, type, channel, title,
  context_type, context_id, status, created_by)
values ('9f032400-0000-4000-8000-000000000312',
  '9f032400-0000-4000-8000-000000000001', 'support', 'whatsapp', 'Repeated tap',
  'job', '9f032400-0000-4000-8000-000000000215', 'active',
  '9f032400-0000-4000-8000-000000000091');
insert into public.whatsapp_channels (id, tenant_id, phone_number_id, display_name, is_active)
values ('9f032400-0000-4000-8000-000000000611',
  '9f032400-0000-4000-8000-000000000001', 'repeated-tap-phone', 'Synthetic', true);
insert into public.whatsapp_conversation_bindings (id, tenant_id, conversation_id,
  channel_id, customer_id, external_wa_id, external_phone_number, contact_name)
values ('9f032400-0000-4000-8000-000000000621',
  '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000312',
  '9f032400-0000-4000-8000-000000000611', '9f032400-0000-4000-8000-000000000111',
  '56900000001', '56900000001', 'Repeated Tap Customer');

-- Three taps on one card: approve, approve again, then reject.
insert into public.whatsapp_webhook_events (id, tenant_id, channel_id, event_key,
  event_type, direction, payload)
select ('9f032400-0000-4000-8000-00000000063' || n)::uuid,
  '9f032400-0000-4000-8000-000000000001', '9f032400-0000-4000-8000-000000000611',
  'message:wamid.tap.' || n, 'message', 'inbound',
  jsonb_build_object('message', jsonb_build_object(
    'id', 'wamid.tap.' || n, 'from', '56900000001',
    'context', jsonb_build_object('id', 'wamid.tap.card'),
    'interactive', jsonb_build_object('button_reply', jsonb_build_object(
      'id', 'job:9f032400-0000-4000-8000-000000000215:' || action || ':1760000000001'))))
from (values (1, 'approve_quote'), (2, 'approve_quote'), (3, 'reject_quote')) as taps(n, action);

insert into public.messages (id, conversation_id, sender_id, tenant_id, content,
  type, metadata, external_provider, external_message_id, message_direction)
values ('9f032400-0000-4000-8000-000000000440', '9f032400-0000-4000-8000-000000000312',
  '9f032400-0000-4000-8000-000000000091', '9f032400-0000-4000-8000-000000000001',
  'Presupuesto WhatsApp', 'action_request',
  jsonb_build_object(
    'action_type', 'approve_quote', 'action_kind', 'job',
    'target_id', '9f032400-0000-4000-8000-000000000215',
    'jobId', '9f032400-0000-4000-8000-000000000215',
    'action_revision_ms', 1760000000001,
    'action_token', 'job:9f032400-0000-4000-8000-000000000215:approve_quote:1760000000001',
    'action_reject_token', 'job:9f032400-0000-4000-8000-000000000215:reject_quote:1760000000001',
    'action_allowed_actions', jsonb_build_array('approve_quote', 'reject_quote'),
    'status', 'pending'),
  'whatsapp', 'wamid.tap.card', 'outbound');
insert into public.messages (id, conversation_id, sender_id, tenant_id, content,
  type, metadata, external_provider, external_message_id, message_direction)
select ('9f032400-0000-4000-8000-00000000044' || n)::uuid,
  '9f032400-0000-4000-8000-000000000312', null, '9f032400-0000-4000-8000-000000000001',
  label, 'text', '{}'::jsonb, 'whatsapp', 'wamid.tap.' || n, 'inbound'
from (values (1, 'Aprobar presupuesto'), (2, 'Aprobar presupuesto'),
             (3, 'Rechazar presupuesto')) as taps(n, label);

create temporary table tap_results(n int primary key, result jsonb, approved_at timestamptz);
grant all on tap_results to service_role;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select lives_ok(
  $$insert into tap_results(n, result)
    select 1, public.apply_whatsapp_job_action('9f032400-0000-4000-8000-000000000215',
      'approve_quote', 'wamid.tap.1', '{}'::jsonb, 'wamid.tap.card', 1760000000001)$$,
  'the first tap applies');
update tap_results set approved_at = (select approved_at from public.mechanic_jobs
  where id = '9f032400-0000-4000-8000-000000000215') where n = 1;
select is((select quotation_status from public.mechanic_jobs
            where id = '9f032400-0000-4000-8000-000000000215'),
  'approved', 'the first tap approves the quote');

select lives_ok(
  $$insert into tap_results
    select 2, public.apply_whatsapp_job_action('9f032400-0000-4000-8000-000000000215',
      'approve_quote', 'wamid.tap.2', '{}'::jsonb, 'wamid.tap.card', 1760000000001)$$,
  'tapping the same button again is not refused');
select is((select result->>'repeated_answer' from tap_results where n = 2),
  'true', 'the repeat is answered as the same decision');
select is((select metadata #>> '{whatsapp_job_action,response,repeated_answer}'
             from public.messages where id = '9f032400-0000-4000-8000-000000000442'),
  'true', 'the repeated tap keeps its own receipt, so its redelivery returns early');
select is((select approved_at from public.mechanic_jobs
            where id = '9f032400-0000-4000-8000-000000000215'),
  (select approved_at from tap_results where n = 1),
  'the repeat does not touch the job again');
select lives_ok(
  $$select public.apply_whatsapp_job_action('9f032400-0000-4000-8000-000000000215',
      'approve_quote', 'wamid.tap.2', '{}'::jsonb, 'wamid.tap.card', 1760000000001)$$,
  'a redelivery of the repeated tap is idempotent');

select throws_ok(
  $$select public.apply_whatsapp_job_action('9f032400-0000-4000-8000-000000000215',
      'reject_quote', 'wamid.tap.3', '{}'::jsonb, 'wamid.tap.card', 1760000000001)$$,
  '23514', 'WhatsApp action request already has a terminal response',
  'a different answer after the recorded one is still refused');
reset role;
select is((select metadata->>'status' from public.messages
            where id = '9f032400-0000-4000-8000-000000000440'),
  'accepted', 'the card keeps the first answer');

select * from finish();
rollback;
