-- Test if user_tenant_id() function works
SELECT 
  auth.uid() as my_user_id,
  public.user_tenant_id() as my_tenant_id,
  (SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid() LIMIT 1) as tenant_from_profile;
  
-- Also check payment methods with explicit tenant filter
SELECT count(*) as payment_method_count
FROM payment_methods
WHERE tenant_id = (SELECT tenant_id FROM user_profiles WHERE user_id = auth.uid() LIMIT 1);
