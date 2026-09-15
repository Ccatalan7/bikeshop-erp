-- Read-back del objetivo comercial tipado (20260817210000).
-- Falla a nivel SQL si la migración no quedó instalada, o si quedó instalada
-- pero rota.
--
-- Lo que se exige: el flujo append-only con **un solo escritor**, la moneda
-- **server-owned** y no representable en la entrada, la semántica exacta de la
-- carga —ausente conserva, `null` limpia—, y el lote v3 con recibo propio,
-- clave interna impredecible y el límite público de 160 bytes intacto.
--
-- Los comandos escriben, así que en el camino de sólo-lectura se ejecutan el
-- normalizador y la lectura, y de los comandos se exige firma, ACL e
-- invariantes de forma.

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

-- ── 1. El flujo tiene su propia tabla, append-only y aislada ──────────────
select 1 / (case when to_regclass('public.supply_need_commercial_revisions')
  is not null then 1 else 0 end) as commercial_revisions_table_present;

-- Separada de las revisiones de interpretación a propósito: `update_supply_need_v1`
-- ya escribe `constraints '[]'` sin `category_id`, y una columna anulable ahí
-- la borraría en silencio el primer escritor que no la copie.
select 1 / (case when not exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supply_need_interpretation_revisions'
    and column_name in ('gama', 'preferred_brand_id',
      'max_landed_unit_cost_net', 'min_gross_margin_ratio')
) then 1 else 0 end) as commercial_fields_never_hang_off_interpretation;

select 1 / (case when relrowsecurity then 1 else 0 end) as commercial_rls_enabled
from pg_class where oid = 'public.supply_need_commercial_revisions'::regclass;

select 1 / (case when count(*) = 1 then 1 else 0 end) as commercial_select_policy
from pg_policy
where polrelid = 'public.supply_need_commercial_revisions'::regclass
  and polname = 'supply_need_commercial_revisions_select';

-- El cliente lee y nunca escribe: el único escritor es la función.
select 1 / (case when
     has_table_privilege('authenticated', 'public.supply_need_commercial_revisions', 'select')
 and not has_table_privilege('authenticated', 'public.supply_need_commercial_revisions', 'insert')
 and not has_table_privilege('authenticated', 'public.supply_need_commercial_revisions', 'update')
 and not has_table_privilege('authenticated', 'public.supply_need_commercial_revisions', 'delete')
 and not has_table_privilege('anon', 'public.supply_need_commercial_revisions', 'select')
  then 1 else 0 end) as commercial_table_acl;

-- Append-only con el mismo guardián que el resto de la evidencia del kernel.
select 1 / (case when exists (
  select 1 from pg_trigger
  where tgrelid = 'public.supply_need_commercial_revisions'::regclass
    and tgname = 'trg_supply_need_commercial_revisions_immutable'
    and not tgisinternal
) then 1 else 0 end) as commercial_revisions_are_append_only;

-- Una revisión dice algo: o fija una preferencia, o declara la limpieza.
-- `cleared` y los campos son mutuamente excluyentes en las dos direcciones.
select 1 / (case when count(*) >= 2 then 1 else 0 end) as cleared_is_coherent_both_ways
from pg_constraint
where conrelid = 'public.supply_need_commercial_revisions'::regclass
  and contype = 'c'
  and pg_get_constraintdef(oid) like '%cleared%';

-- ── 2. El ledger aprende los dos hechos, sin perder ninguno anterior ──────
select 1 / (case when
     pg_get_constraintdef(oid) like '%commercial_target_set%'
 and pg_get_constraintdef(oid) like '%commercial_target_cleared%'
 and pg_get_constraintdef(oid) like '%family_stock_rejected%'
 and pg_get_constraintdef(oid) like '%family_choice_confirmed%'
 and pg_get_constraintdef(oid) like '%internal_stock_rejected%'
 and pg_get_constraintdef(oid) like '%stock_assigned%'
 and pg_get_constraintdef(oid) like '%stock_released%'
 and pg_get_constraintdef(oid) like '%stock_reactivated%'
 and pg_get_constraintdef(oid) like '%purchase_planned%'
 and pg_get_constraintdef(oid) like '%received%'
 and pg_get_constraintdef(oid) like '%covered%'
  then 1 else 0 end) as event_actions_stayed_additive
from pg_constraint
where conrelid = 'public.supply_need_events'::regclass
  and conname = 'supply_need_events_action_check';

-- ── 3. Presencia, firma y ACL ─────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.tenant_commercial_currency_internal_v1(uuid)') is not null
 and to_regprocedure('public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)') is not null
 and to_regprocedure('public.supply_need_commercial_target_internal_v1(uuid,uuid)') is not null
 and to_regprocedure('public.get_supply_need_commercial_target_v1(uuid)') is not null
 and to_regprocedure('public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)') is not null
 and to_regprocedure('public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)') is not null
  then 1 else 0 end) as commercial_functions_present;

