-- ===== AUDIT QUERIES FOR ACCOUNTING EQUATION IMBALANCE =====
-- Run each query separately in Supabase SQL Editor

-- QUERY 0A: Check your current tenant_id
SELECT public.user_tenant_id() as my_tenant_id;

-- QUERY 0B: Check if journal_lines have a different tenant_id
SELECT DISTINCT jl.tenant_id, COUNT(*) as line_count
FROM journal_lines jl
GROUP BY jl.tenant_id;

-- QUERY 0C: Check if journal_entries exist
SELECT COUNT(*) as total_entries, 
       COUNT(*) FILTER (WHERE status = 'posted') as posted_entries
FROM journal_entries;

-- QUERY 0D: Check tenant_id on journal_entries vs journal_lines
SELECT 
  je.tenant_id as entry_tenant,
  jl.tenant_id as line_tenant,
  COUNT(*) as count
FROM journal_entries je
LEFT JOIN journal_lines jl ON je.id = jl.entry_id
GROUP BY je.tenant_id, jl.tenant_id;

-- QUERY 1: Check total debits vs total credits (should be equal)
-- Using je.tenant_id instead of jl.tenant_id
SELECT 
  'Total Posted' as description,
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  SUM(jl.debit_amount) - SUM(jl.credit_amount) as difference
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id();

-- QUERY 2: Find unbalanced journal entries (debits ≠ credits)
SELECT 
  je.entry_number,
  je.entry_date,
  je.description,
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  ABS(SUM(jl.debit_amount) - SUM(jl.credit_amount)) as difference
FROM journal_entries je
JOIN journal_lines jl ON je.id = jl.entry_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id()
GROUP BY je.id, je.entry_number, je.entry_date, je.description
HAVING ABS(SUM(jl.debit_amount) - SUM(jl.credit_amount)) > 0.01
ORDER BY difference DESC
LIMIT 20;

-- QUERY 3: Balances by account type
SELECT 
  a.type as account_type,
  SUM(CASE 
    WHEN a.type = 'asset' THEN jl.debit_amount - jl.credit_amount
    WHEN a.type IN ('liability', 'equity') THEN jl.credit_amount - jl.debit_amount
    WHEN a.type = 'income' THEN jl.credit_amount - jl.debit_amount
    WHEN a.type = 'expense' THEN jl.debit_amount - jl.credit_amount
    ELSE 0
  END) as balance
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND jl.tenant_id = public.user_tenant_id()
GROUP BY a.type
ORDER BY a.type;

-- QUERY 4: Inventory account balance (check for negative)
SELECT 
  a.code,
  a.name,
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  SUM(jl.debit_amount) - SUM(jl.credit_amount) as balance
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND a.name ILIKE '%Inventario%'
  AND jl.tenant_id = public.user_tenant_id()
GROUP BY a.id, a.code, a.name;

-- QUERY 5: Accounts with negative balances (unusual)
SELECT 
  a.code,
  a.name,
  a.type,
  CASE 
    WHEN a.type = 'asset' THEN SUM(jl.debit_amount - jl.credit_amount)
    ELSE SUM(jl.credit_amount - jl.debit_amount)
  END as balance
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND jl.tenant_id = public.user_tenant_id()
GROUP BY a.id, a.code, a.name, a.type
HAVING (
  (a.type = 'asset' AND SUM(jl.debit_amount - jl.credit_amount) < 0)
  OR (a.type IN ('liability', 'equity') AND SUM(jl.credit_amount - jl.debit_amount) < 0)
)
ORDER BY a.type, a.code;

