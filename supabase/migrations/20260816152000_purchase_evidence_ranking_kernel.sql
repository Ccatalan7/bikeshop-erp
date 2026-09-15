-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact ranking/freight read-back passed.
-- Deterministic purchase evidence, landed cost, and explainable candidate ranking.
-- Forward: additive read models and versioned RPCs only.
-- Recovery: stop calling the v1 RPCs; the views/functions can remain installed.
-- Risk: no business-row backfill, no stock movement, and no purchase creation.
begin;

-- A freight component is admitted only from structured evidence. A normalized
-- classified freight line wins over linked expenses for the same invoice so a
-- legacy invoice cannot count the same delivery twice. Free-text
-- additional_costs remain outside the calculation until they acquire a
-- reviewed structural classification.
create or replace view public.purchase_invoice_freight_components_v1
with (security_invoker = true)
as
with normalized_freight as (
  select
    line.tenant_id,
    line.purchase_invoice_id,
    'purchase_invoice_line'::text as source_kind,
    line.id as source_id,
    line.currency_code,
    line.net_amount::numeric(18,4) as recognized_net_amount,
    'classified_freight_line'::text as recognition_basis,
    line.updated_at as evidence_updated_at
  from public.purchase_invoice_lines line
  where line.line_nature = 'freight'
    and line.classification_status = 'classified'
    and line.net_amount > 0
), linked_freight_expenses as (
  select
    link.tenant_id,
    link.purchase_invoice_id,
    'expense_link'::text as source_kind,
    link.id as source_id,
    upper(coalesce(nullif(expense.currency, ''), 'CLP')) as currency_code,
    case
      when expense.total_amount > 0 and expense.subtotal >= 0 then
        round(
          coalesce(link.allocated_amount, expense.total_amount)
            * expense.subtotal / expense.total_amount,
          4
        )
      else coalesce(link.allocated_amount, expense.total_amount)
    end::numeric(18,4) as recognized_net_amount,
    'linked_transport_expense_net'::text as recognition_basis,
    greatest(link.updated_at, expense.updated_at) as evidence_updated_at
  from public.expense_links link
  join public.expenses expense
    on expense.tenant_id = link.tenant_id
   and expense.id = link.expense_id
  left join public.expense_categories category
    on category.tenant_id = expense.tenant_id
   and category.id = expense.category_id
  where lower(btrim(link.link_kind)) in ('delivery', 'freight')
    and lower(coalesce(category.name, '')) ~
      '(flete|transporte|env[ií]o|encomienda)'
    and coalesce(expense.posting_status, 'draft') <> 'void'
    and coalesce(expense.approval_status, 'pending') <> 'rejected'
    and coalesce(link.allocated_amount, expense.total_amount, 0) > 0
    and not exists (
      select 1
      from normalized_freight normalized
      where normalized.tenant_id = link.tenant_id
        and normalized.purchase_invoice_id = link.purchase_invoice_id
    )
)
select * from normalized_freight
union all
select * from linked_freight_expenses;

comment on view public.purchase_invoice_freight_components_v1 is
  'Structured, non-duplicated net freight evidence. Classified normalized lines take precedence over linked transport expenses; unreviewed additional_costs are excluded.';

