-- ============================================================================
-- FINAL FIX: Enable RLS and Create Policies for 9 Missing Tables
-- ============================================================================
-- Run this in Supabase SQL Editor to fix the remaining cross-tenant data leakage
-- ============================================================================

-- Step 1: Enable RLS on the 9 tables
ALTER TABLE bikes ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE mechanic_job_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE mechanic_job_labor ENABLE ROW LEVEL SECURITY;
ALTER TABLE mechanic_job_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE mechanic_jobs ENABLE ROW LEVEL SECURITY;

-- Step 2: Create RLS policies for company_settings (CRITICAL - this is why you see Vinabike's logo)
DO $$ BEGIN
  CREATE POLICY "company_settings_select" ON company_settings FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "company_settings_insert" ON company_settings FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "company_settings_update" ON company_settings FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "company_settings_delete" ON company_settings FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for company_settings';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for company_settings';
END $$;

-- Step 3: Create RLS policies for bikes
DO $$ BEGIN
  CREATE POLICY "bikes_select" ON bikes FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "bikes_insert" ON bikes FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "bikes_update" ON bikes FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "bikes_delete" ON bikes FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for bikes';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for bikes';
END $$;

-- Step 4: Create RLS policies for mechanic_jobs
DO $$ BEGIN
  CREATE POLICY "mechanic_jobs_select" ON mechanic_jobs FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_jobs_insert" ON mechanic_jobs FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_jobs_update" ON mechanic_jobs FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_jobs_delete" ON mechanic_jobs FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for mechanic_jobs';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for mechanic_jobs';
END $$;

-- Step 5: Create RLS policies for mechanic_job_items
DO $$ BEGIN
  CREATE POLICY "mechanic_job_items_select" ON mechanic_job_items FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_items_insert" ON mechanic_job_items FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_items_update" ON mechanic_job_items FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_items_delete" ON mechanic_job_items FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for mechanic_job_items';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for mechanic_job_items';
END $$;

-- Step 6: Create RLS policies for mechanic_job_labor
DO $$ BEGIN
  CREATE POLICY "mechanic_job_labor_select" ON mechanic_job_labor FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_labor_insert" ON mechanic_job_labor FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_labor_update" ON mechanic_job_labor FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_labor_delete" ON mechanic_job_labor FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for mechanic_job_labor';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for mechanic_job_labor';
END $$;

-- Step 7: Create RLS policies for mechanic_job_timeline
DO $$ BEGIN
  CREATE POLICY "mechanic_job_timeline_select" ON mechanic_job_timeline FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_timeline_insert" ON mechanic_job_timeline FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_timeline_update" ON mechanic_job_timeline FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "mechanic_job_timeline_delete" ON mechanic_job_timeline FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for mechanic_job_timeline';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for mechanic_job_timeline';
END $$;

-- Step 8: Create RLS policies for expense_attachments
DO $$ BEGIN
  CREATE POLICY "expense_attachments_select" ON expense_attachments FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_attachments_insert" ON expense_attachments FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_attachments_update" ON expense_attachments FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_attachments_delete" ON expense_attachments FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for expense_attachments';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for expense_attachments';
END $$;

-- Step 9: Create RLS policies for expense_lines
DO $$ BEGIN
  CREATE POLICY "expense_lines_select" ON expense_lines FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_lines_insert" ON expense_lines FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_lines_update" ON expense_lines FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_lines_delete" ON expense_lines FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for expense_lines';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for expense_lines';
END $$;

-- Step 10: Create RLS policies for expense_payments
DO $$ BEGIN
  CREATE POLICY "expense_payments_select" ON expense_payments FOR SELECT USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_payments_insert" ON expense_payments FOR INSERT WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_payments_update" ON expense_payments FOR UPDATE USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "expense_payments_delete" ON expense_payments FOR DELETE USING (tenant_id = public.user_tenant_id());
  RAISE NOTICE '✓ Created RLS policies for expense_payments';
EXCEPTION
  WHEN duplicate_object THEN RAISE NOTICE '⚠ Policies already exist for expense_payments';
END $$;

-- Verify all 9 tables now have RLS enabled
SELECT 
  tablename,
  CASE WHEN rowsecurity THEN '✅ RLS Enabled' ELSE '❌ RLS DISABLED' END as status
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'bikes', 'company_settings', 'expense_attachments', 'expense_lines', 
    'expense_payments', 'mechanic_job_items', 'mechanic_job_labor', 
    'mechanic_job_timeline', 'mechanic_jobs'
  )
ORDER BY tablename;

-- Verify all 9 tables now have RLS policies
SELECT 
  tablename,
  COUNT(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'bikes', 'company_settings', 'expense_attachments', 'expense_lines', 
    'expense_payments', 'mechanic_job_items', 'mechanic_job_labor', 
    'mechanic_job_timeline', 'mechanic_jobs'
  )
GROUP BY tablename
ORDER BY tablename;

-- Expected: All 9 tables should show '✅ RLS Enabled' and have 4 policies each
