-- CLEANUP: null-user manual adjustment anomalies (26 rows)
--
-- Sub-buckets confirmed during audit (20260407160000):
-- 1) 2025-12-09 (13 rows): service/non-stock products.
--    Trigger track_product_stock_changes() explicitly skips service products
--    (product_type = 'service' | track_stock = false), so these rows should
--    never have been created. Definitively bogus.
--
-- 2) 2026-01-16 (9 rows): null creator, massive stock resets (100→1, -99, -297).
--    No business reference, no creator. Anomalous batch origin (script/migration).
--
-- 3) 2026-02-13 (4 rows): null creator, small physical deltas.
--    Borderline, included per operator approval.
--
-- Safe targeting condition:
--   adjustment_type = 'manual'
--   reason = 'Manual adjustment via product form'
--   created_by IS NULL
-- All 124 legitimate admin rows have created_by = vinabikechile@gmail.com
-- and are NOT touched by this migration.
--
-- ⚠️  This migration REVERSES the stock delta of each bogus adjustment before
-- deleting the audit records, so live inventory_qty / stock_quantity are
-- restored to what they would have been had these adjustments never happened.

begin;

-- ============================================================
-- STEP 1 - preview: show affected products and the reversal
--          that will be applied (both columns must match)
-- ============================================================
select
  p.id              as product_id,
  p.name            as product_name,
  p.sku,
  sum(sa.quantity)  as bogus_delta,            -- what was wrongly applied
  -sum(sa.quantity) as reversal_to_apply,      -- what we will subtract back
  p.inventory_qty   as current_inventory_qty,
  p.stock_quantity  as current_stock_quantity,
  p.inventory_qty - sum(sa.quantity) as corrected_inventory_qty,
  p.stock_quantity  - sum(sa.quantity) as corrected_stock_quantity
from public.stock_adjustments sa
join public.products p
  on p.id = sa.product_id
 and p.tenant_id = sa.tenant_id
where sa.tenant_id      = '5443b130-cc28-45af-a420-cd500b288890'
  and sa.adjustment_type = 'manual'
  and coalesce(sa.reason, '') = 'Manual adjustment via product form'
  and sa.created_by is null
group by p.id, p.name, p.sku, p.inventory_qty, p.stock_quantity
order by p.name;

-- ============================================================
-- STEP 2 - reverse the stock delta on each affected product.
--          Both inventory_qty (legacy) and stock_quantity (current)
--          are updated together per the dual-column invariant.
--
--          ⚠️  Disable the stock-tracking trigger for this UPDATE.
--          Without this, track_product_stock_changes() would fire on
--          each row and create new "Ajuste Manual" adjustment rows for
--          the reversal itself, which then need a second cleanup pass.
-- ============================================================
alter table public.products disable trigger trg_track_product_stock_changes;

update public.products p
set
  inventory_qty  = p.inventory_qty  - agg.bogus_delta,
  stock_quantity = p.stock_quantity - agg.bogus_delta,
  updated_at     = now()
from (
  select
    product_id,
    sum(quantity) as bogus_delta
  from public.stock_adjustments
  where tenant_id      = '5443b130-cc28-45af-a420-cd500b288890'
    and adjustment_type = 'manual'
    and coalesce(reason, '') = 'Manual adjustment via product form'
    and created_by is null
  group by product_id
) agg
where p.id        = agg.product_id
  and p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

alter table public.products enable trigger trg_track_product_stock_changes;

-- ============================================================
-- STEP 3 - delete corresponding stock_movements rows
--          (synced by trigger, same created_at timestamp)
-- ============================================================
delete from public.stock_movements sm
using public.stock_adjustments sa
where sm.tenant_id     = '5443b130-cc28-45af-a420-cd500b288890'
  and sa.tenant_id     = '5443b130-cc28-45af-a420-cd500b288890'
  and sm.product_id    = sa.product_id
  and sm.created_at    = sa.created_at
  and sm.movement_type = 'manual'
  and sa.adjustment_type = 'manual'
  and coalesce(sa.reason, '') = 'Manual adjustment via product form'
  and sa.created_by is null;

-- ============================================================
-- STEP 4 - delete the stock_adjustments rows
-- ============================================================
delete from public.stock_adjustments
where tenant_id      = '5443b130-cc28-45af-a420-cd500b288890'
  and adjustment_type = 'manual'
  and coalesce(reason, '') = 'Manual adjustment via product form'
  and created_by is null;

-- ============================================================
-- STEP 5 - verify: all three counts should be 0 / no mismatch
-- ============================================================
select
  (select count(*)
   from public.stock_adjustments
   where tenant_id      = '5443b130-cc28-45af-a420-cd500b288890'
     and adjustment_type = 'manual'
     and coalesce(reason, '') = 'Manual adjustment via product form'
     and created_by is null)   as remaining_null_user_adjustments,

  (select count(*)
   from public.stock_movements sm
   where sm.tenant_id     = '5443b130-cc28-45af-a420-cd500b288890'
     and sm.movement_type = 'manual'
     and not exists (
       select 1 from public.stock_adjustments sa2
       where sa2.tenant_id    = '5443b130-cc28-45af-a420-cd500b288890'
         and sa2.product_id   = sm.product_id
         and sa2.created_at   = sm.created_at
         and sa2.adjustment_type = 'manual'
     ))                         as orphaned_manual_movements,

  (select count(*)
   from public.products
   where tenant_id     = '5443b130-cc28-45af-a420-cd500b288890'
     and inventory_qty <> stock_quantity) as stock_column_drift_rows;

commit;
