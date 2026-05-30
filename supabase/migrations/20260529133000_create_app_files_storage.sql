-- Internal app file library with tenant-scoped Supabase Storage objects.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vinabike-files', 'vinabike-files', false, 52428800, null)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.app_files (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  file_name text not null,
  storage_bucket text not null default 'vinabike-files',
  storage_path text not null,
  mime_type text not null default 'application/octet-stream',
  size_bytes bigint not null default 0,
  source_type text not null default 'manual',
  source_id text,
  source_provider text,
  source_route text,
  context_type text,
  context_id text,
  context_title text,
  context_subtitle text,
  tags text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone,
  constraint app_files_storage_object_unique unique (storage_bucket, storage_path),
  constraint app_files_size_nonnegative check (size_bytes >= 0)
);

create index if not exists idx_app_files_tenant_created
  on public.app_files(tenant_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_app_files_source
  on public.app_files(tenant_id, source_type, created_at desc)
  where deleted_at is null;

create index if not exists idx_app_files_context
  on public.app_files(tenant_id, context_type, context_id)
  where deleted_at is null;

create index if not exists idx_app_files_tags
  on public.app_files using gin(tags);

create index if not exists idx_app_files_metadata
  on public.app_files using gin(metadata);

drop trigger if exists trg_app_files_updated_at on public.app_files;
create trigger trg_app_files_updated_at
  before update on public.app_files
  for each row execute procedure public.set_updated_at();

alter table public.app_files enable row level security;

drop policy if exists "app_files_select" on public.app_files;
drop policy if exists "app_files_insert" on public.app_files;
drop policy if exists "app_files_update" on public.app_files;
drop policy if exists "app_files_delete" on public.app_files;

create policy "app_files_select" on public.app_files
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "app_files_insert" on public.app_files
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "app_files_update" on public.app_files
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

create policy "app_files_delete" on public.app_files
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists "vinabike_files_select" on storage.objects;
drop policy if exists "vinabike_files_insert" on storage.objects;
drop policy if exists "vinabike_files_update" on storage.objects;
drop policy if exists "vinabike_files_delete" on storage.objects;

create policy "vinabike_files_select" on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'vinabike-files'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

create policy "vinabike_files_insert" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'vinabike-files'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

create policy "vinabike_files_update" on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'vinabike-files'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  )
  with check (
    bucket_id = 'vinabike-files'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

create policy "vinabike_files_delete" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'vinabike-files'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

notify pgrst, 'reload schema';
