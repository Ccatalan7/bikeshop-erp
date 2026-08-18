-- Read-back de los candidatos externos gobernados por la necesidad
-- (20260817220000). Falla a nivel SQL si la migración no quedó instalada, o si
-- quedó instalada pero rota.
--
-- Lo que se exige: la vista publica la moneda del precio de catálogo sin
-- reordenar nada; el kernel deja de tratar una resta entre monedas como
-- margen; la RPC pública **se ejecuta** sobre una necesidad real y devuelve
-- proveedores rankeados; el stock-first es una excepción y no una lista vacía;
-- y el envelope se arma clave por clave.

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

-- ── 1. La vista crece en una sola columna, al final ───────────────────────
select 1 / (case when
     (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
       order by ordinal_position desc limit 1) = 'price_currency'
  then 1 else 0 end) as price_currency_is_the_last_column;

select 1 / (case when count(*) = 42 then 1 else 0 end) as projection_grew_by_exactly_one
from information_schema.columns
where table_schema = 'public' and table_name = 'purchase_candidate_metrics_v1';

-- `brand_id`, la identidad que una preferencia comercial casa, sigue en su
-- sitio: la vista se redefine en seis migraciones y partir de una anterior
-- desharía en silencio lo que un revert restauró.
select 1 / (case when
     (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 41) = 'brand_id'
 and (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 40) = 'image_urls'
  then 1 else 0 end) as preceding_columns_kept_their_place;

-- `cost_currency` NO se publica: el candidato histórico se denomina en la
-- moneda de la compra, no en la del catálogo.
select 1 / (case when not exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'purchase_candidate_metrics_v1'
    and column_name = 'cost_currency'
) then 1 else 0 end) as catalog_cost_currency_is_not_published;

select 1 / (case when exists (
  select 1 from pg_class
  where oid = 'public.purchase_candidate_metrics_v1'::regclass
    and 'security_invoker=true' = any(reloptions)
) then 1 else 0 end) as view_stays_security_invoker;

-- ── 2. El kernel no cambió su contrato de salida ──────────────────────────
-- Ninguna clave nueva: el arnés golden compara el item entero, y
-- `catalogSalePriceCurrency` la publica la RPC nueva, en su propio campo.
select 1 / (case when pg_get_functiondef(
  'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)'::regprocedure
) not like '%''catalogSalePriceCurrency''%' then 1 else 0 end)
  as kernel_publishes_no_new_key;

-- Cuando las monedas difieren el margen es DESCONOCIDO, y el neutro es el
-- mismo 0.35 que ya usaba para un margen nulo: no hay una tercera semántica.
select 1 / (case when pg_get_functiondef(
  'public.purchase_candidate_scores_internal_v1(uuid,uuid[],text,text)'::regprocedure
) like '%price_currency%' then 1 else 0 end) as kernel_knows_the_price_currency;

-- ── 3. Presencia, firma y ACL ─────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.supply_need_external_envelope_internal_v1(jsonb,jsonb,text,text,text,jsonb,integer,jsonb,jsonb,jsonb,jsonb)') is not null
 and to_regprocedure('public.supply_need_external_page_internal_v1(integer,integer,integer)') is not null
 and to_regprocedure('public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)') is not null
 and to_regprocedure('public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)') is not null
  then 1 else 0 end) as external_functions_present;

select 1 / (case when
     has_function_privilege('authenticated', 'public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)', 'execute')
 and not has_function_privilege('anon', 'public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_need_external_envelope_internal_v1(jsonb,jsonb,text,text,text,jsonb,integer,jsonb,jsonb,jsonb,jsonb)', 'execute')
  then 1 else 0 end) as external_acl;

-- El techo de fanout no es negociable desde el cliente: la RPC pública no lo
-- expone. Un techo negociable no es un techo.
select 1 / (case when pg_get_function_identity_arguments(
  'public.get_supply_need_external_candidates_v1(uuid,integer,integer,integer,integer)'::regprocedure
) = 'p_need_id uuid, p_limit integer, p_offset integer, p_unverified_limit integer, p_unverified_offset integer'
  then 1 else 0 end) as fanout_ceiling_is_server_owned;

