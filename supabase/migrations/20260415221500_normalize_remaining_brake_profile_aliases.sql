-- Normalize remaining global brake profiles to canonical question keys.
-- This collapses legacy aliases like position/rotor_diameter/num_pistons/
-- deviation_severity while preserving downstream task and part-rule behavior.

update service_profiles
   set name = 'Sangrado de Freno Hidráulico',
       service_family = 'brake',
       description = 'Purga y relleno de sistema de freno hidráulico',
       customer_summary_template = 'Sangrado {{which_wheel}}, fluido {{fluid_type}}',
       mechanic_summary_template = 'Sangrado {{which_wheel}} · Fluido: {{fluid_type}} · Pastillas: {{pad_condition}}',
       updated_at = now()
 where tenant_id is null
   and key = 'hydraulic_brake_bleed';

delete from service_profile_questions spq
using service_profiles sp
where sp.id = spq.service_profile_id
  and sp.tenant_id is null
  and sp.key = 'hydraulic_brake_bleed'
  and spq.key in ('position', 'symptom_severity', 'hose_condition');

insert into service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from service_profiles sp
join (
  values
    ('00000000-0001-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas ruedas"}]'::jsonb),
    ('00000000-0001-0001-0000-000000000002'::uuid, 'fluid_type', 'Tipo de fluido', 'single_select', true, 20,
     '[{"value":"mineral","label":"Aceite Mineral (Shimano / Magura / Tektro)"},{"value":"dot","label":"DOT 4 / 5.1 (SRAM / Hayes / Hope)"}]'::jsonb),
    ('00000000-0001-0001-0000-000000000003'::uuid, 'pad_condition', 'Estado de las pastillas', 'single_select', false, 30,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb),
    ('00000000-0001-0001-0000-000000000004'::uuid, 'replace_pads', '¿Reemplazar pastillas?', 'boolean', false, 40,
     '[]'::jsonb),
    ('00000000-0001-0001-0000-000000000006'::uuid, 'pad_contaminated', '¿Pastillas contaminadas con fluido?', 'boolean', false, 45,
     '[]'::jsonb),
    ('00000000-0001-0001-0000-000000000005'::uuid, 'rotor_condition', 'Estado del disco/rotor', 'single_select', false, 50,
     '[{"value":"ok","label":"Buen estado"},{"value":"glazed","label":"Cristalizado"},{"value":"warped","label":"Combado / deformado"},{"value":"replace","label":"Requiere reemplazo"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'hydraulic_brake_bleed'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

update service_profiles
   set name = 'Limpieza y Elongación de Pistones',
       service_family = 'brake',
       description = 'Limpieza y elongación de pistones de freno hidráulico',
       customer_summary_template = 'Pistones {{which_wheel}}, contaminación {{contamination_level}}',
       mechanic_summary_template = 'Pistones {{which_wheel}} · Contaminación: {{contamination_level}} · Sellos: {{replace_seals}}',
       updated_at = now()
 where tenant_id is null
   and key = 'piston_clean_and_reset';

delete from service_profile_questions spq
using service_profiles sp
where sp.id = spq.service_profile_id
  and sp.tenant_id is null
  and sp.key = 'piston_clean_and_reset'
  and spq.key in ('position', 'fluid_type', 'num_pistons');

insert into service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from service_profiles sp
join (
  values
    ('00000000-0005-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0005-0001-0000-000000000002'::uuid, 'piston_count', 'Número de pistones', 'single_select', false, 20,
     '[{"value":"2","label":"2 pistones"},{"value":"4","label":"4 pistones"}]'::jsonb),
    ('00000000-0005-0001-0000-000000000003'::uuid, 'contamination_level', 'Nivel de contaminación', 'single_select', false, 30,
     '[{"value":"none","label":"Sin contaminación"},{"value":"light","label":"Leve"},{"value":"moderate","label":"Moderada"},{"value":"severe","label":"Severa"}]'::jsonb),
    ('00000000-0005-0001-0000-000000000004'::uuid, 'replace_seals', '¿Reemplazar sellos?', 'boolean', false, 40,
     '[]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'piston_clean_and_reset'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

update service_profiles
   set name = 'Centrado de Rotor',
       service_family = 'brake',
       description = 'Centrado y ajuste de disco/rotor de freno',
       customer_summary_template = 'Centrado rotor {{which_wheel}}',
       mechanic_summary_template = 'Rotor {{which_wheel}} · Daño: {{damage_level}}',
       updated_at = now()
 where tenant_id is null
   and key = 'rotor_truing';

delete from service_profile_questions spq
using service_profiles sp
where sp.id = spq.service_profile_id
  and sp.tenant_id is null
  and sp.key = 'rotor_truing'
  and spq.key in ('position', 'rotor_diameter', 'deviation_severity');

insert into service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from service_profiles sp
join (
  values
    ('00000000-0008-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0008-0001-0000-000000000002'::uuid, 'rotor_size', 'Tamaño del rotor', 'single_select', false, 20,
     '[{"value":"140","label":"140 mm"},{"value":"160","label":"160 mm"},{"value":"180","label":"180 mm"},{"value":"203","label":"203 mm"}]'::jsonb),
    ('00000000-0008-0001-0000-000000000003'::uuid, 'damage_level', 'Nivel de daño del rotor', 'single_select', false, 30,
     '[{"value":"minor","label":"Leve - centrado posible"},{"value":"moderate","label":"Moderado"},{"value":"severe","label":"Severo - puede requerir reemplazo"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'rotor_truing'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

update service_profile_task_templates spt
   set conditions_json = '[{"question_key":"damage_level","operator":"eq","value":"severe"}]'::jsonb,
       updated_at = now()
  from service_profiles sp
 where sp.id = spt.service_profile_id
   and sp.tenant_id is null
   and sp.key = 'rotor_truing'
   and spt.conditions_json::text like '%deviation_severity%';