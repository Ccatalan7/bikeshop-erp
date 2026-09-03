-- Lo que falta de la frontera: el carril exacto y la confirmación.
--
-- `20260831240000` dejó dos bordes vivos, y este forward parte de él sin
-- revertir nada:
--
-- 1. Exigió categoría hoja para `no_criteria` **sin distinguir el carril**. Una
--    necesidad nacida exacta no tiene criterios de familia que comprobar, así
--    que dejaba de contar y su propio stock dejaba de bloquear el paso externo.
--    Pedirle prueba de compatibilidad a una identidad que el taller ya fijó es
--    exigir evidencia de una decisión, no de un hecho.
--
-- 2. `confirm_supply_need_family_choice_v1` **no pasa por el guard
--    compartido**: tiene su propia comprobación en línea, y seguía con la lista
--    de rótulos `('strong','weak','no_criteria')`. Es decir, la puerta que el
--    operador usa de verdad —`Elegir producto`— seguía aceptando un `weak` con
--    criterios sin resolver: en la necesidad real de pastillas Shimano
--    BR-MT200, resina y SIN aletas, dejaba confirmar `PASTILLA … METALICA J04C
--    CON DISIPADOR`, que contradice a la vista el compuesto y las aletas.
--
-- Los dos plan writers y el guard compartido ya quedaron correctos en 240000 y
-- no se tocan.

