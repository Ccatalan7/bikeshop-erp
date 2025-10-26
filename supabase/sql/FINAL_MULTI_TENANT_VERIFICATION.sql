-- ============================================================================
-- FINAL MULTI-TENANT ISOLATION VERIFICATION TEST
-- ============================================================================
-- This is the ULTIMATE test to verify complete multi-tenant SaaS architecture.
-- It checks EVERY table, EVERY policy, and verifies core_schema.sql compliance.
--
-- RUN THIS FROM SUPABASE SQL EDITOR (will show aggregate results)
-- Individual row tests must be run from the Flutter app with authenticated user
-- ============================================================================

-- ============================================================================
-- TEST 1: COMPREHENSIVE TABLE INVENTORY
-- ============================================================================
-- List EVERY table in the public schema with tenant_id status
-- This catches new tables that might have been added without tenant_id

select
  'TEST 1: TABLE INVENTORY' as test_name,
  t.tablename as table_name,
  case
    when exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = t.tablename
        and c.column_name = 'tenant_id'
    ) then '✅ HAS tenant_id'
    else '❌ MISSING tenant_id'
  end as tenant_id_status,
  case
    when t.tablename in ('schema_migrations', 'spatial_ref_sys') then '⚠️  System table (OK)'
    when exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = t.tablename
        and c.column_name = 'tenant_id'
    ) then '✅ Business table'
    else '🚨 CRITICAL: Business table without tenant_id'
  end as classification,
  case
    when c.relrowsecurity then '✅ RLS ENABLED'
    else '❌ RLS DISABLED'
  end as rls_status
from pg_tables t
join pg_class c on c.relname = t.tablename
where t.schemaname = 'public'
  and t.tablename not like 'pg_%'
  and t.tablename not in ('schema_migrations', 'spatial_ref_sys')
order by
  case when exists (
    select 1 from information_schema.columns col
    where col.table_schema = 'public'
      and col.table_name = t.tablename
      and col.column_name = 'tenant_id'
  ) then 1 else 0 end,
  t.tablename;

-- ============================================================================
-- TEST 2: TENANT_ID COLUMN VALIDATION
-- ============================================================================
-- Verify tenant_id column has correct type, constraints, and foreign key

select
  'TEST 2: TENANT_ID COLUMN VALIDATION' as test_name,
  c.table_name,
  c.data_type,
  case when c.is_nullable = 'NO' then '✅ NOT NULL' else '❌ NULLABLE' end as nullable_status,
  case
    when exists (
      select 1 from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on tc.constraint_name = kcu.constraint_name
      where tc.table_name = c.table_name
        and tc.constraint_type = 'FOREIGN KEY'
        and kcu.column_name = 'tenant_id'
    ) then '✅ FK to tenants'
    else '❌ NO FK'
  end as foreign_key_status,
  case
    when exists (
      select 1 from pg_indexes
      where schemaname = 'public'
        and tablename = c.table_name
        and indexdef like '%tenant_id%'
    ) then '✅ INDEXED'
    else '⚠️  NO INDEX'
  end as index_status
from information_schema.columns c
where c.table_schema = 'public'
  and c.column_name = 'tenant_id'
  and c.table_name not in ('tenants') -- tenants table itself doesn't have tenant_id
order by c.table_name;

-- ============================================================================
-- TEST 3: NULL tenant_id CHECK (CRITICAL - MUST BE ZERO)
-- ============================================================================
-- Check for ANY rows with NULL tenant_id (data isolation breach)

do $$
declare
  v_table record;
  v_null_count integer;
  v_total_violations integer := 0;
  v_sql text;
begin
  raise notice '============================================================================';
  raise notice 'TEST 3: NULL TENANT_ID CHECK';
  raise notice '============================================================================';
  
  for v_table in
    select table_name
    from information_schema.columns
    where table_schema = 'public'
      and column_name = 'tenant_id'
      and table_name != 'tenants'
    order by table_name
  loop
    v_sql := format('select count(*) from public.%I where tenant_id is null', v_table.table_name);
    execute v_sql into v_null_count;
    
    if v_null_count > 0 then
      raise notice '🚨 CRITICAL: Table % has % rows with NULL tenant_id', v_table.table_name, v_null_count;
      v_total_violations := v_total_violations + v_null_count;
    else
      raise notice '✅ Table % has no NULL tenant_id values', v_table.table_name;
    end if;
  end loop;
  
  raise notice '============================================================================';
  if v_total_violations = 0 then
    raise notice '✅ SUCCESS: All tables have valid tenant_id values';
  else
    raise notice '🚨 CRITICAL FAILURE: % total rows with NULL tenant_id', v_total_violations;
  end if;
  raise notice '============================================================================';
