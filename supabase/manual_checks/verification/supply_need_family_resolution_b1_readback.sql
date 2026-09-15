-- Read-back de la Fase B1: del stock de la familia a un producto confirmado.
-- Falla a nivel SQL si la migración 20260817160000 no quedó instalada o quedó
-- instalada pero rota.
--
-- Se ejecutan de verdad: el contexto de resolución, el conjunto elegible, el
-- clasificador de coincidencia y la lectura pública de stock con un tenant
-- real. Los dos comandos escriben, así que en el camino de sólo-lectura se
-- exige su firma, su ACL y las invariantes de forma que los distinguen de v1.

-- El contexto de tenant se fija en una sentencia aparte: dentro de un CTE el
-- planificador puede evaluar la función antes de que `set_config` haya corrido.
-- Se elige un usuario del tenant que realmente tiene necesidades, porque
-- `user_tenant_id()` exige perfil único, activo y tenant activo.
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
     to_regprocedure('public.supply_need_resolution_context_internal_v1(uuid,uuid)') is not null
 and to_regprocedure('public.supply_need_match_detail_internal_v1(uuid,uuid,jsonb)') is not null
 and to_regprocedure('public.supply_need_match_state_internal_v1(jsonb,integer)') is not null
 and to_regprocedure('public.supply_need_eligible_products_internal_v1(uuid,uuid,integer)') is not null
 and to_regprocedure('public.get_supply_need_stock_resolution_v1(uuid,integer,integer)') is not null
 and to_regprocedure('public.reject_supply_need_internal_stock_v2(uuid,bigint,bigint,text,text)') is not null
 and to_regprocedure('public.confirm_supply_need_family_choice_v1(uuid,bigint,bigint,uuid,text)') is not null
  then 1 else 0 end) as b1_functions_present;

-- ── 2. ACL ────────────────────────────────────────────────────────────────
select 1 / (case when
     has_function_privilege('authenticated', 'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)', 'execute')
 and has_function_privilege('authenticated', 'public.reject_supply_need_internal_stock_v2(uuid,bigint,bigint,text,text)', 'execute')
 and has_function_privilege('authenticated', 'public.confirm_supply_need_family_choice_v1(uuid,bigint,bigint,uuid,text)', 'execute')
 and not has_function_privilege('anon', 'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)', 'execute')
 and not has_function_privilege('anon', 'public.reject_supply_need_internal_stock_v2(uuid,bigint,bigint,text,text)', 'execute')
 and not has_function_privilege('anon', 'public.confirm_supply_need_family_choice_v1(uuid,bigint,bigint,uuid,text)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_need_eligible_products_internal_v1(uuid,uuid,integer)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_need_resolution_context_internal_v1(uuid,uuid)', 'execute')
  then 1 else 0 end) as b1_acl;

-- ── 3. El ledger aprende los dos hechos nuevos ────────────────────────────
select 1 / (case when
     pg_get_constraintdef(oid) like '%family_stock_rejected%'
 and pg_get_constraintdef(oid) like '%family_choice_confirmed%'
 -- Ampliar un CHECK conserva todo el dominio vivo: ninguna acción anterior
 -- puede desaparecer.
 and pg_get_constraintdef(oid) like '%internal_stock_rejected%'
 and pg_get_constraintdef(oid) like '%stock_assigned%'
 and pg_get_constraintdef(oid) like '%stock_released%'
 and pg_get_constraintdef(oid) like '%stock_reactivated%'
 and pg_get_constraintdef(oid) like '%purchase_planned%'
 and pg_get_constraintdef(oid) like '%received%'
 and pg_get_constraintdef(oid) like '%covered%'
 and pg_get_constraintdef(oid) like '%cancelled%'
  then 1 else 0 end) as event_actions_are_additive
from pg_constraint
where conrelid = 'public.supply_need_events'::regclass
  and conname = 'supply_need_events_action_check';

-- Y ninguna fila viva queda fuera del dominio nuevo.
select 1 / (case when not exists (
  select 1 from public.supply_need_events event
  where event.action not in (
    'created', 'updated', 'cancelled',
    'stock_assigned', 'stock_released', 'stock_reactivated',
    'internal_stock_rejected', 'family_stock_rejected',
    'family_choice_confirmed', 'purchase_planned', 'received', 'covered'
  )
) then 1 else 0 end) as no_live_event_falls_outside_the_domain;

-- ── 4. El contexto de resolución se EJECUTA ───────────────────────────────
with target as (
  select need.id, need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), context as (
  select ctx.need_id, ctx.need_version, ctx.revision_no
  from target,
       public.supply_need_resolution_context_internal_v1(
         target.tenant_id, target.id
       ) ctx
)
select
  1 / (case when (select count(*) from context) = 1 then 1 else 0 end)
    as resolution_context_executes,
  1 / (case when (select need_id from context) = (select id from target)
        then 1 else 0 end) as resolution_context_is_its_need,
  -- La autoridad es la última revisión por `revision_no`, no por reloj.
  1 / (case when (select revision_no from context) >= 1 then 1 else 0 end)
    as resolution_context_carries_its_revision;

