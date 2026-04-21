-- Viñabike wheel / headset product spec templates
--
-- Purpose:
-- - seed the first real system-level wheel/headset ficha definitions and templates
-- - attach the live Viñabike wheel/headset category bridge to those template IDs
-- - unblock the product form and detailed compatibility checks before deeper testing

insert into spec_definitions
  (tenant_id, key, label, data_type, allowed_values, is_filterable,
   is_compatibility_relevant, group_name, sort_order, unit)
values
  (null, 'wheel_size', 'Tamaño de Rueda', 'single_select',
   '["12\"","16\"","20\"","24\"","26\"","27.5\"","29\"","700c","650b","Otra"]',
   true, true, 'Compatibilidad', 10, null),
  (null, 'wheel_position', 'Posición de Rueda', 'single_select',
   '["Delantera","Trasera","Universal"]',
   true, true, 'Identificación', 20, null),
  (null, 'hub_spacing_mm', 'Ancho de Maza / OLD (mm)', 'single_select',
   '["100","110","120","130","135","142","148","150","157"]',
   true, true, 'Compatibilidad', 30, 'mm'),
  (null, 'spoke_holes', 'Número de Rayos / Perforaciones', 'single_select',
   '["24","28","32","36","40"]',
   true, true, 'Compatibilidad', 40, null),
  (null, 'freehub_type', 'Driver / Freehub', 'single_select',
   '["Shimano HG","Micro Spline","SRAM XD","Campagnolo","Rueda libre roscada","Driver BMX","Rosca fija / contratuerca","Maza contrapedal","Desconocido / sin confirmar"]',
   true, true, 'Compatibilidad', 50, null),
  (null, 'valve_type', 'Tipo de Válvula', 'single_select',
   '["Presta","Schrader","Dunlop","Otra","Desconocido"]',
   true, true, 'Compatibilidad', 60, null),
  (null, 'valve_length_mm', 'Largo de Válvula (mm)', 'single_select',
   '["35","44","60","80"]',
   false, false, 'Especificaciones', 70, 'mm'),
  (null, 'spoke_length_mm', 'Largo de Rayo (mm)', 'number',
   '[]', false, false, 'Especificaciones', 80, 'mm'),
  (null, 'spoke_gauge', 'Calibre del Rayo', 'single_select',
   '["14G","14/15G","13G","2.0/1.8","2.0/1.7/2.0"]',
   true, false, 'Especificaciones', 90, null),
  (null, 'spoke_bend_type', 'Tipo de Cabeza del Rayo', 'single_select',
   '["J-Bend","Straight Pull"]',
   true, false, 'Especificaciones', 100, null),
  (null, 'bearing_system', 'Sistema de Rodamientos', 'single_select',
   '["Rodamientos sellados","Bolas sueltas","Mixto"]',
   true, false, 'Especificaciones', 110, null),
  (null, 'headset_standard', 'Estándar de Dirección', 'single_select',
   '["Integrado","Semi-integrado","Externo","Rosca","Tapered"]',
   true, true, 'Compatibilidad', 120, null),
  (null, 'steerer_type', 'Tipo de Tubo de Dirección', 'single_select',
   '["1\"","1 1/8\" recto","Tapered 1 1/8\" - 1.5\"","Otro"]',
   true, false, 'Especificaciones', 130, null),
  (null, 'bearing_application', 'Aplicación del Rodamiento', 'single_select',
   '["Maza","Dirección","Pedalier","Otro"]',
   true, false, 'Identificación', 140, null),
  (null, 'bearing_size_code', 'Código / Medida del Rodamiento', 'text',
   '[]', true, false, 'Compatibilidad', 150, null),
  (null, 'sealant_volume_ml', 'Volumen de Sellante (ml)', 'number',
    '[]', false, false, 'Especificaciones', 160, 'ml'),
    (null, 'rim_tubeless_ready', 'Tubeless Ready (TR)', 'boolean',
    '[]', true, false, 'Tubeless', 170, null),
    (null, 'rim_internal_width_mm', 'Ancho Interno', 'number',
    '[]', true, false, 'Dimensiones', 180, 'mm'),
    (null, 'rim_external_width_mm', 'Ancho Externo', 'number',
    '[]', false, false, 'Dimensiones', 190, 'mm'),
    (null, 'rim_etrto', 'Medida ETRTO', 'text',
    '[]', true, false, 'Dimensiones', 200, null),
    (null, 'rim_erd_mm', 'ERD', 'number',
    '[]', true, false, 'Dimensiones', 210, 'mm'),
    (null, 'rim_material', 'Material de la Llanta', 'single_select',
    '["Aluminio","Carbono","Acero","Otro"]',
    true, false, 'Construcción', 220, null),
    (null, 'rim_eyelet_type', 'Ojillos', 'single_select',
    '["Sin ojillos","Ojillo simple","Doble ojillo"]',
    true, false, 'Construcción', 230, null),
    (null, 'rim_wall_type', 'Construcción de Pared', 'single_select',
    '["Pared simple","Doble pared","Triple pared"]',
    true, false, 'Construcción', 240, null),
    (null, 'rim_symmetry', 'Perfil de la Llanta', 'single_select',
    '["Simétrica","Asimétrica"]',
    true, false, 'Construcción', 250, null),
    (null, 'rim_asymmetric_offset_mm', 'Offset Asimétrico', 'number',
    '[]', false, false, 'Construcción', 260, 'mm')
