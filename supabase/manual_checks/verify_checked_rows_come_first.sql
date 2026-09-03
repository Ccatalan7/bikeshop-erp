-- Read-back de `20260831230000_checked_rows_come_first`.

-- 1. El grupo de evidencia es la PRIMERA clave del orden.
select 1 / (
  case when position(
         'when covered.match_state in (''strong'', ''weak'', ''no_criteria'')'
         in prosrc) < position('case covered.coverage' in prosrc)
       then 1 else 0 end
) as la_evidencia_ordena_antes_que_el_stock
from pg_proc where proname = 'supply_need_stock_bundle_internal_v1';

-- 2. **Sobre las necesidades abiertas reales**: ninguna fila sin verificar
--    puede quedar antes de una comprobada. Es la invariante que la paginación
--    necesita para no partir el grupo.
with abiertas as (
  select n.id, n.tenant_id
  from public.supply_needs n
  where n.supply_state = 'open'
  order by n.created_at desc
  limit 10
), filas as (
  select a.id as need_id,
    (i.value ->> 'ordinal')::int as ordinal,
    (i.value ->> 'matchState') in ('strong', 'weak', 'no_criteria') as comprobada
  from abiertas a,
    lateral jsonb_array_elements(
      public.supply_need_stock_bundle_internal_v1(a.tenant_id, a.id, 400)
        -> 'orderedItems') i(value)
)
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as ninguna_sin_verificar_adelanta_a_una_comprobada
from filas comprobada
join filas sin_verificar
  on sin_verificar.need_id = comprobada.need_id
where comprobada.comprobada
  and not sin_verificar.comprobada
  and sin_verificar.ordinal < comprobada.ordinal;

-- 3. Y en la necesidad real de pastillas, las dos comprobadas encabezan.
with r as (
  select public.supply_need_stock_bundle_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid, 400) as b
)
select 1 / (
  case when count(*) filter (
    where (i.value ->> 'matchState') in ('strong', 'weak', 'no_criteria')
      and (i.value ->> 'ordinal')::int <= 2
  ) = 2 then 1 else 0 end
) as las_dos_comprobadas_encabezan
from r, jsonb_array_elements(r.b -> 'orderedItems') i(value);
