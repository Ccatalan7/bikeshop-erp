-- Future task attachments: private bytes and one atomic link per file.
-- No legacy bytes move here. Production had zero smart_tasks attachments on
-- 2026-09-29; historical public objects need a separate, reviewed migration.
-- Additive only; no change to existing tasks or Storage objects.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('task-attachments', 'task-attachments', false, 20971520, null)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

create table if not exists public.smart_task_attachments (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  task_id uuid not null references public.smart_tasks(id) on delete restrict,
  uploaded_by uuid not null references auth.users(id),
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  storage_deleted_at timestamptz,
  constraint smart_task_attachments_size_check
    check (size_bytes > 0 and size_bytes <= 20971520),
  constraint smart_task_attachments_name_check
    check (length(btrim(file_name)) between 1 and 255),
  constraint smart_task_attachments_path_check
    check (
      split_part(storage_path, '/', 1) = tenant_id::text
      and split_part(storage_path, '/', 2) = task_id::text
      and split_part(storage_path, '/', 3) = id::text
      and split_part(storage_path, '/', 4) <> ''
      and split_part(storage_path, '/', 5) = ''
    )
);

create index if not exists smart_task_attachments_task_active
  on public.smart_task_attachments (tenant_id, task_id, created_at, id)
  where deleted_at is null;

alter table public.smart_task_attachments enable row level security;
revoke all on public.smart_task_attachments from public, anon, authenticated;
grant select on public.smart_task_attachments to authenticated;

drop policy if exists task_attachments_select on storage.objects;
drop policy if exists task_attachments_insert on storage.objects;
drop policy if exists task_attachments_delete on storage.objects;
drop function if exists public.smart_task_attachment_storage_allowed_v1(text, text);

create or replace function public.smart_task_attachment_storage_allowed_v1(
  p_path text,
  p_action text,
  p_owner_id text
)
returns boolean
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_parts text[] := string_to_array(coalesce(p_path, ''), '/');
  v_task public.smart_tasks%rowtype;
  v_attachment public.smart_task_attachments%rowtype;
  v_can_write boolean;
  v_linked boolean;
begin
  if v_actor is null or array_length(v_parts, 1) <> 4
    or v_parts[1] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or v_parts[2] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or v_parts[3] !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or nullif(v_parts[4], '') is null then
    return false;
  end if;

  select * into v_task
  from public.smart_tasks task
  where task.id = v_parts[2]::uuid
    and task.tenant_id = v_parts[1]::uuid;
  if not found or not public.smart_task_can_view_v1(v_task.id) then
    return false;
  end if;
  select * into v_attachment
  from public.smart_task_attachments attachment
  where attachment.storage_path = p_path
    and attachment.tenant_id = v_task.tenant_id
    and attachment.task_id = v_task.id;
  v_linked := found;
  v_can_write := (
    public.user_tenant_id() = v_task.tenant_id
    and (v_task.created_by = v_actor
      or v_task.assigned_to = v_actor
      or public.can_manage_tenant_users(v_task.tenant_id))
  ) or (
    v_task.assigned_to = v_actor
    and public.smart_task_assignee_eligible_v1(v_task.tenant_id, v_actor)
  );
  if p_action = 'read' then
    -- Storage DELETE also needs SELECT on the target row. A tombstone stays
    -- visible only to a writer for the short cleanup window, never to viewers.
    return v_linked and (v_attachment.deleted_at is null
      or coalesce(v_can_write, false));
  end if;
  if p_action = 'write' then
    return coalesce(v_can_write, false) and not v_linked;
  end if;
  if p_action = 'manage' then
    return coalesce(v_can_write, false);
  end if;
  if p_action = 'delete' then
    return coalesce(v_can_write, false)
      and (v_linked and v_attachment.deleted_at is not null
        or not v_linked and p_owner_id = v_actor::text);
  end if;
  return false;
end;
$$;

revoke all on function public.smart_task_attachment_storage_allowed_v1(text, text, text)
  from public, anon, service_role;
grant execute on function public.smart_task_attachment_storage_allowed_v1(text, text, text)
  to authenticated;

drop policy if exists task_attachments_select on storage.objects;
drop policy if exists task_attachments_insert on storage.objects;
drop policy if exists task_attachments_delete on storage.objects;

create policy task_attachments_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'task-attachments'
    and public.smart_task_attachment_storage_allowed_v1(name, 'read', owner_id)
  );

create policy task_attachments_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'task-attachments'
    and owner_id = auth.uid()::text
    and public.smart_task_attachment_storage_allowed_v1(name, 'write', owner_id)
  );

-- No UPDATE policy: a file cannot be replaced in place.
create policy task_attachments_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'task-attachments'
    and public.smart_task_attachment_storage_allowed_v1(name, 'delete', owner_id)
  );

drop policy if exists smart_task_attachments_select on public.smart_task_attachments;
create policy smart_task_attachments_select on public.smart_task_attachments
  for select to authenticated
  using (
    deleted_at is null
    and public.smart_task_can_view_v1(task_id)
  );