-- ── 4. La aritmética de página tiene un solo dueño ───────────────────────
select
  1 / (case when public.supply_need_external_page_internal_v1(10, 0, 25)
        = jsonb_build_object('limit', 10, 'offset', 0, 'total', 25,
            'returned', 10, 'hasMore', true, 'nextOffset', 10)
        then 1 else 0 end) as page_math_first_page,
  1 / (case when public.supply_need_external_page_internal_v1(10, 20, 25)
        = jsonb_build_object('limit', 10, 'offset', 20, 'total', 25,
            'returned', 5, 'hasMore', false, 'nextOffset', null)
        then 1 else 0 end) as page_math_last_page,
  -- Un desplazamiento más allá del final no devuelve un `returned` negativo.
  1 / (case when (public.supply_need_external_page_internal_v1(10, 90, 25)
        ->> 'returned')::integer = 0 then 1 else 0 end) as page_math_never_goes_negative;

-- ── 5. La RPC pública SE EJECUTA sobre una necesidad real ────────────────
-- La necesidad se elige por evidencia, no a mano: abierta, con el bundle en
-- `ok`, sin bloqueo stock-first pendiente, y con historial de compra para sus
-- productos elegibles. Es el caso que demuestra el recorrido completo.
with scoped as (
  select need.id, need.tenant_id,
    public.supply_need_stock_bundle_internal_v1(need.tenant_id, need.id) as bundle
  from public.supply_needs need
  where need.supply_state not in ('covered', 'cancelled')
), open_lane as (
  select scoped.id, scoped.tenant_id, scoped.bundle,
    (select count(*)
       from jsonb_array_elements(scoped.bundle -> 'orderedItems') entry(value)
      where entry.value ->> 'matchState' <> 'conflict'
        and exists (
          select 1 from public.purchase_candidate_metrics_v1 metric
          where metric.tenant_id = scoped.tenant_id
            and metric.product_id = (entry.value ->> 'productId')::uuid
        )) as candidate_products
  from scoped
  where (scoped.bundle ->> 'status') = 'ok'
    and ((scoped.bundle ->> 'blocksExternal')::boolean is not true
      or nullif(btrim(coalesce(
           scoped.bundle ->> 'internalStockRejectionReason', '')), '')
         is not null)
), target as (
  select id, candidate_products
  from open_lane
  order by candidate_products desc, id
  limit 1
), answer as (
  select target.candidate_products,
    public.get_supply_need_external_candidates_v1(target.id, 10, 0, 5, 0) as payload
  from target
)
select
  -- Hay al menos una necesidad con historial: si no, este read-back estaría
  -- afirmando sobre un vacío.
  1 / (case when (select candidate_products from answer) > 0
        then 1 else 0 end) as a_real_need_has_historical_candidates,
  1 / (case when (payload ->> 'status') = 'success' then 1 else 0 end)
    as external_candidates_executes_and_ranks,
  -- **Los proveedores vuelven rankeados, con su razón.** En qué grupo caen lo
  -- decide `matchState`, que depende de la ficha del producto: exigir el grupo
  -- accionable ataba el read-back a los datos del día. El 2026-08-18 una
  -- necesidad creada por la IA —con criterios técnicos que la ficha no puede
  -- confirmar— dejó su único candidato en `unverified` y puso rojo este
  -- archivo sin que nada estuviera roto.
  1 / (case when jsonb_array_length(payload -> 'items')
            + jsonb_array_length(payload -> 'unverifiedItems') > 0
        then 1 else 0 end) as suppliers_come_back_ranked,
  -- Envelope clave por clave: 33 claves, ni una más.
  1 / (case when payload ?& array[
        'needId','needVersion','revisionNo','needSupplyState','quantity','unit',
        'targetRevisionNo','target','targetCurrencyCode','tenantCurrencyCode',
        'preferredBrandAvailable','legacyPreferenceNote',
        'rankingProfile','rankingProfileSource','rankingVersion',
        'lane','categoryId','universeSize','safeLimit','availableFields',
        'coverage','blocksExternal','internalStockRejectionReason','status',
        'candidateUniverseSize','candidateSafeLimit','scoreScope',
        'items','unverifiedItems','counts','page','unverifiedPage',
        'supplierAvailabilitySemantics']
        then 1 else 0 end) as external_envelope_is_complete,
  1 / (case when (select count(*) from jsonb_object_keys(payload)) = 33
        then 1 else 0 end) as external_envelope_has_no_extra_keys,
  -- El origen del perfil viaja: `balanced` por omisión no es `balanced` elegido.
  1 / (case when (payload ->> 'rankingProfileSource')
        in ('revision', 'default', 'default_unrecognized')
        then 1 else 0 end) as profile_source_is_explicit,
  -- El puntaje es relativo al conjunto elegible y se dice.
  1 / (case when (payload -> 'scoreScope' ->> 'basis') = 'eligible_set'
              and (payload -> 'scoreScope' ->> 'comparableAcrossRequests') = 'false'
        then 1 else 0 end) as score_scope_is_declared,
  -- Historial de compra no es disponibilidad de proveedor. Nunca.
  1 / (case when (payload ->> 'supplierAvailabilitySemantics')
        = 'historical_only_unverified' then 1 else 0 end)
    as availability_stays_unverified,
  -- Dos grupos, dos páginas independientes.
  1 / (case when (payload -> 'page' ->> 'total')::integer
              = (payload -> 'counts' ->> 'actionable')::integer
              and (payload -> 'unverifiedPage' ->> 'total')::integer
              = (payload -> 'counts' ->> 'unverified')::integer
        then 1 else 0 end) as the_two_groups_paginate_independently
