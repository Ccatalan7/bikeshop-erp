-- Read-back de 20260821200000_diagnosis_joins_the_registry.sql

select d.key, d.label, jsonb_array_length(d.allowed_values) as valores
from public.spec_definitions d
where d.tenant_id is null and d.group_name = 'Diagnóstico' order by d.sort_order;

select
  -- Los siete campos compartidos del diagnostico existen.
  1 / (case when (select count(*) from public.spec_definitions
        where tenant_id is null and group_name = 'Diagnóstico') = 7
      then 1 else 0 end) as afirma_campos_de_diagnostico,

  -- El sistema es parte del sujeto: sin eso habria que duplicar cada campo
  -- por delantero y trasero, que es la duplicacion que esto viene a matar.
  1 / (case when (select count(*) from information_schema.columns
        where table_name = 'spec_facts' and column_name = 'subject_scope') = 1
      then 1 else 0 end) as afirma_subject_scope,

  -- Y la unicidad lo considera: desgaste adelante y atras son DOS hechos.
  1 / (case when (select indexdef from pg_indexes
        where indexname = 'spec_facts_subject_definition') like '%subject_scope%'
      then 1 else 0 end) as afirma_unicidad_por_sistema,

  -- Una condicion cubre los doce estados que los datos ya usan, en vez de un
  -- vocabulario suelto por campo.
  1 / (case when (select jsonb_array_length(allowed_values)
        from public.spec_definitions
        where key = 'component_condition' and tenant_id is null) = 12
      then 1 else 0 end) as afirma_condicion_compartida,

  -- Su vocabulario tiene fila propia y etiqueta en castellano.
  1 / (case when (select sv.label from public.spec_definition_values sv
        join public.spec_definitions d on d.id = sv.spec_definition_id
        where d.key = 'component_condition' and sv.code = 'replace')
        = 'Hay que cambiarlo'
      then 1 else 0 end) as afirma_etiquetas_en_castellano,

  -- Y el codigo es el que los datos ya traen, no uno nuevo: por eso el
  -- backfill del blob va a calzar sin traducir.
  1 / (case when exists (
        select 1 from public.spec_definition_values sv
        join public.spec_definitions d on d.id = sv.spec_definition_id
        where d.key = 'overall_status' and sv.code = 'attention')
      then 1 else 0 end) as afirma_codigos_que_ya_usan_los_datos;
