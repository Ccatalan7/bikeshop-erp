-- Fase B1: resolver una necesidad por familia hasta el stock, y converger.
--
-- **El bloqueo que desatasca.** `reject_supply_need_internal_stock_v1` exige
-- `product_id is not null and identity_state = 'confirmed'`. Una necesidad del
-- carril familia es `unresolved` por definición, así que no podía registrar el
-- rechazo de stock interno… que es justo la puerta que habilita mirar
-- proveedores. La necesidad quedaba encerrada: ni stock ni compra.
--
-- **Qué entra aquí, y nada más.** Contexto de interpretación, elegibilidad
-- técnica, resolución de stock, rechazo de familia y convergencia a producto
-- exacto. **No** hay scoring externo, ni preferencia comercial tipada, ni UI.
-- `rank_purchase_candidates_v1`, `p_query` y `build_purchase_scenarios_v1`
-- quedan intactos.
--
-- **El orden en que se resuelve importa.** La elegibilidad técnica se decide
-- sobre los productos activos de la categoría y sus descendientes **antes** de
-- cualquier corte. Cortar primero y filtrar después dejaría que veinte
-- conflictos escondieran el producto válido que venía detrás.
--
-- **Nada de esto asigna stock ni crea plan.** Confirmar un producto es fijar
-- identidad, no comprometer unidades: eso sigue siendo
-- `assign_supply_need_from_stock_v1`.
--
-- Forward-only. `*_v1` existentes quedan intactas.

begin;

-- ───────────────────────────────────────────────────────────────────────────
-- 0. El ledger aprende dos hechos que antes no podía nombrar.
--
-- Ampliar un CHECK es forward-compatible: ninguna fila existente lo viola.
-- Sin esto, un rechazo de familia y una convergencia tendrían que disfrazarse
-- de `updated`, y el ledger dejaría de decir qué pasó.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.supply_need_events
  drop constraint if exists supply_need_events_action_check;
