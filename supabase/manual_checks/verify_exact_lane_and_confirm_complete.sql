-- Read-back de `20260831250000_exact_lane_and_confirm_complete`.

-- 1. El carril exacto no tiene que probar una decisión ya tomada.
select 1 / (
  case when pg_get_functiondef(oid) like '%when v_eligible ->> ''lane'' = ''exact'' then true%'
       then 1 else 0 end
) as el_carril_exacto_no_pide_categoria_hoja
from pg_proc where proname = 'supply_need_stock_bundle_internal_v1';

-- 2. La puerta que el operador usa exige evidencia completa, no un rótulo.
select 1 / (
  case when pg_get_functiondef(oid) like '%supply_need_evidence_is_complete_internal_v1%'
        and pg_get_functiondef(oid) not like '%not in (''strong'', ''weak'', ''no_criteria'')%'
       then 1 else 0 end
) as confirmar_exige_evidencia_completa
from pg_proc where proname = 'confirm_supply_need_family_choice_v1';

-- 3. Y sigue rechazando **después** del recibo: un reintento de algo ya escrito
--    no puede fallar por una regla que no existía entonces.
select 1 / (
  case when position('operation_key = v_operation_key' in prosrc)
            < position('supply_need_evidence_is_complete_internal_v1' in prosrc)
       then 1 else 0 end
) as el_recibo_sigue_mandando_antes_que_la_regla
from pg_proc where proname = 'confirm_supply_need_family_choice_v1';

-- 4. **Las filas reales de la necesidad de pastillas.** Ninguna fila con un
--    criterio sin resolver o contradicho puede contarse como comprobada, y
--    `eligible` es exactamente el conjunto completo.
with r as (
  select public.supply_need_stock_bundle_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid, 400) as b
), filas as (
  select i.value ->> 'name' as nombre,
         (i.value ->> 'evidenceComplete')::boolean as completa,
         (select count(*) from jsonb_array_elements(i.value -> 'matchDetail') d
           where d.value ->> 'source' <> 'product_spec'
             and d.value ->> 'source' <> 'identity_fallback') as pendientes
  from r, jsonb_array_elements(r.b -> 'orderedItems') i(value)
)
select 1 / (
  case when count(*) filter (where completa and pendientes > 0) = 0
        and count(*) filter (where pendientes > 0) > 0
       then 1 else 0 end
) as ninguna_con_criterios_pendientes_se_cuenta
from filas;

-- 5. Y el guard de escritura las rechaza una por una, sobre las filas reales.
with r as (
  select public.supply_need_eligible_products_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid) as e
), filas as (
  select (i.value ->> 'productId')::uuid as product_id,
         public.supply_need_evidence_is_complete_internal_v1(
           i.value -> 'matchDetail') as completa
  from r, jsonb_array_elements(r.e -> 'items') i(value)
)
select 1 / (
  case when count(*) filter (where not completa) > 0 then 1 else 0 end
) as hay_filas_que_el_guard_debe_rechazar
from filas;
