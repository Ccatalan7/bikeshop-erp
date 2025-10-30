-- Fix user_invitations role check constraint to include 'admin'
-- The job_roles table allows admin, so invitations must too

-- Step 1: Drop old constraint
alter table user_invitations drop constraint if exists user_invitations_role_check;

-- Step 2: Add new constraint with 'admin' included
alter table user_invitations add constraint user_invitations_role_check
  check (role in ('admin', 'manager', 'cashier', 'mechanic', 'accountant'));

-- Step 3: Verify the change
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'user_invitations'::regclass
  and contype = 'c'
  and conname = 'user_invitations_role_check';
