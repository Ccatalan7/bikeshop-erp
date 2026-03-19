-- ============================================================
-- Service Wizard: System Profiles + Viñabike Product Mappings
-- Deploy in Supabase SQL Editor
-- ============================================================

-- 1) System-level service profiles (tenant_id = NULL = available to all tenants)
-- Uses WHERE NOT EXISTS to avoid duplicate key conflicts regardless of stored IDs
insert into service_profiles (id, tenant_id, key, name, service_family, description, customer_summary_template, mechanic_summary_template)
select
  '00000000-0001-0000-0000-000000000001',
  null,
  'hydraulic_brake_bleed',
  'Sangrado de Freno Hidráulico',
  'brakes',
  'Purga y relleno de sistema de freno hidráulico',
  'Sangrado {{which_wheel}}, fluido {{fluid_type}}',
  'Sangrado {{which_wheel}} · Fluido: {{fluid_type}} · Pastillas: {{pad_condition}}'
where not exists (select 1 from service_profiles where key = 'hydraulic_brake_bleed' and tenant_id is null);

insert into service_profiles (id, tenant_id, key, name, service_family, description)
select '00000000-0002-0000-0000-000000000001', null, 'chain_lube', 'Limpieza y Lubricación de Cadena', 'drivetrain', 'Limpieza profunda y lubricación de cadena, piñones y platos'
where not exists (select 1 from service_profiles where key = 'chain_lube' and tenant_id is null);

insert into service_profiles (id, tenant_id, key, name, service_family, description)
select '00000000-0003-0000-0000-000000000001', null, 'derailleur_adjustment', 'Ajuste de Cambios', 'drivetrain', 'Ajuste y calibración de desviadores delantero y trasero'
where not exists (select 1 from service_profiles where key = 'derailleur_adjustment' and tenant_id is null);

insert into service_profiles (id, tenant_id, key, name, service_family, description)
select '00000000-0004-0000-0000-000000000001', null, 'wheel_truing', 'Centrado de Rueda', 'wheels', 'Centrado y tensado de radios'
where not exists (select 1 from service_profiles where key = 'wheel_truing' and tenant_id is null);

-- 2) Questions for hydraulic brake bleed
-- Resolve the profile id dynamically (handles case where profile was seeded with a different id)
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'hydraulic_brake_bleed' and tenant_id is null limit 1;
  if v_profile_id is null then
    raise notice 'hydraulic_brake_bleed profile not found, skipping questions';
    return;
  end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas ruedas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'fluid_type', 'Tipo de fluido', 'single_select', true, 20,
    '[{"value":"mineral","label":"Aceite mineral"},{"value":"dot3","label":"DOT 3"},{"value":"dot4","label":"DOT 4"},{"value":"dot51","label":"DOT 5.1"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'fluid_type' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'pad_condition', 'Estado de las pastillas', 'single_select', false, 30,
    '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'pad_condition' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'replace_pads', '¿Reemplazar pastillas?', 'boolean', false, 40, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'replace_pads' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'rotor_condition', 'Estado del disco/rotor', 'single_select', false, 50,
    '[{"value":"ok","label":"Buen estado"},{"value":"glazed","label":"Cristalizado"},{"value":"warped","label":"Combado / deformado"},{"value":"replace","label":"Requiere reemplazo"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'rotor_condition' and tenant_id is null);
end $$;

-- 3) Questions for chain lube
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'chain_lube' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'lube_type', 'Tipo de lubricante', 'single_select', true, 10,
    '[{"value":"dry","label":"Seco (polvo / poca lluvia)"},{"value":"wet","label":"Húmedo (lluvia / barro)"},{"value":"ceramic","label":"Cerámico (alto rendimiento)"},{"value":"wax","label":"Cera"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'lube_type' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'chain_wear', 'Desgaste de la cadena', 'single_select', false, 20,
    '[{"value":"ok","label":"OK (< 0.5%)"},{"value":"worn","label":"Desgastada (0.5-0.75%) - reemplazar pronto"},{"value":"replace","label":"Muy desgastada (> 0.75%) - cambiar ahora"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'chain_wear' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'derailleur_check', '¿Revisar derailleur?', 'boolean', false, 30, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'derailleur_check' and tenant_id is null);
end $$;

