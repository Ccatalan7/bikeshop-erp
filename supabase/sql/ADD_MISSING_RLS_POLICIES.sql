-- ============================================================================
-- ADD MISSING RLS POLICIES FOR 17 TABLES
-- ============================================================================
-- These tables have RLS enabled but NO policies, which denies all access.
-- This script creates tenant-filtered policies for all CRUD operations.
-- 
-- Run this ONCE in Supabase SQL Editor to add missing policies.
-- After deployment, verify with FINAL_MULTI_TENANT_VERIFICATION.sql
-- ============================================================================

-- 1. bikes (already in core_schema.sql line 9801, but not deployed)
do $$ begin
  drop policy if exists "bikes_select" on bikes;
  drop policy if exists "bikes_insert" on bikes;
  drop policy if exists "bikes_update" on bikes;
  drop policy if exists "bikes_delete" on bikes;
  
  create policy "bikes_select" on bikes for select using (tenant_id = public.user_tenant_id());
  create policy "bikes_insert" on bikes for insert with check (tenant_id = public.user_tenant_id());
  create policy "bikes_update" on bikes for update using (tenant_id = public.user_tenant_id());
  create policy "bikes_delete" on bikes for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for bikes';
exception
  when undefined_table then raise notice '⚠ Table bikes does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in bikes';
end $$;

-- 2. company_settings (already in core_schema.sql line 9788, but not deployed)
do $$ begin
  drop policy if exists "company_settings_select" on company_settings;
  drop policy if exists "company_settings_insert" on company_settings;
  drop policy if exists "company_settings_update" on company_settings;
  drop policy if exists "company_settings_delete" on company_settings;
  
  create policy "company_settings_select" on company_settings for select using (tenant_id = public.user_tenant_id());
  create policy "company_settings_insert" on company_settings for insert with check (tenant_id = public.user_tenant_id());
  create policy "company_settings_update" on company_settings for update using (tenant_id = public.user_tenant_id());
  create policy "company_settings_delete" on company_settings for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for company_settings';
exception
  when undefined_table then raise notice '⚠ Table company_settings does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in company_settings';
end $$;

