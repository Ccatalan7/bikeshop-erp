-- Read-only verification. The behavioral delete/ack race is covered by the
-- focused local pgTAP; production tasks and objects are not mutated here.
select
  (select count(*) from public.smart_task_attachments
    where deleted_at is not null and storage_deleted_at is null)
    as pending_cleanup_links,
  (select count(*) from public.smart_task_attachments
    where storage_deleted_at is not null)
    as acknowledged_cleanup_links;

select 1 / (case when
  exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure(
      'public.smart_task_attachment_pending_cleanup_v1(integer)')
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig @> array['search_path=pg_catalog, public, auth, pg_temp']
  )
  and exists (
    select 1 from pg_proc p
    where p.oid = to_regprocedure(
      'public.smart_task_attachment_ack_cleanup_v1(uuid,uuid)')
      and p.prosecdef
      and p.proconfig @> array['search_path=pg_catalog, public, storage, auth, pg_temp']
  )
  and exists (
    select 1 from pg_class c
    join pg_index i on i.indexrelid = c.oid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'smart_task_attachments_pending_cleanup'
      and i.indisvalid
  )
  and has_function_privilege('authenticated',
    'public.smart_task_attachment_pending_cleanup_v1(integer)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.smart_task_attachment_ack_cleanup_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_pending_cleanup_v1(integer)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_ack_cleanup_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_attachment_pending_cleanup_v1(integer)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_attachment_ack_cleanup_v1(uuid,uuid)', 'EXECUTE')
then 1 else 0 end) as private_task_attachment_cleanup_contract;