-- Claim receipt serializes a retry with the same key. The row's UUID and
-- unique path allow independent concurrent uploads without JSONB replacement.
create or replace function public.smart_task_attachment_add_v1(
  p_task_id uuid,
  p_attachment_id uuid,
  p_file_name text,
  p_storage_path text,
  p_mime_type text,
  p_size_bytes bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'storage', 'auth', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_task public.smart_tasks%rowtype;
  v_attachment public.smart_task_attachments%rowtype;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if v_actor is null then
    raise exception 'task attachment: active tenant required'
      using errcode = '42501';
  end if;
  select * into v_task from public.smart_tasks task
  where task.id = p_task_id
  for share;
  if not found or not public.smart_task_attachment_storage_allowed_v1(
    p_storage_path, 'manage', null
  ) then
    raise exception 'task attachment: task not writable'
      using errcode = '42501';
  end if;
  v_tenant := v_task.tenant_id;
  if p_task_id is null or p_attachment_id is null
    or nullif(btrim(coalesce(p_file_name, '')), '') is null
    or length(p_file_name) > 255
    or nullif(btrim(coalesce(p_mime_type, '')), '') is null
    or length(p_mime_type) > 200
    or p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > 20971520
    or p_storage_path is null
    or split_part(p_storage_path, '/', 1) <> v_tenant::text
    or split_part(p_storage_path, '/', 2) <> p_task_id::text
    or split_part(p_storage_path, '/', 3) <> p_attachment_id::text
    or split_part(p_storage_path, '/', 4) = ''
    or split_part(p_storage_path, '/', 5) <> '' then
    raise exception 'task attachment: invalid metadata or path'
      using errcode = '22023';
  end if;

  v_fingerprint := md5(concat_ws('|', p_task_id, p_attachment_id,
    p_file_name, p_storage_path, p_mime_type, p_size_bytes));
  select o_replay into v_replay from public.smart_task_claim_receipt(
    v_tenant, v_actor, 'task_attachment_add', p_idempotency_key, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  if not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'task-attachments'
      and object.name = p_storage_path
      and object.owner_id = v_actor::text
  ) then
    raise exception 'task attachment: uploaded object not found'
      using errcode = '23503';
  end if;

  insert into public.smart_task_attachments (
    id, tenant_id, task_id, uploaded_by, storage_path,
    file_name, mime_type, size_bytes
  ) values (
    p_attachment_id, v_tenant, p_task_id, v_actor, p_storage_path,
    btrim(p_file_name), btrim(p_mime_type), p_size_bytes
  ) on conflict (id) do nothing;

  select * into v_attachment from public.smart_task_attachments attachment
  where attachment.id = p_attachment_id;
  if not found or v_attachment.tenant_id <> v_tenant
    or v_attachment.task_id <> p_task_id
    or v_attachment.uploaded_by <> v_actor
    or v_attachment.storage_path <> p_storage_path
    or v_attachment.file_name <> btrim(p_file_name)
    or v_attachment.mime_type <> btrim(p_mime_type)
    or v_attachment.size_bytes <> p_size_bytes
    or v_attachment.deleted_at is not null then
    raise exception 'task attachment: id reused with different content'
      using errcode = '23505';
  end if;

  v_result := jsonb_build_object(
    'id', v_attachment.id,
    'task_id', v_attachment.task_id,
    'name', v_attachment.file_name,
    'type', v_attachment.mime_type,
    'size', v_attachment.size_bytes,
    'storage_bucket', 'task-attachments',
    'storage_path', v_attachment.storage_path,
    'uploaded_by', v_attachment.uploaded_by,
    'uploaded_at', v_attachment.created_at,
    'version', v_attachment.version
  );
  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_attachment_add', p_idempotency_key,
    v_fingerprint, p_task_id, v_result
  );
  return v_result;
end;
$$;

create or replace function public.smart_task_attachment_remove_v1(
  p_task_id uuid,
  p_attachment_id uuid,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_attachment public.smart_task_attachments%rowtype;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if v_actor is null then
    raise exception 'task attachment: active tenant required'
      using errcode = '42501';
  end if;
  select * into v_attachment from public.smart_task_attachments attachment
  where attachment.id = p_attachment_id
    and attachment.task_id = p_task_id
  for update;
  if not found or not public.smart_task_attachment_storage_allowed_v1(
    v_attachment.storage_path, 'manage', null
  ) then
    raise exception 'task attachment: file not writable'
      using errcode = '42501';
  end if;
  v_tenant := v_attachment.tenant_id;
  v_fingerprint := md5(concat_ws('|', p_task_id, p_attachment_id));
  select o_replay into v_replay from public.smart_task_claim_receipt(
    v_tenant, v_actor, 'task_attachment_remove', p_idempotency_key, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  if v_attachment.deleted_at is null then
    update public.smart_task_attachments
    set deleted_at = now(), version = version + 1
    where id = p_attachment_id
    returning * into v_attachment;
  end if;
  v_result := jsonb_build_object(
    'id', v_attachment.id,
    'storage_bucket', 'task-attachments',
    'storage_path', v_attachment.storage_path,
    'version', v_attachment.version,
    'deleted_at', v_attachment.deleted_at
  );
  perform public.smart_task_store_receipt(
    v_tenant, v_actor, 'task_attachment_remove', p_idempotency_key,
    v_fingerprint, p_task_id, v_result
  );
  return v_result;
end;
$$;

revoke all on function public.smart_task_attachment_add_v1(
  uuid, uuid, text, text, text, bigint, text
) from public, anon, service_role;
grant execute on function public.smart_task_attachment_add_v1(
  uuid, uuid, text, text, text, bigint, text
) to authenticated;
revoke all on function public.smart_task_attachment_remove_v1(uuid, uuid, text)
  from public, anon, service_role;
grant execute on function public.smart_task_attachment_remove_v1(uuid, uuid, text)
  to authenticated;

commit;
