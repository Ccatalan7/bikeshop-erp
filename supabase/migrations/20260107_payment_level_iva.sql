
-- ============================================================
-- UPDATE: create_sales_payment_journal_entry()
-- Add check for deleted payments to prevent JE creation
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_sales_payment_journal_entry(p_payment public.sales_payments)
RETURNS void AS $$
DECLARE
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_iva_account_id uuid;
  v_iva_account_code text := '2105';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_description text;
  v_tenant_id uuid;
  v_net_amount numeric(15,2);
  v_iva_amount numeric(15,2);
BEGIN
  IF p_payment.invoice_id IS NULL THEN
    RETURN;
  END IF;

  -- Skip if payment is soft deleted
  IF p_payment.deleted_at IS NOT NULL THEN
    RAISE NOTICE 'create_sales_payment_journal_entry: Payment % is deleted, skipping', p_payment.id;
    RETURN;
  END IF;

  v_tenant_id := p_payment.tenant_id;

  IF v_tenant_id IS NULL THEN
    RAISE WARNING 'create_sales_payment_journal_entry: No tenant_id on payment %, skipping', p_payment.id;
    RETURN;
  END IF;

  -- Check if entry already exists
  SELECT EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE source_module = 'sales_payments'
      AND source_reference = p_payment.id::text
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Get invoice info
  SELECT id, invoice_number, customer_name, total
  INTO v_invoice
  FROM public.sales_invoices
  WHERE id = p_payment.invoice_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Get payment method and its account
  SELECT pm.id, pm.code, pm.name, a.id AS account_id, a.code AS account_code, a.name AS account_name
  INTO v_payment_method
  FROM public.payment_methods pm
  JOIN public.accounts a ON a.id = pm.account_id
  WHERE pm.id = p_payment.payment_method_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment method not found for payment %', p_payment.id;
  END IF;

  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  -- Calculate net and IVA amounts based on payment's tax treatment
  IF p_payment.tax_treatment = 'tax_included' THEN
    -- IVA is included in payment amount: net = amount / 1.19, iva = amount - net
    v_net_amount := COALESCE(p_payment.net_amount, ROUND(p_payment.amount / 1.19, 0));
    v_iva_amount := COALESCE(p_payment.iva_amount, p_payment.amount - v_net_amount);
  ELSE
    -- No tax: full amount goes to receivables
    v_net_amount := p_payment.amount;
    v_iva_amount := 0;
  END IF;

  -- Ensure accounts exist
  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    NULL
  );

  IF v_iva_amount > 0 THEN
    v_iva_account_id := public.ensure_account(
      v_tenant_id,
      v_iva_account_code,
      v_iva_account_name,
      'liability',
      'currentLiability',
      'IVA generado en ventas',
      NULL
    );
  END IF;

  v_description := format('Pago factura %s - %s', 
    COALESCE(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  -- Create journal entry
  INSERT INTO public.journal_entries (
    id, tenant_id, entry_number, entry_date, description,
    type, source_module, source_reference, status,
    total_debit, total_credit, created_at, updated_at
  ) VALUES (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    COALESCE(p_payment.date, now()),
    v_description,
    'payment',
    'sales_payments',
    p_payment.id::text,  -- Use payment ID as reference for proper deletion
    'posted',
    p_payment.amount,
    p_payment.amount,
    now(),
    now()
  );

  -- DR: Cash/Bank account (full amount)
  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    format('Cobro a %s', COALESCE(v_invoice.customer_name, 'Cliente')),
    p_payment.amount,  -- Full amount received
    0,
    now(),
    now()
  );

  -- CR: Accounts Receivable (net amount or full if no tax)
  INSERT INTO public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    format('Cobro factura %s', COALESCE(v_invoice.invoice_number, '')),
    0,
    v_net_amount,  -- Net amount (excludes IVA when tax_included)
    now(),
    now()
  );

  -- CR: IVA Débito Fiscal (only if tax included)
  IF v_iva_amount > 0 THEN
    INSERT INTO public.journal_lines (
      id, tenant_id, entry_id, account_id, account_code, account_name,
      description, debit_amount, credit_amount, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA pago %s', v_payment_method.name),
      0,
      v_iva_amount,
      now(),
      now()
    );
  END IF;

  RAISE NOTICE 'Created payment journal entry: % (net: %, iva: %)', 
    v_entry_id, v_net_amount, v_iva_amount;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.create_sales_payment_journal_entry(public.sales_payments) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_sales_payment_journal_entry(public.sales_payments) TO service_role;


-- ============================================================
-- UPDATE: handle_sales_invoice_change()
-- Add soft-delete of payments when invoice is reverted
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_sales_invoice_change()
RETURNS trigger AS $$
DECLARE
  v_old_status invoice_status;
  v_new_status invoice_status;
  v_old_posted boolean;
  v_new_posted boolean;
  v_non_posted invoice_status[] := ARRAY['draft', 'sent'];
BEGIN
  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'handle_sales_invoice_change: trigger depth > 1, returning';
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;

    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;
    
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;
    
    -- If status hasn't changed, do nothing
    if v_old_status = v_new_status then
      return NEW;
    end if;

    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      -- Both statuses are posted: restore old inventory, consume new
      raise notice 'handle_sales_invoice_change: both posted, restore and consume';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      -- Changed from posted to non-posted: restore inventory
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      -- Changed from non-posted to posted: consume inventory
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      -- Both non-posted: no inventory change
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    -- JOURNAL ENTRY AND PAYMENT HANDLING
    if v_old_posted and not v_new_posted then
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
        
      -- NEW: Soft-delete associated payments
      -- This triggers handle_sales_payment_change -> delete_sales_payment_journal_entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, soft-deleting payments';
      update public.sales_payments 
      set deleted_at = now() 
      where invoice_id = OLD.id
        and deleted_at is null; -- Only delete active payments
        
    elsif not v_old_posted and v_new_posted then
      -- Draft/Sent → Confirmed: CREATE journal entry
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);
      
    elsif v_old_posted and v_new_posted then
      -- Both posted: delete old, create new (amounts might have changed)
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      -- Both non-posted: no journal entry action
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice '🔵 handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    if not (v_old_status = any (v_non_posted)) then
      raise notice '🔵 handle_sales_invoice_change: DELETE posted invoice, restoring inventory';
      perform public.restore_sales_invoice_inventory(OLD);
      
      raise notice '🔵 handle_sales_invoice_change: DELETE posted invoice, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
    end if;

    raise notice '🔵 handle_sales_invoice_change: DELETE completed, now cascade trigger should fire';
    return OLD;
  end if;

  return NULL;
END;
$$ LANGUAGE plpgsql;
