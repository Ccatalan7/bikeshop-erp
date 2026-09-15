-- Falla si un costo cero vuelve a contarse como margen completo.
select 1 / (case when
  definicion like '%coalesce(cost, 0) > 0%'
  and definicion not like '%and cost is not null%'
  -- Y que el caso exista de verdad en el taller: si no hubiera costos en cero
  -- esta guarda no probaría nada.
  and (select count(*) from public.products
       where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and is_active and cost = 0) > 0
then 1 else 0 end) as costo_cero_no_es_margen_lleno
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assistant_search_inventory_v7'
) fn;
