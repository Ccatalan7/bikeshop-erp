-- ============================================================================
-- FIX: Stock Movements View - Quantity Type Casting Issue
-- ============================================================================
-- Problem: PostgrestException "invalid input syntax for type integer: '1.00'"
-- Root Cause: Invoice items store quantity as JSONB numeric (e.g., "1.00")
--             Direct cast to integer fails: (item->>'quantity')::integer
-- Solution: Cast to numeric first, then to integer: ((item->>'quantity')::numeric)::integer
-- Date: November 7, 2025
-- ============================================================================

-- Drop and recreate the view with fixed quantity casting
drop view if exists stock_movements_view cascade;

create view stock_movements_view as
with all_movements as (
  -- Purchase Invoice Items (increases stock)
  select 
    gen_random_uuid() as id,
    (item->>'product_id')::uuid as product_id,
    p.name as product_name,
    p.sku as product_sku,
    pi.date as transaction_date,
    'purchase' as movement_type,
    'manual_purchase' as source,
    pi.id as reference_id,
    pi.invoice_number as reference_number,
    ((item->>'quantity')::numeric)::integer as quantity,  -- ✅ FIXED: numeric → integer
    pi.notes,
    pi.created_by,
    pi.created_at,
    pi.tenant_id,
    null::integer as stock_before,
    null::integer as stock_after
  from purchase_invoices pi,
       jsonb_array_elements(pi.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where pi.status in ('received', 'paid')
  
  union all
  
  -- Sales Invoice Items (decreases stock)
  select 
    gen_random_uuid() as id,
    (item->>'product_id')::uuid as product_id,
    p.name as product_name,
    p.sku as product_sku,
    si.date as transaction_date,
    'sale' as movement_type,
    coalesce(si.source, 'manual_sale') as source,
    si.id as reference_id,
    si.invoice_number as reference_number,
    -((item->>'quantity')::numeric)::integer as quantity,  -- ✅ FIXED: numeric → integer
    si.reference as notes,
    si.created_by,
    si.created_at,
    si.tenant_id,
    null::integer as stock_before,
    null::integer as stock_after
  from sales_invoices si,
       jsonb_array_elements(si.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where si.status in ('sent', 'paid')
  
  union all
  
  -- Stock Adjustments (manual changes, corrections, etc.)
  select 
    sa.id,
    sa.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sa.created_at as transaction_date,
    'adjustment' as movement_type,
    sa.adjustment_type as source,
    sa.id as reference_id,
    'ADJ-' || to_char(sa.created_at, 'YYYYMMDD-HH24MISS') as reference_number,
    sa.quantity,
    sa.reason as notes,
    sa.created_by,
    sa.created_at,
    sa.tenant_id,
    sa.stock_before,
    sa.stock_after
  from stock_adjustments sa
  left join products p on sa.product_id = p.id
),
movements_with_running_stock as (
  select 
    m.id,
    m.product_id,
    m.product_name,
    m.product_sku,
    m.transaction_date,
    m.movement_type,
    m.source,
    m.reference_id,
    m.reference_number,
    m.quantity,
    m.notes,
    m.created_by,
    m.created_at,
    m.tenant_id,
    m.stock_before as stored_stock_before,
    m.stock_after as stored_stock_after,
    p.stock_quantity as current_stock,
    p.stock_quantity - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id 
        order by m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ),
      0
    )::integer as calculated_stock_after
  from all_movements m
  left join products p on m.product_id = p.id and m.tenant_id = p.tenant_id
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
  coalesce(stored_stock_before, (calculated_stock_after - quantity)::integer) as stock_before,
  coalesce(stored_stock_after, calculated_stock_after) as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

-- Enable RLS
alter view stock_movements_view set (security_invoker = on);

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Test the view with a specific product
-- SELECT * FROM stock_movements_view WHERE product_id = 'your-product-id' LIMIT 10;

-- Check for any remaining casting issues
-- SELECT product_name, quantity, movement_type FROM stock_movements_view LIMIT 100;
