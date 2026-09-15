-- Read-back: los predicados salen ordenados por respaldo y el buscador suelta.
with t as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid
), duenio as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid,
    'Necesito un motor para una caja inglesa de 68 mm con eje cuadrado de 118 mm. Que tengo en bodega?'
  ) r from t
), pedalier as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
)
select
  -- Los cuatro filtros se siguen deduciendo.
  1 / (case when jsonb_array_length((select r -> 'predicates' from duenio)) = 4
    then 1 else 0 end) as cuatro_filtros,
  -- El campo con menos ficha queda último, que es el primero en soltarse.
  1 / (case when (select r -> 'predicates' -> -1 ->> 'field' from duenio)
    = 'spindle_interface_accepted' then 1 else 0 end) as el_debil_va_al_final,
  -- El buscador sabe soltar.
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%v_relaxations%'
  ) then 1 else 0 end) as buscador_relaja,
  -- Y la frase que ya funcionaba no cambia.
  1 / (case when jsonb_array_length((select r -> 'predicates' from pedalier)) = 3
    then 1 else 0 end) as pedalier_intacto;
