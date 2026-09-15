-- Falla si la búsqueda de facturas vuelve a exigir un término, o si el listado
-- sin filtro deja de devolver algo con los datos reales del taller.
select 1 / (case when
  definicion not like '%not between 1 and 240%'
  and definicion like '%nullif(v_query, '''') is null%'
  and (select count(*) from public.sales_invoices
       where tenant_id = '5443b130-cc28-45af-a420-cd500b288890') > 0
then 1 else 0 end) as lista_sin_termino
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assistant_search_sales_invoices_v1'
) fn;
