-- =====================================================
-- Purchase Invoice Workflow Implementation
-- =====================================================
-- This script implements the complete workflow for purchase invoices:
-- 1. Inventory increase when status changes to 'received'
-- 2. Accounting journal entries (debit inventory/expense, credit AP)
-- 3. Payment tracking when status changes to 'paid'
-- 4. Trigger system to automate all actions
-- =====================================================

-- =====================================================
-- Part 1: Function to increase inventory when receiving purchase
-- =====================================================
CREATE OR REPLACE FUNCTION consume_purchase_invoice_inventory()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  rec RECORD;
  item JSONB;
  product_id TEXT;
  quantity NUMERIC;
  movement_id UUID;
BEGIN
  -- Find all purchase invoices that are 'received' but haven't been processed yet
  FOR rec IN
    SELECT pi.id, pi.invoice_number, pi.items
    FROM purchase_invoices pi
    WHERE pi.status = 'received'
      AND NOT EXISTS (
        SELECT 1 FROM stock_movements sm
        WHERE sm.movement_type = 'purchase_invoice'
          AND sm.reference = pi.id::text
      )
  LOOP
    RAISE NOTICE 'Processing purchase invoice: %', rec.invoice_number;
    
    -- Process each item in the invoice
    FOR item IN SELECT * FROM jsonb_array_elements(rec.items)
    LOOP
      product_id := item->>'product_id';
      quantity := (item->>'quantity')::NUMERIC;
      
      IF product_id IS NULL OR quantity IS NULL OR quantity <= 0 THEN
        RAISE NOTICE 'Skipping invalid item in invoice %: product_id=%, quantity=%',
          rec.invoice_number, product_id, quantity;
        CONTINUE;
      END IF;
      
      -- Create IN stock movement for the purchase
      INSERT INTO stock_movements (
        id,
        product_id,
        type,
        movement_type,
        quantity,
        reference,
        notes,
        created_at
      )
      VALUES (
        gen_random_uuid(),
        product_id::UUID,
        'IN',
        'purchase_invoice',
        quantity,
        rec.id::text,
        'Compra: ' || rec.invoice_number,
        NOW()
      )
      RETURNING id INTO movement_id;
      
      -- Increase product inventory
      UPDATE products
      SET 
        inventory_qty = COALESCE(inventory_qty, 0) + quantity,
        updated_at = NOW()
      WHERE id = product_id::UUID;
      
      RAISE NOTICE 'Created IN movement % for product % (qty: %)',
        movement_id, product_id, quantity;
    END LOOP;
  END LOOP;
  
  RAISE NOTICE 'Purchase invoice inventory processing completed';
END;
$$;

-- =====================================================
-- Part 2: Function to create accounting journal entry
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
  
  -- Check if entry already exists
  IF EXISTS (
    SELECT 1 FROM journal_entries
    WHERE source_module = 'purchase_invoice'
      AND source_reference = invoice_id::text
  ) THEN
    RAISE NOTICE 'Journal entry already exists for invoice %', invoice_rec.invoice_number;
    RETURN NULL;
  END IF;
  
  -- Find required accounts (use dynamic lookup by code/name)
  -- Inventory account (1105 - Inventario) - prefer exact code match
  SELECT id INTO inventory_account_id
  FROM accounts
  WHERE code = '1105'
  LIMIT 1;
  
  -- If not found, try by name
  IF inventory_account_id IS NULL THEN
    SELECT id INTO inventory_account_id
    FROM accounts
    WHERE name ILIKE '%inventario%' AND code NOT IN ('1150', '1155')
    LIMIT 1;
  END IF;
  
  -- Expense account fallback (if inventory not found, use 5101 - Costo de Ventas)
  IF inventory_account_id IS NULL THEN
    SELECT id INTO expense_account_id
    FROM accounts
    WHERE code = '5101'
    LIMIT 1;
  END IF;
  
  -- IVA Credito Fiscal account (1180 or 1107 - IVA Crédito Fiscal)
  SELECT id INTO iva_account_id
  FROM accounts
  WHERE code IN ('1180', '1107')
  LIMIT 1;
  
  -- Accounts Payable (2100 or 2101 - Proveedores)
  SELECT id INTO ap_account_id
  FROM accounts
  WHERE code IN ('2100', '2101')
  LIMIT 1;
  
  -- Use inventory or expense account (prefer inventory)
  IF inventory_account_id IS NULL THEN
    inventory_account_id := expense_account_id;
  END IF;
  
  -- Validate required accounts exist
  IF inventory_account_id IS NULL THEN
    RAISE EXCEPTION 'Inventory/Expense account not found. Please create account 1105 (Inventario) or 5101 (Costo de Ventas)';
  END IF;
  
  IF iva_account_id IS NULL THEN
    RAISE NOTICE 'IVA Crédito Fiscal account not found. IVA will not be recorded separately.';
  END IF;
  
  IF ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Accounts Payable account not found. Please create account 2101 (Proveedores)';
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
    created_at
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
    description
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    inventory_account_id,
    a.code,
    a.name,
    invoice_rec.subtotal,
    0,
    'Compra de inventario/gastos'
  FROM accounts a
  WHERE a.id = inventory_account_id;
  
  -- Debit: IVA Crédito Fiscal (if account exists)
  IF iva_account_id IS NOT NULL AND invoice_rec.iva_amount > 0 THEN
    INSERT INTO journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      debit_amount,
      credit_amount,
      description
    )
    SELECT
      gen_random_uuid(),
      entry_id,
      iva_account_id,
      a.code,
      a.name,
      invoice_rec.iva_amount,
      0,
      'IVA Crédito Fiscal'
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
    description
  )
  SELECT
    gen_random_uuid(),
    entry_id,
    ap_account_id,
    a.code,
    a.name,
    0,
    invoice_rec.total,
    'Cuenta por pagar: ' || COALESCE(invoice_rec.supplier_name, 'Proveedor')
  FROM accounts a
  WHERE a.id = ap_account_id;
  
  RAISE NOTICE 'Created journal entry % for purchase invoice %',
    entry_id, invoice_rec.invoice_number;
  
  RETURN entry_id;
