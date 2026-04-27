insert into spec_definitions (
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
values (
  null,
  'chain_outer_width_mm',
  'Ancho externo cadena',
  'Ancho externo nominal de la cadena en milimetros. En cadenas modernas ayuda a distinguir 9/10/11/12v dentro de la misma familia interna.',
  'number',
  'mm',
  '["5.25","5.3","5.62","5.88","5.95","6.6","6.7","7.1","7.3","7.8"]'::jsonb,
  '{"min":5.2,"max":7.8}'::jsonb,
  true,
  false,
  true,
  true,
  true,
  'Compatibilidad',
  13
)
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

with target_definition as (
  select id
  from spec_definitions
  where tenant_id is null and key = 'chain_outer_width_mm'
), target_rows(template_key, helper_text) as (
  values
    ('chain', 'Clave para afinar 9/10/11/12v dentro de 11/128 y precisar coberturas reales en 3/32.'),
    ('chain_link', 'Usa el ancho externo nominal cuando el fabricante lo declara para no mezclar 9/10/11/12v.')
)
insert into spec_template_fields (
  template_id,
  spec_definition_id,
  is_required,
  section_key,
  sort_order,
  helper_text
)
select
  st.id,
  td.id,
  false,
  'compatibility',
  25,
  tr.helper_text
from target_rows tr
join spec_templates st
  on st.tenant_id is null
 and st.key = tr.template_key
cross join target_definition td
where not exists (
  select 1
  from spec_template_fields tf
  where tf.template_id = st.id
    and tf.spec_definition_id = td.id
);

update spec_template_fields tf
set is_required = false,
    section_key = 'compatibility',
    sort_order = 25,
    helper_text = case st.key
      when 'chain' then 'Clave para afinar 9/10/11/12v dentro de 11/128 y precisar coberturas reales en 3/32.'
      when 'chain_link' then 'Usa el ancho externo nominal cuando el fabricante lo declara para no mezclar 9/10/11/12v.'
      else tf.helper_text
    end,
    updated_at = now()
from spec_templates st
join spec_definitions sd
  on sd.tenant_id is null
 and sd.key = 'chain_outer_width_mm'
where tf.template_id = st.id
  and tf.spec_definition_id = sd.id
  and st.tenant_id is null
  and st.key in ('chain', 'chain_link');
