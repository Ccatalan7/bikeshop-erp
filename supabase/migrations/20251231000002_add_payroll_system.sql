-- ============================================================================
-- PAYROLL VOUCHER SYSTEM MIGRATION
-- ============================================================================
-- 1. Tables: payroll_vouchers, payroll_voucher_lines
-- 2. Columns: employees.salary_account_id
-- 3. Logic: Auto-create salary accounts, Generate Vouchers, Pay Vouchers
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ADD SALARY ACCOUNT TRACKING TO EMPLOYEES
-- ----------------------------------------------------------------------------

-- Add salary_account_id column
DO $$ BEGIN
  ALTER TABLE employees 
    ADD COLUMN IF NOT EXISTS salary_account_id UUID REFERENCES accounts(id);
EXCEPTION
  WHEN duplicate_column THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_employees_salary_account ON employees(salary_account_id);

-- Function to auto-create salary account (6101-XX)
CREATE OR REPLACE FUNCTION create_employee_salary_account()
RETURNS TRIGGER AS $$
DECLARE
  v_parent_account_id UUID;
  v_next_code TEXT;
  v_new_account_id UUID;
  v_child_count INTEGER;
BEGIN
  -- Find the 6101 parent account for this tenant (Sueldos y Salarios)
  SELECT id INTO v_parent_account_id
  FROM accounts
  WHERE tenant_id = NEW.tenant_id
    AND code = '6101';
  
  -- If not found, we can't create a sub-account, so just return
  IF v_parent_account_id IS NULL THEN
    RAISE NOTICE '⚠️ Account 6101 not found for tenant %, skipping salary account creation', NEW.tenant_id;
    RETURN NEW;
  END IF;
  
  -- Calculate next sub-account code (6101-01, 6101-02, etc.)
  SELECT COUNT(*) INTO v_child_count
  FROM accounts
  WHERE tenant_id = NEW.tenant_id
    AND parent_id = v_parent_account_id;
  
  v_next_code := '6101-' || LPAD((v_child_count + 1)::TEXT, 2, '0');
  
  -- Create the salary sub-account
  INSERT INTO accounts (
    tenant_id,
    code,
    name,
    type,
    category,
    parent_id,
    description
  ) VALUES (
    NEW.tenant_id,
    v_next_code,
    'Salario - ' || NEW.first_name || ' ' || NEW.last_name,
    'expense',
    'operatingExpense',
    v_parent_account_id,
    'Cuenta de salario para empleado: ' || NEW.first_name || ' ' || NEW.last_name
  )
  RETURNING id INTO v_new_account_id;
  
  -- Update the employee with the new account reference
  NEW.salary_account_id := v_new_account_id;
  
  RAISE NOTICE '✅ Created salary account % for employee %', v_next_code, NEW.first_name || ' ' || NEW.last_name;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on INSERT
DROP TRIGGER IF EXISTS trg_create_employee_salary_account ON employees;
CREATE TRIGGER trg_create_employee_salary_account
  BEFORE INSERT ON employees
  FOR EACH ROW
  EXECUTE FUNCTION create_employee_salary_account();

-- Backfill existing employees
DO $$
DECLARE
  emp RECORD;
  v_parent_account_id UUID;
  v_next_code TEXT;
  v_new_account_id UUID;
  v_child_count INTEGER;