-- ── 5. El conjunto elegible se EJECUTA y declara su carril ────────────────
with target as (
  select need.id, need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), eligible as (
  select public.supply_need_eligible_products_internal_v1(
    target.tenant_id, target.id, 400
  ) as payload
  from target
)
select
  1 / (case when jsonb_typeof(payload) = 'object' then 1 else 0 end)
    as eligible_set_executes,
  1 / (case when (payload ->> 'lane') in ('exact', 'family')
        then 1 else 0 end) as eligible_set_declares_its_lane,
  1 / (case when jsonb_typeof(payload -> 'items') = 'array'
        then 1 else 0 end) as eligible_set_returns_a_list,
  1 / (case when payload ? 'universeSize' and payload ? 'safeLimit'
        then 1 else 0 end) as eligible_set_bounds_its_universe,
  -- El conteo de predicados viaja para que el clasificador no lo recompute.
  1 / (case when payload ? 'predicateCount' then 1 else 0 end)
    as predicate_count_travels_with_the_set
from eligible;

-- ── 6. El clasificador se EJECUTA y la regla más estricta gana ────────────
select
  1 / (case when public.supply_need_match_state_internal_v1(
        '[]'::jsonb, 0) = 'no_criteria' then 1 else 0 end)
    as no_criteria_is_its_own_state,
  1 / (case when public.supply_need_match_state_internal_v1(
        jsonb_build_array(
          jsonb_build_object('source', 'conflict'),
          jsonb_build_object('source', 'unresolved')
        ), 2) = 'conflict' then 1 else 0 end)
    as conflict_beats_unverified,
  -- `unverified` es «no lo sé», no «no cumple»: se conserva rotulado.
  1 / (case when public.supply_need_match_state_internal_v1(
        jsonb_build_array(
          jsonb_build_object('source', 'unresolved'),
          jsonb_build_object('source', 'identity_fallback')
        ), 2) = 'unverified' then 1 else 0 end)
    as unverified_beats_weak,
  1 / (case when public.supply_need_match_state_internal_v1(
        jsonb_build_array(jsonb_build_object('source', 'identity_fallback')),
        1) = 'weak' then 1 else 0 end) as identity_fallback_is_weak,
  1 / (case when public.supply_need_match_state_internal_v1(
        jsonb_build_array(jsonb_build_object('source', 'spec')),
        1) = 'strong' then 1 else 0 end) as a_full_spec_match_is_strong;

-- ── 7. La lectura pública se EJECUTA con sesión real ──────────────────────
with resolution as (
  select public.get_supply_need_stock_resolution_v1(
    (select need.id from public.supply_needs need
      order by need.created_at desc limit 1),
    12, 0
  ) as payload
)
select
  1 / (case when (payload ->> 'status') = 'ok' then 1 else 0 end)
    as stock_resolution_executes,
  1 / (case when jsonb_typeof(payload -> 'items') = 'array' then 1 else 0 end)
    as stock_resolution_returns_a_list,
  1 / (case when (payload ->> 'coverage') in ('full', 'partial', 'none')
        then 1 else 0 end) as coverage_is_typed,
  1 / (case when jsonb_typeof(payload -> 'blocksExternal') = 'boolean'
        then 1 else 0 end) as blocking_is_explicit,
  -- El agregado de familia es informativo y nunca prueba cobertura: sumar dos
  -- variantes distintas es una decisión del taller, no una del inventario.
  1 / (case when (payload ->> 'familyAggregateProvesCoverage') = 'false'
        then 1 else 0 end) as family_aggregate_never_proves_coverage,
  -- La lectura es autocontenida: trae con qué llamar al comando.
  1 / (case when payload ? 'needVersion' and payload ? 'revisionNo'
        then 1 else 0 end) as read_is_self_contained,
  1 / (case when (payload -> 'counts') ? 'eligible'
              and (payload -> 'counts') ? 'unverified'
        then 1 else 0 end) as counts_are_published
from resolution;

-- ── 8. Invariantes de forma de los dos comandos ───────────────────────────
-- El rechazo de familia es el carril que v1 nunca podía alcanzar.
select 1 / (case when pg_get_functiondef(
  'public.reject_supply_need_internal_stock_v2(uuid,bigint,bigint,text,text)'::regprocedure
) like '%family_stock_rejected%' then 1 else 0 end) as reject_v2_has_the_family_lane;

-- Atado a la versión de la necesidad Y a la revisión vigente: si alguien
-- reinterpretó entremedio, el rechazo se referiría a otro conjunto.
select 1 / (case when pg_get_functiondef(
  'public.reject_supply_need_internal_stock_v2(uuid,bigint,bigint,text,text)'::regprocedure
) like '%p_expected_revision_no%' then 1 else 0 end) as reject_v2_is_bound_to_its_revision;

select 1 / (case when pg_get_functiondef(
  'public.confirm_supply_need_family_choice_v1(uuid,bigint,bigint,uuid,text)'::regprocedure
) like '%family_choice_confirmed%'
  and pg_get_functiondef(
  'public.confirm_supply_need_family_choice_v1(uuid,bigint,bigint,uuid,text)'::regprocedure
) like '%p_expected_revision_no%'
  then 1 else 0 end) as confirm_is_bound_to_version_and_revision;

-- v1 del rechazo queda intacta: cualquier llamador que no migró sigue servido.
select 1 / (case when to_regprocedure(
  'public.reject_supply_need_internal_stock_v1(uuid,bigint,text,text)'
) is not null then 1 else 0 end) as reject_v1_still_serves_its_callers;
