-- Revierto `purchase_candidate_metrics_v1` a su definición conocida-buena.
--
-- Qué pasó, en orden:
--
-- 1. El ranking por **texto libre** tardaba 32 s contra un `statement_timeout`
--    de 4,5 s. Defecto anterior a este trabajo.
-- 2. Culpé a `tenant_business_date`, que se evalúa por fila porque recibe una
--    columna, y la saqué a un CTE sobre `public.tenants` (20260817126000). El
--    tiempo no bajó, y además el CTE evaluaba la función para todos los
--    tenants: la función exige membresía activa, así que empezó a lanzar 42501
--    en escaneos amplios.
-- 3. Intenté acotarla derivándola de `aggregates` (20260817128000). Eso obligó
--    a materializar el agregado completo antes de filtrar y rompió también el
--    camino **por producto exacto**, que era el único que la app usa y el que
--    sí respondía en ~2 s.
--
-- Tres cambios sin medir el plan, y el último dejó peor de lo que estaba. Se
-- vuelve exactamente a la definición del contrato de medios, que es el estado
-- que la app necesita hoy, y el problema de texto libre queda abierto y
-- documentado en vez de perseguido a ciegas.
--
-- Lección, escrita donde se va a leer: optimizar sin `EXPLAIN` es adivinar, y
-- adivinar en producción cuesta más que el defecto original.

begin;