on conflict do nothing;

insert into spec_templates
  (tenant_id, key, name, technical_family, description, is_active)
values
  (null, 'hub', 'Maza / Hub', 'hub', 'Mazas delanteras o traseras con datos de ancho, perforación y driver', true),
  (null, 'rim', 'Llanta / Rim', 'rim', 'Llantas con rodado, perforación y taladro de válvula', true),
  (null, 'spoke', 'Rayo / Spoke', 'spoke', 'Rayos con largo, calibre y tipo de cabeza', true),
  (null, 'tube', 'Cámara', 'tube', 'Cámaras con rodado, válvula y largo de válvula', true),
  (null, 'rim_strip', 'Cubre Cámara / Rim Strip', 'rim_strip', 'Fondos de aro o cubre cámara por rodado y válvula', true),
  (null, 'tubeless_valve', 'Válvula Tubeless', 'tubeless_valve', 'Válvulas tubeless por tipo y largo', true),
  (null, 'tubeless_consumable', 'Consumible Tubeless', 'tubeless_consumable', 'Sellantes y consumibles tubeless de uso común', true),
  (null, 'headset', 'Juego de Dirección', 'headset', 'Headsets con estándar y tipo de tubo de dirección', true),
  (null, 'bearing', 'Rodamiento', 'bearing', 'Rodamientos por aplicación y medida', true)
on conflict do nothing;

do $$
declare
  t_hub uuid;
  t_rim uuid;
  t_spoke uuid;
  t_tube uuid;
  t_rim_strip uuid;
  t_tubeless_valve uuid;
  t_tubeless_consumable uuid;
  t_headset uuid;
  t_bearing uuid;

  d_wheel_size uuid;
  d_wheel_position uuid;
  d_hub_spacing_mm uuid;
  d_spoke_holes uuid;
  d_freehub_type uuid;
  d_valve_type uuid;
  d_valve_length_mm uuid;
  d_spoke_length_mm uuid;
  d_spoke_gauge uuid;
  d_spoke_bend_type uuid;
  d_bearing_system uuid;
  d_headset_standard uuid;
  d_steerer_type uuid;
  d_bearing_application uuid;
  d_bearing_size_code uuid;
  d_sealant_volume_ml uuid;
  d_rim_tubeless_ready uuid;
  d_rim_internal_width_mm uuid;
  d_rim_external_width_mm uuid;
  d_rim_etrto uuid;
  d_rim_erd_mm uuid;
  d_rim_material uuid;
  d_rim_eyelet_type uuid;
  d_rim_wall_type uuid;
  d_rim_symmetry uuid;
  d_rim_asymmetric_offset_mm uuid;
