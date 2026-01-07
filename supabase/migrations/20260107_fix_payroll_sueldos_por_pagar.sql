-- ============================================================================
-- PAYROLL ACCOUNTING FIX
-- ============================================================================
-- Creates proper "Sueldos por Pagar" (Salaries Payable) liability account
-- and fixes all existing payroll journal entries to use it correctly.
--
-- ACCOUNTING FLOW:
-- 1. Expense: Debit 6101-XX (Salary Expense), Credit 2106 (Sueldos por Pagar)
-- 2. Payment: Debit 2106 (Sueldos por Pagar), Credit Cash/Bank
-- ============================================================================

-- ============================================================================
-- PART 1: CREATE "SUELDOS POR PAGAR" ACCOUNT (2106)
-- ============================================================================

-- Create the Sueldos por Pagar account for each tenant that doesn't have it
INSERT INTO accounts (tenant_id, code, name, type, category, description, is_active)
SELECT 
    t.id,
    '2106',
    'Sueldos por Pagar',
    'liability',
    'currentLiability',
    'Obligaciones pendientes de pago por remuneraciones al personal',
    true
FROM tenants t
WHERE NOT EXISTS (
    SELECT 1 FROM accounts a 
    WHERE a.tenant_id = t.id AND a.code = '2106'
);

-- ============================================================================
-- PART 2: FIX EXISTING PAYROLL EXPENSE JOURNAL ENTRIES
-- ============================================================================
-- These are the "Gasto GTO-XXXXX - Proveedor" entries that should:
-- - Debit: 6101-XX (Salary - Employee)  Already correct
-- - Credit: 2106 (Sueldos por Pagar)  Currently using 2105 or 1101/1110

-- Fix the credit lines in expense entries to use 2106 Sueldos por Pagar
UPDATE journal_lines jl
SET 
    account_id = a.id,
    account_code = '2106',
    account_name = 'Sueldos por Pagar'
FROM journal_entries je, accounts a
WHERE jl.entry_id = je.id
  AND je.source_module = 'expenses'
  AND je.description LIKE 'Gasto GTO-%'
  AND jl.credit_amount > 0
  AND jl.account_code IN ('2105', '1101', '1110')
  AND a.code = '2106'
  AND a.tenant_id = je.tenant_id;

-- ============================================================================
-- PART 3: FIX EXISTING PAYROLL PAYMENT JOURNAL ENTRIES
-- ============================================================================
-- These are the "Pago gasto GTO-XXXXX" entries that should:
-- - Debit: 2106 (Sueldos por Pagar)  Currently using 2105
-- - Credit: 1101/1110 (Cash/Bank)  Already correct

-- Fix the debit lines in payment entries to use 2106 Sueldos por Pagar
UPDATE journal_lines jl
SET 
    account_id = a.id,
    account_code = '2106',
    account_name = 'Sueldos por Pagar'
FROM journal_entries je, accounts a
WHERE jl.entry_id = je.id
  AND je.source_module = 'expense_payments'
  AND je.description LIKE 'Pago gasto GTO-%'
  AND jl.debit_amount > 0
  AND jl.account_code = '2105'
  AND a.code = '2106'
  AND a.tenant_id = je.tenant_id;

