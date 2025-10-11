-- =====================================================
-- Fix Purchase Invoice Workflow Issues
-- =====================================================
-- This script fixes:
-- 1. Re-activation after reversal (creates new entry, not just reversal)
-- 2. Payment journal entries when marking as paid
-- 3. Proper tracking of payment records
-- =====================================================

-- =====================================================
-- Step 1: Create purchase_payments table
-- =====================================================
CREATE TABLE IF NOT EXISTS purchase_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  invoice_number TEXT,
  supplier_name TEXT,
  method TEXT NOT NULL DEFAULT 'transfer'
    CHECK (method IN ('cash', 'card', 'transfer', 'check', 'other')),
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  reference TEXT,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_purchase_payments_invoice_id
  ON purchase_payments(invoice_id);

CREATE INDEX IF NOT EXISTS idx_purchase_payments_date
  ON purchase_payments(date);

-- =====================================================
-- Step 2: Update purchase_invoices table with payment tracking
-- =====================================================
ALTER TABLE purchase_invoices
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS balance NUMERIC(12,2) NOT NULL DEFAULT 0;

-- Initialize balance for existing invoices
UPDATE purchase_invoices
SET balance = total - COALESCE(paid_amount, 0)
WHERE balance != (total - COALESCE(paid_amount, 0));

-- =====================================================
-- Step 3: Fix journal entry creation to handle re-activation
-- =====================================================
CREATE OR REPLACE FUNCTION create_purchase_invoice_journal_entry(
  invoice_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  invoice_rec RECORD;
  entry_id UUID;
  inventory_account_id UUID;
  expense_account_id UUID;
  iva_account_id UUID;
  ap_account_id UUID;
  existing_entry_status TEXT;
BEGIN
  -- Get invoice details
  SELECT * INTO invoice_rec
  FROM purchase_invoices
  WHERE id = invoice_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase invoice % not found', invoice_id;
  END IF;
  
  -- Skip if draft or cancelled
  IF invoice_rec.status IN ('draft', 'cancelled') THEN
    RAISE NOTICE 'Skipping journal entry for % invoice', invoice_rec.status;
    RETURN NULL;
  END IF;
  
  -- Check if entry already exists and get its status
  SELECT status INTO existing_entry_status
  FROM journal_entries
  WHERE source_module = 'purchase_invoice'
    AND source_reference = invoice_id::text
    AND status = 'posted'  -- Only check for active entries
  LIMIT 1;
  
  IF existing_entry_status IS NOT NULL THEN
    RAISE NOTICE 'Active journal entry already exists for invoice %', invoice_rec.invoice_number;
    RETURN NULL;
  END IF;
  
  -- Find required accounts
  SELECT id INTO inventory_account_id
  FROM accounts
  WHERE code = '1105'
  LIMIT 1;
  
  IF inventory_account_id IS NULL THEN
    SELECT id INTO inventory_account_id
    FROM accounts
    WHERE name ILIKE '%inventario%' AND code NOT IN ('1150', '1155')
    LIMIT 1;
  END IF;
  
  IF inventory_account_id IS NULL THEN
    SELECT id INTO expense_account_id
    FROM accounts
    WHERE code = '5101'
    LIMIT 1;
  END IF;
  
  SELECT id INTO iva_account_id
  FROM accounts
  WHERE code IN ('1180', '1107')
  LIMIT 1;
  
  SELECT id INTO ap_account_id
  FROM accounts
  WHERE code IN ('2100', '2101')
  LIMIT 1;
  
  IF inventory_account_id IS NULL THEN
    inventory_account_id := expense_account_id;
  END IF;
  
  IF inventory_account_id IS NULL THEN
    RAISE EXCEPTION 'Inventory/Expense account not found';
  END IF;
  
  IF ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Accounts Payable account not found';
  END IF;
  
  -- Create journal entry
  entry_id := gen_random_uuid();
  
  INSERT INTO journal_entries (
    id,
    entry_number,
    date,
    description,
    source_module,
    source_reference,
    type,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  )
  VALUES (
    entry_id,
    'COMP-' || invoice_rec.invoice_number,
    invoice_rec.date,
    'Compra: ' || COALESCE(invoice_rec.supplier_name, 'Proveedor') || ' - ' || invoice_rec.invoice_number,
    'purchase_invoice',
    invoice_id::text,
    'purchase',
    'posted',
    invoice_rec.total,
    invoice_rec.total,
    NOW(),
    NOW()
  );
  
  -- Debit: Inventory/Expense (subtotal)
  INSERT INTO journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    debit_amount,
    credit_amount,
    description,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    inventory_account_id,
    a.code,
    a.name,
    invoice_rec.subtotal,
    0,
    'Compra de inventario/gastos',
    NOW(),
    NOW()
  FROM accounts a
  WHERE a.id = inventory_account_id;
  
  -- Debit: IVA Crédito Fiscal
  IF iva_account_id IS NOT NULL AND invoice_rec.iva_amount > 0 THEN
    INSERT INTO journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      debit_amount,
      credit_amount,
      description,
      created_at,
      updated_at
    )
    SELECT
      gen_random_uuid(),
      entry_id,
      iva_account_id,
      a.code,
      a.name,
      invoice_rec.iva_amount,
      0,
      'IVA Crédito Fiscal',
      NOW(),
      NOW()
    FROM accounts a
    WHERE a.id = iva_account_id;
  END IF;
  
  -- Credit: Accounts Payable (total)
  INSERT INTO journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    debit_amount,
    credit_amount,
    description,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    ap_account_id,
    a.code,
    a.name,
    0,
    invoice_rec.total,
    'Cuenta por pagar: ' || COALESCE(invoice_rec.supplier_name, 'Proveedor'),
    NOW(),
    NOW()
  FROM accounts a
  WHERE a.id = ap_account_id;
  
  RAISE NOTICE 'Created journal entry % for purchase invoice %',
    entry_id, invoice_rec.invoice_number;
  
  RETURN entry_id;
