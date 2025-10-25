-- ============================================================================
-- TENANT RLS POLICIES FOR ALL 22 MIGRATED TABLES (INCLUDING WEBSITE)
-- ============================================================================
-- Deploy this AFTER running core_schema.sql and data migration
-- This creates Row Level Security policies for complete tenant isolation
-- ============================================================================

-- ============================================================================
-- 1. company_settings
-- ============================================================================
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "company_settings_tenant_select" ON company_settings;
CREATE POLICY "company_settings_tenant_select" 
  ON company_settings FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_insert" ON company_settings;
CREATE POLICY "company_settings_tenant_insert" 
  ON company_settings FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_update" ON company_settings;
CREATE POLICY "company_settings_tenant_update" 
  ON company_settings FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "company_settings_tenant_delete" ON company_settings;
CREATE POLICY "company_settings_tenant_delete" 
  ON company_settings FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 2. product_brands
-- ============================================================================
ALTER TABLE product_brands ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_brands_tenant_select" ON product_brands;
CREATE POLICY "product_brands_tenant_select" 
  ON product_brands FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "product_brands_tenant_insert" ON product_brands;
CREATE POLICY "product_brands_tenant_insert" 
  ON product_brands FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "product_brands_tenant_update" ON product_brands;
CREATE POLICY "product_brands_tenant_update" 
  ON product_brands FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "product_brands_tenant_delete" ON product_brands;
CREATE POLICY "product_brands_tenant_delete" 
  ON product_brands FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 3. payment_methods
-- ============================================================================
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_methods_tenant_select" ON payment_methods;
CREATE POLICY "payment_methods_tenant_select" 
  ON payment_methods FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "payment_methods_tenant_insert" ON payment_methods;
CREATE POLICY "payment_methods_tenant_insert" 
  ON payment_methods FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "payment_methods_tenant_update" ON payment_methods;
CREATE POLICY "payment_methods_tenant_update" 
  ON payment_methods FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "payment_methods_tenant_delete" ON payment_methods;
CREATE POLICY "payment_methods_tenant_delete" 
  ON payment_methods FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 4. expense_categories
-- ============================================================================
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "expense_categories_tenant_select" ON expense_categories;
CREATE POLICY "expense_categories_tenant_select" 
  ON expense_categories FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_categories_tenant_insert" ON expense_categories;
CREATE POLICY "expense_categories_tenant_insert" 
  ON expense_categories FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_categories_tenant_update" ON expense_categories;
CREATE POLICY "expense_categories_tenant_update" 
  ON expense_categories FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_categories_tenant_delete" ON expense_categories;
CREATE POLICY "expense_categories_tenant_delete" 
  ON expense_categories FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 5. departments
-- ============================================================================
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "departments_tenant_select" ON departments;
CREATE POLICY "departments_tenant_select" 
  ON departments FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "departments_tenant_insert" ON departments;
CREATE POLICY "departments_tenant_insert" 
  ON departments FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "departments_tenant_update" ON departments;
CREATE POLICY "departments_tenant_update" 
  ON departments FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "departments_tenant_delete" ON departments;
CREATE POLICY "departments_tenant_delete" 
  ON departments FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 6. service_packages
-- ============================================================================
ALTER TABLE service_packages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_packages_tenant_select" ON service_packages;
CREATE POLICY "service_packages_tenant_select" 
  ON service_packages FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "service_packages_tenant_insert" ON service_packages;
CREATE POLICY "service_packages_tenant_insert" 
  ON service_packages FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "service_packages_tenant_update" ON service_packages;
CREATE POLICY "service_packages_tenant_update" 
  ON service_packages FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "service_packages_tenant_delete" ON service_packages;
CREATE POLICY "service_packages_tenant_delete" 
  ON service_packages FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 7. work_schedules
-- ============================================================================
ALTER TABLE work_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "work_schedules_tenant_select" ON work_schedules;
CREATE POLICY "work_schedules_tenant_select" 
  ON work_schedules FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "work_schedules_tenant_insert" ON work_schedules;
