-- DEBUG: Check each table individually for tenant 46e169a4-ba62-4f86-92cd-778ece1b0afa
-- Run each query separately to see what exists
-- NOTE: Times are in UTC. Chile is UTC-3, Seattle is UTC-8 (5 hour difference)

-- Current time in different timezones
SELECT 
  now() as utc_time,
  now() AT TIME ZONE 'America/Santiago' as chile_time,
  now() AT TIME ZONE 'America/Los_Angeles' as seattle_time,
  (now() - interval '8 hours') as cutoff_utc;

-- Customers
SELECT 'customers' as table, COUNT(*) as total, 
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM customers WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Products
SELECT 'products' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM products WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Sales Invoices
SELECT 'sales_invoices' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM sales_invoices WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Mechanic Jobs
SELECT 'mechanic_jobs' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM mechanic_jobs WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Bikes
SELECT 'bikes' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM bikes WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Bike Brands
SELECT 'bike_brands' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM bike_brands WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;

-- Bike Models
SELECT 'bike_models' as table, COUNT(*) as total,
       COUNT(*) FILTER (WHERE created_at >= now() - interval '8 hours') as last_8h
FROM bike_models WHERE tenant_id = '46e169a4-ba62-4f86-92cd-778ece1b0afa'::uuid;
