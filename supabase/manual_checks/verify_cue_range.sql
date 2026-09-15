-- Read-back: un SKU deja de amarrarse como medida, y las medidas reales siguen.
with t as (select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid),
 sku as (select public.assistant_infer_technical_predicates_internal_v1(
   t.tid, 'cubeta NAKASAWA 10561') r from t),
 pedalier as (select public.assistant_infer_technical_predicates_internal_v1(
   t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118') r from t)
select
  1 / (case when (select r ->> 'predicates' from sku) not like '%10561%'
    then 1 else 0 end) as sku_no_es_medida,
  -- Y vuelve al texto, que es donde encuentra el producto.
  1 / (case when (select r ->> 'residual' from sku) like '%10561%'
    then 1 else 0 end) as sku_queda_en_el_texto,
  1 / (case when jsonb_array_length((select r -> 'predicates' from pedalier)) = 3
    then 1 else 0 end) as medidas_reales_intactas;
