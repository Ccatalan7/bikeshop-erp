-- DEBUG SCRIPT FOR EXPENSE JOURNAL ENTRIES
-- Run this after creating an expense to see what's happening

-- 1. Check the most recent expense
SELECT 
  id,
  expense_number,
  posting_status,
  payment_status,
  total_amount,
  created_at
FROM expenses
ORDER BY created_at DESC
LIMIT 1;

-- 2. Check if expense_lines exist for this expense
SELECT 
  el.id,
  el.expense_id,
  el.account_id,
  el.account_code,
  el.account_name,
  el.subtotal,
  el.tax_amount,
  el.total
FROM expense_lines el
WHERE el.expense_id = (SELECT id FROM expenses ORDER BY created_at DESC LIMIT 1);

-- 3. Check if journal_entry was created
SELECT 
  je.id,
  je.entry_number,
  je.entry_date,
  je.description,
  je.source_module,
  je.source_reference,
  je.status,
  je.total_debit,
  je.total_credit
FROM journal_entries je
WHERE je.source_module = 'expenses'
  AND je.source_reference = (SELECT id::text FROM expenses ORDER BY created_at DESC LIMIT 1);

-- 4. Check journal_lines if entry exists
SELECT 
  jl.id,
  jl.entry_id,
  jl.account_code,
  jl.account_name,
  jl.description,
  jl.debit_amount,
  jl.credit_amount
FROM journal_lines jl
WHERE jl.entry_id IN (
  SELECT je.id 
  FROM journal_entries je
  WHERE je.source_module = 'expenses'
    AND je.source_reference = (SELECT id::text FROM expenses ORDER BY created_at DESC LIMIT 1)
);

-- 5. Test the function directly
DO $$
DECLARE
  v_expense_id uuid;
BEGIN
  SELECT id INTO v_expense_id FROM expenses ORDER BY created_at DESC LIMIT 1;
  RAISE NOTICE 'Testing create_expense_journal_entry for expense: %', v_expense_id;
  PERFORM public.create_expense_journal_entry(v_expense_id);
  RAISE NOTICE 'Function executed successfully';
END $$;

-- 6. Check again after manual call
SELECT 
  je.id,
  je.entry_number,
  je.entry_date,
  je.description,
  je.source_module,
  je.status
FROM journal_entries je
WHERE je.source_module = 'expenses'
ORDER BY je.created_at DESC
LIMIT 5;
