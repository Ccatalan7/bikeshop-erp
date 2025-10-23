-- ================================================
-- COMPREHENSIVE DEPLOYMENT CHECK
-- ================================================
-- Copy this ENTIRE file to Supabase SQL Editor and run it
-- It will show you exactly what's deployed and what's missing
-- ================================================

-- ===== CHECK 1: Triggers =====
SELECT 
  '1. TRIGGERS' as section,
  tgname as trigger_name,
  tgrelid::regclass::text as table_name,
  CASE tgenabled
    WHEN 'O' THEN '✅ Enabled'
    WHEN 'D' THEN '❌ Disabled'
    ELSE '⚠️ Unknown'
  END as status
FROM pg_trigger
WHERE tgname IN ('trg_expenses_change', 'trg_expense_lines_change', 'trg_expense_payments_change')
  AND tgisinternal = false
ORDER BY tgname;

-- ===== CHECK 2: Functions =====
SELECT 
  '2. FUNCTIONS' as section,
  proname as function_name,
  pg_get_function_identity_arguments(oid) as arguments,
  '✅ Exists' as status
FROM pg_proc
WHERE proname IN (
  'process_expense_change',
  'handle_expense_line_change',
  'handle_expense_payment_change',
  'create_expense_journal_entry',
  'delete_expense_journal_entry',
  'recalculate_expense_totals'
)
ORDER BY proname;

-- ===== CHECK 3: journal_entries Columns =====
SELECT 
  '3. JOURNAL_ENTRIES SCHEMA' as section,
  column_name,
  data_type,
  CASE 
    WHEN column_name = 'entry_date' THEN '✅ New column (correct)'
    WHEN column_name = 'date' THEN '❌ Old column (needs migration!)'
    ELSE '✓ OK'
  END as status
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'journal_entries'
ORDER BY ordinal_position;

-- ===== CHECK 4: expense_lines Trigger Definition =====
SELECT 
  '4. EXPENSE_LINES TRIGGER SOURCE' as section,
  CASE 
    WHEN pg_get_triggerdef(oid) IS NOT NULL THEN '✅ Trigger defined'
    ELSE '❌ Trigger missing'
  END as status,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgname = 'trg_expense_lines_change'
  AND tgrelid = 'public.expense_lines'::regclass;

-- ===== CHECK 5: Recent Expenses Analysis =====
SELECT 
  '5. RECENT EXPENSES' as section,
  e.id,
  e.expense_number,
  e.posting_status,
  e.total_amount,
  e.created_at,
  (SELECT COUNT(*) FROM expense_lines WHERE expense_id = e.id) as line_count,
  (SELECT COUNT(*) FROM journal_entries WHERE source_module = 'expenses' AND source_reference = e.id::text) as journal_count,
  CASE 
    WHEN e.posting_status = 'posted' AND (SELECT COUNT(*) FROM expense_lines WHERE expense_id = e.id) = 0 
    THEN '⚠️ Posted but NO LINES'
    WHEN e.posting_status = 'posted' AND (SELECT COUNT(*) FROM journal_entries WHERE source_module = 'expenses' AND source_reference = e.id::text) = 0 
    THEN '❌ MISSING JOURNAL'
    WHEN e.posting_status = 'posted' AND (SELECT COUNT(*) FROM journal_entries WHERE source_module = 'expenses' AND source_reference = e.id::text) > 0 
    THEN '✅ Journal exists'
    ELSE '⏸️ Draft (OK)'
  END as status
FROM expenses e
ORDER BY e.created_at DESC
LIMIT 10;

-- ===== CHECK 6: Journal Entries by Module =====
SELECT 
  '6. JOURNAL ENTRIES BY SOURCE' as section,
  source_module,
  COUNT(*) as count,
  MIN(created_at) as oldest,
  MAX(created_at) as newest
FROM journal_entries
GROUP BY source_module
ORDER BY source_module;

-- ===== SUMMARY CHECK =====
SELECT 
  '7. DEPLOYMENT SUMMARY' as section,
  CASE 
    WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_lines_change')
         AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_expense_line_change')
         AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'entry_date')
         AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'date')
    THEN '✅ SCHEMA FULLY DEPLOYED'
    ELSE '❌ SCHEMA NOT DEPLOYED OR INCOMPLETE'
  END as deployment_status,
  CASE 
    WHEN NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_lines_change')
    THEN '❌ Missing: trg_expense_lines_change trigger'
    WHEN NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'handle_expense_line_change')
    THEN '❌ Missing: handle_expense_line_change function'
    WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'date')
    THEN '❌ Old column still exists: journal_entries.date'
    WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'journal_entries' AND column_name = 'entry_date')
    THEN '❌ New column missing: journal_entries.entry_date'
    ELSE '✓ All components present'
  END as details;

-- ================================================
-- EXPECTED RESULTS FOR SUCCESSFUL DEPLOYMENT:
-- ================================================
-- 1. TRIGGERS: Should show trg_expense_lines_change as ✅ Enabled
-- 2. FUNCTIONS: Should show handle_expense_line_change as ✅ Exists
-- 3. JOURNAL_ENTRIES SCHEMA: Should have entry_date (✅ New column), NOT date
-- 4. EXPENSE_LINES TRIGGER SOURCE: Should show ✅ Trigger defined
-- 5. RECENT EXPENSES: Posted expenses should have ✅ Journal exists
-- 6. JOURNAL ENTRIES: Should show expenses module with count > 0
-- 7. DEPLOYMENT SUMMARY: Should show ✅ SCHEMA FULLY DEPLOYED
-- ================================================
