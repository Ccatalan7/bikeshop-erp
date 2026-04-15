-- Align default brake wizard profiles with the upstream brake-platform vocabulary.
-- This updates the global brake profiles by key, so it works even if the live
-- database already has those profiles under different UUIDs.

update public.service_profile_questions q
   set label = 'Tipo de freno',
       question_type = 'single_select',
       is_required = true,
       sort_order = 20,
       options_json = '[{"value":"hydraulic_disc","label":"Hidráulico"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"rim","label":"Llanta (rim)"},{"value":"v_brake","label":"V-Brake"},{"value":"cantilever","label":"Cantilever"},{"value":"road_caliper_short_reach","label":"Caliper corto / short reach"},{"value":"road_caliper_long_reach","label":"Caliper largo / long reach"},{"value":"roller_brake","label":"Roller brake"},{"value":"drum_brake","label":"Tambor"},{"value":"coaster_brake","label":"Contrapedal"},{"value":"band_brake","label":"Banda"}]'::jsonb,
       updated_at = now()
  from public.service_profiles sp
 where q.service_profile_id = sp.id
   and sp.tenant_id is null
   and sp.key in ('brake_adjustment', 'brake_service_general')
   and q.key = 'brake_type';

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
  gen_random_uuid(),
  sp.tenant_id,
  sp.id,
  'brake_type',
  'Tipo de freno',
  'single_select',
  true,
  20,
  '[{"value":"hydraulic_disc","label":"Hidráulico"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"rim","label":"Llanta (rim)"},{"value":"v_brake","label":"V-Brake"},{"value":"cantilever","label":"Cantilever"},{"value":"road_caliper_short_reach","label":"Caliper corto / short reach"},{"value":"road_caliper_long_reach","label":"Caliper largo / long reach"},{"value":"roller_brake","label":"Roller brake"},{"value":"drum_brake","label":"Tambor"},{"value":"coaster_brake","label":"Contrapedal"},{"value":"band_brake","label":"Banda"}]'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key in ('brake_adjustment', 'brake_service_general')
  and not exists (
    select 1
      from public.service_profile_questions q
     where q.service_profile_id = sp.id
       and q.key = 'brake_type'
  );