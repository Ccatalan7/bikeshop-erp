-- La misma cascada para las otras tres plantillas del pedalier.
--
-- `bottom_bracket_cup`, `bottom_bracket_axle` y `bottom_bracket_bearing`
-- quedaron con los campos nuevos pero sin una sola compuerta: los mismos cinco
-- defectos que se corrigieron en `bottom_bracket`. Llenar sus 14 productos
-- antes de esto seria repetir el error.
--
-- `bottom_bracket_bearing` gana raiz propia. La pregunta que decide todo en un
-- rodamiento de motor es de que sistema es: un canastillo de bolas sueltas se
-- describe por tamano y cantidad de bolita; un rodamiento sellado por su
-- codigo y sus tres diametros. Antes los siete campos salian juntos y ninguno
-- dependia de nada.

begin;

update public.spec_template_fields tf set
  visibility_rules = '[]'::jsonb, option_rules = '[]'::jsonb, updated_at = now()
from public.spec_templates t
where tf.template_id = t.id
  and t.key in ('bottom_bracket_cup', 'bottom_bracket_axle',
                'bottom_bracket_bearing');

insert into public.spec_template_fields (
  tenant_id, template_id, spec_definition_id, is_required, section_key,
  sort_order, visibility_rules, option_rules, helper_text
)
select null, t.id, d.id, f.is_required, f.section_key, f.sort_order,
       f.visibility_rules, f.option_rules, f.helper_text
