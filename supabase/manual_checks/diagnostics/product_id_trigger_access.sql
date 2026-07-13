-- Find all function definitions that access NEW.product_id
-- Then check which triggers call those functions

-- Step 1: Find functions that reference NEW.product_id
SELECT 
  routine_name,
  routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
  AND (routine_definition ILIKE '%NEW.product_id%' OR routine_definition ILIKE '%new.product_id%')
ORDER BY routine_name;
