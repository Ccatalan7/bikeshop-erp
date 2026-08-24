-- Falla si el buscador pierde la demanda, o si «sold_recently» deja de ser
-- filtrable/ordenable. Comprueba además que el dato exista de verdad: si nadie
-- se movió en 90 días, la respuesta a «stock muerto» sería todo el catálogo.
select 1 / (case when
  definicion like '%soldRecently%'
  and definicion like '%''sold_recently''%'
  and definicion like '%recent_demand%'
  and (select count(distinct (item ->> 'product_id')::uuid)
       from public.sales_invoices invoice
         cross join lateral jsonb_array_elements(invoice.items) item
       where invoice.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and invoice.voided_at is null
         and invoice.date >= current_date - 90
         and jsonb_typeof(invoice.items) = 'array'
         and (item ->> 'product_id') ~ '^[0-9a-f-]{36}$') > 50
then 1 else 0 end) as el_buscador_sabe_que_se_movio
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'assistant_search_inventory_v7'
) fn;
