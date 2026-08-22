-- Read-back de 20260821210000_backfill_diagnosis_facts.sql

select subject_type, count(*) as hechos,
  count(distinct subject_scope) as sistemas
from public.spec_facts group by 1 order by 1;

select d.key, f.subject_scope, count(*)
from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id
where f.subject_type = 'job_bike' group by 1,2 order by 3 desc limit 8;

select
  -- Los hallazgos entraron con su sistema, no aplastados en uno solo.
  1 / (case when (select count(distinct subject_scope) from public.spec_facts
        where subject_type = 'job_bike') >= 6
      then 1 else 0 end) as afirma_sistemas_preservados,

  -- El alcance lleva sistema Y pieza: `front_wheel/rim` y `front_wheel/tire`
  -- son dos hechos de la misma condicion sobre piezas distintas. Sin eso, tres
  -- de cada cuatro hallazgos de una rueda se perderian.
  1 / (case when (
        select count(*) from public.spec_facts f
        join public.spec_definitions d on d.id = f.spec_definition_id
        where d.key = 'component_condition' and f.subject_type = 'job_bike'
          and f.subject_scope like 'front_wheel/%') >= 2
      then 1 else 0 end) as afirma_alcance_con_pieza,

  -- Y el mismo campo convive en dos sistemas: desgaste de pastilla adelante y
  -- atras, sin duplicar el campo.
  1 / (case when (
        select count(distinct f.subject_scope) from public.spec_facts f
        join public.spec_definitions d on d.id = f.spec_definition_id
        where d.key = 'wear_percent' and f.subject_type = 'job_bike') >= 2
      then 1 else 0 end) as afirma_mismo_campo_dos_sistemas,

  -- Los cuatro estados de cable que faltaban se rescataron en vez de perderse.
  1 / (case when (
        select count(*) from public.spec_facts f
        join public.spec_fact_values fv on fv.fact_id = f.id
        join public.spec_definition_values sv on sv.id = fv.value_id
        where sv.code in ('high_friction','housing_damaged')) = 4
      then 1 else 0 end) as afirma_estados_de_cable_rescatados,

  -- Ningun valor de lista quedo sin resolver: el codigo del blob es el mismo
  -- del registro, por eso calzan sin traducir.
  1 / (case when (
        select count(*) from public.spec_facts f
        join public.spec_definitions d on d.id = f.spec_definition_id
        where f.subject_type = 'job_bike' and d.data_type = 'single_select'
          and not exists (select 1 from public.spec_fact_values fv
            where fv.fact_id = f.id)) = 0
      then 1 else 0 end) as afirma_todo_resuelto,

  -- Y los tres sujetos conviven en la misma tabla, que era el punto.
  1 / (case when (select count(distinct subject_type) from public.spec_facts) = 3
      then 1 else 0 end) as afirma_tres_sujetos_conviviendo;
