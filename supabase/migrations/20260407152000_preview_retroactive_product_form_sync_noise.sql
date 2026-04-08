-- READ-ONLY preview for retroactive standalone product-form sync noise.
--
-- Goal:
-- Find historical manual adjustments likely caused by legacy
-- inventory_qty/stock_quantity drift, without touching the sales-linked class
-- that was already cleaned separately.
--
-- Conservative detection strategy:
-- 1) Seed rows are standalone manual product-form adjustments with no nearby
--    referenced/non-manual movement for the same product within 60 seconds.
-- 2) A seed row must show the negative-stock resync pattern:
--      - quantity > 0
--      - stock_before < 0 OR stock_after <= 0
-- 3) Once a timestamp/user batch is seeded, include all standalone manual
--    product-form rows from that same tenant + created_by + created_at batch.
--
-- This is intended to catch the confirmed phantom batches like:
-- - 2026-04-07 19:41:23
-- - 2026-04-04 16:03:19
-- - 2026-04-02 21:50:20
-- - 2026-04-02 21:38:33

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
  cr.created_at,
  cr.created_by,
  au.email as created_by_email,
  p.name as product_name,
  p.sku,
  cr.quantity,
  cr.stock_before,
  cr.stock_after,
  cr.adjustment_id
from candidate_rows cr
left join public.products p
  on p.id = cr.product_id
 and p.tenant_id = cr.tenant_id
left join auth.users au
  on au.id = cr.created_by
order by cr.created_at desc, au.email, p.name;

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
  count(*) as candidate_rows,
  sum(quantity) as total_quantity_delta,
  min(stock_before) as min_stock_before,
  max(stock_after) as max_stock_after
from candidate_rows
group by created_at, created_by
order by created_at desc;