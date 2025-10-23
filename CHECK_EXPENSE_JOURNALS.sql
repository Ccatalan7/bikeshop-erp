-- Check existing journal entries
SELECT 
  je.id,
  je.entry_number,
  je.entry_date,
  je.description,
  je.source_module,
  je.source_reference,
  je.status,
  je.total_debit,
  je.total_credit,
  je.created_at
FROM journal_entries je
ORDER BY je.created_at DESC;

-- Check if any are from expenses
SELECT 
  je.entry_number,
  je.description,
  je.source_module,
  e.expense_number,
  e.posting_status,
  e.total_amount
FROM journal_entries je
LEFT JOIN expenses e ON e.id::text = je.source_reference
WHERE je.source_module = 'expenses'
ORDER BY je.created_at DESC;

-- Check recent expenses and their lines
SELECT 
  e.id,
  e.expense_number,
  e.posting_status,
  e.total_amount,
  COUNT(el.id) as line_count,
  e.created_at
FROM expenses e
LEFT JOIN expense_lines el ON el.expense_id = e.id
GROUP BY e.id, e.expense_number, e.posting_status, e.total_amount, e.created_at
ORDER BY e.created_at DESC
LIMIT 10;

-- Check if triggers exist
SELECT 
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  tgenabled as enabled
FROM pg_trigger
WHERE tgname IN ('trg_expenses_change', 'trg_expense_lines_change')
ORDER BY tgname;

-- Check if the expense_lines trigger exists
SELECT EXISTS (
  SELECT 1 
  FROM pg_trigger 
  WHERE tgname = 'trg_expense_lines_change'
    AND tgrelid = 'public.expense_lines'::regclass
) as expense_lines_trigger_exists;
