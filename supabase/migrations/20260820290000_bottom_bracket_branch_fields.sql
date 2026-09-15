-- La respuesta trae su rama: la ficha se compone, no sólo se recorta.
--
-- Hasta acá la cascada era sustractiva. Las respuestas escondían campos y
-- acotaban opciones sobre una lista fija de nueve. Elegir «Copa y cono» no
-- abría ni una pregunta nueva, y las preguntas que esa rama necesita — la mano
-- de la rosca DER/IZQ, el tamaño de bolita, cuántas por lado — existían sólo
-- en `bottom_bracket_cup` y `bottom_bracket_bearing`. Un motor de la categoría
-- `Motor` no podía llegar a ellas nunca, aunque el mecánico declarara que es
-- de bolas sueltas.
--
-- La disciplina que evita que esto se vuelva un cajón de sastre: un campo entra
-- a una rama sólo si esa rama lo necesita para decidir compatibilidad o
-- servicio. La mano de la rosca decide si la cubeta entra; el tamaño y la
-- cantidad de bolitas deciden qué canastillo se vende; el stack de espaciadores
-- decide si unas copas externas de 68 calzan en un cuadro de 73.
--
-- Efecto en el pedalier BSA: 3 campos sin construcción contestada, 5 con
-- cartucho sellado, 7 con copas externas, 8 con copa y cono.

begin;

insert into public.spec_definitions (
  tenant_id, key, label, description, data_type, unit,
  allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, group_name, sort_order
) values
  (null, 'bb_spacer_stack_mm', 'Espaciadores incluidos',
   'Milímetros de espaciador que trae el juego. Unas copas externas de 68 mm necesitan 2,5 mm por lado; en un cuadro de 73 mm van sin ellos.',
   'number', 'mm', '[0,2.5,5]'::jsonb, '{"min":0,"max":10}'::jsonb,
   true, false, true, true, true, 'Pedalier', 72)
on conflict (key) where tenant_id is null do update set
  label = excluded.label,
  description = excluded.description,
  data_type = excluded.data_type,
  unit = excluded.unit,
  allowed_values = excluded.allowed_values,
  validation_rules = excluded.validation_rules,
  is_filterable = excluded.is_filterable,
  is_compatibility_relevant = excluded.is_compatibility_relevant,
  group_name = excluded.group_name,
  sort_order = excluded.sort_order,
  updated_at = now();

update public.spec_template_fields tf set
  visibility_rules = '[]'::jsonb, option_rules = '[]'::jsonb, updated_at = now()
from public.spec_templates t
where tf.template_id = t.id and t.key = 'bottom_bracket';

insert into public.spec_template_fields (
  tenant_id, template_id, spec_definition_id, is_required, section_key,
  sort_order, visibility_rules, option_rules
)
select null, t.id, d.id, f.is_required, f.section_key, f.sort_order,
       f.visibility_rules, f.option_rules
