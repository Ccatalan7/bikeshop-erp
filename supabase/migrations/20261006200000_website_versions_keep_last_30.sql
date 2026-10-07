-- «Versiones guardadas» (approved editor proposal, 2026-10-06): every
-- «Guardar» in the site editor leaves an automatic version
-- (website_backups.is_auto_backup = true). The tenant keeps its last 30
-- automatic versions; versions saved with a name are never pruned. The safety
-- version taken before restoring is named in Spanish, as the editor shows it.
--
-- Same bodies as before otherwise: tenant from public.user_tenant_id(), the
-- same snapshot of blocks, settings and pages, the same restore.

create or replace function public.create_website_backup_internal(
  p_name text,
  p_description text default null::text,
  p_is_auto boolean default false
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_tenant_id uuid;
  v_backup_id uuid;
  v_blocks jsonb;
  v_settings jsonb;
  v_pages jsonb;
  v_block_count integer;
begin
  v_tenant_id := public.user_tenant_id();
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;

  -- Snapshot all blocks
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'block_type', block_type,
      'block_data', block_data,
      'is_visible', is_visible,
      'order_index', order_index,
      'page_id', page_id
    ) order by order_index
  ), '[]'::jsonb)
  into v_blocks
  from website_blocks
  where tenant_id = v_tenant_id;

  select count(*) into v_block_count from website_blocks where tenant_id = v_tenant_id;

  -- Snapshot all settings
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  into v_settings
  from website_settings
  where tenant_id = v_tenant_id;

  -- Snapshot all pages
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id,
      'slug', slug,
      'title', title,
      'meta_title', meta_title,
      'meta_description', meta_description,
      'is_published', is_published,
      'is_home', is_home,
      'template', template
    ) order by created_at
  ), '[]'::jsonb)
  into v_pages
  from website_pages
  where tenant_id = v_tenant_id;

  -- Insert backup
  insert into website_backups (
    tenant_id, name, description, blocks_snapshot, settings_snapshot,
    pages_snapshot, block_count, is_auto_backup, created_by
  ) values (
    v_tenant_id, p_name, p_description, v_blocks, v_settings,
    v_pages, v_block_count, p_is_auto, auth.uid()
  )
  returning id into v_backup_id;

  -- The last 30 automatic versions stay; named ones are never pruned.
  if p_is_auto then
    delete from website_backups
     where tenant_id = v_tenant_id
       and is_auto_backup
       and id in (
         select id
           from website_backups
          where tenant_id = v_tenant_id
            and is_auto_backup
          order by created_at desc, id desc
         offset 30
       );
  end if;

  return v_backup_id;
end;
$function$;

create or replace function public.restore_website_backup_internal(
  p_backup_id uuid,
  p_create_safety_backup boolean default true
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_tenant_id uuid;
  v_backup record;
  v_block record;
begin
  v_tenant_id := public.user_tenant_id();
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;

  select * into v_backup
  from website_backups
  where id = p_backup_id and tenant_id = v_tenant_id;

  if not found then
    raise exception 'Backup not found or access denied';
  end if;

  -- Create safety backup before restoring
  if p_create_safety_backup then
    perform public.create_website_backup(
      'Antes de volver a «' || v_backup.name || '»',
      'Versión guardada sola antes de volver a una anterior.',
      true
    );
  end if;

  -- Delete current blocks
  delete from website_blocks where tenant_id = v_tenant_id;

  -- Restore blocks from snapshot
  for v_block in select * from jsonb_array_elements(v_backup.blocks_snapshot)
  loop
    insert into website_blocks (
      id, tenant_id, block_type, block_data, is_visible, order_index, page_id
    ) values (
      coalesce((v_block.value->>'id')::uuid, gen_random_uuid()),
      v_tenant_id,
      v_block.value->>'block_type',
      (v_block.value->'block_data')::jsonb,
      coalesce((v_block.value->>'is_visible')::boolean, true),
      coalesce((v_block.value->>'order_index')::integer, 0),
      (v_block.value->>'page_id')::uuid
    );
  end loop;

  -- Restore settings
  insert into website_settings (tenant_id, key, value)
  select v_tenant_id, key, value
  from jsonb_each_text(v_backup.settings_snapshot)
  on conflict (tenant_id, key) do update
  set value = excluded.value, updated_at = now();

  return true;
end;
$function$;