alter table public.supply_need_events
  add constraint supply_need_events_action_check check (action in (
    'created', 'updated', 'cancelled',
    'stock_assigned', 'stock_released', 'stock_reactivated',
    'internal_stock_rejected',
    -- El operador revisó el stock de la familia y lo descartó sin haber
    -- elegido todavía un producto exacto.
    'family_stock_rejected',
    -- El operador eligió una alternativa de la familia y la necesidad pasó a
    -- identidad confirmada.
    'family_choice_confirmed',
    'purchase_planned', 'received', 'covered'
  ));

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Único dueño de «qué interpretación manda».
--
-- La autoridad es la última revisión por `revision_no`, no la más reciente por
-- reloj: dos revisiones del mismo instante existirían y el orden por tiempo
-- sería arbitrario. Cualquier otra función que quiera saber la categoría o los
-- criterios de una necesidad pasa por acá; si aparece una segunda lectura, hay
-- dos verdades.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_resolution_context_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid
)
returns table (
  need_id uuid,
  need_version bigint,
  quantity numeric,
  unit text,
  product_id uuid,
  identity_state text,
  supply_state text,
  internal_stock_rejection_reason text,
  revision_no bigint,
  category_id uuid,
  constraints jsonb
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  return query
  select need.id, need.version, need.quantity, need.unit, need.product_id,
    need.identity_state, need.supply_state,
    need.internal_stock_rejection_reason,
    revision.revision_no, revision.category_id,
    coalesce(revision.constraints, '[]'::jsonb)
  from public.supply_needs need
  left join lateral (
    select latest.revision_no, latest.category_id, latest.constraints
    from public.supply_need_interpretation_revisions latest
    where latest.tenant_id = need.tenant_id
      and latest.supply_need_id = need.id
    order by latest.revision_no desc
    limit 1
  ) revision on true
  where need.tenant_id = p_tenant_id
    and need.id = p_need_id;

  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.supply_need_resolution_context_internal_v1(
  uuid, uuid
) from public, anon, authenticated, service_role;

comment on function public.supply_need_resolution_context_internal_v1(uuid, uuid) is
  'Single owner of which interpretation revision governs a supply need. Authority is the highest revision_no, never the most recent clock time.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Agregación de evidencia por producto: dos helpers, una sola regla.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_match_detail_internal_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_predicates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_identity_surface text;
  v_identity_raw text;
  v_predicate jsonb;
  v_detail jsonb := '[]'::jsonb;
begin
  if jsonb_array_length(coalesce(p_predicates, '[]'::jsonb)) = 0 then
    return '[]'::jsonb;
  end if;

  select public.assistant_normalize_query_internal_v1(concat_ws(' ',
      product.name, product.brand, product.model, product.manufacturer,
      product.category_name, product.category
    )),
    unaccent(lower(concat_ws(' ', product.name, product.brand, product.model,
      product.manufacturer, product.category_name, product.category)))
  into v_identity_surface, v_identity_raw
  from public.products product
  where product.tenant_id = p_tenant_id and product.id = p_product_id;
  if not found then return '[]'::jsonb; end if;

  for v_predicate in select value from jsonb_array_elements(p_predicates) loop
    v_detail := v_detail || jsonb_build_array(jsonb_build_object(
      'field', v_predicate ->> 'field',
      'source', public.assistant_inventory_technical_predicate_source_internal_v1(
        p_tenant_id, p_product_id,
        v_predicate ->> 'field', v_predicate ->> 'operator',
        v_predicate -> 'values', v_identity_surface, v_identity_raw
      )
    ));
  end loop;
  return v_detail;
end;
$$;

revoke all on function public.supply_need_match_detail_internal_v1(
  uuid, uuid, jsonb
) from public, anon, authenticated, service_role;

comment on function public.supply_need_match_detail_internal_v1(uuid, uuid, jsonb) is
  'Per-predicate evidence source for one product, delegating to the shared inventory predicate evaluator. It never re-implements the comparison.';

create or replace function public.supply_need_match_state_internal_v1(
  p_detail jsonb,
  p_predicate_count integer
)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  -- La regla más estricta gana. `conflict` contradice la ficha y por eso no se
  -- muestra en ninguna parte; `unverified` es «no lo sé», que no es lo mismo
  -- que «no cumple», así que se conserva rotulado.
  --
  -- Recibe el detalle ya calculado: recomputarlo por rama multiplicaría por
  -- tres las llamadas al evaluador de predicados, que es la parte cara.
  select case
    when coalesce(p_predicate_count, 0) = 0 then 'no_criteria'
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' = 'conflict'
    ) then 'conflict'
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' = 'unresolved'
    ) then 'unverified'
    when exists (
      select 1 from jsonb_array_elements(coalesce(p_detail, '[]'::jsonb)) entry(value)
      where entry.value ->> 'source' = 'identity_fallback'
    ) then 'weak'
    else 'strong'
  end
$$;

revoke all on function public.supply_need_match_state_internal_v1(jsonb, integer)
from public, anon, authenticated, service_role;

comment on function public.supply_need_match_state_internal_v1(jsonb, integer) is
  'Strictest-wins aggregation of already-evaluated predicate evidence: conflict excludes, unverified is unknown rather than incompatible, weak comes from the name and strong from the ficha.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Elegibilidad técnica, resuelta entera antes de cualquier corte.
