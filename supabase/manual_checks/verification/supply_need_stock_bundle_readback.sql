-- Read-back del bundle stock-first (20260817200000).
-- Falla a nivel SQL si la migración no quedó instalada, o si quedó instalada
-- pero rota.
--
-- Lo que se exige: el bundle es **dueño único** de ATP, cobertura y bloqueo y
-- se evalúa **una sola vez por invocación RPC**; la lectura pública sólo pagina
-- y proyecta; y su envelope se arma **clave por clave**, nunca restando del
-- bundle —una resta hereda en silencio todo lo que el bundle agregue después—.

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

-- ── 1. Presencia, firma y ACL ─────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.supply_need_stock_bundle_internal_v1(uuid,uuid,integer)') is not null
 and to_regprocedure('public.get_supply_need_stock_resolution_v1(uuid,integer,integer)') is not null
  then 1 else 0 end) as bundle_and_reader_present;

select 1 / (case when
     not has_function_privilege('authenticated', 'public.supply_need_stock_bundle_internal_v1(uuid,uuid,integer)', 'execute')
 and not has_function_privilege('anon', 'public.supply_need_stock_bundle_internal_v1(uuid,uuid,integer)', 'execute')
 and has_function_privilege('authenticated', 'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)', 'execute')
 and not has_function_privilege('anon', 'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)', 'execute')
  then 1 else 0 end) as bundle_acl;

-- ── 2. El bundle SE EJECUTA y publica el conjunto completo ordenado ───────
with target as (
  select need.id, need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), bundle as (
  select public.supply_need_stock_bundle_internal_v1(
    target.tenant_id, target.id
  ) as payload
  from target
)
select
  1 / (case when (payload ->> 'status') = 'ok' then 1 else 0 end)
    as bundle_executes,
  1 / (case when (payload ->> 'needId')::uuid = (select id from target)
        then 1 else 0 end) as bundle_is_its_need,
  -- El conjunto COMPLETO y ordenado: paginar es cosa de quien muestra.
  1 / (case when jsonb_typeof(payload -> 'orderedItems') = 'array'
        then 1 else 0 end) as bundle_returns_the_whole_ordered_set,
  1 / (case when jsonb_array_length(payload -> 'orderedItems')
            = (payload -> 'counts' ->> 'eligible')::integer
        then 1 else 0 end) as ordered_set_matches_its_count,
  -- El orden viaja explícito: quien pagina no lo recalcula.
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload -> 'orderedItems') entry
        where not (entry.value ? 'ordinal')
      ) then 1 else 0 end) as every_item_carries_its_ordinal,
  -- ATP, cobertura y bloqueo tienen un solo dueño, y es éste.
  1 / (case when (payload ->> 'coverage') in ('full', 'partial', 'none')
              and jsonb_typeof(payload -> 'blocksExternal') = 'boolean'
              and payload ? 'familyAggregateAtp'
        then 1 else 0 end) as bundle_owns_atp_coverage_and_blocking,
  -- El agregado de familia nunca prueba cobertura.
  1 / (case when (payload ->> 'familyAggregateProvesCoverage') = 'false'
        then 1 else 0 end) as family_aggregate_never_proves_coverage
from bundle;

-- ── 3. La lectura pública SE EJECUTA y su envelope es explícito ───────────
with resolution as (
  select public.get_supply_need_stock_resolution_v1(
    (select need.id from public.supply_needs need
      order by need.created_at desc limit 1),
    12, 0
  ) as payload
)
select
  1 / (case when (payload ->> 'status') = 'ok' then 1 else 0 end)
    as public_read_executes,
  -- Clave por clave: exactamente el contrato público de la rama `ok`,
  -- ni una más. `orderedItems` es del bundle y no se filtra.
  1 / (case when payload ?& array[
        'needId','needVersion','revisionNo','quantity','unit','lane','status',
        'categoryId','universeSize','coverage','blocksExternal',
        'internalStockRejectionReason','items','page','counts',
        'familyAggregateAtp','familyAggregateProvesCoverage']
        then 1 else 0 end) as public_envelope_is_complete,
  1 / (case when (select count(*) from jsonb_object_keys(payload)) = 17
        then 1 else 0 end) as public_envelope_has_no_extra_keys,
  1 / (case when not (payload ? 'orderedItems') then 1 else 0 end)
    as bundle_internals_never_leak,
  -- La rama `ok` no publica `safeLimit` ni `availableFields`: sólo tienen
  -- sentido cuando el universo desbordó y hay algo que refinar.
  1 / (case when not (payload ? 'safeLimit')
              and not (payload ? 'availableFields') then 1 else 0 end)
    as refinement_fields_are_absent_when_nothing_overflowed,
  -- El `ordinal` es maquinaria del bundle y se quita al proyectar.
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload -> 'items') entry
        where entry.value ? 'ordinal'
      ) then 1 else 0 end) as ordinal_is_stripped_from_the_public_items,
  1 / (case when jsonb_array_length(payload -> 'items') <= 12
        then 1 else 0 end) as page_respects_its_limit,
  1 / (case when (payload -> 'page' ->> 'limit')::integer = 12
              and (payload -> 'page' ->> 'offset')::integer = 0
              and jsonb_typeof(payload -> 'page' -> 'hasMore') = 'boolean'
        then 1 else 0 end) as page_echoes_its_bounds
from resolution;

-- La paginación corta el mismo conjunto, no otro: el desplazamiento devuelve
-- el resto y nunca repite lo ya mostrado.
with target as (
  select need.id from public.supply_needs need
  order by need.created_at desc limit 1
), first_page as (
  select public.get_supply_need_stock_resolution_v1(target.id, 1, 0) as payload
  from target
), second_page as (
  select public.get_supply_need_stock_resolution_v1(target.id, 1, 1) as payload
  from target
)
select 1 / (case when
      (select (payload -> 'counts' ->> 'eligible')::integer from first_page)
    = (select (payload -> 'counts' ->> 'eligible')::integer from second_page)
  and (
    (select (payload -> 'counts' ->> 'eligible')::integer from first_page) < 2
    or (select payload -> 'items' -> 0 ->> 'productId' from first_page)
       is distinct from
       (select payload -> 'items' -> 0 ->> 'productId' from second_page)
  )
  then 1 else 0 end) as pagination_slices_one_set;

-- ── 4. Una sola evaluación técnica por invocación RPC ─────────────────────
-- No «por sesión»: la RPC externa llama al bundle dentro de su propia
-- invocación y no reutiliza la lectura que la interfaz hizo antes.
select 1 / (case when
  (length(definition) - length(replace(definition, marker, '')))
  / length(marker) = 1
  then 1 else 0 end) as exactly_one_technical_evaluation
from (
  select pg_get_functiondef(
    'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
  ) as definition,
  'supply_need_stock_bundle_internal_v1' as marker
) source;

-- ── 5. El envelope se proyecta, no se resta ───────────────────────────────
select 1 / (case when pg_get_functiondef(
  'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
) not like '%v_bundle - %' then 1 else 0 end) as envelope_is_never_subtracted;

-- Y la lectura pública ya no recalcula nada del dominio técnico: ni ATP, ni
-- cobertura, ni conjunto elegible. Sólo pagina y proyecta.
select 1 / (case when pg_get_functiondef(
  'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
) not like '%supply_need_eligible_products_internal_v1%'
  and pg_get_functiondef(
  'public.get_supply_need_stock_resolution_v1(uuid,integer,integer)'::regprocedure
) not like '%inventory_available_quantity_v1%'
  then 1 else 0 end) as public_read_only_paginates_and_projects;
