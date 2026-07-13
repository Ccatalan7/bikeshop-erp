-- Viñabike wheel / hub / tube / tubeless / headset rollout
--
-- Seeds the missing global service profiles and target rows for the next
-- wheel and steering workflows, then maps only the clearly matching live
-- Viñabike service products.
--
-- Intentionally deferred until dedicated profiles exist:
-- - `Ajuste de dirección` -> future `headset_adjustment`
-- - `Instalación Juego de Dirección` -> future `headset_install`
-- - `Ajuste Maza` -> future dedicated hub-adjustment profile if needed
-- - `Cambio de Maza` -> keep as a part/replacement workflow, not generic maintenance

-- ============================================================
-- Global service profiles
-- ============================================================

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
  '00000000-0009-0000-0000-000000000001',
  null,
  'wheel_build_and_true',
  'Enrayado y Centrado',
  'wheels',
  'Armado, rayado y centrado completo de rueda',
  'Enrayado y centrado {{which_wheel}} {{wheel_size}}',
  'Enrayado {{which_wheel}} · Aro {{wheel_size}} · Agujeros {{hole_count}} · Freno {{brake_type}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'wheel_build_and_true'
);

update public.service_profiles
   set name = 'Enrayado y Centrado',
       service_family = 'wheels',
       description = 'Armado, rayado y centrado completo de rueda',
       customer_summary_template = 'Enrayado y centrado {{which_wheel}} {{wheel_size}}',
       mechanic_summary_template = 'Enrayado {{which_wheel}} · Aro {{wheel_size}} · Agujeros {{hole_count}} · Freno {{brake_type}}',
       updated_at = now()
 where tenant_id is null
   and key = 'wheel_build_and_true';

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
    ('00000000-0009-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"}]'::jsonb),
    ('00000000-0009-0001-0000-000000000002'::uuid, 'wheel_size', 'Tamaño de rueda', 'single_select', true, 20,
     '[{"value":"20","label":"20\""},{"value":"24","label":"24\""},{"value":"26","label":"26\""},{"value":"27.5","label":"27.5\" / 650b"},{"value":"29","label":"29\""},{"value":"700c","label":"700c"}]'::jsonb),
    ('00000000-0009-0001-0000-000000000003'::uuid, 'hole_count', 'Cantidad de perforaciones', 'single_select', true, 30,
     '[{"value":"20","label":"20H"},{"value":"24","label":"24H"},{"value":"28","label":"28H"},{"value":"32","label":"32H"},{"value":"36","label":"36H"},{"value":"40","label":"40H"}]'::jsonb),
    ('00000000-0009-0001-0000-000000000004'::uuid, 'brake_type', 'Plataforma de freno', 'single_select', true, 40,
     '[{"value":"rim","label":"Llanta"},{"value":"mechanical_disc","label":"Disco mecánico"},{"value":"hydraulic_disc","label":"Disco hidráulico"},{"value":"roller_brake","label":"Roller brake"},{"value":"drum_brake","label":"Tambor"},{"value":"coaster_brake","label":"Contrapedal"},{"value":"band_brake","label":"Banda"}]'::jsonb),
    ('00000000-0009-0001-0000-000000000005'::uuid, 'hub_selected', 'Maza seleccionada', 'text', false, 50,
     '[]'::jsonb),
    ('00000000-0009-0001-0000-000000000006'::uuid, 'rim_selected', 'Aro seleccionado', 'text', false, 60,
     '[]'::jsonb),
    ('00000000-0009-0001-0000-000000000007'::uuid, 'spoke_model', 'Modelo de rayo', 'text', false, 70,
     '[]'::jsonb),
    ('00000000-0009-0001-0000-000000000008'::uuid, 'build_pattern', 'Patrón de armado', 'single_select', false, 80,
     '[{"value":"radial","label":"Radial"},{"value":"two_cross","label":"2 cruces"},{"value":"three_cross","label":"3 cruces"},{"value":"other","label":"Otro"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'wheel_build_and_true'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

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
  '00000000-0010-0000-0000-000000000001',
  null,
  'hub_service',
  'Servicio de Maza',
  'wheels',
  'Mantención y servicio de maza delantera o trasera',
  'Servicio de maza {{which_wheel}} · síntoma {{symptom}}',
  'Maza {{which_wheel}} · Eje {{axle_type}} · Síntoma {{symptom}} · Rodamiento {{bearing_system}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'hub_service'
);

