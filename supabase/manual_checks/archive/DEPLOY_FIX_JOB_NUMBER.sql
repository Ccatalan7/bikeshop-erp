-- ============================================================
-- FIX: Mechanic Job Number Generation (Duplicate Key Error)
-- ============================================================
-- Problem: generate_mechanic_job_number() uses COUNT(*) which 
--          creates race conditions and duplicates
-- Solution: Use PostgreSQL sequence (thread-safe, guaranteed unique)
-- Deploy: Copy entire script to Supabase SQL Editor and run
-- ============================================================

-- Step 1: Create dedicated sequence for job numbers
drop sequence if exists public.mechanic_job_number_seq cascade;
create sequence public.mechanic_job_number_seq
  start with 1
  increment by 1
  no cycle;

-- Step 2: Initialize sequence from existing data
do $$
declare
  v_max_number integer;
begin
  -- Extract highest number from existing PG-XXXXX format
  select coalesce(max(
    case 
      when job_number ~ '^PG-[0-9]+$' 
      then substring(job_number from 4)::integer
      else 0
    end
  ), 0) into v_max_number
  from mechanic_jobs;
  
  -- Set sequence to start AFTER highest existing number
  perform setval('public.mechanic_job_number_seq', v_max_number);
  
  raise notice '✅ Sequence initialized to start at: PG-%', lpad((v_max_number + 1)::text, 5, '0');
end $$;

-- Step 3: Replace function to use sequence (NO MORE RACE CONDITIONS!)
create or replace function public.generate_mechanic_job_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next_number integer;
  v_job_number text;
begin
  -- Get next value from sequence (guaranteed unique)
  v_next_number := nextval('public.mechanic_job_number_seq');
  
  -- Format as PG-00001, PG-00002, etc.
  v_job_number := 'PG-' || lpad(v_next_number::text, 5, '0');
  
  return v_job_number;
end;
$$;

-- Step 4: Fix any existing NULL/empty/duplicate job_numbers
with duplicates as (
  select 
    id,
    job_number,
    row_number() over (partition by job_number order by created_at) as rn
  from mechanic_jobs
  where job_number is not null and job_number != ''
)
update mechanic_jobs m
set job_number = public.generate_mechanic_job_number()
from duplicates d
where m.id = d.id and d.rn > 1;

-- Fix NULL/empty job_numbers
update mechanic_jobs
set job_number = public.generate_mechanic_job_number()
where job_number is null or job_number = '';

-- ============================================================
-- VERIFICATION QUERIES (check results after running above)
-- ============================================================

-- Check for duplicates (should return 0 rows)
select 
  job_number,
  count(*) as duplicate_count
from mechanic_jobs
group by job_number
having count(*) > 1
order by job_number;

-- Show recent jobs with their numbers
select 
  id,
  job_number,
  status,
  created_at
from mechanic_jobs
order by created_at desc
limit 10;

-- Test the generator (should return next sequential number)
select public.generate_mechanic_job_number() as next_job_number;

-- ============================================================
-- ✅ DEPLOYMENT COMPLETE
-- Now restart your Flutter app and try creating a pega again
-- ============================================================
