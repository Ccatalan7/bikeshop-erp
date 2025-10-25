-- ============================================================================
-- FIX ALL 26 TABLES MISSING tenant_id
-- ============================================================================
-- This script adds tenant_id to ALL tables that are missing it
-- Assigns existing data to Vinabike tenant (97ef40bf-f58c-4f76-a629-c013fb3928cf)
-- Enables RLS with proper policies
-- ============================================================================

DO $$ 
DECLARE
  vinabike_tenant_id uuid := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
BEGIN
  RAISE NOTICE 'Starting multi-tenant migration for 26 tables...';

  -- ============================================================================
  -- 1. analytics_snapshots
  -- ============================================================================
  RAISE NOTICE 'Fixing analytics_snapshots...';
  
  ALTER TABLE analytics_snapshots 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE analytics_snapshots SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE analytics_snapshots 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_analytics_snapshots_tenant ON analytics_snapshots(tenant_id);
  
  ALTER TABLE analytics_snapshots DROP CONSTRAINT IF EXISTS analytics_snapshots_tenant_unique;
  
  ALTER TABLE ONLY analytics_snapshots 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS analytics_snapshots_tenant_isolation ON analytics_snapshots;
  CREATE POLICY analytics_snapshots_tenant_isolation ON analytics_snapshots
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 2. attendance_records
  -- ============================================================================
  RAISE NOTICE 'Fixing attendance_records...';
  
  ALTER TABLE attendance_records 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE attendance_records SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE attendance_records 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_attendance_records_tenant ON attendance_records(tenant_id);
  
  ALTER TABLE ONLY attendance_records 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS attendance_records_tenant_isolation ON attendance_records;
  CREATE POLICY attendance_records_tenant_isolation ON attendance_records
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 3. campaign_metrics
  -- ============================================================================
  RAISE NOTICE 'Fixing campaign_metrics...';
  
  ALTER TABLE campaign_metrics 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE campaign_metrics SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE campaign_metrics 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_campaign_metrics_tenant ON campaign_metrics(tenant_id);
  
  ALTER TABLE ONLY campaign_metrics 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS campaign_metrics_tenant_isolation ON campaign_metrics;
  CREATE POLICY campaign_metrics_tenant_isolation ON campaign_metrics
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 4. campaigns
  -- ============================================================================
  RAISE NOTICE 'Fixing campaigns...';
  
  ALTER TABLE campaigns 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE campaigns SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE campaigns 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_campaigns_tenant ON campaigns(tenant_id);
  
  ALTER TABLE ONLY campaigns 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS campaigns_tenant_isolation ON campaigns;
  CREATE POLICY campaigns_tenant_isolation ON campaigns
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 5. companies
  -- ============================================================================
  RAISE NOTICE 'Fixing companies...';
  
  ALTER TABLE companies 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE companies SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE companies 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_companies_tenant ON companies(tenant_id);
  
  ALTER TABLE ONLY companies 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS companies_tenant_isolation ON companies;
  CREATE POLICY companies_tenant_isolation ON companies
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 6. company_settings
  -- ============================================================================
  RAISE NOTICE 'Fixing company_settings...';
  
  ALTER TABLE company_settings 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE company_settings SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE company_settings 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_company_settings_tenant ON company_settings(tenant_id);
  
  -- Unique constraint per tenant
  ALTER TABLE company_settings DROP CONSTRAINT IF EXISTS company_settings_tenant_key_unique;
  ALTER TABLE company_settings ADD CONSTRAINT company_settings_tenant_key_unique UNIQUE (tenant_id, key);
  
  ALTER TABLE ONLY company_settings 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS company_settings_tenant_isolation ON company_settings;
  CREATE POLICY company_settings_tenant_isolation ON company_settings
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 7. content_items
  -- ============================================================================
  RAISE NOTICE 'Fixing content_items...';
  
  ALTER TABLE content_items 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE content_items SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE content_items 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_content_items_tenant ON content_items(tenant_id);
  
  ALTER TABLE ONLY content_items 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS content_items_tenant_isolation ON content_items;
  CREATE POLICY content_items_tenant_isolation ON content_items
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 8. content_media
  -- ============================================================================
  RAISE NOTICE 'Fixing content_media...';
  
  ALTER TABLE content_media 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE content_media SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE content_media 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_content_media_tenant ON content_media(tenant_id);
  
  ALTER TABLE ONLY content_media 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS content_media_tenant_isolation ON content_media;
  CREATE POLICY content_media_tenant_isolation ON content_media
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 9. employee_contracts
  -- ============================================================================
  RAISE NOTICE 'Fixing employee_contracts...';
  
  ALTER TABLE employee_contracts 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE employee_contracts SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE employee_contracts 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_employee_contracts_tenant ON employee_contracts(tenant_id);
  
  ALTER TABLE ONLY employee_contracts 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS employee_contracts_tenant_isolation ON employee_contracts;
  CREATE POLICY employee_contracts_tenant_isolation ON employee_contracts
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 10. featured_products
  -- ============================================================================
  RAISE NOTICE 'Fixing featured_products...';
  
  ALTER TABLE featured_products 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE featured_products SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE featured_products 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_featured_products_tenant ON featured_products(tenant_id);
  
  ALTER TABLE ONLY featured_products 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS featured_products_tenant_isolation ON featured_products;
  CREATE POLICY featured_products_tenant_isolation ON featured_products
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 11. inventory_adjustments
  -- ============================================================================
  RAISE NOTICE 'Fixing inventory_adjustments...';
  
  ALTER TABLE inventory_adjustments 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE inventory_adjustments SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE inventory_adjustments 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_tenant ON inventory_adjustments(tenant_id);
  
  ALTER TABLE ONLY inventory_adjustments 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS inventory_adjustments_tenant_isolation ON inventory_adjustments;
  CREATE POLICY inventory_adjustments_tenant_isolation ON inventory_adjustments
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 12. leave_requests
  -- ============================================================================
  RAISE NOTICE 'Fixing leave_requests...';
  
  ALTER TABLE leave_requests 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE leave_requests SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE leave_requests 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_leave_requests_tenant ON leave_requests(tenant_id);
  
  ALTER TABLE ONLY leave_requests 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS leave_requests_tenant_isolation ON leave_requests;
  CREATE POLICY leave_requests_tenant_isolation ON leave_requests
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 13. online_order_items
  -- ============================================================================
  RAISE NOTICE 'Fixing online_order_items...';
  
  ALTER TABLE online_order_items 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE online_order_items SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE online_order_items 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_online_order_items_tenant ON online_order_items(tenant_id);
  
  ALTER TABLE ONLY online_order_items 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS online_order_items_tenant_isolation ON online_order_items;
  CREATE POLICY online_order_items_tenant_isolation ON online_order_items
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 14. payroll_entries
  -- ============================================================================
  RAISE NOTICE 'Fixing payroll_entries...';
  
  ALTER TABLE payroll_entries 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE payroll_entries SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE payroll_entries 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_payroll_entries_tenant ON payroll_entries(tenant_id);
  
  ALTER TABLE ONLY payroll_entries 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS payroll_entries_tenant_isolation ON payroll_entries;
  CREATE POLICY payroll_entries_tenant_isolation ON payroll_entries
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 15. payroll_runs
  -- ============================================================================
  RAISE NOTICE 'Fixing payroll_runs...';
  
  ALTER TABLE payroll_runs 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE payroll_runs SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE payroll_runs 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_payroll_runs_tenant ON payroll_runs(tenant_id);
  
  ALTER TABLE ONLY payroll_runs 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS payroll_runs_tenant_isolation ON payroll_runs;
  CREATE POLICY payroll_runs_tenant_isolation ON payroll_runs
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 16. purchase_order_items
  -- ============================================================================
  RAISE NOTICE 'Fixing purchase_order_items...';
  
  ALTER TABLE purchase_order_items 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE purchase_order_items SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE purchase_order_items 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_purchase_order_items_tenant ON purchase_order_items(tenant_id);
  
  ALTER TABLE ONLY purchase_order_items 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS purchase_order_items_tenant_isolation ON purchase_order_items;
  CREATE POLICY purchase_order_items_tenant_isolation ON purchase_order_items
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 17. purchase_orders
  -- ============================================================================
  RAISE NOTICE 'Fixing purchase_orders...';
  
  ALTER TABLE purchase_orders 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE purchase_orders SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE purchase_orders 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant ON purchase_orders(tenant_id);
  
  ALTER TABLE ONLY purchase_orders 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS purchase_orders_tenant_isolation ON purchase_orders;
  CREATE POLICY purchase_orders_tenant_isolation ON purchase_orders
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 18. sales_order_items
  -- ============================================================================
  RAISE NOTICE 'Fixing sales_order_items...';
  
  ALTER TABLE sales_order_items 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE sales_order_items SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE sales_order_items 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_sales_order_items_tenant ON sales_order_items(tenant_id);
  
  ALTER TABLE ONLY sales_order_items 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS sales_order_items_tenant_isolation ON sales_order_items;
  CREATE POLICY sales_order_items_tenant_isolation ON sales_order_items
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 19. sales_orders
  -- ============================================================================
  RAISE NOTICE 'Fixing sales_orders...';
  
  ALTER TABLE sales_orders 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE sales_orders SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE sales_orders 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_sales_orders_tenant ON sales_orders(tenant_id);
  
  ALTER TABLE ONLY sales_orders 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS sales_orders_tenant_isolation ON sales_orders;
  CREATE POLICY sales_orders_tenant_isolation ON sales_orders
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 20. service_packages
  -- ============================================================================
  RAISE NOTICE 'Fixing service_packages...';
  
  ALTER TABLE service_packages 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE service_packages SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE service_packages 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_service_packages_tenant ON service_packages(tenant_id);
  
  ALTER TABLE ONLY service_packages 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS service_packages_tenant_isolation ON service_packages;
  CREATE POLICY service_packages_tenant_isolation ON service_packages
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 21. shifts
  -- ============================================================================
  RAISE NOTICE 'Fixing shifts...';
  
  ALTER TABLE shifts 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE shifts SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE shifts 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_shifts_tenant ON shifts(tenant_id);
  
  ALTER TABLE ONLY shifts 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS shifts_tenant_isolation ON shifts;
  CREATE POLICY shifts_tenant_isolation ON shifts
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 22. users_profiles
  -- ============================================================================
  RAISE NOTICE 'Fixing users_profiles...';
  
  ALTER TABLE users_profiles 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE users_profiles SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE users_profiles 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_users_profiles_tenant ON users_profiles(tenant_id);
  
  ALTER TABLE ONLY users_profiles 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS users_profiles_tenant_isolation ON users_profiles;
  CREATE POLICY users_profiles_tenant_isolation ON users_profiles
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 23. vehicles
  -- ============================================================================
  RAISE NOTICE 'Fixing vehicles...';
  
  ALTER TABLE vehicles 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE vehicles SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE vehicles 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_vehicles_tenant ON vehicles(tenant_id);
  
  ALTER TABLE ONLY vehicles 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS vehicles_tenant_isolation ON vehicles;
  CREATE POLICY vehicles_tenant_isolation ON vehicles
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 24. website_banners
  -- ============================================================================
  RAISE NOTICE 'Fixing website_banners...';
  
  ALTER TABLE website_banners 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE website_banners SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE website_banners 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_website_banners_tenant ON website_banners(tenant_id);
  
  ALTER TABLE ONLY website_banners 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS website_banners_tenant_isolation ON website_banners;
  CREATE POLICY website_banners_tenant_isolation ON website_banners
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 25. work_order_items
  -- ============================================================================
  RAISE NOTICE 'Fixing work_order_items...';
  
  ALTER TABLE work_order_items 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE work_order_items SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE work_order_items 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_work_order_items_tenant ON work_order_items(tenant_id);
  
  ALTER TABLE ONLY work_order_items 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS work_order_items_tenant_isolation ON work_order_items;
  CREATE POLICY work_order_items_tenant_isolation ON work_order_items
    FOR ALL USING (tenant_id = public.user_tenant_id());

  -- ============================================================================
  -- 26. work_schedules
  -- ============================================================================
  RAISE NOTICE 'Fixing work_schedules...';
  
  ALTER TABLE work_schedules 
    ADD COLUMN IF NOT EXISTS tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE;
  
  UPDATE work_schedules SET tenant_id = vinabike_tenant_id WHERE tenant_id IS NULL;
  
  ALTER TABLE work_schedules 
    ALTER COLUMN tenant_id SET NOT NULL;
  
  CREATE INDEX IF NOT EXISTS idx_work_schedules_tenant ON work_schedules(tenant_id);
  
  ALTER TABLE ONLY work_schedules 
    ENABLE ROW LEVEL SECURITY;
  
  DROP POLICY IF EXISTS work_schedules_tenant_isolation ON work_schedules;
  CREATE POLICY work_schedules_tenant_isolation ON work_schedules
    FOR ALL USING (tenant_id = public.user_tenant_id());

  RAISE NOTICE '✅ ALL 26 TABLES FIXED - Multi-tenant isolation complete!';
  
END $$;

-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================
-- Run this after to confirm all tables now have tenant_id

SELECT 
  table_name,
  '✅ Fixed' as status
FROM information_schema.columns
WHERE column_name = 'tenant_id' 
  AND table_schema = 'public'
  AND table_name IN (
    'analytics_snapshots', 'attendance_records', 'campaign_metrics', 'campaigns',
    'companies', 'company_settings', 'content_items', 'content_media',
    'employee_contracts', 'featured_products', 'inventory_adjustments', 'leave_requests',
    'online_order_items', 'payroll_entries', 'payroll_runs', 'purchase_order_items',
    'purchase_orders', 'sales_order_items', 'sales_orders', 'service_packages',
    'shifts', 'users_profiles', 'vehicles', 'website_banners', 'work_order_items',
    'work_schedules'
  )
ORDER BY table_name;
