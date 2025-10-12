-- ============================================================================
-- Current State: What exists in the database right now?
-- ============================================================================

-- 1. Count everything
SELECT 'Sales Invoices' as table_name, COUNT(*) as count FROM sales_invoices
UNION ALL
SELECT 'Sales Payments' as table_name, COUNT(*) as count FROM sales_payments
UNION ALL
SELECT 'Journal Entries (All)' as table_name, COUNT(*) as count FROM journal_entries
UNION ALL
SELECT 'Journal Entries (Invoice)' as table_name, COUNT(*) as count FROM journal_entries WHERE source_module = 'sales_invoices'
UNION ALL
SELECT 'Journal Entries (Payment)' as table_name, COUNT(*) as count FROM journal_entries WHERE source_module = 'sales_payments'
UNION ALL
SELECT 'Journal Lines' as table_name, COUNT(*) as count FROM journal_lines;

-- 2. Show all journal entries with details
SELECT 
  je.id,
  je.entry_number,
  je.date,
  je.description,
  je.source_module,
  je.type,
  je.status,
  je.total_debit,
  je.total_credit,
  je.created_at,
  (SELECT COUNT(*) FROM journal_lines jl WHERE jl.entry_id = je.id) as line_count
FROM journal_entries je
ORDER BY je.created_at DESC;

-- 3. Show all invoices with their payment status
SELECT 
  si.id,
  si.invoice_number,
  si.customer_name,
  si.status,
  si.total,
  si.paid_amount,
  si.balance,
  si.date,
  si.updated_at,
  (SELECT COUNT(*) FROM sales_payments sp WHERE sp.invoice_id = si.id) as payment_count
FROM sales_invoices si
ORDER BY si.updated_at DESC;
