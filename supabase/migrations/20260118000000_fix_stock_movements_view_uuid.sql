-- Fix invalid input syntax for type uuid in stock_movements_view
-- This ensures that if product_id is stored as text (or if empty strings appear), 
-- they are treated as NULL instead of crashing the UUID cast during JOIN.

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
      else sm.quantity 
    end as quantity, 
    sm.notes,
    null::uuid as created_by,
    sm.created_at,
    sm.tenant_id
  from stock_movements sm
  -- SAFE JOIN: Convert to text, nullify empty strings, then cast to UUID
  left join products p on nullif(sm.product_id::text, '')::uuid = p.id
),
movements_with_running_stock as (
  select 
    m.*,
    p.stock_quantity as current_stock,
    -- Calculate stock_after by working backwards from current stock
    p.stock_quantity - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id 
        order by m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ), 
      0
    )::integer as calculated_stock_after
  from movements_with_sign m
  left join products p on nullif(m.product_id::text, '')::uuid = p.id
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
  quantity,
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

alter view stock_movements_view set (security_invoker = on);
