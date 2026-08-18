-- Fase A del contrato de identidad tipada: la categoría sobrevive a la captura.
--
-- **El problema que cierra.** Una frase casual llega hoy al Asistente de
-- compras, el modelo inspecciona el esquema, resuelve una categoría canónica y
-- unos predicados técnicos… y esa categoría se pierde. `prepare_supply_request`
-- no la acepta, y `create_supply_need_batch_v1` no la escribe, aunque
-- `supply_need_interpretation_revisions.category_id` **ya existe** desde el
-- kernel (20260816150000) y está vacío en todas las filas. Los predicados sí
-- sobreviven, en `constraints`. La categoría no.
--
-- **Qué agrega esta migración, y nada más.** El inspector publica la identidad
-- de la categoría que ya resolvía; el borrador la acepta y la valida; el
-- comando durable la persiste. **No** toca ranking, ni `p_query`, ni el
-- conjunto candidato interno: eso es la fase siguiente y no está aquí.
--
-- **Autoridad.** `catalogItemRef` exacta sigue mandando sobre el producto: si
-- la línea trae producto, su categoría **se deriva del servidor** desde la
-- ficha y cualquier categoría enviada que la contradiga es un error, no una
-- preferencia. La categoría del modelo sólo gobierna la línea sin producto.
--
-- **El UUID nunca llega al modelo.** El inspector expone `entityId`, el
-- runtime lo convierte en una referencia opaca de un turno, y el proyector se
-- lo quita a la salida visible. Es el mismo mecanismo que ya protege
-- `catalogItemRef`.
--
-- **`technical_family` se deriva, no se persiste.** Su dueño es
-- `category_tech_mappings`; guardar una copia crearía una segunda verdad que
-- envejece.
--
-- Forward-only. `*_v1` quedan intactas y siguen sirviendo a cualquier llamador
-- que no haya migrado.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. El inspector publica la identidad de la categoría que ya resolvía.
--
-- Cuerpo de `assistant_inspect_inventory_schema_v1` más `entityId`, y luego
-- los campos operativos de `_v2` con `entityId` nulo —«Inventario» no es una
-- categoría del catálogo y no puede fingir serlo—.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.assistant_inspect_inventory_schema_v3(
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
    group by scope.id, scope.name, scope.full_path, mapping.technical_family,
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
$$;

revoke all on function public.assistant_inspect_inventory_schema_v3(text, text)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_inspect_inventory_schema_v3(text, text)
to authenticated;

comment on function public.assistant_inspect_inventory_schema_v3(text, text) is
  'Tenant-bound discovery of catalog categories, typed filterable specs and coverage. Publishes the resolved category identity as entityId so the gateway can mint a turn-scoped opaque categoryRef; operational rows carry no category identity.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Resolución server-side de una categoría del borrador.
--
-- Devuelve identidad, ruta, familia derivada y la plantilla activa. Lanza si
-- la categoría no es de este tenant o no está activa: el modelo no puede
-- alcanzar el árbol de otro taller ni una rama retirada.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_request_category_scope_internal_v1(
  p_tenant_id uuid,
  p_category_id uuid
)
returns table (
  category_id uuid,
  category_path text,
  technical_family text,
  template_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  return query
  select category.id, category.full_path, mapping.technical_family, template.id
  from public.product_categories category
  left join public.category_tech_mappings mapping
    on mapping.tenant_id = p_tenant_id
   and mapping.category_id = category.id
   and mapping.status = 'active'
  left join lateral (
    select spec_template.id
    from public.spec_templates spec_template
    where spec_template.is_active is true
      and (spec_template.tenant_id is null
        or spec_template.tenant_id = p_tenant_id)
      and (spec_template.id = mapping.template_id
        or (mapping.template_id is null
          and spec_template.technical_family = mapping.technical_family))
    order by (spec_template.id = mapping.template_id) desc,
      (spec_template.tenant_id is not null) desc
    limit 1
  ) template on true
  where category.tenant_id = p_tenant_id
    and category.id = p_category_id
    and category.is_active is true;

  if not found then
    raise exception 'Supply request category is unavailable'
      using errcode = '23514';
  end if;
end;
$$;

revoke all on function public.supply_request_category_scope_internal_v1(
  uuid, uuid
) from public, anon, authenticated, service_role;

comment on function public.supply_request_category_scope_internal_v1(uuid, uuid) is
  'Resolves a supply-request category inside one tenant: identity, path, derived technical family and active spec template. The family is derived on every read and never stored.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Normalizador v2: acepta `categoryId` y decide quién manda.
--
-- Reglas, en el orden en que se aplican:
--   · producto exacto ⇒ su categoría la pone el servidor desde la ficha, y una
--     `categoryId` que la contradiga es error (`23514`), no una preferencia;
--   · línea sin producto ⇒ la categoría del modelo gobierna, si existe;
--   · **una línea sin producto que traiga predicados exige fundamento**: una
--     categoría resuelta, una plantilla activa para ella, y que cada `field`
--     pertenezca a esa plantilla. Sin categoría, sin mapeo activo o sin
--     plantilla resoluble, la línea sólo se admite con `technicalPredicates`
--     vacíos.
--
-- **No hay repliegue a `is_filterable` global.** Esa regla dejaba pasar
-- cualquier definición filtrable del catálogo, incluida la de otra familia:
-- `tire_width` acotando una cadena. La necesidad y su categoría sobreviven sin
-- plantilla —el taller que aún no mapeó sus categorías sigue pudiendo pedir—,
-- pero **ningún criterio técnico sin fundamento** entra al sistema, porque
-- después gobierna un ranking y nadie recordaría de dónde salió.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.normalize_supply_request_items_internal_v2(
  p_tenant_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_item jsonb;
  v_predicate jsonb;
  v_product_id uuid;
  v_requested_category_id uuid;
  v_category record;
  v_product_category_id uuid;
  v_field text;
  v_normalized jsonb;
  v_line jsonb;
  v_result jsonb := '[]'::jsonb;
  v_items_v1 jsonb := '[]'::jsonb;
  v_index integer := 0;
begin
  if p_tenant_id is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 8 then
    raise exception 'Invalid supply request items' using errcode = '22023';
  end if;

  -- El contrato de v1 —claves exactas, tipos, predicados contra
  -- `spec_definitions`, coherencia producto/predicado— se reutiliza entero en
  -- vez de reescribirse: `categoryId` se separa antes y se valida aparte.
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;
    if v_item ? 'categoryId'
       and jsonb_typeof(v_item -> 'categoryId') not in ('string', 'null') then
      raise exception 'Invalid supply request category' using errcode = '22023';
    end if;
    v_items_v1 := v_items_v1 || jsonb_build_array(v_item - 'categoryId');
  end loop;

  v_normalized := public.normalize_supply_request_items_internal_v1(
    p_tenant_id, v_items_v1
  );

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_index := v_index + 1;
    v_line := v_normalized -> (v_index - 1);
    v_product_id := nullif(v_line ->> 'productId', '')::uuid;
    v_requested_category_id := null;
    if jsonb_typeof(v_item -> 'categoryId') = 'string' then
      if (v_item ->> 'categoryId') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'Invalid supply request category' using errcode = '22023';
      end if;
      v_requested_category_id := (v_item ->> 'categoryId')::uuid;
    end if;

    if v_product_id is not null then
      -- Autoridad del producto exacto: la categoría se deriva de la ficha.
      select product.category_id into v_product_category_id
      from public.products product
      where product.tenant_id = p_tenant_id and product.id = v_product_id;
      if v_requested_category_id is not null
         and v_requested_category_id is distinct from v_product_category_id then
        raise exception 'Catalog product does not belong to the requested category'
          using errcode = '23514';
      end if;
      v_requested_category_id := v_product_category_id;
    end if;

    if v_requested_category_id is null then
      -- Sin categoría no hay plantilla, y sin plantilla no hay criterio con
      -- fundamento: la línea sobrevive, sus predicados no.
      if v_product_id is null
         and jsonb_array_length(v_line -> 'technicalPredicates') > 0 then
        raise exception 'Technical predicates require a resolved category'
          using errcode = '23514';
      end if;
      v_result := v_result || jsonb_build_array(v_line || jsonb_build_object(
        'categoryId', null, 'categoryPath', null, 'technicalFamily', null
      ));
      continue;
    end if;

    select scope.category_id, scope.category_path, scope.technical_family,
      scope.template_id
    into v_category
    from public.supply_request_category_scope_internal_v1(
      p_tenant_id, v_requested_category_id
    ) scope;

    -- La plantilla gobierna los predicados sólo cuando la línea no tiene
    -- producto exacto: con producto, v1 ya comprobó que la ficha satisface cada
    -- predicado, que es una prueba más fuerte que la pertenencia al template.
    if v_product_id is null
       and jsonb_array_length(v_line -> 'technicalPredicates') > 0 then
      if v_category.template_id is null then
        raise exception 'Technical predicates require an active category template'
          using errcode = '23514';
      end if;
      for v_predicate in
        select value from jsonb_array_elements(v_line -> 'technicalPredicates')
      loop
        v_field := v_predicate ->> 'field';
        if not exists (
          select 1
          from public.spec_template_fields template_field
          join public.spec_definitions definition
            on definition.id = template_field.spec_definition_id
           and (definition.tenant_id is null
             or definition.tenant_id = p_tenant_id)
          where template_field.template_id = v_category.template_id
            and (template_field.tenant_id is null
              or template_field.tenant_id = p_tenant_id)
            and definition.key = v_field
            and definition.is_filterable is true
        ) then
          raise exception 'Technical predicate does not belong to the category template'
            using errcode = '23514';
        end if;
      end loop;
    end if;

    v_result := v_result || jsonb_build_array(v_line || jsonb_build_object(
      'categoryId', v_category.category_id,
      'categoryPath', v_category.category_path,
      'technicalFamily', v_category.technical_family
    ));
  end loop;

  return v_result;
end;
$$;

revoke all on function public.normalize_supply_request_items_internal_v2(
  uuid, jsonb
) from public, anon, authenticated, service_role;

comment on function public.normalize_supply_request_items_internal_v2(uuid, jsonb) is
  'Supply-request normalization with category provenance. An exact catalog product owns its category; a line without a product may carry a model-resolved category whose active template bounds its technical predicates.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. `prepare_supply_request` v2.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.assistant_prepare_supply_request_v2(
  p_items jsonb,
  p_profile text
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
  v_inventory_authority record;
  v_normalized jsonb;
  v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  select authority.tenant_id, authority.actor_user_id
  into strict v_inventory_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if v_inventory_authority.tenant_id <> v_authority.tenant_id
     or v_inventory_authority.actor_user_id <> v_authority.actor_user_id then
    raise exception 'Assistant authority changed during supply interpretation'
      using errcode = '42501';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local') then
    raise exception 'Invalid supply request profile' using errcode = '22023';
  end if;

  v_normalized := public.normalize_supply_request_items_internal_v2(
    v_authority.tenant_id,
    p_items
  );

  select jsonb_agg(
    (item.value - 'productId') || jsonb_build_object(
      'entityId', item.value -> 'productId',
      'profile', p_profile
    )
    order by item.ordinality
  ) into v_items
  from jsonb_array_elements(v_normalized)
    with ordinality item(value, ordinality);

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    coalesce(v_items, '[]'::jsonb),
    false
  );
end;
$$;

revoke all on function public.assistant_prepare_supply_request_v2(
  jsonb, text
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_prepare_supply_request_v2(
  jsonb, text
) to authenticated;

comment on function public.assistant_prepare_supply_request_v2(jsonb, text) is
  'Read-only server validation for a structured supply-request draft, with category provenance. Category and product identities are resolved from opaque references by the gateway runtime; categoryId is stripped from the model-visible projection.';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. El comando durable persiste la categoría en la ranura que ya existía.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.create_supply_need_batch_v2(
  p_original_request text,
  p_items jsonb,
  p_profile text,
  p_assistant_thread_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_original_request text := btrim(coalesce(p_original_request, ''));
  v_request jsonb;
  v_response jsonb;
  v_normalized jsonb;
  v_item jsonb;
  v_need public.supply_needs%rowtype;
  v_receipt public.supply_need_batch_receipts%rowtype;
  v_constraints jsonb;
  v_clarifications jsonb;
  v_needs jsonb := '[]'::jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_line_operation_key text;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if v_original_request = '' or octet_length(v_original_request) > 2000
     or v_operation_key = '' or octet_length(v_operation_key) > 160 then
    raise exception 'La petición de abastecimiento no es válida.'
      using errcode = '22023';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local') then
    raise exception 'El objetivo de abastecimiento no es válido.'
      using errcode = '22023';
  end if;
  if p_assistant_thread_id is not null and not exists (
    select 1 from public.assistant_threads thread
    where thread.tenant_id = v_tenant_id
      and thread.actor_user_id = v_actor_id
      and thread.id = p_assistant_thread_id
      and thread.state <> 'deleted'
  ) then
    raise exception 'La conversación de IA no pertenece a esta sesión.'
      using errcode = '42501';
  end if;

  v_normalized := public.normalize_supply_request_items_internal_v2(
    v_tenant_id,
    p_items
  );

  -- **Las etiquetas derivadas no entran a nada durable.** `categoryPath` sale
  -- de `product_categories.full_path` y `technicalFamily` de
  -- `category_tech_mappings`: las dos cambian cuando alguien reorganiza el
  -- árbol o remapea una familia, sin que la petición del operador haya
  -- cambiado en nada. Guardarlas rompería el replay —la misma clave de
  -- operación dejaría de coincidir consigo misma tras un rename— y dejaría en
  -- el ledger una copia que envejece al lado de su fuente. La identidad
  -- estable, `categoryId`, es la que se conserva; la glosa se deriva cuando se
  -- necesite mostrar.
  select jsonb_agg(
    item.value - 'categoryPath' - 'technicalFamily'
    order by item.ordinality
  ) into v_normalized
  from jsonb_array_elements(v_normalized)
    with ordinality item(value, ordinality);

  v_request := jsonb_build_object(
    'original_request', v_original_request,
    'items', v_normalized,
    'profile', p_profile,
    'assistant_thread_id', p_assistant_thread_id
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':supply_need_batch:' || v_operation_key,
    0
  ));

  select receipt.* into v_receipt
  from public.supply_need_batch_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra petición.'
        using errcode = '23505';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replay', true);
  end if;

  for v_item in
    select value from jsonb_array_elements(v_normalized)
  loop
    v_constraints := coalesce(v_item -> 'technicalPredicates', '[]'::jsonb);
    v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
      'kind', 'ranking_profile',
      'value', p_profile
    ));
    if v_item ->> 'preference' is not null then
      v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
        'kind', 'commercial_preference',
        'value', v_item ->> 'preference'
      ));
    end if;
    v_clarifications := case
      when v_item ->> 'clarification' is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object(
        'question', v_item ->> 'clarification',
        'blocking', (v_item ->> 'clarificationRequired')::boolean
      ))
    end;

    insert into public.supply_needs (
      tenant_id, origin_kind, assistant_thread_id, original_description,
      product_id, quantity, unit, identity_state, supply_state, usage_state,
      version, created_by, updated_by, created_at, updated_at
    ) values (
      v_tenant_id, 'ad_hoc', p_assistant_thread_id,
      v_item ->> 'description', nullif(v_item ->> 'productId', '')::uuid,
      (v_item ->> 'quantity')::numeric, v_item ->> 'unit',
      v_item ->> 'identityState', 'open', 'not_applicable',
      1, v_actor_id, v_actor_id, clock_timestamp(), clock_timestamp()
    ) returning * into v_need;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, category_id, constraints,
      clarifications, evidence_snapshot, formula_version, created_by
    ) values (
      v_tenant_id, v_need.id, 1, 'ai', v_original_request,
      v_need.identity_state, v_need.product_id,
      -- La ranura estaba desde el kernel y nunca se llenó. La familia técnica
      -- **no** se guarda: se deriva de `category_tech_mappings` en cada
      -- lectura, para que no envejezca una copia.
      nullif(v_item ->> 'categoryId', '')::uuid,
      v_constraints, v_clarifications,
      -- Sin `category_path` ni `technical_family`: son derivadas y su dueño
      -- —`product_categories` y `category_tech_mappings`— responde por ellas
      -- en cada lectura. `category_id` de arriba es la identidad que las
      -- reconstruye.
      jsonb_strip_nulls(jsonb_build_object(
        'line_ref', v_item ->> 'lineRef',
        'product_name', v_item ->> 'productName',
        'product_sku', v_item ->> 'productSku',
        'assistant_thread_id', p_assistant_thread_id
      )),
      'ai-supply-request-v2', v_actor_id
    );

    v_line_operation_key := v_operation_key || ':' || (v_item ->> 'lineRef');
    v_response := jsonb_build_object(
      'need_id', v_need.id,
      'changed', true,
      'version', v_need.version,
      'need', to_jsonb(v_need),
      'line_ref', v_item ->> 'lineRef',
      'batch_id', v_batch_id
    );
    insert into public.supply_need_events (
      tenant_id, supply_need_id, action, changed, actor_id, operation_key,
      request_snapshot, response_snapshot, occurred_at
    ) values (
      v_tenant_id, v_need.id, 'created', true, v_actor_id,
      v_line_operation_key,
      jsonb_build_object(
        'origin_kind', 'ad_hoc',
        'description', v_item ->> 'description',
        'product_id', v_item -> 'productId',
        -- Única adición al evento: de dónde salió la categoría de la línea.
        'category_id', v_item -> 'categoryId',
        'quantity', v_item -> 'quantity',
        'unit', v_item ->> 'unit',
        'assistant_thread_id', p_assistant_thread_id,
        'batch_id', v_batch_id,
        'line_ref', v_item ->> 'lineRef'
      ),
      v_response,
      clock_timestamp()
    );
    v_needs := v_needs || jsonb_build_array(
      to_jsonb(v_need) || jsonb_build_object('line_ref', v_item ->> 'lineRef')
    );
  end loop;

  v_response := jsonb_build_object(
    'batch_id', v_batch_id,
    'changed', true,
    'needs', v_needs,
    'need_count', jsonb_array_length(v_needs)
  );
  insert into public.supply_need_batch_receipts (
    id, tenant_id, actor_id, assistant_thread_id, operation_key,
    request_snapshot, response_snapshot, created_at
  ) values (
    v_batch_id, v_tenant_id, v_actor_id, p_assistant_thread_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  );

  return v_response || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.create_supply_need_batch_v2(
  text, jsonb, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_supply_need_batch_v2(
  text, jsonb, text, uuid, text
) to authenticated;

comment on function public.create_supply_need_batch_v2(
  text, jsonb, text, uuid, text
) is
  'Atomic, replay-safe creation of a reviewed supply-request batch with category provenance. Writes supply_need_interpretation_revisions.category_id, a slot that existed since the kernel and was never populated; technical family stays derived.';

commit;