--
-- Universo: productos activos, no servicios, de la categoría de la revisión y
-- sus descendientes **activos**. No sale de `purchase_candidate_metrics_v1`:
-- esa vista sólo conoce lo que el taller ya compró, así que un producto del
-- catálogo con stock y sin historial no existiría para ella.
--
-- Agregación por producto, de lo más estricto a lo más débil:
--   · algún predicado en `conflict`  → excluido, no aparece;
--   · todos en `product_spec`        → `strong`  (evidencia de ficha);
--   · algún `identity_fallback`      → `weak`    (leído del nombre);
--   · algún `unresolved`             → `unverified` (por verificar);
--   · sin predicados                 → `no_criteria` (conjunto por categoría).
--
-- Si el universo **previo** a evaluar supera `p_max_universe`, se devuelve
-- `needs_refinement` con los conteos y los campos de la plantilla que sirven
-- para refinar. Nunca se trunca en silencio: un corte mudo produce respuestas
-- que parecen completas y no lo son.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.supply_need_eligible_products_internal_v1(
  p_tenant_id uuid,
  p_need_id uuid,
  p_max_universe integer default 400
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
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
  ), evaluated as (
    select product.id as product_id,
      public.supply_need_match_detail_internal_v1(
        p_tenant_id, product.id, v_predicates
      ) as match_detail
    from public.products product
    where product.tenant_id = p_tenant_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
      and product.category_id in (select id from category_scope)
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
$$;

revoke all on function public.supply_need_eligible_products_internal_v1(
  uuid, uuid, integer
) from public, anon, authenticated, service_role;

comment on function public.supply_need_eligible_products_internal_v1(
  uuid, uuid, integer
) is
  'Technical eligibility for a supply need over active catalog products of its category and active descendants. Evaluates every predicate before any cut, excludes conflicts, and reports needs_refinement instead of truncating silently.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Resolución de stock, acotada y paginada.
--
-- Bloquear el paso externo es una decisión de negocio, no una etiqueta: un
-- candidato con cobertura total y evidencia utilizable —`strong`, `weak` o
-- `no_criteria`— obliga a mirarlo antes de comparar proveedores.
-- `unverified` **no bloquea**: exigir que el operador descarte algo que el
-- sistema no pudo verificar sería cobrarle una carencia del ERP.
--
-- El agregado de familia es informativo. Dos unidades de dos variantes
-- distintas **no** demuestran que la necesidad esté cubierta: mezclarlas es una
-- decisión del taller, y este número nunca la toma.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.get_supply_need_stock_resolution_v1(
  p_need_id uuid,
  p_limit integer default 12,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_context record;
  v_eligible jsonb;
  v_items jsonb;
  v_total integer;
  v_full_count integer;
  v_partial_count integer;
  v_none_count integer;
  v_unverified_count integer;
  v_blocking boolean;
  v_family_atp integer;
  v_coverage text;
begin
  if v_tenant_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 50
     or p_offset is null or p_offset < 0 or p_offset > 5000 then
    raise exception 'Invalid stock resolution bounds' using errcode = '22023';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    v_tenant_id, p_need_id
  );

  v_eligible := public.supply_need_eligible_products_internal_v1(
    v_tenant_id, p_need_id
  );

  if v_eligible ->> 'status' <> 'ok' then
    return jsonb_build_object(
      'needId', v_context.need_id,
      'needVersion', v_context.need_version,
      'revisionNo', v_context.revision_no,
      'quantity', v_context.quantity,
      'unit', v_context.unit,
      'lane', v_eligible ->> 'lane',
      'status', v_eligible ->> 'status',
      'categoryId', v_eligible -> 'categoryId',
      'universeSize', v_eligible -> 'universeSize',
      'safeLimit', v_eligible -> 'safeLimit',
      'availableFields', coalesce(v_eligible -> 'availableFields', '[]'::jsonb),
      'coverage', 'none',
      'blocksExternal', false,
      'items', '[]'::jsonb,
      'counts', jsonb_build_object(
        'eligible', 0, 'full', 0, 'partial', 0, 'none', 0, 'unverified', 0
      )
    );
  end if;

  -- ATP una sola vez por producto: llamarla dentro de un CASE la evaluaría
  -- tres veces por fila, y es la parte cara de esta lectura.
  with evaluated as (
    select (entry.value ->> 'productId')::uuid as product_id,
      entry.value ->> 'matchState' as match_state,
      entry.value -> 'matchDetail' as match_detail,
      public.inventory_available_quantity_v1(
        v_tenant_id, (entry.value ->> 'productId')::uuid
      ) as atp
    from jsonb_array_elements(v_eligible -> 'items') entry(value)
  ), covered as (
    select evaluated.*,
      case
        when evaluated.atp >= v_context.quantity then 'full'
        when evaluated.atp > 0 then 'partial'
        else 'none'
      end as coverage
    from evaluated
  ), ranked as (
    select covered.*,
      covered.coverage = 'full'
        and covered.match_state in ('strong', 'weak', 'no_criteria')
        as blocks_external,
      row_number() over (
        order by
          case covered.coverage
            when 'full' then 0 when 'partial' then 1 else 2 end,
          case covered.match_state
            when 'strong' then 0 when 'weak' then 1
            when 'no_criteria' then 2 else 3 end,
          covered.atp desc,
          product.name,
          covered.product_id
      ) as ordinal,
      product.name, product.sku,
      product.image_url_optimized, product.image_url, product.image_urls
    from covered
    join public.products product
      on product.tenant_id = v_tenant_id
     and product.id = covered.product_id
  )
  select count(*)::integer,
    count(*) filter (where coverage = 'full')::integer,
    count(*) filter (where coverage = 'partial')::integer,
    count(*) filter (where coverage = 'none')::integer,
    count(*) filter (where match_state = 'unverified')::integer,
    coalesce(sum(atp), 0)::integer,
    coalesce(bool_or(blocks_external), false),
    coalesce(jsonb_agg(jsonb_build_object(
      'productId', product_id,
      'name', name,
      'sku', sku,
      'imageUrlOptimized', nullif(btrim(image_url_optimized), ''),
      'imageUrl', nullif(btrim(image_url), ''),
      'imageUrls', to_jsonb(coalesce(image_urls, array[]::text[])),
      'atp', atp,
      'coverage', coverage,
      'matchState', match_state,
      'matchDetail', match_detail,
      'blocksExternal', blocks_external
    ) order by ordinal) filter (
      where ordinal > p_offset and ordinal <= p_offset + p_limit
    ), '[]'::jsonb)
  into v_total, v_full_count, v_partial_count, v_none_count,
    v_unverified_count, v_family_atp, v_blocking, v_items
  from ranked;

  v_coverage := case
    when v_full_count > 0 then 'full'
    when v_partial_count > 0 then 'partial'
    else 'none'
  end;

  return jsonb_build_object(
    'needId', v_context.need_id,
    'needVersion', v_context.need_version,
    'revisionNo', v_context.revision_no,
    'quantity', v_context.quantity,
    'unit', v_context.unit,
    'lane', v_eligible ->> 'lane',
    'status', 'ok',
    'categoryId', v_eligible -> 'categoryId',
    'universeSize', v_eligible -> 'universeSize',
    'coverage', v_coverage,
    'blocksExternal', v_blocking,
    'internalStockRejectionReason', v_context.internal_stock_rejection_reason,
    'items', v_items,
    'page', jsonb_build_object(
      'limit', p_limit, 'offset', p_offset, 'hasMore', v_total > p_offset + p_limit
    ),
    'counts', jsonb_build_object(
      'eligible', v_total,
      'full', v_full_count,
      'partial', v_partial_count,
      'none', v_none_count,
      'unverified', v_unverified_count
    ),
    -- Informativo. No prueba cobertura: sumar dos variantes distintas es una
    -- decisión del taller, no una propiedad del inventario.
    'familyAggregateAtp', v_family_atp,
    'familyAggregateProvesCoverage', false
  );
end;
$$;

revoke all on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) to authenticated;

