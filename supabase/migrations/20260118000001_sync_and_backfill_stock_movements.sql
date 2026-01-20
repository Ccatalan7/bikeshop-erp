-- Migration: Sync stock_adjustments to stock_movements and Backfill History
-- FIXED: Removed invalid 'source' column. Maps adjustment_type to movement_type.

-- 1. Create Function to sync new adjustments to movements automatically
create or replace function sync_stock_adjustment_to_movement()
returns trigger as $$
begin
  insert into stock_movements (
    tenant_id, 
    product_id, 
    date, 
    type, 
    movement_type, 
    -- source column removed (it does not exist in stock_movements table)
    reference, 
    quantity, 
    notes, 
    created_at
  ) values (
    NEW.tenant_id, 
    NEW.product_id, 
    NEW.created_at, -- transaction date
    case when NEW.quantity >= 0 then 'IN' else 'OUT' end,
    -- Map adjustment_type (e.g. 'initial') to movement_type so it shows up correctly in the view/UI
    NEW.adjustment_type, 
    NEW.reference,
    abs(NEW.quantity),
    NEW.reason,
    NEW.created_at
  );
  return NEW;
end;
$$ language plpgsql security definer;

-- 2. Create Trigger (if not exists)
drop trigger if exists trg_sync_adjustment_to_movement on stock_adjustments;
create trigger trg_sync_adjustment_to_movement
  after insert on stock_adjustments
  for each row
  execute function sync_stock_adjustment_to_movement();

-- 3. Backfill: Copy EXISTING adjustments that are missing from stock_movements
insert into stock_movements (
  tenant_id, product_id, date, type, movement_type, reference, quantity, notes, created_at
)
select
  tenant_id,
  product_id,
  created_at as date,
  case when quantity >= 0 then 'IN' else 'OUT' end as type,
  adjustment_type as movement_type, -- Map adjustment_type to movement_type
  reference,
  abs(quantity),
  reason as notes,
  created_at
from stock_adjustments sa
where not exists (
  select 1 from stock_movements sm
  where sm.product_id = sa.product_id 
  and sm.created_at = sa.created_at
);

-- 4. Backfill: Ghost Stock (Products with stock > 0 but NO history at all)
insert into stock_movements (
  tenant_id, product_id, date, type, movement_type, reference, quantity, notes, created_at
)
select
  p.tenant_id,
  p.id,
  p.created_at,
  'IN',
  'initial', -- Set movement_type to 'initial'
  'Backfill-Ghost',
  abs(p.stock_quantity),
  'Stock inicial reparado (sin historial previo)',
  p.created_at
from products p
where p.stock_quantity > 0
-- Ensure no existing movements or adjustments for this product
and not exists (select 1 from stock_adjustments sa where sa.product_id = p.id)
and not exists (select 1 from stock_movements sm where sm.product_id = p.id);
