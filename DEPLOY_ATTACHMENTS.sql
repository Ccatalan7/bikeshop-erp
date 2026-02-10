-- ============================================================
-- ADD ATTACHMENT SUPPORT TO MECHANIC JOBS (PEGAS)
-- ============================================================
-- Deploy: Run this in Supabase SQL Editor
-- Date: February 10, 2026
-- 
-- This adds the image_urls column to the mechanic_jobs table
-- to support file attachments in the Pegas module.
-- ============================================================

-- Add image_urls column to mechanic_jobs table
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_jobs' and column_name = 'image_urls'
  ) then
    alter table mechanic_jobs 
      add column image_urls text[] not null default array[]::text[];
    raise notice '✅ Added image_urls column to mechanic_jobs';
  else
    raise notice 'ℹ️ image_urls column already exists in mechanic_jobs';
  end if;
end $$;

-- Add work_performed column if missing (legacy field used in form)
do $$
begin
  if not exists (
    select 1 from information_schema.columns 
    where table_name = 'mechanic_jobs' and column_name = 'work_performed'
  ) then
    alter table mechanic_jobs 
      add column work_performed text;
    raise notice '✅ Added work_performed column to mechanic_jobs';
  else
    raise notice 'ℹ️ work_performed column already exists in mechanic_jobs';
  end if;
end $$;

-- Verify deployment
do $$
begin
  raise notice '';
  raise notice '✅ Attachments support deployed successfully!';
  raise notice '   - mechanic_jobs.image_urls column added/verified';
end $$;
