-- INVESTIGATION PART 2: Identification of "Reference" UUIDs
-- The "Manual Adjustments" have UUIDs in the reference column. 
-- We will find out which table these UUIDs belong to.

with target_product as (
    select id from products where sku = '4715575883212' limit 1
),
mystery_references as (
    select distinct reference as ref_id
    from stock_adjustments sa
    join target_product tp on sa.product_id = tp.id
    where sa.adjustment_type = 'manual'
    and sa.reference is not null
    and sa.reference ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- Valid UUID format
)
select 
    mr.ref_id as "Reference UUID",
    case 
        when exists (select 1 from purchase_invoices where id::text = mr.ref_id) then 'PURCHASE INVOICE'
        when exists (select 1 from sales_invoices where id::text = mr.ref_id) then 'SALES INVOICE'
        when exists (select 1 from products where id::text = mr.ref_id) then 'PRODUCT ID (Self Ref?)'
        -- Add other potential tables if known
        else 'UNKNOWN / MANUAL ENTRY'
    end as "Source Table"
from mystery_references mr;
