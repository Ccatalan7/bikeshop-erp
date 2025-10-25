-- ============================================================================
-- COMPREHENSIVE TENANT ISOLATION VERIFICATION
-- ============================================================================
-- Run this in Supabase SQL Editor to verify multi-tenant setup is correct
-- ============================================================================

-- 1. Check if OLD non-tenant-filtered policies still exist (SHOULD BE 0 ROWS)
select 
  '❌ OLD POLICIES STILL EXIST' as status,
  tablename,
  policyname,
  cmd
from pg_policies
where schemaname = 'public'
  and (
    policyname like 'Authenticated%read' 
    or policyname like 'Authenticated%insert'
    or policyname like 'Authenticated%update'
    or policyname like 'Authenticated%delete'
    or policyname like 'Authenticated can manage%'
  )
order by tablename, policyname;

-- If above returns rows, OLD POLICIES STILL EXIST - run DROP_OLD_POLICIES_FROM_DATABASE.sql first!

-- 2. Check if NEW tenant-filtered policies exist (SHOULD HAVE MANY ROWS)
select 
  '✅ NEW TENANT POLICIES' as status,
  tablename,
  policyname,
  cmd
from pg_policies
where schemaname = 'public'
  and policyname ~ '_(select|insert|update|delete)$'
  and (
    qual like '%user_tenant_id()%' 
    or with_check like '%user_tenant_id()%'
  )
order by tablename, policyname;

-- 3. Verify ALL business tables have tenant_id column (SHOULD BE 0 MISSING)
select 
  '❌ MISSING tenant_id COLUMN' as status,
  table_name
from information_schema.tables t
where table_schema = 'public'
  and table_type = 'BASE TABLE'
  and table_name not in ('schema_migrations', 'spatial_ref_sys', 'tenants', 'storage', 'buckets', 'objects')
  and table_name not like 'auth.%'
  and table_name not like 'storage.%'
  and not exists (
    select 1 
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = t.table_name
      and c.column_name = 'tenant_id'
  )
order by table_name;

-- 4. Check for NULL tenant_id values in critical tables (SHOULD BE 0 ROWS)
do $$
declare
  v_table text;
  v_count integer;
  v_tables text[] := ARRAY[
    'products', 'customers', 'suppliers', 'sales_invoices', 'purchase_invoices',
    'accounts', 'journal_entries', 'journal_lines', 'employees', 'departments',
    'orders', 'order_items', 'stock_movements', 'product_brands', 'categories',
    'sales_payments', 'purchase_payments', 'attendances', 'online_orders',
    'website_settings', 'website_banners', 'featured_products', 'website_content',
    'online_order_items', 'company_settings', 'payment_methods'
  ];
begin
  foreach v_table in array v_tables
  loop
    begin
      execute format('select count(*) from %I where tenant_id is null', v_table) into v_count;
      if v_count > 0 then
        raise notice '❌ Table % has % rows with NULL tenant_id', v_table, v_count;
      else
        raise notice '✅ Table % - all rows have tenant_id', v_table;
      end if;
    exception
      when undefined_table then
        raise notice '⚠️  Table % does not exist', v_table;
      when undefined_column then
        raise notice '❌ Table % missing tenant_id column', v_table;
    end;
  end loop;
end $$;

-- 5. Verify RLS is enabled on all tenant tables (SHOULD ALL BE 'enabled')
select 
  case 
    when relrowsecurity then '✅ RLS ENABLED'
    else '❌ RLS DISABLED'
  end as status,
  schemaname,
  tablename
from pg_tables t
join pg_class c on c.relname = t.tablename
where schemaname = 'public'
  and tablename in (
    'products', 'customers', 'suppliers', 'sales_invoices', 'purchase_invoices',
    'accounts', 'journal_entries', 'journal_lines', 'employees', 'departments',
    'orders', 'order_items', 'stock_movements', 'product_brands', 'categories',
    'sales_payments', 'purchase_payments', 'attendances', 'online_orders',
    'website_settings', 'website_banners', 'featured_products', 'website_content',
    'online_order_items', 'company_settings', 'payment_methods', 'tenants', 'user_activity_log'
  )
order by 
  case when relrowsecurity then 0 else 1 end,
  tablename;

-- 6. Check user tenant assignments
select 
  '📋 USER TENANT ASSIGNMENTS' as status,
  u.email,
  u.raw_app_meta_data->>'tenant_id' as tenant_id,
  u.raw_app_meta_data->>'role' as role,
  t.shop_name,
  t.owner_email
from auth.users u
left join tenants t on t.id::text = u.raw_app_meta_data->>'tenant_id'
where u.email in ('nico.catalan7@gmail.com', 'ccatalansandoval7@gmail.com')
order by u.email;

-- 7. Verify user_tenant_id() function exists and works
select 
  '✅ user_tenant_id() FUNCTION' as status,
  proname as function_name,
  pg_get_function_result(oid) as return_type
from pg_proc
where proname = 'user_tenant_id'
  and pronamespace = 'public'::regnamespace;

-- 8. Test tenant isolation by checking product visibility per tenant
select 
  '📊 PRODUCTS PER TENANT' as status,
  t.shop_name,
  t.id as tenant_id,
  count(p.id) as product_count
from tenants t
left join products p on p.tenant_id = t.id
group by t.id, t.shop_name
order by t.created_at;

-- 9. Check for any tables with old "Authenticated *" policies still present
select 
  '⚠️  CHECK POLICY DEFINITIONS' as status,
  tablename,
  policyname,
  case 
    when qual like '%auth.role()%authenticated%' and qual not like '%tenant_id%' then '❌ NO TENANT FILTER'
    when qual like '%user_tenant_id()%' or with_check like '%user_tenant_id()%' then '✅ TENANT FILTERED'
    else '⚠️  REVIEW NEEDED'
  end as policy_status,
  cmd,
  substring(qual, 1, 100) as condition_preview
from pg_policies
where schemaname = 'public'
  and tablename in (
    'products', 'customers', 'suppliers', 'sales_invoices', 'purchase_invoices',
    'journal_entries', 'journal_lines', 'orders', 'order_items'
  )
order by 
  case 
    when qual like '%auth.role()%authenticated%' and qual not like '%tenant_id%' then 0
    else 1
  end,
  tablename, 
  policyname;

-- ============================================================================
-- EXPECTED RESULTS:
-- ============================================================================
-- Query 1: Should return 0 rows (no old policies)
-- Query 2: Should return many rows (new tenant policies exist)
-- Query 3: Should return 0 rows (all tables have tenant_id)
-- Query 4: Should show all tables have tenant_id with no NULLs
-- Query 5: Should show all tables have RLS enabled
-- Query 6: Should show both users with their tenant assignments
-- Query 7: Should show user_tenant_id() function exists
-- Query 8: Should show products grouped by tenant
-- Query 9: Should show all policies are tenant-filtered (no "NO TENANT FILTER")
-- ============================================================================
