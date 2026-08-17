-- Canonical tire ficha for schema-driven inventory and purchasing decisions.
--
-- Forward: add only system vocabulary plus an exact active category bridge.
-- Existing product facts stay untouched: a commercial name is not sufficient
-- evidence for a structured dimension, standard or compatibility claim.
-- Recovery: remove the exact tire category mapping and deactivate the template.
-- The additive definitions can remain unused without changing product rows.
begin;

insert into public.spec_definitions (
  tenant_id,
  key,
  label,
  description,
  data_type,
  unit,
  allowed_values,
  validation_rules,
  is_filterable,
  is_required_by_default,
  is_compatibility_relevant,
  is_customer_visible,
  is_mechanic_visible,
  group_name,
  sort_order
)
values
  (null, 'wheel_size', 'Tamaño de rueda',
   'Rodado nominal declarado para la cubierta; no reemplaza una medida ETRTO cuando esa precisión está disponible.',
   'single_select', null,
   '["12\"","16\"","20\"","24\"","26\"","27.5\"","29\"","700c","650b","Otra"]'::jsonb,
   '{}'::jsonb, true, false, true, true, true, 'Compatibilidad', 10),

  (null, 'tire_width_in', 'Ancho nominal (pulgadas)',
   'Ancho nominal de cubierta declarado en pulgadas. No se deriva automáticamente del nombre comercial.',
   'number', 'in', '[]'::jsonb, '{"min":0.5,"max":6}'::jsonb,
   true, false, true, true, true, 'Dimensiones', 20),

  (null, 'tire_width_mm', 'Ancho nominal (mm)',
   'Ancho nominal de cubierta declarado en milímetros. Se conserva separado de pulgadas para no inventar conversiones nominales.',
   'number', 'mm', '[]'::jsonb, '{"min":15,"max":150}'::jsonb,
   true, false, true, true, true, 'Dimensiones', 30),

  (null, 'tire_etrto', 'Medida ETRTO',
   'Medida normalizada declarada por el fabricante, por ejemplo 57-584.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 40),

  (null, 'tire_bead_type', 'Construcción del talón',
   'Construcción declarada del talón o carcasa principal.',
   'single_select', null,
   '["Talón de alambre","Talón plegable","Tubular","Sólido / sin aire","Desconocido / sin confirmar"]'::jsonb,
   '{}'::jsonb, true, false, false, true, true, 'Construcción', 50),

  (null, 'tire_tubeless_ready', 'Tubeless Ready',
   'Indica si la cubierta declara compatibilidad tubeless ready.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Tubeless', 60)
on conflict (key) where tenant_id is null do update
set label = excluded.label,
    description = excluded.description,
    data_type = excluded.data_type,
    unit = excluded.unit,
    allowed_values = excluded.allowed_values,
    validation_rules = excluded.validation_rules,
    is_filterable = excluded.is_filterable,
    is_required_by_default = excluded.is_required_by_default,
    is_compatibility_relevant = excluded.is_compatibility_relevant,
    is_customer_visible = excluded.is_customer_visible,
    is_mechanic_visible = excluded.is_mechanic_visible,
    group_name = excluded.group_name,
    sort_order = excluded.sort_order,
    updated_at = now();

insert into public.spec_templates (
  tenant_id,
  key,
  name,
  technical_family,
  description,
  default_tags,
  is_active
)
values (
  null,
  'tire',
  'Neumático / Cubierta',
  'tire',
  'Cubiertas con rodado, ancho nominal, ETRTO, construcción y capacidad tubeless declarados.',
  '["wheel","tire"]'::jsonb,
  true
)
on conflict (key) where tenant_id is null do update
set name = excluded.name,
    technical_family = excluded.technical_family,
    description = excluded.description,
    default_tags = excluded.default_tags,
    is_active = excluded.is_active,
    updated_at = now();

with field_rows(spec_key, is_required, section_key, sort_order, helper_text) as (
  values
    ('wheel_size', true, 'compatibility', 10,
     'Confirma el rodado declarado; usa ETRTO cuando la decisión requiere mayor precisión.'),
    ('tire_etrto', false, 'compatibility', 20,
     'Registra el valor impreso por el fabricante, sin inferirlo desde otras medidas.'),
    ('tire_width_in', false, 'dimensions', 10,
     'Usa este campo cuando el ancho nominal está declarado en pulgadas.'),
    ('tire_width_mm', false, 'dimensions', 20,
     'Usa este campo cuando el ancho nominal está declarado en milímetros.'),
    ('tire_bead_type', false, 'construction', 10, null),
    ('tire_tubeless_ready', false, 'tubeless', 10, null)
)
insert into public.spec_template_fields (
  tenant_id,
  template_id,
  spec_definition_id,
  is_required,
  section_key,
  sort_order,
  helper_text
)
select
  null,
  template.id,
  definition.id,
  field_row.is_required,
  field_row.section_key,
  field_row.sort_order,
  field_row.helper_text
from field_rows field_row
join public.spec_templates template
  on template.tenant_id is null
 and template.key = 'tire'
join public.spec_definitions definition
  on definition.tenant_id is null
 and definition.key = field_row.spec_key
on conflict (template_id, spec_definition_id) do update
set tenant_id = excluded.tenant_id,
    is_required = excluded.is_required,
    section_key = excluded.section_key,
    sort_order = excluded.sort_order,
    helper_text = excluded.helper_text,
    updated_at = now();

insert into public.category_tech_mappings (
  tenant_id,
  category_id,
  technical_family,
  template_id,
  default_tags,
  status
)
select
  category.tenant_id,
  category.id,
  'tire',
  template.id,
  '["wheel","tire"]'::jsonb,
  'active'
from public.product_categories category
cross join public.spec_templates template
where category.is_active is true
  and category.full_path = 'Componentes / Ruedas / Neumáticos'
  and template.tenant_id is null
  and template.key = 'tire'
on conflict (tenant_id, category_id) do update
set technical_family = excluded.technical_family,
    template_id = excluded.template_id,
    default_tags = excluded.default_tags,
    status = excluded.status,
    updated_at = now();

commit;
