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
  v_digits integer := 5; -- Default padding, e.g. 00001
BEGIN
  -- Determine table and prefix based on type
  CASE p_document_type
    WHEN 'sales_invoice' THEN
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
      v_prefix := COALESCE(p_prefix, 'FV');
      v_digits := 6;
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
    WHEN 'stock_adjustment' THEN
      v_table_name := 'stock_adjustments';
      v_column_name := 'adjustment_number';
      v_prefix := COALESCE(p_prefix, 'AJ');
      
    -- Add other types as needed
    ELSE
      RAISE EXCEPTION 'Unknown document type: %', p_document_type;
  END CASE;

  -- Dynamic query to find the max number matching the pattern
  -- Pattern: prefix-digits (e.g. GTO-00035)
  -- Uses regexp to extract the number part
  -- We cast to INTEGER to sort numerically (so 10 > 2)
  EXECUTE format(
    'SELECT MAX(CAST(substring(%I FROM %L) AS INTEGER)) 
     FROM public.%I 
     WHERE tenant_id = %L 
       AND %I ~ %L',
    v_column_name, 
    '^' || v_prefix || '-(\d+)$', -- Regex to match prefix + digits
    v_table_name,
    p_tenant_id,
    v_column_name,
    '^' || v_prefix || '-\d+$'
  ) INTO v_next_seq;

  -- Prepare next sequence
  v_next_seq := COALESCE(v_next_seq, 0) + 1;

  -- Format result
  RETURN v_prefix || '-' || lpad(v_next_seq::text, v_digits, '0');
END;
$$ LANGUAGE plpgsql;
