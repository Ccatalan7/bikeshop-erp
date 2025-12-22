-- Fix stock_movements_view to include Mechanic Jobs that have Invoices which are NOT yet confirmed (Gap filling)

create or replace view stock_movements_view as
with all_movements as (
  -- 1. Purchase Invoices (IN)
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
    ((item->>'quantity')::numeric)::integer as quantity, -- Positive
    pi.notes,
    pi.created_by,
    pi.created_at,
    pi.tenant_id
  from purchase_invoices pi,
       jsonb_array_elements(pi.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where pi.status in ('received', 'paid')

  union all

  -- 2. Sales Invoices (OUT)
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
    -((item->>'quantity')::numeric)::integer as quantity, -- Negaive
    si.reference as notes,
    si.created_by,
    si.created_at,
    si.tenant_id
  from sales_invoices si,
       jsonb_array_elements(si.items) as item
  left join products p on (item->>'product_id')::uuid = p.id
  where si.status in ('confirmed', 'paid')

  union all

  -- 3. Mechanic Jobs (OUT) - UNINVOICED OR PENDING INVOICE
  -- Include Job if:
  --   a) No invoice linked (mj.invoice_id IS NULL)
  --   b) Invoice linked but NOT confirmed/paid (gap filling)
  select 
    mji.id,
    mji.product_id,
    coalesce(mji.product_name, p.name) as product_name,
    coalesce(mji.product_sku, p.sku) as product_sku,
    mj.created_at as transaction_date,
    'mechanic_job' as movement_type,
    'workshop' as source,
    mj.id as reference_id,
    mj.job_number as reference_number,
    -(mji.quantity)::integer as quantity, -- Negative
    mj.notes,
    null::uuid as created_by,
    mji.created_at,
    mj.tenant_id
  from mechanic_job_items mji
  join mechanic_jobs mj on mji.job_id = mj.id
  left join products p on mji.product_id = p.id
  left join sales_invoices si on mj.invoice_id = si.id -- Check invoice status
  where 
    -- Include if invoice not present OR present but filtered out of Sales block above
    (mj.invoice_id is null OR si.status not in ('confirmed', 'paid') OR si.id is null)
    and mj.status not in ('borrador', 'draft', 'cancelado', 'cancelled')
    and (mji.item_type = 'product' or mji.item_type is null)
    and mji.product_id is not null

  union all

  -- 4. Stock Adjustments (IN/OUT)
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
    sa.tenant_id
  from stock_adjustments sa
  left join products p on sa.product_id = p.id
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
  from all_movements m
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
  quantity,
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

alter view stock_movements_view set (security_invoker = on);
