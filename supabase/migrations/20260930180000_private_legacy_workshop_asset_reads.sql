-- C3: destino privado y lectura de las fotos heredadas que tienen trabajo.
-- PREPARED: no copia, cambia un vínculo ni retira un objeto público.
-- Las referencias antiguas siguen siendo identidades estables, también en
-- respaldos. El consumidor resuelve la copia sólo después de comprobar sus
-- bytes y el vínculo vivo. Los PDF/HEIC sin trabajo atribuido quedan fuera.
begin;

insert into storage.buckets (id, name, public, file_size_limit)
values ('workshop-legacy-private', 'workshop-legacy-private', false, 20971520)
on conflict (id) do update
set public = false, file_size_limit = excluded.file_size_limit;

create table public.workshop_legacy_asset_copies (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  customer_id uuid not null references public.customers(id),
  job_id uuid not null references public.mechanic_jobs(id),
  source_bucket text not null default 'vinabike-assets'
    check (source_bucket = 'vinabike-assets'),
  source_path text not null unique,
  source_reference text not null unique,
  storage_path text not null unique,
  file_name text not null,
  mime_type text not null,
  source_size_bytes bigint not null check (source_size_bytes between 1 and 20971520),
  private_size_bytes bigint not null,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  private_sha256 text not null,
  copied_at timestamptz not null,
  verified_at timestamptz not null,
  public_retired_at timestamptz,
  constraint workshop_legacy_asset_copy_bytes check (
    private_size_bytes = source_size_bytes and private_sha256 = source_sha256
    and verified_at >= copied_at
  ),
  constraint workshop_legacy_asset_copy_source check (
    source_path = 'mechanic_jobs/' || customer_id::text || '/' || file_name
    and split_part(source_reference,
      '/storage/v1/object/public/vinabike-assets/', 2) = source_path
    and source_reference ~ '^https?://[^/]+/storage/v1/object/public/vinabike-assets/'
  ),
  constraint workshop_legacy_asset_copy_path check (
    storage_path = tenant_id::text || '/' || job_id::text || '/' || id::text || '/' || file_name
    and length(file_name) between 1 and 255
    and file_name not in ('.', '..')
    and position('/' in file_name) = 0 and position(chr(92) in file_name) = 0
    and position('?' in file_name) = 0 and position('#' in file_name) = 0
  )
);

-- Sólo el procedimiento de copia revisado, ejecutado como postgres, anota
-- los dos hashes tras descargar ambos objetos. Ni staff ni portal pueden
-- fabricar un recibo o subir/reemplazar/borrar bytes en este bucket.
alter table public.workshop_legacy_asset_copies enable row level security;
revoke all on public.workshop_legacy_asset_copies
  from public, anon, authenticated, service_role;

create function public.workshop_legacy_asset_copy_guard_v1()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, storage, pg_temp
as $$
begin
  if not exists (
    select 1 from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    where job.id = new.job_id and job.tenant_id = new.tenant_id
      and customer.id = new.customer_id
      and new.source_reference = any(coalesce(job.image_urls, '{}'::text[]))
  ) or not exists (
    select 1 from storage.objects object
    where object.bucket_id = 'workshop-legacy-private'
      and object.name = new.storage_path
      and (object.metadata->>'size')::bigint = new.private_size_bytes
  ) then
    raise exception 'La copia no coincide con el archivo y el dueño del trabajo.'
      using errcode = '23514';
  end if;
  return new;
end
$$;
revoke all on function public.workshop_legacy_asset_copy_guard_v1()
  from public, anon, authenticated, service_role;
create trigger workshop_legacy_asset_copy_guard
  before insert or update on public.workshop_legacy_asset_copies
  for each row execute function public.workshop_legacy_asset_copy_guard_v1();

create function public.workshop_legacy_asset_job_can_read_v1(p_job_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select auth.uid() is not null and exists (
    select 1 from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    where job.id = p_job_id and public.is_tenant_active(job.tenant_id)
      and (
        public.is_active_tenant_member(job.tenant_id)
        or (job.deleted_at is null and customer.is_active is true
          and customer.auth_user_id = auth.uid())
      )
  )
$$;

create function public.workshop_legacy_asset_storage_can_read_v1(p_path text)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1 from public.workshop_legacy_asset_copies copy
    join public.mechanic_jobs job
      on job.id = copy.job_id and job.tenant_id = copy.tenant_id
        and job.customer_id = copy.customer_id
    where copy.storage_path = p_path
      and copy.source_reference = any(coalesce(job.image_urls, '{}'::text[]))
      and public.workshop_legacy_asset_job_can_read_v1(job.id)
  )
