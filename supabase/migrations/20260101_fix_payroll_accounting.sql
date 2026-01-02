-- Migration to fix Payroll Accounting using NATIVE Core Schema Functions
-- 1. Fixes bug in create_expense_journal_entry (Error 55000: record not assigned)
-- 2. Fixes Primary Key / Foreign Key violation on created_by (Error 23503)
-- 3. Adds 'payroll' type to journal entries (Handling Check Constraints)
-- 4. Updates pay_payroll_voucher to use the native accounting system explicitly
-- 5. Backfills missing accounting entries correctly

-- PART 0: ENSURE TYPE ALLOWS 'payroll'
DO $$
BEGIN
    -- 1. Try to add value if it is an enum (catch error if not)
    BEGIN
        ALTER TYPE journal_entry_type ADD VALUE IF NOT EXISTS 'payroll';
    EXCEPTION WHEN OTHERS THEN 
        NULL; -- Not an enum or other error, ignore
    END;

    -- 2. Update CHECK constraint if it exists (Common in Supabase starters)
    -- We drop the old constraint (if any) and add a new one including 'payroll'
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'journal_entries_type_check') THEN
        ALTER TABLE public.journal_entries DROP CONSTRAINT journal_entries_type_check;
        ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_type_check 
        CHECK (type IN ('manual', 'sales', 'purchase', 'payment', 'receipt', 'adjustment', 'closing', 'opening', 'payroll'));
    ELSE
        -- If no constraint exists, we might want to add one, or leave it alone if it's just text.
        -- Safer to leave it alone unless we are sure. But let's at least try to validate.
        NULL;
    END IF;
END $$;

-- PART 1: FIX THE CORE ACCOUNTING FUNCTION (Now with Payroll Detection!)
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
  v_liability_account_code text := '2105';
  v_liability_account_name text := 'Cuentas por Pagar - Gastos';
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
  v_valid_user_id uuid;
  v_entry_type text := 'purchase'; -- Default
