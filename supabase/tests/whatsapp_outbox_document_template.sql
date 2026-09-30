begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- A WhatsApp template with a PDF header (documento_adjunto_v1) goes through
-- the durable outbox like a document: the private reservation is required,
-- bound to the message, and the row is a file. All data is synthetic, rolled
-- back, and dispatch is disabled in this transaction.
update public.whatsapp_outbox_runtime set enabled = false;
insert into public.tenants(id, shop_name) values
  ('9f0322aa-0000-4000-8000-000000000001', 'Document Template A');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('9f0322aa-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'document-template-test@example.invalid', '', now(), '{}',
  '{"tenant_id":"9f0322aa-0000-4000-8000-000000000001"}', now(), now());
delete from public.user_profiles where user_id = '9f0322aa-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id, tenant_id, role, permissions, is_active)
values ('9f0322aa-0000-4000-8000-000000000091', '9f0322aa-0000-4000-8000-000000000001', 'admin', '{}', true);
insert into public.whatsapp_channels(id, tenant_id, phone_number_id, display_name, is_active)
values ('9f0322aa-0000-4000-8000-000000000131', '9f0322aa-0000-4000-8000-000000000001', 'document-template-test', 'Synthetic', true);
insert into public.conversations(id, tenant_id, type, channel, counterparty_type, title, status)
values
  ('9f0322aa-0000-4000-8000-000000000141', '9f0322aa-0000-4000-8000-000000000001', 'support', 'whatsapp', 'customer', 'Synthetic', 'active'),
  ('9f0322aa-0000-4000-8000-000000000142', '9f0322aa-0000-4000-8000-000000000001', 'support', 'whatsapp', 'customer', 'Other chat', 'active');
insert into public.messaging_attachments(id, tenant_id, conversation_id, storage_bucket,
  storage_path, original_filename, extension, declared_mime_type, size_bytes, status, created_by)
values
  ('9f0322aa-0000-4000-8000-000000000151', '9f0322aa-0000-4000-8000-000000000001',
   '9f0322aa-0000-4000-8000-000000000141', 'chat-attachments',
   '9f0322aa-0000-4000-8000-000000000001/9f0322aa-0000-4000-8000-000000000141/9f0322aa-0000-4000-8000-000000000151.pdf',
   'presupuesto.pdf', 'pdf', 'application/pdf', 1200, 'reserved', '9f0322aa-0000-4000-8000-000000000091'),
  ('9f0322aa-0000-4000-8000-000000000152', '9f0322aa-0000-4000-8000-000000000001',
   '9f0322aa-0000-4000-8000-000000000142', 'chat-attachments',
   '9f0322aa-0000-4000-8000-000000000001/9f0322aa-0000-4000-8000-000000000142/9f0322aa-0000-4000-8000-000000000152.pdf',
   'ajeno.pdf', 'pdf', 'application/pdf', 1200, 'reserved', '9f0322aa-0000-4000-8000-000000000091');
create temporary table document_template_receipts(kind text, receipt jsonb);
grant all on document_template_receipts to authenticated, service_role;
create function pg_temp.document_template_request(p_key text, p_attachment text default null)
returns jsonb language sql immutable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'conversationId', '9f0322aa-0000-4000-8000-000000000141',
    'phoneNumber', '+56911113333', 'phoneNumberId', 'document-template-test',
    'type', 'template', 'templateName', 'documento_adjunto_v1',
    'templateLanguage', 'es_CL', 'attachmentId', p_attachment,
    'caption', 'Hola Claudio, te enviamos el documento adjunto desde Viñabike.',
    'metadata', jsonb_build_object('client_message_id', p_key,
      'template_purpose', 'document_attached')));
$$;

select set_config('request.jwt.claims', '{"sub":"9f0322aa-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '9f0322aa-0000-4000-8000-000000000091', true);
set local role authenticated;
select lives_ok($$insert into document_template_receipts values ('pdf',
  public.enqueue_whatsapp_message_v1(pg_temp.document_template_request('pdf', '9f0322aa-0000-4000-8000-000000000151')))$$,
  'a template with its reserved PDF is accepted');
select lives_ok($$insert into document_template_receipts values ('text',
  public.enqueue_whatsapp_message_v1(pg_temp.document_template_request('text')))$$,
  'a template without a file keeps working');
select throws_ok($$select public.enqueue_whatsapp_message_v1(
  pg_temp.document_template_request('foreign', '9f0322aa-0000-4000-8000-000000000152'))$$,
  '42501', 'Sendable private attachment required',
  'a PDF reserved for another chat cannot ride on this template');
reset role;

select is((select type from public.messages
  where id = (select (receipt->>'message_id')::uuid from document_template_receipts where kind = 'pdf')),
  'file', 'the template with a PDF is a file in the inbox');
select is((select status || ':' || (message_id = (select (receipt->>'message_id')::uuid
    from document_template_receipts where kind = 'pdf'))::text
  from public.messaging_attachments where id = '9f0322aa-0000-4000-8000-000000000151'),
  'attached:true', 'the reservation is bound to that message');
select is((select metadata->>'attachment_id' from public.messages
  where id = (select (receipt->>'message_id')::uuid from document_template_receipts where kind = 'pdf')),
  '9f0322aa-0000-4000-8000-000000000151', 'the durable row names its private file');
select is((select content from public.messages
  where id = (select (receipt->>'message_id')::uuid from document_template_receipts where kind = 'pdf')),
  'Hola Claudio, te enviamos el documento adjunto desde Viñabike.',
  'the inbox shows the template text as the file caption');
select is((select type from public.messages
  where id = (select (receipt->>'message_id')::uuid from document_template_receipts where kind = 'text')),
  'text', 'a template without a file stays a text row');
select is((select status from public.messaging_attachments where id = '9f0322aa-0000-4000-8000-000000000152'),
  'reserved', 'the foreign reservation was not touched');
select * from finish();
rollback;
