-- ============================================================================
-- IDENTIFY DANGEROUS POLICIES - Detailed Analysis
-- ============================================================================
-- This query will show EXACTLY which 29 policies are dangerous and why
-- Run this to see what needs to be fixed in core_schema.sql
-- ============================================================================

select
  tablename,
  policyname,
  cmd as operation,
  permissive,
  roles::text as roles,
  case
    when qual like '%true%' then '🚨 PUBLIC ACCESS (using true)'
    when qual is null then '🚨 NO FILTER (null qual)'
    when qual like '%auth.uid()%' and qual not like '%tenant_id%' then '🚨 USER-ONLY FILTER (no tenant isolation)'
    when roles::text like '%anon%' and qual not like '%tenant_id%' then '🚨 ANONYMOUS ACCESS (no tenant filter)'
    else '🚨 OTHER: ' || left(qual, 50)
  end as issue_type,
  qual as full_policy_definition,
  case
    when qual like '%true%' then 'Replace with tenant_id = user_tenant_id()'
    when qual is null then 'Add tenant_id = user_tenant_id() filter'
    when qual like '%auth.uid()%' and qual not like '%tenant_id%' then 'Add AND tenant_id = user_tenant_id()'
    when roles::text like '%anon%' and qual not like '%tenant_id%' then 'Either remove anon role OR add tenant context'
    else 'Review and add tenant filtering'
  end as recommended_fix
from pg_policies
where schemaname = 'public'
  -- Exclude policies that properly filter by tenant
  and not (qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%')
  -- Flag truly dangerous patterns
  and (
    qual like '%true%'
    or qual is null
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
    or (roles::text like '%anon%' and qual not like '%tenant_id%')
  )
order by tablename, policyname;

-- ============================================================================
-- Group dangerous policies by table
-- ============================================================================

select
  'DANGEROUS POLICIES BY TABLE' as report,
  tablename,
  count(*) as dangerous_policy_count,
  string_agg(policyname, ', ' order by policyname) as policy_names
from pg_policies
where schemaname = 'public'
  and not (qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%')
  and (
    qual like '%true%'
    or qual is null
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
    or (roles::text like '%anon%' and qual not like '%tenant_id%')
  )
group by tablename
order by count(*) desc, tablename;

-- ============================================================================
-- Show which tables need work
-- ============================================================================

select
  'TABLES NEEDING POLICY FIXES' as report,
  t.tablename,
  case when c.relrowsecurity then '✅ RLS ON' else '❌ RLS OFF' end as rls_status,
  coalesce(good.count, 0) as good_policies,
  coalesce(bad.count, 0) as bad_policies,
  case
    when coalesce(bad.count, 0) > 0 then '🚨 HAS DANGEROUS POLICIES'
    when coalesce(good.count, 0) = 0 then '⚠️  NO POLICIES AT ALL'
    else '✅ ALL POLICIES OK'
  end as status
from pg_tables t
join pg_class c on c.relname = t.tablename
left join (
  select tablename, count(*) as count
  from pg_policies
  where schemaname = 'public'
    and (qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%')
  group by tablename
) good on good.tablename = t.tablename
left join (
  select tablename, count(*) as count
  from pg_policies
  where schemaname = 'public'
    and not (qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%')
    and (
      qual like '%true%'
      or qual is null
      or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
      or (roles::text like '%anon%' and qual not like '%tenant_id%')
    )
  group by tablename
) bad on bad.tablename = t.tablename
where t.schemaname = 'public'
  and t.tablename not in ('schema_migrations', 'spatial_ref_sys')
  and exists (
    select 1 from information_schema.columns col
    where col.table_schema = 'public'
      and col.table_name = t.tablename
      and col.column_name = 'tenant_id'
  )
order by coalesce(bad.count, 0) desc, t.tablename;
