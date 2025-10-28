-- Check if accounts were created
SELECT 
  id,
  code,
  name,
  type,
  category,
  tenant_id
FROM accounts
WHERE tenant_id = (SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid() LIMIT 1)
  AND code IN ('1101', '1110')
ORDER BY code;
