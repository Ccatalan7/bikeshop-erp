-- The replies a customer gets right after tapping a quote card button
-- (20261108220000): a thank-you once «Aprobar presupuesto» applies, and an
-- invitation to write after «Tengo una consulta». All data is synthetic,
-- rolled back, and dispatch to Meta is disabled in this transaction.
begin;
select plan(11);
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

update public.whatsapp_outbox_runtime set enabled = false;
insert into public.tenants(id, shop_name) values
  ('9f032500-0000-4000-8000-000000000001', 'Card Replies Test');
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f032500-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'card-replies-staff@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f032500-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f032500-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f032500-0000-4000-8000-000000000091', '9f032500-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.customers(id, tenant_id, name, email)
values ('9f032500-0000-4000-8000-000000000111', '9f032500-0000-4000-8000-000000000001',
  'Camila Torres Soto', 'card-replies-customer@example.invalid');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;
insert into public.bikes(id, tenant_id, customer_id, brand, model)
values ('9f032500-0000-4000-8000-000000000141', '9f032500-0000-4000-8000-000000000001',
  '9f032500-0000-4000-8000-000000000111', 'Trek', 'Marlin 7');
set local session_replication_role = origin;

insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id, job_number, job_type,
  quotation_status, quotation_valid_until, status, created_by)
values ('9f032500-0000-4000-8000-000000000215', '9f032500-0000-4000-8000-000000000001',
  '9f032500-0000-4000-8000-000000000111', '9f032500-0000-4000-8000-000000000141',
  'REPLY-QUOTE', 'quotation', 'pending', now() + interval '7 days', 'PRESUPUESTO',
  '9f032500-0000-4000-8000-000000000091');
insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price)
values ('9f032500-0000-4000-8000-000000000291', '9f032500-0000-4000-8000-000000000001',
  '9f032500-0000-4000-8000-000000000215', 'Servicio cotizado', 'service', 1, 4000);

insert into public.conversations(id, tenant_id, type, channel, title, context_type, context_id,
  status, created_by)
values ('9f032500-0000-4000-8000-000000000312', '9f032500-0000-4000-8000-000000000001',
  'support', 'whatsapp', 'Card replies', 'job', '9f032500-0000-4000-8000-000000000215',
  'active', '9f032500-0000-4000-8000-000000000091');
insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active)
values ('9f032500-0000-4000-8000-000000000611', '9f032500-0000-4000-8000-000000000001',
  'card-replies-phone', 'Synthetic', true);
insert into public.whatsapp_conversation_bindings(id, tenant_id, conversation_id, channel_id,
  customer_id, external_wa_id, external_phone_number, contact_name)
values ('9f032500-0000-4000-8000-000000000621', '9f032500-0000-4000-8000-000000000001',
  '9f032500-0000-4000-8000-000000000312', '9f032500-0000-4000-8000-000000000611',
  '9f032500-0000-4000-8000-000000000111', '56900000002', '56900000002', 'Camila Torres Soto');

-- The quote card the notice left, and the approve tap's event.
insert into public.messages(id, conversation_id, sender_id, tenant_id, content, type, metadata,
  external_provider, external_message_id, message_direction)
values ('9f032500-0000-4000-8000-000000000440', '9f032500-0000-4000-8000-000000000312',
  '9f032500-0000-4000-8000-000000000091', '9f032500-0000-4000-8000-000000000001',
  'Presupuesto', 'action_request',
  jsonb_build_object(
    'template_name', 'taller_presupuesto_pdf_v1',
    'action_type', 'approve_quote', 'action_kind', 'job',
    'target_id', '9f032500-0000-4000-8000-000000000215',
    'jobId', '9f032500-0000-4000-8000-000000000215',
    'action_revision_ms', 1760000000001,
    'action_token', 'job:9f032500-0000-4000-8000-000000000215:approve_quote:1760000000001',
    'action_reject_token', 'job:9f032500-0000-4000-8000-000000000215:reject_quote:1760000000001',
    'action_allowed_actions', jsonb_build_array('approve_quote', 'reject_quote'),
    'status', 'pending'),
  'whatsapp', 'wamid.reply.card', 'outbound');

insert into public.whatsapp_webhook_events(id, tenant_id, channel_id, event_key, event_type,
  direction, payload)
select ('9f032500-0000-4000-8000-00000000063' || n)::uuid,
  '9f032500-0000-4000-8000-000000000001', '9f032500-0000-4000-8000-000000000611',
  'message:wamid.reply.tap.' || n, 'message', 'inbound',
  jsonb_build_object('message', jsonb_build_object(
    'id', 'wamid.reply.tap.' || n, 'from', '56900000002',
    'context', jsonb_build_object('id', 'wamid.reply.card'),
    'interactive', jsonb_build_object('button_reply', jsonb_build_object(
      'id', 'job:9f032500-0000-4000-8000-000000000215:approve_quote:1760000000001'))))
from (values (1), (2)) as taps(n);

create temporary table reply_inbound(n int primary key, message_id uuid);
grant all on reply_inbound to service_role;

-- Two approve taps, stored as the ingest stores them.
insert into public.messages(id, conversation_id, sender_id, tenant_id, content, type, metadata,
  external_provider, external_message_id, message_direction)
select ('9f032500-0000-4000-8000-00000000044' || n)::uuid,
  '9f032500-0000-4000-8000-000000000312', null, '9f032500-0000-4000-8000-000000000001',
  'Aprobar presupuesto', 'text',
  jsonb_build_object('raw_payload', jsonb_build_object('message', jsonb_build_object(
    'id', 'wamid.reply.tap.' || n,
    'context', jsonb_build_object('id', 'wamid.reply.card'),
    'interactive', jsonb_build_object('button_reply', jsonb_build_object(
      'id', 'job:9f032500-0000-4000-8000-000000000215:approve_quote:1760000000001'))))),
  'whatsapp', 'wamid.reply.tap.' || n, 'inbound'
