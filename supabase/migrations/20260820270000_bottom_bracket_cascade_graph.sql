-- Cascada del pedalier: el grafo completo de dependencias.
--
-- La version anterior (20260820220000) implemento el acotado de opciones pero
-- casi nada del compuerteo, y eso permitia estados que no existen. Auditados
-- los nueve campos, habia cinco defectos reales:
--
--   1. `bb_construction` salia sin caja elegida. Una caja Pressfit no puede
--      ser «Cartucho sellado», pero sin caja la lista ofrecia las cinco.
--   2. Con caja BSA no se acotaba nada: ofrecia «Rodamientos prensados» y
--      «Thread-together», imposibles en una caja roscada.
--   3. `includes_spindle` estaba en el puesto 40 y condicionaba los campos 30
--      y 35: la pregunta que abre la compuerta se hacia despues de los campos
--      que dependen de ella.
--   4. `includes_spindle` tampoco dependia de la construccion.
--   5. `bb_shell_width_mm` salia sin caja elegida, y T47, frances, suizo,
--      BB90/95 y BBRight no acotaban ningun ancho.
--
-- El grafo de aca sale de simular las 15 cajas: 70 combinaciones alcanzables,
-- ninguna vacia y ningun campo que quede ofreciendo su vocabulario entero.
-- `spec_cascade_bottom_bracket_test.dart` corre esa misma simulacion.
--
-- `is_set` / `not_set` son operadores nuevos del evaluador: significan «esta
-- pregunta ya fue contestada», que es lo que necesita cada paso despues del
-- primero.

begin;

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
  ('bottom_bracket', 'bb_shell_width_mm', false, 'dimensions', 60,
   '[{"field": "bb_shell_standard", "operator": "is_set"}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BSA 1.37x24", "T47", "Euro BMX roscado 68", "Francés 35x1", "Suizo 35x1", "BB30 42mm"], "allow": [68, 73, 83, 100]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Italiano 36x24", "allow": [70]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB386EVO 46mm"], "allow": [86.5, 89.5, 92, 107, 121]}, {"field": "bb_shell_standard", "operator": "in", "value": ["BB90 / BB95", "BBRight / OSBB"], "allow": [86.5, 89.5, 92]}, {"field": "bb_shell_standard", "operator": "in", "value": ["Mid BMX 41.2mm", "Spanish BMX 37mm", "Americano 51.5mm"], "allow": [68, 73]}]'::jsonb),
  ('bottom_bracket', 'bb_shell_diameter_mm', false, 'dimensions', 70,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "PF30 46mm", "BB30 42mm", "BB386EVO 46mm", "BB90 / BB95", "BBRight / OSBB", "Mid BMX 41.2mm", "Spanish BMX 37mm", "Americano 51.5mm"]}]'::jsonb,
   '[{"field": "bb_shell_standard", "operator": "in", "value": ["BB86 / BB92 41mm", "BB90 / BB95"], "allow": [41]}, {"field": "bb_shell_standard", "operator": "in", "value": ["PF30 46mm", "BB386EVO 46mm", "BBRight / OSBB"], "allow": [42, 46]}, {"field": "bb_shell_standard", "operator": "eq", "value": "BB30 42mm", "allow": [42]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Mid BMX 41.2mm", "allow": [41.2]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Spanish BMX 37mm", "allow": [37]}, {"field": "bb_shell_standard", "operator": "eq", "value": "Americano 51.5mm", "allow": [51.5]}]'::jsonb),
  ('bottom_bracket', 'spindle_length_mm', false, 'dimensions', 80,
   '[{"field": "includes_spindle", "operator": "eq", "value": true}, {"field": "spindle_interface", "operator": "in", "value": ["Cuadrado JIS", "Cuadrado ISO", "ISIS", "Octalink", "Powerspline", "Con chaveta", "BMX 19mm", "BMX 22mm", "BMX 24mm"]}]'::jsonb,
   '[{"field": "spindle_interface", "operator": "in", "value": ["Cuadrado JIS", "Cuadrado ISO"], "allow": [103, 107, 110, 110.5, 113, 113.5, 116, 118, 118.5, 119, 121, 122.5, 124, 124.5, 125, 125.5, 126, 127, 127.5, 128]}, {"field": "spindle_interface", "operator": "eq", "value": "ISIS", "allow": [108, 113, 118]}, {"field": "spindle_interface", "operator": "eq", "value": "Octalink", "allow": [109, 113, 118]}, {"field": "spindle_interface", "operator": "eq", "value": "Powerspline", "allow": [108, 113, 118]}, {"field": "spindle_interface", "operator": "in", "value": ["BMX 19mm", "BMX 22mm", "BMX 24mm"], "allow": [128, 131, 135]}, {"field": "spindle_interface", "operator": "eq", "value": "Con chaveta", "allow": [127.5, 131, 135, 140, 145, 147]}]'::jsonb),
  ('bottom_bracket', 'spindle_diameter_mm', false, 'dimensions', 90,
   '[{"field": "includes_spindle", "operator": "eq", "value": true}, {"field": "spindle_interface", "operator": "in", "value": ["BMX 19mm", "BMX 22mm", "BMX 24mm", "Hollowtech / 24mm", "SRAM DUB 28.99mm", "BB30 30mm", "SRAM GXP 24/22"]}]'::jsonb,
   '[{"field": "spindle_interface", "operator": "eq", "value": "BMX 19mm", "allow": [19]}, {"field": "spindle_interface", "operator": "eq", "value": "BMX 22mm", "allow": [22]}, {"field": "spindle_interface", "operator": "eq", "value": "BMX 24mm", "allow": [24]}, {"field": "spindle_interface", "operator": "eq", "value": "Hollowtech / 24mm", "allow": [24]}, {"field": "spindle_interface", "operator": "eq", "value": "SRAM DUB 28.99mm", "allow": [28.99]}, {"field": "spindle_interface", "operator": "eq", "value": "BB30 30mm", "allow": [30]}, {"field": "spindle_interface", "operator": "eq", "value": "SRAM GXP 24/22", "allow": [24]}]'::jsonb)

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

-- Largos que las reglas ofrecen y el vocabulario no tenia: 108 mm es el ISIS
-- habitual, 109 mm el Octalink, y los ejes con chaveta llegan mas arriba que
-- cualquier cono cuadrado. Sin esto se puede elegir un valor que despues no
-- guarda; lo caza `afirma_opciones_dentro_del_vocabulario`.
update public.spec_definitions set
  allowed_values =
    '[103,107,108,109,110,110.5,113,113.5,116,118,118.5,119,121,122.5,124,'
    '124.5,125,125.5,126,127,127.5,128,131,135,140,145,147]'::jsonb,
  updated_at = now()
where key = 'spindle_length_mm' and tenant_id is null;

commit;
