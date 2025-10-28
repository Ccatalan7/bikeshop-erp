-- Add the correct per-tenant unique constraint
alter table website_settings 
  add constraint website_settings_tenant_key_unique 
  unique(tenant_id, key);

-- Verify it was added
select 
  conname as constraint_name,
  contype as constraint_type,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'website_settings'::regclass
order by conname;
