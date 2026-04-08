-- READ-ONLY investigation queries for the suspected sales invoice inventory bug.
-- Run these in order in Supabase SQL Editor.
--
-- Goal:
-- 1) Prove whether suspicious manual adjustments line up with sales invoice edits.
-- 2) Check whether posted invoices were edited and updated near those adjustments.
-- 3) Compare stock_movements ledger rows vs stock_adjustments rows for the same products.
-- 4) Identify likely affected invoices before running any repair.

-- ============================================================================
-- 1) Recent suspicious manual adjustments
-- ============================================================================
select
  sa.created_at,
  sa.id as adjustment_id,
  sa.product_id,
  p.name as product_name,
  p.sku as product_sku,
  sa.quantity,
  sa.stock_before,
  sa.stock_after,
  sa.reason,
  sa.reference,
  sa.created_by
from public.stock_adjustments sa
left join public.products p
  on p.id = sa.product_id
 and p.tenant_id = sa.tenant_id
where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sa.adjustment_type = 'manual'
  and coalesce(sa.reason, '') in (
    'Manual adjustment via product form',
    'Ajuste Manual'
  )
order by sa.created_at desc
limit 100;

-- ============================================================================
-- 2) Posted sales invoices updated recently
-- ============================================================================
select
  si.updated_at,
  si.created_at,
  si.id as invoice_id,
  si.invoice_number,
  si.status,
  si.customer_name,
  jsonb_array_length(coalesce(si.items, '[]'::jsonb)) as item_count,
  si.subtotal,
  si.iva_amount,
  si.total
from public.sales_invoices si
where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and lower(coalesce(si.status, 'draft')) not in (
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  )
order by si.updated_at desc
limit 100;

-- ============================================================================
-- 3) Match suspicious manual adjustments to posted invoices by product + time
--    This is the strongest first-pass proof.
-- ============================================================================
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
  where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and lower(coalesce(si.status, 'draft')) not in (
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
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
)
select
  sma.adjustment_created_at,
  sma.adjustment_id,
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
  abs(extract(epoch from (sma.adjustment_created_at - pii.invoice_updated_at))) as seconds_from_invoice_update
from suspicious_manual_adjustments sma
join posted_invoice_items pii
  on pii.tenant_id = sma.tenant_id
 and pii.product_id = sma.product_id
left join public.products p
  on p.id = sma.product_id
 and p.tenant_id = sma.tenant_id
where abs(extract(epoch from (sma.adjustment_created_at - pii.invoice_updated_at))) <= 30
order by sma.adjustment_created_at desc, pii.invoice_number;

-- ============================================================================
-- 4) Inspect one invoice in detail
--    Replace FV-00519 with the invoice number you want to inspect.
-- ============================================================================
select
  si.id,
  si.invoice_number,
  si.status,
  si.date,
  si.updated_at,
  si.customer_name,
  si.source,
  si.subtotal,
  si.iva_amount,
  si.total,
  jsonb_pretty(si.items) as items_pretty
from public.sales_invoices si
where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and si.invoice_number = 'FV-00519';

-- ============================================================================
-- 5) Stock movement ledger rows for one invoice
--    Replace FV-00519 if needed.
-- ============================================================================
select
  sm.created_at,
  sm.date as transaction_date,
  sm.id,
  sm.product_id,
  p.name as product_name,
  p.sku,
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.reference,
  sm.notes
from public.stock_movements sm
left join public.products p
  on p.id = sm.product_id
 and p.tenant_id = sm.tenant_id
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sm.reference = (
    select 'sales_invoice:' || si.id::text
    from public.sales_invoices si
    where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and si.invoice_number = 'FV-00519'
  )
order by sm.created_at desc, sm.id desc;

