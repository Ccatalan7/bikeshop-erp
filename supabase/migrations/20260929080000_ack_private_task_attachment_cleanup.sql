-- Durable cleanup of private task bytes after a link has been tombstoned.
-- This is additive: no existing objects or links are deleted by the migration.
begin;

create index if not exists smart_task_attachments_pending_cleanup
  on public.smart_task_attachments (deleted_at, id)
  where deleted_at is not null and storage_deleted_at is null;

create or replace function public.smart_task_attachment_pending_cleanup_v1(
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'task attachment cleanup: authenticated user required'
      using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'task attachment cleanup: limit must be 1..50'
      using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pending.id,
      'task_id', pending.task_id,
      'storage_path', pending.storage_path
    ) order by pending.deleted_at, pending.id
  ), '[]'::jsonb)
  into v_result
  from (
    select attachment.id, attachment.task_id, attachment.storage_path,
      attachment.deleted_at
    from public.smart_task_attachments attachment
    where attachment.deleted_at is not null
      and attachment.storage_deleted_at is null
      and public.smart_task_attachment_storage_allowed_v1(
        attachment.storage_path, 'manage', null
      )
    order by attachment.deleted_at, attachment.id
    limit p_limit
  ) pending;

  return v_result;
end;
$$;

create or replace function public.smart_task_attachment_ack_cleanup_v1(
  p_task_id uuid,
  p_attachment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'storage', 'auth', 'pg_temp'
as $$
declare
  v_attachment public.smart_task_attachments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'task attachment cleanup: authenticated user required'
      using errcode = '42501';
  end if;

  select * into v_attachment
  from public.smart_task_attachments attachment
  where attachment.id = p_attachment_id
    and attachment.task_id = p_task_id
  for update;
  if not found or not public.smart_task_attachment_storage_allowed_v1(
    v_attachment.storage_path, 'manage', null
  ) then
    raise exception 'task attachment cleanup: file not writable'
      using errcode = '42501';
  end if;
  if v_attachment.deleted_at is null then
    raise exception 'task attachment cleanup: file is still active'
      using errcode = '55000';
  end if;
  if exists (
    select 1 from storage.objects object
    where object.bucket_id = 'task-attachments'
      and object.name = v_attachment.storage_path
  ) then
    raise exception 'task attachment cleanup: private bytes still exist'
      using errcode = '55000';
  end if;

  update public.smart_task_attachments
  set storage_deleted_at = coalesce(storage_deleted_at, now())
  where id = p_attachment_id
  returning * into v_attachment;

  return jsonb_build_object(
    'id', v_attachment.id,
    'task_id', v_attachment.task_id,
    'storage_deleted_at', v_attachment.storage_deleted_at
  );
end;
$$;

revoke all on function public.smart_task_attachment_pending_cleanup_v1(integer)
  from public, anon, service_role;
grant execute on function public.smart_task_attachment_pending_cleanup_v1(integer)
  to authenticated;
revoke all on function public.smart_task_attachment_ack_cleanup_v1(uuid, uuid)
  from public, anon, service_role;
grant execute on function public.smart_task_attachment_ack_cleanup_v1(uuid, uuid)
  to authenticated;

commit;
