-- Audit suspicious manual stock adjustments likely caused by editing posted sales invoices.
--
-- Heuristic:
--   - stock_adjustments.adjustment_type = 'manual'
--   - reason matches known trigger leak labels observed in production
--       * 'Manual adjustment via product form'
--       * 'Ajuste Manual'
--   - product appears inside a posted sales invoice
--   - adjustment timestamp is very close to the invoice updated_at timestamp
--
-- This does NOT change data. It helps identify rows to review before cleanup.

with posted_invoice_items as (
  select
    si.tenant_id,
    si.id as invoice_id,
    si.invoice_number,
    si.status,
    si.updated_at as invoice_updated_at,
    nullif(item->>'product_id', '')::uuid as product_id,
    item->>'product_name' as invoice_product_name,
    coalesce((item->>'quantity')::numeric, 0) as invoice_quantity
  from public.sales_invoices si
  cross join lateral jsonb_array_elements(coalesce(si.items, '[]'::jsonb)) item
  where lower(coalesce(si.status, 'draft')) not in (
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  )
),
suspicious_manual_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity as adjustment_quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at as adjustment_created_at,
    sa.created_by
  from public.stock_adjustments sa
  where sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
)
select
  sma.adjustment_id,
  sma.adjustment_created_at,
  p.name as product_name,
  p.sku as product_sku,
  sma.adjustment_quantity,
  sma.stock_before,
  sma.stock_after,
  pii.invoice_id,
  pii.invoice_number,
  pii.status as invoice_status,
  pii.invoice_updated_at,
  pii.invoice_quantity,
  abs(extract(epoch from (sma.adjustment_created_at - pii.invoice_updated_at))) as seconds_from_invoice_update,
  sma.created_by
from suspicious_manual_adjustments sma
join posted_invoice_items pii
  on pii.tenant_id = sma.tenant_id
 and pii.product_id = sma.product_id
left join public.products p
  on p.id = sma.product_id
 and p.tenant_id = sma.tenant_id
where abs(extract(epoch from (sma.adjustment_created_at - pii.invoice_updated_at))) <= 15
order by sma.adjustment_created_at desc, pii.invoice_number;
