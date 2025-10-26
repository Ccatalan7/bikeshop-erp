-- ============================================================================
-- DEBUG: Why does summary show 29 dangerous but detail shows 0?
-- ============================================================================
-- Let's investigate the exact query used in TEST 12 vs our diagnostic query
-- ============================================================================

-- Query 1: Exact replica of TEST 12 dangerous_policies count
select
  'TEST 12 REPLICA - DANGEROUS POLICIES' as test_name,
  count(*) as dangerous_policies_count
from pg_policies
where schemaname = 'public'
  and (
    qual like '%true%'
    or qual is null
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
  );

-- Query 2: Show ALL policies that match the TEST 12 criteria
select
  'ALL POLICIES MATCHING TEST 12 CRITERIA' as report,
  tablename,
  policyname,
  cmd,
  case
    when qual like '%true%' then 'CONTAINS: true'
    when qual is null then 'NULL QUAL'
    when qual like '%auth.uid()%' and qual not like '%tenant_id%' then 'auth.uid() without tenant_id'
    else 'OTHER'
  end as match_reason,
  case
    when qual like '%tenant_id%' then 'HAS tenant_id IN QUAL'
    else 'NO tenant_id in qual'
  end as tenant_check,
  left(qual, 200) as policy_qual
from pg_policies
where schemaname = 'public'
  and (
    qual like '%true%'
    or qual is null
    or (qual like '%auth.uid()%' and qual not like '%tenant_id%')
  )
order by tablename, policyname;

-- Query 3: Count policies by qual pattern
select
  'POLICY PATTERN ANALYSIS' as report,
  count(*) filter (where qual like '%true%') as contains_true,
  count(*) filter (where qual is null) as null_qual,
  count(*) filter (where qual like '%auth.uid()%' and qual not like '%tenant_id%') as auth_uid_no_tenant,
  count(*) filter (where qual like '%user_tenant_id%') as has_user_tenant_id,
  count(*) as total_policies
from pg_policies
where schemaname = 'public';

-- Query 4: Show policies with "true" in them (might be check constraints, not filters)
select
  'POLICIES CONTAINING TRUE' as report,
  tablename,
  policyname,
  cmd,
  permissive,
  left(qual, 200) as qual_preview,
  left(with_check, 200) as with_check_preview
from pg_policies
where schemaname = 'public'
  and qual like '%true%'
order by tablename, policyname;

-- Query 5: Show policies with NULL qual
select
  'POLICIES WITH NULL QUAL' as report,
  tablename,
  policyname,
  cmd,
  permissive,
  with_check as with_check_value
from pg_policies
where schemaname = 'public'
  and qual is null
order by tablename, policyname;
