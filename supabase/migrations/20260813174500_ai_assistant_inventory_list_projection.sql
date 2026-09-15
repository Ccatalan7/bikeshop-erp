-- Deployment status (2026-08-13): production-applied through the guarded
-- standalone-SQL path and registered as 20260813174500. Live read-back proved
-- SECURITY DEFINER, stable volatility, fixed search_path, 4500 ms timeout,
-- authenticated-only EXECUTE and availability filtering before the bounded
-- result set. The production-derived focused pgTAP passed 54/54.
--
begin;

-- V2 makes availability part of the authorized read instead of letting the
-- model and the UI independently filter a generic first-N result. The exact
-- same bounded rows now feed synthesis, the compact list projection and the
-- product-list navigation contract.
create or replace function public.assistant_search_inventory_v2(
  p_query text,
  p_availability text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or p_availability not in (
       'any', 'in_stock', 'low_stock', 'out_of_stock'
     ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with scoped as materialized (
    select
      product.id entity_id,
      product.name,
      product.sku,
      product.brand,
      product.category_name,
      product.category,
      product.price,
      product.warehouse_location,
      product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      case
        when coalesce(product.is_set, false)
          then coalesce(product.full_sets_available, 0)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end available_stock
    from public.products_with_sets product
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
      and not exists (
        select 1
        from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', product.name, product.sku, product.barcode,
            product.brand, product.model, product.manufacturer,
            product.category_name, product.category, product.description)
        )) = 0
      )
  ), matched as materialized (
    select
      scoped.*,
      case
        when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock'
      end availability
    from scoped
    where p_availability = 'any'
       or (p_availability = 'in_stock'
         and tracks_inventory and available_stock > 0)
       or (p_availability = 'low_stock'
         and tracks_inventory and available_stock > 0
         and available_stock <= minimum_stock)
       or (p_availability = 'out_of_stock'
         and tracks_inventory and available_stock <= 0)
    order by
      (public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (position(v_query in public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last,
      name
    limit 11
  ), numbered as (
    select
      entity_id, name, sku, brand, category_name, category, price,
      warehouse_location, available_stock, minimum_stock, availability,
      tracks_inventory,
      row_number() over (
        order by
          (public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
          (position(v_query in public.assistant_normalize_query_internal_v1(name)) > 0) desc,
          updated_at desc nulls last,
          name
      ) ordinal
    from matched
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(category_name, category, ''), 100), ''),
      'price', price,
      'stock', available_stock,
      'minimumStock', minimum_stock,
      'availability', availability,
      'tracksInventory', tracks_inventory,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(warehouse_location, ''), 120), '')
    ) order by ordinal) filter (where ordinal <= 10), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    v_total > 10
  );
end;
$$;

revoke all on function public.assistant_search_inventory_v2(text, text)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_search_inventory_v2(text, text)
to authenticated;

comment on function public.assistant_search_inventory_v2(text, text) is
  'Tenant-bound inventory search whose availability filter is applied before the bounded result set used by assistant synthesis and list navigation.';

commit;
