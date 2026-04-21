-- Safe Viñabike wheel/headset product spec seed
--
-- Only writes facts that are explicit in the live product names.
-- No inferred widths, ERD, eyelet type variants, or material are written unless
-- the product name states them directly.

with spec_defs as (
  select key, id, data_type
  from public.spec_definitions
  where tenant_id is null
), desired_specs as (
  select * from (
    values
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '4109cd4b-c958-4bd3-9d60-4d14f47a8c6c'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '27.5"', '27.5"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '4109cd4b-c958-4bd3-9d60-4d14f47a8c6c'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '28', '28'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'df1bbb6b-35c7-439c-aaeb-0df23114c279'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '27.5"', '27.5"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'df1bbb6b-35c7-439c-aaeb-0df23114c279'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '32', '32'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'df1bbb6b-35c7-439c-aaeb-0df23114c279'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Schrader', 'Schrader'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cd71aafd-bbd3-4aa4-8914-fa7271b2b776'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '29"', '29"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cd71aafd-bbd3-4aa4-8914-fa7271b2b776'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '32', '32'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cd71aafd-bbd3-4aa4-8914-fa7271b2b776'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cd71aafd-bbd3-4aa4-8914-fa7271b2b776'::uuid, 'rim_tubeless_ready', null::text, null::numeric, true, null::text, 'Sí'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '973c0173-c96b-4256-9881-4a14976e847c'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '29"', '29"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '973c0173-c96b-4256-9881-4a14976e847c'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '32', '32'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '973c0173-c96b-4256-9881-4a14976e847c'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Schrader', 'Schrader'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '973c0173-c96b-4256-9881-4a14976e847c'::uuid, 'rim_tubeless_ready', null::text, null::numeric, true, null::text, 'Sí'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '973c0173-c96b-4256-9881-4a14976e847c'::uuid, 'rim_etrto', '622x30', null::numeric, null::boolean, null::text, '622x30'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '5e6f5566-cb6f-45a3-9ad4-566db7124910'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '26"', '26"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '5e6f5566-cb6f-45a3-9ad4-566db7124910'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '32', '32'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '5e6f5566-cb6f-45a3-9ad4-566db7124910'::uuid, 'rim_material', null::text, null::numeric, null::boolean, 'Aluminio', 'Aluminio'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '5e6f5566-cb6f-45a3-9ad4-566db7124910'::uuid, 'rim_wall_type', null::text, null::numeric, null::boolean, 'Doble pared', 'Doble pared'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'e12ec06b-b74b-4867-9119-916d1f29f83d'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '26"', '26"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'e12ec06b-b74b-4867-9119-916d1f29f83d'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '36', '36'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'e12ec06b-b74b-4867-9119-916d1f29f83d'::uuid, 'rim_material', null::text, null::numeric, null::boolean, 'Aluminio', 'Aluminio'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'e12ec06b-b74b-4867-9119-916d1f29f83d'::uuid, 'rim_wall_type', null::text, null::numeric, null::boolean, 'Pared simple', 'Pared simple'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '31a2996f-766e-45a2-8845-76b24296c8b9'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '20"', '20"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '31a2996f-766e-45a2-8845-76b24296c8b9'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Schrader', 'Schrader'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '31a2996f-766e-45a2-8845-76b24296c8b9'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '35', '35'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '45df83b1-a80d-4cb5-a18c-be38f07fa578'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '26"', '26"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '45df83b1-a80d-4cb5-a18c-be38f07fa578'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '45df83b1-a80d-4cb5-a18c-be38f07fa578'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '48', '48'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '92ffa066-65d0-46aa-992b-66534369539c'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '700c', '700c'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '92ffa066-65d0-46aa-992b-66534369539c'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '92ffa066-65d0-46aa-992b-66534369539c'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '48', '48'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'fe2d8c63-da9c-4bf1-b65a-0d5125dbf5ea'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '29"', '29"'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'fe2d8c63-da9c-4bf1-b65a-0d5125dbf5ea'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'fe2d8c63-da9c-4bf1-b65a-0d5125dbf5ea'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '48', '48'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'ec6ef4d0-6c00-4630-bb4a-ba00f6104e67'::uuid, 'wheel_size', null::text, null::numeric, null::boolean, '26"', '26"'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '2f3aa1f5-17ee-42bf-9495-5a1f741bed38'::uuid, 'sealant_volume_ml', null::text, 1000::numeric, null::boolean, null::text, '1000'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'd1645285-9149-49e7-8c21-839654410cd8'::uuid, 'spoke_length_mm', null::text, 265::numeric, null::boolean, null::text, '265'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'd1645285-9149-49e7-8c21-839654410cd8'::uuid, 'spoke_gauge', null::text, null::numeric, null::boolean, '14G', '14G'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '42b125fe-9bae-430a-bb34-47372057fdf6'::uuid, 'spoke_length_mm', null::text, 292::numeric, null::boolean, null::text, '292'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '42b125fe-9bae-430a-bb34-47372057fdf6'::uuid, 'spoke_gauge', null::text, null::numeric, null::boolean, '14G', '14G'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '42b125fe-9bae-430a-bb34-47372057fdf6'::uuid, 'spoke_bend_type', null::text, null::numeric, null::boolean, 'J-Bend', 'J-Bend'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '047a7046-2166-4549-b70f-bb5fa103e67c'::uuid, 'wheel_position', null::text, null::numeric, null::boolean, 'Delantera', 'Delantera'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '047a7046-2166-4549-b70f-bb5fa103e67c'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '36', '36'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '047a7046-2166-4549-b70f-bb5fa103e67c'::uuid, 'hub_spacing_mm', null::text, null::numeric, null::boolean, '100', '100'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cc828965-0efc-4d84-b589-99ae863b3faa'::uuid, 'wheel_position', null::text, null::numeric, null::boolean, 'Trasera', 'Trasera'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cc828965-0efc-4d84-b589-99ae863b3faa'::uuid, 'spoke_holes', null::text, null::numeric, null::boolean, '32', '32'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cc828965-0efc-4d84-b589-99ae863b3faa'::uuid, 'hub_spacing_mm', null::text, null::numeric, null::boolean, '135', '135'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'cc828965-0efc-4d84-b589-99ae863b3faa'::uuid, 'freehub_type', null::text, null::numeric, null::boolean, 'Micro Spline', 'Micro Spline'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'a6cf0009-8f8f-4eb5-91ef-b6937139ee81'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Schrader', 'Schrader'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'a6cf0009-8f8f-4eb5-91ef-b6937139ee81'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '40', '40'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '213fdc9e-5377-4988-9f3a-fe6f24480afc'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '213fdc9e-5377-4988-9f3a-fe6f24480afc'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '60', '60'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '59351c5c-a2bc-49ea-a6b7-c85c4c723c71'::uuid, 'valve_type', null::text, null::numeric, null::boolean, 'Presta', 'Presta'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '59351c5c-a2bc-49ea-a6b7-c85c4c723c71'::uuid, 'valve_length_mm', null::text, null::numeric, null::boolean, '40', '40'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '53f27b2f-1099-4081-8ac0-af9b7e116c01'::uuid, 'headset_standard', null::text, null::numeric, null::boolean, 'Semi-integrado', 'Semi-integrado'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '53f27b2f-1099-4081-8ac0-af9b7e116c01'::uuid, 'steerer_type', null::text, null::numeric, null::boolean, '1 1/8" recto', '1 1/8" recto'),

      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, '2655a0a4-cd2a-42d9-8475-2e4cac6102eb'::uuid, 'headset_standard', null::text, null::numeric, null::boolean, 'Semi-integrado', 'Semi-integrado'),
      ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'c759234b-5545-418f-9582-849f794d891b'::uuid, 'steerer_type', null::text, null::numeric, null::boolean, '1 1/8" recto', '1 1/8" recto')
  ) as v(tenant_id, product_id, spec_key, value_text, value_number, value_boolean, value_option, display_value)
)
insert into public.product_spec_values (
  tenant_id,
  product_id,
  spec_definition_id,
  value_text,
  value_number,
  value_boolean,
  value_option,
  display_value,
  updated_at
)
select
  ds.tenant_id,
  ds.product_id,
  sd.id,
  ds.value_text,
  ds.value_number,
  ds.value_boolean,
  ds.value_option,
  ds.display_value,
  now()
from desired_specs ds
join spec_defs sd on sd.key = ds.spec_key
on conflict (tenant_id, product_id, spec_definition_id) do update
set value_text = excluded.value_text,
    value_number = excluded.value_number,
    value_boolean = excluded.value_boolean,
    value_option = excluded.value_option,
    display_value = excluded.display_value,
    updated_at = now();
