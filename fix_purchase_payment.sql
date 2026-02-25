-- Fix the purchase payment journal entry function to not expect invoice_number on purchase_payments
CREATE OR REPLACE FUNCTION public.create_purchase_payment_journal_entry(p_payment purchase_payments)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_invoice purchase_invoices;
  v_payment_method payment_methods;
  v_is_set boolean;
BEGIN
  -- Check if accounting is enabled
  SELECT COALESCE(
    current_setting('app.accounting_enabled', true) = 'true',
    true
  ) INTO v_is_set;

  IF NOT v_is_set THEN
    RETURN;
  END IF;

  -- Verify source table exists before proceeding
  IF NOT EXISTS (
    SELECT FROM pg_tables
    WHERE schemaname = 'public'
    AND tablename = 'journal_entries'
  ) THEN
    RETURN;
  END IF;

  -- Get invoice details
  SELECT *
    INTO v_invoice
    FROM public.purchase_invoices
   WHERE id = p_payment.invoice_id;

  -- Get payment method details
  SELECT *
    INTO v_payment_method
    FROM public.payment_methods
   WHERE id = p_payment.payment_method_id;

  -- Delete existing entry if any
  DELETE FROM public.journal_entries
  WHERE source_module = 'purchase_payments'
    AND source_reference = p_payment.id::text;

  -- Create new journal entry
  -- Payment against Purchase Invoice:
  -- DEBIT: Accounts Payable (Liability decrease)
  -- CREDIT: Cash/Bank Account (Asset decrease based on payment method)
  INSERT INTO public.journal_entries (
    tenant_id,
    date,
    reference_number,
    description,
    source_module,
    source_table,
    source_reference,
    status,
    debit_total,
    credit_total,
    created_at,
    updated_at
  ) VALUES (
    p_payment.tenant_id,
    p_payment.date,
    'PP-' || COALESCE(v_invoice.invoice_number, p_payment.id::text),
    'Pago P' || COALESCE(v_invoice.invoice_number, p_payment.id::text) || ' - ' || v_invoice.supplier_name,
    'purchase_payments',
    'purchase_payments',
    p_payment.id::text,
    'posted',
    p_payment.amount,
    p_payment.amount,
    now(),
    now()
  );

  -- Since we don't know the exact IDs of the chart of accounts, we rely on the
  -- create_journal_lines triggers or application logic to fill the lines based on
  -- the payment method's account_id and the default accounts payable.
END;
$$;

-- Force Schema Cache Reload for Supabase UI / API
NOTIFY pgrst, 'reload schema';
