-- Deployment status is not encoded in this immutable file. Read the exact
-- production stamp with:
--   scripts/db/migration_status.sh \
--     supabase/migrations/20260816170000_purchase_candidate_media_contract.sql
-- Forward-only additive media contract for the intelligent purchasing
-- workspace.
-- Purpose: publish the real product photo of a candidate and of an internal
-- stock component so rows, cards and the inspector can render identity instead
-- of a monogram-only placeholder.
-- Forward: additive columns on existing read models and versioned RPCs. No
-- business row is written, no stock moves, no purchase is created and no
-- previously applied migration is edited.
-- Recovery: stop reading the new keys; every consumer falls back to the
-- canonical monogram because resolution is nullable end to end.
-- Risk: read-only projection over public.products columns that already exist
-- (image_url_optimized, image_url, image_urls).
begin;

-- ---------------------------------------------------------------------------
-- Candidate metrics gain the product media triple.
--
-- Resolution order is deliberately NOT collapsed server-side: the client owns
-- the fallback chain so a broken optimized URL can still degrade to the raw
-- one at render time instead of failing the whole row.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- The ranking RPC publishes the same media triple. Keys are additive: an older
-- client ignores them and still renders the canonical monogram.
-- ---------------------------------------------------------------------------
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
      'imageUrlOptimized', image_url_optimized,
      'imageUrl', image_url,
      'imageUrls', to_jsonb(image_urls),
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
  'Tenant-bound, explainable historical purchase candidate ranking with product media. It balances landed margin, observed history, recency, stability and evidence; supplier availability is always unverified.';

-- ---------------------------------------------------------------------------
-- The internal stock surface needs the same identity: the workshop row and the
-- phone card show the real part before any supplier is proposed.
-- ---------------------------------------------------------------------------
create or replace function public.get_supply_need_inventory_snapshot_v1(
  p_need_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_need public.supply_needs%rowtype;
  v_product public.products%rowtype;
  v_components jsonb;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.product_id is null then
    return jsonb_build_object(
      'need_id', v_need.id,
      'identity_state', v_need.identity_state,
      'assignable', false,
      'reason', 'identity_unresolved',
      'components', '[]'::jsonb
    );
  end if;

  select product.* into v_product
  from public.products product
  where product.tenant_id = v_tenant_id and product.id = v_need.product_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_id', requirement.product_id,
    'name', component.name,
    'sku', component.sku,
    'image_url_optimized', nullif(btrim(component.image_url_optimized), ''),
    'image_url', nullif(btrim(component.image_url), ''),
    'image_urls', to_jsonb(coalesce(component.image_urls, array[]::text[])),
    'quantity_in_set', requirement.quantity_in_set,
    'required_quantity', requirement.required_quantity,
    'on_hand', coalesce(component.stock_quantity, component.inventory_qty, 0),
    'online_committed', coalesce(online.quantity, 0),
    'workshop_committed', coalesce(workshop.quantity, 0),
    'atp', public.inventory_available_quantity_v1(
      v_tenant_id, requirement.product_id
    )
  ) order by requirement.product_id), '[]'::jsonb)
  into v_components
  from (
    select v_product.id as product_id,
           1::integer as quantity_in_set,
           v_need.quantity::integer as required_quantity
    where not coalesce(v_product.is_set, false)
    union all
    select map.component_product_id,
           map.quantity_in_set,
           (v_need.quantity::integer * map.quantity_in_set)::integer
    from public.product_set_components map
    where map.tenant_id = v_tenant_id
      and map.set_product_id = v_product.id
      and coalesce(v_product.is_set, false)
  ) requirement
  join public.products component
    on component.tenant_id = v_tenant_id
   and component.id = requirement.product_id
  left join lateral (
    select coalesce(sum(reservation.quantity), 0)::integer as quantity
    from public.online_order_inventory_reservations reservation
    where reservation.tenant_id = v_tenant_id
      and reservation.product_id = requirement.product_id
      and reservation.state = 'active'
      and reservation.expires_at > clock_timestamp()
  ) online on true
  left join lateral (
    select coalesce(sum(commitment.quantity), 0)::integer as quantity
    from public.workshop_inventory_commitments commitment
    where commitment.tenant_id = v_tenant_id
      and commitment.product_id = requirement.product_id
      and commitment.state = 'active'
  ) workshop on true;

  return jsonb_build_object(
    'need_id', v_need.id,
    'need_version', v_need.version,
    'source_product_id', v_product.id,
    'source_product_name', v_product.name,
    'is_set', coalesce(v_product.is_set, false),
    'requested_quantity', v_need.quantity,
    'unit', v_need.unit,
    'available_to_promise', public.inventory_available_quantity_v1(
      v_tenant_id, v_product.id
    ),
    'assignable', (
      v_need.unit = 'unit'
      and v_need.quantity = trunc(v_need.quantity)
      and public.inventory_available_quantity_v1(v_tenant_id, v_product.id)
          >= v_need.quantity
    ),
    'components', v_components
  );
end;
$$;

revoke all on function public.get_supply_need_inventory_snapshot_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_inventory_snapshot_v1(uuid)
  to authenticated;

comment on function public.get_supply_need_inventory_snapshot_v1(uuid) is
  'Reservation-aware internal stock snapshot for one supply need, including component product media so the stock surface renders real identity before any supplier is compared.';

grant select on public.purchase_candidate_metrics_v1 to authenticated;

notify pgrst, 'reload schema';

commit;
