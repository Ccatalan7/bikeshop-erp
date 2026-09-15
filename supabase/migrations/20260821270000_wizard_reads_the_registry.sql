-- Fase 10, último lector: el wizard bebe del mismo registro.
--
-- `service_profile_questions.options_json` era la única de las cuatro formas
-- que ya separaba código y etiqueta — `{"label":"Cuadrado JIS","value":
-- "square_jis"}` —, y de hecho fue de ahí que se cosecharon 192 de los códigos
-- del registro. Lo que le falta no es forma, es fuente: su etiqueta es una
-- copia, así que renombrar un valor no le llega.
--
-- Una vista resuelve las opciones desde `spec_definition_values` cuando la
-- pregunta corresponde a un campo del registro, y conserva `options_json` para
-- las preguntas que son propias del wizard y no tienen campo — el síntoma
-- principal, «¿reemplazar unidad?», y las demás que no describen la pieza sino
-- la visita.
--
-- Con esto los seis lectores quedan bebiendo del mismo vocabulario y un
-- renombre llega a la ficha, a la tienda, al asistente, al scorer y al wizard
-- con un solo `update`.

begin;

create or replace view public.service_profile_questions_resolved_v1
with (security_invoker = true) as
select
  q.id, q.tenant_id, q.service_profile_id, q.key, q.label,
  q.question_type, q.is_required, q.is_advanced, q.sort_order,
  q.visibility_rules, q.default_answer_json, q.created_at, q.updated_at,
  coalesce(
    (
      select jsonb_agg(
        jsonb_build_object('value', sv.code, 'label', sv.label)
        order by sv.sort_order
      )
      from public.spec_definition_values sv
      join public.spec_definitions d on d.id = sv.spec_definition_id
      where d.key = q.key and d.tenant_id is null and sv.is_active
    ),
    q.options_json
  ) as options_json,
  -- Para saber, desde fuera, cuáles preguntas ya viven del registro y cuáles
  -- siguen siendo propias del wizard.
  exists (
    select 1 from public.spec_definitions d
    where d.key = q.key and d.tenant_id is null
      and jsonb_array_length(d.allowed_values) > 0
  ) as options_from_registry
from public.service_profile_questions q;

comment on view public.service_profile_questions_resolved_v1 is
  'Las preguntas del wizard con sus opciones resueltas desde el registro '
  'cuando la pregunta corresponde a un campo de ficha. Las preguntas propias '
  'de la visita —síntoma, «¿reemplazar unidad?»— conservan su options_json.';

grant select on public.service_profile_questions_resolved_v1 to authenticated;

commit;