END;
$$;

-- =====================================================
-- Step 4: Create function to generate payment journal entry
-- =====================================================
CREATE OR REPLACE FUNCTION create_purchase_payment_journal_entry(
  payment_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  payment_rec RECORD;
  entry_id UUID;
  cash_account_id UUID;
  ap_account_id UUID;
BEGIN
  -- Get payment details
  SELECT pp.*, pi.invoice_number, pi.supplier_name
  INTO payment_rec
  FROM purchase_payments pp
  JOIN purchase_invoices pi ON pi.id = pp.invoice_id
  WHERE pp.id = payment_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase payment % not found', payment_id;
  END IF;
  
  -- Check if entry already exists
  IF EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_module = 'purchase_payment'
      AND source_reference = payment_id::text
  ) THEN
    RAISE NOTICE 'Journal entry already exists for payment %', payment_id;
    RETURN NULL;
  END IF;
  
  -- Find cash/bank account based on payment method
  IF payment_rec.method IN ('transfer', 'check') THEN
    SELECT id INTO cash_account_id
    FROM accounts
    WHERE code = '1101' OR (name ILIKE '%banco%' AND type = 'asset')
    LIMIT 1;
  ELSE
    SELECT id INTO cash_account_id
    FROM accounts
    WHERE code = '1100' OR (name ILIKE '%caja%' AND type = 'asset')
    LIMIT 1;
  END IF;
  
  -- Find accounts payable
  SELECT id INTO ap_account_id
  FROM accounts
  WHERE code IN ('2100', '2101')
  LIMIT 1;
  
  IF cash_account_id IS NULL THEN
    RAISE EXCEPTION 'Cash/Bank account not found';
  END IF;
  
  IF ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Accounts Payable account not found';
  END IF;
  
  -- Create journal entry
  entry_id := gen_random_uuid();
  
  INSERT INTO journal_entries (
    id,
    entry_number,
    date,
    description,
    source_module,
    source_reference,
    type,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  )
  VALUES (
    entry_id,
    'PAGO-' || COALESCE(payment_rec.invoice_number, payment_rec.invoice_id::text),
    payment_rec.date,
    'Pago: ' || COALESCE(payment_rec.supplier_name, 'Proveedor') || ' - ' || COALESCE(payment_rec.invoice_number, ''),
    'purchase_payment',
    payment_id::text,
    'payment',
    'posted',
    payment_rec.amount,
    payment_rec.amount,
    NOW(),
    NOW()
  );
  
  -- Debit: Accounts Payable (reduces liability)
  INSERT INTO journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    debit_amount,
    credit_amount,
    description,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    ap_account_id,
    a.code,
    a.name,
    payment_rec.amount,
    0,
    'Pago a proveedor',
    NOW(),
    NOW()
  FROM accounts a
  WHERE a.id = ap_account_id;
  
  -- Credit: Cash/Bank (reduces asset)
  INSERT INTO journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    debit_amount,
    credit_amount,
    description,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    cash_account_id,
    a.code,
    a.name,
    0,
    payment_rec.amount,
    'Pago ' || payment_rec.method || ': ' || COALESCE(payment_rec.reference, ''),
    NOW(),
    NOW()
  FROM accounts a
  WHERE a.id = cash_account_id;
  
  RAISE NOTICE 'Created payment journal entry % for payment %',
    entry_id, payment_id;
  
  RETURN entry_id;