update public.service_profiles
   set name = 'Servicio de Maza',
       service_family = 'wheels',
       description = 'Mantención y servicio de maza delantera o trasera',
       customer_summary_template = 'Servicio de maza {{which_wheel}} · síntoma {{symptom}}',
       mechanic_summary_template = 'Maza {{which_wheel}} · Eje {{axle_type}} · Síntoma {{symptom}} · Rodamiento {{bearing_system}}',
       updated_at = now()
 where tenant_id is null
   and key = 'hub_service';

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
    ('00000000-0010-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"}]'::jsonb),
    ('00000000-0010-0001-0000-000000000002'::uuid, 'axle_type', 'Tipo de eje', 'single_select', true, 20,
     '[{"value":"quick_release","label":"Quick release"},{"value":"thru_axle_12","label":"Thru axle 12 mm"},{"value":"thru_axle_15","label":"Thru axle 15 mm"},{"value":"solid_nut","label":"Eje macizo con tuerca"},{"value":"bmx_bolt_on","label":"BMX / bolt-on"},{"value":"other","label":"Otro"}]'::jsonb),
    ('00000000-0010-0001-0000-000000000003'::uuid, 'symptom', 'Síntoma principal', 'single_select', true, 30,
     '[{"value":"play","label":"Juego"},{"value":"noise","label":"Ruido"},{"value":"roughness","label":"Dureza / aspereza"},{"value":"preventive","label":"Mantención preventiva"}]'::jsonb),
    ('00000000-0010-0001-0000-000000000004'::uuid, 'bearing_system', 'Sistema de rodamientos', 'single_select', false, 40,
     '[{"value":"cup_cone","label":"Copa y cono"},{"value":"cartridge","label":"Rodamiento sellado / cartridge"},{"value":"unknown","label":"Desconocido"}]'::jsonb),
    ('00000000-0010-0001-0000-000000000005'::uuid, 'freehub_service_needed', '¿Revisar cuerpo de freehub?', 'boolean', false, 50,
     '[]'::jsonb),
    ('00000000-0010-0001-0000-000000000006'::uuid, 'bearing_replacement_needed', '¿Reemplazar rodamientos?', 'boolean', false, 60,
     '[]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'hub_service'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

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
  '00000000-0011-0000-0000-000000000001',
  null,
  'tube_replacement',
  'Cambio de Cámara',
  'wheels',
  'Reemplazo de cámara interior',
  'Cambio de cámara {{which_wheel}} {{wheel_size}}',
  'Cámara {{which_wheel}} · Aro {{wheel_size}} · Válvula {{valve_type}} · Neumático {{tire_condition}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'tube_replacement'
);

