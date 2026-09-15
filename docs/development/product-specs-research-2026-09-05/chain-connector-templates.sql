select t.key, t.technical_family, t.contract_version, t.form_contract,
       jsonb_agg(jsonb_build_object('key',d.key,'label',d.label,
         'data_type',d.data_type,'unit',d.unit,'allowed_values',d.allowed_values,
         'validation_rules',d.validation_rules,'section',f.section_key,
         'sort_order',f.sort_order,'required',f.is_required,
         'visibility_rules',f.visibility_rules,'constraint_rules',f.constraint_rules)
         order by f.sort_order,d.key) as fields
from public.spec_templates t
join public.spec_template_fields f on f.template_id=t.id
join public.spec_definitions d on d.id=f.spec_definition_id
where t.is_active and t.technical_family in ('chain','chain_link')
group by t.id order by t.key;