END;
$$;

-- =====================================================
-- Step 5: Function to recalculate invoice payments
-- =====================================================
CREATE OR REPLACE FUNCTION recalculate_purchase_invoice_payments(
  p_invoice_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_total NUMERIC(12,2);
  v_balance NUMERIC(12,2);
  v_new_status TEXT;
BEGIN
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;
  
  IF NOT FOUND THEN
    RETURN;
  END IF;
  
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total
  FROM purchase_payments
  WHERE invoice_id = p_invoice_id;
  
  v_balance := GREATEST(COALESCE(v_invoice.total, 0) - v_total, 0);
  
  -- Determine new status
  IF v_invoice.status = 'cancelled' THEN
    v_new_status := v_invoice.status;
  ELSIF v_invoice.status = 'draft' AND v_total = 0 THEN
    v_new_status := 'draft';
  ELSIF v_total >= COALESCE(v_invoice.total, 0) THEN
    v_new_status := 'paid';
  ELSIF v_total > 0 THEN
    v_new_status := 'received';
  ELSE
    v_new_status := v_invoice.status;
  END IF;
  
  UPDATE purchase_invoices
  SET paid_amount = v_total,
      balance = v_balance,
      status = v_new_status,
      updated_at = NOW()
  WHERE id = p_invoice_id;
END;
$$;

-- =====================================================
-- Step 6: Trigger for purchase_payments changes
-- =====================================================
CREATE OR REPLACE FUNCTION handle_purchase_payment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM recalculate_purchase_invoice_payments(NEW.invoice_id);
    PERFORM create_purchase_payment_journal_entry(NEW.id);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM recalculate_purchase_invoice_payments(NEW.invoice_id);
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM recalculate_purchase_invoice_payments(OLD.invoice_id);
    -- TODO: Reverse the journal entry
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS purchase_payment_change_trigger ON purchase_payments;

CREATE TRIGGER purchase_payment_change_trigger
  AFTER INSERT OR UPDATE OR DELETE ON purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_payment_change();

-- =====================================================
-- Step 7: Trigger for automatic payment when marked as paid
-- =====================================================
CREATE OR REPLACE FUNCTION handle_purchase_invoice_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  payment_exists BOOLEAN;
BEGIN
  -- Only handle status change to 'paid'
  IF TG_OP = 'UPDATE' AND OLD.status != 'paid' AND NEW.status = 'paid' THEN
    -- Check if payment already exists
    SELECT EXISTS (
      SELECT 1 FROM purchase_payments
      WHERE invoice_id = NEW.id
    ) INTO payment_exists;
    
    -- If no payment exists, create one automatically
    IF NOT payment_exists AND NEW.balance > 0 THEN
      INSERT INTO purchase_payments (
        invoice_id,
        invoice_number,
        supplier_name,
        method,
        amount,
        date,
        notes
      )
      VALUES (
        NEW.id,
        NEW.invoice_number,
        NEW.supplier_name,
        'transfer',
        NEW.balance,
        NOW(),
        'Pago automático al marcar como pagada'
      );
      
      RAISE NOTICE 'Created automatic payment for invoice %', NEW.invoice_number;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS purchase_invoice_paid_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_paid_trigger
  AFTER UPDATE OF status ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_invoice_paid();

-- =====================================================
-- Step 8: Update timestamp trigger for purchase_payments
-- =====================================================
DROP TRIGGER IF EXISTS set_purchase_payments_updated_at ON purchase_payments;

CREATE TRIGGER set_purchase_payments_updated_at
  BEFORE UPDATE ON purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION set_updated_at();

-- =====================================================
-- Success message
-- =====================================================
DO $$
BEGIN
  RAISE NOTICE '✅ Purchase invoice workflow fixes applied successfully!';
  RAISE NOTICE '   - Re-activation now creates new journal entries';
  RAISE NOTICE '   - Payment journal entries are created automatically';
  RAISE NOTICE '   - Purchase payments table created';
END $$;