from (values
  ('bottom_bracket', 'bb_shell_standard', true, 'compatibility', 10,
   '[]'::jsonb,
   '[]'::jsonb),
  ('bottom_bracket', 'bb_construction', true, 'compatibility', 20,
   '[{"field": "bb_shell_standard", "operator": "is_set"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": ["Cartucho sellado", "Copas externas", "Copa y cono"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB30 42mm", "BB386EVO 46mm", "BB90 / BB95", "BBRight / OSBB"], "allow": ["Rodamientos prensados", "Thread-together"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Mid BMX 41.2mm", "Spanish BMX 37mm"], "allow": ["Cartucho sellado", "Rodamientos prensados"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Americano 51.5mm"], "allow": ["Copa y cono"]}]'::jsonb),
  ('bottom_bracket', 'includes_spindle', true, 'compatibility', 30,
   '[{"field": "bb_construction", "operator": "is_set"}]'::jsonb,
   '[]'::jsonb),
  ('bottom_bracket', 'spindle_interface', false, 'compatibility', 40,
   '[{"field": "includes_spindle", "operator": "eq", "value": true}]'::jsonb,
   '[{"field": "bb_construction", "operator": "eq", "value": "Cartucho sellado", "allow": ["Cuadrado JIS", "Cuadrado ISO", "ISIS", "Octalink", "Powerspline", "BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_construction", "operator": "eq", "value": "Copas externas", "allow": ["Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm"]}, {"field": "bb_construction", "operator": "eq", "value": "Copa y cono", "allow": ["Cuadrado JIS", "Cuadrado ISO", "Con chaveta", "One-piece / americano"]}, {"field": "bb_construction", "operator": "in", "value": ["Rodamientos prensados", "Thread-together"], "allow": ["Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22", "BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": ["Cuadrado JIS", "Cuadrado ISO", "ISIS", "Octalink", "Powerspline", "Con chaveta", "Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB30 42mm", "BB386EVO 46mm", "BB90 / BB95", "BBRight / OSBB"], "allow": ["Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Mid BMX 41.2mm", "Spanish BMX 37mm"], "allow": ["BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Americano 51.5mm"], "allow": ["One-piece / americano"]}]'::jsonb),
  ('bottom_bracket', 'spindle_interface_accepted', false, 'compatibility', 50,
   '[{"field": "includes_spindle", "operator": "eq", "value": false}]'::jsonb,
   '[{"field": "bb_construction", "operator": "eq", "value": "Copas externas", "allow": ["Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm"]}, {"field": "bb_construction", "operator": "in", "value": ["Rodamientos prensados", "Thread-together"], "allow": ["Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22", "BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_construction", "operator": "eq", "value": "Cartucho sellado", "allow": ["Cuadrado JIS", "Cuadrado ISO", "ISIS", "Octalink", "Powerspline", "BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_construction", "operator": "eq", "value": "Copa y cono", "allow": ["Cuadrado JIS", "Cuadrado ISO", "Con chaveta", "One-piece / americano"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": ["Cuadrado JIS", "Cuadrado ISO", "ISIS", "Octalink", "Powerspline", "Con chaveta", "Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB30 42mm", "BB386EVO 46mm", "BB90 / BB95", "BBRight / OSBB"], "allow": ["Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Mid BMX 41.2mm", "Spanish BMX 37mm"], "allow": ["BMX 19mm", "BMX 22mm", "BMX 24mm"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Americano 51.5mm"], "allow": ["One-piece / americano"]}]'::jsonb),
  ('bottom_bracket', 'bb_cup_thread_pair', false, 'compatibility', 60,
   '[{"field": "bb_construction", "operator": "in", "value": ["Copa y cono", "Copas externas"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"]}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "eq", "value": "BSA 1.37x24", "allow": ["Derecha / Izquierda (BSA inglés)"]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Italiano 36x24", "T47", "Francés 35x1", "Euro BMX roscado 68"], "allow": ["Derecha / Derecha (italiano o genérico)"]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Suizo 35x1", "allow": ["Derecha / Izquierda (BSA inglés)"]}]'::jsonb),
  ('bottom_bracket', 'bb_shell_width_mm', false, 'dimensions', 70,
   '[{"field": "bb_shell_standard", "operator": "is_set"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "T47", "Euro BMX roscado 68", "Francés 35x1", "Suizo 35x1", "BB30 42mm"], "allow": [68, 73, 83, 100]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Italiano 36x24", "allow": [70]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB386EVO 46mm"], "allow": [86.5, 89.5, 92, 107, 121]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB90 / BB95", "BBRight / OSBB"], "allow": [86.5, 89.5, 92]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Mid BMX 41.2mm", "Spanish BMX 37mm", "Americano 51.5mm"], "allow": [68, 73]}]'::jsonb),
  ('bottom_bracket', 'bb_shell_diameter_mm', false, 'dimensions', 80,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB30 42mm", "BB386EVO 46mm", "BB90 / BB95", "BBRight / OSBB", "Mid BMX 41.2mm", "Spanish BMX 37mm", "Americano 51.5mm"]}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "BB90 / BB95"], "allow": [41]}, {"field": "bb_shell_standard", "operator": "in", "value": ["PF30 46mm", "BB386EVO 46mm", "BBRight / OSBB"], "allow": [42, 46]}, {"field": "bb_shell_standard", "operator": "eq", "value": "BB30 42mm", "allow": [42]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Mid BMX 41.2mm", "allow": [41.2]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Spanish BMX 37mm", "allow": [37]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Americano 51.5mm", "allow": [51.5]}]'::jsonb),
  ('bottom_bracket', 'bb_cup_outer_diameter_mm', false, 'dimensions', 90,
   '[{"field": "bb_construction", "operator": "eq", "value": "Copa y cono"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": [34.8, 35, 36, 37]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Americano 51.5mm", "allow": [51.5]}]'::jsonb),
  ('bottom_bracket', 'spindle_length_mm', false, 'dimensions', 100,
   '[{"field": "includes_spindle", "operator": "eq", "value": true}, {"field": "spindle_interface", "operator": "not_in", "value": ["Hollowtech / 24mm", "SRAM GXP 24/22", "SRAM DUB 28.99mm", "BB30 30mm", "One-piece / americano"]}]'::jsonb,
   '[{"field": "spindle_interface", "operator": "in", "value": ["Cuadrado JIS", "Cuadrado ISO"], "allow": [103, 107, 110, 110.5, 113, 113.5, 116, 118, 118.5, 119, 121, 122.5, 124, 124.5, 125, 125.5, 126, 127, 127.5, 128]}, {"field": "spindle_interface", "operator": "eq", "value": "ISIS", "allow": [108, 113, 118]}, {"field": "spindle_interface", "operator": "eq", "value": "Octalink", "allow": [109, 113, 118]}, {"field": "spindle_interface", "operator": "eq", "value": "Powerspline", "allow": [108, 113, 118]}, {"field": "spindle_interface", "operator": "in", "value": ["BMX 19mm", "BMX 22mm", "BMX 24mm"], "allow": [128, 131, 135]}, {"field": "spindle_interface", "operator": "eq", "value": "Con chaveta", "allow": [127.5, 131, 135, 140, 145, 147]}]'::jsonb),
  ('bottom_bracket', 'spindle_diameter_mm', false, 'dimensions', 110,
   '[{"field": "includes_spindle", "operator": "eq", "value": true}, {"field": "spindle_interface", "operator": "in", "value": ["BMX 19mm", "BMX 22mm", "BMX 24mm", "Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22"]}]'::jsonb,
   '[{"field": "spindle_interface", "operator": "eq", "value": "BMX 19mm", "allow": [19]}, {"field": "spindle_interface", "operator": "eq", "value": "BMX 22mm", "allow": [22]}, {"field": "spindle_interface", "operator": "eq", "value": "BMX 24mm", "allow": [24]}, {"field": "spindle_interface", "operator": "eq", "value": "Hollowtech / 24mm", "allow": [24]}, {"field": "spindle_interface", "operator": "eq", "value": "SRAM DUB 28.99mm", "allow": [28.99]}, {"field": "spindle_interface", "operator": "eq", "value": "BB30 30mm", "allow": [30]}, {"field": "spindle_interface", "operator": "eq", "value": "SRAM GXP 24/22", "allow": [24]}]'::jsonb),
  ('bottom_bracket', 'bb_spacer_stack_mm', false, 'dimensions', 120,
   '[{"field": "bb_construction", "operator": "eq", "value": "Copas externas"}]'::jsonb,
   '[{"field": "bb_shell_width_mm", "operator": "eq", "value": 68, "allow": [2.5, 5]}, {"field": "bb_shell_width_mm", "operator": "eq", "value": 73, "allow": [0, 2.5]}, {"field": "bb_shell_width_mm", "operator": "eq", "value": 83, "allow": [0]}]'::jsonb),
  ('bottom_bracket', 'bb_ball_size_in', false, 'identification', 130,
   '[{"field": "bb_construction", "operator": "eq", "value": "Copa y cono"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": ["1/4"]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Americano 51.5mm", "allow": ["1/4"]}]'::jsonb),
  ('bottom_bracket', 'bb_ball_count_per_side', false, 'identification', 140,
   '[{"field": "bb_construction", "operator": "eq", "value": "Copa y cono"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "Italiano 36x24", "T47", "Francés 35x1", "Suizo 35x1", "Euro BMX roscado 68"], "allow": [9, 11]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Americano 51.5mm", "allow": [9, 11]}]'::jsonb),
  ('bottom_bracket', 'bearing_size_code', false, 'identification', 150,
   '[{"field": "bb_construction", "operator": "in", "value": ["Copas externas", "Rodamientos prensados", "Thread-together", "Cartucho sellado"]}]'::jsonb,
   '[]'::jsonb)
) as f(
  template_key, def_key, is_required, section_key, sort_order,
  visibility_rules, option_rules
)
join public.spec_templates t on t.key = f.template_key and t.tenant_id is null
join public.spec_definitions d on d.key = f.def_key and d.tenant_id is null
on conflict (template_id, spec_definition_id) do update set
  is_required = excluded.is_required,
  section_key = excluded.section_key,
  sort_order = excluded.sort_order,
  visibility_rules = excluded.visibility_rules,
  option_rules = excluded.option_rules,
  updated_at = now();

commit;