-- ============================================================================
-- 6) Manual adjustments for products that are in one invoice
--    Replace FV-00519 if needed.
-- ============================================================================
with invoice_items as (
  select
    si.id as invoice_id,
    si.invoice_number,
    si.updated_at,
    nullif(item->>'product_id', '')::uuid as product_id,
    item->>'product_name' as product_name,
    coalesce((item->>'quantity')::numeric, 0) as invoice_quantity
  from public.sales_invoices si
  cross join lateral jsonb_array_elements(coalesce(si.items, '[]'::jsonb)) item
  where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and si.invoice_number = 'FV-00519'
)
select
  sa.created_at,
  sa.id as adjustment_id,
  ii.invoice_number,
  ii.updated_at as invoice_updated_at,
  ii.product_id,
  p.name as product_name,
  p.sku,
  ii.invoice_quantity,
  sa.quantity as adjustment_quantity,
  sa.stock_before,
  sa.stock_after,
  abs(extract(epoch from (sa.created_at - ii.updated_at))) as seconds_from_invoice_update
from public.stock_adjustments sa
join invoice_items ii
  on ii.product_id = sa.product_id
left join public.products p
  on p.id = sa.product_id
 and p.tenant_id = sa.tenant_id
where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sa.adjustment_type = 'manual'
order by sa.created_at desc;

-- ============================================================================
-- 7) Find posted invoices that probably caused bogus manual adjustments
--    Aggregated view for triage.
-- ============================================================================
with posted_invoice_items as (
  select
    si.tenant_id,
    si.id as invoice_id,
    si.invoice_number,
    si.status,
    si.updated_at as invoice_updated_at,
    nullif(item->>'product_id', '')::uuid as product_id
  from public.sales_invoices si
  cross join lateral jsonb_array_elements(coalesce(si.items, '[]'::jsonb)) item
  where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and lower(coalesce(si.status, 'draft')) not in (
      'draft','borrador',
      'sent','enviado','enviada','issued','emitido','emitida',
      'cancelled','cancelado','cancelada','anulado','anulada'
    )
),
matched as (
  select distinct
    pii.invoice_id,
    pii.invoice_number,
    pii.status,
    pii.invoice_updated_at,
    sa.id as adjustment_id
  from posted_invoice_items pii
  join public.stock_adjustments sa
    on sa.tenant_id = pii.tenant_id
   and sa.product_id = pii.product_id
   and sa.adjustment_type = 'manual'
   and coalesce(sa.reason, '') in (
     'Manual adjustment via product form',
     'Ajuste Manual'
   )
   and abs(extract(epoch from (sa.created_at - pii.invoice_updated_at))) <= 30
)
select
  invoice_updated_at,
  invoice_id,
  invoice_number,
  status,
  count(*) as matched_manual_adjustments
from matched
group by invoice_updated_at, invoice_id, invoice_number, status
order by invoice_updated_at desc, matched_manual_adjustments desc;

-- ============================================================================
-- 8) Check if any sales-invoice ledger rows have the wrong sign
--    Sales should generally be OUT / negative quantity.
-- ============================================================================
select
  sm.created_at,
  sm.date as transaction_date,
  sm.id,
  sm.reference,
  sm.product_id,
  p.name as product_name,
  p.sku,
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.notes
from public.stock_movements sm
left join public.products p
  on p.id = sm.product_id
 and p.tenant_id = sm.tenant_id
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sm.reference like 'sales_invoice:%'
  and (sm.type <> 'OUT' or sm.quantity > 0)
order by sm.created_at desc
limit 100;

-- ============================================================================
-- 9) Compare suspicious manual adjustments vs stock_movements around same minute
--    Helps determine whether the bad row came from direct product updates.
-- ============================================================================
with suspicious as (
  select
    sa.id,
    sa.product_id,
    sa.created_at,
    sa.quantity,
    sa.stock_before,
    sa.stock_after
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
)
select
  s.created_at as adjustment_created_at,
  s.id as adjustment_id,
  p.name as product_name,
  p.sku,
  s.quantity as adjustment_qty,
  sm.created_at as movement_created_at,
  sm.reference,
  sm.type,
  sm.movement_type,
  sm.quantity as movement_qty,
  sm.notes
from suspicious s
left join public.stock_movements sm
  on sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
 and sm.product_id = s.product_id
 and abs(extract(epoch from (sm.created_at - s.created_at))) <= 30
left join public.products p
  on p.id = s.product_id
 and p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by s.created_at desc, sm.created_at desc;