CREATE OR REPLACE FUNCTION public.supply_need_stock_bundle_internal_v1(p_tenant_id uuid, p_need_id uuid, p_max_universe integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_context record;
  v_eligible jsonb;
  v_items jsonb;
  v_total integer;
  v_full_count integer;
  v_partial_count integer;
  v_none_count integer;
  v_unverified_count integer;
  v_eligible_count integer;
  v_blocking boolean;
  v_family_atp integer;
  v_coverage text;
  v_category_is_leaf boolean;
begin
  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    p_tenant_id, p_need_id
  );

  -- La ÚNICA evaluación técnica de esta llamada.
  v_eligible := public.supply_need_eligible_products_internal_v1(
    p_tenant_id, p_need_id, p_max_universe
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
      'internalStockRejectionReason', v_context.internal_stock_rejection_reason,
      'coverage', 'none',
      'blocksExternal', false,
      'orderedItems', '[]'::jsonb,
      'counts', jsonb_build_object(
        'eligible', 0, 'reviewed', 0, 'full', 0, 'partial', 0, 'none', 0,
        'unverified', 0
      ),
      'familyAggregateAtp', 0,
      'familyAggregateProvesCoverage', false
    );
  end if;

  -- ATP una sola vez por producto: llamarla dentro de un CASE la evaluaría
  -- tres veces por fila, y es la parte cara de esta lectura.
  -- ¿La categoría de esta necesidad es una hoja del árbol del taller?
  -- Sin criterios, la categoría **es** toda la especificación, y sólo una hoja
  -- está lo bastante cerrada para que pertenecer a ella signifique algo. Una
  -- categoría con hijas activas agrupa cosas distintas: ahí «no hay criterios»
  -- no puede convertirse en compatibilidad inventada.
  select not exists (
    select 1 from public.product_categories child
    where child.tenant_id = p_tenant_id
      and child.parent_id = v_context.category_id
      and child.is_active is true
  ) into v_category_is_leaf;

  with evaluated as (
    select (entry.value ->> 'productId')::uuid as product_id,
      entry.value ->> 'matchState' as match_state,
      entry.value -> 'matchDetail' as match_detail,
      public.inventory_available_quantity_v1(
        p_tenant_id, (entry.value ->> 'productId')::uuid
      ) as atp
    from jsonb_array_elements(v_eligible -> 'items') entry(value)
  ), covered as (
    select evaluated.*,
      case
        when evaluated.atp >= v_context.quantity then 'full'
        when evaluated.atp > 0 then 'partial'
        else 'none'
      end as coverage,
      -- **Comprobada es COMPLETA, no «algo coincide».** `weak` significaba que
      -- algo se estableció y nada contradijo, con el resto sin resolver; la
      -- necesidad real de pastillas contaba como comprobadas dos filas
      -- `METALICA CON DISIPADOR` que contradicen a la vista el compuesto
      -- orgánico y la ausencia de aletas: sólo el sistema de freno estaba
      -- establecido, por el nombre, y los otros dos criterios seguían sin
      -- resolver. Una alternativa exige **todos** los predicados pedidos
      -- probados; lo parcial sigue visible y ordena mejor, pero por confirmar.
      case
        -- **El carril exacto ya tiene su identidad decidida por el taller.**
        -- `20260831240000` exigió categoría hoja para `no_criteria` sin
        -- distinguir el carril, y con eso una necesidad nacida exacta —que no
        -- tiene criterios de familia que comprobar— dejaba de contar y su
        -- propio stock dejaba de bloquear el paso externo. Pedirle una prueba
        -- de compatibilidad a una identidad que el taller ya fijó es exigir
        -- evidencia de una decisión, no de un hecho.
        when v_eligible ->> 'lane' = 'exact' then true
        when evaluated.match_state = 'no_criteria' then v_category_is_leaf
        else public.supply_need_evidence_is_complete_internal_v1(
          evaluated.match_detail
        )
      end as evidence_complete
    from evaluated
  ), ranked as (
    select covered.*,
      covered.coverage = 'full' and covered.evidence_complete
        as blocks_external,
      row_number() over (
        order by
          -- **La evidencia ordena antes que el stock.** La pantalla separa lo
          -- comprobado de lo que no, así que el orden tiene que respetar esa
          -- separación o la paginación la rompe: con la cobertura primero, una
          -- fila sin verificar con existencias adelantaba a una comprobada sin
          -- stock, y la segunda alternativa comprobada de la necesidad real de
          -- pastillas —Shimano J04C, ATP 0— caía a la página siguiente, detrás
          -- de once filas sin verificar. El operador veía «2 comprobadas» y
          -- sólo una en pantalla.
          case when covered.evidence_complete then 0 else 1 end,
          -- Dentro de cada grupo manda lo de siempre: primero lo que cubre.
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
      on product.tenant_id = p_tenant_id
     and product.id = covered.product_id
  )
  -- **Elegible es lo COMPROBADO, no lo revisado.** La categoría define el
  -- universo que hay que mirar; que una fila sobreviva a él no la hace una
  -- alternativa. Con `eligible` contando también lo no verificado, la necesidad
  -- de pastillas BR-MT200 anunciaba «49 alternativas internas elegibles» y
  -- ofrecía elegir patines V-Brake y pastillas Avid: 47 de esas 49 no tenían
  -- ni un criterio establecido. Lo revisado se conserva aparte, en `reviewed`,
  -- porque saber cuánto del catálogo está sin fichar sí es información.
  select count(*)::integer,
    count(*) filter (where coverage = 'full' and evidence_complete)::integer,
    count(*) filter (where coverage = 'partial' and evidence_complete)::integer,
    count(*) filter (where coverage = 'none' and evidence_complete)::integer,
    count(*) filter (where not evidence_complete)::integer,
    count(*) filter (where evidence_complete)::integer,
    coalesce(sum(atp), 0)::integer,
    coalesce(bool_or(blocks_external), false),
    -- El conjunto ORDENADO y completo. Paginar es cosa de quien muestra.
    coalesce(jsonb_agg(jsonb_build_object(
      'ordinal', ordinal,
      'productId', product_id,
      'name', name,
      'sku', sku,
      'imageUrlOptimized', nullif(btrim(image_url_optimized), ''),
      'imageUrl', nullif(btrim(image_url), ''),
      'imageUrls', to_jsonb(coalesce(image_urls, array[]::text[])),
      'atp', atp,
      'coverage', coverage,
      'matchState', match_state,
      'evidenceComplete', evidence_complete,
      'matchDetail', match_detail,
      'blocksExternal', blocks_external
    ) order by ordinal), '[]'::jsonb)
  into v_total, v_full_count, v_partial_count, v_none_count,
    v_unverified_count, v_eligible_count, v_family_atp, v_blocking, v_items
  from ranked;

  -- Y la cobertura sale de esos mismos contadores: decir «la bodega cubre esta
  -- necesidad» apoyándose en un producto que nadie pudo verificar es afirmar
  -- lo que no se sabe. Sin nada comprobado, la cobertura es `none` aunque haya
  -- existencias: hay stock de algo, no de esto.
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
    'orderedItems', v_items,
    'counts', jsonb_build_object(
      'eligible', v_eligible_count,
      'reviewed', v_total,
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
$function$;

CREATE OR REPLACE FUNCTION public.confirm_supply_need_family_choice_v1(p_need_id uuid, p_expected_version bigint, p_expected_revision_no bigint, p_product_id uuid, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET lock_timeout TO '750ms'
AS $function$
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
  -- **Elegir declara que ESTE producto es la necesidad: exige prueba.**
  -- Rechazar sólo `conflict` era una compuerta vacía —el conjunto elegible ya
  -- excluye los contradictorios— y dejaba pasar lo `unverified`: un cliente
  -- publicado anterior, que todavía muestra `Elegir producto` sobre filas sin
  -- verificar, podía confirmar hoy un patín V-Brake para una necesidad de
  -- pastillas. La lista es positiva: sólo entra lo comprobado.
  -- **Comprobado es COMPLETO, también acá.** Esta función no pasa por el guard
  -- compartido: tiene su propia comprobación, y con la lista de rótulos seguía
  -- aceptando un `weak` con criterios sin resolver. En la necesidad real de
  -- pastillas Shimano BR-MT200, resina y sin aletas, eso dejaba confirmar
  -- `PASTILLA … METALICA J04C CON DISIPADOR`: sólo el sistema de freno estaba
  -- establecido, por el nombre, y el compuesto y las aletas seguían sin leerse.
  if not coalesce(
       case
         when (v_chosen ->> 'matchState') = 'no_criteria' then not exists (
           select 1
           from public.product_categories child
           where child.tenant_id = v_tenant_id
             and child.parent_id = v_context.category_id
             and child.is_active is true
         )
         else public.supply_need_evidence_is_complete_internal_v1(
           v_chosen -> 'matchDetail'
         )
       end, false) then
    raise exception 'El producto no está comprobado contra los criterios de la necesidad.'
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
$function$;
