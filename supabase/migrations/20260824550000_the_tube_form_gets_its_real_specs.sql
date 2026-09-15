-- La ficha de una cámara: ancho, sellante y material.
--
-- El formulario `tube` tenía tres campos —medida de rueda, tipo y largo de
-- válvula— y le faltaba justo lo que decide si una cámara sirve: **el rango de
-- ancho**. Con eso, «¿esta cámara sirve para un neumático 2.1?» se contesta con
-- aritmética en vez de calzando texto.
--
-- **El ancho va como número, no como lista.** Medido contra el catálogo real:
-- 45 pares distintos de ancho en 120 cámaras, y crecen con cada compra. Pero la
-- razón de fondo no es la cantidad: el ancho de una cámara es un **rango
-- medido**, y una medida nunca es un modelo. Una lista obligaría a editar el
-- esquema cada vez que un proveedor traiga 1.75/2.10, y `1.95/2.125` nunca
-- calzaría con `1.95 a 2.125` escrito de otra forma.
--
-- Va en pulgadas para MTB/BMX y en milímetros para ruta —700c se vende como
-- `18/25C`—, siguiendo la separación que el esquema ya hace con `tire_width_in`
-- y `tire_width_mm`. Una cámara llena un par o el otro, en la unidad en que se
-- vende.
--
-- El material queda con TPU y látex desde ya, aunque hoy el taller no tenga
-- ninguna: cuando compre, el valor ya existe y nadie tiene que tocar el
-- esquema para registrarla.

begin;

-- El único parcial es `unique (key) where tenant_id is null`, así que la
-- reentrada va por `not exists` y no por `on conflict (key)`.
insert into public.spec_definitions (
  tenant_id, key, label, description, data_type, unit,
  allowed_values, validation_rules,
  is_filterable, is_required_by_default, is_compatibility_relevant,
  is_customer_visible, is_mechanic_visible, group_name, sort_order
)
select null, nueva.key, nueva.label, nueva.description, nueva.data_type,
  nueva.unit, nueva.allowed_values, nueva.validation_rules,
  nueva.is_filterable, false, nueva.is_compatibility_relevant,
  true, true, nueva.group_name, nueva.sort_order
from (values
  ('tube_width_min_in', 'Ancho mínimo (pulgadas)',
   'El extremo angosto del rango que cubre la cámara.',
   'number', 'in', '[]'::jsonb, '{"min": 0.5, "max": 6}'::jsonb,
   true, true, 'Dimensiones', 30),
  ('tube_width_max_in', 'Ancho máximo (pulgadas)',
   'El extremo ancho del rango que cubre la cámara.',
   'number', 'in', '[]'::jsonb, '{"min": 0.5, "max": 6}'::jsonb,
   true, true, 'Dimensiones', 31),
  ('tube_width_min_mm', 'Ancho mínimo (mm)',
   'El extremo angosto del rango, para cámaras de ruta que se venden en mm.',
   'number', 'mm', '[]'::jsonb, '{"min": 10, "max": 120}'::jsonb,
   true, true, 'Dimensiones', 32),
  ('tube_width_max_mm', 'Ancho máximo (mm)',
   'El extremo ancho del rango, para cámaras de ruta que se venden en mm.',
   'number', 'mm', '[]'::jsonb, '{"min": 10, "max": 120}'::jsonb,
   true, true, 'Dimensiones', 33),
  ('tube_has_sealant', 'Trae líquido sellante',
   'Autosellante o anti-pinchazo: viene con líquido adentro de fábrica.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, 'Construcción', 40),
  ('tube_material', 'Material de la cámara',
   'Butilo es lo normal. TPU y látex quedan disponibles para cuando se compren.',
   'single_select', null,
   '["Butilo", "TPU", "Látex", "Otro"]'::jsonb, '{}'::jsonb,
   true, false, 'Construcción', 41)
) as nueva(key, label, description, data_type, unit, allowed_values,
  validation_rules, is_filterable, is_compatibility_relevant, group_name,
  sort_order)
where not exists (
  select 1 from public.spec_definitions existente
  where existente.tenant_id is null and existente.key = nueva.key
);

-- El vocabulario del material va también en `spec_definition_values`, que es de
-- donde la interfaz saca los códigos estables: `allowed_values` lleva la
-- etiqueta, esta tabla lleva el código con el que se guarda.
insert into public.spec_definition_values (
  tenant_id, spec_definition_id, code, label, sort_order, is_active
)
select null, definition.id, entry.code, entry.label, entry.sort_order, true
from public.spec_definitions definition
cross join (values
  ('butyl', 'Butilo', 10),
  ('tpu', 'TPU', 20),
  ('latex', 'Látex', 30),
  ('other', 'Otro', 40)
) as entry(code, label, sort_order)
where definition.key = 'tube_material'
  and not exists (
    select 1 from public.spec_definition_values existing
    where existing.spec_definition_id = definition.id
      and existing.code = entry.code
  );

-- Y al formulario de la cámara. El ancho entra en compatibilidad porque es lo
-- que decide si sirve; sellante y material son ficha técnica.
insert into public.spec_template_fields (
  tenant_id, template_id, spec_definition_id,
  is_required, section_key, sort_order, helper_text
)
select null, template.id, definition.id,
  false, field.section_key, field.sort_order, field.helper_text
from public.spec_templates template
join (values
  ('tube_width_min_in', 'compatibility', 30,
   'El rango que dice el envase: 1.95/2.125 se guarda como 1.95 y 2.125.'),
  ('tube_width_max_in', 'compatibility', 31, null),
  ('tube_width_min_mm', 'compatibility', 32,
   'Sólo para ruta: 700x18/25C se guarda como 18 y 25.'),
  ('tube_width_max_mm', 'compatibility', 33, null),
  ('tube_has_sealant', 'specs', 40, null),
  ('tube_material', 'specs', 41, null)
) as field(key, section_key, sort_order, helper_text) on true
join public.spec_definitions definition on definition.key = field.key
where template.key = 'tube'
  and not exists (
    select 1 from public.spec_template_fields existing
    where existing.template_id = template.id
      and existing.spec_definition_id = definition.id
  );

commit;
