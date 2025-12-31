-- Migration: Add employee salary and payment fields
-- Date: 2025-12-31

-- Add salary and payment configuration fields to employees table
ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS hourly_rate NUMERIC(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS preferred_payment_method TEXT DEFAULT 'transfer',
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_type TEXT;

-- Add constraints
DO $$ 
BEGIN
  -- Check constraint for payment method
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'employees_payment_method_check'
  ) THEN
    ALTER TABLE employees 
      ADD CONSTRAINT employees_payment_method_check 
      CHECK (preferred_payment_method IS NULL OR preferred_payment_method IN ('cash', 'transfer', 'check'));
  END IF;
  
  -- Check constraint for bank account type
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'employees_bank_account_type_check'
  ) THEN
    ALTER TABLE employees 
      ADD CONSTRAINT employees_bank_account_type_check 
      CHECK (bank_account_type IS NULL OR bank_account_type IN ('checking', 'savings', 'vista'));
  END IF;
END $$;

-- ============================================================================
-- RPC: Get comprehensive employee hours summary
-- Returns aggregated attendance statistics for an employee over a date range
-- ============================================================================
CREATE OR REPLACE FUNCTION get_employee_hours_summary(
  p_employee_id UUID,
  p_start_date DATE,
  p_end_date DATE
) RETURNS JSON AS $$
DECLARE
  v_result JSON;
  v_expected_start TIME := '09:00:00';
  v_expected_end TIME := '18:00:00';
BEGIN
  SELECT json_build_object(
    'total_days_worked', COUNT(*),
    'total_hours', COALESCE(SUM(worked_hours), 0),
    'total_overtime', COALESCE(SUM(overtime_hours), 0),
    'total_break_minutes', COALESCE(SUM(break_minutes), 0),
    'average_hours_per_day', ROUND(COALESCE(AVG(worked_hours), 0)::numeric, 2),
    'earliest_check_in', MIN(check_in::time),
    'latest_check_out', MAX(check_out::time),
    'days_with_overtime', COUNT(*) FILTER (WHERE COALESCE(overtime_hours, 0) > 0),
    'late_arrivals', COUNT(*) FILTER (WHERE check_in::time > v_expected_start + INTERVAL '30 minutes'),
    'early_departures', COUNT(*) FILTER (WHERE check_out IS NOT NULL AND check_out::time < v_expected_end - INTERVAL '30 minutes'),
    'perfect_attendance_days', COUNT(*) FILTER (WHERE COALESCE(worked_hours, 0) >= 8),
    'short_days', COUNT(*) FILTER (WHERE COALESCE(worked_hours, 0) < 8 AND COALESCE(worked_hours, 0) > 0)
  ) INTO v_result
  FROM attendances
  WHERE employee_id = p_employee_id
    AND check_in >= p_start_date
    AND check_in < p_end_date + INTERVAL '1 day'
    AND status IN ('completed', 'approved');
  
  RETURN COALESCE(v_result, '{}'::json);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_employee_hours_summary(UUID, DATE, DATE) TO authenticated;

COMMENT ON FUNCTION get_employee_hours_summary IS 
  'Returns comprehensive attendance statistics for an employee over a date range. 
   Includes total hours, overtime, late arrivals, early departures, and more.';
