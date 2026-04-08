-- READ-ONLY verification after running
-- 20260407145000_cleanup_historical_sales_invoice_manual_adjustment_noise.sql.
--
-- Expected result after successful cleanup:
-- - No rows returned from the detail query
-- - Aggregate query returns zero rows

with suspicious_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity as adjustment_quantity,
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
    si.invoice_number,
    sa.product_id,
    sa.adjustment_quantity,
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
  where si.invoice_number in (
    'FV-00307',
    'FV-00123',
    'FV-00300',
    'FV-00338',
    'FV-00048',
    'FV-00074',
    'FV-00269',
    'FV-00471',
    'FV-00503',
    'FV-00011',
    'FV-00135',
    'FV-00170',
    'FV-00179',
    'FV-00201',
    'FV-00212',
    'FV-00283',
    'FV-00289',
    'FV-00490',
    'FV-00502',
    'FV-00504'
  )
)
select
  ms.invoice_number,
  ms.adjustment_created_at,
  p.name as product_name,
  p.sku,
  ms.adjustment_quantity,
  ms.adjustment_id,
  ms.sale_movement_id,
  abs(extract(epoch from (ms.sale_movement_created_at - ms.adjustment_created_at))) as seconds_to_sale_out
from matched_sales ms
left join public.products p
  on p.id = ms.product_id
 and p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by ms.adjustment_created_at desc, ms.invoice_number, p.name;

with suspicious_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
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
  where si.invoice_number in (
    'FV-00307',
    'FV-00123',
    'FV-00300',
    'FV-00338',
    'FV-00048',
    'FV-00074',
    'FV-00269',
    'FV-00471',
    'FV-00503',
    'FV-00011',
    'FV-00135',
    'FV-00170',
    'FV-00179',
    'FV-00201',
    'FV-00212',
    'FV-00283',
    'FV-00289',
    'FV-00490',
    'FV-00502',
    'FV-00504'
  )
)
select invoice_number, count(*) as remaining_suspicious_adjustment_rows
from matched_sales
group by invoice_number
order by remaining_suspicious_adjustment_rows desc, invoice_number;