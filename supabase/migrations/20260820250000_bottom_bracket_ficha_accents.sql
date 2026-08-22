-- Tildes en el vocabulario del pedalier.
--
-- Escribi las etiquetas y ayudas sin acentos por prudencia de codificacion en
-- la migracion 20260820220000, y salen asi en la ficha real: «Construccion»,
-- «Empieza por aca», «diametro». La base es UTF-8 y el resto del catalogo ya
-- usa tildes; no habia nada que evitar.

begin;

update public.spec_definitions set label = 'Construcción',
  description = 'Cómo está hecho por dentro. No cambia si calza, pero decide si se ajusta, cómo se sirve y qué servicio aplica.',
  updated_at = now()
where key = 'bb_construction' and tenant_id is null;

update public.spec_definitions set
  description = 'Cómo se monta el pedalier al cuadro. Define rosca, diámetro y anchos posibles.',
  updated_at = now()
where key = 'bb_shell_standard' and tenant_id is null;

update public.spec_definitions set
  description = 'Si el producto trae el eje. Un cartucho sellado sí; unas copas externas no, el eje viene con la biela.',
  updated_at = now()
where key = 'includes_spindle' and tenant_id is null;

update public.spec_definitions set
  description = 'Qué ejes admite un pedalier que no trae el suyo. Acepta más de uno: hay copas que sirven para Hollowtech 24/24 y para GXP 22/24.',
  updated_at = now()
where key = 'spindle_interface_accepted' and tenant_id is null;

update public.spec_definitions set
  description = 'Combinación de rosca de las cubetas. El inglés BSA lleva la copa fija a la izquierda; el italiano y buena parte de lo genérico van ambas a la derecha.',
  updated_at = now()
where key = 'bb_cup_thread_pair' and tenant_id is null;

update public.spec_definitions set label = 'Diámetro de cubeta',
  description = 'Diámetro exterior de la cubeta, medido sobre la rosca o el asiento.',
  updated_at = now()
where key = 'bb_cup_outer_diameter_mm' and tenant_id is null;

update public.spec_definitions set label = 'Tamaño de bolita',
  description = 'Diámetro de las bolitas del canastillo, en pulgadas.',
  updated_at = now()
where key = 'bb_ball_size_in' and tenant_id is null;

update public.spec_definitions set
  description = 'Cantidad de bolitas por canastillo. Un canastillo 1/4 x 9 lleva nueve.',
  updated_at = now()
where key = 'bb_ball_count_per_side' and tenant_id is null;

update public.spec_definitions set allowed_values =
  '["Derecha / Izquierda (BSA inglés)","Derecha / Derecha (italiano o genérico)","Sin rosca (a presión)"]'::jsonb,
  updated_at = now()
where key = 'bb_cup_thread_pair' and tenant_id is null;

update public.spec_definitions set allowed_values =
  '["BSA 1.37x24","Italiano 36x24","T47","Francés 35x1","Suizo 35x1",'
  '"Euro BMX roscado 68","BB86 / BB92 41mm","PF30 46mm","BB30 42mm",'
  '"BB386EVO 46mm","BB90 / BB95","BBRight / OSBB","Mid BMX 41.2mm",'
  '"Spanish BMX 37mm","Americano 51.5mm"]'::jsonb,
  updated_at = now()
where key = 'bb_shell_standard' and tenant_id is null;

update public.spec_template_fields tf set helper_text = h.texto, updated_at = now()
from (values
  ('bb_shell_standard', 'Empieza por acá: define la rosca, el diámetro y qué anchos existen.'),
  ('bb_construction', 'Una misma caja BSA acepta cartucho sellado, copa y cono, o copas externas.'),
  ('spindle_interface', 'El eje que este pedalier trae.'),
  ('spindle_interface_accepted', 'Marca todas las que sirven. Hay copas que aceptan 24/24 y 22/24 a la vez.'),
  ('includes_spindle', 'Un cartucho sellado trae el eje; unas copas externas no.'),
  ('bb_shell_diameter_mm', 'En las cajas roscadas manda la rosca, no el diámetro del bore.'),
  ('bb_cup_thread_pair', 'DER/IZQ es el inglés; DER/DER aparece en italiano y en buena parte de lo genérico.'),
  ('bb_ball_size_in', 'Sólo para canastillos de bolitas sueltas.'),
  ('spindle_interface_accepted_cup', 'Marca todas las que sirven.')
) as h(def_key, texto)
join public.spec_definitions d
  on d.key = h.def_key and d.tenant_id is null
where tf.spec_definition_id = d.id
  and tf.helper_text is not null;

update public.spec_template_fields tf set
  helper_text = 'Un eje suelto vive en un sistema de copa y cono.', updated_at = now()
from public.spec_definitions d, public.spec_templates t
where tf.spec_definition_id = d.id and tf.template_id = t.id
  and d.key = 'bb_construction' and t.key = 'bottom_bracket_axle';

commit;
