-- Existing immutable reference library for candidate research, not automatic links.
select r.id,r.technical_family,r.brand,r.model,r.manufacturer_sku,r.label,
 public.spec_payload_display_internal_v1(r.fact_values) facts,
 r.claims,r.sources,r.reviewed_on
from public.product_spec_references r order by r.technical_family,r.brand,r.model,r.id;
