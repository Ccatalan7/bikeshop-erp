-- Read-back: la negación amarra el booleano y afirmar no estrecha de más.
with t as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid
), niega as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motores que no traen eje'
  ) r from t
), sin_eje as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motor sin eje'
  ) r from t
), medida as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
)
select
  1 / (case when (select r -> 'predicates' from niega)
    @> '[{"field":"includes_spindle","operator":"eq","values":[false]}]'::jsonb
    then 1 else 0 end) as niega_amarra,
  1 / (case when (select r -> 'predicates' from sin_eje)
    @> '[{"field":"includes_spindle","operator":"eq","values":[false]}]'::jsonb
    then 1 else 0 end) as sin_eje_amarra,
  -- Una frase que sólo habla de la medida no toca el booleano.
  1 / (case when (select r ->> 'predicates' from medida) not like '%includes_spindle%'
    then 1 else 0 end) as medida_no_lo_toca,
  1 / (case when jsonb_array_length((select r -> 'predicates' from medida)) = 3
    then 1 else 0 end) as pedalier_intacto,
  -- Y «no» y «traen» no quedan como texto libre exigiendo aparecer en el nombre.
  1 / (case when (select r ->> 'residual' from niega) not like '%no%'
    then 1 else 0 end) as sin_residuo_de_negacion;