from (values

  -- ── Cubetas: sólo copas, nunca traen eje ────────────────────────────────
  ('bottom_bracket_cup', 'bb_shell_standard', true, 'compatibility', 10,
   '[]'::jsonb, '[]'::jsonb,
   'La caja del cuadro donde entran estas cubetas.'),

  ('bottom_bracket_cup', 'bb_construction', true, 'compatibility', 20,
   '[{"field":"bb_shell_standard","operator":"is_set"}]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","Italiano 36x24","T47","Francés 35x1","Suizo 35x1",'
   '"Euro BMX roscado 68"],"allow":["Copa y cono","Copas externas"]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB30 42mm","BB386EVO 46mm",'
   '"BB90 / BB95","BBRight / OSBB","Mid BMX 41.2mm","Spanish BMX 37mm"],'
   '"allow":["Rodamientos prensados","Thread-together"]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Americano 51.5mm",'
   '"allow":["Copa y cono"]}]'::jsonb,
   'Un juego de cubetas no es un cartucho: o son de bolas, o son copas.'),

  ('bottom_bracket_cup', 'bb_cup_thread_pair', true, 'compatibility', 30,
   '[{"field":"bb_construction","operator":"is_set"},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","Italiano 36x24","T47","Francés 35x1","Suizo 35x1",'
   '"Euro BMX roscado 68","Americano 51.5mm"]}]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","Suizo 35x1"],'
   '"allow":["Derecha / Izquierda (BSA inglés)"]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["Italiano 36x24","T47","Francés 35x1","Euro BMX roscado 68",'
   '"Americano 51.5mm"],'
   '"allow":["Derecha / Derecha (italiano o genérico)"]}]'::jsonb,
   'DER/IZQ es el inglés; DER/DER aparece en italiano y en lo genérico.'),

  ('bottom_bracket_cup', 'spindle_interface_accepted', true, 'compatibility', 40,
   '[{"field":"bb_construction","operator":"is_set"}]'::jsonb,
   '[{"field":"bb_construction","operator":"eq","value":"Copa y cono",'
   '"allow":["Cuadrado JIS","Cuadrado ISO","Con chaveta","One-piece / americano",'
   '"BMX 19mm","BMX 22mm","BMX 24mm"]},'
   '{"field":"bb_construction","operator":"eq","value":"Copas externas",'
   '"allow":["Hollowtech / 24mm","SRAM GXP 24/22","SRAM DUB 28.99mm"]},'
   '{"field":"bb_construction","operator":"in",'
   '"value":["Rodamientos prensados","Thread-together"],'
   '"allow":["Hollowtech / 24mm","SRAM DUB 28.99mm","BB30 30mm",'
   '"SRAM GXP 24/22","BMX 19mm","BMX 22mm","BMX 24mm"]}]'::jsonb,
   'Marca todas las que sirven.'),

  ('bottom_bracket_cup', 'bb_shell_width_mm', false, 'dimensions', 50,
   '[{"field":"bb_shell_standard","operator":"is_set"}]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","T47","Euro BMX roscado 68","Francés 35x1",'
   '"Suizo 35x1","BB30 42mm"],"allow":[68,73,83,100]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Italiano 36x24",'
   '"allow":[70]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["BB86 / BB92 41mm","PF30 46mm","BB386EVO 46mm"],'
   '"allow":[86.5,89.5,92,107,121]},'
   '{"field":"bb_shell_standard","operator":"in",'
   '"value":["Mid BMX 41.2mm","Spanish BMX 37mm","Americano 51.5mm"],'
   '"allow":[68,73]}]'::jsonb, null),

  ('bottom_bracket_cup', 'bb_cup_outer_diameter_mm', false, 'dimensions', 60,
   '[{"field":"bb_construction","operator":"eq","value":"Copa y cono"}]'::jsonb,
   '[{"field":"bb_shell_standard","operator":"in",'
   '"value":["BSA 1.37x24","Italiano 36x24","T47","Francés 35x1","Suizo 35x1",'
   '"Euro BMX roscado 68"],"allow":[34.8,35,36,37]},'
   '{"field":"bb_shell_standard","operator":"eq","value":"Americano 51.5mm",'
   '"allow":[51.5]}]'::jsonb,
   'Se mide sobre la rosca. 34,8 mm es el inglés corriente.'),

  -- ── Ejes sueltos: todo el producto es el eje ────────────────────────────
  ('bottom_bracket_axle', 'bb_construction', true, 'compatibility', 10,
   '[]'::jsonb,
   '[{"allow":["Copa y cono","Cartucho sellado"]}]'::jsonb,
   'Un eje suelto se vende para un sistema de bolas o para reponer un cartucho.'),

  ('bottom_bracket_axle', 'spindle_interface', true, 'compatibility', 20,
   '[{"field":"bb_construction","operator":"is_set"}]'::jsonb,
   '[{"field":"bb_construction","operator":"eq","value":"Copa y cono",'
   '"allow":["Cuadrado JIS","Cuadrado ISO","Con chaveta","BMX 19mm",'
   '"BMX 22mm","BMX 24mm"]},'
   '{"field":"bb_construction","operator":"eq","value":"Cartucho sellado",'
   '"allow":["Cuadrado JIS","Cuadrado ISO","ISIS","Octalink","Powerspline"]}]'::jsonb,
   null),

  ('bottom_bracket_axle', 'spindle_length_mm', false, 'dimensions', 30,
   '[{"field":"spindle_interface","operator":"is_set"}]'::jsonb,
   '[{"field":"spindle_interface","operator":"in",'
   '"value":["Cuadrado JIS","Cuadrado ISO"],'
   '"allow":[103,107,110,110.5,113,113.5,116,118,118.5,119,121,122.5,124,'
   '124.5,125,125.5,126,127,127.5,128]},'
   '{"field":"spindle_interface","operator":"eq","value":"Con chaveta",'
   '"allow":[127.5,131,135,140,145,147]},'
   '{"field":"spindle_interface","operator":"in",'
   '"value":["BMX 19mm","BMX 22mm","BMX 24mm"],"allow":[128,131,135]},'
   '{"field":"spindle_interface","operator":"eq","value":"ISIS",'
   '"allow":[108,113,118]},'
   '{"field":"spindle_interface","operator":"eq","value":"Octalink",'
   '"allow":[109,113,118]},'
   '{"field":"spindle_interface","operator":"eq","value":"Powerspline",'
   '"allow":[108,113,118]}]'::jsonb, null),

  ('bottom_bracket_axle', 'spindle_diameter_mm', false, 'dimensions', 40,
   '[{"field":"spindle_interface","operator":"in",'
   '"value":["BMX 19mm","BMX 22mm","BMX 24mm"]}]'::jsonb,
   '[{"field":"spindle_interface","operator":"eq","value":"BMX 19mm","allow":[19]},'
   '{"field":"spindle_interface","operator":"eq","value":"BMX 22mm","allow":[22]},'
   '{"field":"spindle_interface","operator":"eq","value":"BMX 24mm","allow":[24]}]'::jsonb,
   null),

  -- ── Rodamientos: la raíz es de qué sistema son ──────────────────────────
  ('bottom_bracket_bearing', 'bb_construction', true, 'compatibility', 10,
   '[]'::jsonb,
   '[{"allow":["Copa y cono","Cartucho sellado","Rodamientos prensados"]}]'::jsonb,
   'Un canastillo de bolas y un rodamiento sellado no se describen igual.'),

  ('bottom_bracket_bearing', 'bb_ball_size_in', true, 'identification', 20,
   '[{"field":"bb_construction","operator":"eq","value":"Copa y cono"}]'::jsonb,
   '[]'::jsonb,
   'Sólo los canastillos de bolas sueltas.'),

  ('bottom_bracket_bearing', 'bb_ball_count_per_side', true, 'identification', 30,
   '[{"field":"bb_construction","operator":"eq","value":"Copa y cono"}]'::jsonb,
   '[]'::jsonb,
   'Un canastillo 1/4 x 9 lleva nueve por lado.'),

  ('bottom_bracket_bearing', 'bearing_size_code', true, 'identification', 40,
   '[{"field":"bb_construction","operator":"in",'
   '"value":["Cartucho sellado","Rodamientos prensados"]}]'::jsonb,
   '[]'::jsonb,
   'El código comercial, por ejemplo 6805 o 163110.'),

  ('bottom_bracket_bearing', 'bearing_inner_diameter_mm', false, 'dimensions', 50,
   '[{"field":"bb_construction","operator":"in",'
   '"value":["Cartucho sellado","Rodamientos prensados"]}]'::jsonb,
   '[]'::jsonb, null),

  ('bottom_bracket_bearing', 'bearing_outer_diameter_mm', false, 'dimensions', 60,
   '[{"field":"bb_construction","operator":"in",'
   '"value":["Cartucho sellado","Rodamientos prensados"]}]'::jsonb,
   '[]'::jsonb, null),

  ('bottom_bracket_bearing', 'bb_bearing_width_mm', false, 'dimensions', 70,
   '[{"field":"bb_construction","operator":"in",'
   '"value":["Cartucho sellado","Rodamientos prensados"]}]'::jsonb,
   '[]'::jsonb, null),

  ('bottom_bracket_bearing', 'spindle_diameter_mm', false, 'dimensions', 80,
   '[{"field":"bb_construction","operator":"is_set"}]'::jsonb,
   '[]'::jsonb,
   'Diámetro del eje que este rodamiento acepta.')

) as f(
  template_key, def_key, is_required, section_key, sort_order,
  visibility_rules, option_rules, helper_text
)
join public.spec_templates t on t.key = f.template_key and t.tenant_id is null
join public.spec_definitions d on d.key = f.def_key and d.tenant_id is null
on conflict (template_id, spec_definition_id) do update set
  is_required = excluded.is_required,
  section_key = excluded.section_key,
  sort_order = excluded.sort_order,
  visibility_rules = excluded.visibility_rules,
  option_rules = excluded.option_rules,
  helper_text = excluded.helper_text,
  updated_at = now();

commit;
