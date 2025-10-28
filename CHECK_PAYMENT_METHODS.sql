-- Check if payment methods were actually created
SELECT 
  pm.id,
  pm.code,
  pm.name,
  pm.tenant_id,
  pm.is_active,
  a.code as account_code,
  a.name as account_name
FROM payment_methods pm
LEFT JOIN accounts a ON pm.account_id = a.id
WHERE pm.tenant_id = (SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid() LIMIT 1)
ORDER BY pm.sort_order;
