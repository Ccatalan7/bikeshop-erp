-- VERIFY: Check if accounts table in DATABASE has tenant_id
-- This checks the ACTUAL deployed database, not the schema file

-- 1. Check accounts table structure in database
select 
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'accounts'
order by ordinal_position;

-- 2. Check if accounts has tenant_id FK constraint
select
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name as foreign_table_name,
  ccu.column_name as foreign_column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
  and tc.table_schema = kcu.table_schema
left join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
  and ccu.table_schema = tc.table_schema
where tc.table_schema = 'public'
  and tc.table_name = 'accounts'
order by tc.constraint_type, tc.constraint_name;

-- 3. Check unique constraint on accounts (code vs tenant_id+code)
select
  tc.constraint_name,
  string_agg(kcu.column_name, ', ' order by kcu.ordinal_position) as columns
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
where tc.table_schema = 'public'
  and tc.table_name = 'accounts'
  and tc.constraint_type = 'UNIQUE'
group by tc.constraint_name;

-- 4. Check RLS policies on accounts
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'accounts'
order by policyname;

-- 5. Sample data check - see if accounts have tenant_id values
select 
  id,
  tenant_id,
  code,
  name,
  type
from accounts
limit 10;
