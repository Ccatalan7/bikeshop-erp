-- HISTORICAL MANUAL HELPER — NOT A DEPLOYMENT PATH.
-- Do not run this from the SQL Editor or as a follow-up to core_schema.sql.
-- If the behavior is still required, inspect production first and convert it
-- into one reviewed standalone migration with executable verification.

do $$
declare
  tenant_rec record;
  existing_count int;
begin
  -- Loop through all tenants
  for tenant_rec in select id, shop_name from tenants
  loop
    -- Check if this tenant already has job roles
    select count(*) into existing_count
    from job_roles
    where tenant_id = tenant_rec.id;
    
    if existing_count = 0 then
      -- Seed job roles for this tenant
      raise notice 'Seeding job roles for tenant: % (ID: %)', tenant_rec.shop_name, tenant_rec.id;
      perform public.seed_job_roles_for_tenant(tenant_rec.id);
    else
      raise notice 'Tenant % already has % job roles, skipping', tenant_rec.shop_name, existing_count;
    end if;
  end loop;
  
  raise notice 'Job roles seeding complete!';
end $$;

-- Verify the results
select 
  t.shop_name as tenant,
  count(jr.id) as role_count,
  array_agg(jr.display_name order by jr.sort_order) as roles
from tenants t
left join job_roles jr on jr.tenant_id = t.id
group by t.id, t.shop_name
order by t.shop_name;