begin
  select id into t_hub from spec_templates where key = 'hub' and tenant_id is null;
  select id into t_rim from spec_templates where key = 'rim' and tenant_id is null;
  select id into t_spoke from spec_templates where key = 'spoke' and tenant_id is null;
  select id into t_tube from spec_templates where key = 'tube' and tenant_id is null;
  select id into t_rim_strip from spec_templates where key = 'rim_strip' and tenant_id is null;
  select id into t_tubeless_valve from spec_templates where key = 'tubeless_valve' and tenant_id is null;
  select id into t_tubeless_consumable from spec_templates where key = 'tubeless_consumable' and tenant_id is null;
  select id into t_headset from spec_templates where key = 'headset' and tenant_id is null;
  select id into t_bearing from spec_templates where key = 'bearing' and tenant_id is null;

  select id into d_wheel_size from spec_definitions where key = 'wheel_size' and tenant_id is null;
  select id into d_wheel_position from spec_definitions where key = 'wheel_position' and tenant_id is null;
  select id into d_hub_spacing_mm from spec_definitions where key = 'hub_spacing_mm' and tenant_id is null;
  select id into d_spoke_holes from spec_definitions where key = 'spoke_holes' and tenant_id is null;
  select id into d_freehub_type from spec_definitions where key = 'freehub_type' and tenant_id is null;
  select id into d_valve_type from spec_definitions where key = 'valve_type' and tenant_id is null;
  select id into d_valve_length_mm from spec_definitions where key = 'valve_length_mm' and tenant_id is null;
  select id into d_spoke_length_mm from spec_definitions where key = 'spoke_length_mm' and tenant_id is null;
  select id into d_spoke_gauge from spec_definitions where key = 'spoke_gauge' and tenant_id is null;
  select id into d_spoke_bend_type from spec_definitions where key = 'spoke_bend_type' and tenant_id is null;
  select id into d_bearing_system from spec_definitions where key = 'bearing_system' and tenant_id is null;
  select id into d_headset_standard from spec_definitions where key = 'headset_standard' and tenant_id is null;
  select id into d_steerer_type from spec_definitions where key = 'steerer_type' and tenant_id is null;
  select id into d_bearing_application from spec_definitions where key = 'bearing_application' and tenant_id is null;
  select id into d_bearing_size_code from spec_definitions where key = 'bearing_size_code' and tenant_id is null;
  select id into d_sealant_volume_ml from spec_definitions where key = 'sealant_volume_ml' and tenant_id is null;
  select id into d_rim_tubeless_ready from spec_definitions where key = 'rim_tubeless_ready' and tenant_id is null;
  select id into d_rim_internal_width_mm from spec_definitions where key = 'rim_internal_width_mm' and tenant_id is null;
  select id into d_rim_external_width_mm from spec_definitions where key = 'rim_external_width_mm' and tenant_id is null;
  select id into d_rim_etrto from spec_definitions where key = 'rim_etrto' and tenant_id is null;
  select id into d_rim_erd_mm from spec_definitions where key = 'rim_erd_mm' and tenant_id is null;
  select id into d_rim_material from spec_definitions where key = 'rim_material' and tenant_id is null;
  select id into d_rim_eyelet_type from spec_definitions where key = 'rim_eyelet_type' and tenant_id is null;
  select id into d_rim_wall_type from spec_definitions where key = 'rim_wall_type' and tenant_id is null;
  select id into d_rim_symmetry from spec_definitions where key = 'rim_symmetry' and tenant_id is null;
  select id into d_rim_asymmetric_offset_mm from spec_definitions where key = 'rim_asymmetric_offset_mm' and tenant_id is null;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_hub, d_wheel_position, true, 'identification', 10),
    (null, t_hub, d_hub_spacing_mm, true, 'compatibility', 10),
    (null, t_hub, d_spoke_holes, true, 'compatibility', 20),
    (null, t_hub, d_freehub_type, false, 'compatibility', 30),
    (null, t_hub, d_bearing_system, false, 'specs', 10)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_rim, d_wheel_size, true, 'compatibility', 10),
    (null, t_rim, d_spoke_holes, true, 'compatibility', 20),
    (null, t_rim, d_valve_type, false, 'compatibility', 30),
    (null, t_rim, d_rim_internal_width_mm, false, 'dimensions', 10),
    (null, t_rim, d_rim_external_width_mm, false, 'dimensions', 20),
    (null, t_rim, d_rim_etrto, false, 'dimensions', 30),
    (null, t_rim, d_rim_erd_mm, false, 'dimensions', 40),
    (null, t_rim, d_rim_material, false, 'construction', 10),
    (null, t_rim, d_rim_eyelet_type, false, 'construction', 20),
    (null, t_rim, d_rim_wall_type, false, 'construction', 30),
    (null, t_rim, d_rim_symmetry, false, 'construction', 40),
    (null, t_rim, d_rim_tubeless_ready, false, 'tubeless', 10)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order, visibility_rules)
  values
    (
      null,
      t_rim,
      d_rim_asymmetric_offset_mm,
      false,
      'construction',
      50,
      '[{"field":"rim_symmetry","operator":"eq","value":"Asimétrica"}]'::jsonb
    )
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_spoke, d_spoke_length_mm, true, 'specs', 10),
    (null, t_spoke, d_spoke_gauge, false, 'specs', 20),
    (null, t_spoke, d_spoke_bend_type, false, 'specs', 30)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_tube, d_wheel_size, true, 'compatibility', 10),
    (null, t_tube, d_valve_type, true, 'compatibility', 20),
    (null, t_tube, d_valve_length_mm, false, 'specs', 10)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_rim_strip, d_wheel_size, true, 'compatibility', 10),
    (null, t_rim_strip, d_valve_type, false, 'compatibility', 20)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_tubeless_valve, d_valve_type, true, 'compatibility', 10),
    (null, t_tubeless_valve, d_valve_length_mm, false, 'specs', 10)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_tubeless_consumable, d_sealant_volume_ml, false, 'specs', 10)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_headset, d_headset_standard, true, 'compatibility', 10),
    (null, t_headset, d_bearing_system, false, 'specs', 10),
    (null, t_headset, d_steerer_type, false, 'specs', 20)
  on conflict do nothing;

  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_bearing, d_bearing_application, true, 'identification', 10),
    (null, t_bearing, d_bearing_size_code, true, 'compatibility', 10)
  on conflict do nothing;
