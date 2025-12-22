-- Fix stock_movements_view filters to match actual inventory consumption logic
-- Ref Issue: Stock movements calculation discrepancy (gaps in history/math)
-- Root Cause: View was including 'sent' (non-consuming) and excluding 'confirmed' (consuming) invoices.

-- Drop existing view
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
    ((item->>'quantity')::numeric)::integer as quantity,
    pi.notes,
    pi.created_by,
    pi.created_at,
    pi.tenant_id,
    null::integer as stock_before,  -- Will be calculated
    null::integer as stock_after    -- Will be calculated
  from purchase_invoices pi,
       jsonb_array_elements(pi.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  -- PURCHASE FILTER: received, paid (Standard consumption on received)
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
    -((item->>'quantity')::numeric)::integer as quantity, -- Negative for sales
    si.reference as notes,
    si.created_by,
    si.created_at,
    si.tenant_id,
    null::integer as stock_before,  -- Will be calculated
    null::integer as stock_after    -- Will be calculated
  from sales_invoices si,
       jsonb_array_elements(si.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  -- SALE FILTER CORRECTION: confirmed, paid (Standard consumption on confirmed)
  -- Exclude: draft, sent, cancelled
  where si.status in ('confirmed', 'paid')
  
  union all
  
  -- Stock Adjustments (manual changes, corrections, etc.)
  -- NOTE: Adjustments already have stock_before/stock_after stored, so we include them
  select 
    sa.id,
    sa.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sa.created_at as transaction_date, -- Use created_at for adjustments consistency
    'adjustment' as movement_type,
    sa.adjustment_type as source,
    sa.id as reference_id,
    'ADJ-' || to_char(sa.created_at, 'YYYYMMDD-HH24MISS') as reference_number,
    sa.quantity,
    sa.reason as notes,
    sa.created_by,
    sa.created_at,
    sa.tenant_id,
    sa.stock_before,  -- Already stored in table
    sa.stock_after    -- Already stored in table
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
    m.stock_before as stored_stock_before,  -- From adjustments only
    m.stock_after as stored_stock_after,    -- From adjustments only
    p.stock_quantity as current_stock,
    -- Calculate stock_after by working backwards from current stock
    -- Subtract all changes that happened AFTER this transaction (newer transactions)
    -- NOTE: coalesce(sum(...), 0) returns 0 for the most recent transaction, so it starts at current_stock
    p.stock_quantity - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id 
        order by m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ),
      0
    )::integer as calculated_stock_after
  from all_movements m
  left join products p on m.product_id = p.id
  -- We don't join on tenant_id for products here to allow safer left join if needed, 
  -- but RLS will handle visibility.
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
  -- For adjustments: use stored_stock_before, for sales/purchases: calculate it
  coalesce(stored_stock_before, (calculated_stock_after - quantity)::integer) as stock_before,
  -- For adjustments: use stored_stock_after, for sales/purchases: use calculated
  coalesce(stored_stock_after, calculated_stock_after) as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

-- Ensure RLS is enabled (View inherits security of underlying tables, but we set invoker)
alter view stock_movements_view set (security_invoker = on);