from (values (1), (2)) as taps(n);

select is((select count(*)::integer from public.messages
            where conversation_id = '9f032500-0000-4000-8000-000000000312'
              and message_direction = 'outbound' and type = 'text'), 0,
  'an approve tap by itself sends nothing before it applies');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select lives_ok(
  $$select public.apply_whatsapp_job_action('9f032500-0000-4000-8000-000000000215',
      'approve_quote', 'wamid.reply.tap.1', '{}'::jsonb, 'wamid.reply.card', 1760000000001)$$,
  'the approval applies');
select lives_ok(
  $$select public.apply_whatsapp_job_action('9f032500-0000-4000-8000-000000000215',
      'approve_quote', 'wamid.reply.tap.2', '{}'::jsonb, 'wamid.reply.card', 1760000000001)$$,
  'a second tap is the same decision');
reset role;
select set_config('request.jwt.claims', '{}', true);

select is((select string_agg(content, ' | ') from public.messages
            where conversation_id = '9f032500-0000-4000-8000-000000000312'
              and message_direction = 'outbound' and type = 'text'),
  'Gracias, Camila, quedó aprobado. Ya nos ponemos manos a la obra con tu Trek Marlin 7 y te avisamos por aquí apenas terminemos.',
  'one thank-you goes out, with the first name and the bike, and the second tap sends no other');
select is((select o.state || '|' || (o.request->>'type') || '|' || o.actor_id::text
             from public.whatsapp_outbox o
             join public.messages m on m.id = o.message_id
            where m.conversation_id = '9f032500-0000-4000-8000-000000000312'
              and m.message_direction = 'outbound' and m.type = 'text'),
  'queued|text|9f032500-0000-4000-8000-000000000091',
  'it waits in the outbox as a plain message from whoever runs the job');
select is((select quotation_status from public.mechanic_jobs
            where id = '9f032500-0000-4000-8000-000000000215'),
  'approved', 'the quote is approved');

-- «Tengo una consulta» on the same card.
insert into public.messages(id, conversation_id, sender_id, tenant_id, content, type, metadata,
  external_provider, external_message_id, message_direction)
values ('9f032500-0000-4000-8000-000000000450', '9f032500-0000-4000-8000-000000000312', null,
  '9f032500-0000-4000-8000-000000000001', 'Tengo una consulta', 'text',
  jsonb_build_object('raw_payload', jsonb_build_object('message', jsonb_build_object(
    'id', 'wamid.reply.question',
    'context', jsonb_build_object('id', 'wamid.reply.card'),
    'button', jsonb_build_object('payload', 'respuesta:1', 'text', 'Tengo una consulta')))),
  'whatsapp', 'wamid.reply.question', 'inbound');

select is((select m.content from public.messages m
            where m.conversation_id = '9f032500-0000-4000-8000-000000000312'
              and m.message_direction = 'outbound' and m.type = 'text'
              and m.metadata->>'client_message_id' = 'card-reply:wamid.reply.question'),
  'Claro, Camila. Cuéntanos tu consulta por aquí y te respondemos lo antes posible.',
  'the question gets an invitation to write');
select ok((select m.message_sequence from public.messages m
            where m.conversation_id = '9f032500-0000-4000-8000-000000000312'
              and m.metadata->>'client_message_id' = 'card-reply:wamid.reply.question')
          > (select message_sequence from public.messages
              where id = '9f032500-0000-4000-8000-000000000450'),
  'the reply sits under the customer''s message in the chat');

-- Nothing else answers by itself.
insert into public.messages(id, conversation_id, sender_id, tenant_id, content, type, metadata,
  external_provider, external_message_id, message_direction)
values
  ('9f032500-0000-4000-8000-000000000451', '9f032500-0000-4000-8000-000000000312', null,
   '9f032500-0000-4000-8000-000000000001', 'Hola, ¿a qué hora cierran?', 'text',
   jsonb_build_object('raw_payload', jsonb_build_object('message', jsonb_build_object(
     'id', 'wamid.reply.plain', 'text', jsonb_build_object('body', 'Hola')))),
   'whatsapp', 'wamid.reply.plain', 'inbound'),
  ('9f032500-0000-4000-8000-000000000452', '9f032500-0000-4000-8000-000000000312', null,
   '9f032500-0000-4000-8000-000000000001', 'Tengo una consulta', 'text',
   jsonb_build_object('raw_payload', jsonb_build_object('message', jsonb_build_object(
     'id', 'wamid.reply.other-card',
     'context', jsonb_build_object('id', 'wamid.not-a-quote-card'),
     'button', jsonb_build_object('payload', 'respuesta:1', 'text', 'Tengo una consulta')))),
   'whatsapp', 'wamid.reply.other-card', 'inbound');
select is((select count(*)::integer from public.messages
            where conversation_id = '9f032500-0000-4000-8000-000000000312'
              and message_direction = 'outbound' and type = 'text'), 2,
  'a plain message and a reply to another card get no automatic answer');

select ok(not has_function_privilege('authenticated',
    'public.whatsapp_card_reply_internal(uuid,uuid,uuid,text,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.whatsapp_card_reply_internal(uuid,uuid,uuid,text,uuid,text,text)', 'EXECUTE'),
  'the reply helper is closed to every caller role');
select ok(has_function_privilege('service_role',
    'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE'),
  'only the service applies a WhatsApp job action');

select * from finish();
rollback;
