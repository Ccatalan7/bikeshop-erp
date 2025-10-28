-- COMPREHENSIVE CHECK: Find ALL tables missing tenant_id column
-- This checks every table in public schema (excluding system tables)

select 
  t.table_name,
  case 
    when c.column_name is not null then '✅ HAS tenant_id'
    else '❌ MISSING tenant_id'
  end as tenant_isolation_status,
  case 
    when t.table_name in ('tenants', 'reserved_subdomains', 'user_activity_log') then '⚠️ Exception (system table)'
    when c.column_name is null then '🚨 CRITICAL: Needs tenant_id!'
    else '✓ OK'
  end as verdict
from information_schema.tables t
left join information_schema.columns c 
  on c.table_schema = t.table_schema 
  and c.table_name = t.table_name 
  and c.column_name = 'tenant_id'
where t.table_schema = 'public'
  and t.table_type = 'BASE TABLE'
  and t.table_name not like 'pg_%'
  and t.table_name not in (
    'tenants',              -- Root tenant table
    'reserved_subdomains',  -- Global system table
    'migrations',           -- System table
    'schema_migrations'     -- System table
  )
order by 
  case when c.column_name is null then 0 else 1 end,
  t.table_name;

-- Detailed check: Show tables with tenant_id but missing proper constraints
select 
  t.table_name,
  c.column_name,
  c.is_nullable,
  case 
    when fk.constraint_name is not null then '✅ Has FK to tenants'
    else '❌ Missing FK constraint'
  end as fk_status,
  case 
    when idx.indexname is not null then '✅ Has index'
    else '⚠️ Missing index (performance issue)'
  end as index_status
from information_schema.tables t
join information_schema.columns c 
  on c.table_schema = t.table_schema 
  and c.table_name = t.table_name 
  and c.column_name = 'tenant_id'
left join information_schema.key_column_usage kcu
  on kcu.table_schema = t.table_schema
  and kcu.table_name = t.table_name
  and kcu.column_name = 'tenant_id'
left join information_schema.referential_constraints rc
  on rc.constraint_schema = kcu.constraint_schema
  and rc.constraint_name = kcu.constraint_name
left join information_schema.constraint_column_usage ccu
  on ccu.constraint_schema = rc.unique_constraint_schema
  and ccu.constraint_name = rc.unique_constraint_name
left join information_schema.table_constraints fk
  on fk.constraint_schema = kcu.constraint_schema
  and fk.constraint_name = kcu.constraint_name
  and fk.constraint_type = 'FOREIGN KEY'
left join pg_indexes idx
  on idx.schemaname = t.table_schema
  and idx.tablename = t.table_name
  and idx.indexdef like '%tenant_id%'
where t.table_schema = 'public'
  and t.table_type = 'BASE TABLE'
order by t.table_name;

-- RLS Policy Check: Tables with tenant_id but NO RLS policies
select 
  t.table_name,
  case 
    when pc.tablename is not null then '✅ RLS enabled'
    else '❌ RLS NOT enabled'
  end as rls_status,
  coalesce(policy_count.count, 0) as policy_count,
  case 
    when coalesce(policy_count.count, 0) = 0 then '🚨 NO RLS POLICIES (data leak risk!)'
    when coalesce(policy_count.count, 0) < 4 then '⚠️ Incomplete policies (should have SELECT/INSERT/UPDATE/DELETE)'
    else '✓ OK'
  end as policy_verdict
from information_schema.tables t
join information_schema.columns c 
  on c.table_schema = t.table_schema 
  and c.table_name = t.table_name 
  and c.column_name = 'tenant_id'
left join pg_tables pc
  on pc.schemaname = t.table_schema
  and pc.tablename = t.table_name
  and pc.rowsecurity = true
left join (
  select 
    schemaname,
    tablename,
    count(*) as count
  from pg_policies
  group by schemaname, tablename
) policy_count
  on policy_count.schemaname = t.table_schema
  and policy_count.tablename = t.table_name
where t.table_schema = 'public'
  and t.table_type = 'BASE TABLE'
order by 
  case when pc.tablename is null then 0 else 1 end,
  coalesce(policy_count.count, 0),
  t.table_name;
