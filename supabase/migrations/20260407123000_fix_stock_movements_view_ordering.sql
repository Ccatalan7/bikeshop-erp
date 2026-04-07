-- Fix stock_movements_view ordering so visible chronology and running stock
-- calculations use transaction_date first, with created_at/id only as
-- deterministic tiebreakers.

DROP VIEW IF EXISTS stock_movements_view CASCADE;

CREATE VIEW stock_movements_view AS
WITH movement_documents AS (
  SELECT
    sm.id,
    sm.product_id,
    p.name AS product_name,
    p.sku AS product_sku,
    sm.date AS transaction_date,
    sm.type,
    sm.movement_type AS raw_movement_type,
    sm.reference,
    CASE
      WHEN sm.type = 'OUT' THEN -ABS(sm.quantity)
      WHEN sm.type = 'IN' THEN ABS(sm.quantity)
      ELSE sm.quantity
    END AS quantity,
    sm.notes,
    NULL::uuid AS created_by,
    sm.created_at,
    sm.tenant_id,
    CASE
      WHEN COALESCE(sm.reference, '') ~ '^sales_invoice:[0-9a-fA-F-]{36}$'
        THEN split_part(sm.reference, ':', 2)::uuid
      WHEN COALESCE(sm.reference, '') ~ '^purchase_invoice:[0-9a-fA-F-]{36}$'
        THEN split_part(sm.reference, ':', 2)::uuid
      WHEN COALESCE(sm.reference, '') ~ '^mechanic_job:[0-9a-fA-F-]{36}$'
        THEN split_part(sm.reference, ':', 2)::uuid
      ELSE NULL::uuid
    END AS document_id,
    CASE
      WHEN COALESCE(sm.reference, '') LIKE 'sales_invoice:%' THEN 'sales_invoice'
      WHEN COALESCE(sm.reference, '') LIKE 'purchase_invoice:%' THEN 'purchase_invoice'
      WHEN COALESCE(sm.reference, '') LIKE 'mechanic_job:%' THEN 'mechanic_job'
      ELSE NULL::text
    END AS document_type
  FROM stock_movements sm
  LEFT JOIN products p
    ON NULLIF(sm.product_id::text, '')::uuid = p.id
   AND sm.tenant_id = p.tenant_id
),
movements_with_resolution AS (
  SELECT
    md.id,
    md.product_id,
    md.product_name,
    md.product_sku,
    md.transaction_date,
    CASE
      WHEN md.document_type = 'sales_invoice' THEN 'sale'
      WHEN md.document_type = 'purchase_invoice' THEN 'purchase'
      WHEN md.document_type = 'mechanic_job' THEN 'sale'
      WHEN COALESCE(md.raw_movement_type, '') IN ('purchase', 'purchase_invoice', 'manual_purchase') THEN 'purchase'
      WHEN COALESCE(md.raw_movement_type, '') IN ('sale', 'sales_invoice', 'sales_invoice_component', 'manual_sale') THEN 'sale'
      WHEN COALESCE(md.raw_movement_type, '') IN ('transfer', 'transfer_in', 'transfer_out') THEN 'transfer'
      WHEN COALESCE(md.raw_movement_type, '') IN ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'adjustment', 'inventory_adjust', 'inventory_adjustment') THEN 'adjustment'
      ELSE 'adjustment'
    END AS movement_type,
    CASE
      WHEN md.document_type = 'sales_invoice' THEN COALESCE(si.source, 'sale')
      WHEN md.document_type = 'purchase_invoice' THEN 'purchase_invoice'
      WHEN md.document_type = 'mechanic_job' THEN 'mechanic_job'
      WHEN NULLIF(TRIM(COALESCE(md.raw_movement_type, '')), '') IS NOT NULL THEN md.raw_movement_type
      ELSE 'manual'
    END AS source,
    CASE
      WHEN md.document_type IN ('sales_invoice', 'purchase_invoice', 'mechanic_job') THEN md.document_id
      ELSE NULL::uuid
    END AS reference_id,
    CASE
      WHEN md.document_type = 'sales_invoice' THEN COALESCE(NULLIF(si.invoice_number, ''), md.reference)
      WHEN md.document_type = 'purchase_invoice' THEN COALESCE(NULLIF(pi.invoice_number, ''), md.reference)
      WHEN md.document_type = 'mechanic_job' THEN COALESCE(NULLIF(mj.job_number, ''), md.reference)
      WHEN NULLIF(TRIM(COALESCE(md.reference, '')), '') IS NOT NULL THEN md.reference
      WHEN NULLIF(TRIM(COALESCE(md.notes, '')), '') IS NOT NULL THEN md.notes
      ELSE NULL::text
    END AS reference_number,
    md.quantity,
    md.notes,
    md.created_by,
    md.created_at,
    md.tenant_id
  FROM movement_documents md
  LEFT JOIN sales_invoices si
    ON md.document_type = 'sales_invoice'
   AND md.document_id = si.id
   AND md.tenant_id = si.tenant_id
  LEFT JOIN purchase_invoices pi
    ON md.document_type = 'purchase_invoice'
   AND md.document_id = pi.id
   AND md.tenant_id = pi.tenant_id
  LEFT JOIN mechanic_jobs mj
    ON md.document_type = 'mechanic_job'
   AND md.document_id = mj.id
   AND md.tenant_id = mj.tenant_id
),
movements_with_running_stock AS (
  SELECT
    m.*,
    GREATEST(COALESCE(p.stock_quantity, 0), COALESCE(p.inventory_qty, 0)) AS current_stock,
    GREATEST(COALESCE(p.stock_quantity, 0), COALESCE(p.inventory_qty, 0)) - COALESCE(
      SUM(m.quantity) OVER (
        PARTITION BY m.product_id, m.tenant_id
        ORDER BY m.transaction_date DESC NULLS LAST, m.created_at DESC, m.id DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ),
      0
    )::integer AS calculated_stock_after
  FROM movements_with_resolution m
  LEFT JOIN products p
    ON NULLIF(m.product_id::text, '')::uuid = p.id
   AND m.tenant_id = p.tenant_id
)
SELECT
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
  (calculated_stock_after - quantity)::integer AS stock_before,
  calculated_stock_after AS stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
FROM movements_with_running_stock;

ALTER VIEW stock_movements_view SET (security_invoker = on);