from answer;

-- Cada candidato accionable trae su razón en números y en palabras: el
-- veredicto técnico y la calidad de la evidencia son dos autoridades
-- distintas, y una factura completa no convierte a un no verificado en
-- «Cumple».
with scoped as (
  select need.id, need.tenant_id,
    public.supply_need_stock_bundle_internal_v1(need.tenant_id, need.id) as bundle
  from public.supply_needs need
  where need.supply_state not in ('covered', 'cancelled')
), open_lane as (
  select scoped.id, scoped.tenant_id, scoped.bundle,
    (select count(*)
       from jsonb_array_elements(scoped.bundle -> 'orderedItems') entry(value)
      where entry.value ->> 'matchState' <> 'conflict'
        and exists (
          select 1 from public.purchase_candidate_metrics_v1 metric
          where metric.tenant_id = scoped.tenant_id
            and metric.product_id = (entry.value ->> 'productId')::uuid
        )) as candidate_products
  from scoped
  where (scoped.bundle ->> 'status') = 'ok'
    and ((scoped.bundle ->> 'blocksExternal')::boolean is not true
      or nullif(btrim(coalesce(
           scoped.bundle ->> 'internalStockRejectionReason', '')), '')
         is not null)
), target as (
  select id from open_lane order by candidate_products desc, id limit 1
), answer as (
  select public.get_supply_need_external_candidates_v1(target.id, 10, 0, 5, 0) as payload
  from target
), items as (
  -- Los dos grupos: un candidato no verificado también debe traer su razón
  -- completa. «No saber» no exime de explicar por qué aparece.
  select entry.value as item
  from answer,
    lateral jsonb_array_elements(
      (answer.payload -> 'items') || (answer.payload -> 'unverifiedItems')
    ) entry(value)
)
select
  1 / (case when not exists (
        select 1 from items
        where not (item ?& array['candidateId','supplierName','rank',
          'overallRank','baseRank','baseRankingScore','rankingScore',
          'rankingVersion','group','matchState','matchDetail','requestMatch',
          'evidenceQuality','freightEvidence','catalogSalePriceCurrency'])
      ) then 1 else 0 end) as every_candidate_carries_its_reason,
  -- `matchState` decide el veredicto técnico; `evidenceQuality` describe la
  -- evidencia económica. Son autoridades separadas.
  1 / (case when not exists (
        select 1 from items
        where (item ->> 'group') = 'actionable'
          and (item ->> 'matchState') = 'unverified'
      ) then 1 else 0 end) as unverified_never_lands_in_the_actionable_group,
  -- El blend se declara: sin señal conocida el puntaje heredado se conserva
  -- **exactamente**.
  1 / (case when not exists (
        select 1 from items
        where (item -> 'requestMatch' ->> 'blendApplied') = 'false'
          and (item ->> 'rankingScore')::numeric
              is distinct from (item ->> 'baseRankingScore')::numeric
      ) then 1 else 0 end) as no_signals_keeps_the_legacy_score_exactly,
  1 / (case when not exists (
        select 1 from items
        where not ((item -> 'requestMatch' -> 'signals') ?& array[
          'preferredBrandId','maxLandedUnitCostNet','minGrossMarginRatio','gama'])
      ) then 1 else 0 end) as the_four_signals_are_always_reported
