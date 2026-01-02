-- ============================================================================
-- FIX: REFRACTOR PAYMENT METHOD TO USE FOREIGN KEYS (payment_methods table)
-- ============================================================================
-- This script:
-- 1. Adds `preferred_payment_method_id` to `employees` table (FK to `payment_methods`)
-- 2. Backfills the new column by matching existing text values ('cash' -> 'Efectivo', etc.)
-- 3. Updates `generate_payroll_voucher_draft` to use the new ID column

-- ----------------------------------------------------------------------------
-- 1. ADD COLUMN
-- ----------------------------------------------------------------------------
DO $$ BEGIN
  ALTER TABLE employees 
    ADD COLUMN IF NOT EXISTS preferred_payment_method_id UUID REFERENCES payment_methods(id);
EXCEPTION
  WHEN duplicate_column THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 2. BACKFILL DATA (Best Effort Matching)
-- ----------------------------------------------------------------------------
-- Match 'cash' to 'Efectivo'
UPDATE employees
SET preferred_payment_method_id = (
  SELECT id FROM payment_methods 
  WHERE name ILIKE '%efectivo%' 
  LIMIT 1
)
WHERE preferred_payment_method = 'cash' 
  AND preferred_payment_method_id IS NULL;

-- Match 'transfer' to 'Transferencia'
UPDATE employees
SET preferred_payment_method_id = (
  SELECT id FROM payment_methods 
  WHERE name ILIKE '%tansferencia%' OR name ILIKE '%bancaria%' OR name ILIKE '%Electronic%'
  LIMIT 1
)
WHERE preferred_payment_method = 'transfer'
  AND preferred_payment_method_id IS NULL;
  
-- Match 'check' to 'Cheque'
UPDATE employees
SET preferred_payment_method_id = (
  SELECT id FROM payment_methods 
  WHERE name ILIKE '%cheque%' 
  LIMIT 1
)
WHERE preferred_payment_method = 'check'
  AND preferred_payment_method_id IS NULL;

-- Fallback for any remaining active employees to a default method (usually Transferencia)
UPDATE employees
SET preferred_payment_method_id = (
  SELECT id FROM payment_methods 
  ORDER BY name 
  LIMIT 1
)
WHERE preferred_payment_method_id IS NULL;

-- ----------------------------------------------------------------------------
-- 3. UPDATE GENERATE VOUCHER FUNCTION
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
    SELECT 
      COALESCE(SUM(worked_hours), 0),
      COALESCE(SUM(overtime_hours), 0)
    INTO v_hours, v_overtime
    FROM attendances
    WHERE employee_id = emp.id
      AND check_in::DATE BETWEEN p_start_date AND p_end_date;
    
    v_rate := emp.rate;
    v_overtime_rate := v_rate * 1.5;
    v_regular_amt := v_hours * v_rate;
    v_overtime_amt := v_overtime * v_overtime_rate;
    
    -- INSERT LINE with explicit payment_method_id
    INSERT INTO payroll_voucher_lines (
      tenant_id, voucher_id, employee_id, employee_name,
      worked_hours, overtime_hours, hourly_rate, overtime_rate,
      regular_amount, overtime_amount, total_amount,
      payment_method, -- Legacy
      payment_method_id, -- NEW: Proper FK
      salary_account_id, 
      is_included
    ) VALUES (
      v_tenant_id, v_voucher_id, emp.id, 
      emp.first_name || ' ' || emp.last_name,
      v_hours, v_overtime, v_rate, v_overtime_rate,
      v_regular_amt, v_overtime_amt, v_regular_amt + v_overtime_amt,
      COALESCE(emp.preferred_payment_method::TEXT, 'transfer'), -- Keep separate purely for display fallback
      emp.preferred_payment_method_id, -- USE THE REAL ID
      emp.salary_account_id, 
      (v_hours + v_overtime > 0)
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