end $$;

-- ============================================================================
-- TEST 4: RLS POLICY INVENTORY
-- ============================================================================
-- List ALL policies on ALL tables to verify tenant filtering

select
  'TEST 4: RLS POLICY INVENTORY' as test_name,
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  case
    -- Check if policy definition includes tenant filtering (both qual and with_check)
    when qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%' then '✅ TENANT FILTERED (qual)'
    when with_check like '%tenant_id%user_tenant_id%' or with_check like '%user_tenant_id()%' then '✅ TENANT FILTERED (with_check)'
    when qual like '%auth.uid()%' and tablename not in ('customers', 'customer_addresses') then '⚠️  USER FILTERED'
    when qual like '%true%' and qual not like '%user_tenant_id%' then '🚨 PUBLIC ACCESS (qual)'
    when qual is null and cmd = 'INSERT' and (with_check like '%user_tenant_id%') then '✅ INSERT POLICY (tenant filtered)'
    when qual is null and cmd = 'INSERT' then '⚠️  INSERT POLICY (check with_check)'
    when qual is null then '🚨 NO FILTER (null qual)'
    else '⚠️  CHECK MANUALLY: ' || left(coalesce(qual, with_check, 'none'), 50)
  end as filter_status,
  left(coalesce(qual, 'NULL - check with_check: ' || with_check), 100) as policy_definition_preview
from pg_policies
where schemaname = 'public'
order by
  case
    when qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%' then 1
    when with_check like '%tenant_id%user_tenant_id%' or with_check like '%user_tenant_id()%' then 1
    when qual like '%auth.uid()%' then 2
    when qual like '%true%' or qual is null then 3
    else 4
  end,
  tablename,
  policyname;

-- ============================================================================
-- TEST 5: DANGEROUS POLICY DETECTION
-- ============================================================================
-- Find policies that allow cross-tenant access (PUBLIC, no tenant filter)

select
  'TEST 5: DANGEROUS POLICY DETECTION' as test_name,
  tablename,
  policyname,
  cmd as operation,
  '🚨 DANGEROUS' as severity,
  case
    when qual like '%true%' and qual not like '%user_tenant_id%' then 'PUBLIC ACCESS (using true)'
    when qual is null and cmd = 'INSERT' and (with_check is null or with_check not like '%user_tenant_id%') then 'INSERT: No tenant filter in with_check'
    when qual is null and cmd != 'INSERT' then 'NO FILTER (null qual, not INSERT)'
    when qual like '%auth.uid()%' and qual not like '%tenant_id%' then 'USER-ONLY FILTER (no tenant isolation)'
    when roles::text like '%anon%' and qual not like '%tenant_id%' and (with_check is null or with_check not like '%tenant_id%') then 'ANONYMOUS ACCESS (no tenant filter)'
    else 'OTHER: ' || left(coalesce(qual, with_check, 'none'), 50)
  end as reason,
  left(coalesce(qual, 'qual=NULL, with_check=' || with_check), 150) as policy_definition
from pg_policies
where schemaname = 'public'
  -- Exclude policies that properly filter by tenant in qual OR with_check
  and not (
    qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%' or
    with_check like '%tenant_id%user_tenant_id%' or with_check like '%user_tenant_id()%'
  )
  -- Flag truly dangerous patterns
  and (
    (qual like '%true%' and qual not like '%user_tenant_id%')
    or (qual is null and cmd = 'INSERT' and (with_check is null or with_check not like '%user_tenant_id%'))
    or (qual is null and cmd != 'INSERT')
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
    or (roles::text like '%anon%' and qual not like '%tenant_id%' and (with_check is null or with_check not like '%tenant_id%'))
  )
order by tablename, policyname;

-- ============================================================================
-- TEST 6: TABLES WITHOUT RLS POLICIES
-- ============================================================================
-- Find tables with RLS enabled but NO policies (denies all access)

select
  'TEST 6: TABLES WITHOUT POLICIES' as test_name,
  t.tablename,
  case when c.relrowsecurity then '✅ RLS ENABLED' else '❌ RLS DISABLED' end as rls_status,
  coalesce(p.policy_count, 0) as policy_count,
  case
    when coalesce(p.policy_count, 0) = 0 and c.relrowsecurity then '⚠️  NO POLICIES (denies all access)'
    when coalesce(p.policy_count, 0) = 0 and not c.relrowsecurity then '🚨 NO RLS, NO POLICIES (open access)'
    else '✅ Has policies'
  end as status