from items limit 1;

-- ── 6. Stock-first es una excepción, no una lista vacía ──────────────────
-- Una lista vacía la muestra cualquier interfaz como «no hay proveedores», y
-- el operador terminaría comprando lo que ya tiene en bodega.
select 1 / (case when pg_get_functiondef(
  'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
) like '%stock_first_required%'
  and pg_get_functiondef(
  'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
) like '%reject_supply_need_internal_stock_v2%'
  then 1 else 0 end) as stock_first_raises_instead_of_emptying;

-- Los caminos sin ranking quedan separados por causa y próxima acción.
select 1 / (case when
     definition like '%supply_closed%'
 and definition like '%technical_conflict%'
 and definition like '%no_eligible_products%'
 and definition like '%no_historical_candidates%'
 and definition like '%analysis_too_broad%'
 -- Historial vacío NO se llama `verifiedEmpty`: aquí no se verificó
 -- disponibilidad externa de nadie.
 and definition not like '%verifiedEmpty%'
  then 1 else 0 end) as no_ranking_paths_are_named_by_cause
from (
  select pg_get_functiondef(
    'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
  ) as definition
) source;

-- ── 7. Una sola llamada al bundle y una sola al kernel ───────────────────
select
  1 / (case when
    (length(definition) - length(replace(definition,
      'supply_need_stock_bundle_internal_v1', '')))
    / length('supply_need_stock_bundle_internal_v1') = 1
    then 1 else 0 end) as exactly_one_technical_evaluation,
  1 / (case when
    (length(definition) - length(replace(definition,
      'purchase_candidate_scores_internal_v1', '')))
    / length('purchase_candidate_scores_internal_v1') = 1
    then 1 else 0 end) as exactly_one_kernel_call,
  -- El universo se resuelve en una sentencia PROPIA. Derivar los ids desde la
  -- vista dentro de la misma sentencia que invoca el kernel midió 6.494 ms.
  1 / (case when position('into v_candidate_ids' in definition)
              < position('purchase_candidate_scores_internal_v1' in definition)
        then 1 else 0 end) as universe_is_resolved_before_the_kernel,
  -- El envelope tiene un solo dueño y nunca se resta del bundle.
  1 / (case when definition not like '%v_bundle - %' then 1 else 0 end)
    as envelope_is_never_subtracted
from (
  select pg_get_functiondef(
    'public.supply_need_external_candidates_internal_v1(uuid,uuid,integer,integer,integer,integer,integer)'::regprocedure
  ) as definition
) source;

-- ── 8. Las `*_v1` anteriores quedan con su firma y su salida ─────────────
select 1 / (case when
     to_regprocedure('public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)') is not null
 and to_regprocedure('public.get_supply_need_stock_resolution_v1(uuid,integer,integer)') is not null
 and to_regprocedure('public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)') is not null
  then 1 else 0 end) as previous_contracts_survive;
