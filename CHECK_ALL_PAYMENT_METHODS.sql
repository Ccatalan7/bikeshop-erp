-- Check ALL payment methods (across all tenants) to see what exists
SELECT 
  id,
  tenant_id,
  code,
  name,
  is_active
FROM payment_methods
ORDER BY tenant_id, code;
