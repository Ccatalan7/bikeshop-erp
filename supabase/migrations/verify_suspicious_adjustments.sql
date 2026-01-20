-- INVESTIGATION SCRIPT: Correlate Manual Adjustments with Purchase Invoices
-- This script will help you find the purchase invoice that likely triggered a "Manual Adjustment".

-- 1. We look for the product by SKU (from your screenshot: 4715575883212)
with target_product as (
    select id, name, sku 
    from products 
    where sku = '4715575883212'  -- <-- The SKU from your screenshot
    limit 1
),
-- 2. We get the "Suspicious" Manual Adjustments for this product
suspicious_adjustments as (
    select 
        sa.id as adjustment_id,
        sa.created_at, 
        sa.quantity, 
        sa.adjustment_type,
        sa.reason
    from stock_adjustments sa
    join target_product tp on sa.product_id = tp.id
    where sa.adjustment_type = 'manual' 
    order by sa.created_at desc
),
-- 3. We look for Purchase Invoices that contain this product
candidate_invoices as (
    select 
        pi.id as invoice_id,
        pi.invoice_number,
        pi.status,
        -- We try to find the timestamp that matches the adjustment
        -- Could be received_date, confirmed_date, or just updated_at
        coalesce(pi.received_date, pi.confirmed_date, pi.updated_at) as event_date,
        (item->>'quantity')::numeric as item_qty
    from purchase_invoices pi
    cross join jsonb_array_elements(pi.items) item
    join target_product tp on (item->>'product_sku') = tp.sku
)
-- 4. Correctly match them by Time (within 2 minutes) and Quantity
select 
    sa.created_at as "Hora Ajuste Manual",
    sa.quantity as "Cant.",
    ' <--- MATCH ---> ' as "Link",
    ci.invoice_number as "Factura Compra #",
    ci.event_date as "Hora Factura",
    ci.status as "Estado Factura"
from suspicious_adjustments sa
left join candidate_invoices ci 
    on sa.quantity = ci.item_qty -- Same quantity
    and abs(extract(epoch from (sa.created_at - ci.event_date))) < 120 -- Within 2 minutes
order by sa.created_at desc;
