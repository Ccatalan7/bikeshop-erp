-- Read-back: la palabra del rótulo deja de imponer un valor.
with t as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid
), ancho as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motor caja 73'
  ) r from t
), pedalier as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
), rotor as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'discos de freno de 160'
  ) r from t
)
select
  -- «caja 73» ya no inventa un estándar; sólo amarra el ancho.
  1 / (case when (select r ->> 'predicates' from ancho) not like '%bb_shell_standard%'
    then 1 else 0 end) as sin_estandar_supuesto,
  1 / (case when (select r -> 'predicates' from ancho)
    @> '[{"field":"bb_shell_width_mm","operator":"eq","values":[73]}]'::jsonb
    then 1 else 0 end) as ancho_amarrado,
  -- Con «BSA» dicho de verdad, el estándar vuelve: gana el campo con datos.
  1 / (case when (select r ->> 'predicates' from pedalier) like '%bb_shell_standard%'
    then 1 else 0 end) as bsa_dicho_si_amarra,
  1 / (case when jsonb_array_length((select r -> 'predicates' from pedalier)) = 3
    then 1 else 0 end) as pedalier_tres_campos,
  -- Y el número que es opción de lista sigue funcionando.
  1 / (case when (select r ->> 'predicates' from rotor) like '%rotor_diameter_mm%'
    then 1 else 0 end) as rotor_intacto;
