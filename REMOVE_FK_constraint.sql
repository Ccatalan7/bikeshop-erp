-- ============================================================
-- REMOVE FK CONSTRAINT - Let trigger handle everything
-- The FK was running before the trigger and breaking the link
-- ============================================================

-- Drop the foreign key constraint completely
alter table mechanic_jobs 
  drop constraint if exists mechanic_jobs_invoice_id_fkey;

-- Verify constraint was removed
select 
  tc.constraint_name,
  tc.table_name,
  kcu.column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu 
  on tc.constraint_name = kcu.constraint_name
where tc.table_name = 'mechanic_jobs'
  and kcu.column_name = 'invoice_id'
  and tc.constraint_type = 'FOREIGN KEY';

-- Should return no rows if FK was removed successfully
