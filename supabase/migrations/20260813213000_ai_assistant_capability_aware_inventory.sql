-- Capability-aware inventory planning. The model first discovers the tenant's
-- real category/spec vocabulary and coverage, then submits typed predicates.
-- Range comparisons never fall back to ambiguous product-name measurements.
begin;

create or replace function public.assistant_inventory_technical_predicate_source_internal_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_field_key text,
  p_operator text,
  p_values jsonb,
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
  v_definition record;
  v_value record;
  v_match boolean := false;
  v_candidate text;
  v_candidate_normalized text;
  v_number numeric;
  v_first numeric;
  v_second numeric;
  v_boolean boolean;
begin
  select definition.data_type, definition.allowed_values
  into v_definition
  from public.spec_definitions definition
  where definition.key = p_field_key
    and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    and definition.is_filterable is true
  order by (definition.tenant_id is not null) desc
  limit 1;
  if not found then return 'unresolved'; end if;

  select value.value_text, value.value_number, value.value_boolean,
    value.value_option, value.value_json, value.display_value
  into v_value
  from public.product_spec_values value
  join public.spec_definitions definition
    on definition.id = value.spec_definition_id
   and definition.key = p_field_key
   and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
  where value.tenant_id = p_tenant_id
    and value.product_id = p_product_id
  order by (definition.tenant_id is not null) desc
  limit 1;

  if found then
    if v_definition.data_type = 'number' then
      if v_value.value_number is null then return 'conflict'; end if;
      v_number := v_value.value_number;
      v_first := (p_values ->> 0)::numeric;
      if p_operator = 'eq' then v_match := v_number = v_first;
      elsif p_operator = 'neq' then v_match := v_number <> v_first;
      elsif p_operator = 'lt' then v_match := v_number < v_first;
      elsif p_operator = 'lte' then v_match := v_number <= v_first;
      elsif p_operator = 'gt' then v_match := v_number > v_first;
      elsif p_operator = 'gte' then v_match := v_number >= v_first;
      elsif p_operator = 'between' then
        v_second := (p_values ->> 1)::numeric;
        v_match := v_number between least(v_first, v_second)
          and greatest(v_first, v_second);
      elsif p_operator = 'in' then
        v_match := exists (
          select 1 from jsonb_array_elements(p_values) requested(value)
          where v_number = (requested.value #>> '{}')::numeric
        );
      end if;
    elsif v_definition.data_type = 'boolean' then
      if v_value.value_boolean is null then return 'conflict'; end if;
      v_boolean := (p_values ->> 0)::boolean;
      if p_operator = 'eq' then v_match := v_value.value_boolean = v_boolean;
      elsif p_operator = 'neq' then v_match := v_value.value_boolean <> v_boolean;
      end if;
    elsif v_definition.data_type in ('single_select', 'multi_select', 'text') then
      if p_operator = 'contains' then
        v_candidate_normalized := public.assistant_normalize_query_internal_v1(
          p_values ->> 0
        );
        v_match := position(v_candidate_normalized in
          public.assistant_normalize_query_internal_v1(concat_ws(' ',
            v_value.value_text, v_value.value_option, v_value.display_value,
            v_value.value_json::text
          ))) > 0;
      else
        v_match := exists (
          select 1
          from jsonb_array_elements(p_values) requested(value)
          where public.assistant_normalize_query_internal_v1(
              requested.value #>> '{}'
            ) in (
              public.assistant_normalize_query_internal_v1(v_value.value_text),
              public.assistant_normalize_query_internal_v1(v_value.value_option),
              public.assistant_normalize_query_internal_v1(v_value.display_value)
            )
            or (
              jsonb_typeof(v_value.value_json) = 'array'
              and exists (
                select 1
                from jsonb_array_elements(v_value.value_json) member(value)
                where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
                  and public.assistant_normalize_query_internal_v1(
                    member.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
              )
            )
        );
        if p_operator = 'neq' then v_match := not v_match; end if;
      end if;
    end if;
    return case when v_match then 'product_spec' else 'conflict' end;
  end if;

  -- Curated identity may fill only exact equality/membership for an empty
  -- ficha. It is never a range engine: 68x122.5 cannot prove "eje < 125".
  if p_operator in ('eq', 'in') then
    for v_candidate in
      select requested.value #>> '{}'
      from jsonb_array_elements(p_values) requested(value)
    loop
      v_candidate_normalized := public.assistant_normalize_query_internal_v1(
        v_candidate
      );
      if position(
           ' ' || v_candidate_normalized || ' '
           in ' ' || coalesce(p_identity_surface, '') || ' '
         ) > 0
         or (
           v_candidate_normalized ~ '^[0-9]+(?:[.]?[0-9]+)?$'
           and coalesce(p_identity_raw, '') ~ (
             '(^|[^0-9.])' || replace(v_candidate_normalized, '.', '[.]') ||
             '([^0-9.]|$)'
           )
         ) then
        return 'identity_fallback';
      end if;
    end loop;
  end if;
  return 'unresolved';
end;
$$;

revoke all on function
  public.assistant_inventory_technical_predicate_source_internal_v1(
    uuid, uuid, text, text, jsonb, text, text
  )
from public, anon, authenticated, service_role;

create or replace function public.assistant_inspect_inventory_schema_v1(
  p_query text,
  p_category text
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
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or octet_length(coalesce(p_category, '')) > 160 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with recursive candidate_roots as materialized (
    select category.id, category.name, category.full_path, category.level,
      row_number() over (order by
        (public.assistant_normalize_query_internal_v1(category.name) =
          coalesce(v_category, v_query)) desc,
        (public.assistant_normalize_query_internal_v1(category.full_path) =
          coalesce(v_category, v_query)) desc,
        category.level,
        length(category.full_path),
        category.full_path
      ) root_rank
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        (
          v_category is not null
          and exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (public.assistant_normalize_query_internal_v1(category.name) = v_category
            or public.assistant_normalize_query_internal_v1(
              category.full_path
            ) = v_category)
        )
        or (
          v_category is not null
          and not exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (
            position(v_category in public.assistant_normalize_query_internal_v1(
              category.full_path
            )) > 0
            or position(public.assistant_normalize_query_internal_v1(
              category.name
            ) in v_category) > 0
          )
        )
        or (
          v_category is null
          and length(public.assistant_normalize_query_internal_v1(category.name)) >= 3
          and position(public.assistant_normalize_query_internal_v1(
            category.name
          ) in v_query) > 0
        )
        or (
          v_category is null
          and exists (
            select 1 from regexp_split_to_table(v_query, ' +') token
            where length(token) >= 4
              and position(token in public.assistant_normalize_query_internal_v1(
                category.full_path
              )) > 0
          )
        )
      )
    order by root_rank
    limit 8
  ), category_scope as (
    select root.id, root.name, root.full_path, root.level, root.root_rank
    from candidate_roots root
    where root.root_rank <= 8
    union
    select child.id, child.name, child.full_path, child.level, scope.root_rank
    from public.product_categories child
    join category_scope scope on child.parent_id = scope.id
    where child.tenant_id = v_authority.tenant_id
      and child.is_active is true
  ), category_rows as materialized (
    select distinct on (scope.id)
      'category'::text kind,
      scope.name category,
      scope.full_path category_path,
      mapping.technical_family,
      null::text field_key,
      null::text field_label,
      null::text data_type,
      null::text unit,
      null::text operators,
      null::text allowed_values,
      count(distinct product.id)::integer product_count,
      0::integer populated_count,
      scope.root_rank,
      scope.level,
      0 sort_order
    from category_scope scope
    left join public.category_tech_mappings mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
    group by scope.id, scope.name, scope.full_path, mapping.technical_family,
      scope.root_rank, scope.level
    order by scope.id, (mapping.technical_family is not null) desc
  ), field_rows as materialized (
    select
      'field'::text kind,
      scope.name category,
      scope.full_path category_path,
      mapping.technical_family,
      definition.key field_key,
      definition.label field_label,
      definition.data_type,
      definition.unit,
      case definition.data_type
        when 'number' then 'eq,neq,lt,lte,gt,gte,between,in'
        when 'boolean' then 'eq,neq'
        when 'single_select' then 'eq,neq,in'
        when 'multi_select' then 'eq,neq,in'
        when 'text' then 'eq,neq,in,contains'
      end operators,
      nullif(public.assistant_truncate_utf8_internal_v1(
        definition.allowed_values::text, 480
      ), '[]') allowed_values,
      count(distinct product.id)::integer product_count,
      count(distinct value.product_id)::integer populated_count,
      scope.root_rank,
      scope.level,
      template_field.sort_order
    from category_scope scope
    join public.category_tech_mappings mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    join lateral (
      select template.id
      from public.spec_templates template
      where template.is_active is true
        and (template.tenant_id is null or template.tenant_id = v_authority.tenant_id)
        and (template.id = mapping.template_id
          or (mapping.template_id is null
            and template.technical_family = mapping.technical_family))
      order by (template.id = mapping.template_id) desc,
        (template.tenant_id is not null) desc
      limit 1
    ) template on true
    join public.spec_template_fields template_field
      on template_field.template_id = template.id
     and (template_field.tenant_id is null
       or template_field.tenant_id = v_authority.tenant_id)
    join public.spec_definitions definition
      on definition.id = template_field.spec_definition_id
     and (definition.tenant_id is null
       or definition.tenant_id = v_authority.tenant_id)
     and definition.is_filterable is true
     and definition.data_type in (
       'text', 'number', 'boolean', 'single_select', 'multi_select'
     )
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
    left join public.product_spec_values value
      on value.tenant_id = v_authority.tenant_id
     and value.product_id = product.id
     and value.spec_definition_id = definition.id
    group by scope.name, scope.full_path, mapping.technical_family,
      definition.key, definition.label, definition.data_type,
      definition.unit, definition.allowed_values, scope.root_rank,
      scope.level, template_field.sort_order
  ), bounded as materialized (
    select * from category_rows
    union all
    select * from field_rows
    order by root_rank, level, category_path, sort_order, field_key nulls first
    limit 41
  ), numbered as (
    select *, row_number() over (
      order by root_rank, level, category_path, sort_order, field_key nulls first
    ) ordinal
    from bounded
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', kind,
      'category', public.assistant_truncate_utf8_internal_v1(category, 160),
      'categoryPath', public.assistant_truncate_utf8_internal_v1(category_path, 240),
      'technicalFamily', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(technical_family, ''), 120
      ), ''),
      'field', field_key,
      'label', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(field_label, ''), 160
      ), ''),
      'dataType', data_type,
      'unit', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(unit, ''), 40
      ), ''),
      'operators', operators,
      'allowedValues', allowed_values,
      'productCount', product_count,
      'populatedCount', populated_count
    ) order by ordinal) filter (where ordinal <= 40), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 40
  );
