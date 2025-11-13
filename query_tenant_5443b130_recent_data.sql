-- Find all data created by tenant 5443b130-cc28-45af-a420-cd500b288890 in the last 8 hours
-- Run this in Supabase SQL Editor
-- NOTE: Times are in UTC. Adjust interval for timezone differences (Chile is UTC-3, Seattle is UTC-8)
-- Change '8 hours' to a larger window if needed: '24 hours' or '7 days'

WITH tenant_filter AS (
  SELECT '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
         now() - interval '8 hours' as cutoff_time  -- Increased to account for timezone difference
)

-- DEBUG: Show current time and cutoff
-- SELECT now() as current_time, (now() - interval '8 hours') as cutoff_time;

-- Customers
SELECT 'customers' as table_name, c.id, c.created_at, c.name as description
FROM customers c, tenant_filter tf
WHERE c.tenant_id = tf.tenant_id 
  AND c.created_at >= tf.cutoff_time

UNION ALL

-- Products
SELECT 'products' as table_name, p.id, p.created_at, p.name as description
FROM products p, tenant_filter tf
WHERE p.tenant_id = tf.tenant_id 
  AND p.created_at >= tf.cutoff_time

UNION ALL

-- Sales Invoices
SELECT 'sales_invoices' as table_name, si.id, si.created_at, 
       'Invoice #' || si.invoice_number as description
FROM sales_invoices si, tenant_filter tf
WHERE si.tenant_id = tf.tenant_id 
  AND si.created_at >= tf.cutoff_time

UNION ALL

-- Sales Payments
SELECT 'sales_payments' as table_name, sp.id, sp.created_at,
       'Payment $' || sp.amount::text as description
FROM sales_payments sp, tenant_filter tf
WHERE sp.tenant_id = tf.tenant_id 
  AND sp.created_at >= tf.cutoff_time

UNION ALL

-- Purchase Invoices
SELECT 'purchase_invoices' as table_name, pi.id, pi.created_at,
       'Purchase #' || pi.invoice_number as description
FROM purchase_invoices pi, tenant_filter tf
WHERE pi.tenant_id = tf.tenant_id 
  AND pi.created_at >= tf.cutoff_time

UNION ALL

-- Purchase Payments
SELECT 'purchase_payments' as table_name, pp.id, pp.created_at,
       'Payment $' || pp.amount::text as description
FROM purchase_payments pp, tenant_filter tf
WHERE pp.tenant_id = tf.tenant_id 
  AND pp.created_at >= tf.cutoff_time

UNION ALL

-- Journal Entries
SELECT 'journal_entries' as table_name, je.id, je.created_at,
       'Entry #' || je.entry_number as description
FROM journal_entries je, tenant_filter tf
WHERE je.tenant_id = tf.tenant_id 
  AND je.created_at >= tf.cutoff_time

UNION ALL

-- Orders (no order_number column, uses id)
SELECT 'orders' as table_name, o.id, o.created_at,
       'Order from ' || o.source || ' - $' || o.total::text as description
FROM orders o, tenant_filter tf
WHERE o.tenant_id = tf.tenant_id 
  AND o.created_at >= tf.cutoff_time

UNION ALL

-- Mechanic Jobs
SELECT 'mechanic_jobs' as table_name, mj.id, mj.created_at,
       'Job #' || mj.job_number as description
FROM mechanic_jobs mj, tenant_filter tf
WHERE mj.tenant_id = tf.tenant_id 
  AND mj.created_at >= tf.cutoff_time

UNION ALL

-- Employees
SELECT 'employees' as table_name, e.id, e.created_at,
       e.first_name || ' ' || e.last_name as description
FROM employees e, tenant_filter tf
WHERE e.tenant_id = tf.tenant_id 
  AND e.created_at >= tf.cutoff_time

UNION ALL

-- Stock Adjustments
SELECT 'stock_adjustments' as table_name, sa.id, sa.created_at,
       sa.adjustment_type || ' - Qty: ' || sa.quantity_change::text as description
FROM stock_adjustments sa, tenant_filter tf
WHERE sa.tenant_id = tf.tenant_id 
  AND sa.created_at >= tf.cutoff_time

UNION ALL

-- User Activity Log
SELECT 'user_activity_log' as table_name, ual.id, ual.created_at,
       ual.action as description
FROM user_activity_log ual, tenant_filter tf
WHERE ual.tenant_id = tf.tenant_id 
  AND ual.created_at >= tf.cutoff_time

UNION ALL

-- Bikes (customer bikes)
SELECT 'bikes' as table_name, b.id, b.created_at,
       COALESCE(b.brand, bb.name, 'Unknown') || ' ' || 
       COALESCE(b.model, bm.name, 'Unknown') || 
       COALESCE(' (' || b.serial_number || ')', '') as description
FROM bikes b
LEFT JOIN bike_brands bb ON b.brand_id = bb.id
LEFT JOIN bike_models bm ON b.model_id = bm.id
CROSS JOIN tenant_filter tf
WHERE b.tenant_id = tf.tenant_id 
  AND b.created_at >= tf.cutoff_time

UNION ALL

-- Bike Brands
SELECT 'bike_brands' as table_name, bb.id, bb.created_at,
       bb.name as description
FROM bike_brands bb, tenant_filter tf
WHERE bb.tenant_id = tf.tenant_id 
  AND bb.created_at >= tf.cutoff_time

UNION ALL

-- Bike Models
SELECT 'bike_models' as table_name, bm.id, bm.created_at,
       bm.name || ' (Brand ID: ' || bm.brand_id::text || ')' as description
FROM bike_models bm, tenant_filter tf
WHERE bm.tenant_id = tf.tenant_id 
  AND bm.created_at >= tf.cutoff_time

ORDER BY created_at DESC;