-- Every eligible purchase line remains independently reconstructable. Freight
-- is allocated in currency minor units with the largest-remainder method and a
-- stable line-id tie break, so allocated components reconcile exactly.
create or replace view public.purchase_line_landed_cost_observations_v1
with (security_invoker = true)
as
with eligible_lines as (
  select
    line.tenant_id,
    line.id as purchase_invoice_line_id,
    line.purchase_invoice_id,
    invoice.invoice_number,
    invoice.supplier_id,
    coalesce(supplier.name, invoice.supplier_name) as supplier_name,
    invoice.date as economic_date,
    invoice.status as document_status,
    line.product_id,
    coalesce(product.name, line.product_name_snapshot, line.description)
      as product_name,
    coalesce(product.sku, line.product_sku_snapshot) as product_sku,
    product.category_id,
    coalesce(category.full_path, category.name, product.category_name,
      product.category) as category_path,
    case
      when product.category_id is not null then 'current_product_category'
      else 'unresolved'
    end as category_source,
    coalesce(product.brand, brand.name) as brand,
    line.line_nature,
    product.purchase_treatment,
    line.quantity::numeric(18,4) as quantity,
    coalesce(nullif(product.unit, ''), 'unidad') as unit,
    line.net_amount::numeric(18,4) as merchandise_net_amount,
    line.currency_code,
    invoice.tax_treatment,
    line.updated_at as line_updated_at
  from public.purchase_invoice_lines line
  join public.purchase_invoices invoice
    on invoice.tenant_id = line.tenant_id
   and invoice.id = line.purchase_invoice_id
  left join public.products product
    on product.tenant_id = line.tenant_id
   and product.id = line.product_id
  left join public.product_categories category
    on category.tenant_id = product.tenant_id
   and category.id = product.category_id
  left join public.product_brands brand
    on brand.tenant_id = product.tenant_id
   and brand.id = product.brand_id
  left join public.suppliers supplier
    on supplier.tenant_id = invoice.tenant_id
   and supplier.id = invoice.supplier_id
  where invoice.status in ('confirmed', 'received', 'paid')
    and line.line_kind = 'item'
    and line.classification_status = 'classified'
    and line.line_nature in ('inventory', 'workshop_consumable')
    and line.quantity > 0
    and line.net_amount >= 0
), invoice_denominators as (
  select
    tenant_id,
    purchase_invoice_id,
    currency_code,
    sum(merchandise_net_amount)::numeric(24,8) as merchandise_net_total
  from eligible_lines
  group by tenant_id, purchase_invoice_id, currency_code
), freight_summary as (
  select
    component.tenant_id,
    component.purchase_invoice_id,
    count(*)::integer as component_count,
    jsonb_object_agg(
      component.currency_code,
      currency_total.net_amount
      order by component.currency_code
    ) as totals_by_currency,
    max(component.evidence_updated_at) as freight_updated_at
  from public.purchase_invoice_freight_components_v1 component
  join lateral (
    select sum(peer.recognized_net_amount)::numeric(24,8) as net_amount
    from public.purchase_invoice_freight_components_v1 peer
    where peer.tenant_id = component.tenant_id
      and peer.purchase_invoice_id = component.purchase_invoice_id
      and peer.currency_code = component.currency_code
  ) currency_total on true
  group by component.tenant_id, component.purchase_invoice_id
), allocation_base as (
  select
    line.*,
    denominator.merchandise_net_total,
    coalesce(summary.component_count, 0) as freight_component_count,
    coalesce(
      (summary.totals_by_currency ->> line.currency_code)::numeric,
      0
    )::numeric(24,8) as allocatable_freight_net,
    case
      when summary.component_count is null then 0
      else summary.component_count - (
        select count(*)::integer
        from public.purchase_invoice_freight_components_v1 component
        where component.tenant_id = line.tenant_id
          and component.purchase_invoice_id = line.purchase_invoice_id
          and component.currency_code = line.currency_code
      )
    end as foreign_currency_component_count,
    summary.freight_updated_at,
    case when line.currency_code = 'CLP' then 100 else 100 end as minor_scale
  from eligible_lines line
  join invoice_denominators denominator
    on denominator.tenant_id = line.tenant_id
   and denominator.purchase_invoice_id = line.purchase_invoice_id
   and denominator.currency_code = line.currency_code
  left join freight_summary summary
    on summary.tenant_id = line.tenant_id
   and summary.purchase_invoice_id = line.purchase_invoice_id
), raw_allocations as (
  select
    base.*,
    case when merchandise_net_total > 0 then
      allocatable_freight_net * minor_scale
        * merchandise_net_amount / merchandise_net_total
      else 0 end::numeric(30,12) as raw_minor,
    round(allocatable_freight_net * minor_scale)::bigint
      as target_minor
  from allocation_base base
), floored_allocations as (
  select
    raw.*,
    floor(raw_minor)::bigint as floor_minor,
    raw_minor - floor(raw_minor) as fractional_minor
  from raw_allocations raw
), residuals as (
  select
    floored.*,
    greatest(
      target_minor - sum(floor_minor) over (
        partition by tenant_id, purchase_invoice_id, currency_code
      ),
      0
    )::bigint as residual_minor,
    row_number() over (
      partition by tenant_id, purchase_invoice_id, currency_code
      order by fractional_minor desc, purchase_invoice_line_id
    )::bigint as residual_rank
  from floored_allocations floored
), allocated as (
  select
    residuals.*,
    (
      floor_minor + case when residual_rank <= residual_minor then 1 else 0 end
    )::numeric / minor_scale as allocated_freight_net
  from residuals
)
select
  tenant_id,
  purchase_invoice_line_id,
  purchase_invoice_id,
  invoice_number,
  supplier_id,
  supplier_name,
  economic_date,
  document_status,
  product_id,
  product_name,
  product_sku,
  category_id,
  category_path,
  category_source,
  brand,
  line_nature,
  purchase_treatment,
  quantity,
  unit,
  merchandise_net_amount,
  (merchandise_net_amount / quantity)::numeric(18,6)
    as base_unit_cost_net,
  allocated_freight_net::numeric(18,4),
  ((merchandise_net_amount + allocated_freight_net) / quantity)
    ::numeric(18,6) as landed_unit_cost_net,
  currency_code,
  tax_treatment,
  case
    when freight_component_count = 0 then 'none'
    when foreign_currency_component_count > 0 then 'partial_currency'
    when merchandise_net_total <= 0 then 'unavailable_denominator'
    else 'complete'
  end as freight_evidence_status,
  freight_component_count,
  foreign_currency_component_count,
  case
    when product_id is null then 'unresolved_product'
    when category_id is null then 'exact_product_category_missing'
    else 'exact_product'
  end as identity_quality,
  greatest(line_updated_at, coalesce(freight_updated_at, line_updated_at))
    as evidence_updated_at
