-- FULL DETAILED LIST - ALL JOBS FROM NOV 19-24
-- Removed tenant filter to see if RLS is the issue

SELECT 
  mj.job_number,
  to_char(mj.created_at, 'DD/MM/YY HH24:MI') as created_at,
  to_char(mj.arrival_date, 'DD/MM/YY HH24:MI') as arrival_date,
  to_char(mj.updated_at, 'DD/MM/YY HH24:MI') as updated_at,
  mj.status,
  mj.tenant_id,
  c.name as customer_name,
  c.email as customer_email,
  c.phone as customer_phone,
  b.brand as bike_brand,
  b.model as bike_model,
  mj.labor_cost,
  mj.total_cost
FROM mechanic_jobs mj
LEFT JOIN customers c ON mj.customer_id = c.id
LEFT JOIN bikes b ON mj.bike_id = b.id
WHERE (mj.created_at::date BETWEEN '2025-11-19' AND '2025-11-24'
   OR mj.arrival_date::date BETWEEN '2025-11-19' AND '2025-11-24')
ORDER BY mj.created_at, mj.job_number;


