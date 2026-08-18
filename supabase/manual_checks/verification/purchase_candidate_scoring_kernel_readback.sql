-- Read-back del kernel único de scoring (20260817190000).
-- Falla a nivel SQL si la migración no quedó instalada, o si quedó instalada
-- pero rota.
--
-- Lo que se exige: el kernel **se ejecuta** sobre identidades de candidato
-- reales, ordena de forma contigua, publica el item canónico ya armado, y el
-- envelope de `rank_purchase_candidates_v1` no se movió ni un campo. La gama
-- **ordena y nunca elimina**, y eso se comprueba ejecutando las dos formas
-- sobre el mismo universo.

-- El contexto de tenant va en una sentencia aparte: dentro de un CTE el
-- planificador puede evaluar la función antes de que `set_config` haya corrido.
select set_config(
  'request.jwt.claim.sub',
  (select profile.user_id::text
     from public.user_profiles profile
     join public.tenants tenant
       on tenant.id = profile.tenant_id
      and tenant.is_active is true
    where profile.is_active is true
      and profile.tenant_id = (
        select need.tenant_id from public.supply_needs need
        order by need.created_at desc limit 1
      )
    group by profile.user_id
   having count(*) = 1
    limit 1),
  true
) as tenant_context_ready;

-- ── 1. Presencia y firma exacta ────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)') is not null
 and to_regprocedure('public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)') is not null
  then 1 else 0 end) as kernel_and_wrapper_present;

-- El kernel recibe **identidades de candidato**, no productos: colapsar a
-- `product_ids` y reexpandir agregaría proveedores que la consulta no trajo.
select 1 / (case when pg_get_function_identity_arguments(
  'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)'::regprocedure
) = 'p_tenant_id uuid, p_candidate_ids uuid[], p_profile text, p_gama text'
  then 1 else 0 end) as kernel_takes_candidate_identities;

-- ── 2. ACL: el kernel es interno, el wrapper conserva el suyo ─────────────
select 1 / (case when
     not has_function_privilege('authenticated', 'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)', 'execute')
 and not has_function_privilege('anon', 'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)', 'execute')
 and has_function_privilege('authenticated', 'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)', 'execute')
 and not has_function_privilege('anon', 'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)', 'execute')
  then 1 else 0 end) as kernel_acl;

-- ── 3. El kernel SE EJECUTA sobre candidatos reales ───────────────────────
-- Acotado al tenant que tiene necesidades: el camino guardado corre con rol
-- privilegiado y sin RLS, y un barrido completo tocaría todos los talleres.
with scope as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), universe as (
  select array_agg(picked.candidate_id) as candidate_ids
  from (
    select metric.candidate_id
    from public.purchase_candidate_metrics_v1 metric, scope
    where metric.tenant_id = scope.tenant_id
    order by metric.candidate_id
    limit 50
  ) picked
), scored as (
  select kernel.candidate_id, kernel.product_id, kernel.rank,
    kernel.matched_count, kernel.ranking_score, kernel.item
  from scope, universe,
       public.purchase_candidate_scores_internal_v1(
         scope.tenant_id, universe.candidate_ids, 'balanced'
       ) kernel
)
select
  1 / (case when (select count(*) from scored) > 0 then 1 else 0 end)
    as kernel_executes_with_rows,
  -- Devuelve exactamente el universo que recibió: ni agrega ni pierde.
  1 / (case when (select count(*) from scored)
            = (select coalesce(array_length(candidate_ids, 1), 0) from universe)
        then 1 else 0 end) as kernel_returns_its_universe,
  -- Orden contiguo desde 1: `row_number()` sobre el conjunto completo.
  1 / (case when (select min(rank) from scored) = 1
              and (select max(rank) from scored) = (select count(*) from scored)
              and (select count(distinct rank) from scored) = (select count(*) from scored)
        then 1 else 0 end) as ranks_are_contiguous,
  -- `matched_count` es el tamaño del conjunto, igual en cada fila.
  1 / (case when (select count(distinct matched_count) from scored) = 1
              and (select max(matched_count) from scored) = (select count(*) from scored)
        then 1 else 0 end) as matched_count_is_the_set_size,
  -- Un puntaje mayor nunca queda peor rankeado.
  1 / (case when not exists (
        select 1 from scored a join scored b on a.rank < b.rank
        where a.ranking_score < b.ranking_score
      ) then 1 else 0 end) as score_and_rank_agree;

