-- Check both user accounts and their metadata

-- Check auth.users table
select 
  email,
  raw_user_meta_data->>'role' as role,
  raw_user_meta_data->>'name' as name,
  created_at
from auth.users
where email in ('admin@vinabike.cl', 'ccatalansandoval7@gmail.com')
order by created_at;

-- Check if they have employee records
select 
  e.name,
  e.role,
  e.email,
  e.tenant_id,
  t.shop_name as tenant_name,
  u.email as auth_email
from employees e
left join tenants t on t.id = e.tenant_id
left join auth.users u on u.id = e.auth_user_id
where e.email in ('admin@vinabike.cl', 'ccatalansandoval7@gmail.com')
   or u.email in ('admin@vinabike.cl', 'ccatalansandoval7@gmail.com')
order by e.created_at;

-- Check tenants
select 
  id,
  shop_name,
  owner_email,
  plan,
  is_active,
  created_at
from tenants
where owner_email in ('admin@vinabike.cl', 'ccatalansandoval7@gmail.com')
order by created_at;
