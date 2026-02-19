-- Fix: Revert sales_invoice number padding from 6 digits back to 5 digits.
-- The previous migration (20260211150000_fix_get_next_document_number.sql)
-- accidentally set v_digits := 6 for sales_invoice, producing FV-000367 instead of FV-00367.
-- This migration:
--   1. Renames existing FV-000XXX invoice numbers to FV-00XXX
--   2. Restores the get_next_document_number function to use uniform 5-digit padding

-- =========================================================
-- STEP 1: Rename already-created 6-digit invoice numbers
-- Pattern: FV-0NNNNN (6 digit) → FV-NNNNN (5 digit)
-- Only touches invoices where format is exactly FV-0DDDDD (6 digits total)
-- =========================================================
UPDATE public.sales_invoices
SET invoice_number = 'FV-' || substring(invoice_number FROM 5)
WHERE invoice_number ~ '^FV-0\d{5}$';

-- Verify: SELECT invoice_number FROM public.sales_invoices WHERE invoice_number ~ '^FV-' ORDER BY invoice_number;


CREATE OR REPLACE FUNCTION public.get_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text DEFAULT NULL
) RETURNS text AS $$
DECLARE
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_last_number text;
  v_next_seq integer;
  v_digits integer := 5; -- Default padding for all types: e.g. FV-00001
BEGIN
  -- Determine table and prefix based on type
  CASE p_document_type
    WHEN 'sales_invoice' THEN
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
      v_prefix := COALESCE(p_prefix, 'FV');
      -- v_digits stays at 5 (removed the erroneous := 6 override)
    WHEN 'purchase_invoice' THEN
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
      v_prefix := COALESCE(p_prefix, 'FC');
    WHEN 'expense' THEN
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
      v_prefix := COALESCE(p_prefix, 'GTO');
    WHEN 'journal_entry' THEN
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
      v_prefix := COALESCE(p_prefix, 'AS');
    WHEN 'mechanic_job' THEN
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
      v_prefix := COALESCE(p_prefix, 'PG');
    WHEN 'sales_payment' THEN
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
      v_prefix := COALESCE(p_prefix, 'PV');
    WHEN 'purchase_payment' THEN
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
      v_prefix := COALESCE(p_prefix, 'PC');
    WHEN 'stock_adjustment' THEN
      v_table_name := 'stock_adjustments';
      v_column_name := 'adjustment_number';
      v_prefix := COALESCE(p_prefix, 'AJ');
    ELSE
      RAISE EXCEPTION 'Unknown document type: %', p_document_type;
  END CASE;

  -- Dynamic query to find the max number matching the pattern
  -- Pattern: prefix-digits (e.g. FV-00035)
  -- Uses regexp to extract the number part
  -- We cast to INTEGER to sort numerically (so 10 > 2)
  EXECUTE format(
    'SELECT MAX(CAST(substring(%I FROM %L) AS INTEGER)) 
     FROM public.%I 
     WHERE tenant_id = %L 
       AND %I ~ %L',
    v_column_name, 
    '^' || v_prefix || '-(\d+)$',
    v_table_name,
    p_tenant_id,
    v_column_name,
    '^' || v_prefix || '-\d+$'
  ) INTO v_next_seq;

  -- Prepare next sequence
  v_next_seq := COALESCE(v_next_seq, 0) + 1;

  -- Format result with 5-digit zero-padding
  RETURN v_prefix || '-' || lpad(v_next_seq::text, v_digits, '0');
END;
$$ LANGUAGE plpgsql;


-- Also fix preview_next_document_number to be consistent
CREATE OR REPLACE FUNCTION public.preview_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text DEFAULT NULL
) RETURNS text AS $$
DECLARE
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_next_seq integer;
  v_digits integer := 5;
BEGIN
  CASE p_document_type
    WHEN 'sales_invoice' THEN
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
      v_prefix := COALESCE(p_prefix, 'FV');
    WHEN 'purchase_invoice' THEN
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
      v_prefix := COALESCE(p_prefix, 'FC');
    WHEN 'expense' THEN
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
      v_prefix := COALESCE(p_prefix, 'GTO');
    WHEN 'journal_entry' THEN
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
      v_prefix := COALESCE(p_prefix, 'AS');
    WHEN 'mechanic_job' THEN
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
      v_prefix := COALESCE(p_prefix, 'PG');
    WHEN 'sales_payment' THEN
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
      v_prefix := COALESCE(p_prefix, 'PV');
    WHEN 'purchase_payment' THEN
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
      v_prefix := COALESCE(p_prefix, 'PC');
    WHEN 'stock_adjustment' THEN
      v_table_name := 'stock_adjustments';
      v_column_name := 'adjustment_number';
      v_prefix := COALESCE(p_prefix, 'AJ');
    ELSE
      RAISE EXCEPTION 'Unknown document type: %', p_document_type;
  END CASE;

  EXECUTE format(
    'SELECT MAX(CAST(substring(%I FROM %L) AS INTEGER)) 
     FROM public.%I 
     WHERE tenant_id = %L 
       AND %I ~ %L',
    v_column_name, 
    '^' || v_prefix || '-(\d+)$',
    v_table_name,
    p_tenant_id,
    v_column_name,
    '^' || v_prefix || '-\d+$'
  ) INTO v_next_seq;

  v_next_seq := COALESCE(v_next_seq, 0) + 1;

  RETURN v_prefix || '-' || lpad(v_next_seq::text, v_digits, '0');
END;
$$ LANGUAGE plpgsql;
