-- `inspect_inventory_schema` volvía a fallar en cada llamada real.
--
-- Al mover la cobertura al registro unificado de fichas (20260821…), la
-- subconsulta que arma `allowedValues` quedó referenciando `definition.id`
-- mientras el GROUP BY sólo agrupaba por `definition.key`. Postgres lo rechaza
-- con «subquery uses ungrouped column "definition.id" from outer query», así
-- que la función abortaba y el ejecutor lo reportaba como
-- `tool_source_unavailable`: 28 fallidas contra 5 exitosas el 2026-08-21.
--
-- El costo no fue sólo esa herramienta: es la que resuelve la categoría antes
-- de buscar, así que el modelo se quedaba buscando a ciegas y gastando rondas.
--
-- Un error de agrupamiento no aparece al crear la función: aparece al primer
-- dato que llega a esa rama. Por eso el read-back de esta migración EJECUTA la
-- consulta agrupada contra los datos reales del taller.

CREATE OR REPLACE FUNCTION public.assistant_inspect_inventory_schema_v3(p_query text, p_category text)
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
  v_items jsonb;
  v_total integer;
  v_active_count integer;
  v_stock_count integer;
  v_minimum_stock_count integer;
  v_price_count integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

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
      scope.id entity_id,
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
      -- La fila de campo pertenece a la misma categoría que la fila de
      -- categoría: agrupar por `scope.id` además del nombre evita fundir dos
      -- ramas homónimas del árbol en una sola identidad.
      scope.id entity_id,
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
        coalesce((
          select jsonb_agg(sv.label order by sv.sort_order)::text
          from public.spec_definition_values sv
          where sv.spec_definition_id = definition.id and sv.is_active
        ), definition.allowed_values::text), 480
      ), '[]') allowed_values,
      count(distinct product.id)::integer product_count,
      count(distinct value.subject_id)::integer populated_count,
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
    -- La cobertura sale del registro unificado. Antes contaba filas de
    -- `product_spec_values`; ahora cuenta hechos, que es lo mismo hoy y lo
    -- correcto cuando la tabla vieja se retire.
    left join public.spec_facts value
      on value.tenant_id = v_authority.tenant_id
     and value.subject_type = 'product'
     and value.subject_id = product.id
     and value.spec_definition_id = definition.id
     and value.subject_scope is null
    -- `definition.id` va en el GROUP BY porque la subconsulta de
    -- `allowed_values` lo referencia. Sin él Postgres aborta con «subquery
    -- uses ungrouped column», y la función falla ENTERA: 28 llamadas fallidas
    -- contra 5 exitosas el 2026-08-21, y el asistente perdiendo la herramienta
    -- que resuelve categorías antes de buscar. Agruparlo no cambia la
    -- granularidad: es la clave primaria de la misma fila que ya aporta
    -- `definition.key`.
    group by scope.id, scope.name, scope.full_path, mapping.technical_family,
      definition.id, definition.key, definition.label, definition.data_type,
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
      'entityId', entity_id,
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

  -- Campos operativos: los mismos de `_v2`, sin identidad de categoría porque
  -- «Inventario» no es una categoría del catálogo.
  select count(*)::integer,
    count(*) filter (where coalesce(product.track_stock, false))::integer,
    count(*) filter (
      where coalesce(product.track_stock, false)
        and coalesce(product.min_stock_level, 0) > 0
    )::integer,
    count(*) filter (where coalesce(product.price, 0) > 0)::integer
  into v_active_count, v_stock_count, v_minimum_stock_count, v_price_count
  from public.products product
  where product.tenant_id = v_authority.tenant_id
    and product.is_active is true;

  v_items := v_items || jsonb_build_array(
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'stock',
      'label', 'Stock disponible', 'dataType', 'number', 'unit', 'unidades',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_stock_count
    ),
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'minimum_stock',
      'label', 'Stock mínimo', 'dataType', 'number', 'unit', 'unidades',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_minimum_stock_count
    ),
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'price',
      'label', 'Precio de venta', 'dataType', 'number', 'unit', 'CLP',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_price_count
    )
  );

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 40
  );
end;
$function$
;
