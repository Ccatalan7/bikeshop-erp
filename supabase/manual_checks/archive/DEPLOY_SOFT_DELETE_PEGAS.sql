-- DEPLOY: Add Soft Delete to Mechanic Jobs
-- Copy-paste this into Supabase SQL Editor (don't run full core_schema.sql!)

-- Add soft delete columns to mechanic_jobs
alter table mechanic_jobs add column if not exists deleted_at timestamp with time zone;
alter table mechanic_jobs add column if not exists deleted_by uuid references auth.users(id) on delete set null;

-- Create index for efficient soft-delete queries
create index if not exists idx_mechanic_jobs_deleted_at on mechanic_jobs(deleted_at) where deleted_at is not null;

-- Verify deployment
select 
  column_name, 
  data_type, 
  is_nullable
from information_schema.columns 
where table_name = 'mechanic_jobs' 
  and column_name in ('deleted_at', 'deleted_by')
order by column_name;

-- Expected output:
-- deleted_at   | timestamp with time zone | YES
-- deleted_by   | uuid                     | YES

-- ✅ After running this, restart your Flutter app