CREATE POLICY "work_schedules_tenant_insert" 
  ON work_schedules FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "work_schedules_tenant_update" ON work_schedules;
CREATE POLICY "work_schedules_tenant_update" 
  ON work_schedules FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "work_schedules_tenant_delete" ON work_schedules;
CREATE POLICY "work_schedules_tenant_delete" 
  ON work_schedules FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 8. employee_contracts
-- ============================================================================
ALTER TABLE employee_contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "employee_contracts_tenant_select" ON employee_contracts;
CREATE POLICY "employee_contracts_tenant_select" 
  ON employee_contracts FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "employee_contracts_tenant_insert" ON employee_contracts;
CREATE POLICY "employee_contracts_tenant_insert" 
  ON employee_contracts FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "employee_contracts_tenant_update" ON employee_contracts;
CREATE POLICY "employee_contracts_tenant_update" 
  ON employee_contracts FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "employee_contracts_tenant_delete" ON employee_contracts;
CREATE POLICY "employee_contracts_tenant_delete" 
  ON employee_contracts FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 9. expense_attachments
-- ============================================================================
ALTER TABLE expense_attachments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "expense_attachments_tenant_select" ON expense_attachments;
CREATE POLICY "expense_attachments_tenant_select" 
  ON expense_attachments FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_attachments_tenant_insert" ON expense_attachments;
CREATE POLICY "expense_attachments_tenant_insert" 
  ON expense_attachments FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_attachments_tenant_update" ON expense_attachments;
CREATE POLICY "expense_attachments_tenant_update" 
  ON expense_attachments FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "expense_attachments_tenant_delete" ON expense_attachments;
CREATE POLICY "expense_attachments_tenant_delete" 
  ON expense_attachments FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 10. website_banners
-- ============================================================================
ALTER TABLE website_banners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "website_banners_tenant_select" ON website_banners;
CREATE POLICY "website_banners_tenant_select" 
  ON website_banners FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_banners_tenant_insert" ON website_banners;
CREATE POLICY "website_banners_tenant_insert" 
  ON website_banners FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_banners_tenant_update" ON website_banners;
CREATE POLICY "website_banners_tenant_update" 
  ON website_banners FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_banners_tenant_delete" ON website_banners;
CREATE POLICY "website_banners_tenant_delete" 
  ON website_banners FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 11. website_content
-- ============================================================================
ALTER TABLE website_content ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "website_content_tenant_select" ON website_content;
CREATE POLICY "website_content_tenant_select" 
  ON website_content FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_content_tenant_insert" ON website_content;
CREATE POLICY "website_content_tenant_insert" 
  ON website_content FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_content_tenant_update" ON website_content;
CREATE POLICY "website_content_tenant_update" 
  ON website_content FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_content_tenant_delete" ON website_content;
CREATE POLICY "website_content_tenant_delete" 
  ON website_content FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 12. online_order_items
-- ============================================================================
ALTER TABLE online_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "online_order_items_tenant_select" ON online_order_items;
CREATE POLICY "online_order_items_tenant_select" 
  ON online_order_items FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_order_items_tenant_insert" ON online_order_items;
CREATE POLICY "online_order_items_tenant_insert" 
  ON online_order_items FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_order_items_tenant_update" ON online_order_items;
CREATE POLICY "online_order_items_tenant_update" 
  ON online_order_items FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_order_items_tenant_delete" ON online_order_items;
CREATE POLICY "online_order_items_tenant_delete" 
  ON online_order_items FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 13. orders
-- ============================================================================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "orders_tenant_select" ON orders;
CREATE POLICY "orders_tenant_select" 
  ON orders FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "orders_tenant_insert" ON orders;
CREATE POLICY "orders_tenant_insert" 
  ON orders FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "orders_tenant_update" ON orders;
