-- ============================================================
-- MULTI-TENANT WEBSITE CONFIGURATION
-- ============================================================
-- Add website deployment columns to company_settings table
-- for multi-tenant website deployment with Firebase Hosting
-- 
-- Date: 2025-10-25
-- Feature: Multi-Tenant Website Deployment
-- Reference: MULTI_TENANT_WEBSITE_SETUP_GUIDE.md
-- ============================================================

-- Add website configuration columns
do $$ begin
  alter table company_settings add column if not exists website_enabled boolean default false;
  alter table company_settings add column if not exists website_subdomain text;
  alter table company_settings add column if not exists website_url text;
  alter table company_settings add column if not exists firebase_site_name text;
  alter table company_settings add column if not exists website_deployed_at timestamptz;
  alter table company_settings add column if not exists website_status text default 'not_configured';
  
  raise notice '✅ Website configuration columns added to company_settings';
exception
  when undefined_table then 
    raise exception '❌ Table company_settings does not exist. Run core_schema.sql first.';
  when duplicate_column then 
    raise notice '⚠️  Website columns already exist in company_settings - skipping';
end $$;

-- Add column comments for documentation
do $$ begin
  comment on column company_settings.website_enabled is 'Whether tenant has activated their public website';
  comment on column company_settings.website_subdomain is 'Unique subdomain for tenant website (e.g., bikeshop-santiago)';
  comment on column company_settings.website_url is 'Full URL of deployed website (e.g., https://bikeshop-santiago.web.app)';
  comment on column company_settings.firebase_site_name is 'Firebase Hosting site name';
  comment on column company_settings.website_deployed_at is 'When website was last deployed';
  comment on column company_settings.website_status is 'Current deployment status: not_configured, pending, deployed, failed';
  
  raise notice '✅ Column comments added';
exception
  when undefined_column then 
    raise notice '⚠️  Some columns do not exist - comments not added';
end $$;

-- Add unique constraint on website_subdomain (each subdomain can only be used once)
do $$ begin
  alter table company_settings add constraint unique_website_subdomain unique(website_subdomain);
  raise notice '✅ Unique constraint added to website_subdomain';
exception
  when duplicate_table then 
    raise notice '⚠️  Unique constraint already exists on website_subdomain - skipping';
  when undefined_column then 
    raise exception '❌ Column website_subdomain does not exist. Run the column addition first.';
end $$;

-- Create indexes for performance
do $$ begin
  create index if not exists idx_company_settings_website_subdomain 
    on company_settings(website_subdomain) 
    where website_subdomain is not null;
    
  create index if not exists idx_company_settings_website_status 
    on company_settings(website_status);
  
  raise notice '✅ Indexes created for website_subdomain and website_status';
exception
  when undefined_table then 
    raise exception '❌ Table company_settings does not exist';
  when undefined_column then 
    raise notice '⚠️  Some columns do not exist - indexes not created';
end $$;

-- Verify the changes
do $$ 
declare
  col_count integer;
begin
  select count(*) into col_count
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'company_settings'
    and column_name in (
      'website_enabled',
      'website_subdomain',
      'website_url',
      'firebase_site_name',
      'website_deployed_at',
      'website_status'
    );
  
  if col_count = 6 then
    raise notice '✅ VERIFICATION PASSED: All 6 website configuration columns exist';
  else
    raise warning '⚠️  VERIFICATION FAILED: Expected 6 columns, found %', col_count;
  end if;
end $$;

-- Display current company_settings schema
select 
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'company_settings'
order by ordinal_position;
