-- Rewrite stock_movements_view to use the stock_movements TABLE as source of truth
-- This ensures ALL movement types (Sales, Purchases, Adjustments, Mechanic Jobs, etc.) are included.
-- Previously, the view only queried invoices and adjustments, missing Mechanic Jobs and other sources.

drop view if exists stock_movements_view cascade;

create view stock_movements_view as
with movements_with_sign as (
  select 
    sm.id,
    sm.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sm.date as transaction_date,
    sm.movement_type,
    -- Parse source/reference for better display if needed
    coalesce(sm.movement_type, 'manual') as source,
    sm.id as reference_id,
    -- Extract readable reference or use raw reference
    coalesce(sm.reference, sm.id::text) as reference_number,
    -- Apply sign based on type (IN/OUT)
    case 
      when sm.type = 'OUT' then -abs(sm.quantity)
      when sm.type = 'IN' then abs(sm.quantity)
      else sm.quantity -- adjusting/transfer might be signed already? assume abs and define sign by type
    end as quantity, -- This quantity is SIGNED
    sm.notes,
    -- Created by/at
    -- We don't have created_by on stock_movements table in core schema? 
    -- Let's check. Schema says: id, tenant_id, product_id... created_at. No created_by column shown in snippet.
    -- We'll use null or map from join if critical. For now null.
    null::uuid as created_by,
    sm.created_at,
    sm.tenant_id
  from stock_movements sm
  left join products p on sm.product_id = p.id
),
movements_with_running_stock as (
  select 
    m.*,
    p.stock_quantity as current_stock,
    -- Calculate stock_after by working backwards from current stock
    -- stock_after = current_stock - (sum of FUTURE movements)
    -- If this is the most recent movement, sum of future is 0, so after = current.
    p.stock_quantity - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id 
        order by m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ), 
      0
    )::integer as calculated_stock_after
  from movements_with_sign m
  left join products p on m.product_id = p.id
)
select 
  id,
  product_id,
  product_name,
  product_sku,
  transaction_date,
  movement_type,
  source,
  reference_id,
  reference_number,
  quantity, -- Signed quantity
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

alter view stock_movements_view set (security_invoker = on);
