-- Page private task-file cleanup within the tenant selected by the client.
-- The v1 queue remains available to existing callers; the new client uses v2
-- so an authorized assignment in a different tenant cannot occupy its page.
begin;

create or replace function public.smart_task_attachment_pending_cleanup_v2(
  p_tenant_id uuid,
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
  if p_tenant_id is null or p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'task attachment cleanup: tenant and limit required'
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
    where attachment.tenant_id = p_tenant_id
      and attachment.deleted_at is not null
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

revoke all on function public.smart_task_attachment_pending_cleanup_v2(uuid, integer)
  from public, anon, service_role;
grant execute on function public.smart_task_attachment_pending_cleanup_v2(uuid, integer)
  to authenticated;

commit;
