-- 1. Check Live Function Definitions (Queries 2 & 3 combined for ease)
SELECT 
    p.proname AS function_name,
    pg_get_functiondef(p.oid) AS live_function_code
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
AND p.proname IN (
    'consume_purchase_invoice_inventory',
    'recalculate_purchase_invoice_payments'
);

-- Note: Also testing if `trg_set_purchase_context` is missing, we'll recreate it if so.
