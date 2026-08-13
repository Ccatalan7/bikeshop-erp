-- Natural-language inventory search is retrieval, not technical truth. This
-- version binds model-planned technical filters to the canonical Spec Engine,
-- prefers product_spec_values, rejects structured conflicts, and permits an
-- identity-field fallback only when the canonical field is still unpopulated.
begin;

create or replace function public.assistant_inventory_technical_filter_source_internal_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_field_key text,
  p_requested_value text,
  p_identity_surface text,
  p_identity_raw text
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_requested text;
begin
  v_requested := public.assistant_normalize_query_internal_v1(p_requested_value);

  if exists (
    select 1
    from public.product_spec_values value
    join public.spec_definitions definition
      on definition.id = value.spec_definition_id
     and definition.key = p_field_key
     and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    where value.tenant_id = p_tenant_id
      and value.product_id = p_product_id
      and (
        public.assistant_normalize_query_internal_v1(value.value_option) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_text) = v_requested
        or public.assistant_normalize_query_internal_v1(value.display_value) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_number::text) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_boolean::text) = v_requested
        or (
          jsonb_typeof(value.value_json) = 'array'
          and exists (
            select 1
            from jsonb_array_elements(value.value_json) member(value)
            where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
              and public.assistant_normalize_query_internal_v1(
                member.value #>> '{}'
              ) = v_requested
          )
        )
      )
  ) then
    return 'product_spec';
  end if;

  -- Any populated canonical value owns the field. A conflicting value cannot
  -- be overruled by a product name, description, SKU or model-generated prose.
  if exists (
    select 1
    from public.product_spec_values value
    join public.spec_definitions definition
      on definition.id = value.spec_definition_id
     and definition.key = p_field_key
     and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    where value.tenant_id = p_tenant_id
      and value.product_id = p_product_id
  ) then
    return 'conflict';
  end if;

  -- Sparse catalogs remain searchable only from the curated identity surface.
  -- Identifier substrings and compatibility/description prose never satisfy
  -- an absent technical field.
  if position(
       ' ' || v_requested || ' '
       in ' ' || coalesce(p_identity_surface, '') || ' '
     ) > 0
     or (
       v_requested ~ '^[0-9]+$'
       and coalesce(p_identity_raw, '') ~ (
         '(^|[^0-9])' || v_requested || '([^0-9]|$)'
       )
     ) then
    return 'identity_fallback';
  end if;

  return 'unresolved';
end;
$$;

revoke all on function
  public.assistant_inventory_technical_filter_source_internal_v1(
    uuid, uuid, text, text, text, text
  )
from public, anon, authenticated, service_role;

create or replace function public.assistant_search_inventory_v3(
  p_query text,
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
     or p_availability not in (
       'any', 'in_stock', 'low_stock', 'out_of_stock'
     )
     or jsonb_typeof(p_technical_filters) <> 'array'
     or jsonb_array_length(p_technical_filters) > 6 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then
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
  ), product_surfaces as materialized (
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
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
  ), scoped as materialized (
    select product.*
    from product_surfaces product
    where not exists (
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
      and not exists (
        select 1
        from requested_filters filter
        where public.assistant_inventory_technical_filter_source_internal_v1(
          v_authority.tenant_id,
          product.entity_id,
          filter.field_key,
          filter.canonical_value,
          product.identity_surface,
          product.identity_raw
        ) not in ('product_spec', 'identity_fallback')
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

revoke all on function public.assistant_search_inventory_v3(text, text, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_search_inventory_v3(text, text, jsonb)
to authenticated;

comment on function public.assistant_search_inventory_v3(text, text, jsonb) is
  'Tenant-bound inventory search combining conjunctive identity retrieval, canonical Spec Engine filters with conflict authority, and availability before the bounded result set.';

commit;
