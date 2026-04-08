-- READ-ONLY inspection of the remaining review-needed standalone
-- product-form sync noise rows after high-confidence cleanup.
--
-- Goal:
-- Show the exact remaining rows with enough context to decide whether they
-- were real manual admin corrections or less-obvious legacy sync artifacts.

with standalone_manual_rows as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at,
    sa.created_by
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
    and sa.reference is null
), standalone_without_business_context as (
  select smr.*
  from standalone_manual_rows smr
  where not exists (
    select 1
    from public.stock_movements sm
    where sm.tenant_id = smr.tenant_id
      and sm.product_id = smr.product_id
      and abs(extract(epoch from (sm.created_at - smr.created_at))) <= 60
      and (
        coalesce(sm.reference, '') <> ''
        or coalesce(sm.movement_type, '') <> 'manual'
      )
  )
), seed_rows as (
  select *
  from standalone_without_business_context
  where quantity > 0
    and (stock_before < 0 or stock_after <= 0)
), seeded_batches as (
  select distinct tenant_id, created_by, created_at
  from seed_rows
), candidate_rows as (
  select swbc.*
  from standalone_without_business_context swbc
  join seeded_batches sb
    on sb.tenant_id = swbc.tenant_id
   and sb.created_by is not distinct from swbc.created_by
   and sb.created_at = swbc.created_at
), classified_rows as (
  select
    cr.*,
    p.name as product_name,
    p.sku,
    coalesce(p.product_type, 'product') as current_product_type,
    coalesce(p.track_stock, true) as current_track_stock,
    p.inventory_qty as current_inventory_qty,
    p.stock_quantity as current_stock_quantity,
    case
      when coalesce(p.product_type, 'product') = 'service'
           or coalesce(p.track_stock, true) = false
        then 'high_confidence_non_stock'
      when cr.quantity > 0 and cr.stock_before < 0 and cr.stock_after = 0
        then 'high_confidence_negative_to_zero'
      else 'review_needed'
    end as cleanup_class
  from candidate_rows cr
  left join public.products p
    on p.id = cr.product_id
   and p.tenant_id = cr.tenant_id
)
select
  cr.created_at,
  cr.created_by,
  au.email as created_by_email,
  cr.product_name,
  cr.sku,
  cr.current_product_type,
  cr.current_track_stock,
  cr.quantity,
  cr.stock_before,
  cr.stock_after,
  cr.current_inventory_qty,
  cr.current_stock_quantity,
  (coalesce(cr.current_stock_quantity, 0) - coalesce(cr.current_inventory_qty, 0)) as current_column_drift,
  cr.adjustment_id
from classified_rows cr
left join auth.users au
  on au.id = cr.created_by
where cr.cleanup_class = 'review_needed'
order by cr.created_at desc, cr.product_name;

with standalone_manual_rows as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at,
    sa.created_by
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
    and sa.reference is null
), standalone_without_business_context as (
  select smr.*
  from standalone_manual_rows smr
  where not exists (
    select 1
    from public.stock_movements sm
    where sm.tenant_id = smr.tenant_id
      and sm.product_id = smr.product_id
      and abs(extract(epoch from (sm.created_at - smr.created_at))) <= 60
      and (
        coalesce(sm.reference, '') <> ''
        or coalesce(sm.movement_type, '') <> 'manual'
      )
  )
), seed_rows as (
  select *
  from standalone_without_business_context
  where quantity > 0
    and (stock_before < 0 or stock_after <= 0)
), seeded_batches as (
  select distinct tenant_id, created_by, created_at
  from seed_rows
), candidate_rows as (
  select swbc.*
  from standalone_without_business_context swbc
  join seeded_batches sb
    on sb.tenant_id = swbc.tenant_id
   and sb.created_by is not distinct from swbc.created_by
   and sb.created_at = swbc.created_at
), classified_rows as (
  select
    cr.*,
    coalesce(p.product_type, 'product') as current_product_type,
    coalesce(p.track_stock, true) as current_track_stock,
    case
      when coalesce(p.product_type, 'product') = 'service'
           or coalesce(p.track_stock, true) = false
        then 'high_confidence_non_stock'
      when cr.quantity > 0 and cr.stock_before < 0 and cr.stock_after = 0
        then 'high_confidence_negative_to_zero'
      else 'review_needed'
    end as cleanup_class
  from candidate_rows cr
  left join public.products p
    on p.id = cr.product_id
   and p.tenant_id = cr.tenant_id
)
select
  created_at,
  created_by,
  count(*) as review_needed_rows,
  sum(quantity) as total_quantity_delta,
  min(stock_before) as min_stock_before,
  max(stock_after) as max_stock_after
from classified_rows
where cleanup_class = 'review_needed'
group by created_at, created_by
order by created_at desc;