end;
$$;

revoke all on function public.assistant_inspect_inventory_schema_v1(text, text)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_inspect_inventory_schema_v1(text, text)
to authenticated;

comment on function public.assistant_inspect_inventory_schema_v1(text, text) is
  'Tenant-bound discovery of catalog categories, typed filterable specs, supported operators and actual structured-data coverage.';

create or replace function public.assistant_search_inventory_v5(
  p_query text,
  p_category text,
  p_availability text,
  p_technical_predicates jsonb
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
  v_predicate jsonb;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(public.assistant_normalize_query_internal_v1(p_category), '');
  if v_query is null and v_category is null
     and jsonb_array_length(p_technical_predicates) = 0 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if v_category is not null and not exists (
    select 1 from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_predicate in
    select value from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values')
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (definition.tenant_id is null or definition.tenant_id = v_authority.tenant_id)
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in ('eq','neq','lt','lte','gt','gte','between','in','contains')
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (v_operator not in ('between','in') and jsonb_array_length(v_values) <> 1)
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number')
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean')
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or (jsonb_array_length(v_definition.allowed_values) > 0 and not exists (
               select 1 from jsonb_array_elements(v_definition.allowed_values) allowed(value)
               where public.assistant_normalize_query_internal_v1(
                 allowed.value #>> '{}'
               ) = public.assistant_normalize_query_internal_v1(
                 requested.value #>> '{}'
               )
             )))
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120)
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);
  end loop;

  with recursive selected_category as materialized (
    select category.id, category.name, category.full_path
    from public.product_categories category
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
    order by (public.assistant_normalize_query_internal_v1(category.full_path) = v_category) desc,
      category.level desc
    limit 1
  ), category_scope as (
    select selected.id from selected_category selected
    union
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_authority.tenant_id and child.is_active is true
  ), scoped_families as materialized (
    select distinct mapping.technical_family
    from category_scope scope
    join public.category_tech_mappings mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    where mapping.technical_family is not null
  ), requested_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_technical_predicates) predicate(value)
  ), product_surfaces as materialized (
    select product.id entity_id, product.category_id,
      mapping.technical_family, product.name, product.sku, product.brand,
      product.category_name, product.category, product.price,
      product.warehouse_location, product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      case when coalesce(product.is_set, false)
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
      unaccent(lower(concat_ws(' ', product.name, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
      public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
    from public.products_with_sets product
    left join public.category_tech_mappings mapping
      on mapping.tenant_id = product.tenant_id
     and mapping.category_id = product.category_id and mapping.status = 'active'
    where product.tenant_id = v_authority.tenant_id and product.is_active is true
  ), scoped as materialized (
    select product.*, predicate_state.technical_match
    from product_surfaces product
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec','identity_fallback'
        )), true) predicates_match,
        case when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback' end technical_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          v_authority.tenant_id, product.entity_id, predicate.field_key,
          predicate.operator, predicate.values, product.identity_surface,
          product.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (v_category is null or product.category_id in (select id from category_scope)
        or (product.technical_family is not null and product.technical_family in (
          select technical_family from scoped_families
        )))
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where case when token ~ '[0-9]' then not (
            position(' ' || token || ' ' in ' ' || product.identity_surface || ' ') > 0
            or (token ~ '^[0-9]+$' and product.identity_raw ~ (
              '(^|[^0-9])' || token || '([^0-9]|$)'))
            or product.sku_exact = token or product.barcode_exact = token
          ) else position(token in product.search_surface) = 0 end
      ))
  ), matched as materialized (
    select scoped.*,
      case when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock' end availability
    from scoped
    where p_availability = 'any'
      or (p_availability = 'in_stock' and tracks_inventory and available_stock > 0)
      or (p_availability = 'low_stock' and tracks_inventory
        and available_stock > 0 and available_stock <= minimum_stock)
      or (p_availability = 'out_of_stock' and tracks_inventory and available_stock <= 0)
    order by (v_query is not null and
        public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (v_query is not null and position(v_query in
        public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last, name
    limit 11
  ), numbered as (
    select *, row_number() over (order by
      (v_query is not null and
        public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (v_query is not null and position(v_query in
        public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(category_name, category, ''), 100
      ), ''),
      'price', price,
      'stock', available_stock,
      'minimumStock', minimum_stock,
      'availability', availability,
      'tracksInventory', tracks_inventory,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(warehouse_location, ''), 120
      ), ''),
      'technicalMatch', technical_match
    ) order by ordinal) filter (where ordinal <= 10), '[]'::jsonb), count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 10
  );
end;
$$;

revoke all on function public.assistant_search_inventory_v5(text, text, text, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_search_inventory_v5(text, text, text, jsonb)
to authenticated;

comment on function public.assistant_search_inventory_v5(text, text, text, jsonb) is
  'Tenant-bound inventory search over category descendants and typed canonical technical predicates; only exact equality can use labelled identity fallback.';

commit;
