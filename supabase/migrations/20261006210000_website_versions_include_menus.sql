-- «Versiones guardadas» also carry the menus (2026-10-06, Codex review of
-- 20261006200000): a version left by a «Guardar» that changed the menus
-- restored blocks and settings but never `website_navigation`, so going back
-- to it left the current menus in place.
--
-- * `website_backups.navigation_snapshot` keeps the tenant's menu rows
--   (without tenant_id). Older versions keep it null and their restore leaves
--   the menus as they are, as before.
-- * Creating a version takes a per-tenant transaction lock first, so two
--   saves at the same time cannot both see themselves as the 30th and leave
--   31 automatic versions.
-- * Restoring replaces the tenant's menu rows by the snapshot's: inserted
--   without parents, then each parent set (the self reference cascades on
--   delete and is checked on every row).

alter table public.website_backups
  add column if not exists navigation_snapshot jsonb;

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
  v_navigation jsonb;
  v_block_count integer;
begin
  v_tenant_id := public.user_tenant_id();
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;

  -- One version at a time per tenant: the prune below must see the others.
  perform pg_advisory_xact_lock(
    hashtextextended('website_backups:' || v_tenant_id::text, 0)
  );

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

  -- Snapshot the menus
  select coalesce(
    jsonb_agg(to_jsonb(nav) - 'tenant_id' order by nav.created_at, nav.id),
    '[]'::jsonb
  )
  into v_navigation
  from website_navigation nav
  where nav.tenant_id = v_tenant_id;

  -- Insert backup
  insert into website_backups (
    tenant_id, name, description, blocks_snapshot, settings_snapshot,
    pages_snapshot, navigation_snapshot, block_count, is_auto_backup,
    created_by
  ) values (
    v_tenant_id, p_name, p_description, v_blocks, v_settings,
    v_pages, v_navigation, v_block_count, p_is_auto, auth.uid()
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

  -- Restore the menus (a version from before 2026-10-06 has none: they stay)
  if v_backup.navigation_snapshot is not null then
    delete from website_navigation where tenant_id = v_tenant_id;

    insert into website_navigation (
      id, tenant_id, menu_location, label, icon, link_type, link_value,
      open_in_new_tab, parent_id, order_index, is_visible, show_on_desktop,
      show_on_mobile, css_class, highlight, created_at, updated_at
    )
    select r.id, v_tenant_id, r.menu_location, r.label, r.icon, r.link_type,
           r.link_value, r.open_in_new_tab, null, r.order_index, r.is_visible,
           r.show_on_desktop, r.show_on_mobile, r.css_class, r.highlight,
           coalesce(r.created_at, now()), now()
      from jsonb_populate_recordset(
             null::public.website_navigation,
             v_backup.navigation_snapshot
           ) r;

    update website_navigation nav
       set parent_id = r.parent_id
      from jsonb_populate_recordset(
             null::public.website_navigation,
             v_backup.navigation_snapshot
           ) r
     where nav.tenant_id = v_tenant_id
       and nav.id = r.id
       and r.parent_id is not null
       and exists (
         select 1
           from website_navigation parent
          where parent.tenant_id = v_tenant_id
            and parent.id = r.parent_id
       );
  end if;

  return true;
end;
$function$;
