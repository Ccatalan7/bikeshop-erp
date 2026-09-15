-- Read-only: evaluate every mapped product with the currently deployed
-- validator. No issues means only that existing rules pass, not that those
-- rules cover all mechanical requirements of the product family.
select p.id,p.spec_revision,p.updated_at,t.id template_id,t.contract_version,
  public.spec_validate_draft_internal_v1(t.id,
    public.spec_active_product_values_internal_v1(p.id,t.id),
    p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues
from public.products p
join public.tenants tn on tn.id=p.tenant_id and tn.subdomain='vinabike'
join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
join public.spec_templates t on t.id=b.template_id and t.is_active
order by p.id;