-- El item canónico viaja **ya armado** desde el kernel: un solo dueño de la
-- proyección, y nadie reescanea la vista cara para reconstruirlo.
with scope as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), universe as (
  select array_agg(picked.candidate_id) as candidate_ids
  from (
    select metric.candidate_id
    from public.purchase_candidate_metrics_v1 metric, scope
    where metric.tenant_id = scope.tenant_id
    order by metric.candidate_id
    limit 50
  ) picked
), scored as (
  select kernel.candidate_id, kernel.rank, kernel.ranking_score, kernel.item
  from scope, universe,
       public.purchase_candidate_scores_internal_v1(
         scope.tenant_id, universe.candidate_ids, 'balanced'
       ) kernel
)
select
  1 / (case when not exists (
        select 1 from scored where jsonb_typeof(item) <> 'object'
      ) then 1 else 0 end) as item_is_an_object,
  -- La identidad del item es la del candidato, no la del producto.
  1 / (case when not exists (
        select 1 from scored
        where (item ->> 'candidateId')::uuid is distinct from candidate_id
           or (item ->> 'rank')::integer is distinct from rank
           or (item ->> 'rankingScore')::numeric is distinct from ranking_score
      ) then 1 else 0 end) as item_carries_its_own_identity,
  -- Los 43 campos del contrato siguen publicados: el arnés golden existe
  -- porque reescribir esta proyección de memoria ya produjo nueve distintos.
  1 / (case when not exists (
        select 1 from scored
        where not (item ?& array[
          'candidateId','rank','rankingProfile','rankingVersion','rankingScore',
          'productId','productName','productSku','brand','category',
          'imageUrlOptimized','imageUrl','imageUrls',
          'supplierId','supplierName','supplierWebsite','supplierLocation',
          'isConfirmedLocal','supplierAvailability','currency',
          'latestBaseUnitCostNet','latestAllocatedFreightNet',
          'latestLandedUnitCostNet','catalogSalePriceGross','catalogSalePriceNet',
          'projectedUnitGrossProfit','projectedGrossMarginRatio',
          'purchaseCount','purchasedUnits','lastPurchaseAt','evidenceAgeDays',
          'evidenceQuality','freightEvidence',
          'economyScore','historyScore','recencyScore','stabilityScore',
          'evidenceScore','gama','gamaIsConfident','gamaScore',
          'latestPurchaseInvoiceId','latestPurchaseInvoiceLineId'])
      ) then 1 else 0 end) as item_contract_is_complete,
  -- Y ninguna clave de más: una columna nueva de la vista no puede colarse.
  1 / (case when not exists (
        select 1 from scored
        where (select count(*) from jsonb_object_keys(item)) <> 43
      ) then 1 else 0 end) as item_has_no_extra_keys
from scored limit 1;

-- ── 4. La gama ORDENA, NUNCA ELIMINA ──────────────────────────────────────
-- Mismo universo, con y sin gama pedida: el conteo es idéntico.
with scope as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), universe as (
  select array_agg(picked.candidate_id) as candidate_ids
  from (
    select metric.candidate_id
    from public.purchase_candidate_metrics_v1 metric, scope
    where metric.tenant_id = scope.tenant_id
    order by metric.candidate_id
    limit 50
  ) picked
), plain as (
  select count(*)::integer as n
  from scope, universe,
       public.purchase_candidate_scores_internal_v1(
         scope.tenant_id, universe.candidate_ids, 'balanced'
       ) kernel
), with_gama as (
  select count(*)::integer as n
  from scope, universe,
       public.purchase_candidate_scores_internal_v1(
         scope.tenant_id, universe.candidate_ids, 'balanced', 'alta'
       ) kernel
)
select 1 / (case when (select n from plain) = (select n from with_gama)
      then 1 else 0 end) as gama_orders_and_never_eliminates;

-- ── 5. El wrapper SE EJECUTA y su envelope no se movió ────────────────────
with ranked as (
  select public.rank_purchase_candidates_v1(
    null,
    (select metric.product_id
       from public.purchase_candidate_metrics_v1 metric
       where metric.tenant_id = (
         select need.tenant_id from public.supply_needs need
         order by need.created_at desc limit 1)
       order by metric.candidate_id
       limit 1),
    null, 'balanced', 10, null
  ) as payload
)
select
  1 / (case when (payload ->> 'status') in ('success', 'verifiedEmpty')
        then 1 else 0 end) as wrapper_executes,
  1 / (case when jsonb_typeof(payload -> 'items') = 'array'
        then 1 else 0 end) as wrapper_returns_a_list,
  -- El envelope es el mismo de siempre: seis claves, ni una más.
  1 / (case when payload ?& array['asOf','status','items','resultCount',
                                  'hasMore','supplierAvailabilitySemantics']
              and (select count(*) from jsonb_object_keys(payload)) = 6
        then 1 else 0 end) as wrapper_envelope_is_unchanged,
  -- La disponibilidad sigue siendo histórica, nunca stock del portal.
  1 / (case when (payload ->> 'supplierAvailabilitySemantics')
              = 'historical_only_unverified' then 1 else 0 end)
    as availability_semantics_survive,
  1 / (case when (payload ->> 'resultCount')::integer
              = jsonb_array_length(payload -> 'items') then 1 else 0 end)
    as result_count_matches_the_list
from ranked;

-- ── 6. Invariantes de forma: un solo dueño, y la forma prohibida ──────────
-- El wrapper delega: no vuelve a armar el item.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) like '%purchase_candidate_scores_internal_v1%'
  and pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) not like '%''rankingVersion'', ''purchase-ranking-v1''%'
  then 1 else 0 end) as wrapper_delegates_the_projection;

-- La forma prohibida: derivar los ids DESDE la vista dentro de la misma
-- sentencia que invoca el kernel midió 6.494 ms en producción. El wrapper
-- resuelve su universo en una sentencia propia, con `into v_candidate_ids`.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) like '%into v_candidate_ids%'
  then 1 else 0 end) as universe_is_resolved_in_its_own_statement;

-- El kernel lee la vista cara **una sola vez** y la acota por identidad de
-- candidato. La medición decidió esta forma: filtrar por `candidate_id` es
-- selectivo —13,8 ms con uno, 35,7 con los 268— mientras que filtrar por
-- subárbol de categoría obliga a materializar la vista entera.
select
  1 / (case when
    (length(definition) - length(replace(definition, marker, '')))
    / length(marker) = 1
    then 1 else 0 end) as kernel_reads_the_expensive_view_once,
  1 / (case when definition like '%metric.candidate_id = any(p_candidate_ids)%'
        then 1 else 0 end) as kernel_filters_by_candidate_identity,
  -- Y nunca por subárbol de categoría: eso es trabajo del llamador, que ya
  -- resolvió su universo en una sentencia propia.
  1 / (case when definition not like '%category_scope%'
        then 1 else 0 end) as kernel_never_resolves_a_category_subtree
from (
  select pg_get_functiondef(
    'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)'::regprocedure
  ) as definition,
  'public.purchase_candidate_metrics_v1' as marker
) source;