BEGIN
  FOR emp IN 
    SELECT * FROM employees 
    WHERE salary_account_id IS NULL
  LOOP
    -- Find 6101 for this tenant
    SELECT id INTO v_parent_account_id
    FROM accounts
    WHERE tenant_id = emp.tenant_id AND code = '6101';
    
    IF v_parent_account_id IS NOT NULL THEN
      -- Get next sequence
      SELECT COUNT(*) INTO v_child_count
      FROM accounts
      WHERE tenant_id = emp.tenant_id AND parent_id = v_parent_account_id;
      
      v_next_code := '6101-' || LPAD((v_child_count + 1)::TEXT, 2, '0');
      
      -- Create account
      INSERT INTO accounts (tenant_id, code, name, type, category, parent_id, description)
      VALUES (
        emp.tenant_id,
        v_next_code,
        'Salario - ' || emp.first_name || ' ' || emp.last_name,
        'expense',
        'operatingExpense',
        v_parent_account_id,
        'Cuenta de salario para empleado: ' || emp.first_name || ' ' || emp.last_name
      )
      RETURNING id INTO v_new_account_id;
      
      -- Link to employee
      UPDATE employees SET salary_account_id = v_new_account_id WHERE id = emp.id;
      
      RAISE NOTICE '✅ Created salary account % for %', v_next_code, emp.first_name;
    END IF;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. PAYROLL VOUCHERS TABLE
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS payroll_vouchers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
  
  -- Period Info
  voucher_number TEXT NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  period_label TEXT, -- e.g., "Semana 52 (23 Dic - 29 Dic 2025)"
  
  -- Totals
  total_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  employee_count INTEGER NOT NULL DEFAULT 0,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'paid', 'voided')),
  
  -- Payment Details (filled when paid)
  paid_at TIMESTAMP WITH TIME ZONE,
  paid_by UUID REFERENCES auth.users(id),
  
  -- Audit
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payroll_vouchers_tenant ON payroll_vouchers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_vouchers_status ON payroll_vouchers(status);
CREATE INDEX IF NOT EXISTS idx_payroll_vouchers_period ON payroll_vouchers(period_start, period_end);

-- Sequence for voucher numbers
CREATE SEQUENCE IF NOT EXISTS payroll_voucher_number_seq START WITH 1;

-- ----------------------------------------------------------------------------
-- 3. PAYROLL VOUCHER LINES TABLE
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS payroll_voucher_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE NOT NULL,
  voucher_id UUID REFERENCES payroll_vouchers(id) ON DELETE CASCADE NOT NULL,
  employee_id UUID REFERENCES employees(id) ON DELETE RESTRICT NOT NULL,
  
  -- Data (editable before finalization)
  employee_name TEXT NOT NULL,
  worked_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  overtime_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
  hourly_rate NUMERIC(10,2) NOT NULL DEFAULT 0,
  overtime_rate NUMERIC(10,2) NOT NULL DEFAULT 0,
  
  -- Calculated
  regular_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  overtime_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  
  -- Payment Details
  payment_method TEXT DEFAULT 'transfer', -- Keep for legacy UI or display
  payment_method_id UUID REFERENCES payment_methods(id),
  payment_account_id UUID REFERENCES accounts(id),
  
  is_included BOOLEAN NOT NULL DEFAULT true,
  
  -- Expense Reference (filled after payment)
  expense_id UUID REFERENCES expenses(id),
  salary_account_id UUID REFERENCES accounts(id),
  
  -- Audit
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pvl_voucher ON payroll_voucher_lines(voucher_id);
CREATE INDEX IF NOT EXISTS idx_pvl_employee ON payroll_voucher_lines(employee_id);

-- ----------------------------------------------------------------------------
-- 4. RLS POLICIES
-- ----------------------------------------------------------------------------