BEGIN
  -- Load Expense
  SELECT e.* INTO v_expense FROM public.expenses e WHERE e.id = p_expense_id;

  IF NOT FOUND THEN RETURN; END IF;
  
  -- Validation Checks
  IF lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted' THEN RETURN; END IF;
  
  v_total := coalesce(v_expense.total_amount, 0);
  IF v_total = 0 THEN RETURN; END IF;

  -- Delete existing entry to recreate fresh
  SELECT exists (
           SELECT 1 FROM public.journal_entries
           WHERE source_module = 'expenses' AND source_reference = v_expense.id::text
         ) INTO v_exists;

  IF v_exists THEN
    PERFORM public.delete_expense_journal_entry(p_expense_id);
  END IF;

  -- Ensure Liability Account
  v_liability_account_id := coalesce(
    v_expense.liability_account_id,
    public.ensure_account(v_expense.tenant_id, v_liability_account_code, v_liability_account_name, 'liability', 'currentLiability', 'Obligaciones por gastos pendientes de pago', null)
  );

  -- Resolve Payment/Cash Account
  IF v_expense.payment_account_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_cash_account FROM public.accounts a WHERE a.id = v_expense.payment_account_id;
  ELSIF v_expense.payment_method_id IS NOT NULL THEN
    SELECT a.id, a.code, a.name INTO v_cash_account 
    FROM public.payment_methods pm 
    JOIN public.accounts a ON a.id = pm.account_id 
    WHERE pm.id = v_expense.payment_method_id;
  END IF;

  -- Ensure Tax Account
  v_tax_account_id := public.ensure_account(v_expense.tenant_id, v_tax_account_code, v_tax_account_name, 'asset', 'currentAsset', 'Crédito fiscal IVA soportado en compras', null);

  v_supplier := coalesce(nullif(v_expense.supplier_name, ''), 'Proveedor');
  v_document := coalesce(nullif(v_expense.document_number, ''), v_expense.expense_number);
  v_description := format('Gasto %s - %s', v_document, v_supplier);

  -- VALIDATE CREATOR (Fix for FK Violation)
  SELECT id INTO v_valid_user_id FROM public.users_profiles WHERE id = v_expense.created_by;
  IF v_valid_user_id IS NULL THEN
    SELECT id INTO v_valid_user_id FROM public.users_profiles WHERE id = auth.uid();
  END IF;
  IF v_valid_user_id IS NULL THEN
    SELECT id INTO v_valid_user_id FROM public.users_profiles ORDER BY created_at ASC LIMIT 1;
  END IF;

  -- DETERMINE ENTRY TYPE
  -- Check if it looks like Payroll
  IF v_expense.notes LIKE 'Pago de salario%' OR v_expense.notes LIKE 'Salario%' OR v_expense.reference LIKE 'Semana %' THEN
      v_entry_type := 'payroll';
  ELSE
      v_entry_type := 'purchase';
  END IF;

  -- Insert Journal Entry Header
  -- REMOVED CAST ::journal_entry_type to be safe (it's likely text)
  INSERT INTO public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type, source_module, source_reference, status, total_debit, total_credit, created_at, updated_at, created_by
  ) VALUES (
    v_entry_id,
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_expense.issue_date, now()),
    v_description,
    v_entry_type, -- Pass as text, let DB validation handle it
    'expenses',
    v_expense.expense_number,
    'posted',
    v_total,
    v_total,
    now(),
    now(),
    v_valid_user_id
  );

  -- Insert Journal Lines from Expense Lines
  FOR v_line IN
    SELECT el.* FROM public.expense_lines el 
    WHERE el.expense_id = v_expense.id 
    ORDER BY el.line_index, el.created_at
  LOOP
    v_line_count := v_line_count + 1;
    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name, description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_line.account_id,
      v_line.account_code,
      v_line.account_name,
      coalesce(nullif(v_line.description, ''), v_description),
      coalesce(v_line.total, v_line.subtotal, 0),
      0,
      now(),
      now()
    );
  END LOOP;

  -- Fallback if no lines (FIXED: Proper Null Check)
  IF v_line_count = 0 THEN
    IF v_expense.category_id IS NOT NULL THEN
      SELECT a.id, a.code, a.name INTO v_default_account
      FROM public.expense_categories ec
      JOIN public.accounts a ON a.id = ec.default_account_id
      WHERE ec.id = v_expense.category_id;
    END IF;

    IF v_default_account IS NULL OR v_default_account.id IS NULL THEN
      SELECT public.ensure_account(
               v_expense.tenant_id, '5200', 'Gastos Generales', 'expense', 'operatingExpense', 'Gastos generales y administrativos', null
             ) as id, '5200' as code, 'Gastos Generales' as name
      INTO v_default_account;
    END IF;

    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name, description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_default_account.id,
      v_default_account.code,
      v_default_account.name,
      v_description,
      coalesce(v_expense.subtotal, v_total - coalesce(v_expense.tax_amount, 0)),
      0,
      now(),
      now()
    );
  END IF;

  -- Tax Handling
  v_tax_total := coalesce(v_expense.tax_amount, 0);
  IF v_tax_total <> 0 THEN
    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name, description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      v_expense.tenant_id,
      v_entry_id,
      v_tax_account_id,
      v_tax_account_code,
      v_tax_account_name,
      format('IVA crédito gasto %s', v_document),
      v_tax_total,
      0,
      now(),
      now()
    );
  END IF;

  -- Credit / Payment Handling
  IF lower(coalesce(v_expense.payment_status, 'pending')) = 'paid' AND coalesce(v_expense.balance, 0) <= 0.01 AND v_cash_account.id IS NOT NULL THEN
    v_credit_account_id := v_cash_account.id;
    v_credit_account_code := v_cash_account.code;
    v_credit_account_name := v_cash_account.name;
  ELSE
    v_credit_account_id := v_liability_account_id;
    SELECT code, name INTO v_credit_account_code, v_credit_account_name FROM public.accounts WHERE id = v_credit_account_id;
  END IF;

  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name, description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_credit_account_id,
    v_credit_account_code,
    v_credit_account_name,
    v_description,
    0,
    v_total,
    now(),
    now()
  );

END;
$$;


