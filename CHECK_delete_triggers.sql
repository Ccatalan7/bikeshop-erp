-- Check ALL triggers on sales_invoices that might interfere with deletion
SELECT 
    t.tgname as trigger_name,
    CASE t.tgtype::integer & 1 
        WHEN 1 THEN 'ROW' 
        ELSE 'STATEMENT' 
    END as level,
    CASE t.tgtype::integer & 66
        WHEN 2 THEN 'BEFORE'
        WHEN 64 THEN 'INSTEAD OF'
        ELSE 'AFTER'
    END as timing,
    CASE t.tgtype::integer & 28
        WHEN 4 THEN 'INSERT'
        WHEN 8 THEN 'DELETE'
        WHEN 16 THEN 'UPDATE'
        ELSE 'OTHER'
    END as event,
    p.proname as function_name,
    t.tgenabled as enabled
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE t.tgrelid = 'sales_invoices'::regclass
  AND NOT t.tgisinternal
  AND t.tgtype::integer & 8 = 8  -- Only DELETE triggers
ORDER BY 
    CASE t.tgtype::integer & 66
        WHEN 2 THEN 1 
        WHEN 64 THEN 2 
        ELSE 3 
    END,
    t.tgname;