ALTER TABLE payroll_vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_voucher_lines ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "pv_select" ON payroll_vouchers FOR SELECT TO authenticated
    USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "pv_insert" ON payroll_vouchers FOR INSERT TO authenticated
    WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "pv_update" ON payroll_vouchers FOR UPDATE TO authenticated
    USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "pv_delete" ON payroll_vouchers FOR DELETE TO authenticated
    USING (tenant_id = public.user_tenant_id());

  CREATE POLICY "pvl_select" ON payroll_voucher_lines FOR SELECT TO authenticated
    USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "pvl_insert" ON payroll_voucher_lines FOR INSERT TO authenticated
    WITH CHECK (tenant_id = public.user_tenant_id());
  CREATE POLICY "pvl_update" ON payroll_voucher_lines FOR UPDATE TO authenticated
    USING (tenant_id = public.user_tenant_id());
  CREATE POLICY "pvl_delete" ON payroll_voucher_lines FOR DELETE TO authenticated
    USING (tenant_id = public.user_tenant_id());
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 5. RPC: GENERATE DRAFT VOUCHER
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION generate_payroll_voucher_draft(
  p_start_date DATE,
  p_end_date DATE,
  p_period_label TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_tenant_id UUID;
  v_voucher_id UUID;
  v_voucher_number TEXT;
  v_total_hours NUMERIC := 0;
  v_total_amount NUMERIC := 0;
  v_emp_count INTEGER := 0;
  emp RECORD;
  v_hours NUMERIC;
  v_overtime NUMERIC;
  v_rate NUMERIC;
  v_overtime_rate NUMERIC;
  v_regular_amt NUMERIC;
  v_overtime_amt NUMERIC;
BEGIN
  v_tenant_id := public.user_tenant_id();
  
  -- Generate voucher number (PV-00001)
  v_voucher_number := 'PV-' || LPAD(nextval('payroll_voucher_number_seq')::TEXT, 5, '0');
  
  -- Create the voucher header
  INSERT INTO payroll_vouchers (
    tenant_id, voucher_number, period_start, period_end, period_label,
    status, created_by
  ) VALUES (
    v_tenant_id, v_voucher_number, p_start_date, p_end_date, 
    COALESCE(p_period_label, 'Periodo: ' || p_start_date || ' - ' || p_end_date),
    'draft', auth.uid()
  )
  RETURNING id INTO v_voucher_id;
  
  -- Create lines for each active employee
  FOR emp IN 
    SELECT e.*, 
           COALESCE(e.hourly_rate, 0) as rate
    FROM employees e
    WHERE e.tenant_id = v_tenant_id
      AND e.status = 'active'
  LOOP
    -- Get hours summary for this period
    -- NOTE: We sum hours from the 'attendances' table
    SELECT 
      COALESCE(SUM(worked_hours), 0),
      COALESCE(SUM(overtime_hours), 0)
    INTO v_hours, v_overtime
    FROM attendances
    WHERE employee_id = emp.id
      AND check_in::DATE BETWEEN p_start_date AND p_end_date;
    
    -- If no hours, we still add them to the voucher but as 0
    -- This allows the user to manually add hours if they forgot to clock in
    
    v_rate := emp.rate;
    v_overtime_rate := v_rate * 1.5;
    v_regular_amt := v_hours * v_rate;
    v_overtime_amt := v_overtime * v_overtime_rate;
    
    INSERT INTO payroll_voucher_lines (
      tenant_id, voucher_id, employee_id, employee_name,
      worked_hours, overtime_hours, hourly_rate, overtime_rate,
      regular_amount, overtime_amount, total_amount,
      payment_method, salary_account_id, is_included
    ) VALUES (
      v_tenant_id, v_voucher_id, emp.id, 
      emp.first_name || ' ' || emp.last_name,
      v_hours, v_overtime, v_rate, v_overtime_rate,
      v_regular_amt, v_overtime_amt, v_regular_amt + v_overtime_amt,
      COALESCE(emp.preferred_payment_method::TEXT, 'transfer'),
      emp.salary_account_id, 
      (v_hours + v_overtime > 0) -- Only check "included" if they have hours
    );
    
    if (v_hours + v_overtime > 0) then
        v_total_hours := v_total_hours + v_hours + v_overtime;
        v_total_amount := v_total_amount + v_regular_amt + v_overtime_amt;
        v_emp_count := v_emp_count + 1;
    end if;
    
  END LOOP;
  
  -- Update voucher totals
  UPDATE payroll_vouchers
  SET total_hours = v_total_hours,
      total_amount = v_total_amount,
      employee_count = v_emp_count
  WHERE id = v_voucher_id;
  
  RETURN v_voucher_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ----------------------------------------------------------------------------
-- 6. RPC: PAY VOUCHER (Generate Expenses)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION pay_payroll_voucher(p_voucher_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_voucher payroll_vouchers%ROWTYPE;
  line RECORD;
  v_expense_id UUID;
  v_expense_seq INTEGER;
  v_lines_processed INTEGER := 0;
  v_acc_code TEXT;
  v_acc_name TEXT;
BEGIN
  SELECT * INTO v_voucher FROM payroll_vouchers WHERE id = p_voucher_id;
  
  IF v_voucher IS NULL THEN
    RAISE EXCEPTION 'Voucher not found';
  END IF;
  
  IF v_voucher.status != 'pending' THEN
    RAISE EXCEPTION 'Voucher must be in pending status to pay (current: %)', v_voucher.status;
  END IF;
  
  FOR line IN 
    SELECT * FROM payroll_voucher_lines
    WHERE voucher_id = p_voucher_id AND is_included = true
  LOOP
    -- Skip if no amount
    IF COALESCE(line.total_amount, 0) <= 0 THEN
       CONTINUE;
    END IF;
    
    -- Validate salary account
    IF line.salary_account_id IS NULL THEN
       RAISE EXCEPTION 'Employee % has missing Salary Account. Please check employee settings.', line.employee_name;
    END IF;

    -- Use the explicit IDs from the line
    v_pay_method_id := line.payment_method_id;
    v_pay_account_id := line.payment_account_id;
    
    -- Fallback logic only if IDs are missing (Legacy Support or UI didn't set them)
    IF v_pay_method_id IS NULL THEN
        -- Try to resolve from text string if possible, or error out
        IF line.payment_method = 'cash' THEN
           SELECT id INTO v_pay_method_id FROM payment_methods WHERE name ILIKE '%efectivo%' OR name ILIKE '%cash%' LIMIT 1;
           SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1101%' LIMIT 1;
        ELSIF line.payment_method = 'transfer' THEN
           SELECT id INTO v_pay_method_id FROM payment_methods WHERE name ILIKE '%transf%' LIMIT 1;
           SELECT id INTO v_pay_account_id FROM accounts WHERE code LIKE '1102%' LIMIT 1;
        END IF;
    END IF;

    -- Generate Expense Number
    SELECT COALESCE(MAX(SUBSTRING(expense_number FROM '[0-9]+$')::INT), 0) + 1
    INTO v_expense_seq
    FROM expenses
    WHERE tenant_id = line.tenant_id;
    
    -- Insert Expense Header
    INSERT INTO expenses (
      tenant_id,
      expense_number,
      category_id,
      liability_account_id, 
      payment_account_id,
      payment_method_id,
      document_type,
      subtotal,
      tax_amount,
      total_amount,
      issue_date,
      reference,
      notes,
      posting_status,
      payment_status,
      created_by,
      paid_at
    ) VALUES (
      line.tenant_id,
      'GTO-' || LPAD(v_expense_seq::TEXT, 5, '0'),
      NULL,
      NULL,
      v_pay_account_id,
      v_pay_method_id,
      'ticket',
      line.total_amount,
      0,
      line.total_amount,
      CURRENT_DATE,
      'Semana ' || COALESCE(v_voucher.period_label, '') || ' - ' || v_voucher.voucher_number,
      'Pago de salario: ' || line.employee_name,
      'posted',
      'paid',
      auth.uid(),
      NOW()
    )
    RETURNING id INTO v_expense_id;
    
    -- Insert Expense Line (This is what actually records the expense against the 6101 account)
    INSERT INTO expense_lines (
        tenant_id,
        expense_id,
        line_index,
        account_id,
        account_code,
        account_name,
        description,
        quantity,
        unit_price,
        subtotal,
        tax_rate,
        tax_amount,
        total
    ) VALUES (
        line.tenant_id,
        v_expense_id,
        0, -- First line
        line.salary_account_id,
        v_acc_code,
        v_acc_name,
        'Salario: ' || line.employee_name,
        1,
        line.total_amount,
        line.total_amount,
        0,
        0,
        line.total_amount
    );

    -- Link expense to voucher line
    UPDATE payroll_voucher_lines
    SET expense_id = v_expense_id
    WHERE id = line.id;
    
    v_lines_processed := v_lines_processed + 1;
  END LOOP;
  
  IF v_lines_processed = 0 THEN
      RAISE EXCEPTION 'No valid lines to pay.';
  END IF;
  
  -- Mark voucher as paid
  UPDATE payroll_vouchers
  SET status = 'paid',
      paid_at = now(),
      paid_by = auth.uid()
  WHERE id = p_voucher_id;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
