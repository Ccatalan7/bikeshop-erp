-- Falla si el reparto del tope se rompe: 37 del catálogo más los 3 campos
-- operativos fijos tienen que caber en los 40 que acepta el ejecutor.
-- (La RPC no se puede invocar desde aquí: exige identidad de asistente. El
-- comportamiento se comprueba con la llamada real en la app.)
select 1 / (case when
  definicion like '%ordinal <= 37%'
  and definicion like '%v_total > 37%'
  and definicion not like '%ordinal <= 40%'
  and (length(definicion) - length(replace(definicion, '''operational_field''', ''))) / length('''operational_field''') = 3
then 1 else 0 end) as el_tope_se_reparte
from (
  select pg_get_functiondef(p.oid) definicion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'assistant_inspect_inventory_schema_v3'
) fn;