CREATE POLICY "orders_tenant_update" 
  ON orders FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "orders_tenant_delete" ON orders;
CREATE POLICY "orders_tenant_delete" 
  ON orders FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 14. order_items
-- ============================================================================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "order_items_tenant_select" ON order_items;
CREATE POLICY "order_items_tenant_select" 
  ON order_items FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "order_items_tenant_insert" ON order_items;
CREATE POLICY "order_items_tenant_insert" 
  ON order_items FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "order_items_tenant_update" ON order_items;
CREATE POLICY "order_items_tenant_update" 
  ON order_items FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "order_items_tenant_delete" ON order_items;
CREATE POLICY "order_items_tenant_delete" 
  ON order_items FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 15. mechanic_jobs
-- ============================================================================
ALTER TABLE mechanic_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mechanic_jobs_tenant_select" ON mechanic_jobs;
CREATE POLICY "mechanic_jobs_tenant_select" 
  ON mechanic_jobs FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "mechanic_jobs_tenant_insert" ON mechanic_jobs;
CREATE POLICY "mechanic_jobs_tenant_insert" 
  ON mechanic_jobs FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "mechanic_jobs_tenant_update" ON mechanic_jobs;
CREATE POLICY "mechanic_jobs_tenant_update" 
  ON mechanic_jobs FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "mechanic_jobs_tenant_delete" ON mechanic_jobs;
CREATE POLICY "mechanic_jobs_tenant_delete" 
  ON mechanic_jobs FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 16. mechanic_job_items (child table - RLS through parent join)
-- ============================================================================
ALTER TABLE mechanic_job_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mechanic_job_items_tenant_select" ON mechanic_job_items;
CREATE POLICY "mechanic_job_items_tenant_select" 
  ON mechanic_job_items FOR SELECT 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_items.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_items_tenant_insert" ON mechanic_job_items;
CREATE POLICY "mechanic_job_items_tenant_insert" 
  ON mechanic_job_items FOR INSERT 
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_items.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_items_tenant_update" ON mechanic_job_items;
CREATE POLICY "mechanic_job_items_tenant_update" 
  ON mechanic_job_items FOR UPDATE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_items.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_items.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_items_tenant_delete" ON mechanic_job_items;
CREATE POLICY "mechanic_job_items_tenant_delete" 
  ON mechanic_job_items FOR DELETE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_items.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

-- ============================================================================
-- 17. mechanic_job_labor (child table - RLS through parent join)
-- ============================================================================
ALTER TABLE mechanic_job_labor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mechanic_job_labor_tenant_select" ON mechanic_job_labor;
CREATE POLICY "mechanic_job_labor_tenant_select" 
  ON mechanic_job_labor FOR SELECT 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_labor.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_labor_tenant_insert" ON mechanic_job_labor;
CREATE POLICY "mechanic_job_labor_tenant_insert" 
  ON mechanic_job_labor FOR INSERT 
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_labor.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_labor_tenant_update" ON mechanic_job_labor;
CREATE POLICY "mechanic_job_labor_tenant_update" 
  ON mechanic_job_labor FOR UPDATE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_labor.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_labor.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_labor_tenant_delete" ON mechanic_job_labor;
CREATE POLICY "mechanic_job_labor_tenant_delete" 
  ON mechanic_job_labor FOR DELETE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_labor.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

-- ============================================================================
-- 18. mechanic_job_timeline (child table - RLS through parent join)
-- ============================================================================
ALTER TABLE mechanic_job_timeline ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "mechanic_job_timeline_tenant_select" ON mechanic_job_timeline;
CREATE POLICY "mechanic_job_timeline_tenant_select" 
  ON mechanic_job_timeline FOR SELECT 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_timeline.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_timeline_tenant_insert" ON mechanic_job_timeline;
