-- La bodega se juzga sobre la categoría, no sobre el catálogo entero.
--
-- `get_supply_need_stock_resolution_v3` respondía `500 / 57014` —statement
-- timeout— con la sesión autenticada y el resto de las consultas en 200. El
-- tope no era el sospechado: el rol `authenticated` trae 8 s y la función se
-- sube a 9000 ms en su propio `proconfig`; los 4500 ms son de
-- `get_supply_need_external_candidates_v1`, otra función.
--
-- Medido contra producción el 2026-08-31, necesidad real de pastillas
-- (`b9484ed6`), tres predicados técnicos y 49 productos en la categoría:
--
--   supply_need_stock_bundle_internal_v1        9223 ms · 59 530 buffers
--   supply_need_eligible_products_internal_v1   7634 ms · 55 283 buffers  (83%)
--   una fuente de predicado, en caliente            1,3 ms
--   el detalle de UN producto, en caliente         13,5 ms
--   normalizar los 49 productos                     13 ms
--
-- Ninguna pieza suma siete segundos. El plan sí lo explica: la llamada por
-- producto acababa en el filtro del scan de `products`, de modo que
-- se evaluaba antes del join de categoría y corría sobre las **1554** filas
-- del tenant. Acotar el conjunto primero deja la misma respuesta en 289 ms.
--
-- Esto no toca el modelo de datos, no sube ningún tope y no cambia qué se
-- considera compatible: es CUÁNDO se evalúa, no QUÉ.

