-- ============================================================================
-- PAYROLL STATUS FLOW REFACTOR
-- ============================================================================
-- Fix the broken payroll status system:
-- - Rename "pending" → "confirmed"
-- - Add proper confirm_payroll_voucher RPC
-- - Add revert_payroll_payment RPC (paid → confirmed)
-- - Fix expense_number duplication issue
-- ============================================================================

-- 1. FIRST: Drop the old constraint so we can update status values
DO $$
BEGIN
  ALTER TABLE public.payroll_vouchers DROP CONSTRAINT IF EXISTS payroll_vouchers_status_check;
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN others THEN RAISE NOTICE 'Drop constraint: %', SQLERRM;
END $$;

-- 2. Rename existing "pending" records to "confirmed"
UPDATE public.payroll_vouchers
SET status = 'confirmed'
WHERE status = 'pending';

-- 3. Add the new constraint with updated status values
DO $$
BEGIN
  ALTER TABLE public.payroll_vouchers 
    ADD CONSTRAINT payroll_vouchers_status_check 
    CHECK (status IN ('draft', 'confirmed', 'paid', 'voided'));
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN duplicate_object THEN NULL; -- constraint already exists
  WHEN others THEN RAISE NOTICE 'Add constraint: %', SQLERRM;
END $$;


-- ============================================================================
-- 3. FIX: Sync expense_number_seq to prevent duplicate key errors
-- ============================================================================
DO $$
DECLARE
  v_max_num bigint;
BEGIN
  -- Get the highest existing expense number
  SELECT COALESCE(
    MAX((regexp_replace(expense_number, '^GTO-', ''))::bigint),
    0
  )
  INTO v_max_num
  FROM public.expenses
  WHERE expense_number ~ '^GTO-[0-9]+$';

  -- Set the sequence to this value (next call will return v_max_num + 1)
  PERFORM setval('expense_number_seq', v_max_num, true);
  
  RAISE NOTICE 'expense_number_seq synced to %', v_max_num;
EXCEPTION
  WHEN undefined_table THEN NULL;
  WHEN others THEN RAISE NOTICE 'expense_number_seq sync failed: %', SQLERRM;
END $$;

-- 4. Update generate_expense_number to be conflict-resistant
CREATE OR REPLACE FUNCTION public.generate_expense_number()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next bigint;
  v_number text;
  v_attempts int := 0;
