-- El buscador deja de exigir que la frase del operador coincida con el nombre
-- del producto. Cuando el modelo no manda predicados, el servidor los deduce
-- con `assistant_infer_technical_predicates_internal_v1` y usa como texto libre
-- sólo lo que quedó sin traducir.
--
-- Medido el 2026-08-21 con `pg_stat_statements`: «dame los motores de caja BSA
-- con ancho de caja 68 y largo de eje 118» sí llegaba a este RPC, y devolvía
-- cero porque «caja» y «bsa» no están en el nombre de ningún producto.

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v7(p_query text, p_category text, p_availability text, p_technical_predicates jsonb, p_operational_predicates jsonb, p_sort_field text, p_sort_direction text, p_limit integer, p_selection_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_predicate jsonb;
  v_translated_values jsonb;
  v_untranslated integer;
  v_applied_predicates jsonb := '[]'::jsonb;
  v_dropped_predicates integer := 0;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_operational_predicate jsonb;
  v_operational_field text;
  v_operational_operator text;
  v_operational_values jsonb;
  v_operational_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
  v_inferred jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability is null
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8
     or jsonb_typeof(p_operational_predicates) <> 'array'
     or jsonb_array_length(p_operational_predicates) > 6
     or p_sort_field is null
     or p_sort_field not in ('relevance','name','stock','minimum_stock','price')
     or p_sort_direction is null
     or p_sort_direction not in ('asc','desc')
     or (p_sort_field = 'relevance' and p_sort_direction <> 'desc')
     or p_limit not between 1 and 10
     or p_selection_mode is null
     or p_selection_mode not in ('all_matches','top_n') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
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

  for v_predicate in
    select value
    from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (
         v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values'
       )
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (
        definition.tenant_id is null
        or definition.tenant_id = v_authority.tenant_id
      )
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in','contains'
       )
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (
         v_operator not in ('between','in')
         and jsonb_array_length(v_values) <> 1
       )
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number'
         )
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean'
         )
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1
           from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
         )
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120
         )
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);

    -- Interpretar antes de actuar. El operador habla como habla: «caja
    -- inglesa», «cuadrado», «hollowtech». El vocabulario guarda la entrada
    -- completa. Traducir eso es trabajo del buscador, no del operador: se
    -- resuelve contra `allowed_values` y recién ahí se filtra.
    if v_definition.data_type in ('single_select', 'multi_select')
       and v_operator in ('eq', 'neq', 'in')
       and jsonb_array_length(v_definition.allowed_values) > 0 then
      -- Un término que calza con varias entradas NO es un problema: es un
      -- filtro más ancho. «cuadrado» calza con JIS y con ISO, y los dos son
      -- cuadrados — se devuelven los dos. Rendirse ahí sería esconderle al
      -- operador stock que sí sirve.
      select jsonb_agg(distinct candidata), count(*) filter (where sin_traduccion)
      into v_translated_values, v_untranslated
      from (
        select
          jsonb_array_elements(
            public.assistant_resolve_select_value_internal_v1(
              v_definition.allowed_values, pedido.value #>> '{}'
            )
          ) as candidata,
          false as sin_traduccion
        from jsonb_array_elements(v_values) as pedido(value)
        union all
        select null::jsonb, true
        from jsonb_array_elements(v_values) as pedido(value)
        where jsonb_array_length(
          public.assistant_resolve_select_value_internal_v1(
            v_definition.allowed_values, pedido.value #>> '{}'
          )
        ) = 0
      ) resolucion
      where candidata is not null or sin_traduccion;

      -- Sólo se descarta el predicado cuando NINGÚN término se pudo traducir.
      -- Pedir tres cosas y equivocarse en una devuelve las otras dos.
      if v_translated_values is null
         or jsonb_array_length(v_translated_values) = 0 then
        v_dropped_predicates := v_dropped_predicates + 1;
        continue;
      end if;

      v_values := v_translated_values;
      -- Con más de una candidata la comparación pasa a ser de pertenencia.
      if v_operator = 'eq' and jsonb_array_length(v_values) > 1 then
        v_operator := 'in';
      end if;
    end if;

    v_applied_predicates := v_applied_predicates || jsonb_build_array(
      jsonb_build_object(
        'field', v_field, 'operator', v_operator, 'values', v_values
      )
    );
  end loop;

  -- El resto de la función filtra con los predicados ya traducidos.
  p_technical_predicates := v_applied_predicates;

  -- El operador escribe una frase, no predicados. Cuando el modelo no arma
  -- ninguno, el servidor traduce esa frase contra el registro de vocabulario y
  -- los hechos reales, y filtra con lo que reconoce. Las palabras que sobran se
  -- descartan: el filtro de texto exige que *cada* palabra esté en el nombre
  -- del producto, así que dejar «dame» o «caja» dentro devolvía cero.
  -- Los productos sin ficha no se pierden: el resolvedor de predicados admite
  -- `identity_fallback`, que reconoce la medida en el propio nombre.
  if jsonb_array_length(p_technical_predicates) = 0 and v_query is not null then
    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      v_authority.tenant_id, p_query
    );
    if jsonb_array_length(v_inferred -> 'predicates') > 0 then
      p_technical_predicates := v_inferred -> 'predicates';
      v_query := nullif(btrim(v_inferred ->> 'residual'), '');
    end if;
  end if;

  for v_operational_predicate in
    select value
    from jsonb_array_elements(p_operational_predicates) item(value)
  loop
    if jsonb_typeof(v_operational_predicate) <> 'object'
       or not (
         v_operational_predicate ? 'field'
         and v_operational_predicate ? 'operator'
         and v_operational_predicate ? 'values'
       )
       or jsonb_typeof(v_operational_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_operational_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_field := btrim(v_operational_predicate ->> 'field');
    v_operational_operator := v_operational_predicate ->> 'operator';
    v_operational_values := v_operational_predicate -> 'values';
    if v_operational_field not in ('stock', 'minimum_stock', 'price')
       or v_operational_field = any(v_operational_fields)
       or v_operational_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in'
       )
       or jsonb_array_length(v_operational_values) not between 1 and 10
       or (
         v_operational_operator = 'between'
         and jsonb_array_length(v_operational_values) <> 2
       )
       or (
         v_operational_operator not in ('between','in')
         and jsonb_array_length(v_operational_values) <> 1
       )
       or exists (
         select 1
         from jsonb_array_elements(v_operational_values) requested(value)
         where jsonb_typeof(requested.value) <> 'number'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_fields := array_append(
      v_operational_fields, v_operational_field
    );
  end loop;

  with recursive selected_category as materialized (
    select category.id, category.name, category.full_path
    from public.product_categories category
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
    order by (
      public.assistant_normalize_query_internal_v1(category.full_path) = v_category
    ) desc, category.level desc
    limit 1
  ), category_scope as (
    select selected.id from selected_category selected
    union
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_authority.tenant_id
      and child.is_active is true
  ), scoped_families as materialized (
    select distinct mapping.technical_family
    from category_scope scope
    join public.category_tech_mappings mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id
     and mapping.status = 'active'
    where mapping.technical_family is not null
  ), requested_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_technical_predicates) predicate(value)
  ), requested_operational_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_operational_predicates) predicate(value)
  ), product_surfaces as materialized (
    select product.id entity_id, product.category_id,
      mapping.technical_family, product.name, product.sku, product.brand,
      product.category_name, product.category, product.price,
      product.warehouse_location, product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      public.inventory_available_quantity_v1(
        product.tenant_id, product.id
      ) available_stock,
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
     and mapping.category_id = product.category_id
     and mapping.status = 'active'
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
  ), scoped as materialized (
    select product.*, predicate_state.technical_match
    from product_surfaces product
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec','identity_fallback'
        )), true) predicates_match,
        case
          when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback'
        end technical_match
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
      and (
        v_category is null
        or product.category_id in (select id from category_scope)
        or (
          product.technical_family is not null
          and product.technical_family in (
            select technical_family from scoped_families
          )
        )
      )
      and (
        v_query is null
        or not exists (
          select 1 from regexp_split_to_table(v_query, ' +') token
          where case
            when token ~ '[0-9]' then not (
              position(
                ' ' || token || ' ' in ' ' || product.identity_surface || ' '
              ) > 0
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
      )
  ), matched as materialized (
    select scoped.*,
      case
        when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock'
      end availability
    from scoped
    where (
      p_availability = 'any'
      or (
        p_availability = 'in_stock'
        and tracks_inventory and available_stock > 0
      )
      or (
        p_availability = 'low_stock'
        and tracks_inventory and available_stock > 0
        and available_stock <= minimum_stock
      )
      or (
        p_availability = 'out_of_stock'
        and tracks_inventory and available_stock <= 0
      )
    )
      and not exists (
        select 1
        from requested_operational_predicates predicate
        cross join lateral (
          select case predicate.field_key
            when 'stock' then scoped.available_stock::numeric
            when 'minimum_stock' then scoped.minimum_stock::numeric
            when 'price' then scoped.price::numeric
            else null::numeric
          end actual_value
        ) actual
        where actual.actual_value is null
          or (
            predicate.field_key in ('stock', 'minimum_stock')
            and not scoped.tracks_inventory
          )
          or not case predicate.operator
            when 'eq' then
              actual.actual_value = (predicate.values ->> 0)::numeric
            when 'neq' then
              actual.actual_value <> (predicate.values ->> 0)::numeric
            when 'lt' then
              actual.actual_value < (predicate.values ->> 0)::numeric
            when 'lte' then
              actual.actual_value <= (predicate.values ->> 0)::numeric
            when 'gt' then
              actual.actual_value > (predicate.values ->> 0)::numeric
            when 'gte' then
              actual.actual_value >= (predicate.values ->> 0)::numeric
            when 'between' then actual.actual_value between
              least(
                (predicate.values ->> 0)::numeric,
                (predicate.values ->> 1)::numeric
              ) and greatest(
                (predicate.values ->> 0)::numeric,
                (predicate.values ->> 1)::numeric
              )
            when 'in' then exists (
              select 1
              from jsonb_array_elements_text(
                predicate.values
              ) requested(value)
              where requested.value::numeric = actual.actual_value
            )
            else false
          end
      )
  ), numbered as (
    select *,
      count(*) over()::integer matched_count,
      count(*) filter (where tracks_inventory) over()::integer tracked_count,
      coalesce(sum(available_stock) filter (
        where tracks_inventory
      ) over(), 0)::integer total_stock,
      coalesce(sum(greatest(available_stock, 0) * price) filter (
        where tracks_inventory
      ) over(), 0)::numeric inventory_retail_value,
      avg(price) over()::numeric average_price,
      min(price) over()::numeric minimum_price,
      max(price) over()::numeric maximum_price,
      row_number() over (order by
        case
          when p_sort_field = 'stock' and p_sort_direction = 'asc'
            then available_stock
        end asc nulls last,
        case
          when p_sort_field = 'stock' and p_sort_direction = 'desc'
            then available_stock
        end desc nulls last,
        case
          when p_sort_field = 'minimum_stock' and p_sort_direction = 'asc'
            then minimum_stock
        end asc nulls last,
        case
          when p_sort_field = 'minimum_stock' and p_sort_direction = 'desc'
            then minimum_stock
        end desc nulls last,
        case
          when p_sort_field = 'price' and p_sort_direction = 'asc'
            then price
        end asc nulls last,
        case
          when p_sort_field = 'price' and p_sort_direction = 'desc'
            then price
        end desc nulls last,
        case
          when p_sort_field = 'name' and p_sort_direction = 'asc'
            then public.assistant_normalize_query_internal_v1(name)
        end asc nulls last,
        case
          when p_sort_field = 'name' and p_sort_direction = 'desc'
            then public.assistant_normalize_query_internal_v1(name)
        end desc nulls last,
        case
          when p_sort_field = 'relevance' then (
            v_query is not null
            and public.assistant_normalize_query_internal_v1(sku) = v_query
          )
        end desc nulls last,
        case
          when p_sort_field = 'relevance' then (
            v_query is not null
            and position(
              v_query in public.assistant_normalize_query_internal_v1(name)
            ) > 0
          )
        end desc nulls last,
        case when p_sort_field = 'relevance' then updated_at end desc nulls last,
        public.assistant_normalize_query_internal_v1(name), entity_id
      ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(sku, ''), 80
      ), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(brand, ''), 100
      ), ''),
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
      'technicalMatch', technical_match,
      'matchedCount', matched_count,
      'trackedCount', tracked_count,
      'totalStock', total_stock,
      'inventoryRetailValue', inventory_retail_value,
      'averagePrice', average_price,
      'minimumPrice', minimum_price,
      'maximumPrice', maximum_price
    ) order by ordinal) filter (
      where ordinal <= p_limit
    ), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    p_selection_mode = 'all_matches' and v_total > p_limit
  );
end;
$function$
;
