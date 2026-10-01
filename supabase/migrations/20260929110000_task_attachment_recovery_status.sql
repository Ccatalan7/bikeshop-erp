-- Tell an authorized uploader whether their attachment UUID was linked,
-- removed, or never linked. Absence alone does not authorize Storage deletion:
-- an upload or add RPC may still be running in another session.
begin;

create or replace function public.smart_task_attachment_recovery_status_v1(
  p_tenant_id uuid,
  p_task_id uuid,
  p_attachment_id uuid
)
returns text
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_attachment public.smart_task_attachments%rowtype;
begin
  if v_actor is null then
    raise exception 'task attachment recovery: authenticated user required'
      using errcode = '42501';
  end if;
  if p_tenant_id is null or p_task_id is null or p_attachment_id is null then
    raise exception 'task attachment recovery: identity required'
      using errcode = '22023';
  end if;
  if not public.smart_task_attachment_storage_allowed_v1(
    p_tenant_id::text || '/' || p_task_id::text || '/'
      || p_attachment_id::text || '/recovery',
    'manage', null
  ) then
    raise exception 'task attachment recovery: task not writable'
      using errcode = '42501';
  end if;

  select * into v_attachment
  from public.smart_task_attachments attachment
  where attachment.id = p_attachment_id;
  if not found then
    return 'absent';
  end if;
  if v_attachment.tenant_id <> p_tenant_id
    or v_attachment.task_id <> p_task_id
    or v_attachment.uploaded_by <> v_actor then
    raise exception 'task attachment recovery: identity mismatch'
      using errcode = '42501';
  end if;
  if v_attachment.deleted_at is not null then
    return 'removed';
  end if;
  return 'active';
end;
$$;

revoke all on function public.smart_task_attachment_recovery_status_v1(
  uuid, uuid, uuid
) from public, anon, service_role;
grant execute on function public.smart_task_attachment_recovery_status_v1(
  uuid, uuid, uuid
) to authenticated;

commit;
