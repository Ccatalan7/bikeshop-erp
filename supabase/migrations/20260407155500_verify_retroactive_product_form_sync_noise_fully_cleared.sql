-- READ-ONLY verification after running both:
-- - 20260407153500_cleanup_retroactive_product_form_sync_noise_high_confidence.sql
-- - 20260407155000_cleanup_retroactive_product_form_sync_noise_remaining_review_batches.sql
--
-- Expected result: no rows.

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
)
select
  created_at,
  created_by,
  count(*) as remaining_candidate_rows,
  sum(quantity) as total_quantity_delta,
  min(stock_before) as min_stock_before,
  max(stock_after) as max_stock_after
from candidate_rows
group by created_at, created_by
order by created_at desc;