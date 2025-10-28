-- Check if ccatalan.us@gmail.com has a user_profile with tenant_id
select 
  au.id as auth_user_id,
  au.email,
  up.user_id,
  up.tenant_id,
  up.role,
  up.is_active,
  t.shop_name as tenant_name,
  t.subdomain
from auth.users au
left join public.user_profiles up on up.user_id = au.id
left join public.tenants t on t.id = up.tenant_id
where au.email = 'ccatalan.us@gmail.com';

-- If tenant_id is NULL, we need to assign one
-- First, check if there are any tenants
select id, shop_name, subdomain, owner_email, created_at 
from public.tenants 
order by created_at 
limit 5;
