-- Read-only contract check; behavioral isolation is covered by local pgTAP.
select count(*) as attachment_links
from public.smart_task_attachments;

select 1 / (case when exists (
  select 1 from pg_proc p
  where p.oid = to_regprocedure(
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)')
    and p.prosecdef and p.provolatile = 's'
    and p.proconfig @> array['search_path=pg_catalog, public, auth, pg_temp']
    and position('v_attachment.uploaded_by <> v_actor'
      in pg_get_functiondef(p.oid)) > 0
    and position('smart_task_attachment_storage_allowed_v1'
      in pg_get_functiondef(p.oid)) > 0
  ) and has_function_privilege('authenticated',
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)',
    'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)',
    'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)',
    'EXECUTE')
then 1 else 0 end) as task_attachment_recovery_status_contract;
