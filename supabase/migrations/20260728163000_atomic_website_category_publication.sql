-- Deployment status: applied to production and registered on 2026-07-28.
-- Verified: postgres-owned SECURITY DEFINER function, fixed search_path,
-- authenticated-only execute grant, tenant serialization and audit marker;
-- the live 5/133 category selection remained unchanged.
--
-- Replace the public category set in one tenant-scoped transaction. The
-- previous client sequence first hid every category and then published the
-- selected IDs in a second request, so a failure or concurrent save could
-- leave a partial public catalog and rewrote updated_at on every category.

create or replace function public.replace_website_category_visibility(
  p_tenant_id uuid,
  p_visible_category_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_tenant_id uuid := public.user_tenant_id();
  v_requested_ids uuid[];
  v_before_ids uuid[];
  v_added_ids uuid[];
  v_removed_ids uuid[];
  v_invalid_ids uuid[];
  v_changed_at timestamptz := clock_timestamp();
begin
  if v_caller_id is null
     or p_tenant_id is null
     or v_caller_tenant_id is distinct from p_tenant_id then
    raise exception 'website_category_publication_tenant_forbidden'
      using errcode = '42501';
  end if;

  if array_position(p_visible_category_ids, null) is not null then
    raise exception 'website_category_publication_invalid_category'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(requested.category_id order by requested.category_id),
    '{}'::uuid[]
  )
  into v_requested_ids
  from (
    select distinct category_id
    from unnest(
      coalesce(p_visible_category_ids, '{}'::uuid[])
    ) as requested_id(category_id)
  ) requested;

  -- Serialize replacements for the same tenant without locking unrelated
  -- stores or widening the transaction to the whole categories table.
  perform pg_advisory_xact_lock(
    hashtextextended(
      'website_category_publication:' || p_tenant_id::text,
      0
    )
  );

  select coalesce(
    array_agg(requested.category_id order by requested.category_id),
    '{}'::uuid[]
  )
  into v_invalid_ids
  from unnest(v_requested_ids) requested(category_id)
  left join public.product_categories category
    on category.id = requested.category_id
   and category.tenant_id = p_tenant_id
   and category.is_active is true
  where category.id is null;

  if cardinality(v_invalid_ids) > 0 then
    raise exception 'website_category_publication_invalid_category'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(category.id order by category.id),
    '{}'::uuid[]
  )
  into v_before_ids
  from public.product_categories category
  where category.tenant_id = p_tenant_id
    and category.show_on_website is true;

  select coalesce(
    array_agg(category_id order by category_id),
    '{}'::uuid[]
  )
  into v_added_ids
  from (
    select unnest(v_requested_ids) as category_id
    except
    select unnest(v_before_ids) as category_id
  ) added;

  select coalesce(
    array_agg(category_id order by category_id),
    '{}'::uuid[]
  )
  into v_removed_ids
  from (
    select unnest(v_before_ids) as category_id
    except
    select unnest(v_requested_ids) as category_id
  ) removed;

  update public.product_categories category
  set show_on_website = category.id = any(v_requested_ids),
      updated_at = v_changed_at
  where category.tenant_id = p_tenant_id
    and category.show_on_website is distinct from (
      category.id = any(v_requested_ids)
    );

  if cardinality(v_added_ids) > 0 or cardinality(v_removed_ids) > 0 then
    insert into public.user_activity_log (
      tenant_id,
      user_id,
      action,
      details,
      performed_by,
      created_at
    )
    values (
      p_tenant_id,
      v_caller_id,
      'website_category_publication_replaced',
      jsonb_build_object(
        'before_ids', to_jsonb(v_before_ids),
        'after_ids', to_jsonb(v_requested_ids),
        'added_ids', to_jsonb(v_added_ids),
        'removed_ids', to_jsonb(v_removed_ids)
      ),
      v_caller_id,
      v_changed_at
    );
  end if;

  return jsonb_build_object(
    'visible_ids', to_jsonb(v_requested_ids),
    'added_ids', to_jsonb(v_added_ids),
    'removed_ids', to_jsonb(v_removed_ids),
    'changed_at', v_changed_at
  );
end;
$$;

revoke all on function public.replace_website_category_visibility(uuid, uuid[])
  from public, anon;
grant execute on function public.replace_website_category_visibility(uuid, uuid[])
  to authenticated;
