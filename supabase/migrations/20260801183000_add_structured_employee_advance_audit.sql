-- Structured, tenant-safe audit evidence for employee advances.
-- Deployment status: NOT DEPLOYED. This is an expand-first migration: the
-- published client may continue using register_employee_advance_v2 while the
-- new client adopts v3. No legacy row is backfilled with invented facts.
--
-- Forward behaviour:
--   * legacy rows keep nullable structured fields;
--   * v3 requires one canonical reason plus a real explanation;
--   * short workweeks require work_ended_on;
--   * an optional original receipt must be an actor-owned app_files upload
--     scoped to this operation key; its client SHA-256 is retained alongside
--     the immutable server-owned Storage object id, version and ETag;
--   * receipt uploads are bounded to 12 MiB and PDF/JPEG/PNG/WebP metadata
--     without narrowing the shared vinabike-files bucket;
--   * ledger v2 enriches the already bounded/keyset v1 page.
-- Recovery: keep the additive columns/table and revoke v3/v2-ledger EXECUTE.
-- Dropping audit evidence would destroy financial provenance and is not an
-- automatic rollback. The only table scans are small CHECK validations; no
-- data rewrite or backfill is performed.

begin;

alter table public.employee_advances
  add column if not exists reason_code text,
  add column if not exists reason_explanation text,
  add column if not exists work_ended_on date;

alter table public.employee_advances
  drop constraint if exists employee_advances_structured_reason_check;
alter table public.employee_advances
  add constraint employee_advances_structured_reason_check
  check (
    (
      reason_code is null
      and reason_explanation is null
      and work_ended_on is null
    )
    or (
      reason_code is not null
      and reason_code in (
        'requested_advance',
        'short_workweek',
        'other'
      )
      and reason_explanation is not null
      and char_length(btrim(reason_explanation)) between 1 and 1000
      and (
        (reason_code = 'short_workweek' and work_ended_on is not null)
        or
        (reason_code <> 'short_workweek' and work_ended_on is null)
      )
    )
  );

alter table public.employee_advances
  drop constraint if exists employee_advances_work_ended_on_range_check;
alter table public.employee_advances
  add constraint employee_advances_work_ended_on_range_check
  check (
    work_ended_on is null
    or work_ended_on between date '1900-01-01' and date '2100-12-31'
  );

-- One operation owns at most one active original receipt. This also turns a
-- concurrent retry after an ambiguous Storage/REST response into a read-back
-- instead of two metadata rows for the same money command.
create unique index if not exists
  uq_app_files_payroll_advance_operation_active
  on public.app_files (tenant_id, context_id)
  where deleted_at is null
    and source_type = 'payroll_advance'
    and context_type = 'payroll_advance_operation'
    and context_id is not null;

create table if not exists public.employee_advance_evidence (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null
    references public.tenants(id) on delete restrict,
  advance_id uuid not null
    references public.employee_advances(id) on delete restrict,
  app_file_id uuid not null
    references public.app_files(id) on delete restrict,
  storage_object_id uuid not null,
  storage_object_version text not null
    check (char_length(btrim(storage_object_version)) between 1 and 500),
  storage_object_etag text not null
    check (char_length(btrim(storage_object_etag)) between 1 and 500),
  storage_object_owner_id uuid not null references auth.users(id),
  file_sha256 text not null
    check (file_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references auth.users(id),
  created_at timestamp with time zone not null default statement_timestamp(),
  check (created_by = storage_object_owner_id),
  unique (tenant_id, advance_id),
  unique (tenant_id, app_file_id),
  unique (tenant_id, storage_object_id)
);

create index if not exists idx_employee_advance_evidence_advance
  on public.employee_advance_evidence(tenant_id, advance_id);

alter table public.employee_advance_evidence enable row level security;

drop policy if exists employee_advance_evidence_read_payroll
  on public.employee_advance_evidence;
create policy employee_advance_evidence_read_payroll
  on public.employee_advance_evidence
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

revoke all on table public.employee_advance_evidence
  from public, anon, authenticated, service_role;
grant select on table public.employee_advance_evidence to authenticated;

-- Keep the receipt contract outside PostgREST's exposed schemas. The public
-- capability RPC below is the only client-facing projection; Storage and
-- app_files guards consume this same private authority.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create or replace function private.employee_advance_receipt_policy_v1()
returns jsonb
language sql
immutable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'contract_version', 1,
    'max_size_bytes', 12582912,
    'allowed_mime_types', jsonb_build_array(
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp'
    )
  );
$$;

