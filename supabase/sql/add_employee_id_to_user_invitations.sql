-- Add employee_id and metadata columns to user_invitations table
-- This links user invitations to employee records for the HR module

-- Step 1: Add employee_id column (nullable for existing invitations)
alter table user_invitations 
  add column if not exists employee_id uuid references employees(id) on delete set null;

-- Step 2: Add metadata column for storing additional invitation context
alter table user_invitations 
  add column if not exists metadata jsonb;

-- Step 3: Create index for employee lookups
create index if not exists idx_user_invitations_employee_id on user_invitations(employee_id);

-- Step 4: Verify the changes
select column_name, data_type, is_nullable
from information_schema.columns
where table_name = 'user_invitations'
  and column_name in ('employee_id', 'metadata')
order by column_name;
