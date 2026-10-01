-- An uploader must be able to see its own unlinked object long enough to
-- remove it after a failed attachment RPC. Storage DELETE requires SELECT.
-- The existing write predicate still checks the task, tenant, actor and path;
-- active linked objects keep their original task visibility policy.
begin;

drop policy if exists task_attachments_select on storage.objects;
create policy task_attachments_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'task-attachments'
    and (
      public.smart_task_attachment_storage_allowed_v1(
        name, 'read', owner_id
      )
      or (
        owner_id = auth.uid()::text
        and public.smart_task_attachment_storage_allowed_v1(
          name, 'write', owner_id
        )
      )
    )
  );

commit;
