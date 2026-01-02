-- Fix: Link existing employees to their salary accounts
-- Run this script in Supabase SQL Editor to link existing employees
-- to their already-created salary accounts (6101-XX format)

DO $$
DECLARE
  emp RECORD;
  v_matching_account_id UUID;
BEGIN
  -- Loop through employees without a salary_account_id
  FOR emp IN 
    SELECT id, first_name, last_name, tenant_id 
    FROM employees 
    WHERE salary_account_id IS NULL
  LOOP
    -- Find matching account by name pattern
    SELECT id INTO v_matching_account_id
    FROM accounts
    WHERE tenant_id = emp.tenant_id
      AND code LIKE '6101%'
      AND (
        name ILIKE '%' || emp.first_name || '%'
        OR name ILIKE '%' || emp.last_name || '%'
        OR (name ILIKE '%' || emp.first_name || ' ' || emp.last_name || '%')
      )
    LIMIT 1;

    IF v_matching_account_id IS NOT NULL THEN
      UPDATE employees 
      SET salary_account_id = v_matching_account_id
      WHERE id = emp.id;
      
      RAISE NOTICE 'Linked employee % % to account %', 
        emp.first_name, emp.last_name, v_matching_account_id;
    ELSE
      RAISE NOTICE 'No matching account found for % %', 
        emp.first_name, emp.last_name;
    END IF;
  END LOOP;
END $$;

-- Verify the fix
SELECT e.first_name, e.last_name, e.salary_account_id, a.code, a.name
FROM employees e
LEFT JOIN accounts a ON e.salary_account_id = a.id
ORDER BY e.last_name;