update public.service_profiles
   set name = 'Cambio de Cámara',
       service_family = 'wheels',
       description = 'Reemplazo de cámara interior',
       customer_summary_template = 'Cambio de cámara {{which_wheel}} {{wheel_size}}',
       mechanic_summary_template = 'Cámara {{which_wheel}} · Aro {{wheel_size}} · Válvula {{valve_type}} · Neumático {{tire_condition}}',
       updated_at = now()
 where tenant_id is null
   and key = 'tube_replacement';

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
    ('00000000-0011-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"}]'::jsonb),
    ('00000000-0011-0001-0000-000000000002'::uuid, 'wheel_size', 'Tamaño de rueda', 'single_select', true, 20,
     '[{"value":"20","label":"20\""},{"value":"24","label":"24\""},{"value":"26","label":"26\""},{"value":"27.5","label":"27.5\" / 650b"},{"value":"29","label":"29\""},{"value":"700c","label":"700c"}]'::jsonb),
    ('00000000-0011-0001-0000-000000000003'::uuid, 'valve_type', 'Tipo de válvula', 'single_select', true, 30,
     '[{"value":"presta","label":"Presta"},{"value":"schrader","label":"Schrader"},{"value":"dunlop","label":"Dunlop"},{"value":"other","label":"Otra"}]'::jsonb),
    ('00000000-0011-0001-0000-000000000004'::uuid, 'tire_condition', 'Estado del neumático', 'single_select', false, 40,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastado"},{"value":"damaged","label":"Dañado"}]'::jsonb),
    ('00000000-0011-0001-0000-000000000005'::uuid, 'rim_tape_condition', 'Estado de la cinta de aro', 'single_select', false, 50,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastada"},{"value":"missing","label":"Falta / incorrecta"}]'::jsonb),
    ('00000000-0011-0001-0000-000000000006'::uuid, 'puncture_cause', 'Causa del pinchazo', 'text', false, 60,
     '[]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'tube_replacement'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

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
  '00000000-0012-0000-0000-000000000001',
  null,
  'tubeless_conversion',
  'Conversión Tubeless',
  'wheels',
  'Conversión de rueda a sistema tubeless',
  'Conversión tubeless {{which_wheel}} {{wheel_size}}',
  'Tubeless {{which_wheel}} · Aro {{wheel_size}} · Tire ready {{tire_tubeless_ready}} · Sellante {{sealant_volume_ml}} ml'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'tubeless_conversion'
);

update public.service_profiles
   set name = 'Conversión Tubeless',
       service_family = 'wheels',
       description = 'Conversión de rueda a sistema tubeless',
       customer_summary_template = 'Conversión tubeless {{which_wheel}} {{wheel_size}}',
       mechanic_summary_template = 'Tubeless {{which_wheel}} · Aro {{wheel_size}} · Tire ready {{tire_tubeless_ready}} · Sellante {{sealant_volume_ml}} ml',
       updated_at = now()
 where tenant_id is null
   and key = 'tubeless_conversion';

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
    ('00000000-0012-0001-0000-000000000001'::uuid, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0012-0001-0000-000000000002'::uuid, 'wheel_size', 'Tamaño de rueda', 'single_select', true, 20,
     '[{"value":"20","label":"20\""},{"value":"24","label":"24\""},{"value":"26","label":"26\""},{"value":"27.5","label":"27.5\" / 650b"},{"value":"29","label":"29\""},{"value":"700c","label":"700c"}]'::jsonb),
    ('00000000-0012-0001-0000-000000000003'::uuid, 'tire_tubeless_ready', '¿Neumático tubeless-ready?', 'boolean', true, 30,
     '[]'::jsonb),
    ('00000000-0012-0001-0000-000000000004'::uuid, 'valve_length_mm', 'Largo de válvula', 'single_select', false, 40,
     '[{"value":"35","label":"35 mm"},{"value":"44","label":"44 mm"},{"value":"55","label":"55 mm"},{"value":"60","label":"60 mm"},{"value":"80","label":"80 mm"}]'::jsonb),
    ('00000000-0012-0001-0000-000000000005'::uuid, 'sealant_volume_ml', 'Volumen de sellante', 'single_select', false, 50,
     '[{"value":"60","label":"60 ml"},{"value":"80","label":"80 ml"},{"value":"100","label":"100 ml"},{"value":"120","label":"120 ml"}]'::jsonb),
    ('00000000-0012-0001-0000-000000000006'::uuid, 'rim_tape_width_mm', 'Ancho de cinta tubeless', 'single_select', false, 60,
     '[{"value":"21","label":"21 mm"},{"value":"23","label":"23 mm"},{"value":"25","label":"25 mm"},{"value":"27","label":"27 mm"},{"value":"30","label":"30 mm"},{"value":"32","label":"32 mm"},{"value":"35","label":"35 mm"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'tubeless_conversion'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

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
  '00000000-0013-0000-0000-000000000001',
  null,
  'headset_service',
  'Mantención de Dirección',
  'cockpit',
  'Mantención del sistema de dirección y headset',
  'Mantención de dirección · síntoma {{symptom}}',
  'Dirección · Síntoma {{symptom}} · Rodamientos {{bearing_replacement_needed}} · Pista corona {{crown_race_condition}}'
where not exists (
  select 1
    from public.service_profiles
   where tenant_id is null
     and key = 'headset_service'
);

update public.service_profiles
   set name = 'Mantención de Dirección',
       service_family = 'cockpit',
       description = 'Mantención del sistema de dirección y headset',
       customer_summary_template = 'Mantención de dirección · síntoma {{symptom}}',
       mechanic_summary_template = 'Dirección · Síntoma {{symptom}} · Rodamientos {{bearing_replacement_needed}} · Pista corona {{crown_race_condition}}',
       updated_at = now()
 where tenant_id is null
   and key = 'headset_service';

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
    ('00000000-0013-0001-0000-000000000001'::uuid, 'symptom', 'Síntoma principal', 'single_select', true, 10,
     '[{"value":"play","label":"Juego"},{"value":"roughness","label":"Dureza"},{"value":"noise","label":"Ruido"},{"value":"preventive","label":"Mantención"}]'::jsonb),
    ('00000000-0013-0001-0000-000000000002'::uuid, 'bearing_replacement_needed', '¿Reemplazar rodamientos?', 'boolean', false, 20,
     '[]'::jsonb),
    ('00000000-0013-0001-0000-000000000003'::uuid, 'crown_race_condition', 'Estado de la pista de corona', 'single_select', false, 30,
     '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastada"},{"value":"replace","label":"Reemplazar"}]'::jsonb)
) as seed(id, key, label, question_type, is_required, sort_order, options_json)
  on true
where sp.tenant_id is null
  and sp.key = 'headset_service'
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();

insert into public.service_profile_targets (
  tenant_id,
  service_profile_id,
  target_family,
  target_position_mode,
  target_rules
)
select null, sp.id, 'wheels', 'front_rear', '{}'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key in ('wheel_build_and_true', 'hub_service', 'tube_replacement', 'tubeless_conversion')
  and not exists (
    select 1
      from public.service_profile_targets spt
     where spt.tenant_id is null
       and spt.service_profile_id = sp.id
       and spt.target_family = 'wheels'
       and spt.target_position_mode = 'front_rear'
  );

insert into public.service_profile_targets (
  tenant_id,
  service_profile_id,
  target_family,
  target_position_mode,
  target_rules
)
select null, sp.id, 'cockpit', 'none', '{}'::jsonb
from public.service_profiles sp
where sp.tenant_id is null
  and sp.key = 'headset_service'
  and not exists (
    select 1
      from public.service_profile_targets spt
     where spt.tenant_id is null
       and spt.service_profile_id = sp.id
       and spt.target_family = 'cockpit'
       and spt.target_position_mode = 'none'
  );

-- ============================================================
-- Viñabike mappings
-- ============================================================

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Enrayado + Centrado', 'wheel_build_and_true'),
      ('Servicio de Mazas (C/U)', 'hub_service'),
      ('Mantención Maza', 'hub_service'),
      ('Cambio de cámara (no incluye cámara)', 'tube_replacement'),
      ('Tubeless Viñabike', 'tubeless_conversion'),
      ('Tubeless Bettabikes', 'tubeless_conversion'),
      ('Mantención De Dirección', 'headset_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
update public.service_product_profile_mappings spm
   set status = 'inactive'
  from desired_mappings dm
 where spm.tenant_id = dm.tenant_id
   and spm.product_id = dm.product_id
   and spm.status = 'active'
   and spm.service_profile_id <> dm.service_profile_id;

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Enrayado + Centrado', 'wheel_build_and_true'),
      ('Servicio de Mazas (C/U)', 'hub_service'),
      ('Mantención Maza', 'hub_service'),
      ('Cambio de cámara (no incluye cámara)', 'tube_replacement'),
      ('Tubeless Viñabike', 'tubeless_conversion'),
      ('Tubeless Bettabikes', 'tubeless_conversion'),
      ('Mantención De Dirección', 'headset_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
update public.service_product_profile_mappings spm
   set status = 'active'
  from desired_mappings dm
 where spm.tenant_id = dm.tenant_id
   and spm.product_id = dm.product_id
   and spm.service_profile_id = dm.service_profile_id;

with desired_mappings as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    p.id as product_id,
    sp.id as service_profile_id
  from (
    values
      ('Enrayado + Centrado', 'wheel_build_and_true'),
      ('Servicio de Mazas (C/U)', 'hub_service'),
      ('Mantención Maza', 'hub_service'),
      ('Cambio de cámara (no incluye cámara)', 'tube_replacement'),
      ('Tubeless Viñabike', 'tubeless_conversion'),
      ('Tubeless Bettabikes', 'tubeless_conversion'),
      ('Mantención De Dirección', 'headset_service')
  ) as desired(product_name, profile_key)
  join public.products p
    on p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and p.product_type = 'service'
   and p.name = desired.product_name
  join public.service_profiles sp
    on sp.tenant_id is null
   and sp.key = desired.profile_key
)
insert into public.service_product_profile_mappings (
  tenant_id,
  product_id,
  service_profile_id,
  status
)
select
  dm.tenant_id,
  dm.product_id,
  dm.service_profile_id,
  'active'
from desired_mappings dm
where not exists (
  select 1
    from public.service_product_profile_mappings spm
   where spm.tenant_id = dm.tenant_id
     and spm.product_id = dm.product_id
     and spm.service_profile_id = dm.service_profile_id
);