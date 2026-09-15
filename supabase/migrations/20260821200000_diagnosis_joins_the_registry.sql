-- Fase 5: el diagnóstico entra al registro compartido.
--
-- La ficha de diagnóstico guarda sus hallazgos como blob JSONB anidado por
-- sistema, con vocabularios sueltos: `ok`, `attention`, `replace`, `rough`,
-- `service` se repiten en ocho campos distintos y ninguno está declarado en
-- ninguna parte. Nadie puede saber qué valores admite `hub_bearing_condition`
-- sin leer los datos que ya existen.
--
-- Dos cosas que este cambio NO hace, a propósito:
--
--   * No convierte un hallazgo de visita en verdad durable. El diagnóstico
--     sigue siendo estado de la visita; lo que se unifica es el VOCABULARIO y
--     la forma de guardarlo, no su significado. La distinción entre lo que la
--     bici es y lo que se vio ese día es del backbone y se mantiene.
--   * No borra el blob. `diagnosis_sheet_data` sigue siendo lo que la app lee
--     hasta que se muevan los lectores.
--
-- El sistema —freno delantero, freno trasero, transmisión— pasa a ser parte
-- del SUJETO, no del campo. `pad_wear_percent` es el mismo campo en los dos
-- frenos; lo que cambia es de cuál se habla. Por eso `subject_scope`: sin él
-- habría que inventar `front_pad_wear_percent` y `rear_pad_wear_percent` y
-- duplicar cada campo por sistema, que es justo la clase de duplicación que
-- esta unificación viene a matar.

begin;

alter table public.spec_facts
  add column if not exists subject_scope text;

comment on column public.spec_facts.subject_scope is
  'Qué parte del sujeto: `front_brake`, `rear_brake`, `drivetrain`, '
  '`front_wheel`… Null cuando el hecho es del sujeto entero, que es el caso '
  'de un producto y de casi toda la ficha de una bici.';

-- La unicidad ahora considera el sistema: una bici en un trabajo puede tener
-- desgaste de pastilla adelante y atrás, y son dos hechos, no uno repetido.
drop index if exists public.spec_facts_subject_definition;
create unique index if not exists spec_facts_subject_definition
  on public.spec_facts (
    tenant_id, subject_type, subject_id, spec_definition_id,
    coalesce(subject_scope, '')
  );

-- ── Vocabularios compartidos del diagnóstico ───────────────────────────────
insert into public.spec_definitions (
  tenant_id, key, label, description, data_type, unit,
  allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, group_name, sort_order
) values
  (null, 'overall_status', 'Estado del sistema',
   'Cómo quedó el sistema tras revisarlo en esta visita.',
   'single_select', null,
   '["ok","attention","critical","unknown"]'::jsonb, '{}'::jsonb,
   true, false, false, false, true, 'Diagnóstico', 100),

  (null, 'component_condition', 'Condición del componente',
   'Estado físico de una pieza revisada: sirve, hay que mirarla, o hay que cambiarla.',
   'single_select', null,
   '["ok","attention","service","rough","play","sticky","bent","loose","uneven","worn","damaged","replace"]'::jsonb,
   '{}'::jsonb, true, false, false, false, true, 'Diagnóstico', 101),

  (null, 'contamination_status', 'Contaminación',
   'Si la superficie está limpia, sucia o contaminada con aceite o líquido.',
   'single_select', null,
   '["ok","dirty","contaminated","replace"]'::jsonb, '{}'::jsonb,
   true, false, false, false, true, 'Diagnóstico', 102),

  (null, 'noise_status', 'Ruido',
   'Qué ruido hace el sistema al moverlo o al andar.',
   'single_select', null,
   '["ok","clicking","creaking","knocking","service"]'::jsonb, '{}'::jsonb,
   true, false, false, false, true, 'Diagnóstico', 103),

  (null, 'wear_percent', 'Desgaste',
   'Desgaste medido de la pieza, en porcentaje.',
   'number', '%', '[]'::jsonb, '{"min":0,"max":100}'::jsonb,
   true, false, false, false, true, 'Diagnóstico', 104),

  (null, 'tubeless_status', 'Estado tubeless',
   'Si el sistema es tubeless y en qué estado está el líquido.',
   'single_select', null,
   '["not_applicable","ok","dry","leaking"]'::jsonb, '{}'::jsonb,
   true, false, false, false, true, 'Diagnóstico', 105),

  (null, 'diagnosis_notes', 'Notas del mecánico',
   'Lo que el mecánico escribió sobre este sistema en esta visita.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   false, false, false, false, true, 'Diagnóstico', 106)
on conflict (key) where tenant_id is null do update set
  label = excluded.label,
  description = excluded.description,
  data_type = excluded.data_type,
  allowed_values = excluded.allowed_values,
  group_name = excluded.group_name,
  updated_at = now();

-- Su vocabulario entra al registro con el mismo código que ya usan los datos.
insert into public.spec_definition_values (
  tenant_id, spec_definition_id, code, label, sort_order
)
select d.tenant_id, d.id, valor.codigo,
  coalesce(etiquetas.etiqueta, initcap(replace(valor.codigo, '_', ' '))),
  valor.orden::integer
from public.spec_definitions d
cross join lateral (
  select v #>> '{}' as codigo, ordinality as orden
  from jsonb_array_elements(d.allowed_values) with ordinality as v(v, ordinality)
) valor
left join (values
  ('ok','Sin problemas'), ('attention','Necesita atención'),
  ('critical','Crítico'), ('unknown','Sin revisar'),
  ('service','Necesita servicio'), ('rough','Áspero'), ('play','Con juego'),
  ('sticky','Pegajoso'), ('bent','Doblado'), ('loose','Suelto'),
  ('uneven','Disparejo'), ('worn','Gastado'), ('damaged','Dañado'),
  ('replace','Hay que cambiarlo'), ('dirty','Sucio'),
  ('contaminated','Contaminado'), ('clicking','Clic'), ('creaking','Cruje'),
  ('knocking','Golpea'), ('not_applicable','No aplica'), ('dry','Seco'),
  ('leaking','Con fuga')
) as etiquetas(codigo, etiqueta) on etiquetas.codigo = valor.codigo
where d.tenant_id is null and d.group_name = 'Diagnóstico'
  and jsonb_array_length(d.allowed_values) > 0
on conflict (spec_definition_id, code) do update set
  label = excluded.label, updated_at = now();

commit;
