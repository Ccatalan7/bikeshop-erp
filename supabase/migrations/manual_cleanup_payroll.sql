SET session_replication_role = 'replica';

DO $$
DECLARE
    v_rows INT;
BEGIN
    RAISE NOTICE 'Starting Aggressive Cleanup...';

    -- 1. DELETE JOURNAL ENTRIES (Linked to Payroll Expenses)
    -- Deletes lines first
    DELETE FROM journal_lines 
    WHERE entry_id IN (
        SELECT id FROM journal_entries 
        WHERE (source_module = 'expenses' AND source_reference IN (
             SELECT expense_number FROM expenses 
             WHERE notes LIKE 'Pago de salario%' OR reference LIKE 'Semana %'
          ))
          OR (notes LIKE 'Payroll Expense%')
          OR (description LIKE 'Gasto GTO-% - Proveedor' AND NOT EXISTS (
               SELECT 1 FROM expenses WHERE expense_number = source_reference
          ))
    );
    
    -- Deletes entries
    DELETE FROM journal_entries 
    WHERE (source_module = 'expenses' AND source_reference IN (
             SELECT expense_number FROM expenses 
             WHERE notes LIKE 'Pago de salario%' OR reference LIKE 'Semana %'
          ))
          OR (notes LIKE 'Payroll Expense%')
          OR (description LIKE 'Gasto GTO-% - Proveedor' AND NOT EXISTS (
               SELECT 1 FROM expenses WHERE expense_number = source_reference
          ));

    -- 2. DELETE EXPENSES (Payroll related)
    -- Deletes lines first
    DELETE FROM expense_lines 
    WHERE expense_id IN (
        SELECT id FROM expenses 
        WHERE notes LIKE 'Pago de salario%' OR reference LIKE 'Semana %'
    );

    -- Deletes expenses
    DELETE FROM expenses 
    WHERE notes LIKE 'Pago de salario%' OR reference LIKE 'Semana %';

    -- 3. DELETE VOUCHERS (Paid ones)
    DELETE FROM payroll_voucher_lines
    WHERE voucher_id IN (SELECT id FROM payroll_vouchers WHERE status = 'paid');

    DELETE FROM payroll_vouchers
    WHERE status = 'paid';
    
    RAISE NOTICE 'Cleanup complete.';
END $$;

SET session_replication_role = 'origin';
