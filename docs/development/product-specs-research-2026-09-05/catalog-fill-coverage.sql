-- Read-only preparation for catalogue research. Includes inactive physical
-- products; service records belong to their own workflow, not part fitment.
with scoped as (
 select p.id,p.tenant_id,p.name,p.brand,p.model,p.manufacturer_sku,p.is_active,
        c.id category_id,c.name category,t.id template_id,t.technical_family,
        p.spec_reference_id
 from public.products p
 join public.tenants tn on tn.id=p.tenant_id and tn.subdomain='vinabike'
 left join public.product_categories c on c.id=p.category_id and c.tenant_id=p.tenant_id
 left join public.category_tech_mappings m on m.category_id=c.id
   and m.tenant_id=p.tenant_id and m.status='active'
 left join public.spec_templates t on t.id=m.template_id and t.is_active
 where p.product_type is distinct from 'service'
), facts as (
 select f.subject_id,count(*) fact_count,
        count(*) filter(where f.confirmed) confirmed_count
 from public.spec_facts f join scoped p on p.id=f.subject_id and p.tenant_id=f.tenant_id
 where f.subject_type='product' and f.subject_scope is null
 group by f.subject_id
)
select coalesce(technical_family,'unmapped') technical_family,
 count(*) products,count(*) filter(where is_active) active_products,
 count(*) filter(where nullif(btrim(brand),'') is not null) with_brand,
 count(*) filter(where nullif(btrim(model),'') is not null) with_model,
 count(*) filter(where nullif(btrim(manufacturer_sku),'') is not null) with_mpn,
 count(*) filter(where spec_reference_id is not null) with_reference,
 count(*) filter(where coalesce(f.fact_count,0)>0) with_facts,
 count(*) filter(where coalesce(f.confirmed_count,0)>0) with_confirmed_facts,
 coalesce(sum(f.fact_count),0) facts,
 array_agg(distinct category order by category) categories
from scoped p left join facts f on f.subject_id=p.id
group by technical_family order by count(*) desc,technical_family;
