-- PRE-DEPLOY INSPECTION PACK
-- Purpose: inspect stock movement integrity before applying the stock movement view/source fixes.
-- Safe: read-only. No writes.
-- Run sections one by one in Supabase SQL Editor.

-- ============================================================================
-- 0) PARAMETERS
-- Replace these values as needed before running the sections below.
-- ============================================================================

-- Primary tenant: Vinabike
-- 5443b130-cc28-45af-a420-cd500b288890

-- Example SKU from investigation:
-- 4715575883212


-- ============================================================================
-- 1) TARGET PRODUCT SNAPSHOT
-- Confirms product identity and current stock columns.
-- ============================================================================

select
  p.id,
  p.tenant_id,
  p.name,
  p.sku,
  p.inventory_qty,
  p.stock_quantity,
  p.updated_at
from public.products p
where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and p.sku = '4715575883212';


-- ============================================================================
-- 2) CURRENT VIEW OUTPUT FOR ONE PRODUCT
-- This shows what the UI currently sees.
-- ============================================================================

with target_product as (
  select id
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sku = '4715575883212'
  limit 1
)
select
  smv.id,
  smv.transaction_date,
  smv.created_at,
  smv.movement_type,
  smv.source,
  smv.reference_id,
  smv.reference_number,
  smv.quantity,
  smv.stock_before,
  smv.stock_after,
  smv.notes,
  smv.tenant_id
from public.stock_movements_view smv
join target_product tp on tp.id = smv.product_id
order by smv.created_at desc
limit 100;


-- ============================================================================
-- 3) RAW STOCK_MOVEMENTS FOR THE SAME PRODUCT
-- This shows raw movement rows before the view transforms them.
-- ============================================================================

with target_product as (
  select id
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sku = '4715575883212'
  limit 1
)
select
  sm.id,
  sm.created_at,
  sm.date,
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.reference,
  sm.notes,
  sm.tenant_id
from public.stock_movements sm
join target_product tp on tp.id = sm.product_id
order by sm.created_at desc
limit 100;


-- ============================================================================
-- 4) RAW STOCK_ADJUSTMENTS FOR THE SAME PRODUCT
-- Useful for checking whether product-form/manual adjustments are being logged.
-- ============================================================================

with target_product as (
  select id
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sku = '4715575883212'
  limit 1
)
select
  sa.id,
  sa.created_at,
  sa.adjustment_type,
  sa.quantity,
  sa.stock_before,
  sa.stock_after,
  sa.reason,
  sa.reference,
  sa.created_by,
  sa.tenant_id
from public.stock_adjustments sa
join target_product tp on tp.id = sa.product_id
order by sa.created_at desc
limit 100;


-- ============================================================================
-- 5) SUSPECT "MANUAL" ROWS THAT ALREADY LOOK DOCUMENT-DRIVEN
-- These are the rows most likely to be mislabeled by the current view.
-- ============================================================================

select
  sm.id,
  sm.product_id,
  p.sku,
  p.name,
  sm.created_at,
  sm.type,
  sm.movement_type,
  sm.reference,
  sm.notes,
  sm.quantity,
  sm.tenant_id
from public.stock_movements sm
left join public.products p
  on p.id = sm.product_id
 and p.tenant_id = sm.tenant_id
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and coalesce(sm.movement_type, '') in ('', 'manual')
  and (
    coalesce(sm.reference, '') like 'sales_invoice:%'
    or coalesce(sm.reference, '') like 'purchase_invoice:%'
    or coalesce(sm.reference, '') like 'mechanic_job:%'
  )
order by sm.created_at desc
limit 200;


-- ============================================================================
-- 6) POTENTIAL DUPLICATE MANUAL LOGS
-- Heuristic: a stock_adjustment and stock_movement on the same product, same
-- quantity, same tenant, within 10 seconds. This is the main duplication check.
-- ============================================================================

select
  sa.product_id,
  p.sku,
  p.name,
  sa.id as adjustment_id,
  sa.created_at as adjustment_created_at,
  sa.adjustment_type,
  sa.quantity as adjustment_quantity,
  sa.reason,
  sm.id as movement_id,
  sm.created_at as movement_created_at,
  sm.type as movement_direction,
  sm.movement_type,
  sm.quantity as movement_quantity,
  sm.reference,
  sm.notes,
  abs(extract(epoch from (sm.created_at - sa.created_at))) as seconds_apart,
  sa.tenant_id
from public.stock_adjustments sa
join public.stock_movements sm
  on sm.product_id = sa.product_id
 and sm.tenant_id = sa.tenant_id
 and sm.quantity = sa.quantity
 and abs(extract(epoch from (sm.created_at - sa.created_at))) <= 10
left join public.products p
  on p.id = sa.product_id
 and p.tenant_id = sa.tenant_id
where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by sa.created_at desc
limit 300;


-- ============================================================================
-- 7) UGLY/BROKEN REFERENCE CANDIDATES IN THE CURRENT VIEW
-- Current bug pattern: reference_number falls back to raw UUID-ish values.
-- ============================================================================

select
  smv.id,
  smv.product_id,
  smv.product_sku,
  smv.product_name,
  smv.created_at,
  smv.movement_type,
  smv.source,
  smv.reference_id,
  smv.reference_number,
  smv.quantity,
  smv.tenant_id
from public.stock_movements_view smv
where smv.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and (
    smv.reference_number ~ '^[0-9a-fA-F-]{36}$'
    or smv.reference_id is null and coalesce(smv.reference_number, '') <> ''
  )
order by smv.created_at desc
limit 300;