end $$;

do $$
declare
  v_tenant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  t_hub uuid;
  t_rim uuid;
  t_spoke uuid;
  t_tube uuid;
  t_rim_strip uuid;
  t_tubeless_valve uuid;
  t_tubeless_consumable uuid;
  t_headset uuid;
  t_bearing uuid;
begin
  select id into t_hub from spec_templates where key = 'hub' and tenant_id is null;
  select id into t_rim from spec_templates where key = 'rim' and tenant_id is null;
  select id into t_spoke from spec_templates where key = 'spoke' and tenant_id is null;
  select id into t_tube from spec_templates where key = 'tube' and tenant_id is null;
  select id into t_rim_strip from spec_templates where key = 'rim_strip' and tenant_id is null;
  select id into t_tubeless_valve from spec_templates where key = 'tubeless_valve' and tenant_id is null;
  select id into t_tubeless_consumable from spec_templates where key = 'tubeless_consumable' and tenant_id is null;
  select id into t_headset from spec_templates where key = 'headset' and tenant_id is null;
  select id into t_bearing from spec_templates where key = 'bearing' and tenant_id is null;

  insert into public.category_tech_mappings (
    tenant_id,
    category_id,
    technical_family,
    template_id,
    default_tags,
    status
  )
  select
    v_tenant,
    desired.category_id,
    desired.technical_family,
    desired.template_id,
    '[]'::jsonb,
    'active'
  from (
    values
      ('6f8d526a-11cb-46af-9860-96ab9d8839c6'::uuid, 'hub', t_hub),
      ('164a2269-4d0b-419b-af48-0098f0aae9d3'::uuid, 'hub', t_hub),
      ('072f9bc7-d5c7-4c31-8ec9-965099aefbab'::uuid, 'rim', t_rim),
      ('0e365f76-54a5-4224-8551-cb5d1d8dc539'::uuid, 'spoke', t_spoke),
      ('f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4'::uuid, 'tube', t_tube),
      ('e2660380-1cb6-4a13-9c20-452039dfa0b8'::uuid, 'tube', t_tube),
      ('aa02fb21-d0f0-4bdd-a334-d18dbcff82f6'::uuid, 'rim_strip', t_rim_strip),
      ('14d2d632-1f5f-406c-9a7c-16f55a5fc1ae'::uuid, 'tubeless_valve', t_tubeless_valve),
      ('e2014395-26a3-4fa0-8b1b-e2d049c6a0df'::uuid, 'tubeless_consumable', t_tubeless_consumable),
      ('eea4e61b-4038-407f-a715-9f11ba477c13'::uuid, 'headset', t_headset),
      ('407c429d-4e24-4744-8189-441cf865dc05'::uuid, 'bearing', t_bearing),
      ('67d3ea45-aa2a-4137-8178-e73a853f76da'::uuid, 'bearing', t_bearing)
  ) as desired(category_id, technical_family, template_id)
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status,
        updated_at = now();
end $$;