CREATE POLICY "mechanic_job_timeline_tenant_insert" 
  ON mechanic_job_timeline FOR INSERT 
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_timeline.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_timeline_tenant_update" ON mechanic_job_timeline;
CREATE POLICY "mechanic_job_timeline_tenant_update" 
  ON mechanic_job_timeline FOR UPDATE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_timeline.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_timeline.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

DROP POLICY IF EXISTS "mechanic_job_timeline_tenant_delete" ON mechanic_job_timeline;
CREATE POLICY "mechanic_job_timeline_tenant_delete" 
  ON mechanic_job_timeline FOR DELETE 
  USING (EXISTS (
    SELECT 1 FROM mechanic_jobs 
    WHERE mechanic_jobs.id = mechanic_job_timeline.job_id 
    AND mechanic_jobs.tenant_id = public.user_tenant_id()
  ));

-- ============================================================================
-- 19. website_blocks (NEW - visual editor blocks)
-- ============================================================================
ALTER TABLE website_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "website_blocks_tenant_select" ON website_blocks;
CREATE POLICY "website_blocks_tenant_select" 
  ON website_blocks FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_blocks_tenant_insert" ON website_blocks;
CREATE POLICY "website_blocks_tenant_insert" 
  ON website_blocks FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_blocks_tenant_update" ON website_blocks;
CREATE POLICY "website_blocks_tenant_update" 
  ON website_blocks FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_blocks_tenant_delete" ON website_blocks;
CREATE POLICY "website_blocks_tenant_delete" 
  ON website_blocks FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 20. website_settings (NEW - store configuration)
-- ============================================================================
ALTER TABLE website_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "website_settings_tenant_select" ON website_settings;
CREATE POLICY "website_settings_tenant_select" 
  ON website_settings FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_settings_tenant_insert" ON website_settings;
CREATE POLICY "website_settings_tenant_insert" 
  ON website_settings FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_settings_tenant_update" ON website_settings;
CREATE POLICY "website_settings_tenant_update" 
  ON website_settings FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "website_settings_tenant_delete" ON website_settings;
CREATE POLICY "website_settings_tenant_delete" 
  ON website_settings FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 21. featured_products (NEW - homepage featured items)
-- ============================================================================
ALTER TABLE featured_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "featured_products_tenant_select" ON featured_products;
CREATE POLICY "featured_products_tenant_select" 
  ON featured_products FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "featured_products_tenant_insert" ON featured_products;
CREATE POLICY "featured_products_tenant_insert" 
  ON featured_products FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "featured_products_tenant_update" ON featured_products;
CREATE POLICY "featured_products_tenant_update" 
  ON featured_products FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "featured_products_tenant_delete" ON featured_products;
CREATE POLICY "featured_products_tenant_delete" 
  ON featured_products FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- 22. online_orders (NEW - customer website orders)
-- ============================================================================
ALTER TABLE online_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "online_orders_tenant_select" ON online_orders;
CREATE POLICY "online_orders_tenant_select" 
  ON online_orders FOR SELECT 
  USING (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_orders_tenant_insert" ON online_orders;
CREATE POLICY "online_orders_tenant_insert" 
  ON online_orders FOR INSERT 
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_orders_tenant_update" ON online_orders;
CREATE POLICY "online_orders_tenant_update" 
  ON online_orders FOR UPDATE 
  USING (tenant_id = public.user_tenant_id())
  WITH CHECK (tenant_id = public.user_tenant_id());

DROP POLICY IF EXISTS "online_orders_tenant_delete" ON online_orders;
CREATE POLICY "online_orders_tenant_delete" 
  ON online_orders FOR DELETE 
  USING (tenant_id = public.user_tenant_id());

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
-- All 22 tables now have complete RLS policies for tenant isolation
-- 18 direct tenant_id tables + 4 child tables with parent joins
-- 
-- Website tables (7):
--   - website_blocks (NEW)
--   - website_settings (NEW)
--   - featured_products (NEW)
--   - online_orders (NEW)
--   - website_banners
--   - website_content
--   - online_order_items
-- ============================================================================
