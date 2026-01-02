-- AGGRESSIVE CLEANUP SCRIPT: Delete all Payroll Data (Vouchers, Expenses, JEs)
-- Usage: Run this to wipe the slate clean.

SET session_replication_role = 'replica';

DO $$
DECLARE
    v_rows INT;
BEGIN
    RAISE NOTICE 'Starting Aggressive Cleanup...';

    -- 1. Identify and Delete Journal Lines & Entries
    -- Strategy: Find Entries linked to Payroll Expenses or Manual Payroll Entries
    CREATE TEMP TABLE temp_entries_to_nuke AS
    SELECT id FROM journal_entries
    WHERE 
       -- Case A: Linked to an Expense that looks like Payroll
       (source_module = 'expenses' AND source_reference IN (
           SELECT expense_number FROM expenses 
           WHERE notes LIKE 'Pago de salario%' OR reference LIKE 'Semana %'
       ))
       OR
       -- Case B: Manual Legacy Entries
       (notes LIKE 'Payroll Expense%')
       OR
       -- Case C: Orphaned Native Entries (Expense deleted but Entry remains)
       (description LIKE 'Gasto GTO-% - Proveedor' AND NOT EXISTS (
           SELECT 1 FROM expenses WHERE expense_number = source_reference
       ));

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Found % Journal Entries to delete', v_rows;
    
    DELETE FROM journal_lines WHERE entry_id IN (SELECT id FROM temp_entries_to_nuke);
    DELETE FROM journal_entries WHERE id IN (SELECT id FROM temp_entries_to_nuke);

    -- 2. Identify and Delete Expenses & Lines
    CREATE TEMP TABLE temp_expenses_to_nuke AS
    SELECT id FROM expenses
    WHERE notes LIKE 'Pago de salario%' 
       OR reference LIKE 'Semana %';

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE NOTICE 'Found % Expenses to delete', v_rows;

    DELETE FROM expense_lines WHERE expense_id IN (SELECT id FROM temp_expenses_to_nuke);
    DELETE FROM expenses WHERE id IN (SELECT id FROM temp_expenses_to_nuke);

    -- 3. Delete Vouchers
    DELETE FROM payroll_voucher_lines
    WHERE voucher_id IN (SELECT id FROM payroll_vouchers WHERE status = 'paid');

    DELETE FROM payroll_vouchers
    WHERE status = 'paid';
    
    DROP TABLE temp_entries_to_nuke;
    DROP TABLE temp_expenses_to_nuke;
    
    RAISE NOTICE 'Cleanup complete.';
END;
$$;

SET session_replication_role = 'origin';
