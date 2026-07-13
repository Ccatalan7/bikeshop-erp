-- FIX: Ensure tasks CASCADE delete when parent item deleted
-- The FK constraint says CASCADE but it's not working properly

-- Step 1: Drop existing constraint
ALTER TABLE mechanic_job_tasks 
DROP CONSTRAINT IF EXISTS mechanic_job_tasks_parent_item_id_fkey CASCADE;

-- Step 2: Re-add with explicit CASCADE
ALTER TABLE mechanic_job_tasks
ADD CONSTRAINT mechanic_job_tasks_parent_item_id_fkey
FOREIGN KEY (parent_item_id)
REFERENCES mechanic_job_items(id)
ON DELETE CASCADE;

-- Step 3: Verify
SELECT 
    tc.table_name, 
    kcu.column_name, 
    ccu.table_name AS foreign_table_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.table_name = 'mechanic_job_tasks' 
  AND kcu.column_name = 'parent_item_id';

-- ✅ Should show delete_rule = 'CASCADE'
