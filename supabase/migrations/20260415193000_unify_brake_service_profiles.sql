-- Unify global brake service profiles around the centralized brake backbone.
-- Goals:
-- 1. Align service_family with the live/code canonical value: brake
-- 2. Remove obsolete legacy questions that create UI drift
-- 3. Seed canonical shared brake symptom vocabulary into global brake profiles

insert into public.service_profiles (
  id,
  tenant_id,
  key,
  name,
  service_family,
  description,
  customer_summary_template,
  mechanic_summary_template
)
select
  '00000000-0006-0000-0000-000000000001'::uuid,
  null,
  'brake_adjustment',
  'Regulación de Freno',
  'brake',
  'Ajuste y regulación de frenos mecánicos o hidráulicos',
  'Regulación {{which_wheel}}, tipo {{brake_type}}',
  'Regulación {{which_wheel}} · Tipo: {{brake_type}} · Síntomas: {{symptom}}'
where not exists (
  select 1
  from public.service_profiles
  where tenant_id is null
    and key = 'brake_adjustment'
);

update public.service_profiles
set
  name = 'Regulación de Freno',
  service_family = 'brake',
  description = 'Ajuste y regulación de frenos mecánicos o hidráulicos',
  customer_summary_template = 'Regulación {{which_wheel}}, tipo {{brake_type}}',
  mechanic_summary_template = 'Regulación {{which_wheel}} · Tipo: {{brake_type}} · Síntomas: {{symptom}}',
  updated_at = now()
where tenant_id is null
  and key = 'brake_adjustment';

insert into public.service_profiles (
  id,
  tenant_id,
  key,
  name,
  service_family,
  description,
  customer_summary_template,
  mechanic_summary_template
)
select
  '00000000-0007-0000-0000-000000000001'::uuid,
  null,
  'brake_service_general',
  'Mantención de Freno',
  'brake',
  'Mantención general del sistema de freno',
  'Mantención {{which_wheel}}, tipo {{brake_type}}',
  'Mantención {{which_wheel}} · Tipo: {{brake_type}} · Pastillas: {{pad_condition}} · Síntomas: {{symptom}}'
where not exists (
  select 1
  from public.service_profiles
  where tenant_id is null
    and key = 'brake_service_general'
);

update public.service_profiles
set
  name = 'Mantención de Freno',
  service_family = 'brake',
  description = 'Mantención general del sistema de freno',
  customer_summary_template = 'Mantención {{which_wheel}}, tipo {{brake_type}}',
  mechanic_summary_template = 'Mantención {{which_wheel}} · Tipo: {{brake_type}} · Pastillas: {{pad_condition}} · Síntomas: {{symptom}}',
  updated_at = now()
where tenant_id is null
  and key = 'brake_service_general';

update public.service_profiles
set
  service_family = 'brake',
  updated_at = now()
where tenant_id is null
  and key in (
    'hydraulic_brake_bleed',
    'piston_clean_and_reset',
    'rotor_truing'
  );

delete from public.service_profile_questions spq
using public.service_profiles sp
where sp.id = spq.service_profile_id
  and sp.tenant_id is null
  and (
    (sp.key = 'brake_adjustment' and spq.key in ('position', 'includes_cable_housing'))
    or (sp.key = 'brake_service_general' and spq.key = 'position')
  );

insert into public.service_profile_questions (
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
from public.service_profiles sp
join (
  values
    ('00000000-0006-0001-0000-000000000001'::uuid, 'brake_adjustment', 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0006-0001-0000-000000000002'::uuid, 'brake_adjustment', 'brake_type', 'Tipo de freno', 'single_select', true, 20,
     '[{"value":"hydraulic_disc","label":"Hidráulico"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"rim","label":"Llanta (rim)"},{"value":"v_brake","label":"V-Brake"},{"value":"cantilever","label":"Cantilever"},{"value":"road_caliper_short_reach","label":"Caliper corto / short reach"},{"value":"road_caliper_long_reach","label":"Caliper largo / long reach"},{"value":"roller_brake","label":"Roller brake"},{"value":"drum_brake","label":"Tambor"},{"value":"coaster_brake","label":"Contrapedal"},{"value":"band_brake","label":"Banda"}]'::jsonb),
    ('00000000-0006-0001-0000-000000000003'::uuid, 'brake_adjustment', 'symptom', 'Síntomas observados', 'multi_select', false, 30,
     '[{"value":"noise","label":"Ruido"},{"value":"vibration","label":"Vibración"},{"value":"rubbing","label":"Roce constante"},{"value":"low_power","label":"Poca potencia"},{"value":"spongy_lever","label":"Maneta esponjosa"},{"value":"intermittent","label":"Frenado intermitente"}]'::jsonb),
    ('00000000-0006-0001-0000-000000000004'::uuid, 'brake_adjustment', 'pad_condition', 'Estado de las pastillas', 'single_select', false, 40,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb),
    ('00000000-0006-0001-0000-000000000005'::uuid, 'brake_adjustment', 'rotor_condition', 'Condición del rotor', 'single_select', false, 50,
     '[{"value":"ok","label":"Buen estado"},{"value":"glazed","label":"Sucio / contaminado"},{"value":"warped","label":"Desviado / roza"},{"value":"replace","label":"Reemplazar"}]'::jsonb),
    ('00000000-0007-0001-0000-000000000001'::uuid, 'brake_service_general', 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0007-0001-0000-000000000002'::uuid, 'brake_service_general', 'brake_type', 'Tipo de freno', 'single_select', true, 20,
     '[{"value":"hydraulic_disc","label":"Hidráulico"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"rim","label":"Llanta (rim)"},{"value":"v_brake","label":"V-Brake"},{"value":"cantilever","label":"Cantilever"},{"value":"road_caliper_short_reach","label":"Caliper corto / short reach"},{"value":"road_caliper_long_reach","label":"Caliper largo / long reach"},{"value":"roller_brake","label":"Roller brake"},{"value":"drum_brake","label":"Tambor"},{"value":"coaster_brake","label":"Contrapedal"},{"value":"band_brake","label":"Banda"}]'::jsonb),
    ('00000000-0007-0001-0000-000000000003'::uuid, 'brake_service_general', 'pad_condition', 'Estado de las pastillas', 'single_select', false, 30,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb),
    ('00000000-0007-0001-0000-000000000004'::uuid, 'brake_service_general', 'fluid_check', '¿Revisar nivel de fluido hidráulico?', 'boolean', false, 40,
     '[]'::jsonb),
    ('00000000-0007-0001-0000-000000000005'::uuid, 'brake_service_general', 'symptom', 'Síntomas observados', 'multi_select', false, 50,
     '[{"value":"noise","label":"Ruido"},{"value":"vibration","label":"Vibración"},{"value":"rubbing","label":"Roce constante"},{"value":"low_power","label":"Poca potencia"},{"value":"spongy_lever","label":"Maneta esponjosa"},{"value":"intermittent","label":"Frenado intermitente"}]'::jsonb)
) as seed(id, profile_key, key, label, question_type, is_required, sort_order, options_json)
  on sp.key = seed.profile_key
where sp.tenant_id is null
  and sp.key in ('brake_adjustment', 'brake_service_general')
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();