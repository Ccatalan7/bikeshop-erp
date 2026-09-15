-- Falla si se pierde la valorización a costo o su cobertura.
select 1 / (case when
  definicion like '%inventoryCostValue%'
  and definicion like '%costedCount%'
  and definicion like '%tracks_inventory and coalesce(cost, 0) > 0%'
  and (select round(sum(coalesce(cost,0) * greatest(coalesce(stock_quantity,0),0)))
       from public.products
       where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and is_active and coalesce(track_stock,true)) > 0
then 1 else 0 end) as inventario_valorizado_a_costo
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assistant_search_inventory_v7'
) fn;