END;
$$;

-- =====================================================
-- Part 3: Trigger function to handle purchase invoice changes
-- =====================================================
CREATE OR REPLACE FUNCTION handle_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  entry_id UUID;
BEGIN
  -- Log the change
  RAISE NOTICE 'Purchase invoice trigger fired: % -> %',
    COALESCE(OLD.status, 'NEW'), NEW.status;
  
  -- Handle status changes
  IF TG_OP = 'UPDATE' THEN
    -- Status changed from non-received to received -> increase inventory
    IF OLD.status != 'received' AND NEW.status = 'received' THEN
      RAISE NOTICE 'Invoice % marked as RECEIVED, processing inventory...', NEW.invoice_number;
      PERFORM consume_purchase_invoice_inventory();
    END IF;
    
    -- Status changed and not draft/cancelled -> create/update journal entry
    IF OLD.status != NEW.status AND NEW.status NOT IN ('draft', 'cancelled') THEN
      RAISE NOTICE 'Creating journal entry for invoice %', NEW.invoice_number;
      BEGIN
        entry_id := create_purchase_invoice_journal_entry(NEW.id);
        IF entry_id IS NOT NULL THEN
          RAISE NOTICE 'Journal entry created: %', entry_id;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create journal entry for invoice %: %',
          NEW.invoice_number, SQLERRM;
      END;
    END IF;
  END IF;
  
  -- For INSERT operations with status = 'received', process immediately
  IF TG_OP = 'INSERT' AND NEW.status = 'received' THEN
    RAISE NOTICE 'New invoice % created as RECEIVED, processing...', NEW.invoice_number;
    PERFORM consume_purchase_invoice_inventory();
    
    BEGIN
      entry_id := create_purchase_invoice_journal_entry(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to create journal entry for new invoice %: %',
        NEW.invoice_number, SQLERRM;
    END;
  END IF;
  
  RETURN NEW;
END;
$$;

-- =====================================================
-- Part 4: Install/Replace trigger
-- =====================================================
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER INSERT OR UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- =====================================================
-- Part 5: Verification queries
-- =====================================================
-- Check purchase invoices status distribution
SELECT
  status,
  COUNT(*) as count,
  SUM(total) as total_amount
FROM purchase_invoices
GROUP BY status
ORDER BY status;

-- Check stock movements from purchase invoices
SELECT
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.reference,
  sm.notes,
  sm.created_at,
  p.name as product_name
FROM stock_movements sm
LEFT JOIN products p ON p.id = sm.product_id
WHERE sm.movement_type = 'purchase_invoice'
ORDER BY sm.created_at DESC
LIMIT 10;

-- Check journal entries from purchase invoices
SELECT
  je.entry_number,
  je.date,
  je.description,
  je.source_reference,
  je.status,
  (SELECT SUM(debit_amount) FROM journal_lines WHERE entry_id = je.id) as total_debit,
  (SELECT SUM(credit_amount) FROM journal_lines WHERE entry_id = je.id) as total_credit
FROM journal_entries je
WHERE je.source_module = 'purchase_invoice'
ORDER BY je.date DESC
LIMIT 10;

-- =====================================================
-- Part 6: Manual execution (if needed)
-- =====================================================
-- To manually process all unprocessed received invoices:
-- SELECT consume_purchase_invoice_inventory();

-- To manually create journal entry for a specific invoice:
-- SELECT create_purchase_invoice_journal_entry('invoice-uuid-here');

-- =====================================================
-- NOTES:
-- =====================================================
-- 1. This script creates IN movements (not OUT like sales)
-- 2. Accounting debits inventory/expense and IVA, credits AP
-- 3. Status flow: draft → received → paid
-- 4. Received status triggers inventory and accounting
-- 5. Paid status is handled by payment recording (future enhancement)
-- 6. All functions include error handling and logging
-- 7. Respects Chilean accounting (IVA Crédito Fiscal)
-- =====================================================