$$;

create policy workshop_legacy_private_select on storage.objects
  for select to authenticated
  using (bucket_id = 'workshop-legacy-private'
    and public.workshop_legacy_asset_storage_can_read_v1(name));

-- Las políticas permisivas antiguas se combinan con OR. Este destino tiene
-- su propio cerco restrictivo: otra política del bucket público no puede
-- autorizar un SELECT ni una escritura privada por accidente.
create policy workshop_legacy_private_authenticated_guard on storage.objects
  as restrictive for select to authenticated
  using (bucket_id <> 'workshop-legacy-private'
    or public.workshop_legacy_asset_storage_can_read_v1(name));
create policy workshop_legacy_private_anon_guard on storage.objects
  as restrictive for select to anon
  using (bucket_id <> 'workshop-legacy-private');
create policy workshop_legacy_private_insert_guard on storage.objects
  as restrictive for insert to anon, authenticated
  with check (bucket_id <> 'workshop-legacy-private');
create policy workshop_legacy_private_update_guard on storage.objects
  as restrictive for update to anon, authenticated
  using (bucket_id <> 'workshop-legacy-private')
  with check (bucket_id <> 'workshop-legacy-private');
create policy workshop_legacy_private_delete_guard on storage.objects
  as restrictive for delete to anon, authenticated
  using (bucket_id <> 'workshop-legacy-private');

create function public.workshop_legacy_asset_read_v1(p_reference text)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, public, auth, storage, pg_temp
as $$
declare
  v_copy public.workshop_legacy_asset_copies%rowtype;
begin
  if auth.uid() is null or not exists (
    select 1 from public.mechanic_jobs job
    where p_reference = any(coalesce(job.image_urls, '{}'::text[]))
      and public.workshop_legacy_asset_job_can_read_v1(job.id)
  ) then
    raise exception 'No tienes acceso a este archivo del trabajo.' using errcode = '42501';
  end if;
  select * into v_copy from public.workshop_legacy_asset_copies copy
  where copy.source_reference = p_reference;
  if not found then
    -- No convierte los bytes públicos en privados. Permite que el cliente
    -- preparado funcione antes de la copia autorizada, con vínculo comprobado.
    return jsonb_build_object('mode', 'legacy', 'url', p_reference);
  end if;
  if not public.workshop_legacy_asset_storage_can_read_v1(v_copy.storage_path)
    or not exists (
      select 1 from storage.objects object
      where object.bucket_id = 'workshop-legacy-private'
        and object.name = v_copy.storage_path
        and (object.metadata->>'size')::bigint = v_copy.private_size_bytes
    ) then
    raise exception 'La copia privada del archivo no está disponible. Pide al taller que la revise.'
      using errcode = '55000';
  end if;
  return jsonb_build_object(
    'mode', 'private', 'id', v_copy.id, 'bucket', 'workshop-legacy-private',
    'path', v_copy.storage_path, 'file_name', v_copy.file_name,
    'mime_type', v_copy.mime_type, 'size_bytes', v_copy.private_size_bytes
  );
end
$$;

revoke all on function public.workshop_legacy_asset_job_can_read_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.workshop_legacy_asset_storage_can_read_v1(text)
  from public, anon, service_role;
grant execute on function public.workshop_legacy_asset_storage_can_read_v1(text)
  to authenticated;
revoke all on function public.workshop_legacy_asset_read_v1(text)
  from public, anon, service_role;
grant execute on function public.workshop_legacy_asset_read_v1(text) to authenticated;

comment on table public.workshop_legacy_asset_copies is
  'Recibos privados de fotos heredadas: dueño exacto, bytes originales y privados verificados; no atribuye los objetos sin vínculo.';
comment on function public.workshop_legacy_asset_read_v1(text) is
  'Resuelve una referencia estable sólo para staff activo o su cliente; una copia faltante/revocada nunca vuelve a su URL pública.';

notify pgrst, 'reload schema';
commit;
