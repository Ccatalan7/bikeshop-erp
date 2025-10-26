-- ============================================================================
-- FIND ALL 29 DANGEROUS POLICIES (including non-tenant tables)
-- ============================================================================
-- This query shows ALL policies without tenant filtering, including system tables
-- ============================================================================

select
  tablename,
  policyname,
  cmd as operation,
  case
    when not exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = pg_policies.tablename
        and c.column_name = 'tenant_id'
    ) then '⚠️  NO tenant_id COLUMN (system table?)'
    when qual like '%true%' then '🚨 PUBLIC ACCESS (using true)'
    when qual is null then '🚨 NO FILTER (null qual)'
    when qual like '%auth.uid()%' and qual not like '%tenant_id%' then '🚨 USER-ONLY FILTER (no tenant isolation)'
    when roles::text like '%anon%' and qual not like '%tenant_id%' then '🚨 ANONYMOUS ACCESS (no tenant filter)'
    else '🚨 OTHER: ' || left(qual, 50)
  end as issue_type,
  case
    when exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = pg_policies.tablename
        and c.column_name = 'tenant_id'
    ) then '✅ HAS tenant_id'
    else '❌ NO tenant_id'
  end as has_tenant_id,
  left(qual, 150) as policy_definition
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
order by
  case when exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = pg_policies.tablename
      and c.column_name = 'tenant_id'
  ) then 1 else 0 end,
  tablename,
  policyname;

-- ============================================================================
-- COUNT BY CATEGORY
-- ============================================================================

select
  'DANGEROUS POLICY SUMMARY' as report,
  count(*) filter (
    where exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = pg_policies.tablename
        and c.column_name = 'tenant_id'
    )
  ) as dangerous_on_tenant_tables,
  count(*) filter (
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = pg_policies.tablename
        and c.column_name = 'tenant_id'
    )
  ) as on_system_tables,
  count(*) as total_dangerous
from pg_policies
where schemaname = 'public'
  and not (qual like '%tenant_id%user_tenant_id%' or qual like '%user_tenant_id()%')
  and (
    qual like '%true%'
    or qual is null
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
    or (roles::text like '%anon%' and qual not like '%tenant_id%')
  );