comment on function public.get_supply_need_stock_resolution_v1(
  uuid, integer, integer
) is
  'Stock-first resolution for a supply need over its eligible product set. Reports per-product ATP coverage, full counts and whether any usable full candidate blocks the external step; the family aggregate is informational and never proves interchangeable coverage.';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Rechazo de stock interno, con carril de familia.
--
-- v1 **no se toca**: sigue sirviendo al carril exacto tal cual. v2 conserva esa
-- semántica y agrega la que faltaba —descartar el stock de la familia sin
-- haber elegido producto—, que era el nudo que dejaba la necesidad encerrada.
--
-- Se ata a `expected_version` **y** a la revisión vigente: si alguien
-- reinterpretó la necesidad entremedio, la categoría pudo cambiar y el rechazo
-- se referiría a otro conjunto.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.reject_supply_need_internal_stock_v2(
  p_need_id uuid,
  p_expected_version bigint,
  p_expected_revision_no bigint,
  p_reason text,
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
  v_reason text := btrim(coalesce(p_reason, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_context record;
  v_resolution jsonb;
  v_action text;
  v_atp integer;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_expected_revision_no is null
     or v_reason = '' or octet_length(v_reason) > 500
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'El rechazo requiere necesidad, versión, revisión, motivo y clave.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'expected_revision_no', p_expected_revision_no,
    'reason', v_reason
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action not in ('internal_stock_rejected', 'family_stock_rejected')
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro rechazo.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de rechazar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state <> 'open' then
    raise exception 'La necesidad ya no está abierta.' using errcode = '55000';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    v_tenant_id, p_need_id
  );
  if v_context.revision_no is distinct from p_expected_revision_no then
    raise exception 'La interpretación cambió; vuelve a revisar el stock.'
      using errcode = '40001';
  end if;

  if v_need.product_id is not null and v_need.identity_state = 'confirmed' then
    -- Carril exacto: misma prueba que v1, para que la semántica no se bifurque.
    if v_need.unit <> 'unit' or v_need.quantity <> trunc(v_need.quantity) then
      raise exception 'No existe una alternativa interna confirmada para rechazar.'
        using errcode = '55000';
    end if;
    v_atp := public.inventory_available_quantity_v1(
      v_tenant_id, v_need.product_id
    );
    if v_atp < v_need.quantity then
      raise exception 'No hay stock interno asignable; no requiere rechazo.'
        using errcode = '23514';
    end if;
    v_action := 'internal_stock_rejected';
  else
    -- Carril familia: se exige al menos un candidato que efectivamente
    -- bloquee. Rechazar un stock que no existe sería registrar una decisión
    -- que nadie tuvo que tomar.
    v_resolution := public.get_supply_need_stock_resolution_v1(p_need_id, 1, 0);
    if (v_resolution ->> 'blocksExternal')::boolean is not true then
      raise exception 'No hay stock interno asignable; no requiere rechazo.'
        using errcode = '23514';
    end if;
    v_atp := (v_resolution -> 'counts' ->> 'full')::integer;
    v_action := 'family_stock_rejected';
  end if;

  v_changed := v_need.internal_stock_rejection_reason is distinct from v_reason;
  if v_changed then
    update public.supply_needs need
    set internal_stock_rejection_reason = v_reason,
        internal_stock_rejected_at = clock_timestamp(),
        internal_stock_rejected_by = v_actor_id,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = v_need.id
    returning * into v_need;
  end if;

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', v_changed,
    'lane', case when v_action = 'internal_stock_rejected' then 'exact'
      else 'family' end,
    'blocking_full_candidates', v_atp,
    'revision_no', v_context.revision_no,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, v_action, v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;
  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.reject_supply_need_internal_stock_v2(
  uuid, bigint, bigint, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.reject_supply_need_internal_stock_v2(
  uuid, bigint, bigint, text, text
) to authenticated;

comment on function public.reject_supply_need_internal_stock_v2(
  uuid, bigint, bigint, text, text
) is
  'Replay-safe internal-stock rejection for both lanes. Keeps v1 semantics for a confirmed exact product and adds the family lane, which v1 could never reach because it required a confirmed product; bound to both the need version and the governing interpretation revision.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Convergencia: elegir una alternativa de la familia fija la identidad.
--
-- `update_supply_need_v1` no sirve para esto y el motivo importa: escribe la
-- revisión manual con `constraints '[]'`, `clarifications '[]'` y **sin**
-- `category_id`. Como la autoridad es la última revisión, confirmar por ese
-- camino **borraría la procedencia** de la Fase A y el siguiente cálculo de
-- familia quedaría ciego sin que nada lo delatara.
--
-- Se permite elegir un candidato `unverified`: «no lo sé» no es «no cumple»,
-- y la elección la hace una persona. Lo que no se permite es `conflict`.
--
-- No asigna stock ni crea plan: fija identidad y nada más.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.confirm_supply_need_family_choice_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_expected_revision_no bigint,
  p_product_id uuid,
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
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_context record;
  v_previous public.supply_need_interpretation_revisions%rowtype;
  v_eligible jsonb;
  v_chosen jsonb;
  v_next_revision bigint;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_expected_revision_no is null or p_product_id is null
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La confirmación requiere necesidad, versión, revisión, producto y clave.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'expected_revision_no', p_expected_revision_no,
    'product_id', p_product_id
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'family_choice_confirmed'
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra confirmación.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de confirmar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state <> 'open' then
    raise exception 'La necesidad ya no está abierta.' using errcode = '55000';
  end if;
  if v_need.product_id is not null and v_need.identity_state = 'confirmed' then
    raise exception 'La necesidad ya tiene un producto confirmado.'
      using errcode = '55000';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    v_tenant_id, p_need_id
  );
  if v_context.revision_no is distinct from p_expected_revision_no then
    raise exception 'La interpretación cambió; vuelve a revisar las alternativas.'
      using errcode = '40001';
  end if;

  -- Revalidación bajo el lock: elegibilidad y categoría se comprueban ahora,
  -- no cuando el operador miró la pantalla.
  v_eligible := public.supply_need_eligible_products_internal_v1(
    v_tenant_id, p_need_id
  );
  if v_eligible ->> 'status' <> 'ok' then
    raise exception 'No hay un conjunto elegible para confirmar.'
      using errcode = '55000';
  end if;
  select entry.value into v_chosen
  from jsonb_array_elements(v_eligible -> 'items') entry(value)
  where (entry.value ->> 'productId')::uuid = p_product_id;
  if v_chosen is null then
    raise exception 'El producto no pertenece al conjunto elegible de la necesidad.'
      using errcode = '23514';
  end if;
  if v_chosen ->> 'matchState' = 'conflict' then
    raise exception 'El producto contradice un criterio de la necesidad.'
      using errcode = '23514';
  end if;

  select revision.* into v_previous
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id
    and revision.revision_no = v_context.revision_no;

  update public.supply_needs need
  set product_id = p_product_id,
      identity_state = 'confirmed',
      version = need.version + 1,
      updated_by = v_actor_id,
      updated_at = clock_timestamp()
  where need.tenant_id = v_tenant_id and need.id = v_need.id
  returning * into v_need;

  select coalesce(max(revision.revision_no), 0) + 1 into v_next_revision
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = v_need.id;

  insert into public.supply_need_interpretation_revisions (
    tenant_id, supply_need_id, revision_no, source, raw_description,
    identity_state, canonical_product_id, category_id, constraints,
    clarifications, evidence_snapshot, formula_version, created_by
  ) values (
    v_tenant_id, v_need.id, v_next_revision, 'manual',
    coalesce(v_previous.raw_description, v_need.original_description),
    'confirmed', p_product_id,
    -- La procedencia se conserva entera: sin esto, confirmar apagaría la
    -- categoría y los criterios que produjeron la alternativa.
    v_context.category_id,
    coalesce(v_previous.constraints, '[]'::jsonb),
    coalesce(v_previous.clarifications, '[]'::jsonb),
    -- Sólo evidencia estable: por qué este producto era elegible. Nada de
    -- glosas derivadas —ruta de categoría o familia técnica—, que envejecen
    -- al lado de su fuente.
    jsonb_build_object(
      'chosen_from', 'family_alternative',
      'match_state', v_chosen ->> 'matchState',
      'match_detail', coalesce(v_chosen -> 'matchDetail', '[]'::jsonb),
      'from_revision_no', v_context.revision_no
    ),
    'family-choice-v1', v_actor_id
  );

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', true,
    'product_id', p_product_id,
    'match_state', v_chosen ->> 'matchState',
    'revision_no', v_next_revision,
    'from_revision_no', v_context.revision_no,
    -- Un rechazo de familia anterior sigue en pie: la persona ya decidió que
    -- el stock interno no servía, y confirmar cuál era el producto no
    -- reabre esa decisión.
    'internal_stock_rejection_reason', v_need.internal_stock_rejection_reason,
    'version', v_need.version,
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'family_choice_confirmed', true, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.confirm_supply_need_family_choice_v1(
  uuid, bigint, bigint, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.confirm_supply_need_family_choice_v1(
  uuid, bigint, bigint, uuid, text
) to authenticated;

comment on function public.confirm_supply_need_family_choice_v1(
  uuid, bigint, bigint, uuid, text
) is
  'Replay-safe convergence from a family alternative to a confirmed exact product. Revalidates tenant, category and eligibility under lock, copies category_id, constraints and clarifications into the new interpretation, stores only stable match evidence, preserves an earlier family rejection, and neither assigns stock nor creates a plan.';

commit;
