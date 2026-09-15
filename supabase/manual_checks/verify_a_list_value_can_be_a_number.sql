-- Read-back: un número que es opción de lista se reconoce como tal.
with t as (
  select tenant_id tid from public.product_categories
  where public.assistant_normalize_query_internal_v1(full_path)
    = 'componentes transmision motores' limit 1
), rotor as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'discos de freno de 160'
  ) r from t
), rueda as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'ruedas rodado 29'
  ) r from t
), motor as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
)
select
  1 / (case when (select r -> 'predicates' from rotor)
    @> '[{"field":"rotor_diameter_mm","operator":"in","values":["160"]}]'::jsonb
    then 1 else 0 end) as rotor_160,
  -- El rótulo trae comilla —29"— y aun así calza con el token 29.
  1 / (case when (select r ->> 'predicates' from rueda) like '%wheel_size%'
    then 1 else 0 end) as rodado_29,
  -- «160» no se lleva «160/140»: se compara por igualdad, no por fragmento.
  1 / (case when (select r ->> 'predicates' from rotor) not like '%160/140%'
    then 1 else 0 end) as sin_arrastrar_dobles,
  -- Y la cascada de pedalier sigue igual que antes.
  1 / (case when jsonb_array_length((select r -> 'predicates' from motor)) = 3
    then 1 else 0 end) as pedalier_intacto;