select 1 / (case when
     has_function_privilege('authenticated', 'public.get_supply_need_commercial_target_v1(uuid)', 'execute')
 and has_function_privilege('authenticated', 'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)', 'execute')
 and has_function_privilege('authenticated', 'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)', 'execute')
 and not has_function_privilege('anon', 'public.get_supply_need_commercial_target_v1(uuid)', 'execute')
 and not has_function_privilege('anon', 'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)', 'execute')
 and not has_function_privilege('anon', 'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)', 'execute')
 and not has_function_privilege('authenticated', 'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_need_commercial_target_internal_v1(uuid,uuid)', 'execute')
  then 1 else 0 end) as commercial_acl;

-- ── 4. La moneda del taller SE EJECUTA y es un código de tres letras ──────
select 1 / (case when public.tenant_commercial_currency_internal_v1(
    (select need.tenant_id from public.supply_needs need
      order by need.created_at desc limit 1)
  ) ~ '^[A-Z]{3}$' then 1 else 0 end) as tenant_currency_is_server_owned;

-- ── 5. El normalizador SE EJECUTA: ausente conserva, `null` limpia ────────
with scope as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), brand as (
  select brand.id
  from public.product_brands brand, scope
  where brand.is_active is true
    and (brand.tenant_id is null or brand.tenant_id = scope.tenant_id)
  order by brand.id
  limit 1
), applied as (
  select
    -- Fija las cuatro preferencias de una vez.
    public.normalize_commercial_target_internal_v1(
      scope.tenant_id, '{}'::jsonb,
      jsonb_build_object(
        'gama', 'alta',
        'preferredBrandId', brand.id::text,
        'maxLandedUnitCostNet', 12000,
        'minGrossMarginRatio', 0.35
      )
    ) as full_target,
    -- Clave ausente: conserva lo que ya había.
    public.normalize_commercial_target_internal_v1(
      scope.tenant_id,
      jsonb_build_object('gama', 'media', 'maxLandedUnitCostNet', 9000),
      jsonb_build_object('minGrossMarginRatio', 0.5)
    ) as preserved,
    -- Clave en `null`: limpia ese campo y sólo ese.
    public.normalize_commercial_target_internal_v1(
      scope.tenant_id,
      jsonb_build_object('gama', 'media', 'maxLandedUnitCostNet', 9000),
      jsonb_build_object('gama', null)
    ) as cleared_one,
    brand.id as expected_brand
  from scope, brand
)
select
  1 / (case when (full_target ->> 'gama') = 'alta'
              and (full_target ->> 'preferredBrandId')::uuid = expected_brand
              and (full_target ->> 'maxLandedUnitCostNet')::numeric = 12000
              and (full_target ->> 'minGrossMarginRatio')::numeric = 0.35
        then 1 else 0 end) as normalizer_applies_the_four_preferences,
  1 / (case when (preserved ->> 'gama') = 'media'
              and (preserved ->> 'maxLandedUnitCostNet')::numeric = 9000
              and (preserved ->> 'minGrossMarginRatio')::numeric = 0.5
        then 1 else 0 end) as absent_key_preserves,
  1 / (case when not (cleared_one ? 'gama')
              and (cleared_one ->> 'maxLandedUnitCostNet')::numeric = 9000
        then 1 else 0 end) as explicit_null_clears_only_that_field
from applied;

-- La moneda no es representable en la entrada, y una marca ajena o retirada se
-- **rechaza**, no se ignora.
select 1 / (case when pg_get_functiondef(
  'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)'::regprocedure
) like '%La moneda del objetivo comercial la fija el servidor.%'
  and pg_get_functiondef(
  'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)'::regprocedure
) like '%no está disponible para este taller%'
  and pg_get_functiondef(
  'public.normalize_commercial_target_internal_v1(uuid,jsonb,jsonb)'::regprocedure
) like '%Campo desconocido en el objetivo comercial%'
  then 1 else 0 end) as currency_brand_and_unknown_keys_are_rejected;

