-- Falla si el buscador deja de exponer costo y margen, o si el margen deja de
-- calcularse sobre los datos reales del taller.
select 1 / (case when
  definicion like '%''cost'', cost,%'
  and definicion like '%''marginPercent''%'
  and definicion like '%''margin''%'
  and (select count(*) from public.products
       where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and is_active and coalesce(price,0) > 0 and cost is not null) > 500
then 1 else 0 end) as el_buscador_sabe_el_margen
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assistant_search_inventory_v7'
) fn;
