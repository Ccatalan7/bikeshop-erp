-- Deployment status: pending.
--
-- Forward behavior:
--   Creates one private, tenant-prefixed Android release bucket. Active ERP
--   staff can read only objects below their own tenant UUID. Client uploads,
--   updates, and deletes remain denied; the guarded release publisher uses a
--   privileged maintenance credential.
--
-- Recovery:
--   Drop android_release_objects_select_staff to disable all client reads.
--   Preserve the private bucket and immutable APKs until an explicit,
--   separately authorized artifact-retention decision is made.
--
-- Lock/backfill risk:
--   Storage catalog/policy metadata only; no business-table scan or backfill.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'erp-mobile-releases',
  'erp-mobile-releases',
  false,
  262144000,
  array[
    'application/json',
    'application/vnd.android.package-archive'
  ]::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists android_release_objects_select_staff
  on storage.objects;

create policy android_release_objects_select_staff
on storage.objects
for select
to authenticated
using (
  bucket_id = 'erp-mobile-releases'
  and exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = auth.uid()
      and profile.is_active is true
      and profile.tenant_id::text = (storage.foldername(name))[1]
  )
);