-- ============================================================================
-- 8) SALES INVOICE SOURCE COVERAGE
-- Shows whether invoice rows are missing source by flow.
-- ============================================================================

select
  coalesce(si.source, '<null>') as source,
  si.status,
  count(*) as invoice_count,
  min(si.created_at) as first_seen,
  max(si.created_at) as last_seen
from public.sales_invoices si
where si.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
group by coalesce(si.source, '<null>'), si.status
order by invoice_count desc, source, si.status;


-- ============================================================================
-- 9) WEBSITE ORDERS WITH LINKED INVOICES BUT WRONG/MISSING SOURCE
-- These should normally resolve to ecommerce after the source-stamp fix.
-- ============================================================================

select
  oo.id as order_id,
  oo.order_number,
  oo.created_at as order_created_at,
  oo.payment_method,
  oo.payment_status,
  oo.sales_invoice_id,
  si.invoice_number,
  si.status as invoice_status,
  si.source as invoice_source,
  si.reference as invoice_reference,
  si.created_at as invoice_created_at
from public.online_orders oo
left join public.sales_invoices si
  on si.id = oo.sales_invoice_id
 and si.tenant_id = oo.tenant_id
where oo.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and oo.sales_invoice_id is not null
  and coalesce(si.source, '') <> 'ecommerce'
order by oo.created_at desc
limit 200;


-- ============================================================================
-- 10) MECHANIC JOB INVOICES WITH WRONG/MISSING SOURCE
-- These should normally resolve to mechanic_job after the source-stamp fix.
-- ============================================================================

select
  mj.id as job_id,
  mj.job_number,
  mj.created_at as job_created_at,
  mj.invoice_id,
  si.invoice_number,
  si.status,
  si.source,
  si.reference,
  si.created_at as invoice_created_at
from public.mechanic_jobs mj
left join public.sales_invoices si
  on si.id = mj.invoice_id
 and si.tenant_id = mj.tenant_id
where mj.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and mj.invoice_id is not null
  and coalesce(si.source, '') <> 'mechanic_job'
order by mj.created_at desc
limit 200;


-- ============================================================================
-- 11) RECENT STOCK MOVEMENTS BY ORIGIN PATTERN
-- This gives a tenant-level overview of what is actually being recorded today.
-- ============================================================================

select
  coalesce(sm.movement_type, '<null>') as raw_movement_type,
  case
    when coalesce(sm.reference, '') like 'sales_invoice:%' then 'sales_invoice_ref'
    when coalesce(sm.reference, '') like 'purchase_invoice:%' then 'purchase_invoice_ref'
    when coalesce(sm.reference, '') like 'mechanic_job:%' then 'mechanic_job_ref'
    when coalesce(sm.reference, '') = '' then 'no_reference'
    else 'other_reference'
  end as reference_pattern,
  sm.type,
  count(*) as row_count,
  min(sm.created_at) as first_seen,
  max(sm.created_at) as last_seen
from public.stock_movements sm
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
group by coalesce(sm.movement_type, '<null>'), reference_pattern, sm.type
order by row_count desc, last_seen desc;


-- ============================================================================
-- 12) PRODUCTS WITH THE MOST "MANUAL" HISTORY
-- Useful to spot whether the problem is isolated or systemic.
-- ============================================================================

select
  sm.product_id,
  p.sku,
  p.name,
  count(*) as manual_like_rows,
  min(sm.created_at) as first_seen,
  max(sm.created_at) as last_seen
from public.stock_movements sm
left join public.products p
  on p.id = sm.product_id
 and p.tenant_id = sm.tenant_id
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and coalesce(sm.movement_type, '') in ('', 'manual')
group by sm.product_id, p.sku, p.name
order by manual_like_rows desc, last_seen desc
limit 100;


-- ============================================================================
-- 13) SALES/PURCHASE REFERENCE RESOLUTION CHECK
-- This shows whether raw movement references can be resolved to real documents.
-- ============================================================================

with docs as (
  select
    sm.id as movement_id,
    sm.created_at,
    sm.product_id,
    sm.reference,
    sm.movement_type,
    sm.tenant_id,
    case
      when coalesce(sm.reference, '') ~ '^sales_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^purchase_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^mechanic_job:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      else null::uuid
    end as document_id,
    case
      when coalesce(sm.reference, '') like 'sales_invoice:%' then 'sales_invoice'
      when coalesce(sm.reference, '') like 'purchase_invoice:%' then 'purchase_invoice'
      when coalesce(sm.reference, '') like 'mechanic_job:%' then 'mechanic_job'
      else null::text
    end as document_type
  from public.stock_movements sm
  where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
)
select
  d.movement_id,
  d.created_at,
  d.product_id,
  p.sku,
  p.name,
  d.movement_type,
  d.reference,
  d.document_type,
  d.document_id,
  si.invoice_number as sales_invoice_number,
  pi.invoice_number as purchase_invoice_number,
  mj.job_number as mechanic_job_number
from docs d
left join public.products p
  on p.id = d.product_id
 and p.tenant_id = d.tenant_id
left join public.sales_invoices si
  on d.document_type = 'sales_invoice'
 and si.id = d.document_id
 and si.tenant_id = d.tenant_id
left join public.purchase_invoices pi
  on d.document_type = 'purchase_invoice'
 and pi.id = d.document_id
 and pi.tenant_id = d.tenant_id
left join public.mechanic_jobs mj
  on d.document_type = 'mechanic_job'
 and mj.id = d.document_id
 and mj.tenant_id = d.tenant_id
where d.document_type is not null
order by d.created_at desc
limit 300;