-- READ-ONLY preview of sales-invoice-trigger manual-adjustment noise.
--
-- This identifies the specific bogus pattern:
--   1) stock_adjustments manual row
--   2) matching stock_movements manual row at the same timestamp
--   3) matching sales OUT row for the same product within 30 seconds
--
-- It intentionally excludes plain manual edits that do NOT have a nearby
-- sales-invoice OUT row.

with suspicious_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity as adjustment_quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at as adjustment_created_at
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
), matched_sales as (
  select distinct
    sa.adjustment_id,
    sa.adjustment_created_at,
    sa.product_id,
    sa.adjustment_quantity,
    si.id as invoice_id,
    si.invoice_number,
    sm_sale.id as sale_movement_id,
    sm_sale.created_at as sale_movement_created_at
  from suspicious_adjustments sa
  join public.stock_movements sm_sale
    on sm_sale.tenant_id = sa.tenant_id
   and sm_sale.product_id = sa.product_id
   and sm_sale.reference like 'sales_invoice:%'
   and sm_sale.type = 'OUT'
   and abs(extract(epoch from (sm_sale.created_at - sa.adjustment_created_at))) <= 30
  join public.sales_invoices si
    on si.tenant_id = sm_sale.tenant_id
   and sm_sale.reference = 'sales_invoice:' || si.id::text
), matched_manual_movements as (
  select distinct
    sa.adjustment_id,
    sm_manual.id as manual_movement_id
  from suspicious_adjustments sa
  join public.stock_movements sm_manual
    on sm_manual.tenant_id = sa.tenant_id
   and sm_manual.product_id = sa.product_id
   and sm_manual.created_at = sa.adjustment_created_at
   and sm_manual.type = case when sa.adjustment_quantity >= 0 then 'IN' else 'OUT' end
   and coalesce(sm_manual.movement_type, '') = 'manual'
   and sm_manual.quantity = abs(sa.adjustment_quantity)
   and coalesce(sm_manual.reference, '') = coalesce(sa.reference, '')
   and coalesce(sm_manual.notes, '') = coalesce(sa.reason, '')
)
select
  ms.invoice_number,
  ms.adjustment_created_at,
  p.name as product_name,
  p.sku,
  ms.adjustment_quantity,
  ms.adjustment_id,
  ms.sale_movement_id,
  mmm.manual_movement_id,
  abs(extract(epoch from (ms.sale_movement_created_at - ms.adjustment_created_at))) as seconds_to_sale_out
from matched_sales ms
left join matched_manual_movements mmm
  on mmm.adjustment_id = ms.adjustment_id
left join public.products p
  on p.id = ms.product_id
 and p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by ms.adjustment_created_at desc, ms.invoice_number, p.name;

-- Aggregate by invoice
with suspicious_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity as adjustment_quantity,
    sa.reference,
    sa.reason,
    sa.created_at as adjustment_created_at
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
), matched_sales as (
  select distinct
    sa.adjustment_id,
    si.invoice_number
  from suspicious_adjustments sa
  join public.stock_movements sm_sale
    on sm_sale.tenant_id = sa.tenant_id
   and sm_sale.product_id = sa.product_id
   and sm_sale.reference like 'sales_invoice:%'
   and sm_sale.type = 'OUT'
   and abs(extract(epoch from (sm_sale.created_at - sa.adjustment_created_at))) <= 30
  join public.sales_invoices si
    on si.tenant_id = sm_sale.tenant_id
   and sm_sale.reference = 'sales_invoice:' || si.id::text
)
select invoice_number, count(*) as suspicious_adjustment_rows
from matched_sales
group by invoice_number
order by suspicious_adjustment_rows desc, invoice_number;
