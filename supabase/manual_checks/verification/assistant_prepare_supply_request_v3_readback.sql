-- Read-back de `assistant_prepare_supply_request_v3` (20260818210000).
-- Falla a nivel SQL si no quedó instalada o quedó rota.
--
-- La función pública exige autoridad de asistente, que no existe fuera de una
-- sesión del gateway, así que acá se ejecutan sus dueños delegados con un
-- tenant explícito —el camino guardado corre con rol privilegiado y sin RLS— y
-- de la pública se exigen firma, ACL y las invariantes de forma que la separan
-- de `_v2`.

-- ── 1. Presencia, firma y ACL ─────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.assistant_prepare_supply_request_v3(jsonb,text)') is not null
 and to_regprocedure('public.assistant_prepare_supply_request_v2(jsonb,text)') is not null
  then 1 else 0 end) as v3_present_and_v2_intact;

select 1 / (case when
     has_function_privilege('authenticated', 'public.assistant_prepare_supply_request_v3(jsonb,text)', 'execute')
 and not has_function_privilege('anon', 'public.assistant_prepare_supply_request_v3(jsonb,text)', 'execute')
  then 1 else 0 end) as v3_acl;

-- ── 2. Las reglas del objetivo tienen UN dueño, y v3 lo delega ───────────
-- Reimplementarlas acá crearía una segunda verdad que envejece.
select 1 / (case when pg_get_functiondef(
  'public.assistant_prepare_supply_request_v3(jsonb,text)'::regprocedure
) like '%normalize_commercial_target_internal_v1%'
  and pg_get_functiondef(
  'public.assistant_prepare_supply_request_v3(jsonb,text)'::regprocedure
) like '%normalize_supply_request_items_internal_v2%'
  then 1 else 0 end) as v3_delegates_both_domains;

-- El objetivo se reindexa por `lineRef` real, nunca por posición: colgar un
-- objetivo de la línea equivocada es el defecto que ya se corrigió una vez.
select 1 / (case when pg_get_functiondef(
  'public.assistant_prepare_supply_request_v3(jsonb,text)'::regprocedure
) like '%v_targets ? (item.value ->> ''lineRef'')%'
  then 1 else 0 end) as target_is_indexed_by_line_ref;

-- ── 3. El dueño delegado SE EJECUTA y aplica el dominio ─────────────────
with scope as (
  select need.tenant_id from public.supply_needs need
  order by need.created_at desc limit 1
), brand as (
  select brand.id from public.product_brands brand, scope
  where brand.is_active is true
    and (brand.tenant_id is null or brand.tenant_id = scope.tenant_id)
  order by brand.id limit 1
), applied as (
  select public.normalize_commercial_target_internal_v1(
    scope.tenant_id, '{}'::jsonb,
    jsonb_build_object(
      'gama', 'alta',
      'preferredBrandId', brand.id::text,
      'maxLandedUnitCostNet', 12000,
      'minGrossMarginRatio', 0.35)
  ) as target, brand.id as expected_brand
  from scope, brand
)
select
  1 / (case when (target ->> 'gama') = 'alta'
              and (target ->> 'preferredBrandId')::uuid = expected_brand
              and (target ->> 'maxLandedUnitCostNet')::numeric = 12000
              and (target ->> 'minGrossMarginRatio')::numeric = 0.35
        then 1 else 0 end) as delegated_owner_applies_the_target,
  -- La tarjeta que este borrador produce tiene que ser aceptable para la base:
  -- un borrador que la interfaz muestra y la persistencia rechaza es el
  -- defecto que la fase A ya cobró una vez.
  1 / (case when public.assistant_cards_valid_v1(
        jsonb_build_array(jsonb_build_object(
          'kind','supply_need_draft','eyebrow','Peticion estructurada',
          'title','1 necesidad para revisar','description','Revisa antes de guardar.',
          'destination','purchases','chips', jsonb_build_array('Equilibrio'),
          'supplyNeedDraft', jsonb_build_object('profile','balanced',
            'lines', jsonb_build_array(jsonb_build_object(
              'lineRef','line-1','description','cadena 9 velocidades',
              'productId', null,'productName', null,'productSku', null,
              'identityState','unresolved','quantity', 2,'unit','unidad',
              'technicalPredicates','[]'::jsonb,'preference', null,
              'clarification', null,'clarificationRequired', false,
              'commercialTarget', target)))
        ))) then 1 else 0 end) as the_produced_target_is_persistable
from applied;

-- ── 4. La moneda sigue sin ser representable ────────────────────────────
select 1 / (case when pg_get_functiondef(
  'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)'::regprocedure
) like '%La moneda del objetivo comercial la fija el servidor.%'
  then 1 else 0 end) as currency_stays_server_owned;

-- ── 5. Un objetivo vacío no pasa como objetivo ──────────────────────────
select 1 / (case when pg_get_functiondef(
  'public.assistant_prepare_supply_request_v3(jsonb,text)'::regprocedure
) like '%Empty commercial target%' then 1 else 0 end) as empty_target_is_rejected;