-- ============================================================================
-- PART 4: UPDATE EXPENSE JOURNAL ENTRY FUNCTION FOR PAYROLL
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_expense_journal_entry(p_expense_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_account_code text;
  v_liability_account_name text;
  v_tax_account_id uuid;
  v_tax_account_code text := '2120';
  v_tax_account_name text := 'IVA Crédito Fiscal';
  v_cash_account record;
  v_total numeric(14,2);
  v_tax_total numeric(14,2);
  v_credit_account_id uuid;
  v_credit_account_code text;
  v_credit_account_name text;
  v_description text;
  v_supplier text;
  v_document text;
  v_line record;
  v_line_count integer := 0;
  v_default_account record;
  v_is_payroll boolean := false;
BEGIN
  SELECT e.* INTO v_expense FROM public.expenses e WHERE e.id = p_expense_id;

  IF NOT FOUND THEN RETURN; END IF;
  IF lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' THEN RETURN; END IF;

  v_total := coalesce(v_expense.total_amount, 0);
  IF v_total = 0 THEN RETURN; END IF;

  -- Detect if this is a payroll expense
  v_is_payroll := (
    v_expense.notes LIKE 'Pago de salario%' OR 
    v_expense.notes LIKE 'Salario:%' OR 
    v_expense.reference LIKE 'Semana %'
  );

  -- Delete existing journal entry if it exists (using expense_number as reference)
  SELECT EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'expenses' AND source_reference = v_expense.expense_number
  ) INTO v_exists;

  IF v_exists THEN
    DELETE FROM public.journal_entries
    WHERE source_module = 'expenses' AND source_reference = v_expense.expense_number;
  END IF;

  -- Determine the correct liability account
  IF v_is_payroll THEN
    -- Use 2106 Sueldos por Pagar for payroll
    v_liability_account_code := '2106';
    v_liability_account_name := 'Sueldos por Pagar';
    SELECT id INTO v_liability_account_id
    FROM public.accounts
    WHERE tenant_id = v_expense.tenant_id AND code = '2106';
    
    IF v_liability_account_id IS NULL THEN
      v_liability_account_id := public.ensure_account(
        v_expense.tenant_id, '2106', 'Sueldos por Pagar',
        'liability', 'currentLiability',
        'Obligaciones pendientes de pago por remuneraciones al personal', null
      );
    END IF;
  ELSE
    -- Use 2105 Cuentas por Pagar - Gastos for non-payroll expenses
    v_liability_account_code := '2105';
    v_liability_account_name := 'Cuentas por Pagar - Gastos';
    v_liability_account_id := coalesce(
      v_expense.liability_account_id,
      public.ensure_account(
        v_expense.tenant_id, v_liability_account_code, v_liability_account_name,
        'liability', 'currentLiability',
        'Obligaciones por gastos pendientes de pago', null
      )
    );
  END IF;

  -- Initialize cash account record
  SELECT null::uuid as id, null::text as code, null::text as name INTO v_cash_account;

  IF v_expense.payment_account_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_cash_account
    FROM public.accounts a WHERE a.id = v_expense.payment_account_id;
  ELSIF v_expense.payment_method_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_cash_account
    FROM public.payment_methods pm
    JOIN public.accounts a ON a.id = pm.account_id
    WHERE pm.id = v_expense.payment_method_id;
  END IF;

  v_tax_account_id := public.ensure_account(
    v_expense.tenant_id, v_tax_account_code, v_tax_account_name,
    'asset', 'currentAsset', 'Crédito fiscal IVA soportado en compras', null
  );

  v_supplier := coalesce(nullif(v_expense.supplier_name, ''), 'Proveedor');
  v_document := coalesce(nullif(v_expense.document_number, ''), v_expense.expense_number);
  v_description := format('Gasto %s - %s', v_document, v_supplier);

  -- Insert Journal Entry Header
  INSERT INTO public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type,
    source_module, source_reference, status, total_debit, total_credit,
    created_at, updated_at
  ) VALUES (
    v_entry_id, v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_expense.issue_date, now()),
    v_description,
    CASE WHEN v_is_payroll THEN 'payroll' ELSE 'purchase' END,
    'expenses', v_expense.expense_number, 'posted',
    v_total, v_total, now(), now()
  );

  -- Insert Journal Lines from Expense Lines (DEBIT side)
  FOR v_line IN
    SELECT el.* FROM public.expense_lines el
    WHERE el.expense_id = v_expense.id
    ORDER BY el.line_index, el.created_at
  LOOP
    v_line_count := v_line_count + 1;
    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_expense.tenant_id, v_entry_id,
      v_line.account_id, v_line.account_code, v_line.account_name,
      coalesce(nullif(v_line.description, ''), v_description),
      coalesce(v_line.total, v_line.subtotal, 0), 0, now(), now()
    );
  END LOOP;

  -- Fallback if no lines
  IF v_line_count = 0 THEN
    IF v_expense.category_id IS NOT NULL THEN
      SELECT a.id, a.code, a.name INTO v_default_account
      FROM public.expense_categories ec
      JOIN public.accounts a ON a.id = ec.default_account_id
      WHERE ec.id = v_expense.category_id;
    END IF;

    IF v_default_account IS NULL OR v_default_account.id IS NULL THEN
      SELECT public.ensure_account(
        v_expense.tenant_id, '5200', 'Gastos Generales', 'expense', 'operatingExpense',
        'Gastos generales y administrativos', null
      ) as id, '5200' as code, 'Gastos Generales' as name
      INTO v_default_account;
    END IF;

    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_expense.tenant_id, v_entry_id,
      v_default_account.id, v_default_account.code, v_default_account.name,
      v_description,
      coalesce(v_expense.subtotal, v_total - coalesce(v_expense.tax_amount, 0)), 0,
      now(), now()
    );
  END IF;

  -- Tax handling
  v_tax_total := coalesce(v_expense.tax_amount, 0);
  IF v_tax_total <> 0 THEN
    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_expense.tenant_id, v_entry_id,
      v_tax_account_id, v_tax_account_code, v_tax_account_name,
      format('IVA crédito gasto %s', v_document),
      v_tax_total, 0, now(), now()
    );
  END IF;

  -- CREDIT side: ALWAYS use liability account for payroll
  IF v_is_payroll THEN
    v_credit_account_id := v_liability_account_id;
    v_credit_account_code := v_liability_account_code;
    v_credit_account_name := v_liability_account_name;
  ELSE
    IF lower(coalesce(v_expense.payment_status, 'pending')) = 'paid'
       AND coalesce(v_expense.balance, 0) <= 0.01
       AND v_cash_account.id IS NOT NULL THEN
      v_credit_account_id := v_cash_account.id;
      v_credit_account_code := v_cash_account.code;
      v_credit_account_name := v_cash_account.name;
    ELSE
      v_credit_account_id := v_liability_account_id;
      SELECT code, name INTO v_credit_account_code, v_credit_account_name
      FROM public.accounts WHERE id = v_credit_account_id;
    END IF;
  END IF;

  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_expense.tenant_id, v_entry_id,
    v_credit_account_id, v_credit_account_code, v_credit_account_name,
    v_description, 0, v_total, now(), now()
  );