from allocated;

comment on view public.purchase_line_landed_cost_observations_v1 is
  'Reproducible eligible purchase-line observations with deterministic proportional freight allocation. Historical supplier purchases never imply current supplier availability.';

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
  latest.latest_purchase_at
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
  'Exact-product historical purchase metrics, latest eligible landed cost, tax-normalized catalog sale basis, and explicitly unverified supplier availability.';

create or replace function public.rank_purchase_candidates_v1(
  p_query text default null,
  p_product_id uuid default null,
  p_category_id uuid default null,
  p_profile text default 'balanced',
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_query text := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_items jsonb;
  v_total integer;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local')
     or p_limit not between 1 and 20
     or octet_length(coalesce(p_query, '')) > 240
     or (v_query is null and p_product_id is null and p_category_id is null) then
    raise exception 'Invalid purchase ranking arguments' using errcode = '22023';
  end if;
  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id and product.id = p_product_id
  ) then
    raise exception 'Product not found' using errcode = 'P0002';
  end if;
  if p_category_id is not null and not exists (
    select 1 from public.product_categories category
    where category.tenant_id = v_tenant_id and category.id = p_category_id
  ) then
    raise exception 'Category not found' using errcode = 'P0002';
  end if;

  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = v_tenant_id and category.id = p_category_id
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_tenant_id and child.is_active is true
  ), filtered as materialized (
    select metric.*,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        metric.product_name, metric.product_sku, metric.brand,
        metric.category_path, metric.supplier_name
      )) as search_surface
    from public.purchase_candidate_metrics_v1 metric
    where metric.tenant_id = v_tenant_id
      and (p_product_id is null or metric.product_id = p_product_id)
      and (p_category_id is null or metric.category_id in (
        select id from category_scope
      ))
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', metric.product_name, metric.product_sku, metric.brand,
            metric.category_path, metric.supplier_name)
        )) = 0
      ))
  ), bounded as (
    select filtered.*,
      max(purchase_count) over()::numeric as max_purchase_count,
      max(purchased_units) over()::numeric as max_purchased_units
    from filtered
  ), dimensions as (
    select bounded.*,
      case
        when projected_gross_margin_ratio is null then 0.35
        else greatest(0, least(1,
          (projected_gross_margin_ratio + 0.10) / 0.70
        ))
      end::numeric as economy_score,
      (
        0.65 * case when max_purchase_count <= 1 then 1
          else ln(1 + purchase_count) / ln(1 + max_purchase_count) end
        + 0.35 * case when max_purchased_units <= 1 then 1
          else ln(1 + purchased_units) / ln(1 + max_purchased_units) end
      )::numeric as history_score,
      exp(-greatest(evidence_age_days, 0)::numeric / 180)::numeric
        as recency_score,
      case
        when observation_count < 2
          or average_landed_unit_cost_net <= 0
          or landed_cost_standard_deviation is null then 0.50
        else greatest(0, least(1,
          1 - landed_cost_standard_deviation / average_landed_unit_cost_net
        ))
      end::numeric as stability_score,
      (
        0.30
        + case when supplier_id is not null then 0.15 else 0 end
        + case when catalog_sale_price_net is not null then 0.20 else 0 end
        + case when latest_freight_evidence_status in ('complete', 'none')
            then 0.20 else 0 end
        + case when evidence_age_days <= 180 then 0.15 else 0 end
      )::numeric as evidence_score,
      case when is_confirmed_local then 1 else 0 end::numeric as local_score
    from bounded
  ), scored as (
    select dimensions.*,
      case p_profile
        when 'profitability' then
          0.62 * economy_score + 0.15 * history_score
          + 0.08 * recency_score + 0.05 * stability_score
          + 0.10 * evidence_score
        when 'urgent_local' then
          0.28 * economy_score + 0.16 * history_score
          + 0.24 * recency_score + 0.22 * local_score
          + 0.10 * evidence_score
        else
          0.38 * economy_score + 0.24 * history_score
          + 0.16 * recency_score + 0.12 * stability_score
          + 0.10 * evidence_score
      end::numeric as ranking_score,
      case
        when latest_identity_quality = 'exact_product'
          and catalog_sale_price_net is not null
          and latest_freight_evidence_status in ('complete', 'none')
          and evidence_age_days <= 180 then 'complete'
        when latest_identity_quality like 'exact_product%'
          then 'partial'
        else 'weak'
      end as evidence_quality
    from dimensions
  ), numbered as (
    select scored.*,
      row_number() over (
        order by ranking_score desc, evidence_score desc,
          latest_purchase_at desc, candidate_id
      )::integer as rank,
      count(*) over()::integer as matched_count
    from scored
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'candidateId', candidate_id,
      'rank', rank,
      'rankingProfile', p_profile,
      'rankingVersion', 'purchase-ranking-v1',
      'rankingScore', round(ranking_score, 6),
      'productId', product_id,
      'productName', product_name,
      'productSku', product_sku,
      'brand', brand,
      'category', category_path,
      'supplierId', supplier_id,
      'supplierName', supplier_name,
      'supplierWebsite', supplier_website,
      'supplierLocation', supplier_location,
      'isConfirmedLocal', is_confirmed_local,
      'supplierAvailability', supplier_availability,
      'currency', currency_code,
      'latestBaseUnitCostNet', latest_base_unit_cost_net,
      'latestAllocatedFreightNet', latest_allocated_freight_net,
      'latestLandedUnitCostNet', latest_landed_unit_cost_net,
      'catalogSalePriceGross', catalog_sale_price_gross,
      'catalogSalePriceNet', catalog_sale_price_net,
      'projectedUnitGrossProfit', projected_unit_gross_profit,
      'projectedGrossMarginRatio', projected_gross_margin_ratio,
      'purchaseCount', purchase_count,
      'purchasedUnits', purchased_units,
      'lastPurchaseAt', latest_purchase_at,
      'evidenceAgeDays', evidence_age_days,
      'evidenceQuality', evidence_quality,
      'freightEvidence', latest_freight_evidence_status,
      'economyScore', round(economy_score, 6),
      'historyScore', round(history_score, 6),
      'recencyScore', round(recency_score, 6),
      'stabilityScore', round(stability_score, 6),
      'evidenceScore', round(evidence_score, 6),
      'latestPurchaseInvoiceId', latest_purchase_invoice_id,
      'latestPurchaseInvoiceLineId', latest_purchase_invoice_line_id
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  into v_items, v_total
  from numbered;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'status', case when v_total = 0 then 'verifiedEmpty' else 'success' end,
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'hasMore', v_total > p_limit,
    'supplierAvailabilitySemantics', 'historical_only_unverified'
  );
end;
$$;

revoke all on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer
) to authenticated;

comment on function public.rank_purchase_candidates_v1(
  text, uuid, uuid, text, integer
) is
  'Tenant-bound, explainable historical purchase candidate ranking. It balances landed margin, observed history, recency, stability and evidence; supplier availability is always unverified.';

grant select on public.purchase_invoice_freight_components_v1 to authenticated;
grant select on public.purchase_line_landed_cost_observations_v1 to authenticated;
grant select on public.purchase_candidate_metrics_v1 to authenticated;

commit;