from pg_tables t
join pg_class c on c.relname = t.tablename
left join (
  select tablename, count(*) as policy_count
  from pg_policies
  where schemaname = 'public'
  group by tablename
) p on p.tablename = t.tablename
where t.schemaname = 'public'
  and t.tablename not like 'pg_%'
  and t.tablename not in ('schema_migrations', 'spatial_ref_sys')
order by
  case when coalesce(p.policy_count, 0) = 0 then 0 else 1 end,
  t.tablename;

-- ============================================================================
-- TEST 7: POLICY COVERAGE CHECK
-- ============================================================================
-- Verify each table has policies for SELECT, INSERT, UPDATE, DELETE

select
  'TEST 7: POLICY COVERAGE CHECK' as test_name,
  t.tablename,
  case when c.relrowsecurity then '✅' else '❌' end as rls_enabled,
  case when exists (select 1 from pg_policies where tablename = t.tablename and cmd = 'SELECT') then '✅' else '❌' end as has_select,
  case when exists (select 1 from pg_policies where tablename = t.tablename and cmd = 'INSERT') then '✅' else '❌' end as has_insert,
  case when exists (select 1 from pg_policies where tablename = t.tablename and cmd = 'UPDATE') then '✅' else '❌' end as has_update,
  case when exists (select 1 from pg_policies where tablename = t.tablename and cmd = 'DELETE') then '✅' else '❌' end as has_delete,
  (
    select count(*)
    from pg_policies p
    where p.tablename = t.tablename
      and (p.qual like '%tenant_id%user_tenant_id%' or p.qual like '%user_tenant_id()%')
  ) as tenant_filtered_policies
from pg_tables t
join pg_class c on c.relname = t.tablename
where t.schemaname = 'public'
  and t.tablename not like 'pg_%'
  and t.tablename not in ('schema_migrations', 'spatial_ref_sys')
  and exists (
    select 1 from information_schema.columns col
    where col.table_schema = 'public'
      and col.table_name = t.tablename
      and col.column_name = 'tenant_id'
  )
order by t.tablename;

-- ============================================================================
-- TEST 8: HELPER FUNCTION VALIDATION
-- ============================================================================
-- Verify critical helper functions exist and are properly defined

select
  'TEST 8: HELPER FUNCTION VALIDATION' as test_name,
  proname as function_name,
  case
    when proname = 'user_tenant_id' then '✅ CRITICAL - Returns current user tenant'
    when proname like '%tenant%' then '✅ Tenant-related function'
    when proname like 'ensure_%' then '✅ Helper function'
    else '✅ Exists'
  end as purpose,
  pg_get_functiondef(p.oid)::text like '%tenant_id%' as uses_tenant_id
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in (
    'user_tenant_id',
    'ensure_account',
    'recalculate_sales_invoice_payments',
    'recalculate_purchase_invoice_payments',
    'recalculate_expense_totals',
    'recalculate_mechanic_job_costs'
  )
order by proname;

-- ============================================================================
-- TEST 9: TRIGGER VALIDATION
-- ============================================================================
-- Verify all critical triggers exist and point to correct functions

select
  'TEST 9: TRIGGER VALIDATION' as test_name,
  t.tgname as trigger_name,
  c.relname as table_name,
  p.proname as function_name,
  case
    when t.tgtype::integer & 1 = 1 then 'ROW'
    else 'STATEMENT'
  end as level,
  case
    when t.tgtype::integer & 2 = 2 then 'BEFORE'
    when t.tgtype::integer & 4 = 4 then 'AFTER'
    else 'INSTEAD OF'
  end as timing,
  case
    when t.tgtype::integer & 4 = 4 then 'INSERT'
    when t.tgtype::integer & 8 = 8 then 'DELETE'
    when t.tgtype::integer & 16 = 16 then 'UPDATE'
    else 'MULTIPLE'
  end as event
from pg_trigger t
join pg_class c on t.tgrelid = c.oid
join pg_proc p on t.tgfoid = p.oid
where c.relnamespace = (select oid from pg_namespace where nspname = 'public')
  and not t.tgisinternal
  and t.tgname like any(array[
    'trg_%',
    '%_trigger',
    '%_change'
  ])
order by c.relname, t.tgname;

-- ============================================================================
-- TEST 10: ACCOUNTING INTEGRITY CHECK
-- ============================================================================
-- Verify accounting helper functions use tenant isolation

select
  'TEST 10: ACCOUNTING INTEGRITY' as test_name,
  proname as function_name,
  case
    when pg_get_functiondef(p.oid)::text like '%tenant_id%' then '✅ TENANT-AWARE'
    else '⚠️  CHECK MANUALLY'
  end as tenant_awareness,
  case
    when proname like 'create_%journal_entry%' then 'Creates journal entries'
    when proname like 'delete_%journal_entry%' then 'Deletes journal entries'
    when proname like 'consume_%inventory%' then 'Inventory management'
    when proname like 'restore_%inventory%' then 'Inventory restoration'
    when proname like 'recalculate%' then 'Recalculation logic'
    else 'Other accounting function'
  end as purpose
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    proname like '%journal_entry%'
    or proname like '%inventory%'
    or proname like 'recalculate%'
    or proname like 'ensure_account%'
  )
