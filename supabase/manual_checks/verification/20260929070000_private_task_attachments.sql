-- Read-only structural readback. Local behavioral tests exercise authority,
-- retries, and concurrent inserts without mutating production tasks.
select 1 / (case when
  exists (
    select 1 from storage.buckets
    where id = 'task-attachments'
      and public is false
      and file_size_limit = 20971520
  )
  and exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'smart_task_attachments'
      and c.relrowsecurity
  )
  and not has_table_privilege('authenticated',
    'public.smart_task_attachments', 'INSERT')
  and not has_table_privilege('authenticated',
    'public.smart_task_attachments', 'UPDATE')
  and not has_table_privilege('authenticated',
    'public.smart_task_attachments', 'DELETE')
  and has_table_privilege('authenticated',
    'public.smart_task_attachments', 'SELECT')
  and not has_table_privilege('anon',
    'public.smart_task_attachments', 'SELECT')
  and has_function_privilege('authenticated',
    'public.smart_task_attachment_storage_allowed_v1(text,text,text)',
    'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_storage_allowed_v1(text,text,text)',
    'EXECUTE')
  and has_function_privilege('authenticated',
    'public.smart_task_attachment_add_v1(uuid,uuid,text,text,text,bigint,text)',
    'EXECUTE')
  and has_function_privilege('authenticated',
    'public.smart_task_attachment_remove_v1(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_add_v1(uuid,uuid,text,text,text,bigint,text)',
    'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_remove_v1(uuid,uuid,text)', 'EXECUTE')
  and (
    select count(*) = 3
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname in (
        'task_attachments_select', 'task_attachments_insert',
        'task_attachments_delete'
      )
      and coalesce(qual, with_check, '') like
        '%smart_task_attachment_storage_allowed_v1%'
  )
  and not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'task_attachments_update'
  )
  and exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'smart_task_attachments'
      and policyname = 'smart_task_attachments_select'
      and qual like '%smart_task_can_view_v1%'
  )
then 1 else 0 end) as private_task_attachment_contract;