-- 3. contracts (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "contracts_select" on contracts for select using (tenant_id = public.user_tenant_id());
  create policy "contracts_insert" on contracts for insert with check (tenant_id = public.user_tenant_id());
  create policy "contracts_update" on contracts for update using (tenant_id = public.user_tenant_id());
  create policy "contracts_delete" on contracts for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for contracts';
exception
  when undefined_table then raise notice '⚠ Table contracts does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in contracts';
  when duplicate_object then raise notice '⚠ Policies already exist for contracts';
end $$;

-- 4. customer_addresses (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "customer_addresses_select" on customer_addresses for select using (tenant_id = public.user_tenant_id());
  create policy "customer_addresses_insert" on customer_addresses for insert with check (tenant_id = public.user_tenant_id());
  create policy "customer_addresses_update" on customer_addresses for update using (tenant_id = public.user_tenant_id());
  create policy "customer_addresses_delete" on customer_addresses for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for customer_addresses';
exception
  when undefined_table then raise notice '⚠ Table customer_addresses does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in customer_addresses';
  when duplicate_object then raise notice '⚠ Policies already exist for customer_addresses';
end $$;

-- 5. employee_contracts (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "employee_contracts_select" on employee_contracts for select using (tenant_id = public.user_tenant_id());
  create policy "employee_contracts_insert" on employee_contracts for insert with check (tenant_id = public.user_tenant_id());
  create policy "employee_contracts_update" on employee_contracts for update using (tenant_id = public.user_tenant_id());
  create policy "employee_contracts_delete" on employee_contracts for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for employee_contracts';
exception
  when undefined_table then raise notice '⚠ Table employee_contracts does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in employee_contracts';
  when duplicate_object then raise notice '⚠ Policies already exist for employee_contracts';
end $$;

-- 6. expense_attachments (already in core_schema.sql line 9866, but not deployed)
do $$ begin
  drop policy if exists "expense_attachments_select" on expense_attachments;
  drop policy if exists "expense_attachments_insert" on expense_attachments;
  drop policy if exists "expense_attachments_update" on expense_attachments;
  drop policy if exists "expense_attachments_delete" on expense_attachments;
  
  create policy "expense_attachments_select" on expense_attachments for select using (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_insert" on expense_attachments for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_update" on expense_attachments for update using (tenant_id = public.user_tenant_id());
  create policy "expense_attachments_delete" on expense_attachments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_attachments';
exception
  when undefined_table then raise notice '⚠ Table expense_attachments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_attachments';
end $$;

-- 7. expense_lines (already in core_schema.sql line 9879, but not deployed)
do $$ begin
  drop policy if exists "expense_lines_select" on expense_lines;
  drop policy if exists "expense_lines_insert" on expense_lines;
  drop policy if exists "expense_lines_update" on expense_lines;
  drop policy if exists "expense_lines_delete" on expense_lines;
  
  create policy "expense_lines_select" on expense_lines for select using (tenant_id = public.user_tenant_id());
  create policy "expense_lines_insert" on expense_lines for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_lines_update" on expense_lines for update using (tenant_id = public.user_tenant_id());
  create policy "expense_lines_delete" on expense_lines for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_lines';
exception
  when undefined_table then raise notice '⚠ Table expense_lines does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_lines';
end $$;

-- 8. expense_payments (already in core_schema.sql line 9892, but not deployed)
do $$ begin
  drop policy if exists "expense_payments_select" on expense_payments;
  drop policy if exists "expense_payments_insert" on expense_payments;
  drop policy if exists "expense_payments_update" on expense_payments;
  drop policy if exists "expense_payments_delete" on expense_payments;
  
  create policy "expense_payments_select" on expense_payments for select using (tenant_id = public.user_tenant_id());
  create policy "expense_payments_insert" on expense_payments for insert with check (tenant_id = public.user_tenant_id());
  create policy "expense_payments_update" on expense_payments for update using (tenant_id = public.user_tenant_id());
  create policy "expense_payments_delete" on expense_payments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for expense_payments';
exception
  when undefined_table then raise notice '⚠ Table expense_payments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in expense_payments';
end $$;

-- 9. mechanic_job_items (already in core_schema.sql line 9827, but not deployed)
do $$ begin
  drop policy if exists "mechanic_job_items_select" on mechanic_job_items;
  drop policy if exists "mechanic_job_items_insert" on mechanic_job_items;
  drop policy if exists "mechanic_job_items_update" on mechanic_job_items;
  drop policy if exists "mechanic_job_items_delete" on mechanic_job_items;
  
  create policy "mechanic_job_items_select" on mechanic_job_items for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_insert" on mechanic_job_items for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_update" on mechanic_job_items for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_items_delete" on mechanic_job_items for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_job_items';
exception
  when undefined_table then raise notice '⚠ Table mechanic_job_items does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_job_items';
end $$;

-- 10. mechanic_job_labor (already in core_schema.sql line 9840, but not deployed)
do $$ begin
  drop policy if exists "mechanic_job_labor_select" on mechanic_job_labor;
  drop policy if exists "mechanic_job_labor_insert" on mechanic_job_labor;
  drop policy if exists "mechanic_job_labor_update" on mechanic_job_labor;
  drop policy if exists "mechanic_job_labor_delete" on mechanic_job_labor;
  
  create policy "mechanic_job_labor_select" on mechanic_job_labor for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_labor_insert" on mechanic_job_labor for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_labor_update" on mechanic_job_labor for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_labor_delete" on mechanic_job_labor for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_job_labor';
exception
  when undefined_table then raise notice '⚠ Table mechanic_job_labor does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_job_labor';
end $$;

-- 11. mechanic_job_timeline (already in core_schema.sql line 9853, but not deployed)
do $$ begin
  drop policy if exists "mechanic_job_timeline_select" on mechanic_job_timeline;
  drop policy if exists "mechanic_job_timeline_insert" on mechanic_job_timeline;
  drop policy if exists "mechanic_job_timeline_update" on mechanic_job_timeline;
  drop policy if exists "mechanic_job_timeline_delete" on mechanic_job_timeline;
  
  create policy "mechanic_job_timeline_select" on mechanic_job_timeline for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_timeline_insert" on mechanic_job_timeline for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_timeline_update" on mechanic_job_timeline for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_job_timeline_delete" on mechanic_job_timeline for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_job_timeline';
exception
  when undefined_table then raise notice '⚠ Table mechanic_job_timeline does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_job_timeline';
end $$;

-- 12. mechanic_jobs (already in core_schema.sql line 9814, but not deployed)
do $$ begin
  drop policy if exists "mechanic_jobs_select" on mechanic_jobs;
  drop policy if exists "mechanic_jobs_insert" on mechanic_jobs;
  drop policy if exists "mechanic_jobs_update" on mechanic_jobs;
  drop policy if exists "mechanic_jobs_delete" on mechanic_jobs;
  
  create policy "mechanic_jobs_select" on mechanic_jobs for select using (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_insert" on mechanic_jobs for insert with check (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_update" on mechanic_jobs for update using (tenant_id = public.user_tenant_id());
  create policy "mechanic_jobs_delete" on mechanic_jobs for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for mechanic_jobs';
exception
  when undefined_table then raise notice '⚠ Table mechanic_jobs does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in mechanic_jobs';
end $$;

-- 13. payments (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "payments_select" on payments for select using (tenant_id = public.user_tenant_id());
  create policy "payments_insert" on payments for insert with check (tenant_id = public.user_tenant_id());
  create policy "payments_update" on payments for update using (tenant_id = public.user_tenant_id());
  create policy "payments_delete" on payments for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for payments';
exception
  when undefined_table then raise notice '⚠ Table payments does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in payments';
  when duplicate_object then raise notice '⚠ Policies already exist for payments';
end $$;

-- 14. product_images (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "product_images_select" on product_images for select using (tenant_id = public.user_tenant_id());
  create policy "product_images_insert" on product_images for insert with check (tenant_id = public.user_tenant_id());
  create policy "product_images_update" on product_images for update using (tenant_id = public.user_tenant_id());
  create policy "product_images_delete" on product_images for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for product_images';
exception
  when undefined_table then raise notice '⚠ Table product_images does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in product_images';
  when duplicate_object then raise notice '⚠ Policies already exist for product_images';
end $$;

-- 15. service_packages (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "service_packages_select" on service_packages for select using (tenant_id = public.user_tenant_id());
  create policy "service_packages_insert" on service_packages for insert with check (tenant_id = public.user_tenant_id());
  create policy "service_packages_update" on service_packages for update using (tenant_id = public.user_tenant_id());
  create policy "service_packages_delete" on service_packages for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for service_packages';
exception
  when undefined_table then raise notice '⚠ Table service_packages does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in service_packages';
  when duplicate_object then raise notice '⚠ Policies already exist for service_packages';
end $$;

-- 16. warehouses (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "warehouses_select" on warehouses for select using (tenant_id = public.user_tenant_id());
  create policy "warehouses_insert" on warehouses for insert with check (tenant_id = public.user_tenant_id());
  create policy "warehouses_update" on warehouses for update using (tenant_id = public.user_tenant_id());
  create policy "warehouses_delete" on warehouses for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for warehouses';
exception
  when undefined_table then raise notice '⚠ Table warehouses does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in warehouses';
  when duplicate_object then raise notice '⚠ Policies already exist for warehouses';
end $$;

-- 17. work_orders (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "work_orders_select" on work_orders for select using (tenant_id = public.user_tenant_id());
  create policy "work_orders_insert" on work_orders for insert with check (tenant_id = public.user_tenant_id());
  create policy "work_orders_update" on work_orders for update using (tenant_id = public.user_tenant_id());
  create policy "work_orders_delete" on work_orders for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for work_orders';
exception
  when undefined_table then raise notice '⚠ Table work_orders does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in work_orders';
  when duplicate_object then raise notice '⚠ Policies already exist for work_orders';
end $$;

-- 18. work_schedules (NEW - add to core_schema.sql after deployment)
do $$ begin
  create policy "work_schedules_select" on work_schedules for select using (tenant_id = public.user_tenant_id());
  create policy "work_schedules_insert" on work_schedules for insert with check (tenant_id = public.user_tenant_id());
  create policy "work_schedules_update" on work_schedules for update using (tenant_id = public.user_tenant_id());
  create policy "work_schedules_delete" on work_schedules for delete using (tenant_id = public.user_tenant_id());
  raise notice '✓ Created RLS policies for work_schedules';
exception
  when undefined_table then raise notice '⚠ Table work_schedules does not exist';
  when undefined_column then raise notice '⚠ Column tenant_id missing in work_schedules';
  when duplicate_object then raise notice '⚠ Policies already exist for work_schedules';
end $$;

-- ============================================================================
-- VERIFICATION: Check how many tables still have no policies
-- ============================================================================

select
  'POST-DEPLOYMENT VERIFICATION' as report,
  count(*) filter (where policy_count = 0) as tables_without_policies,
  count(*) filter (where policy_count > 0) as tables_with_policies
from (
  select
    t.tablename,
    coalesce((
      select count(*)
      from pg_policies p
      where p.tablename = t.tablename
        and p.schemaname = 'public'
    ), 0) as policy_count
  from pg_tables t
  where t.schemaname = 'public'
    and t.tablename not in ('schema_migrations', 'spatial_ref_sys')
    and exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = t.tablename
        and c.column_name = 'tenant_id'
    )
) counts;

-- ============================================================================
-- NEXT STEPS:
-- 1. Run this script in Supabase SQL Editor
-- 2. Re-run FINAL_MULTI_TENANT_VERIFICATION.sql to verify all policies exist
-- 3. Add missing policies to core_schema.sql for future deployments:
--    - contracts
--    - customer_addresses
--    - employee_contracts
--    - payments
--    - product_images
--    - service_packages
--    - warehouses
--    - work_orders
--    - work_schedules
-- ============================================================================
