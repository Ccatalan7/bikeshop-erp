-- ============================================================================
-- FIX WEBSITE_SETTINGS UNIQUE CONSTRAINT - CRITICAL MULTI-TENANT BUG
-- ============================================================================
-- Problem: Global unique constraint on "key" column (not scoped to tenant_id)
-- This prevents multiple tenants from having the same setting keys!
-- Error: "duplicate key value violates unique constraint website_settings_key_key"
-- ============================================================================

-- Drop the WRONG global unique constraint
alter table website_settings drop constraint if exists website_settings_key_key;

-- Verify the correct per-tenant unique constraint exists
do $$ 
begin
  -- Check if the correct constraint exists
  if not exists (
    select 1 
    from pg_constraint 
    where conname like '%website_settings%tenant_id%key%'
      or conname like '%website_settings%key%tenant_id%'
  ) then
    -- Add the correct per-tenant unique constraint if missing
    alter table website_settings add constraint website_settings_tenant_key_unique unique(tenant_id, key);
  end if;
end $$;

-- Verify constraints
select 
  conname as constraint_name,
  contype as constraint_type,
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'website_settings'::regclass
order by conname;
