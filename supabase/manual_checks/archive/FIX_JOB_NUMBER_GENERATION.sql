-- Fix job_number generation to use proper sequence (prevents duplicates)
-- Deploy this to Supabase SQL Editor

-- Step 1: Create a dedicated sequence for job numbers
drop sequence if exists public.mechanic_job_number_seq cascade;
create sequence public.mechanic_job_number_seq
  start with 1
  increment by 1
  no cycle;

-- Step 2: Set the sequence to start AFTER existing job numbers
do $$
declare
  v_max_number integer;
begin
  -- Extract the highest existing number from PG-XXXXX format
  select coalesce(max(
    case 
      when job_number ~ '^PG-[0-9]+$' 
      then substring(job_number from 4)::integer
      else 0
    end
  ), 0) into v_max_number
  from mechanic_jobs;
  
  -- Set sequence to start after the highest existing number
  perform setval('public.mechanic_job_number_seq', v_max_number);
  
  raise notice 'Sequence initialized to start at: %', v_max_number + 1;
end $$;

-- Step 3: Replace the generation function to use the sequence
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

-- Step 4: Clean up any NULL or empty job_numbers in existing records
-- (This will trigger the auto-generation for those records)
update mechanic_jobs
set job_number = public.generate_mechanic_job_number()
where job_number is null or job_number = '';

-- Step 5: Verify the fix
select 
  job_number,
  count(*) as count
from mechanic_jobs
group by job_number
having count(*) > 1
order by job_number;
-- ☝️ Should return 0 rows (no duplicates)

select 
  id,
  job_number,
  status,
  created_at
from mechanic_jobs
order by created_at desc
limit 10;
-- ☝️ Should show properly formatted job numbers

-- Step 6: Test the generation
select public.generate_mechanic_job_number() as test_job_number;
-- ☝️ Should return next sequential number like "PG-00042"