-- ── 6. La lectura pública SE EJECUTA y es autocontenida ───────────────────
with target as (
  select public.get_supply_need_commercial_target_v1(
    (select need.id from public.supply_needs need
      order by need.created_at desc limit 1)
  ) as payload
)
select
  1 / (case when jsonb_typeof(payload) = 'object' then 1 else 0 end)
    as commercial_read_executes,
  1 / (case when payload ?& array['needId','needVersion','needSupplyState',
        'currencyCode','tenantCurrencyCode','targetRevisionNo','target',
        'preferredBrandAvailable','legacyPreferenceNote']
        then 1 else 0 end) as commercial_read_envelope_is_complete,
  1 / (case when (select count(*) from jsonb_object_keys(payload)) = 9
        then 1 else 0 end) as commercial_read_has_no_extra_keys,
  -- El comando exige versión y estado: la lectura los trae.
  1 / (case when (payload ->> 'needVersion')::bigint >= 1
              and (payload ->> 'needSupplyState') is not null
        then 1 else 0 end) as read_carries_what_the_command_demands,
  -- Sin revisión, `targetRevisionNo = 0`: la ausencia se dice, y no es lo
  -- mismo que una limpieza explícita.
  1 / (case when (payload ->> 'targetRevisionNo')::bigint >= 0
        then 1 else 0 end) as absence_is_stated,
  1 / (case when (payload ->> 'currencyCode') ~ '^[A-Z]{3}$'
              and (payload ->> 'tenantCurrencyCode') ~ '^[A-Z]{3}$'
        then 1 else 0 end) as both_currencies_travel,
  1 / (case when jsonb_typeof(payload -> 'target') = 'object'
        then 1 else 0 end) as target_is_an_object
from target;

-- La moneda de la lectura es la de **su revisión**, nunca la de hoy: un taller
-- que pasa de CLP a USD no puede reinterpretar un tope guardado.
select 1 / (case when pg_get_functiondef(
  'public.supply_need_commercial_target_internal_v1(uuid,uuid)'::regprocedure
) like '%v_currency := v_revision.currency_code;%'
  then 1 else 0 end) as read_uses_its_revision_currency;

-- `commercial_preference` legado viaja como NOTA y no rankea.
select 1 / (case when pg_get_functiondef(
  'public.supply_need_commercial_target_internal_v1(uuid,uuid)'::regprocedure
) like '%''drivesRanking'', false%' then 1 else 0 end) as legacy_note_never_ranks;

-- ── 7. Invariantes de forma del comando ───────────────────────────────────
-- Concurrencia optimista doble: versión de la necesidad y revisión comercial.
select 1 / (case when pg_get_function_identity_arguments(
  'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
) = 'p_need_id uuid, p_expected_version bigint, p_expected_target_revision_no bigint, p_target jsonb, p_operation_key text'
  then 1 else 0 end) as command_is_doubly_optimistic;

-- El lock se toma ANTES de leer el recibo: dos peticiones idénticas
-- simultáneas ven `replay = true`, no un 40001 ni una violación cruda.
select 1 / (case when
  position('pg_advisory_xact_lock' in definition)
  < position('from public.supply_need_commercial_revisions' in definition)
  then 1 else 0 end) as lock_precedes_the_receipt_read
from (
  select pg_get_functiondef(
    'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
  ) as definition
) source;

-- Una re-denominación explícita con el mismo número NO es un no-op: el acto
-- cambia el significado, aunque el número coincida. Ningún número se convierte.
select 1 / (case when pg_get_functiondef(
  'public.set_supply_need_commercial_target_v1(uuid,bigint,bigint,jsonb,text)'::regprocedure
) like '%currency_code%' then 1 else 0 end) as command_owns_its_currency;

-- ── 8. `create_supply_need_batch_v3` ──────────────────────────────────────
-- Recibo propio en el MISMO espacio de nombres que v2: una clave usada por
-- cualquiera de los dos bloquea al otro.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%supply_need_batch_receipts%' then 1 else 0 end) as v3_owns_a_receipt;

-- El límite público se conserva en 160 bytes: las claves internas son de
-- tamaño fijo en vez de sufijos que obligarían a recortar el contrato.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%octet_length(v_operation_key) > 160%'
  and pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%v3-core:%'
  and pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%v3-target:%'
  then 1 else 0 end) as public_key_limit_is_preserved;

-- La semilla se genera DENTRO de la transacción y no se deriva de la clave
-- pública: `md5(tenant:clave)` era presembrable y habría dejado replayar
-- necesidades ajenas colgándoles objetivos nuevos.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%v_seed := gen_random_uuid();%'
  and pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) not like '%md5(v_tenant_id::text%'
  then 1 else 0 end) as internal_key_is_unseedable;

-- El objetivo se indexa por el `lineRef` real, no por posición: v2 acepta
-- `line-1..line-8` en cualquier orden.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%line_ref%' then 1 else 0 end) as targets_are_indexed_by_line_ref;

-- v3 delega TODAS las reglas en v2, que queda intacta.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v3(text,jsonb,text,uuid,text)'::regprocedure
) like '%create_supply_need_batch_v2%'
  and to_regprocedure('public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)') is not null
  then 1 else 0 end) as v3_delegates_to_v2;
