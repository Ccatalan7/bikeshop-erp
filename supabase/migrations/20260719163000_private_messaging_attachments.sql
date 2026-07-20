-- Private, tenant-scoped attachment contract for Messaging.
--
-- New messages never persist public or signed URLs. A client first reserves a
-- canonical object path, uploads exactly that object, then publishes the
-- message through a SECURITY DEFINER RPC which verifies the stored bytes.

begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'chat-attachments',
  'chat-attachments',
  false,
  20971520,
  array[
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'video/mp4',
    'video/3gpp',
    'audio/mpeg',
    'audio/ogg',
    'audio/mp4',
    'audio/aac'
  ]::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Unreferenced legacy objects are never deleted merely because no current
-- message points at them. Preserve exact bytes first in a service-only private
-- quarantine whose object names are content hashes, never old paths or PII.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'messaging-attachment-quarantine',
  'messaging-attachment-quarantine',
  false,
  67108864,
  null
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.messaging_attachments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  storage_bucket text not null default 'chat-attachments',
  storage_path text not null,
  original_filename text not null,
  extension text not null,
  declared_mime_type text not null,
  size_bytes bigint not null,
  sha256 text,
  status text not null default 'reserved',
  failure_code text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  attached_at timestamptz,
  failed_at timestamptz,
  constraint messaging_attachments_storage_object_unique
    unique (storage_bucket, storage_path),
  constraint messaging_attachments_message_unique unique (message_id),
  constraint messaging_attachments_bucket_check
    check (storage_bucket = 'chat-attachments'),
  constraint messaging_attachments_status_check
    check (status in ('reserved', 'attached', 'failed', 'quarantined')),
  constraint messaging_attachments_filename_check
    check (
      char_length(original_filename) between 1 and 200
      and original_filename !~ E'[/\\\\\\x00-\\x1f\\x7f]'
    ),
  constraint messaging_attachments_extension_check
    check (extension in (
      'jpg', 'jpeg', 'png', 'gif', 'webp',
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt',
      'mp4', '3gp', 'mp3', 'ogg', 'm4a', 'aac'
    )),
  constraint messaging_attachments_mime_extension_check
    check (
      (extension in ('jpg', 'jpeg') and declared_mime_type = 'image/jpeg')
      or (extension = 'png' and declared_mime_type = 'image/png')
      or (extension = 'gif' and declared_mime_type = 'image/gif')
      or (extension = 'webp' and declared_mime_type = 'image/webp')
      or (extension = 'pdf' and declared_mime_type = 'application/pdf')
      or (extension = 'doc' and declared_mime_type = 'application/msword')
      or (
        extension = 'docx'
        and declared_mime_type = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
      or (extension = 'xls' and declared_mime_type = 'application/vnd.ms-excel')
      or (
        extension = 'xlsx'
        and declared_mime_type = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      )
      or (extension = 'txt' and declared_mime_type = 'text/plain')
      or (extension = 'mp4' and declared_mime_type = 'video/mp4')
      or (extension = '3gp' and declared_mime_type = 'video/3gpp')
      or (extension = 'mp3' and declared_mime_type = 'audio/mpeg')
      or (extension = 'ogg' and declared_mime_type = 'audio/ogg')
      or (extension = 'm4a' and declared_mime_type = 'audio/mp4')
      or (extension = 'aac' and declared_mime_type = 'audio/aac')
    ),
  constraint messaging_attachments_size_check
    check (
      size_bytes > 0
      and size_bytes <= case
        when declared_mime_type like 'image/%' then 5242880
        when declared_mime_type like 'audio/%' then 16777216
        when declared_mime_type like 'video/%' then 16777216
        when declared_mime_type = 'text/plain' then 2097152
        else 20971520
      end
    ),
  constraint messaging_attachments_sha256_check
    check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  constraint messaging_attachments_path_check
    check (
      storage_path = tenant_id::text || '/' || conversation_id::text || '/'
        || id::text || '.' || extension
    ),
  constraint messaging_attachments_terminal_state_check
    check (
      (status = 'attached' and message_id is not null and attached_at is not null)
      or (status in ('failed', 'quarantined') and failed_at is not null)
      or status = 'reserved'
    )
);

create index if not exists idx_messaging_attachments_conversation_created
  on public.messaging_attachments (conversation_id, created_at desc);

create index if not exists idx_messaging_attachments_reserved_cleanup
  on public.messaging_attachments (created_at)
  where status = 'reserved';