BEGIN
  LOOP
    v_attempts := v_attempts + 1;
    
    -- Get next sequence value
    SELECT nextval('expense_number_seq') INTO v_next;
    v_number := format('GTO-%s', lpad(v_next::text, 5, '0'));
    
    -- Check if this number already exists
    IF NOT EXISTS (SELECT 1 FROM public.expenses WHERE expense_number = v_number) THEN
      RETURN v_number;
    END IF;
    
    -- Safety: don't loop forever
    IF v_attempts > 100 THEN
      -- Fallback to timestamp-based number
      RETURN format('GTO-%s', lpad((extract(epoch from now())::bigint % 100000)::text, 5, '0'));
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- 5. CREATE confirm_payroll_voucher RPC (draft → confirmed)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.confirm_payroll_voucher(p_voucher_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  -- Get current status
  SELECT status INTO v_status
  FROM public.payroll_vouchers
  WHERE id = p_voucher_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payroll voucher not found';
  END IF;
  
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft vouchers can be confirmed. Current status: %', v_status;
  END IF;
  
  -- Update to confirmed
  UPDATE public.payroll_vouchers
  SET status = 'confirmed',
      updated_at = now()
  WHERE id = p_voucher_id;
  
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.confirm_payroll_voucher(uuid) TO authenticated;

-- ============================================================================
-- 6. UPDATE pay_payroll_voucher to require "confirmed" status
-- ============================================================================
-- Note: The main logic is in 20260106_payroll_multi_payment_methods.sql
-- We just need to update the status check from 'pending' to 'confirmed'

CREATE OR REPLACE FUNCTION public.pay_payroll_voucher(
  p_voucher_id uuid,
  p_payment_splits jsonb DEFAULT NULL
)
RETURNS boolean
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_voucher record;
  line record;
  v_expense_id uuid;
  v_expense_number text;
  v_splits jsonb;
  v_split jsonb;
  v_split_amount numeric(14,2);
  v_total_split numeric(14,2);
  v_method_id uuid;
  v_account_id uuid;
  v_notes text;
  v_reference text;
  v_default_method_id uuid;
  v_default_account_id uuid;
BEGIN
  SELECT *
    INTO v_voucher
    FROM public.payroll_vouchers
   WHERE id = p_voucher_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voucher not found';
  END IF;

  -- CHANGED: Require 'confirmed' status instead of 'pending'
  IF v_voucher.status <> 'confirmed' THEN
    RAISE EXCEPTION 'Voucher must be in confirmed status to pay. Current status: %', v_voucher.status;
  END IF;

  FOR line IN
    SELECT *
      FROM public.payroll_voucher_lines
     WHERE voucher_id = p_voucher_id
       AND is_included = true
  LOOP
    IF COALESCE(line.total_amount, 0) <= 0 THEN
      CONTINUE;
    END IF;

    IF line.salary_account_id IS NULL THEN
      RAISE EXCEPTION 'Employee % has missing Salary Account', line.employee_name;
    END IF;

    v_reference := format('Semana %s - %s', COALESCE(v_voucher.period_label, ''), v_voucher.voucher_number);
    v_notes := format('Pago de salario: %s', line.employee_name);

    -- Determine payment splits (JSON overrides defaults)
    v_splits := NULL;
    IF p_payment_splits IS NOT NULL AND line.id IS NOT NULL THEN
      v_splits := p_payment_splits -> (line.id::text);
    END IF;

    IF v_splits IS NULL THEN
      v_splits := jsonb_build_array(
        jsonb_build_object(
          'payment_method_id', line.payment_method_id,
          'payment_account_id', line.payment_account_id,
          'amount', line.total_amount
        )
      );
    END IF;

    IF jsonb_typeof(v_splits) <> 'array' THEN
      RAISE EXCEPTION 'Invalid payment splits for employee %', line.employee_name;
    END IF;

    -- Create Expense Header
    v_expense_number := public.generate_expense_number();

    -- If there's only 1 payment method/account, store it in the header for UI convenience.
    SELECT
      nullif((v_splits->0->>'payment_method_id'), '')::uuid,
      nullif((v_splits->0->>'payment_account_id'), '')::uuid
      INTO v_method_id, v_account_id;

    INSERT INTO public.expenses (
      tenant_id,
      expense_number,
      document_type,
      subtotal,
      tax_amount,
      total_amount,
      issue_date,
      reference,
      notes,
      posting_status,
      payment_status,
      payment_method_id,
      payment_account_id,
      created_by
    ) VALUES (
      line.tenant_id,
      v_expense_number,
      'ticket',
      line.total_amount,
      0,
      line.total_amount,
      current_date,
      v_reference,
      v_notes,
      'posted',
      'pending',
      v_method_id,
      v_account_id,
      auth.uid()
    ) RETURNING id INTO v_expense_id;

    -- Link back to the payroll voucher line
    UPDATE public.payroll_voucher_lines
       SET expense_id = v_expense_id
     WHERE id = line.id;

    -- Expense line (debit salary expense account)
    INSERT INTO public.expense_lines (
      tenant_id,
      expense_id,
      line_index,
      account_id,
      description,
      quantity,
      unit_price,
      tax_amount,
      total
    ) VALUES (
      line.tenant_id,
      v_expense_id,
      0,
      line.salary_account_id,
      format('Salario: %s', line.employee_name),
      1,
      line.total_amount,
      0,
      line.total_amount
    );

    -- Fallback payment method IDs (legacy string support)
    v_default_method_id := line.payment_method_id;
    v_default_account_id := line.payment_account_id;

    IF v_default_method_id IS NULL THEN
      IF line.payment_method = 'cash' THEN
        SELECT pm.id
          INTO v_default_method_id
          FROM public.payment_methods pm
         WHERE pm.tenant_id = line.tenant_id
           AND (pm.name ILIKE '%efectivo%' OR pm.name ILIKE '%cash%')
         LIMIT 1;
      ELSE
        SELECT pm.id
          INTO v_default_method_id
          FROM public.payment_methods pm
         WHERE pm.tenant_id = line.tenant_id
           AND pm.name ILIKE '%transf%'
         LIMIT 1;
      END IF;
    END IF;

    v_total_split := 0;

    FOR v_split IN
      SELECT * FROM jsonb_array_elements(v_splits)
    LOOP
      v_split_amount := COALESCE(nullif(v_split->>'amount', '')::numeric, 0);
      IF v_split_amount <= 0 THEN
        CONTINUE;
      END IF;

      v_method_id := nullif(v_split->>'payment_method_id', '')::uuid;
      v_account_id := nullif(v_split->>'payment_account_id', '')::uuid;

      IF v_method_id IS NULL THEN
        v_method_id := v_default_method_id;
      END IF;

      IF v_account_id IS NULL THEN
        v_account_id := v_default_account_id;
      END IF;

      IF v_method_id IS NULL THEN
        RAISE EXCEPTION 'Missing payment method for employee %', line.employee_name;
      END IF;

      v_total_split := v_total_split + v_split_amount;

      INSERT INTO public.expense_payments (
        tenant_id,
        expense_id,
        payment_method_id,
        payment_account_id,
        amount,
        payment_date,
        reference,
        notes
      ) VALUES (
        line.tenant_id,
        v_expense_id,
        v_method_id,
        v_account_id,
        v_split_amount,
        now(),
        v_reference,
        v_notes
      );
    END LOOP;

    -- Ensure header totals reflect the line totals
    PERFORM public.recalculate_expense_totals(v_expense_id);

    IF abs(v_total_split - line.total_amount) > 0.01 THEN
      RAISE EXCEPTION 'Payment splits must sum to the line total for employee %', line.employee_name;
    END IF;
  END LOOP;

  UPDATE public.payroll_vouchers
     SET status = 'paid',
         paid_at = now(),
         paid_by = auth.uid(),
         updated_at = now()
   WHERE id = p_voucher_id;

  RETURN true;
END;
$$;

-- Single-arg wrapper
CREATE OR REPLACE FUNCTION public.pay_payroll_voucher(p_voucher_id uuid)
RETURNS boolean
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  PERFORM public.pay_payroll_voucher(p_voucher_id, NULL);
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.pay_payroll_voucher(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_payroll_voucher(uuid, jsonb) TO authenticated;

-- ============================================================================
-- 7. CREATE revert_payroll_payment RPC (paid → confirmed)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.revert_payroll_payment(p_voucher_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_line record;
BEGIN
  -- Get current status
  SELECT status INTO v_status
  FROM public.payroll_vouchers
  WHERE id = p_voucher_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payroll voucher not found';
  END IF;
  
  IF v_status <> 'paid' THEN
    RAISE EXCEPTION 'Only paid vouchers can have their payment reverted. Current status: %', v_status;
  END IF;
  
  -- For each line with an expense_id, delete the expense chain
  FOR v_line IN
    SELECT id, expense_id
    FROM public.payroll_voucher_lines
    WHERE voucher_id = p_voucher_id
      AND expense_id IS NOT NULL
  LOOP
    -- Delete expense_payments (this will trigger journal entry deletion via cascade/trigger)
    DELETE FROM public.expense_payments WHERE expense_id = v_line.expense_id;
    
    -- Delete expense_lines
    DELETE FROM public.expense_lines WHERE expense_id = v_line.expense_id;
    
    -- Delete journal entries linked to this expense
    DELETE FROM public.journal_entries 
    WHERE source_module = 'expenses' 
      AND source_reference = v_line.expense_id::text;
    
    -- Delete the expense itself
    DELETE FROM public.expenses WHERE id = v_line.expense_id;
    
    -- Clear the expense_id from the payroll line
    UPDATE public.payroll_voucher_lines
    SET expense_id = NULL
    WHERE id = v_line.id;
  END LOOP;
  
  -- Update voucher status back to confirmed
  UPDATE public.payroll_vouchers
  SET status = 'confirmed',
      paid_at = NULL,
      paid_by = NULL,
      updated_at = now()
  WHERE id = p_voucher_id;
  
  RAISE NOTICE 'Payroll payment reverted for voucher %', p_voucher_id;
  
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.revert_payroll_payment(uuid) TO authenticated;

-- ============================================================================
-- 8. UPDATE revert_to_draft to work with 'confirmed' status
-- ============================================================================
-- This already exists but we need to update it to check for 'confirmed' instead of 'pending'
CREATE OR REPLACE FUNCTION public.revert_payroll_to_draft(p_voucher_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  -- Get current status
  SELECT status INTO v_status
  FROM public.payroll_vouchers
  WHERE id = p_voucher_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payroll voucher not found';
  END IF;
  
  IF v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'Only confirmed vouchers can be reverted to draft. Current status: %', v_status;
  END IF;
  
  -- Update to draft
  UPDATE public.payroll_vouchers
  SET status = 'draft',
      updated_at = now()
  WHERE id = p_voucher_id;
  
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.revert_payroll_to_draft(uuid) TO authenticated;

-- Migration complete: Payroll status flow refactored successfully