order by proname;

-- ============================================================================
-- TEST 11: SCHEMA COMPLETENESS CHECK
-- ============================================================================
-- Verify all expected tables from core_schema.sql exist in database

with expected_tables as (
  select unnest(array[
    'tenants',
    'user_activity_log',
    'user_invitations',
    'customers',
    'customer_addresses',
    'company_settings',
    'product_brands',
    'products',
    'product_categories',
    'suppliers',
    'accounts',
    'sales_invoices',
    'sales_payments',
    'payment_methods',
    'purchase_invoices',
    'purchase_payments',
    'expenses',
    'expense_categories',
    'expense_lines',
    'expense_payments',
    'expense_attachments',
    'stock_movements',
    'journal_entries',
    'journal_lines',
    'orders',
    'order_items',
    'bikes',
    'service_packages',
    'mechanic_jobs',
    'mechanic_job_items',
    'mechanic_job_labor',
    'mechanic_job_timeline',
    'online_orders',
    'online_order_items',
    'website_settings',
    'website_banners',
    'website_blocks',
    'website_content',
    'featured_products',
    'employees',
    'contracts',
    'attendance_records',
    'leave_requests',
    'payroll_records',
    'departments',
    'job_titles'
  ]) as table_name
)
select
  'TEST 11: SCHEMA COMPLETENESS' as test_name,
  et.table_name as expected_table,
  case
    when t.tablename is not null then '✅ EXISTS'
    else '❌ MISSING'
  end as status,
  case
    when t.tablename is not null and exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = et.table_name
        and c.column_name = 'tenant_id'
    ) then '✅ HAS tenant_id'
    when t.tablename is not null and et.table_name in ('tenants') then '⚠️  System table (no tenant_id expected)'
    when t.tablename is not null then '❌ MISSING tenant_id'
    else ''
  end as tenant_id_status
from expected_tables et
left join pg_tables t on t.tablename = et.table_name and t.schemaname = 'public'
order by
  case when t.tablename is not null then 1 else 0 end,
  et.table_name;

-- ============================================================================
-- TEST 12: FINAL SUMMARY
-- ============================================================================

select
  'TEST 12: FINAL SUMMARY' as test_name,
  (select count(*) from pg_tables where schemaname = 'public' and tablename not in ('schema_migrations', 'spatial_ref_sys')) as total_tables,
  (select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'tenant_id') as tables_with_tenant_id,
  (select count(*) from pg_tables t join pg_class c on c.relname = t.tablename where t.schemaname = 'public' and c.relrowsecurity) as tables_with_rls,
  (select count(*) from pg_policies where schemaname = 'public') as total_policies,
  (select count(*) from pg_policies where schemaname = 'public' and (
    qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%' or
    with_check like '%tenant_id%user_tenant_id%' or with_check like '%user_tenant_id()%'
  )) as tenant_filtered_policies,
  (select count(*) from pg_policies where schemaname = 'public' and (
    (qual like '%true%' and qual not like '%user_tenant_id%') or 
    (qual is null and (with_check is null or (with_check not like '%user_tenant_id%'))) or 
    (qual like '%auth.uid()%' and qual not like '%tenant_id%')
  )) as dangerous_policies;

-- ============================================================================
-- INSTRUCTIONS FOR NEXT STEPS
-- ============================================================================
-- 
-- ✅ IF ALL TESTS PASS:
--    - Deploy core_schema.sql to production
--    - Test multi-tenant isolation from Flutter app
--    - Mark multi-tenant migration as COMPLETE
-- 
-- ❌ IF ANY TEST FAILS:
--    - Review failed test output
--    - Fix issues in core_schema.sql (NOT in patch files)
--    - Re-run this verification test
--    - Do NOT deploy until all tests pass
-- 
-- 🚨 CRITICAL FAILURES (must fix immediately):
--    - Tables without tenant_id
--    - Tables with NULL tenant_id values
--    - Tables without RLS enabled
--    - Dangerous policies (public access, no tenant filter)
-- 
-- ⚠️  WARNINGS (review and fix if needed):
--    - Tables without indexes on tenant_id
--    - Missing CRUD policies (SELECT/INSERT/UPDATE/DELETE)
--    - Functions that don't reference tenant_id
-- 
-- ============================================================================