CREATE OR REPLACE FUNCTION public.supply_need_eligible_products_internal_v1(p_tenant_id uuid, p_need_id uuid, p_max_universe integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_context record;
  v_universe_size integer := 0;
  v_predicates jsonb;
  v_predicate_count integer;
  v_items jsonb;
  v_template_id uuid;
  v_available_fields jsonb := '[]'::jsonb;
  v_detail jsonb;
begin
  if p_max_universe is null or p_max_universe not between 1 and 5000 then
    raise exception 'Invalid eligible product bound' using errcode = '22023';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    p_tenant_id, p_need_id
  );

  -- Sólo los predicados técnicos: `ranking_profile` y `commercial_preference`
  -- viven en el mismo arreglo y no son criterios de compatibilidad.
  select coalesce(jsonb_agg(entry.value), '[]'::jsonb)
  into v_predicates
  from jsonb_array_elements(v_context.constraints) entry(value)
  where entry.value ? 'field' and entry.value ? 'operator'
    and entry.value ? 'values';
  v_predicate_count := jsonb_array_length(v_predicates);

  -- Carril exacto: el universo es un solo producto y no se ensancha.
  if v_context.product_id is not null
     and v_context.identity_state = 'confirmed' then
    v_detail := public.supply_need_match_detail_internal_v1(
      p_tenant_id, v_context.product_id, v_predicates
    );
    return jsonb_build_object(
      'status', 'ok',
      'lane', 'exact',
      'categoryId', v_context.category_id,
      'universeSize', 1,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'items', jsonb_build_array(jsonb_build_object(
        'productId', v_context.product_id,
        'matchState', public.supply_need_match_state_internal_v1(
          v_detail, v_predicate_count
        ),
        'matchDetail', v_detail
      ))
    );
  end if;

  if v_context.category_id is null then
    return jsonb_build_object(
      'status', 'identity_unresolved',
      'lane', 'family',
      'categoryId', null,
      'universeSize', 0,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'items', '[]'::jsonb
    );
  end if;

  -- El universo se cuenta ANTES de evaluar: el techo es sobre lo que habría
  -- que mirar, no sobre lo que sobrevive.
  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = p_tenant_id
      and category.id = v_context.category_id
      and category.is_active is true
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = p_tenant_id and child.is_active is true
  )
  select count(*)::integer into v_universe_size
  from public.products product
  where product.tenant_id = p_tenant_id
    and product.is_active is true
    and not coalesce(product.is_service, false)
    and coalesce(product.product_type, 'product') <> 'service'
    and product.category_id in (select id from category_scope);

  if v_universe_size > p_max_universe then
    -- La plantilla activa la resuelve su dueño de la Fase A, no una variante
    -- local. Resolverla acá con `coalesce(mapping.template_id, …)` publicaba
    -- los campos de una plantilla **inactiva** cuando el mapeo la nombraba
    -- explícitamente: se le ofrecía al operador refinar por criterios que el
    -- taller ya había retirado.
    select scope.template_id into v_template_id
    from public.supply_request_category_scope_internal_v1(
      p_tenant_id, v_context.category_id
    ) scope;

    if v_template_id is not null then
      select coalesce(jsonb_agg(distinct definition.key), '[]'::jsonb)
      into v_available_fields
      from public.spec_template_fields template_field
      join public.spec_definitions definition
        on definition.id = template_field.spec_definition_id
       and (definition.tenant_id is null
         or definition.tenant_id = p_tenant_id)
       and definition.is_filterable is true
      where template_field.template_id = v_template_id
        and (template_field.tenant_id is null
          or template_field.tenant_id = p_tenant_id);
    end if;

    -- Refinar es una acción concreta: se dice cuántos hay, cuál es el techo y
    -- qué campos de la plantilla sirven para acotar. «Sé más específico» no
    -- es una respuesta.
    return jsonb_build_object(
      'status', 'needs_refinement',
      'lane', 'family',
      'categoryId', v_context.category_id,
      'universeSize', v_universe_size,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'availableFields', v_available_fields,
      'items', '[]'::jsonb
    );
  end if;

  -- Se evalúa el universo entero y recién después se excluye `conflict`.
  --
  -- **El alcance se cierra ANTES de evaluar, y por eso `scoped` es
  -- `materialized`.** La llamada por producto acababa en el filtro
  -- del scan de `products`, así que el planificador la ejecutaba durante ese
  -- scan y **antes** del join que restringe a la categoría: medido el
  -- 2026-08-31 sobre la necesidad real de pastillas, `Seq Scan on products
  -- (rows=1554)` con 7154 ms para juzgar 49 productos. Se pagaba el juicio
  -- completo de las 1554 filas del tenant para descartar 1505 después.
  --
  -- No se recorta el universo ni cambia qué se considera compatible: se
  -- evalúan exactamente los mismos productos que antes sobrevivían al filtro.
  -- Lo único que cambia es cuándo. Misma medición tras el cambio: 289 ms y
  -- 2013 buffers, contra 7160 ms y 51 691.
  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = p_tenant_id
      and category.id = v_context.category_id
      and category.is_active is true
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = p_tenant_id and child.is_active is true
  ), scoped as materialized (
    select product.id as product_id
    from public.products product
    where product.tenant_id = p_tenant_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
      and product.category_id in (select id from category_scope)
  ), evaluated as materialized (
    select scoped.product_id,
      public.supply_need_match_detail_internal_v1(
        p_tenant_id, scoped.product_id, v_predicates
      ) as match_detail
    from scoped
  ), stated as (
    select evaluated.product_id, evaluated.match_detail,
      public.supply_need_match_state_internal_v1(
        evaluated.match_detail, v_predicate_count
      ) as match_state
    from evaluated
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'productId', stated.product_id,
    'matchState', stated.match_state,
    'matchDetail', stated.match_detail
  ) order by stated.product_id), '[]'::jsonb)
  into v_items
  from stated
  where stated.match_state <> 'conflict';

  return jsonb_build_object(
    'status', 'ok',
    'lane', 'family',
    'categoryId', v_context.category_id,
    'universeSize', v_universe_size,
    'safeLimit', p_max_universe,
    'predicateCount', v_predicate_count,
    'items', v_items
  );
end;
$function$;