create or replace function private.normalize_employee_advance_receipt_mime(
  p_mime text
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select lower(btrim(split_part(coalesce(p_mime, ''), ';', 1)));
$$;

create or replace function private.employee_advance_receipt_values_allowed(
  p_size_bytes bigint,
  p_mime text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select
    p_size_bytes between 1 and (
      private.employee_advance_receipt_policy_v1()->>'max_size_bytes'
    )::bigint
    and private.normalize_employee_advance_receipt_mime(p_mime) in (
      select jsonb_array_elements_text(
        private.employee_advance_receipt_policy_v1()
          ->'allowed_mime_types'
      )
    );
$$;

create or replace function private.employee_advance_receipt_metadata_allowed(
  p_metadata jsonb
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select case
    when coalesce(p_metadata->>'size', '') ~ '^[0-9]{1,18}$' then
      private.employee_advance_receipt_values_allowed(
        (p_metadata->>'size')::bigint,
        coalesce(
          nullif(btrim(p_metadata->>'mimetype'), ''),
          nullif(btrim(p_metadata->>'contentType'), ''),
          ''
        )
      )
    else false
  end;
$$;

revoke all on function private.employee_advance_receipt_policy_v1()
  from public, anon, authenticated, service_role;
revoke all on function private.normalize_employee_advance_receipt_mime(text)
  from public, anon, authenticated, service_role;
revoke all on function private.employee_advance_receipt_values_allowed(
  bigint,
  text
) from public, anon, authenticated, service_role;
revoke all on function private.employee_advance_receipt_metadata_allowed(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.employee_advance_receipt_values_allowed(
  bigint,
  text
) to authenticated;
grant execute on function private.employee_advance_receipt_metadata_allowed(
  jsonb
) to authenticated;

create or replace function public.get_employee_advance_receipt_policy_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return private.employee_advance_receipt_policy_v1();
end;
$$;

revoke all on function public.get_employee_advance_receipt_policy_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_employee_advance_receipt_policy_v1()
  to authenticated;

-- The generic app_files INSERT policy is intentionally broad for the file
-- library. Payroll evidence adds a restrictive policy so a caller cannot
-- claim another actor, label an arbitrary object as payroll evidence, or use
-- a lookalike namespace. The Storage object itself is verified by v3 below.
drop policy if exists app_files_payroll_evidence_insert_guard
  on public.app_files;
create policy app_files_payroll_evidence_insert_guard
  on public.app_files
  as restrictive
  for insert
  to authenticated
  with check (
    not (
      source_type = 'payroll_advance'
      or context_type is not distinct from 'payroll_advance_operation'
      or (
        storage_bucket = 'vinabike-files'
        and split_part(storage_path, '/', 2) = 'evidence'
        and split_part(storage_path, '/', 3) = 'payroll_advance'
      )
    )
    or (
      tenant_id = public.user_tenant_id()
      and public.can_manage_tenant_payroll(tenant_id)
      and uploaded_by = auth.uid()
      and source_type = 'payroll_advance'
      and context_type = 'payroll_advance_operation'
      and context_id is not null
      and context_id ~ '^[A-Za-z0-9:_-]{8,200}$'
      and source_id = context_id
      and metadata->>'operation_key' = context_id
      and lower(coalesce(metadata->>'sha256', '')) ~ '^[0-9a-f]{64}$'
      and private.employee_advance_receipt_values_allowed(
        size_bytes,
        mime_type
      )
      and storage_bucket = 'vinabike-files'
      and split_part(storage_path, '/', 1) = tenant_id::text
      and split_part(storage_path, '/', 2) = 'evidence'
      and split_part(storage_path, '/', 3) = 'payroll_advance'
      and split_part(storage_path, '/', 4) <> ''
    )
  );

drop policy if exists app_files_payroll_evidence_update_guard
  on public.app_files;
create policy app_files_payroll_evidence_update_guard
  on public.app_files
  as restrictive
  for update
  to authenticated
  using (
    not (
      source_type = 'payroll_advance'
      or context_type is not distinct from 'payroll_advance_operation'
      or (
        storage_bucket = 'vinabike-files'
        and split_part(storage_path, '/', 2) = 'evidence'
        and split_part(storage_path, '/', 3) = 'payroll_advance'
      )
    )
    or (
      tenant_id = public.user_tenant_id()
      and public.can_manage_tenant_payroll(tenant_id)
      and uploaded_by = auth.uid()
      and source_type = 'payroll_advance'
      and context_type = 'payroll_advance_operation'
      and context_id is not null
      and context_id ~ '^[A-Za-z0-9:_-]{8,200}$'
      and source_id = context_id
      and metadata->>'operation_key' = context_id
      and lower(coalesce(metadata->>'sha256', '')) ~ '^[0-9a-f]{64}$'
      and private.employee_advance_receipt_values_allowed(
        size_bytes,
        mime_type
      )
      and storage_bucket = 'vinabike-files'
      and split_part(storage_path, '/', 1) = tenant_id::text
      and split_part(storage_path, '/', 2) = 'evidence'
      and split_part(storage_path, '/', 3) = 'payroll_advance'
      and split_part(storage_path, '/', 4) <> ''
    )
  )
  with check (
    not (
      source_type = 'payroll_advance'
      or context_type is not distinct from 'payroll_advance_operation'
      or (
        storage_bucket = 'vinabike-files'
        and split_part(storage_path, '/', 2) = 'evidence'
        and split_part(storage_path, '/', 3) = 'payroll_advance'
      )
    )
    or (
      tenant_id = public.user_tenant_id()
      and public.can_manage_tenant_payroll(tenant_id)
      and uploaded_by = auth.uid()
      and source_type = 'payroll_advance'
      and context_type = 'payroll_advance_operation'
      and context_id is not null
      and context_id ~ '^[A-Za-z0-9:_-]{8,200}$'
      and source_id = context_id
      and metadata->>'operation_key' = context_id
      and lower(coalesce(metadata->>'sha256', '')) ~ '^[0-9a-f]{64}$'
      and private.employee_advance_receipt_values_allowed(
        size_bytes,
        mime_type
      )
      and storage_bucket = 'vinabike-files'
      and split_part(storage_path, '/', 1) = tenant_id::text
      and split_part(storage_path, '/', 2) = 'evidence'
      and split_part(storage_path, '/', 3) = 'payroll_advance'
      and split_part(storage_path, '/', 4) <> ''
    )
  );

create or replace function public.guard_payroll_advance_app_file_identity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  storage_owner_id_value text;
  storage_version_value text;
  storage_etag_value text;
  storage_size_value bigint;
  storage_mime_value text;
begin
  if new.source_type = 'payroll_advance'
     or new.context_type is not distinct from 'payroll_advance_operation'
     or (
       new.storage_bucket = 'vinabike-files'
       and split_part(new.storage_path, '/', 2) = 'evidence'
       and split_part(new.storage_path, '/', 3) = 'payroll_advance'
     ) then
    select
      nullif(object.owner_id, ''),
      nullif(btrim(object.version), ''),
      coalesce(
        nullif(btrim(object.metadata->>'eTag'), ''),
        nullif(btrim(object.metadata->>'etag'), ''),
        nullif(btrim(object.metadata->>'ETag'), '')
      ),
      case
        when coalesce(object.metadata->>'size', '') ~ '^[0-9]{1,18}$'
          then (object.metadata->>'size')::bigint
        else null
      end,
      private.normalize_employee_advance_receipt_mime(
        coalesce(
          nullif(btrim(object.metadata->>'mimetype'), ''),
          nullif(btrim(object.metadata->>'contentType'), ''),
          ''
        )
      )
    into
      storage_owner_id_value,
      storage_version_value,
      storage_etag_value,
      storage_size_value,
      storage_mime_value
    from storage.objects object
    where object.bucket_id = new.storage_bucket
      and object.name = new.storage_path
    for share;

    if auth.uid() is null
       or new.tenant_id is distinct from public.user_tenant_id()
       or not public.can_manage_tenant_payroll(new.tenant_id)
       or new.uploaded_by is distinct from auth.uid()
       or storage_owner_id_value is distinct from auth.uid()::text
       or storage_version_value is null
       or storage_etag_value is null
       or new.source_type is distinct from 'payroll_advance'
       or coalesce(new.source_id, '') !~ '^[A-Za-z0-9:_-]{8,200}$'
       or new.context_type is distinct from 'payroll_advance_operation'
       or new.context_id is distinct from new.source_id
       or new.metadata->>'operation_key' is distinct from new.context_id
       or lower(coalesce(new.metadata->>'sha256', '')) !~
         '^[0-9a-f]{64}$'
       or private.employee_advance_receipt_values_allowed(
         new.size_bytes,
         new.mime_type
       ) is not true
       or storage_size_value is distinct from new.size_bytes
       or storage_mime_value is distinct from
         private.normalize_employee_advance_receipt_mime(new.mime_type)
       or new.storage_bucket is distinct from 'vinabike-files'
       or split_part(new.storage_path, '/', 1) is distinct from
         new.tenant_id::text
       or split_part(new.storage_path, '/', 2) is distinct from 'evidence'
       or split_part(new.storage_path, '/', 3) is distinct from
         'payroll_advance'
       or split_part(new.storage_path, '/', 4) = '' then
      raise exception 'payroll_advance_app_file_identity_invalid'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_payroll_advance_app_file_identity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aab_payroll_advance_app_file_identity
  on public.app_files;
create trigger trg_aab_payroll_advance_app_file_identity
  before insert or update on public.app_files
  for each row execute function public.guard_payroll_advance_app_file_identity();

-- A blob is mutable while it is only an upload. It becomes write-once exactly
-- when a validated app_files row claims it. This keeps failed/abandoned uploads
-- recoverable without allowing a linked financial receipt to be overwritten.
create or replace function private.is_locked_employee_advance_storage_object(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
    select 1
    from public.app_files app_file
    where app_file.storage_bucket = p_bucket_id
      and app_file.storage_path = p_name
      and app_file.deleted_at is null
      and app_file.storage_bucket = 'vinabike-files'
      and split_part(app_file.storage_path, '/', 1) =
        app_file.tenant_id::text
      and split_part(app_file.storage_path, '/', 2) = 'evidence'
      and split_part(app_file.storage_path, '/', 3) = 'payroll_advance'
      and split_part(app_file.storage_path, '/', 4) <> ''
      and app_file.source_type = 'payroll_advance'
      and app_file.source_id ~ '^[A-Za-z0-9:_-]{8,200}$'
      and app_file.context_type = 'payroll_advance_operation'
      and app_file.context_id = app_file.source_id
      and app_file.metadata->>'operation_key' = app_file.context_id
      and lower(coalesce(app_file.metadata->>'sha256', '')) ~
        '^[0-9a-f]{64}$'
      and app_file.uploaded_by is not null
  );
$$;

revoke all on function private.is_locked_employee_advance_storage_object(
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function private.is_locked_employee_advance_storage_object(
  text,
  text
) to authenticated;

drop policy if exists vinabike_payroll_evidence_insert_scoped
  on storage.objects;
create policy vinabike_payroll_evidence_insert_scoped
  on storage.objects
  as restrictive
  for insert
  to authenticated
  with check (
    not (
      bucket_id = 'vinabike-files'
      and split_part(name, '/', 2) = 'evidence'
      and split_part(name, '/', 3) = 'payroll_advance'
    )
    or (
      bucket_id = 'vinabike-files'
      and split_part(name, '/', 1) = public.user_tenant_id()::text
      and split_part(name, '/', 2) = 'evidence'
      and split_part(name, '/', 3) = 'payroll_advance'
      and split_part(name, '/', 4) <> ''
      and owner_id = auth.uid()::text
      and public.can_manage_tenant_payroll(public.user_tenant_id())
      and private.employee_advance_receipt_metadata_allowed(metadata)
    )
  );

drop policy if exists vinabike_payroll_evidence_update_immutable
  on storage.objects;
create policy vinabike_payroll_evidence_update_immutable
  on storage.objects
  as restrictive
  for update
  to authenticated
  using (
    not private.is_locked_employee_advance_storage_object(bucket_id, name)
  )
  with check (
    not private.is_locked_employee_advance_storage_object(bucket_id, name)
    and (
      not (
        bucket_id = 'vinabike-files'
        and split_part(name, '/', 2) = 'evidence'
        and split_part(name, '/', 3) = 'payroll_advance'
      )
      or (
        bucket_id = 'vinabike-files'
        and split_part(name, '/', 1) = public.user_tenant_id()::text
        and split_part(name, '/', 2) = 'evidence'
        and split_part(name, '/', 3) = 'payroll_advance'
        and split_part(name, '/', 4) <> ''
        and owner_id = auth.uid()::text
        and public.can_manage_tenant_payroll(public.user_tenant_id())
        and private.employee_advance_receipt_metadata_allowed(metadata)
      )
    )
  );

drop policy if exists vinabike_payroll_evidence_delete_immutable
  on storage.objects;
create policy vinabike_payroll_evidence_delete_immutable
  on storage.objects
  as restrictive
  for delete
  to authenticated
  using (
    not private.is_locked_employee_advance_storage_object(bucket_id, name)
  );

create or replace function public.guard_employee_advance_evidence_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  advance_tenant_id uuid;
  operation_key_value text;
  operation_actor_id uuid;
  file_row public.app_files%rowtype;
  storage_object_id_value uuid;
  storage_object_version_value text;
  storage_object_etag_value text;
  storage_object_owner_id_value text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'employee_advance_evidence_is_immutable'
      using errcode = '55000';
  end if;

  select advance.tenant_id
  into advance_tenant_id
  from public.employee_advances advance
  where advance.id = new.advance_id
  for share;

  select app_file.*
  into file_row
  from public.app_files app_file
  where app_file.id = new.app_file_id
  for share;

  select money_operation.operation_key, money_operation.created_by
  into operation_key_value, operation_actor_id
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = new.tenant_id
    and money_operation.employee_advance_id = new.advance_id
    and money_operation.operation_type = 'employee_advance'
  for share;

  if file_row.id is not null then
    select
      object.id,
      nullif(btrim(object.version), ''),
      coalesce(
        nullif(btrim(object.metadata->>'eTag'), ''),
        nullif(btrim(object.metadata->>'etag'), ''),
        nullif(btrim(object.metadata->>'ETag'), '')
      ),
      nullif(object.owner_id, '')
    into
      storage_object_id_value,
      storage_object_version_value,
      storage_object_etag_value,
      storage_object_owner_id_value
    from storage.objects object
    where object.bucket_id = file_row.storage_bucket
      and object.name = file_row.storage_path
      and coalesce(object.metadata->>'size', '') =
        file_row.size_bytes::text
    for share;
  end if;

  if advance_tenant_id is null
     or advance_tenant_id <> new.tenant_id
     or operation_key_value is null
     or file_row.id is null
     or file_row.tenant_id <> new.tenant_id
     or file_row.deleted_at is not null
     or file_row.size_bytes <= 0
     or file_row.source_type is distinct from 'payroll_advance'
     or file_row.source_id is distinct from operation_key_value
     or file_row.context_type is distinct from 'payroll_advance_operation'
     or file_row.context_id is distinct from operation_key_value
     or file_row.metadata->>'operation_key' is distinct from
       operation_key_value
     or file_row.storage_bucket is distinct from 'vinabike-files'
     or split_part(file_row.storage_path, '/', 1) is distinct from
       new.tenant_id::text
     or split_part(file_row.storage_path, '/', 2) is distinct from 'evidence'
     or split_part(file_row.storage_path, '/', 3) is distinct from
       'payroll_advance'
     or split_part(file_row.storage_path, '/', 4) = ''
     or storage_object_id_value is null
     or storage_object_version_value is null
     or storage_object_etag_value is null
     or storage_object_owner_id_value is distinct from operation_actor_id::text
     or new.storage_object_id is distinct from storage_object_id_value
     or new.storage_object_version is distinct from
       storage_object_version_value
     or new.storage_object_etag is distinct from storage_object_etag_value
     or new.storage_object_owner_id::text is distinct from
       storage_object_owner_id_value
     or new.created_by is distinct from operation_actor_id
     or file_row.uploaded_by is distinct from operation_actor_id
     or lower(coalesce(file_row.metadata->>'sha256', '')) <>
       new.file_sha256 then
    raise exception 'employee_advance_evidence_invalid'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_employee_advance_evidence_row()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_employee_advance_evidence_row
  on public.employee_advance_evidence;
create trigger trg_aaa_employee_advance_evidence_row
  before insert or update or delete on public.employee_advance_evidence
  for each row execute function public.guard_employee_advance_evidence_row();

create or replace function public.guard_linked_employee_advance_app_file()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if (
       old.storage_bucket = 'vinabike-files'
       and split_part(old.storage_path, '/', 1) = old.tenant_id::text
       and split_part(old.storage_path, '/', 2) = 'evidence'
       and split_part(old.storage_path, '/', 3) = 'payroll_advance'
       and old.source_type = 'payroll_advance'
       and old.context_type = 'payroll_advance_operation'
     )
     or exists (
       select 1
       from public.employee_advance_evidence evidence
       where evidence.app_file_id = old.id
     ) then
    raise exception 'employee_advance_evidence_file_is_immutable'
      using errcode = '55000';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_linked_employee_advance_app_file()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_linked_employee_advance_app_file
  on public.app_files;
create trigger trg_aaa_linked_employee_advance_app_file
  before update or delete on public.app_files
  for each row execute function public.guard_linked_employee_advance_app_file();

create or replace function public.guard_employee_advance_storage_object()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if private.is_locked_employee_advance_storage_object(
       old.bucket_id,
       old.name
     ) then
    raise exception 'employee_advance_evidence_object_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'UPDATE'
     and private.is_locked_employee_advance_storage_object(
       new.bucket_id,
       new.name
     ) then
    raise exception 'employee_advance_evidence_object_is_immutable'
      using errcode = '55000';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_employee_advance_storage_object()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_aaa_employee_advance_storage_object
  on storage.objects;
create trigger trg_aaa_employee_advance_storage_object
  before update or delete on storage.objects
  for each row execute function public.guard_employee_advance_storage_object();

-- An earlier local draft exposed this helper through PostgREST's public
-- schema. Remove it only after policies and trigger bodies point at the
-- private owner above, so rerunning the idempotent migration is safe.
drop function if exists public.is_locked_employee_advance_storage_object(
  text,
  text
);

alter table public.payroll_money_command_contexts
  drop constraint if exists payroll_money_command_contexts_command_check;
alter table public.payroll_money_command_contexts
  add constraint payroll_money_command_contexts_command_check
  check (
    command in (
      'manual_payment',
      'advance_registration',
      'advance_audit_attach',
      'legacy_reversal'
    )
  );

create or replace function public.guard_employee_advance_money_command()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  audit_attach_allowed boolean := false;
begin
  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = new.tenant_id
         and command_context.command = 'advance_registration'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE'
     and exists (
       select 1
       from public.payroll_money_operations money_operation
       where money_operation.employee_advance_id = old.id
         and money_operation.tenant_id = old.tenant_id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use an audited idempotent reversal command';
  end if;

  if tg_op = 'UPDATE'
     and exists (
       select 1
       from public.payroll_money_operations money_operation
       where money_operation.employee_advance_id = old.id
         and money_operation.tenant_id = old.tenant_id
     ) then
    audit_attach_allowed := exists (
      select 1
      from public.payroll_money_command_contexts command_context
      where command_context.transaction_id = txid_current()
        and command_context.tenant_id = old.tenant_id
        and command_context.command = 'advance_audit_attach'
    );

    if audit_attach_allowed then
      if old.reason_code is not null
         or (
           to_jsonb(new) - array[
             'reason_code',
             'reason_explanation',
             'work_ended_on',
             'updated_at'
           ]::text[]
         ) <> (
           to_jsonb(old) - array[
             'reason_code',
             'reason_explanation',
             'work_ended_on',
             'updated_at'
           ]::text[]
         ) then
        raise exception 'payroll_advance_audit_is_immutable'
          using errcode = '55000';
      end if;
    elsif (
      to_jsonb(new) - array[
        'amount_applied',
        'status',
        'updated_at'
      ]::text[]
    ) <> (
      to_jsonb(old) - array[
        'amount_applied',
        'status',
        'updated_at'
      ]::text[]
    ) then
      raise exception 'payroll_money_receipt_movement_is_immutable'
        using
          errcode = '55000',
          detail = 'Only allocation-derived advance fields may change';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_employee_advance_money_command()
  from public, anon, authenticated, service_role;

create or replace function public.register_employee_advance_v3(
  p_operation_key text,
  p_employee_id uuid,
  p_amount numeric,
  p_payment_method_id uuid,
  p_payment_account_id uuid,
  p_paid_at timestamp with time zone,
  p_reference text,
  p_notes text,
  p_reason_code text,
  p_reason_explanation text,
  p_work_ended_on date,
  p_evidence_file_id uuid,
  p_evidence_file_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := btrim(coalesce(p_operation_key, ''));
  reason_code_value text := lower(btrim(coalesce(p_reason_code, '')));
  reason_explanation_value text := btrim(
    coalesce(p_reason_explanation, '')
  );
  evidence_sha256_value text := lower(
    btrim(coalesce(p_evidence_file_sha256, ''))
  );
  receipt_value jsonb;
  advance_id_value uuid;
  advance_row public.employee_advances%rowtype;
  evidence_row public.employee_advance_evidence%rowtype;
  audit_preexisting boolean;
  evidence_owner_id uuid;
  evidence_file_row public.app_files%rowtype;
  evidence_storage_object_id uuid;
  evidence_storage_object_version text;
  evidence_storage_object_etag text;
  evidence_storage_object_owner_id text;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if reason_code_value not in (
       'requested_advance',
       'short_workweek',
       'other'
     )
     or char_length(reason_explanation_value) not between 1 and 1000
     or (
       reason_code_value = 'short_workweek'
       and p_work_ended_on is null
     )
     or (
       reason_code_value <> 'short_workweek'
       and p_work_ended_on is not null
     )
     or (
       p_work_ended_on is not null
       and p_work_ended_on not between date '1900-01-01' and date '2100-12-31'
     ) then
    raise exception 'payroll_advance_invalid_reason'
      using errcode = '22023';
  end if;

  if (p_evidence_file_id is null) <>
       (evidence_sha256_value = '')
     or (
       evidence_sha256_value <> ''
       and evidence_sha256_value !~ '^[0-9a-f]{64}$'
     ) then
    raise exception 'payroll_advance_invalid_evidence'
      using errcode = '22023';
  end if;

  select money_operation.created_by
  into evidence_owner_id
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = tenant_id_value
    and money_operation.operation_key = operation_key_value
    and money_operation.operation_type = 'employee_advance';

  evidence_owner_id := coalesce(evidence_owner_id, auth.uid());

  if p_evidence_file_id is not null then
    select app_file.*
    into evidence_file_row
    from public.app_files app_file
    where app_file.id = p_evidence_file_id
    for share;

    if evidence_file_row.id is not null then
      select
        object.id,
        nullif(btrim(object.version), ''),
        coalesce(
          nullif(btrim(object.metadata->>'eTag'), ''),
          nullif(btrim(object.metadata->>'etag'), ''),
          nullif(btrim(object.metadata->>'ETag'), '')
        ),
        nullif(object.owner_id, '')
      into
        evidence_storage_object_id,
        evidence_storage_object_version,
        evidence_storage_object_etag,
        evidence_storage_object_owner_id
      from storage.objects object
      where object.bucket_id = evidence_file_row.storage_bucket
        and object.name = evidence_file_row.storage_path
        and coalesce(object.metadata->>'size', '') =
          evidence_file_row.size_bytes::text
      for share;
    end if;

    if evidence_file_row.id is null
       or evidence_file_row.tenant_id <> tenant_id_value
       or evidence_file_row.deleted_at is not null
       or evidence_file_row.size_bytes <= 0
       or evidence_file_row.source_type <> 'payroll_advance'
       or evidence_file_row.source_id <> operation_key_value
       or evidence_file_row.context_type <> 'payroll_advance_operation'
       or evidence_file_row.context_id <> operation_key_value
       or evidence_file_row.metadata->>'operation_key' <>
         operation_key_value
       or evidence_file_row.storage_bucket <> 'vinabike-files'
       or split_part(evidence_file_row.storage_path, '/', 1) <>
         tenant_id_value::text
       or split_part(evidence_file_row.storage_path, '/', 2) <> 'evidence'
       or split_part(evidence_file_row.storage_path, '/', 3) <>
         'payroll_advance'
       or split_part(evidence_file_row.storage_path, '/', 4) = ''
       or evidence_storage_object_id is null
       or evidence_storage_object_version is null
       or evidence_storage_object_etag is null
       or evidence_storage_object_owner_id is distinct from
         evidence_owner_id::text
       or evidence_file_row.uploaded_by is distinct from evidence_owner_id
       or lower(coalesce(evidence_file_row.metadata->>'sha256', '')) <>
         evidence_sha256_value then
      raise exception 'payroll_advance_evidence_not_found'
        using errcode = '42501';
    end if;
  end if;

  receipt_value := public.register_employee_advance_v2(
    operation_key_value,
    p_employee_id,
    p_amount,
    p_payment_method_id,
    p_payment_account_id,
    p_paid_at,
    p_reference,
    p_notes
  );

  advance_id_value := nullif(receipt_value->>'advance_id', '')::uuid;
  select advance.*
  into advance_row
  from public.employee_advances advance
  where advance.id = advance_id_value
    and advance.tenant_id = tenant_id_value
  for update;

  if advance_row.id is null then
    raise exception 'payroll_advance_receipt_invalid'
      using errcode = '55000';
  end if;

  select evidence.*
  into evidence_row
  from public.employee_advance_evidence evidence
  where evidence.tenant_id = tenant_id_value
    and evidence.advance_id = advance_id_value
  for update;

  audit_preexisting := advance_row.reason_code is not null;

  if audit_preexisting then
    if advance_row.reason_code <> reason_code_value
       or advance_row.reason_explanation <> reason_explanation_value
       or advance_row.work_ended_on is distinct from p_work_ended_on
       or (evidence_row.id is null) <> (p_evidence_file_id is null)
       or (
         evidence_row.id is not null
         and (
           evidence_row.app_file_id <> p_evidence_file_id
           or evidence_row.file_sha256 <> evidence_sha256_value
           or evidence_row.storage_object_id <>
             evidence_storage_object_id
           or evidence_row.storage_object_version <>
             evidence_storage_object_version
           or evidence_row.storage_object_etag <>
             evidence_storage_object_etag
           or evidence_row.storage_object_owner_id <>
             evidence_storage_object_owner_id::uuid
         )
       ) then
      raise exception 'payroll_advance_audit_idempotency_conflict'
        using errcode = 'P0001';
    end if;
  else
    insert into public.payroll_money_command_contexts (
      transaction_id,
      tenant_id,
      command,
      operation_key,
      actor_id
    ) values (
      txid_current(),
      tenant_id_value,
      'advance_audit_attach',
      operation_key_value,
      auth.uid()
    );

    update public.employee_advances advance
    set reason_code = reason_code_value,
        reason_explanation = reason_explanation_value,
        work_ended_on = p_work_ended_on
    where advance.id = advance_id_value
      and advance.tenant_id = tenant_id_value;

    delete from public.payroll_money_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.tenant_id = tenant_id_value
      and command_context.command = 'advance_audit_attach';

    if p_evidence_file_id is not null then
      insert into public.employee_advance_evidence (
        tenant_id,
        advance_id,
        app_file_id,
        storage_object_id,
        storage_object_version,
        storage_object_etag,
        storage_object_owner_id,
        file_sha256,
        created_by
      ) values (
        tenant_id_value,
        advance_id_value,
        p_evidence_file_id,
        evidence_storage_object_id,
        evidence_storage_object_version,
        evidence_storage_object_etag,
        evidence_storage_object_owner_id::uuid,
        evidence_sha256_value,
        auth.uid()
      )
      returning * into evidence_row;
    end if;
  end if;

  return receipt_value || jsonb_build_object(
    'reason_code', reason_code_value,
    'reason_explanation', reason_explanation_value,
    'work_ended_on', p_work_ended_on,
    'evidence_file_id', evidence_row.app_file_id,
    'evidence_file_sha256', evidence_row.file_sha256,
    'evidence_storage_object_id', evidence_row.storage_object_id,
    'evidence_storage_object_version', evidence_row.storage_object_version,
    'evidence_storage_object_etag', evidence_row.storage_object_etag,
    'replayed', audit_preexisting
  );
end;
$$;

revoke all on function public.register_employee_advance_v3(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  date,
  uuid,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.register_employee_advance_v3(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  date,
  uuid,
  text
) to authenticated;

create or replace function public.get_employee_advance_ledger_page_v2(
  p_employee_id uuid,
  p_page_size integer default 25,
  p_cursor_paid_at timestamp with time zone default null,
  p_cursor_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  base_page jsonb;
  enriched_items jsonb;
begin
  base_page := public.get_employee_advance_ledger_page_v1(
    p_employee_id,
    p_page_size,
    p_cursor_paid_at,
    p_cursor_id
  );

  select coalesce(
    jsonb_agg(
      item_row.item || jsonb_build_object(
        'reason',
          case
            when advance.reason_code is null then null
            else jsonb_build_object(
              'code', advance.reason_code,
              'explanation', advance.reason_explanation,
              'work_ended_on', advance.work_ended_on
            )
          end,
        'original_evidence',
          case
            when evidence.id is null then null
            else jsonb_build_object(
              'id', evidence.id,
              'app_file_id', evidence.app_file_id,
              'file_name', app_file.file_name,
              'mime_type', app_file.mime_type,
              'size_bytes', app_file.size_bytes,
              'sha256', evidence.file_sha256,
              'storage_object_id', evidence.storage_object_id,
              'storage_object_version', evidence.storage_object_version,
              'storage_object_etag', evidence.storage_object_etag,
              'created_at', evidence.created_at,
              'created_by', evidence.created_by
            )
          end
      )
      order by item_row.ordinality
    ),
    '[]'::jsonb
  )
  into enriched_items
  from jsonb_array_elements(base_page->'items')
    with ordinality as item_row(item, ordinality)
  join public.employee_advances advance
    on advance.id = (item_row.item->>'id')::uuid
   and advance.tenant_id = tenant_id_value
  left join public.employee_advance_evidence evidence
    on evidence.advance_id = advance.id
   and evidence.tenant_id = advance.tenant_id
  left join public.app_files app_file
    on app_file.id = evidence.app_file_id
   and app_file.tenant_id = evidence.tenant_id;

  return jsonb_set(
    jsonb_set(base_page, '{contract_version}', '2'::jsonb),
    '{items}',
    enriched_items
  );
end;
$$;

revoke all on function public.get_employee_advance_ledger_page_v2(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) from public, anon, authenticated, service_role;
grant execute on function public.get_employee_advance_ledger_page_v2(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) to authenticated;

comment on table public.employee_advance_evidence is
  'Append-only tenant-scoped link from one employee advance to its original canonical app_files receipt and immutable SHA-256 snapshot.';
comment on function public.get_employee_advance_receipt_policy_v1() is
  'Payroll-authorized capability returning the exact versioned size and MIME contract for immutable employee-advance receipts.';
comment on function public.register_employee_advance_v3(
  text,
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  date,
  uuid,
  text
) is
  'Expand-first idempotent employee-advance command requiring structured reason audit and optionally attaching one immutable original app_files receipt.';
comment on function public.get_employee_advance_ledger_page_v2(
  uuid,
  integer,
  timestamp with time zone,
  uuid
) is
  'Version 2 of the bounded employee-advance ledger, enriched with structured reason and immutable original-receipt evidence.';

commit;
