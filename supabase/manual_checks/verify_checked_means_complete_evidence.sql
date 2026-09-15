-- Read-back de `20260831240000_checked_means_complete_evidence`.

-- 1. La completitud es una función propia, inmutable y no expuesta.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_completitud_tiene_dueno
from pg_proc
where proname = 'supply_need_evidence_is_complete_internal_v1'
  and provolatile = 'i';

-- 2. Decide sobre la evidencia entera: un criterio sin resolver no completa.
select 1 / (
  case when public.supply_need_evidence_is_complete_internal_v1(
         '[{"field":"a","source":"product_spec"},
           {"field":"b","source":"unresolved"}]'::jsonb) is false
        and public.supply_need_evidence_is_complete_internal_v1(
         '[{"field":"a","source":"product_spec"},
           {"field":"b","source":"identity_fallback"}]'::jsonb) is true
        and public.supply_need_evidence_is_complete_internal_v1(
         '[]'::jsonb) is false
       then 1 else 0 end
) as un_criterio_sin_resolver_no_completa;

-- 3. Los contadores y el bloqueo salen de la completitud, no del rótulo.
select 1 / (
  case when pg_get_functiondef(oid) like '%filter (where coverage = ''full'' and evidence_complete)%'
        and pg_get_functiondef(oid) like '%covered.evidence_complete%'
        and pg_get_functiondef(oid) not like '%match_state in (''strong'', ''weak'', ''no_criteria'')%'
       then 1 else 0 end
) as el_contrato_cuenta_completitud
from pg_proc where proname = 'supply_need_stock_bundle_internal_v1';

-- 4. **Sobre la necesidad real de pastillas**: las dos filas que antes contaban
--    como comprobadas tienen dos criterios sin resolver, así que ya no cuentan;
--    y ninguna fila con evidencia incompleta entra en `eligible`.
with r as (
  select public.supply_need_stock_bundle_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid, 400) as b
), filas as (
  select (i.value ->> 'matchState') as estado,
         (i.value ->> 'evidenceComplete')::boolean as completa,
         (select count(*) from jsonb_array_elements(i.value -> 'matchDetail') d
           where d.value ->> 'source' = 'unresolved') as sin_resolver
  from r, jsonb_array_elements(r.b -> 'orderedItems') i(value)
)
select 1 / (
  case when count(*) filter (where completa and sin_resolver > 0) = 0
        and count(*) filter (where estado = 'weak' and sin_resolver > 0) > 0
       then 1 else 0 end
) as lo_incompleto_ya_no_cuenta_como_comprobado
from filas;

select 1 / (
  case when (r.b #>> '{counts,eligible}')::int
            = (select count(*) from jsonb_array_elements(r.b -> 'orderedItems') i
               where (i.value ->> 'evidenceComplete')::boolean)
       then 1 else 0 end
) as elegible_es_exactamente_lo_completo
from (
  select public.supply_need_stock_bundle_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid, 400) as b
) r;
