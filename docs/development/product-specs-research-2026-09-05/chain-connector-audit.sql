-- Read-only, scoped to Viñabike catalogue identity and technical facts.
select p.id, p.name, p.brand, p.model, p.manufacturer_sku,
       c.name category, t.key template, t.technical_family,
       p.spec_revision, p.spec_reference_id,
       public.spec_payload_display_internal_v1(
         public.spec_product_payload_internal_v1(p.id)) as facts
from public.products p
join public.tenants tn on tn.id=p.tenant_id and tn.subdomain='vinabike'
join public.product_categories c on c.id=p.category_id
join public.category_tech_mappings m on m.category_id=c.id and m.status='active'
join public.spec_templates t on t.id=m.template_id and t.is_active
where p.is_active and p.product_type <> 'service'
  and t.technical_family in ('chain','chain_link')
order by t.technical_family, p.brand, p.name;