END;
$$;

-- ============================================================================
-- PART 5: UPDATE EXPENSE PAYMENT JOURNAL ENTRY FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_expense_payment_journal_entry(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment record;
  v_expense record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_code text;
  v_liability_name text;
  v_payment_account record;
  v_description text;
  v_is_payroll boolean := false;
BEGIN
  SELECT ep.* INTO v_payment
  FROM public.expense_payments ep
  WHERE ep.id = p_payment_id;

  IF NOT FOUND THEN RETURN; END IF;
  IF coalesce(v_payment.amount, 0) = 0 THEN RETURN; END IF;

  SELECT e.* INTO v_expense
  FROM public.expenses e
  WHERE e.id = v_payment.expense_id;

  IF NOT FOUND THEN RETURN; END IF;

  -- Detect if this is a payroll expense
  v_is_payroll := (
    v_expense.notes LIKE 'Pago de salario%' OR 
    v_expense.notes LIKE 'Salario:%' OR 
    v_expense.reference LIKE 'Semana %'
  );

  -- Delete existing entry if exists
  SELECT EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'expense_payments' AND source_reference = p_payment_id::text
  ) INTO v_exists;

  IF v_exists THEN
    DELETE FROM public.journal_entries
    WHERE source_module = 'expense_payments' AND source_reference = p_payment_id::text;
  END IF;

  -- Determine liability account based on expense type
  IF v_is_payroll THEN
    v_liability_code := '2106';
    v_liability_name := 'Sueldos por Pagar';
  ELSE
    v_liability_code := '2105';
    v_liability_name := 'Cuentas por Pagar - Gastos';
  END IF;

  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    (SELECT id FROM public.accounts WHERE tenant_id = v_expense.tenant_id AND code = v_liability_code),
    public.ensure_account(
      v_expense.tenant_id, v_liability_code, v_liability_name,
      'liability', 'currentLiability', 'Obligaciones por gastos', null
    )
  );

  -- Get payment account
  SELECT null::uuid as id, null::text as code, null::text as name INTO v_payment_account;

  IF v_payment.payment_account_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_payment_account
    FROM public.accounts a WHERE a.id = v_payment.payment_account_id;
  ELSIF v_payment.payment_method_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_payment_account
    FROM public.payment_methods pm
    JOIN public.accounts a ON a.id = pm.account_id
    WHERE pm.id = v_payment.payment_method_id;
  END IF;

  IF v_payment_account.id IS NULL THEN
    RETURN;
  END IF;

  v_description := format('Pago gasto %s', v_expense.expense_number);

  -- Insert Journal Entry Header
  INSERT INTO public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type,
    source_module, source_reference, status, total_debit, total_credit,
    created_at, updated_at
  ) VALUES (
    v_entry_id, v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_payment.payment_date, now()),
    v_description, 'payment',
    'expense_payments', p_payment_id::text, 'posted',
    v_payment.amount, v_payment.amount, now(), now()
  );

  -- Debit: Liability account (reduce what we owe)
  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_expense.tenant_id, v_entry_id,
    v_liability_account_id, v_liability_code, v_liability_name,
    v_description, v_payment.amount, 0, now(), now()
  );

  -- Credit: Cash/Bank account (reduce our cash)
  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_expense.tenant_id, v_entry_id,
    v_payment_account.id, v_payment_account.code, v_payment_account.name,
    v_description, 0, v_payment.amount, now(), now()
  );
