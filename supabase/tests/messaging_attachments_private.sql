begin;

select plan(57);

select has_table(
  'public',
  'messaging_attachments',
  'messaging attachments have a durable private-object registry'
);
select ok(
  exists (
    select 1 from storage.buckets
    where id = 'chat-attachments'
  ),
  'the dedicated chat attachment bucket exists'
);
select is(
  (select public from storage.buckets where id = 'chat-attachments'),
  false,
  'the attachment bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'chat-attachments'),
  20971520::bigint,
  'the bucket has a 20 MiB hard ceiling'
);
select ok(
  exists (
    select 1 from storage.buckets
    where id = 'messaging-attachment-quarantine'
  ),
  'legacy orphan quarantine has a dedicated bucket'
);
select is(
  (select public from storage.buckets
   where id = 'messaging-attachment-quarantine'),
  false,
  'legacy orphan quarantine is private'
);
select ok(
  exists (
    select 1
    from storage.buckets bucket,
      unnest(bucket.allowed_mime_types) as mime_type
    where bucket.id = 'chat-attachments'
      and mime_type = 'audio/ogg'
  ),
  'safe WhatsApp audio remains supported'
);
select ok(
  exists (
    select 1
    from storage.buckets bucket,
      unnest(bucket.allowed_mime_types) as mime_type
    where bucket.id = 'chat-attachments'
      and mime_type = 'video/mp4'
  ),
  'safe WhatsApp video remains supported'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.messaging_attachments'::regclass
      and conname = 'messaging_attachments_path_check'
  ),
  'registry paths are constrained to tenant/conversation/attachment'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.messaging_attachments'::regclass),
  'attachment registry RLS is enabled'
);
select has_table(
  'public',
  'messaging_legacy_orphan_quarantine_receipts',
  'legacy orphan preservation has a durable no-PII receipt registry'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.messaging_legacy_orphan_quarantine_receipts'::regclass
  ),
  'legacy orphan quarantine receipts have RLS enabled'
);
select ok(
  has_table_privilege('authenticated', 'public.messaging_attachments', 'SELECT'),
  'authenticated readers can inspect visible references'
);
select ok(
  not has_table_privilege('authenticated', 'public.messaging_attachments', 'INSERT'),
  'clients cannot insert attachment registry rows directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.messaging_attachments', 'UPDATE'),
  'clients cannot mutate attachment registry rows directly'
);
select has_function(
  'public',
  'reserve_messaging_attachment',
  array['uuid', 'text', 'text', 'bigint'],
  'attachment reservation uses one canonical RPC'
);
select has_function(
  'public',
  'publish_messaging_attachment',
  array['uuid', 'text'],
  'attachment publication uses one canonical RPC'
);
select has_function(
  'public',
  'fail_messaging_attachment',
  array['uuid', 'text'],
  'failed reservations have an explicit command'
);
select has_function(
  'public',
  'mark_whatsapp_conversation_quote_sent',
  array['uuid', 'uuid', 'uuid', 'text', 'jsonb'],
  'WhatsApp quote evidence uses the conversation-scoped command'
);
select has_function(
  'public',
  'list_legacy_messaging_attachment_candidates',
  array[]::text[],
  'legacy message enumeration is a reviewed maintenance command'
);
select has_function(
  'public',
  'list_legacy_messaging_public_objects',
  array[]::text[],
  'legacy public object enumeration is a reviewed maintenance command'
);
select has_function(
  'public',
  'finalize_legacy_messaging_attachment_backfill',
  array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'bigint', 'text', 'text'],
  'legacy attachment metadata and registry finalize atomically'
);
select has_function(
  'public',
  'finalize_legacy_messaging_orphan_quarantine',
  array['text', 'text', 'bigint', 'timestamp with time zone'],
  'legacy orphans receive a verified private quarantine receipt'
);
select has_function(
  'public',
  'mark_legacy_messaging_orphan_public_deleted',
  array['text', 'text'],
  'public deletion is recorded only after private quarantine'
);
select is(
  (
    select prosecdef from pg_proc
    where oid = 'public.reserve_messaging_attachment(uuid,text,text,bigint)'::regprocedure
  ),
  true,
  'reserve RPC is security definer'
);
select is(
  (
    select prosecdef from pg_proc
    where oid = 'public.publish_messaging_attachment(uuid,text)'::regprocedure
  ),
  true,
  'publish RPC is security definer'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.reserve_messaging_attachment(uuid,text,text,bigint)',
    'EXECUTE'
  ),
  'authenticated callers can reserve after conversation authorization'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.publish_messaging_attachment(uuid,text)',
    'EXECUTE'
  ),
  'authenticated callers can publish their exact reservation'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.fail_messaging_attachment(uuid,text)',
    'EXECUTE'
  ),
  'authenticated callers can fail their exact reservation'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.reserve_messaging_attachment(uuid,text,text,bigint)',
    'EXECUTE'
  ),
  'anonymous callers cannot reserve messaging storage'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.mark_whatsapp_job_quote_sent(uuid,text,jsonb)',
    'EXECUTE'
  ),
  'the legacy job-id-only quote mutation is retired'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.mark_whatsapp_conversation_quote_sent(uuid,uuid,uuid,text,jsonb)',
    'EXECUTE'
  ),
  'only the service pipeline can record verified WhatsApp quote evidence'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.list_legacy_messaging_attachment_candidates()',
    'EXECUTE'
  ),
  'service maintenance can enumerate only reviewed legacy candidates'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.list_legacy_messaging_public_objects()',
    'EXECUTE'
  ),
  'service maintenance can enumerate the narrow legacy public prefixes'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_legacy_messaging_attachment_backfill(uuid,uuid,text,text,text,text,bigint,text,text)',
    'EXECUTE'
  ),
  'service maintenance can atomically finalize a verified copy'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.finalize_legacy_messaging_attachment_backfill(uuid,uuid,text,text,text,text,bigint,text,text)',
    'EXECUTE'
  ),
  'ordinary clients cannot run the legacy backfill command'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_legacy_messaging_orphan_quarantine(text,text,bigint,timestamptz)',
    'EXECUTE'
  ),
  'service maintenance can finalize verified orphan quarantine copies'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.finalize_legacy_messaging_orphan_quarantine(text,text,bigint,timestamptz)',
    'EXECUTE'
  ),
  'ordinary clients cannot finalize orphan quarantine copies'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.mark_legacy_messaging_orphan_public_deleted(text,text)',
    'EXECUTE'
  ),
  'service maintenance can record verified public orphan deletion'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'chat_attachments_insert_reserved'
  ),
  'storage insert requires a matching reservation'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'chat_attachments_select_scoped'
  ),
  'storage reads require an attached visible conversation'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'chat_attachments_delete_failed_own'
  ),
  'storage deletion is limited to failed owned cleanup'
);
select ok(
  position(
    'attachment_id' in
    pg_get_functiondef('public.publish_messaging_attachment(uuid,text)'::regprocedure)
  ) > 0,
  'published messages store the immutable attachment id'
);
select ok(
  position(
    '''url''' in
    pg_get_functiondef('public.publish_messaging_attachment(uuid,text)'::regprocedure)
  ) = 0,
  'published messages persist no URL metadata'
);
select ok(
  position(
    'messaging_can_write_conversation' in
    pg_get_functiondef(
      'public.messaging_attachment_storage_can_insert(text,text)'::regprocedure
    )
  ) > 0,
  'storage upload uses the canonical writable-conversation boundary'
);
select ok(
  position(
    'messaging_can_write_conversation' in
    pg_get_functiondef(
      'public.reserve_messaging_attachment(uuid,text,text,bigint)'::regprocedure
    )
  ) > 0,
  'reservation uses the canonical writable-conversation boundary'
);
select ok(
  position(
    'v_attachment.status = ''attached''' in
    pg_get_functiondef(
      'public.publish_messaging_attachment(uuid,text)'::regprocedure
    )
  ) < position(
    'messaging_can_write_conversation' in
    pg_get_functiondef(
      'public.publish_messaging_attachment(uuid,text)'::regprocedure
    )
  ),
  'publish replays an attached receipt before enforcing current write state'
);
select ok(
  position(
    'whatsapp_conversation_bindings' in
    pg_get_functiondef(
      'public.mark_whatsapp_conversation_quote_sent(uuid,uuid,uuid,text,jsonb)'::regprocedure
    )
  ) > 0,
  'quote evidence verifies the WhatsApp customer binding'
);
select ok(
  position(
    'transition_mechanic_job_status' in
    pg_get_functiondef(
      'public.mark_whatsapp_conversation_quote_sent(uuid,uuid,uuid,text,jsonb)'::regprocedure
    )
  ) > 0,
  'quote sent lifecycle changes use the canonical Jobs Table transition command'
);
select ok(
  position(
    'download_url' in pg_get_functiondef(
      'public.finalize_legacy_messaging_attachment_backfill(uuid,uuid,text,text,text,text,bigint,text,text)'::regprocedure
    )
  ) > 0,
  'finalization scrubs every legacy URL metadata field'
);
select ok(
  position(
    '''legacy-orphans/''' in pg_get_functiondef(
      'public.finalize_legacy_messaging_orphan_quarantine(text,text,bigint,timestamptz)'::regprocedure
    )
  ) > 0,
  'orphan quarantine paths derive from content hashes without legacy paths'
);

