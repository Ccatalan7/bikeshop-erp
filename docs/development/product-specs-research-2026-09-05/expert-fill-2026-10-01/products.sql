with pub as (
  select p.id, p.name, left(regexp_replace(coalesce(p.description,''),'\s+',' ','g'),400) description, p.brand, p.model, p.manufacturer_sku, t.key template_key, t.id template_id
  from public.products p
  join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
  join public.spec_templates t on t.id=b.template_id
  where p.tenant_id='5443b130-cc28-45af-a420-cd500b288890' and coalesce(p.is_active,true)
    and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
)
select pub.id, pub.name, pub.description, pub.brand, pub.model, pub.manufacturer_sku, pub.template_key,
  (select jsonb_object_agg(d.key, jsonb_build_object('s', f.source, 'v',
      coalesce(to_jsonb(f.value_number), to_jsonb(f.value_boolean), to_jsonb(f.value_text), f.value_json,
        (select jsonb_agg(v.label order by fv.position) from public.spec_fact_values fv join public.spec_definition_values v on v.id=fv.value_id where fv.fact_id=f.id))))
   from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.tenant_id='5443b130-cc28-45af-a420-cd500b288890' and f.subject_type='product' and f.subject_id=pub.id and f.subject_scope is null) facts
from pub order by pub.template_key, pub.name
