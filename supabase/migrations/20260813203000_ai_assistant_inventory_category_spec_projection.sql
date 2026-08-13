-- Inventory discovery must not treat a free-text product-name search as the
-- whole retrieval contract. The model names the catalog category separately;
-- PostgreSQL resolves it through product_categories/category_tech_mappings,
-- then applies canonical technical facts and stock inside the same projection.
begin;

create or replace function public.assistant_search_inventory_v4(
  p_query text,
  p_category text,
  p_availability text,
  p_technical_filters jsonb
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
  v_category text;
  v_filter jsonb;
  v_filter_field text;
  v_filter_value text;
  v_filter_fields text[] := array[]::text[];
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
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability not in (
       'any', 'in_stock', 'low_stock', 'out_of_stock'
     )
     or jsonb_typeof(p_technical_filters) <> 'array'
     or jsonb_array_length(p_technical_filters) > 6 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category),
    ''
  );
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_filter in
    select value from jsonb_array_elements(p_technical_filters) item(value)
  loop
    if jsonb_typeof(v_filter) <> 'object'
       or not (v_filter ? 'field' and v_filter ? 'value')
       or jsonb_typeof(v_filter -> 'field') <> 'string'
       or jsonb_typeof(v_filter -> 'value') <> 'string'
       or exists (
         select 1 from jsonb_object_keys(v_filter) key
         where key not in ('field', 'value')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_filter_field := btrim(v_filter ->> 'field');
    v_filter_value := btrim(v_filter ->> 'value');
    if v_filter_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or octet_length(v_filter_value) not between 1 and 120
       or v_filter_field = any(v_filter_fields)
       or not exists (
         select 1
         from public.spec_definitions definition
         where definition.key = v_filter_field
           and (definition.tenant_id is null
             or definition.tenant_id = v_authority.tenant_id)
           and definition.is_filterable is true
           and (
             jsonb_array_length(definition.allowed_values) = 0
             or exists (
               select 1
               from jsonb_array_elements(definition.allowed_values) allowed(value)
               where jsonb_typeof(allowed.value) = 'string'
                 and public.assistant_normalize_query_internal_v1(
                   allowed.value #>> '{}'
                 ) = public.assistant_normalize_query_internal_v1(v_filter_value)
             )
           )
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_filter_fields := array_append(v_filter_fields, v_filter_field);
  end loop;

  with requested_filters as materialized (
    select
      filter.ordinality,
      filter.value ->> 'field' field_key,
      coalesce((
        select allowed.value #>> '{}'
        from public.spec_definitions definition
        cross join jsonb_array_elements(definition.allowed_values) allowed(value)
        where definition.key = filter.value ->> 'field'
          and (definition.tenant_id is null
            or definition.tenant_id = v_authority.tenant_id)
          and definition.is_filterable is true
          and jsonb_typeof(allowed.value) = 'string'
          and public.assistant_normalize_query_internal_v1(
            allowed.value #>> '{}'
          ) = public.assistant_normalize_query_internal_v1(
            filter.value ->> 'value'
          )
        order by (definition.tenant_id is not null) desc
        limit 1
      ), filter.value ->> 'value') canonical_value
    from jsonb_array_elements(p_technical_filters)
      with ordinality filter(value, ordinality)
  ), category_scope as materialized (
    select distinct category.id category_id, mapping.technical_family
    from public.product_categories category
    left join public.category_tech_mappings mapping
      on mapping.tenant_id = category.tenant_id
     and mapping.category_id = category.id
     and mapping.status = 'active'
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ), product_surfaces as materialized (
    select
      product.id entity_id,
      product.category_id,
      mapping.technical_family,
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
      end available_stock,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.sku, product.barcode, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category, product.description
      )) search_surface,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      )) identity_surface,
      unaccent(lower(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      ))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
      public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
    from public.products_with_sets product
    left join public.category_tech_mappings mapping
      on mapping.tenant_id = product.tenant_id
     and mapping.category_id = product.category_id
     and mapping.status = 'active'
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
  ), scoped as materialized (
    select
      product.*,
      filter_state.technical_match
    from product_surfaces product
    cross join lateral (
      select
        coalesce(bool_and(source.value in ('product_spec', 'identity_fallback')), true)
          filters_match,
        case
          when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback'
        end technical_match
      from requested_filters filter
      cross join lateral (
        select public.assistant_inventory_technical_filter_source_internal_v1(
          v_authority.tenant_id,
          product.entity_id,
          filter.field_key,
          filter.canonical_value,
          product.identity_surface,
          product.identity_raw
        ) value
      ) source
    ) filter_state
    where filter_state.filters_match
      and (
        v_category is null
        or exists (
          select 1
          from category_scope scope
          where (
            scope.technical_family is not null
            and scope.technical_family = product.technical_family
          ) or (
            scope.technical_family is null
            and scope.category_id = product.category_id
          )
        )
      )
      and not exists (
        select 1
        from regexp_split_to_table(v_query, ' +') token
        where case
          when token ~ '[0-9]' then not (
            position(' ' || token || ' ' in
              ' ' || product.identity_surface || ' ') > 0
            or (
              token ~ '^[0-9]+$'
              and product.identity_raw ~ (
                '(^|[^0-9])' || token || '([^0-9]|$)'
              )
            )
            or product.sku_exact = token
            or product.barcode_exact = token
          )
          else position(token in product.search_surface) = 0
        end
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
      tracks_inventory, technical_match,
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
      'location', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(warehouse_location, ''), 120), ''),
      'technicalMatch', technical_match
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

revoke all on function public.assistant_search_inventory_v4(text, text, text, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_search_inventory_v4(text, text, text, jsonb)
to authenticated;

comment on function public.assistant_search_inventory_v4(text, text, text, jsonb) is
  'Tenant-bound inventory search resolving a catalog category through the canonical technical-family mapping before applying canonical specs, identity fallback for missing fields, and availability.';

commit;
