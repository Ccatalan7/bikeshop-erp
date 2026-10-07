-- «Versiones guardadas», second review (2026-10-06):
--
-- * `record_website_version` leaves the automatic version of a «Guardar» for
--   whoever may save the site (`can_edit_tenant_settings`, the same check as
--   `replace_page_blocks`). `create_website_backup` stays admin-only for
--   versions saved by hand, and restoring stays admin-only too.
-- * Restoring puts back each page's own data from the version (title,
--   Google title and description, published, template) — captured since the
--   start but never restored — and leaves out the blocks of a page deleted
--   since, which made the whole restore fail on `page_id`.
-- * Settings keys added after a version are deliberately kept: integration
--   keys live in the same table and must not vanish by going back.

create or replace function public.record_website_version(
  p_name text,
  p_description text default null::text
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if auth.uid() is null
     or v_tenant_id is null
     or not public.can_edit_tenant_settings(v_tenant_id) then
    raise exception 'website_version_forbidden' using errcode = '42501';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'website_version_name_required' using errcode = '22023';
  end if;
  return public.create_website_backup_internal(
    left(btrim(p_name), 200),
    nullif(btrim(coalesce(p_description, '')), ''),
    true
  );
end;
$function$;

revoke all on function public.record_website_version(text, text)
  from public, anon;
grant execute on function public.record_website_version(text, text)
  to authenticated;

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

  -- The pages' own data (title, Google, published, template) as it was; a
  -- page created since stays, a page deleted since is not recreated.
  update website_pages page
     set title = coalesce(nullif(snap->>'title', ''), page.title),
         meta_title = snap->>'meta_title',
         meta_description = snap->>'meta_description',
         is_published = coalesce((snap->>'is_published')::boolean,
                                 page.is_published),
         template = coalesce(snap->>'template', page.template),
         updated_at = now()
    from jsonb_array_elements(coalesce(v_backup.pages_snapshot, '[]'::jsonb))
         snap
   where page.tenant_id = v_tenant_id
     and page.id = (snap->>'id')::uuid;

  -- Restore blocks from snapshot (a block of a page deleted since stays out)
  for v_block in select * from jsonb_array_elements(v_backup.blocks_snapshot)
  loop
    continue when (v_block.value->>'page_id') is not null
      and not exists (
        select 1
          from website_pages page
         where page.tenant_id = v_tenant_id
           and page.id = (v_block.value->>'page_id')::uuid
      );
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
