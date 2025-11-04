-- ============================================================
-- FIX: Change FK constraint back to SET NULL, let trigger handle cascade
-- The ON DELETE CASCADE FK was interfering with the trigger
-- ============================================================

-- First, change the foreign key constraint back to SET NULL
alter table mechanic_jobs 
  drop constraint if exists mechanic_jobs_invoice_id_fkey;

alter table mechanic_jobs 
  add constraint mechanic_jobs_invoice_id_fkey
  foreign key (invoice_id) 
  references sales_invoices(id) 
  on delete set null;  -- ← Changed from CASCADE to SET NULL

-- Now the trigger will handle the actual cascade delete
-- (No changes needed to the trigger - it's already deployed)

-- Verify the constraint was updated
select 
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu 
  on tc.constraint_name = kcu.constraint_name
join information_schema.referential_constraints rc
  on tc.constraint_name = rc.constraint_name
where tc.table_name = 'mechanic_jobs'
  and kcu.column_name = 'invoice_id';