-- PART 2: UPDATE PAYROLL FUNCTION
CREATE OR REPLACE FUNCTION pay_payroll_voucher(p_voucher_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_voucher payroll_vouchers%ROWTYPE;
  line RECORD;
  v_expense_id UUID;
  v_expense_seq INTEGER;
  v_expense_number TEXT;
  
  v_pay_method_id UUID;
  v_pay_method_name TEXT;
  v_pay_account_id UUID;
BEGIN
  SELECT * INTO v_voucher FROM payroll_vouchers WHERE id = p_voucher_id;
  
  IF v_voucher IS NULL THEN RAISE EXCEPTION 'Voucher not found'; END IF;
  IF v_voucher.status != 'pending' THEN RAISE EXCEPTION 'Voucher must be in pending status'; END IF;
  
  FOR line IN 
    SELECT * FROM payroll_voucher_lines WHERE voucher_id = p_voucher_id AND is_included = true
  LOOP
    IF COALESCE(line.total_amount, 0) <= 0 THEN CONTINUE; END IF;
    IF line.salary_account_id IS NULL THEN RAISE EXCEPTION 'Employee % has missing Salary Account', line.employee_name; END IF;

    -- ID Resolution Logic
    v_pay_method_id := line.payment_method_id;
    v_pay_account_id := line.payment_account_id;
    
    -- Resolve Account ID if missing
    IF v_pay_account_id IS NULL THEN
        IF v_pay_method_id IS NOT NULL THEN
            SELECT name INTO v_pay_method_name FROM payment_methods WHERE id = v_pay_method_id;
            IF v_pay_method_name ILIKE '%efectivo%' OR v_pay_method_name ILIKE '%cash%' THEN
                 SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1101%' LIMIT 1;
            ELSIF v_pay_method_name ILIKE '%transf%' THEN
                 SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1102%' LIMIT 1;
            END IF;
        END IF;

        IF v_pay_account_id IS NULL THEN
             IF line.payment_method = 'cash' THEN SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1101%' LIMIT 1;
            ELSIF line.payment_method = 'transfer' THEN SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1102%' LIMIT 1;
            END IF;
        END IF;
        
        IF v_pay_account_id IS NULL THEN SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1101%' LIMIT 1; END IF;
    END IF;
    
    IF v_pay_method_id IS NULL THEN
       IF line.payment_method = 'cash' THEN SELECT id INTO v_pay_method_id FROM payment_methods WHERE name ILIKE '%efectivo%' LIMIT 1;
       ELSE SELECT id INTO v_pay_method_id FROM payment_methods WHERE name ILIKE '%transf%' LIMIT 1;
       END IF;
    END IF;

    -- Create Expense
    SELECT COALESCE(MAX(SUBSTRING(expense_number FROM '[0-9]+$')::INT), 0) + 1 INTO v_expense_seq FROM expenses WHERE tenant_id = line.tenant_id;
    v_expense_number := 'GTO-' || LPAD(v_expense_seq::TEXT, 5, '0');
    
    INSERT INTO expenses (
      tenant_id, expense_number, payment_account_id, payment_method_id, document_type,
      subtotal, tax_amount, total_amount, issue_date, reference, notes,
      posting_status, payment_status, created_by, paid_at
    ) VALUES (
      line.tenant_id, v_expense_number, v_pay_account_id, v_pay_method_id, 'ticket',
      line.total_amount, 0, line.total_amount, CURRENT_DATE,
      'Semana ' || COALESCE(v_voucher.period_label, '') || ' - ' || v_voucher.voucher_number,
      'Pago de salario: ' || line.employee_name,
      'posted', 'paid', auth.uid(), NOW()
    ) RETURNING id INTO v_expense_id;
    
    INSERT INTO expense_lines (
        tenant_id, expense_id, account_id, quantity, unit_price, subtotal, tax_rate, tax_amount, total, description
    ) VALUES (
        line.tenant_id, v_expense_id, line.salary_account_id,
        1, line.total_amount, line.total_amount, 0, 0, line.total_amount,
        'Salario: ' || line.employee_name
    );
    
    -- EXPLICIT CALL TO NATIVE ACCOUNTING FUNCTION
    PERFORM public.create_expense_journal_entry(v_expense_id);

  END LOOP;
  
  UPDATE payroll_vouchers SET status = 'paid', paid_at = NOW() WHERE id = p_voucher_id;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- PART 3: BACKFILL (Using the Native Function)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT e.id, e.expense_number 
        FROM expenses e
        LEFT JOIN journal_entries je ON je.source_reference = e.expense_number AND je.source_module = 'expenses'
        WHERE e.expense_number LIKE 'GTO-%' 
          AND e.payment_status = 'paid'
          AND je.id IS NULL
    LOOP
        PERFORM public.create_expense_journal_entry(r.id);
    END LOOP;
END;
$$;
