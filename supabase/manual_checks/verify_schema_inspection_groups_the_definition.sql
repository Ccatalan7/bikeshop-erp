-- Falla si la consulta agrupada vuelve a referenciar una columna sin agrupar.
-- No mira el texto de la función: EJECUTA la misma forma contra los datos
-- reales del taller, que es lo único que prueba que Postgres la acepta.
with category_scope as (
  select category.id, category.name, category.full_path
  from public.product_categories category
  where category.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and category.is_active is true
), filas as (
  select scope.id, scope.name, scope.full_path, mapping.technical_family,
    definition.id definition_id, definition.key, definition.label,
    definition.data_type, definition.unit,
    nullif(coalesce((
      select jsonb_agg(sv.label order by sv.sort_order)::text
      from public.spec_definition_values sv
      where sv.spec_definition_id = definition.id and sv.is_active
    ), definition.allowed_values::text), '[]') allowed_values,
    count(distinct product.id)::integer product_count
  from category_scope scope
    join public.category_tech_mappings mapping
      on mapping.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and mapping.category_id = scope.id and mapping.status = 'active'
    join lateral (
      select template.id
      from public.spec_templates template
      where template.is_active is true
        and (template.tenant_id is null
          or template.tenant_id = '5443b130-cc28-45af-a420-cd500b288890')
        and (template.id = mapping.template_id
          or (mapping.template_id is null
            and template.technical_family = mapping.technical_family))
      order by (template.id = mapping.template_id) desc,
        (template.tenant_id is not null) desc
      limit 1
    ) template on true
    join public.spec_template_fields template_field
      on template_field.template_id = template.id
    join public.spec_definitions definition
      on definition.id = template_field.spec_definition_id
     and definition.is_filterable is true
    left join public.products product
      on product.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and product.category_id = scope.id and product.is_active is true
  group by scope.id, scope.name, scope.full_path, mapping.technical_family,
    definition.id, definition.key, definition.label, definition.data_type,
    definition.unit, definition.allowed_values
)
select 1 / (case when (select count(*) from filas) > 0 then 1 else 0 end)
  as inspeccion_agrupa_la_definicion;
