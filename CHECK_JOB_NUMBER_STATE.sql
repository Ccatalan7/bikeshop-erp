-- Quick diagnostic: Check current state of mechanic_jobs table
-- Run this FIRST to see what's broken

-- 1. Check for duplicate job_numbers
select 
  job_number,
  count(*) as count,
  array_agg(id::text) as job_ids
from mechanic_jobs
group by job_number
having count(*) > 1
order by job_number;
-- ☝️ If this returns rows, you have duplicates

-- 2. Check for NULL or empty job_numbers
select 
  id,
  job_number,
  status,
  created_at
from mechanic_jobs
where job_number is null or job_number = ''
order by created_at desc;
-- ☝️ If this returns rows, these jobs have no number

-- 3. Show all job_numbers to see the pattern
select 
  id,
  job_number,
  customer_id,
  bike_id,
  status,
  created_at
from mechanic_jobs
order by created_at desc
limit 20;
-- ☝️ Look for patterns: are numbers sequential? any gaps?

-- 4. Check if trigger exists and is enabled
select 
  t.tgname as trigger_name,
  t.tgrelid::regclass as table_name,
  case t.tgenabled
    when 'O' then 'Enabled'
    when 'D' then 'Disabled'
    when 'R' then 'Replica Only'
    when 'A' then 'Always'
    else 'Unknown'
  end as status
from pg_trigger t
where t.tgrelid = 'mechanic_jobs'::regclass
  and t.tgname like '%job%'
order by t.tgname;
-- ☝️ Should show trigger enabled

-- 5. Check if sequence exists (should NOT exist yet - we'll create it)
select 
  sequencename,
  last_value,
  increment_by
from pg_sequences
where sequencename like '%job%';
-- ☝️ Should return empty or show old sequence if any