END;
$$;

-- ============================================================================
-- PART 6: CLEANUP DUPLICATE EXPENSE JOURNAL ENTRIES
-- ============================================================================
-- Some expenses have multiple journal entries due to bugs in previous versions.
-- We keep ONLY the FIRST entry (lowest entry_number) per expense and delete the rest.

-- First, preview what will be deleted
DO $$
DECLARE
  v_deleted_count integer := 0;
BEGIN
  RAISE NOTICE 'Starting duplicate expense journal entry cleanup...';
  
  -- Delete duplicate expense journal entries (keep first, delete others)
  WITH ranked_expense_entries AS (
    SELECT 
      je.id,
      je.entry_number,
      je.source_reference,
      ROW_NUMBER() OVER (
        PARTITION BY je.source_reference 
        ORDER BY je.entry_number ASC
      ) as rn
    FROM journal_entries je
    WHERE je.source_module = 'expenses'
      AND je.source_reference LIKE 'GTO-%'
  ),
  duplicates AS (
    SELECT id FROM ranked_expense_entries WHERE rn > 1
  )
  DELETE FROM journal_entries WHERE id IN (SELECT id FROM duplicates);
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RAISE NOTICE 'Deleted % duplicate expense journal entries', v_deleted_count;
END $$;

-- ============================================================================
-- PART 7: VERIFY FINAL STATE
-- ============================================================================

-- Show summary of Sueldos por Pagar (2106) account
-- Should show balanced credits and debits if all salaries are paid
DO $$
DECLARE
  v_credits numeric;
  v_debits numeric;
  v_balance numeric;
BEGIN
  SELECT 
    COALESCE(SUM(jl.credit_amount), 0),
    COALESCE(SUM(jl.debit_amount), 0)
  INTO v_credits, v_debits
  FROM journal_lines jl
  JOIN accounts a ON jl.account_id = a.id
  WHERE a.code = '2106';
  
  v_balance := v_credits - v_debits;
  
  RAISE NOTICE '=== SUELDOS POR PAGAR (2106) SUMMARY ===';
  RAISE NOTICE 'Total Credits (liabilities created): $%', v_credits;
  RAISE NOTICE 'Total Debits (liabilities paid): $%', v_debits;
  RAISE NOTICE 'Balance (unpaid salaries): $%', v_balance;
  
  IF v_balance = 0 THEN
    RAISE NOTICE 'All salaries are paid - account is balanced!';
  ELSIF v_balance > 0 THEN
    RAISE NOTICE 'Outstanding salary payments: $%', v_balance;
  ELSE
    RAISE NOTICE 'WARNING: Negative balance - overpayment or data issue!';
  END IF;
END $$;