create table if not exists public.messaging_legacy_orphan_quarantine_receipts (
  id uuid primary key default gen_random_uuid(),
  source_bucket text not null default 'vinabike-assets',
  source_path_sha256 text not null unique,
  source_content_sha256 text not null,
  quarantine_bucket text not null default 'messaging-attachment-quarantine',
  quarantine_path text not null,
  size_bytes bigint not null,
  source_created_at timestamptz not null,
  quarantined_at timestamptz not null default now(),
  deleted_from_public_at timestamptz,
  constraint messaging_legacy_orphan_source_bucket_check
    check (source_bucket = 'vinabike-assets'),
  constraint messaging_legacy_orphan_quarantine_bucket_check
    check (quarantine_bucket = 'messaging-attachment-quarantine'),
  constraint messaging_legacy_orphan_source_path_hash_check
    check (source_path_sha256 ~ '^[0-9a-f]{64}$'),
  constraint messaging_legacy_orphan_content_hash_check
    check (source_content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint messaging_legacy_orphan_quarantine_path_check
    check (quarantine_path = 'legacy-orphans/' || source_content_sha256),
  constraint messaging_legacy_orphan_size_check
    check (size_bytes >= 0 and size_bytes <= 67108864)
);

alter table public.messaging_legacy_orphan_quarantine_receipts
  enable row level security;

drop trigger if exists trg_messaging_attachments_updated_at
  on public.messaging_attachments;
create trigger trg_messaging_attachments_updated_at
  before update on public.messaging_attachments
  for each row execute function public.set_updated_at();

alter table public.messaging_attachments enable row level security;

drop policy if exists messaging_attachments_select_scoped
  on public.messaging_attachments;
create policy messaging_attachments_select_scoped
on public.messaging_attachments
for select
to authenticated
using (
  public.messaging_can_read_conversation_messages(conversation_id)
  and exists (
    select 1
    from public.conversations conversation
    where conversation.id = messaging_attachments.conversation_id
      and conversation.tenant_id = messaging_attachments.tenant_id
  )
);

-- Storage policies call these narrow helpers instead of granting clients
-- mutable access to the attachment registry itself.
create or replace function public.messaging_attachment_storage_can_insert(
  p_bucket text,
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_bucket = 'chat-attachments'
    and exists (
      select 1
      from public.messaging_attachments attachment
      join public.conversations conversation
        on conversation.id = attachment.conversation_id
       and conversation.tenant_id = attachment.tenant_id
      where attachment.storage_bucket = p_bucket
        and attachment.storage_path = p_path
        and attachment.status = 'reserved'
        and attachment.created_by = auth.uid()
        and conversation.status in ('pending', 'active')
        and public.messaging_can_write_conversation(
          attachment.conversation_id
        )
    );
$$;

create or replace function public.messaging_attachment_storage_can_read(
  p_bucket text,
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_bucket = 'chat-attachments'
    and exists (
      select 1
      from public.messaging_attachments attachment
      join public.conversations conversation
        on conversation.id = attachment.conversation_id
       and conversation.tenant_id = attachment.tenant_id
      where attachment.storage_bucket = p_bucket
        and attachment.storage_path = p_path
        and attachment.status = 'attached'
        and public.messaging_can_read_conversation_messages(
          attachment.conversation_id
        )
    );
$$;

create or replace function public.messaging_attachment_storage_can_delete(
  p_bucket text,
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_bucket = 'chat-attachments'
    and exists (
      select 1
      from public.messaging_attachments attachment
      where attachment.storage_bucket = p_bucket
        and attachment.storage_path = p_path
        and attachment.status in ('failed', 'quarantined')
        and attachment.created_by = auth.uid()
    );
$$;

drop policy if exists chat_attachments_select_scoped on storage.objects;
drop policy if exists chat_attachments_insert_reserved on storage.objects;
drop policy if exists chat_attachments_update_denied on storage.objects;
drop policy if exists chat_attachments_delete_denied on storage.objects;
drop policy if exists chat_attachments_delete_failed_own on storage.objects;

create policy chat_attachments_select_scoped
on storage.objects
for select
to authenticated
using (
  public.messaging_attachment_storage_can_read(bucket_id, name)
);

create policy chat_attachments_insert_reserved
on storage.objects
for insert
to authenticated
with check (
  public.messaging_attachment_storage_can_insert(bucket_id, name)
);

-- Failed client uploads may be removed through the Storage API, which deletes
-- both the database object row and the underlying bytes. Attached objects and
-- active reservations remain immutable to clients.
create policy chat_attachments_delete_failed_own
on storage.objects
for delete
to authenticated
using (
  public.messaging_attachment_storage_can_delete(bucket_id, name)
);

create or replace function public.reserve_messaging_attachment(
  p_conversation_id uuid,
  p_original_filename text,
  p_declared_mime_type text,
  p_size_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_attachment_id uuid := gen_random_uuid();
  v_filename text;
  v_extension text;
  v_mime text := lower(btrim(coalesce(p_declared_mime_type, '')));
  v_path text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.messaging_can_write_conversation(p_conversation_id) then
    raise exception 'Not authorized to attach files to this conversation'
      using errcode = '42501';
  end if;

  select conversation.tenant_id
  into v_tenant_id
  from public.conversations conversation
  where conversation.id = p_conversation_id
    and conversation.status in ('pending', 'active')
  for share;

  if not found then
    raise exception 'Conversation not found or is closed' using errcode = 'P0002';
  end if;

  v_filename := left(
    regexp_replace(
      btrim(coalesce(p_original_filename, '')),
      E'[/\\\\\\x00-\\x1f\\x7f]+',
      '_',
      'g'
    ),
    200
  );
  v_extension := lower(substring(v_filename from '\.([^.]+)$'));

  if nullif(v_filename, '') is null or nullif(v_extension, '') is null then
    raise exception 'Attachment filename must include an extension'
      using errcode = '22023';
  end if;

  v_path := v_tenant_id::text || '/' || p_conversation_id::text || '/'
    || v_attachment_id::text || '.' || v_extension;

  -- The table constraints are the single source of truth for MIME, extension
  -- and bounded-size validation. Constraint failures are deterministic and no
  -- storage path is exposed before they pass.
  insert into public.messaging_attachments (
    id,
    tenant_id,
    conversation_id,
    storage_path,
    original_filename,
    extension,
    declared_mime_type,
    size_bytes,
    created_by
  ) values (
    v_attachment_id,
    v_tenant_id,
    p_conversation_id,
    v_path,
    v_filename,
    v_extension,
    v_mime,
    p_size_bytes,
    auth.uid()
  );

  return jsonb_build_object(
    'attachment_id', v_attachment_id,
    'conversation_id', p_conversation_id,
    'storage_bucket', 'chat-attachments',
    'storage_path', v_path,
    'original_filename', v_filename,
    'extension', v_extension,
    'content_type', v_mime,
    'size_bytes', p_size_bytes
  );
end;
$$;

create or replace function public.publish_messaging_attachment(
  p_attachment_id uuid,
  p_caption text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_attachment public.messaging_attachments%rowtype;
  v_object record;
  v_message_id uuid;
  v_caption text := nullif(btrim(coalesce(p_caption, '')), '');
  v_object_size bigint;
  v_object_mime text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select attachment.*
  into v_attachment
  from public.messaging_attachments attachment
  where attachment.id = p_attachment_id
  for update;

  if not found then
    raise exception 'Attachment reservation not found' using errcode = 'P0002';
  end if;

  if v_attachment.created_by is distinct from auth.uid()
     or not public.messaging_can_read_conversation_messages(
       v_attachment.conversation_id
     ) then
    raise exception 'Not authorized to publish this attachment'
      using errcode = '42501';
  end if;

  if v_attachment.status = 'attached' then
    return jsonb_build_object(
      'attachment_id', v_attachment.id,
      'message_id', v_attachment.message_id,
      'changed', false
    );
  end if;

  if not public.messaging_can_write_conversation(
    v_attachment.conversation_id
  ) then
    raise exception 'Conversation is closed; attachment cannot be published'
      using errcode = '55000';
  end if;

  -- Lock the parent status through message creation. A reservation made while
  -- open must not become publishable after another user archives the chat.
  perform 1
  from public.conversations conversation
  where conversation.id = v_attachment.conversation_id
    and conversation.tenant_id = v_attachment.tenant_id
    and conversation.status in ('pending', 'active')
  for share;

  if not found then
    raise exception 'Conversation is closed; attachment cannot be published'
      using errcode = '55000';
  end if;

  if v_attachment.status <> 'reserved' then
    raise exception 'Attachment reservation is not publishable'
      using errcode = '23514';
  end if;

  select object.metadata
  into v_object
  from storage.objects object
  where object.bucket_id = v_attachment.storage_bucket
    and object.name = v_attachment.storage_path;

  if not found then
    raise exception 'Uploaded attachment object not found'
      using errcode = 'P0002';
  end if;

  begin
    v_object_size := nullif(v_object.metadata->>'size', '')::bigint;
  exception when invalid_text_representation then
    v_object_size := null;
  end;
  v_object_mime := lower(coalesce(
    nullif(v_object.metadata->>'mimetype', ''),
    nullif(v_object.metadata->>'contentType', ''),
    ''
  ));

  if v_object_size is distinct from v_attachment.size_bytes
     or v_object_mime is distinct from v_attachment.declared_mime_type then
    update public.messaging_attachments
    set status = 'quarantined',
        failure_code = 'stored_object_contract_mismatch',
        failed_at = now()
    where id = v_attachment.id;
    raise exception 'Uploaded attachment does not match its reservation'
      using errcode = '23514';
  end if;

  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    metadata
  ) values (
    v_attachment.conversation_id,
    auth.uid(),
    v_attachment.tenant_id,
    coalesce(v_caption, v_attachment.original_filename),
    case
      when v_attachment.declared_mime_type like 'image/%' then 'image'
      else 'file'
    end,
    jsonb_build_object(
      'attachment_id', v_attachment.id,
      'storage_bucket', v_attachment.storage_bucket,
      'storage_path', v_attachment.storage_path,
      'filename', v_attachment.original_filename,
      'extension', v_attachment.extension,
      'content_type', v_attachment.declared_mime_type,
      'size_bytes', v_attachment.size_bytes,
      'attachment_access', 'private_signed_runtime'
    )
  ) returning id into v_message_id;

  update public.messaging_attachments
  set status = 'attached',
      message_id = v_message_id,
      attached_at = now(),
      failure_code = null,
      failed_at = null
  where id = v_attachment.id;

  return jsonb_build_object(
    'attachment_id', v_attachment.id,
    'message_id', v_message_id,
    'changed', true
  );
end;
$$;

create or replace function public.fail_messaging_attachment(
  p_attachment_id uuid,
  p_failure_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_attachment public.messaging_attachments%rowtype;
  v_failure_code text := left(
    regexp_replace(
      lower(btrim(coalesce(p_failure_code, 'upload_failed'))),
      '[^a-z0-9_.-]+',
      '_',
      'g'
    ),
    120
  );
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select attachment.*
  into v_attachment
  from public.messaging_attachments attachment
  where attachment.id = p_attachment_id
  for update;

  if not found then
    return jsonb_build_object('attachment_id', p_attachment_id, 'changed', false);
  end if;

  if v_attachment.created_by is distinct from auth.uid()
     or not public.messaging_can_read_conversation_messages(
       v_attachment.conversation_id
     ) then
    raise exception 'Not authorized to fail this attachment'
      using errcode = '42501';
  end if;

  if v_attachment.status = 'attached' then
    raise exception 'Published attachments cannot be failed'
      using errcode = '23514';
  end if;

  if v_attachment.status in ('failed', 'quarantined') then
    return jsonb_build_object(
      'attachment_id', v_attachment.id,
      'status', v_attachment.status,
      'changed', false
    );
  end if;

  update public.messaging_attachments
  set status = 'failed',
      failure_code = coalesce(nullif(v_failure_code, ''), 'upload_failed'),
      failed_at = now()
  where id = v_attachment.id;

  return jsonb_build_object(
    'attachment_id', v_attachment.id,
    'status', 'failed',
    'changed', true
  );
end;
$$;

-- Service-only helpers for the one-shot migration of the historical public
-- `vinabike-assets/chat` and `vinabike-assets/whatsapp-media` objects. They
-- deliberately return opaque identifiers and paths only to the maintenance
-- process; no authenticated application role can enumerate this data.
create or replace function public.messaging_legacy_attachment_urls(
  p_metadata jsonb,
  p_content text,
  p_message_type text
)
returns setof text
language sql
immutable
set search_path = public, pg_temp
as $$
  select distinct btrim(candidate.value)
  from (
    values
      (p_metadata->>'url'),
      (p_metadata->>'media_url'),
      (p_metadata->>'image_url'),
      (p_metadata->>'file_url'),
      (p_metadata->>'documentUrl'),
      (p_metadata->>'document_url'),
      (p_metadata->>'storage_url'),
      (p_metadata->>'public_url'),
      (p_metadata->>'whatsapp_media_url'),
      (p_metadata->>'download_url'),
      (case when p_message_type in ('image', 'file') then p_content end)
  ) as candidate(value)
  where nullif(btrim(candidate.value), '') is not null
    and btrim(candidate.value) ~
      '^https?://xzdvtzdqjeyqxnkqprtf\.supabase\.co/storage/v1/object/public/vinabike-assets/(chat|whatsapp-media)/[^?#]+([?#].*)?$';
$$;

create or replace function public.list_legacy_messaging_attachment_candidates()
returns table (
  message_id uuid,
  tenant_id uuid,
  conversation_id uuid,
  legacy_url text,
  distinct_legacy_url_count bigint,
  message_type text,
  message_created_at timestamptz,
  metadata jsonb
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    message.id,
    message.tenant_id,
    message.conversation_id,
    candidate.legacy_url,
    candidate.distinct_legacy_url_count,
    message.type,
    message.created_at,
    message.metadata
  from public.messages message
  cross join lateral (
    select
      min(url) as legacy_url,
      count(distinct url) as distinct_legacy_url_count
    from public.messaging_legacy_attachment_urls(
      coalesce(message.metadata, '{}'::jsonb),
      message.content,
      message.type
    ) url
  ) candidate
  where candidate.legacy_url is not null
  order by message.created_at, message.id;
$$;

create or replace function public.list_legacy_messaging_public_objects()
returns table (
  storage_path text,
  object_created_at timestamptz,
  object_updated_at timestamptz,
  object_metadata jsonb
)
language sql
stable
security definer
set search_path = public, storage, pg_temp
as $$
  select
    object.name,
    object.created_at,
    object.updated_at,
    coalesce(object.metadata, '{}'::jsonb)
  from storage.objects object
  where object.bucket_id = 'vinabike-assets'
    and (
      object.name like 'chat/%'
      or object.name like 'whatsapp-media/%'
    )
  order by object.created_at, object.id;
$$;

create or replace function public.finalize_legacy_messaging_orphan_quarantine(
  p_source_path_sha256 text,
  p_source_content_sha256 text,
  p_size_bytes bigint,
  p_source_created_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_existing public.messaging_legacy_orphan_quarantine_receipts%rowtype;
  v_quarantine_path text := 'legacy-orphans/' || lower(p_source_content_sha256);
  v_object_size bigint;
begin
  if lower(coalesce(p_source_path_sha256, '')) !~ '^[0-9a-f]{64}$'
     or lower(coalesce(p_source_content_sha256, '')) !~ '^[0-9a-f]{64}$'
     or p_size_bytes is null
     or p_size_bytes < 0
     or p_size_bytes > 67108864
     or p_source_created_at is null then
    raise exception 'Invalid orphan quarantine receipt'
      using errcode = '22023';
  end if;

  select receipt.*
  into v_existing
  from public.messaging_legacy_orphan_quarantine_receipts receipt
  where receipt.source_path_sha256 = lower(p_source_path_sha256)
  for update;

  if found then
    if v_existing.source_content_sha256 <> lower(p_source_content_sha256)
       or v_existing.quarantine_path <> v_quarantine_path
       or v_existing.size_bytes <> p_size_bytes
       or v_existing.source_created_at <> p_source_created_at then
      raise exception 'Existing orphan quarantine receipt differs from retry'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'receipt_id', v_existing.id,
      'changed', false,
      'deleted_from_public', v_existing.deleted_from_public_at is not null
    );
  end if;

  select nullif(object.metadata->>'size', '')::bigint
  into v_object_size
  from storage.objects object
  where object.bucket_id = 'messaging-attachment-quarantine'
    and object.name = v_quarantine_path;

  if not found or v_object_size is distinct from p_size_bytes then
    raise exception 'Private orphan quarantine readback is missing or mismatched'
      using errcode = '23514';
  end if;

  insert into public.messaging_legacy_orphan_quarantine_receipts (
    source_path_sha256,
    source_content_sha256,
    quarantine_path,
    size_bytes,
    source_created_at
  ) values (
    lower(p_source_path_sha256),
    lower(p_source_content_sha256),
    v_quarantine_path,
    p_size_bytes,
    p_source_created_at
  ) returning * into v_existing;

  return jsonb_build_object(
    'receipt_id', v_existing.id,
    'changed', true,
    'deleted_from_public', false
  );
end;
$$;

create or replace function public.mark_legacy_messaging_orphan_public_deleted(
  p_source_path_sha256 text,
  p_source_content_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_receipt public.messaging_legacy_orphan_quarantine_receipts%rowtype;
  v_changed boolean;
begin
  select receipt.*
  into v_receipt
  from public.messaging_legacy_orphan_quarantine_receipts receipt
  where receipt.source_path_sha256 = lower(p_source_path_sha256)
    and receipt.source_content_sha256 = lower(p_source_content_sha256)
  for update;

  if not found then
    raise exception 'Verified orphan quarantine receipt not found'
      using errcode = 'P0002';
  end if;

  v_changed := v_receipt.deleted_from_public_at is null;
  if v_changed then
    update public.messaging_legacy_orphan_quarantine_receipts
    set deleted_from_public_at = now()
    where id = v_receipt.id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_receipt.id,
    'changed', v_changed,
    'deleted_from_public', true
  );
end;
$$;

create or replace function public.finalize_legacy_messaging_attachment_backfill(
  p_message_id uuid,
  p_attachment_id uuid,
  p_storage_path text,
  p_original_filename text,
  p_extension text,
  p_declared_mime_type text,
  p_size_bytes bigint,
  p_sha256 text,
  p_expected_legacy_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_temp
as $$
declare
  v_message public.messages%rowtype;
  v_existing public.messaging_attachments%rowtype;
  v_object_metadata jsonb;
  v_object_size bigint;
  v_object_mime text;
  v_legacy_url_count bigint;
  v_clean_metadata jsonb;
begin
  select message.*
  into v_message
  from public.messages message
  where message.id = p_message_id
  for update;

  if not found then
    raise exception 'Legacy message not found' using errcode = 'P0002';
  end if;

  select count(distinct url)
  into v_legacy_url_count
  from public.messaging_legacy_attachment_urls(
    coalesce(v_message.metadata, '{}'::jsonb),
    v_message.content,
    v_message.type
  ) url;

  select attachment.*
  into v_existing
  from public.messaging_attachments attachment
  where attachment.message_id = v_message.id;

  if found then
    if v_existing.id <> p_attachment_id
       or v_existing.storage_path <> p_storage_path
       or v_existing.sha256 is distinct from lower(p_sha256)
       or v_existing.status <> 'attached' then
      raise exception 'Existing private attachment differs from retry receipt'
        using errcode = '23514';
    end if;

    -- A lost acknowledgement may leave legacy URL fields on the message even
    -- though the registry commit succeeded. Repairing those fields is safe and
    -- idempotent because the immutable private receipt already matches.
    v_clean_metadata := coalesce(v_message.metadata, '{}'::jsonb)
      - array[
        'url', 'media_url', 'image_url', 'file_url', 'documentUrl',
        'document_url', 'storage_url', 'public_url',
        'whatsapp_media_url', 'download_url'
      ]::text[];
    v_clean_metadata := v_clean_metadata || jsonb_build_object(
      'attachment_id', v_existing.id,
      'storage_bucket', v_existing.storage_bucket,
      'storage_path', v_existing.storage_path,
      'filename', v_existing.original_filename,
      'extension', v_existing.extension,
      'content_type', v_existing.declared_mime_type,
      'size_bytes', v_existing.size_bytes,
      'attachment_access', 'private_signed_runtime'
    );

    update public.messages
    set metadata = v_clean_metadata,
        content = case
          when content = p_expected_legacy_url then v_existing.original_filename
          else content
        end
    where id = v_message.id;

    return jsonb_build_object(
      'message_id', v_message.id,
      'attachment_id', v_existing.id,
      'changed', false,
      'repaired', true
    );
  end if;

  if v_legacy_url_count <> 1
     or not exists (
       select 1
       from public.messaging_legacy_attachment_urls(
         coalesce(v_message.metadata, '{}'::jsonb),
         v_message.content,
         v_message.type
       ) url
       where url = p_expected_legacy_url
     ) then
    raise exception 'Legacy URL evidence changed or is ambiguous'
      using errcode = '40001';
  end if;

  if p_storage_path <> v_message.tenant_id::text || '/'
      || v_message.conversation_id::text || '/' || p_attachment_id::text
      || '.' || lower(p_extension) then
    raise exception 'Private storage path does not match message ownership'
      using errcode = '23514';
  end if;

  select coalesce(object.metadata, '{}'::jsonb)
  into v_object_metadata
  from storage.objects object
  where object.bucket_id = 'chat-attachments'
    and object.name = p_storage_path;

  if not found then
    raise exception 'Private object readback is missing' using errcode = 'P0002';
  end if;

  begin
    v_object_size := nullif(v_object_metadata->>'size', '')::bigint;
  exception when invalid_text_representation then
    v_object_size := null;
  end;
  v_object_mime := lower(coalesce(
    nullif(v_object_metadata->>'mimetype', ''),
    nullif(v_object_metadata->>'contentType', ''),
    ''
  ));

  if v_object_size is distinct from p_size_bytes
     or v_object_mime is distinct from lower(p_declared_mime_type) then
    raise exception 'Private object metadata does not match copy receipt'
      using errcode = '23514';
  end if;

  insert into public.messaging_attachments (
    id,
    tenant_id,
    conversation_id,
    message_id,
    storage_path,
    original_filename,
    extension,
    declared_mime_type,
    size_bytes,
    sha256,
    status,
    created_by,
    attached_at
  ) values (
    p_attachment_id,
    v_message.tenant_id,
    v_message.conversation_id,
    v_message.id,
    p_storage_path,
    p_original_filename,
    lower(p_extension),
    lower(p_declared_mime_type),
    p_size_bytes,
    lower(p_sha256),
    'attached',
    null,
    now()
  );

  v_clean_metadata := coalesce(v_message.metadata, '{}'::jsonb)
    - array[
      'url', 'media_url', 'image_url', 'file_url', 'documentUrl',
      'document_url', 'storage_url', 'public_url',
      'whatsapp_media_url', 'download_url'
    ]::text[];
  v_clean_metadata := v_clean_metadata || jsonb_build_object(
    'attachment_id', p_attachment_id,
    'storage_bucket', 'chat-attachments',
    'storage_path', p_storage_path,
    'filename', p_original_filename,
    'extension', lower(p_extension),
    'content_type', lower(p_declared_mime_type),
    'size_bytes', p_size_bytes,
    'attachment_access', 'private_signed_runtime'
  );

  update public.messages
  set metadata = v_clean_metadata,
      content = case
        when content = p_expected_legacy_url then p_original_filename
        else content
      end
  where id = v_message.id;

  return jsonb_build_object(
    'message_id', v_message.id,
    'attachment_id', p_attachment_id,
    'changed', true,
    'repaired', false
  );
end;
$$;

-- Replaces the legacy job-id-only WhatsApp quote mutation. The persisted
-- outbound action message, conversation context, WhatsApp customer binding,
-- job tenant and customer must all describe the same operation.
create or replace function public.mark_whatsapp_conversation_quote_sent(
  p_conversation_id uuid,
  p_job_id uuid,
  p_message_id uuid,
  p_external_message_id text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_status_id uuid;
  v_operation_key text;
  v_transition_result jsonb;
begin
  select job.*
  into v_job
  from public.mechanic_jobs job
  join public.conversations conversation
    on conversation.id = p_conversation_id
   and conversation.tenant_id = job.tenant_id
  where job.id = p_job_id
    and job.deleted_at is null
    and exists (
      select 1
      from public.whatsapp_conversation_bindings binding
      where binding.conversation_id = conversation.id
        and binding.tenant_id = conversation.tenant_id
        and binding.customer_id = job.customer_id
    )
    and (
      (
        conversation.context_type = 'job'
        and conversation.context_id = job.id
      )
      or exists (
        select 1
        from public.conversation_contexts context
        where context.conversation_id = conversation.id
          and context.tenant_id = conversation.tenant_id
          and context.context_type = 'job'
          and context.context_id = job.id
      )
    )
    and exists (
      select 1
      from public.messages message
      where message.id = p_message_id
        and message.conversation_id = conversation.id
        and message.tenant_id = conversation.tenant_id
        and message.external_provider = 'whatsapp'
        and message.external_message_id = p_external_message_id
        and message.type = 'action_request'
        and message.metadata->>'action_type' = 'approve_quote'
        and coalesce(
          nullif(message.metadata->>'target_id', ''),
          nullif(message.metadata->>'job_id', '')
        ) = job.id::text
    )
  ;

  if not found then
    raise exception 'Conversation, customer, job and outbound quote evidence do not match'
      using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_external_message_id, '')), '') is null then
    raise exception 'External message evidence is required'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.mechanic_job_timeline timeline
    where timeline.job_id = p_job_id
      and timeline.event_type = 'whatsapp_quote_sent'
      and timeline.new_value = p_external_message_id
  ) then
    return jsonb_build_object(
      'job_id', p_job_id,
      'conversation_id', p_conversation_id,
      'message_id', p_message_id,
      'external_message_id', p_external_message_id,
      'duplicate', true
    );
  end if;

  select status.id
  into v_status_id
  from public.job_statuses status
  where status.tenant_id = v_job.tenant_id
    and status.code = 'ESPERANDO_APROBACION'
    and status.is_active = true
  order by status.sort_order
  limit 1;

  v_operation_key := 'whatsapp-quote-sent:' || p_external_message_id;
  if v_status_id is not null then
    -- Status/status_id, lifecycle timestamps, accounting guards and the
    -- durable idempotency receipt all belong to the same canonical command
    -- used by Jobs Table. Never bypass that command from Messaging.
    v_transition_result := public.transition_mechanic_job_status(
      v_job.id,
      v_status_id,
      v_operation_key
    );
  end if;

  update public.mechanic_jobs
  set diagnostic_sent_at = coalesce(diagnostic_sent_at, now()),
      requires_approval = true,
      updated_at = now()
  where id = v_job.id
    and tenant_id = v_job.tenant_id;

  -- A concurrent replay can pass the first evidence check while the canonical
  -- status command is serializing on the job. Re-check before appending the
  -- timeline event so only one external-message receipt is written.
  if exists (
    select 1
    from public.mechanic_job_timeline timeline
    where timeline.job_id = p_job_id
      and timeline.event_type = 'whatsapp_quote_sent'
      and timeline.new_value = p_external_message_id
  ) then
    return jsonb_build_object(
      'job_id', p_job_id,
      'conversation_id', p_conversation_id,
      'message_id', p_message_id,
      'external_message_id', p_external_message_id,
      'operation_key', v_operation_key,
      'canonical_result', v_transition_result,
      'duplicate', true
    );
  end if;

  perform public.log_mechanic_job_timeline(
    v_job.id,
    'whatsapp_quote_sent',
    null,
    p_external_message_id,
    'Presupuesto enviado por WhatsApp con conversación y cliente verificados'
  );

  return jsonb_build_object(
    'job_id', v_job.id,
    'conversation_id', p_conversation_id,
    'message_id', p_message_id,
    'external_message_id', p_external_message_id,
    'status_code', coalesce(v_transition_result->>'status', v_job.status),
    'operation_key', v_operation_key,
    'canonical_result', v_transition_result,
    'payload', coalesce(p_payload, '{}'::jsonb),
    'duplicate', false
  );
end;
$$;

revoke all on table public.messaging_attachments
  from public, anon, authenticated;
grant select on table public.messaging_attachments to authenticated;
grant all on table public.messaging_attachments to service_role;
revoke all on table public.messaging_legacy_orphan_quarantine_receipts
  from public, anon, authenticated;
grant all on table public.messaging_legacy_orphan_quarantine_receipts
  to service_role;

revoke all on function public.messaging_attachment_storage_can_insert(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_attachment_storage_can_read(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_attachment_storage_can_delete(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.messaging_attachment_storage_can_insert(text, text)
  to authenticated;
grant execute on function public.messaging_attachment_storage_can_read(text, text)
  to authenticated;
grant execute on function public.messaging_attachment_storage_can_delete(text, text)
  to authenticated;

revoke all on function public.reserve_messaging_attachment(uuid, text, text, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.reserve_messaging_attachment(uuid, text, text, bigint)
  to authenticated;

revoke all on function public.publish_messaging_attachment(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.publish_messaging_attachment(uuid, text)
  to authenticated;

revoke all on function public.fail_messaging_attachment(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.fail_messaging_attachment(uuid, text)
  to authenticated;

revoke all on function public.messaging_legacy_attachment_urls(jsonb, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.list_legacy_messaging_attachment_candidates()
  from public, anon, authenticated, service_role;
revoke all on function public.list_legacy_messaging_public_objects()
  from public, anon, authenticated, service_role;
revoke all on function public.finalize_legacy_messaging_orphan_quarantine(
  text, text, bigint, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.mark_legacy_messaging_orphan_public_deleted(
  text, text
) from public, anon, authenticated, service_role;
revoke all on function public.finalize_legacy_messaging_attachment_backfill(
  uuid, uuid, text, text, text, text, bigint, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.list_legacy_messaging_attachment_candidates()
  to service_role;
grant execute on function public.list_legacy_messaging_public_objects()
  to service_role;
grant execute on function public.finalize_legacy_messaging_orphan_quarantine(
  text, text, bigint, timestamptz
) to service_role;
grant execute on function public.mark_legacy_messaging_orphan_public_deleted(
  text, text
) to service_role;
grant execute on function public.finalize_legacy_messaging_attachment_backfill(
  uuid, uuid, text, text, text, text, bigint, text, text
) to service_role;

revoke all on function public.mark_whatsapp_job_quote_sent(uuid, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.mark_whatsapp_conversation_quote_sent(
  uuid, uuid, uuid, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.mark_whatsapp_conversation_quote_sent(
  uuid, uuid, uuid, text, jsonb
) to service_role;

notify pgrst, 'reload schema';

commit;
