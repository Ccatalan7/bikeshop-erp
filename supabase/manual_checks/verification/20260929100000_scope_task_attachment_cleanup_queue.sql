-- Read-only production assertion. Behavioral tenant paging is covered by
-- private_task_attachments.sql on the local database with rollback.
select
  (select count(*) from public.smart_task_attachments attachment
    where attachment.deleted_at is not null
      and attachment.storage_deleted_at is null) as pending_cleanup_links;

select 1 / (case when exists (
  select 1 from pg_proc p
  where p.oid = to_regprocedure(
    'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)')
    and p.prosecdef and p.provolatile = 's'
    and p.proconfig @> array['search_path=pg_catalog, public, auth, pg_temp']
    and position('attachment.tenant_id = p_tenant_id'
      in pg_get_functiondef(p.oid)) > 0
    and position('smart_task_attachment_storage_allowed_v1'
      in pg_get_functiondef(p.oid)) > 0
  ) and has_function_privilege('authenticated',
    'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)',
    'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)',
    'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)',
    'EXECUTE')
then 1 else 0 end) as scoped_task_attachment_cleanup_contract;
