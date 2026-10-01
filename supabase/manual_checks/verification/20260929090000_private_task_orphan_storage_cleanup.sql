-- Read-only production check. Local pgTAP proves the effective owner-only
-- SELECT + DELETE behavior without uploading or deleting production files.
select
  (select count(*) from storage.objects object
    where object.bucket_id = 'task-attachments') as private_task_objects,
  (select count(*) from storage.objects object
    where object.bucket_id = 'task-attachments'
      and not exists (
        select 1 from public.smart_task_attachments attachment
        where attachment.storage_path = object.name
      )) as unlinked_private_task_objects;

select 1 / (case when exists (
  select 1 from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'storage'
    and c.relname = 'objects'
    and p.polname = 'task_attachments_select'
    and p.polcmd = 'r'
    and 'authenticated'::regrole::oid = any(p.polroles)
    and position('task-attachments' in pg_get_expr(p.polqual, p.polrelid)) > 0
    and position('''read''' in pg_get_expr(p.polqual, p.polrelid)) > 0
    and position('''write''' in pg_get_expr(p.polqual, p.polrelid)) > 0
    and position('owner_id' in pg_get_expr(p.polqual, p.polrelid)) > 0
    and position('auth.uid()' in pg_get_expr(p.polqual, p.polrelid)) > 0
  ) and exists (
    select 1 from storage.buckets bucket
    where bucket.id = 'task-attachments' and not bucket.public
  ) then 1 else 0 end) as private_task_orphan_cleanup_contract;