-- QUERY 6: Full accounting equation check
SELECT 
  SUM(CASE WHEN a.type = 'asset' THEN jl.debit_amount - jl.credit_amount ELSE 0 END) as total_assets,
  SUM(CASE WHEN a.type = 'liability' THEN jl.credit_amount - jl.debit_amount ELSE 0 END) as total_liabilities,
  SUM(CASE WHEN a.type = 'equity' THEN jl.credit_amount - jl.debit_amount ELSE 0 END) as total_equity,
  SUM(CASE WHEN a.type = 'income' THEN jl.credit_amount - jl.debit_amount ELSE 0 END) as total_income,
  SUM(CASE WHEN a.type = 'expense' THEN jl.debit_amount - jl.credit_amount ELSE 0 END) as total_expense,
  SUM(CASE WHEN a.type = 'income' THEN jl.credit_amount - jl.debit_amount ELSE 0 END) 
    - SUM(CASE WHEN a.type = 'expense' THEN jl.debit_amount - jl.credit_amount ELSE 0 END) as net_income,
  -- Accounting Equation Check
  SUM(CASE WHEN a.type = 'asset' THEN jl.debit_amount - jl.credit_amount ELSE 0 END) 
  - (
    SUM(CASE WHEN a.type = 'liability' THEN jl.credit_amount - jl.debit_amount ELSE 0 END)
    + SUM(CASE WHEN a.type = 'equity' THEN jl.credit_amount - jl.debit_amount ELSE 0 END)
    + SUM(CASE WHEN a.type = 'income' THEN jl.credit_amount - jl.debit_amount ELSE 0 END)
    - SUM(CASE WHEN a.type = 'expense' THEN jl.debit_amount - jl.credit_amount ELSE 0 END)
  ) as equation_difference
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND jl.tenant_id = public.user_tenant_id();

-- QUERY 7: Check for journal lines with NULL or missing account types
-- This could cause amounts to be excluded from the equation
SELECT 
  jl.id as line_id,
  je.entry_number,
  jl.account_id,
  a.code as account_code,
  a.name as account_name,
  a.type as account_type,
  jl.debit_amount,
  jl.credit_amount
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
LEFT JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id()
  AND (a.type IS NULL OR a.type NOT IN ('asset', 'liability', 'equity', 'income', 'expense'))
LIMIT 50;

-- QUERY 8: Check total debits vs credits (should be EXACTLY equal)
SELECT 
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  SUM(jl.debit_amount) - SUM(jl.credit_amount) as raw_difference
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id();

-- QUERY 9: Check if IVA accounts exist and their types
-- IVA should be LIABILITY type, not income/expense
SELECT 
  a.code,
  a.name,
  a.type,
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  CASE 
    WHEN a.type = 'asset' THEN SUM(jl.debit_amount - jl.credit_amount)
    WHEN a.type IN ('liability', 'equity') THEN SUM(jl.credit_amount - jl.debit_amount)
    ELSE SUM(jl.credit_amount - jl.debit_amount)
  END as balance
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id()
  AND (a.name ILIKE '%IVA%' OR a.code LIKE '211%' OR a.code LIKE '212%')
GROUP BY a.id, a.code, a.name, a.type
ORDER BY a.code;

-- QUERY 10: List ALL accounts with their balances to find the missing 20,117
SELECT 
  a.code,
  a.name,
  a.type,
  SUM(jl.debit_amount) as total_debits,
  SUM(jl.credit_amount) as total_credits,
  CASE 
    WHEN a.type = 'asset' THEN SUM(jl.debit_amount - jl.credit_amount)
    WHEN a.type IN ('liability', 'equity') THEN SUM(jl.credit_amount - jl.debit_amount)
    WHEN a.type = 'income' THEN SUM(jl.credit_amount - jl.debit_amount)
    WHEN a.type = 'expense' THEN SUM(jl.debit_amount - jl.credit_amount)
    ELSE 0
  END as balance
FROM journal_lines jl
JOIN journal_entries je ON je.id = jl.entry_id
JOIN accounts a ON a.id = jl.account_id
WHERE je.status = 'posted'
  AND je.tenant_id = public.user_tenant_id()
GROUP BY a.id, a.code, a.name, a.type
ORDER BY a.type, a.code;