-- 4) Questions for derailleur adjustment
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'derailleur_adjustment' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'derailleurs', '¿Qué desviadores?', 'multi_select', true, 10,
    '[{"value":"rear","label":"Trasero"},{"value":"front","label":"Delantero"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'derailleurs' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'cable_condition', 'Estado de cables', 'single_select', false, 20,
    '[{"value":"ok","label":"OK"},{"value":"frayed","label":"Deshilachados - reemplazar"},{"value":"replace","label":"Ya reemplazados"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'cable_condition' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'include_housing', '¿Incluye funda de cables?', 'boolean', false, 30, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'include_housing' and tenant_id is null);
end $$;

-- 5) Questions for wheel truing
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'wheel_truing' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'rim_damage', 'Daño en el aro', 'single_select', false, 20,
    '[{"value":"none","label":"Sin daño visible"},{"value":"minor","label":"Leve - centrado posible"},{"value":"major","label":"Grave - puede requerir reemplazo"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'rim_damage' and tenant_id is null);
end $$;

-- ============================================================
-- 6) New brake-specific service profiles
-- ============================================================

-- Piston clean & reset (Limpieza y Elongación de Pistones)
insert into service_profiles (id, tenant_id, key, name, service_family, description, customer_summary_template, mechanic_summary_template)
select '00000000-0005-0000-0000-000000000001', null, 'piston_clean_and_reset',
  'Limpieza y Elongación de Pistones', 'brakes',
  'Limpieza y elongación de pistones de freno hidráulico',
  'Pistones {{which_wheel}}, contaminación {{contamination_level}}',
  'Pistones {{which_wheel}} · Contaminación: {{contamination_level}} · Sellos: {{replace_seals}}'
where not exists (select 1 from service_profiles where key = 'piston_clean_and_reset' and tenant_id is null);

-- Brake adjustment (Regulación de Freno)
insert into service_profiles (id, tenant_id, key, name, service_family, description, customer_summary_template, mechanic_summary_template)
select '00000000-0006-0000-0000-000000000001', null, 'brake_adjustment',
  'Regulación de Freno', 'brakes',
  'Ajuste y regulación de frenos mecánicos o hidráulicos',
  'Regulación {{which_wheel}}, tipo {{brake_type}}',
  'Regulación {{which_wheel}} · Tipo: {{brake_type}} · Fundas: {{includes_cable_housing}}'
where not exists (select 1 from service_profiles where key = 'brake_adjustment' and tenant_id is null);

-- General brake service (Mantención de Freno)
insert into service_profiles (id, tenant_id, key, name, service_family, description, customer_summary_template, mechanic_summary_template)
select '00000000-0007-0000-0000-000000000001', null, 'brake_service_general',
  'Mantención de Freno', 'brakes',
  'Mantención general del sistema de freno',
  'Mantención {{which_wheel}}, tipo {{brake_type}}',
  'Mantención {{which_wheel}} · Tipo: {{brake_type}} · Pastillas: {{pad_condition}}'
where not exists (select 1 from service_profiles where key = 'brake_service_general' and tenant_id is null);

-- Rotor truing (Centrado de Rotor)
insert into service_profiles (id, tenant_id, key, name, service_family, description, customer_summary_template, mechanic_summary_template)
select '00000000-0008-0000-0000-000000000001', null, 'rotor_truing',
  'Centrado de Rotor', 'brakes',
  'Centrado y ajuste de disco/rotor de freno',
  'Centrado rotor {{which_wheel}}',
  'Rotor {{which_wheel}} · Daño: {{damage_level}}'
where not exists (select 1 from service_profiles where key = 'rotor_truing' and tenant_id is null);

-- Questions: piston_clean_and_reset
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'piston_clean_and_reset' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'piston_count', 'Número de pistones', 'single_select', false, 20,
    '[{"value":"2","label":"2 pistones"},{"value":"4","label":"4 pistones"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'piston_count' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'contamination_level', 'Nivel de contaminación', 'single_select', false, 30,
    '[{"value":"none","label":"Sin contaminación"},{"value":"light","label":"Leve"},{"value":"moderate","label":"Moderada"},{"value":"severe","label":"Severa"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'contamination_level' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'replace_seals', '¿Reemplazar sellos?', 'boolean', false, 40, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'replace_seals' and tenant_id is null);
end $$;

