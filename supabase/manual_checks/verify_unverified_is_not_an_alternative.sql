-- Read-back de `20260831180000_unverified_is_not_an_alternative`.

-- 1. El contrato publica las dos cifras, y son cosas distintas.
select 1 / (
  case when pg_get_functiondef(oid) like '%''reviewed'', v_total%'
        and pg_get_functiondef(oid) like '%''eligible'', v_eligible_count%'
       then 1 else 0 end
) as elegible_y_revisado_son_dos_cifras
from pg_proc where proname = 'supply_need_stock_bundle_internal_v1';

-- 2. La cobertura ya no puede contar lo no verificado.
select 1 / (
  case when pg_get_functiondef(oid) not like '%filter (where coverage = ''full'')%'
       then 1 else 0 end
) as la_cobertura_no_cuenta_lo_no_verificado
from pg_proc where proname = 'supply_need_stock_bundle_internal_v1';

-- 3. **Sobre necesidades abiertas reales, en una sola pasada.** El juicio se
--    evalúa UNA vez por necesidad —repetirlo por assert no cabía en el tope de
--    lectura— y de ahí salen las tres invariantes. Se acota a las diez más
--    recientes con categoría: deterministas y suficientes, y se dice.
with abiertas as (
  select n.id, n.tenant_id
  from public.supply_needs n
  where n.supply_state = 'open'
  order by n.created_at desc
  limit 10
), juicio as (
  select a.id,
    public.supply_need_stock_bundle_internal_v1(a.tenant_id, a.id, 400) as r
  from abiertas a
), desglose as (
  select j.id,
    (j.r #>> '{counts,eligible}')::int as elegible,
    (j.r #>> '{counts,reviewed}')::int as revisado,
    (j.r #>> '{counts,unverified}')::int as sin_verificar,
    j.r ->> 'coverage' as cobertura,
    (select count(*)::int from jsonb_array_elements(j.r -> 'orderedItems') i
      where i.value ->> 'matchState' <> 'unverified') as comprobadas,
    (select count(*)::int from jsonb_array_elements(j.r -> 'orderedItems') i
      where i.value ->> 'matchState' <> 'unverified'
        and i.value ->> 'coverage' <> 'none') as comprobadas_con_stock
  from juicio j
)
select 1 / (
  case when count(*) filter (
    where elegible is distinct from comprobadas
       or revisado is distinct from (elegible + sin_verificar)
       or (cobertura <> 'none' and comprobadas_con_stock = 0)
  ) = 0 and count(*) > 0 then 1 else 0 end
) as elegible_es_lo_comprobado_y_la_cobertura_tambien
from desglose;
