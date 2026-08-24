-- Falla si la función vuelve a numerar todo el conjunto para poder contar, o
-- si pierde el total. `count(*) over ()` fue lo que la llevó a 5.003 ms.
select 1 / (case when
  definicion not like '%over ()%'
  and definicion like '%limit p_limit%'
  and definicion like '%select count(*) from matched%'
  and definicion like '%v_total > p_limit, v_total%'
then 1 else 0 end) as corta_temprano_y_cuenta_aparte
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'assistant_find_inventory_risks_v1'
) fn;
