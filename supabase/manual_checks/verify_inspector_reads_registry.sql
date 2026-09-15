-- Read-back de 20260821240000_assistant_inspector_reads_registry.sql

select proname,
  (pg_get_functiondef(oid) like '%spec_facts%') as lee_hechos,
  (pg_get_functiondef(oid) like '%spec_definition_values%') as lee_vocabulario,
  (pg_get_functiondef(oid) like '%join public.product_spec_values%') as lee_tabla_vieja
from pg_proc where proname = 'assistant_inspect_inventory_schema_v3';

select
  -- La cobertura sale del registro, no de la tabla vieja.
  1 / (case when (select count(*) from pg_proc
        where proname = 'assistant_inspect_inventory_schema_v3'
          and pg_get_functiondef(oid) like '%spec_facts%'
          -- Se busca el JOIN, no la palabra: el comentario de la migracion
          -- la nombra para explicar de donde viene.
          and pg_get_functiondef(oid) not like '%join public.product_spec_values%') = 1
      then 1 else 0 end) as afirma_cobertura_desde_el_registro,

  -- Y el vocabulario tambien: una etiqueta renombrada llega al asistente sin
  -- reescribir la definicion.
  1 / (case when (select count(*) from pg_proc
        where proname = 'assistant_inspect_inventory_schema_v3'
          and pg_get_functiondef(oid) like '%spec_definition_values%') = 1
      then 1 else 0 end) as afirma_vocabulario_desde_el_registro,

  -- El respaldo a allowed_values se queda: hay campos que aun no estan en el
  -- registro y el inspector no puede quedarse mudo para esos.
  1 / (case when (select count(*) from pg_proc
        where proname = 'assistant_inspect_inventory_schema_v3'
          and pg_get_functiondef(oid) like '%definition.allowed_values::text%') = 1
      then 1 else 0 end) as afirma_respaldo_conservado,

  -- La firma no cambio: el gateway desplegado la sigue llamando igual.
  1 / (case when (select pg_get_function_identity_arguments(oid) from pg_proc
        where proname = 'assistant_inspect_inventory_schema_v3')
        = 'p_query text, p_category text'
      then 1 else 0 end) as afirma_firma_intacta,

  -- Y la cobertura sigue cuadrando con la realidad: los 34 motores tienen su
  -- construccion, que es lo que el asistente usa para filtrar.
  1 / (case when (select count(distinct subject_id) from public.spec_facts f
        join public.spec_definitions d on d.id = f.spec_definition_id
        where d.key = 'bb_construction' and f.subject_type = 'product') = 48
      then 1 else 0 end) as afirma_cobertura_real;
