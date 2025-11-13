-- Find all data created by tenant 46e169a4-ba62-4f86-92cd-778ece1b0afa in the last 8 hours
-- WITH DETAILED INFORMATION

WITH tenant_filter AS (
  SELECT '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid as tenant_id,
         now() - interval '8 hours' as cutoff_time
)

-- Customers
SELECT 
  'customers' as table_name, 
  c.id, 
  c.created_at, 
  c.name as description,
  jsonb_build_object(
    'email', c.email,
    'phone', c.phone,
    'rut', c.rut
  ) as details
FROM customers c, tenant_filter tf
WHERE c.tenant_id = tf.tenant_id 
  AND c.created_at >= tf.cutoff_time

UNION ALL

-- Bike Brands
SELECT 
  'bike_brands' as table_name, 
  bb.id, 
  bb.created_at,
  bb.name as description,
  jsonb_build_object(
    'country', bb.country,
    'is_active', bb.is_active
  ) as details
FROM bike_brands bb, tenant_filter tf
WHERE bb.tenant_id = tf.tenant_id 
  AND bb.created_at >= tf.cutoff_time

UNION ALL

-- Bike Models
SELECT 
  'bike_models' as table_name, 
  bm.id, 
  bm.created_at,
  bm.name as description,
  jsonb_build_object(
    'brand_id', bm.brand_id,
    'year', bm.year,
    'is_active', bm.is_active
  ) as details
FROM bike_models bm, tenant_filter tf
WHERE bm.tenant_id = tf.tenant_id 
  AND bm.created_at >= tf.cutoff_time

UNION ALL

-- Bikes
SELECT 
  'bikes' as table_name, 
  b.id, 
  b.created_at,
  COALESCE(b.brand, bb.name, 'Unknown') || ' ' || 
  COALESCE(b.model, bm.name, 'Unknown') as description,
  jsonb_build_object(
    'customer_id', b.customer_id,
    'serial_number', b.serial_number,
    'year', b.year,
    'color', b.color,
    'bike_type', b.bike_type
  ) as details
FROM bikes b
LEFT JOIN bike_brands bb ON b.brand_id = bb.id
LEFT JOIN bike_models bm ON b.model_id = bm.id
CROSS JOIN tenant_filter tf
WHERE b.tenant_id = tf.tenant_id 
  AND b.created_at >= tf.cutoff_time

UNION ALL

-- Mechanic Jobs
SELECT 
  'mechanic_jobs' as table_name, 
  mj.id, 
  mj.created_at,
  'Job #' || mj.job_number as description,
  jsonb_build_object(
    'customer_id', mj.customer_id,
    'bike_id', mj.bike_id,
    'status', mj.status,
    'client_request', mj.client_request,
    'diagnosis', mj.diagnosis,
    'work_performed', mj.work_performed,
    'labor_cost', mj.labor_cost,
    'total_cost', mj.total_cost,
    'invoice_id', mj.invoice_id
  ) as details
FROM mechanic_jobs mj, tenant_filter tf
WHERE mj.tenant_id = tf.tenant_id 
  AND mj.created_at >= tf.cutoff_time

UNION ALL

-- Sales Invoices
SELECT 
  'sales_invoices' as table_name, 
  si.id, 
  si.created_at, 
  'Invoice #' || si.invoice_number as description,
  jsonb_build_object(
    'customer_id', si.customer_id,
    'customer_name', si.customer_name,
    'date', si.date,
    'due_date', si.due_date,
    'subtotal', si.subtotal,
    'net_amount', si.net_amount,
    'iva_amount', si.iva_amount,
    'total', si.total,
    'paid_amount', si.paid_amount,
    'balance', si.balance,
    'status', si.status,
    'tax_treatment', si.tax_treatment,
    'items', si.items
  ) as details
FROM sales_invoices si, tenant_filter tf
WHERE si.tenant_id = tf.tenant_id 
  AND si.created_at >= tf.cutoff_time

UNION ALL

-- Products (if any were created)
SELECT 
  'products' as table_name, 
  p.id, 
  p.created_at, 
  p.name as description,
  jsonb_build_object(
    'sku', p.sku,
    'price', p.price,
    'cost', p.cost,
    'stock_quantity', p.stock_quantity,
    'category', p.category,
    'is_active', p.is_active
  ) as details
FROM products p, tenant_filter tf
WHERE p.tenant_id = tf.tenant_id 
  AND p.created_at >= tf.cutoff_time

UNION ALL

-- Journal Entries (accounting)
SELECT 
  'journal_entries' as table_name, 
  je.id, 
  je.created_at,
  'Entry #' || je.entry_number as description,
  jsonb_build_object(
    'entry_date', je.entry_date,
    'reference', je.source_reference,
    'description', je.description,
    'total_debit', je.total_debit,
    'total_credit', je.total_credit,
    'status', je.status
  ) as details
FROM journal_entries je, tenant_filter tf
WHERE je.tenant_id = tf.tenant_id 
  AND je.created_at >= tf.cutoff_time

ORDER BY created_at DESC;
