-- READ-ONLY verification after running
-- 20260407153500_cleanup_retroactive_product_form_sync_noise_high_confidence.sql.
--
-- Expected result:
-- - No rows for high_confidence_non_stock
-- - No rows for high_confidence_negative_to_zero
-- - Any remaining rows should only be review_needed

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
  cleanup_class,
  created_at,
  created_by,
  product_name,
  sku,
  quantity,
  stock_before,
  stock_after,
  adjustment_id
from classified_rows
order by created_at desc, cleanup_class, product_name;

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
select cleanup_class, count(*) as remaining_rows
from classified_rows
group by cleanup_class
order by cleanup_class;