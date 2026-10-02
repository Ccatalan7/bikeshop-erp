select t.key template_key, d.key field_key, d.data_type, d.unit, d.label, left(coalesce(d.description,''),160) description,
  coalesce(t.form_contract->'roles'->>d.key,'primary') role, f.section_key, f.sort_order, d.is_customer_visible visible,
  d.validation_rules - 'rows_schema' rules,
  case when d.validation_rules ? 'rows_schema' then d.validation_rules->'rows_schema' end rows_schema,
  (select jsonb_agg(v.label order by v.sort_order nulls last, v.label) from public.spec_definition_values v where v.spec_definition_id=d.id and v.is_active and v.tenant_id is null) options
from public.spec_templates t
join public.spec_template_fields f on f.template_id=t.id
join public.spec_definitions d on d.id=f.spec_definition_id
where t.tenant_id is null and t.is_active
  and coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'
order by t.key, f.sort_order
