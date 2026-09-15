-- Research queue only. Text/images are discovery evidence, never validated
-- model, MPN, packaging or compatibility facts by themselves.
with observations as (
 select f.tenant_id,f.subject_id,
 jsonb_object_agg(d.key,jsonb_build_object('source',f.source,'confirmed',f.confirmed)
   order by d.key) provenance
 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
 join public.tenants tn on tn.id=f.tenant_id and tn.subdomain='vinabike'
 where f.subject_type='product' and f.subject_scope is null
 group by f.tenant_id,f.subject_id
)
select p.id,p.name,p.sku,p.brand,p.model,p.manufacturer_sku,p.barcode,p.gtin,
 p.supplier_id,p.supplier_name,p.supplier_code,p.supplier_reference,
 p.description,p.image_url,p.image_urls,p.is_active,
 p.category_id,c.name category,t.id template_id,t.technical_family,t.contract_version,
 p.spec_revision,p.updated_at,p.spec_reference_id,p.spec_template_id,b.binding_source,
 coalesce(o.provenance,'{}'::jsonb) existing_observations,
 public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p.id)) current_values
from public.products p
join public.tenants tn on tn.id=p.tenant_id and tn.subdomain='vinabike'
left join public.product_categories c on c.id=p.category_id and c.tenant_id=p.tenant_id
left join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
left join public.spec_templates t on t.id=b.template_id and t.is_active
left join observations o on o.subject_id=p.id and o.tenant_id=p.tenant_id
where p.product_type is distinct from 'service'
order by p.is_active desc,coalesce(t.technical_family,'unmapped'),p.brand,p.name,p.id;