create or replace view public.purchase_candidate_metrics_v1
with (security_invoker = true)
as
with exact_observations as (
  select observation.*
  from public.purchase_line_landed_cost_observations_v1 observation
  where observation.product_id is not null
), aggregates as (
  select
    tenant_id,
    product_id,
    supplier_id,
    supplier_name,
    currency_code,
    count(distinct purchase_invoice_id)::integer as purchase_count,
    count(*)::integer as observation_count,
    sum(quantity)::numeric(18,4) as purchased_units,
    min(economic_date) as first_purchase_at,
    max(economic_date) as last_purchase_at,
    avg(landed_unit_cost_net)::numeric(18,6) as average_landed_unit_cost_net,
    stddev_samp(landed_unit_cost_net)::numeric(18,6)
      as landed_cost_standard_deviation,
    count(*) filter (
      where freight_evidence_status in ('complete', 'none')
    )::integer as complete_cost_observation_count
  from exact_observations
  group by tenant_id, product_id, supplier_id, supplier_name, currency_code
), latest as (
  select distinct on (
    tenant_id, product_id, supplier_id, supplier_name, currency_code
  )
    tenant_id,
    product_id,
    supplier_id,
    supplier_name,
    currency_code,
    purchase_invoice_id as latest_purchase_invoice_id,
    purchase_invoice_line_id as latest_purchase_invoice_line_id,
    economic_date as latest_purchase_at,
    base_unit_cost_net as latest_base_unit_cost_net,
    allocated_freight_net as latest_allocated_freight_net,
    landed_unit_cost_net as latest_landed_unit_cost_net,
    freight_evidence_status as latest_freight_evidence_status,
    identity_quality as latest_identity_quality
  from exact_observations
  order by tenant_id, product_id, supplier_id, supplier_name, currency_code,
    economic_date desc, purchase_invoice_line_id desc
)
select
  aggregate.tenant_id,
  md5(
    aggregate.product_id::text || ':' ||
    coalesce(aggregate.supplier_id::text, aggregate.supplier_name, '') || ':' ||
    aggregate.currency_code
  )::uuid as candidate_id,
  aggregate.product_id,
  product.name as product_name,
  product.sku as product_sku,
  product.category_id,
  coalesce(category.full_path, category.name, product.category_name,
    product.category) as category_path,
  coalesce(product.brand, brand.name) as brand,
  aggregate.supplier_id,
  aggregate.supplier_name,
  supplier.website as supplier_website,
  nullif(concat_ws(', ', supplier.comuna, supplier.city), '')
    as supplier_location,
  exists (
    select 1
    from public.supplier_relationship_tags tag
    where tag.tenant_id = aggregate.tenant_id
      and tag.supplier_id = aggregate.supplier_id
      and tag.tag_code in ('local', 'local_workshop', 'emergency_local')
      and tag.valid_from <= public.tenant_business_date(aggregate.tenant_id)
      and (tag.valid_to is null
        or tag.valid_to >= public.tenant_business_date(aggregate.tenant_id))
  ) as is_confirmed_local,
  aggregate.currency_code,
  aggregate.purchase_count,
  aggregate.observation_count,
  aggregate.purchased_units,
  aggregate.first_purchase_at,
  aggregate.last_purchase_at,
  latest.latest_purchase_invoice_id,
  latest.latest_purchase_invoice_line_id,
  latest.latest_base_unit_cost_net,
  latest.latest_allocated_freight_net,
  latest.latest_landed_unit_cost_net,
  aggregate.average_landed_unit_cost_net,
  aggregate.landed_cost_standard_deviation,
  latest.latest_freight_evidence_status,
  latest.latest_identity_quality,
  aggregate.complete_cost_observation_count,
  product.price::numeric(18,4) as catalog_sale_price_gross,
  case
    when product.price is null or product.price <= 0 then null
    when coalesce(product.tax_rate, 19) > 1
      then (product.price / (1 + coalesce(product.tax_rate, 19) / 100))
    else (product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0)))
  end::numeric(18,6) as catalog_sale_price_net,
  case
    when product.price is null or product.price <= 0 then null
    else (
      (case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end) - latest.latest_landed_unit_cost_net
    )::numeric(18,6)
  end as projected_unit_gross_profit,
  case
    when product.price is null or product.price <= 0 then null
    else (
      ((case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end) - latest.latest_landed_unit_cost_net)
      / nullif((case
        when coalesce(product.tax_rate, 19) > 1
          then product.price / (1 + coalesce(product.tax_rate, 19) / 100)
        else product.price / (1 + greatest(coalesce(product.tax_rate, 0.19), 0))
      end), 0)
    )::numeric(12,8)
  end as projected_gross_margin_ratio,
  greatest(
    public.tenant_business_date(aggregate.tenant_id)
      - latest.latest_purchase_at::date,
    0
  )::integer as evidence_age_days,
  product.updated_at as sale_price_updated_at,
  'unverified'::text as supplier_availability,
  latest.latest_purchase_at,
  -- CREATE OR REPLACE VIEW only permits additive columns at the end of the
  -- existing projection. Keeping the media triple here preserves every
  -- previously published ordinal/name and makes this migration forward-only.
  nullif(btrim(product.image_url_optimized), '') as image_url_optimized,
  nullif(btrim(product.image_url), '') as image_url,
  coalesce(product.image_urls, array[]::text[]) as image_urls
from aggregates aggregate
join latest
  on latest.tenant_id = aggregate.tenant_id
 and latest.product_id = aggregate.product_id
 and latest.supplier_id is not distinct from aggregate.supplier_id
 and latest.supplier_name is not distinct from aggregate.supplier_name
 and latest.currency_code = aggregate.currency_code
join public.products product
  on product.tenant_id = aggregate.tenant_id
 and product.id = aggregate.product_id
left join public.product_categories category
  on category.tenant_id = product.tenant_id
 and category.id = product.category_id
left join public.product_brands brand
  on brand.tenant_id = product.tenant_id
 and brand.id = product.brand_id
left join public.suppliers supplier
  on supplier.tenant_id = aggregate.tenant_id
 and supplier.id = aggregate.supplier_id
where product.is_active is true;

comment on view public.purchase_candidate_metrics_v1 is
  'Exact-product historical purchase metrics, latest eligible landed cost, tax-normalized catalog sale basis, product media triple, and explicitly unverified supplier availability.';

grant select on public.purchase_candidate_metrics_v1 to authenticated;

commit;
