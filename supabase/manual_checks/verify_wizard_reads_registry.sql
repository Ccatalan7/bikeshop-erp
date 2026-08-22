-- Read-back de 20260821270000_wizard_reads_the_registry.sql

select key, options_from_registry,
  left(options_json::text, 90) as opciones
from public.service_profile_questions_resolved_v1
where key in ('bottom_bracket_family','spindle_interface','replace_unit','symptom')
order by options_from_registry desc, key limit 6;

select
  -- La vista existe y la app puede leerla.
  1 / (case when (select count(*) from information_schema.views
        where table_schema = 'public'
          and table_name = 'service_profile_questions_resolved_v1') = 1
      then 1 else 0 end) as afirma_vista_creada,

  1 / (case when has_table_privilege('authenticated',
        'public.service_profile_questions_resolved_v1', 'select')
      then 1 else 0 end) as afirma_legible_por_la_app,

  -- Las preguntas que corresponden a un campo de ficha beben del registro.
  1 / (case when (select count(*) from public.service_profile_questions_resolved_v1
        where options_from_registry) > 0
      then 1 else 0 end) as afirma_preguntas_desde_el_registro,

  -- Y las propias de la visita conservan sus opciones: el sintoma no es una
  -- caracteristica de la pieza y no tiene por que estar en el registro.
  1 / (case when (select count(*) from public.service_profile_questions_resolved_v1
        where not options_from_registry
          and options_json <> '[]'::jsonb) > 0
      then 1 else 0 end) as afirma_preguntas_de_visita_intactas,

  -- Ninguna pregunta se quedo sin opciones al cambiar de fuente.
  1 / (case when (select count(*) from public.service_profile_questions q
        join public.service_profile_questions_resolved_v1 r on r.id = q.id
        where q.options_json <> '[]'::jsonb
          and r.options_json = '[]'::jsonb) = 0
      then 1 else 0 end) as afirma_ninguna_perdio_opciones,

  -- La vista respeta el aislamiento por tenant de la tabla base.
  1 / (case when (select count(*) from pg_class
        where relname = 'service_profile_questions_resolved_v1'
          and reloptions::text like '%security_invoker=true%') = 1
      then 1 else 0 end) as afirma_aislamiento;
