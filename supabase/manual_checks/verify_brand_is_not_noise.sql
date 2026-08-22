-- Read-back: la marca sobrevive; la palabra que nombra un campo no.
with t as (select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid),
 marca as (select public.assistant_infer_technical_predicates_internal_v1(
   t.tid, 'que motores shimano tengo en stock') r from t),
 pedalier as (select public.assistant_infer_technical_predicates_internal_v1(
   t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118') r from t)
select
  1 / (case when (select r ->> 'residual' from marca) like '%shimano%'
    then 1 else 0 end) as marca_sobrevive,
  -- «caja», «ancho» y «largo» nombran campos: siguen sin llegar al texto.
  1 / (case when (select r ->> 'residual' from pedalier) = ''
    then 1 else 0 end) as rotulos_siguen_consumidos,
  1 / (case when jsonb_array_length((select r -> 'predicates' from pedalier)) = 3
    then 1 else 0 end) as pedalier_intacto;