-- Behavioral boundary: archival is terminal for new attachment writes, while
-- an already-committed publish receipt remains replayable after archival.
insert into public.tenants (id, shop_name) values (
  '9f191630-0000-4000-8000-000000000001',
  'Private Messaging Attachment Test Tenant'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '9f191630-0000-4000-8000-000000000091',
  'authenticated',
  'authenticated',
  'attachment-staff@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id', '9f191630-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

-- Auth bootstrap triggers can create a profile and leave transaction-local
-- claims behind. Replace both with the deterministic staff fixture.
delete from public.user_profiles
where user_id = '9f191630-0000-4000-8000-000000000091';

update auth.users
set raw_user_meta_data = jsonb_build_object(
  'tenant_id', '9f191630-0000-4000-8000-000000000001'
)
where id = '9f191630-0000-4000-8000-000000000091';

insert into public.user_profiles (
  user_id, tenant_id, role, permissions, is_active
) values (
  '9f191630-0000-4000-8000-000000000091',
  '9f191630-0000-4000-8000-000000000001',
  'admin',
  '{}'::jsonb,
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '9f191630-0000-4000-8000-000000000091',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9f191630-0000-4000-8000-000000000091',
  true
);

insert into public.conversations (
  id, tenant_id, type, channel, title, status, created_by
) values
  (
    '9f191630-0000-4000-8000-000000000311',
    '9f191630-0000-4000-8000-000000000001',
    'support', 'website_portal', 'Closed before reserve', 'active',
    '9f191630-0000-4000-8000-000000000091'
  ),
  (
    '9f191630-0000-4000-8000-000000000312',
    '9f191630-0000-4000-8000-000000000001',
    'support', 'website_portal', 'Closed before publish', 'active',
    '9f191630-0000-4000-8000-000000000091'
  ),
  (
    '9f191630-0000-4000-8000-000000000313',
    '9f191630-0000-4000-8000-000000000001',
    'support', 'website_portal', 'Attached before close', 'active',
    '9f191630-0000-4000-8000-000000000091'
  );

update public.conversations
set status = 'resolved'
where id = '9f191630-0000-4000-8000-000000000311';

select throws_ok(
  $$select public.reserve_messaging_attachment(
      '9f191630-0000-4000-8000-000000000311',
      'closed.pdf',
      'application/pdf',
      128
    )$$,
  '42501',
  'Not authorized to attach files to this conversation',
  'resolved conversations reject new attachment reservations'
);

create temporary table attachment_reserved_before_close as
select public.reserve_messaging_attachment(
  '9f191630-0000-4000-8000-000000000312',
  'reserved.pdf',
  'application/pdf',
  128
) as receipt;

insert into storage.objects (bucket_id, name, metadata)
select
  'chat-attachments',
  receipt->>'storage_path',
  jsonb_build_object('size', 128, 'mimetype', 'application/pdf')
from attachment_reserved_before_close;

update public.conversations
set status = 'resolved'
where id = '9f191630-0000-4000-8000-000000000312';

select throws_ok(
  format(
    'select public.publish_messaging_attachment(%L::uuid, null)',
    (select receipt->>'attachment_id' from attachment_reserved_before_close)
  ),
  '55000',
  'Conversation is closed; attachment cannot be published',
  'a reservation cannot publish after its conversation is resolved'
);
select is(
  (
    select attachment.status
    from public.messaging_attachments attachment
    where attachment.id = (
      select (receipt->>'attachment_id')::uuid
      from attachment_reserved_before_close
    )
  ),
  'reserved',
  'failed publish after archival leaves the reservation intact'
);
select is(
  (
    select attachment.message_id
    from public.messaging_attachments attachment
    where attachment.id = (
      select (receipt->>'attachment_id')::uuid
      from attachment_reserved_before_close
    )
  ),
  null::uuid,
  'failed publish after archival creates no attachment message'
);

create temporary table attachment_attached_before_close as
select public.reserve_messaging_attachment(
  '9f191630-0000-4000-8000-000000000313',
  'attached.pdf',
  'application/pdf',
  256
) as reservation;

insert into storage.objects (bucket_id, name, metadata)
select
  'chat-attachments',
  reservation->>'storage_path',
  jsonb_build_object('size', 256, 'mimetype', 'application/pdf')
from attachment_attached_before_close;

alter table attachment_attached_before_close add column publication jsonb;
update attachment_attached_before_close
set publication = public.publish_messaging_attachment(
  (reservation->>'attachment_id')::uuid,
  'Committed before archive'
);

select is(
  (select (publication->>'changed')::boolean
   from attachment_attached_before_close),
  true,
  'an open conversation publishes the reserved attachment exactly once'
);

update public.conversations
set status = 'resolved'
where id = '9f191630-0000-4000-8000-000000000313';

select is(
  (
    select (
      public.publish_messaging_attachment(
        (reservation->>'attachment_id')::uuid,
        'Ignored replay caption'
      )->>'changed'
    )::boolean
    from attachment_attached_before_close
  ),
  false,
  'an attached receipt replays unchanged after the conversation is resolved'
);

select * from finish();
rollback;