-- Questions: brake_adjustment
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'brake_adjustment' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'brake_type', 'Tipo de freno', 'single_select', true, 20,
    '[{"value":"mech_disc","label":"Mecánico (disco)"},{"value":"rim","label":"Llanta (rim)"},{"value":"hydraulic","label":"Hidráulico"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'brake_type' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'includes_cable_housing', '¿Incluye fundas y piolas?', 'boolean', false, 30, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'includes_cable_housing' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'pad_condition', 'Estado de las pastillas', 'single_select', false, 40,
    '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'pad_condition' and tenant_id is null);
end $$;

-- Questions: brake_service_general
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'brake_service_general' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'brake_type', 'Tipo de freno', 'single_select', true, 20,
    '[{"value":"mech_disc","label":"Mecánico (disco)"},{"value":"rim","label":"Llanta (rim)"},{"value":"hydraulic","label":"Hidráulico"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'brake_type' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'pad_condition', 'Estado de las pastillas', 'single_select', false, 30,
    '[{"value":"ok","label":"Buen estado"},{"value":"worn","label":"Desgastadas - reemplazar"},{"value":"critical","label":"Crítico - cambio urgente"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'pad_condition' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'fluid_check', '¿Revisar nivel de fluido hidráulico?', 'boolean', false, 40, '[]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'fluid_check' and tenant_id is null);
end $$;

-- Questions: rotor_truing
do $$
declare
  v_profile_id uuid;
begin
  select id into v_profile_id from service_profiles where key = 'rotor_truing' and tenant_id is null limit 1;
  if v_profile_id is null then return; end if;

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'which_wheel', '¿Qué rueda?', 'single_select', true, 10,
    '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'which_wheel' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'rotor_size', 'Tamaño del rotor', 'single_select', false, 20,
    '[{"value":"140","label":"140 mm"},{"value":"160","label":"160 mm"},{"value":"180","label":"180 mm"},{"value":"203","label":"203 mm"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'rotor_size' and tenant_id is null);

  insert into service_profile_questions (tenant_id, service_profile_id, key, label, question_type, is_required, sort_order, options_json)
  select null, v_profile_id, 'damage_level', 'Nivel de daño del rotor', 'single_select', false, 30,
    '[{"value":"minor","label":"Leve - centrado posible"},{"value":"moderate","label":"Moderado"},{"value":"severe","label":"Severo - puede requerir reemplazo"}]'::jsonb
  where not exists (select 1 from service_profile_questions where service_profile_id = v_profile_id and key = 'damage_level' and tenant_id is null);
end $$;

-- ============================================================
-- 7) Viñabike product → profile mappings (all brake services)
-- ============================================================
do $$
declare
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_product_id uuid;
  v_profile_id uuid;
  v_rec record;
begin
  for v_rec in
    select sku, profile_key from (values
      ('NNV78',        'piston_clean_and_reset'),
      ('M003',         'brake_adjustment'),
      ('SKU-3DC8D9D7', 'hydraulic_brake_bleed'),
      ('NNV91',        'brake_service_general'),
      ('NNV88',        'brake_service_general'),
      ('M006',         'brake_adjustment'),
      ('NNV165',       'hydraulic_brake_bleed'),
      ('NNV38',        'rotor_truing'),
      ('M002',         'brake_service_general')
    ) as t(sku, profile_key)
  loop
    select id into v_product_id from products
    where tenant_id = v_tenant_id and sku = v_rec.sku limit 1;

    select id into v_profile_id from service_profiles
    where key = v_rec.profile_key and tenant_id is null limit 1;

    if v_product_id is not null and v_profile_id is not null then
      insert into service_product_profile_mappings
        (tenant_id, product_id, service_profile_id, status)
      values (v_tenant_id, v_product_id, v_profile_id, 'active')
      on conflict (tenant_id, product_id)
        do update set service_profile_id = excluded.service_profile_id;
      raise notice 'Mapped SKU % → %', v_rec.sku, v_rec.profile_key;
    elsif v_product_id is null then
      raise notice 'SKU % not found in tenant', v_rec.sku;
    else
      raise notice 'Profile % not found', v_rec.profile_key;
    end if;
  end loop;
end $$;

-- Verify
select
  p.name as product_name, p.sku, sp.name as profile_name, sp.key, m.status
from service_product_profile_mappings m
join products p on p.id = m.product_id
join service_profiles sp on sp.id = m.service_profile_id
where m.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by p.name;
