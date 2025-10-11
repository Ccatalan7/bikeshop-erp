-- =====================================================
-- Purchase Invoice Reversal Functions
-- =====================================================
-- This script adds the ability to reverse purchase invoice
-- status changes and undo their effects on inventory and accounting.
-- =====================================================

-- =====================================================
-- Function 1: Reverse Inventory (Received → Draft)
-- =====================================================
CREATE OR REPLACE FUNCTION reverse_purchase_invoice_inventory(
  invoice_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  invoice_rec RECORD;
  movement_rec RECORD;
  product_rec RECORD;
  can_reverse BOOLEAN := true;
BEGIN
  -- Get invoice details
  SELECT * INTO invoice_rec
  FROM purchase_invoices
  WHERE id = invoice_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase invoice % not found', invoice_id;
  END IF;
  
  RAISE NOTICE 'Reversing inventory for invoice %', invoice_rec.invoice_number;
  
  -- Find all stock movements for this invoice
  FOR movement_rec IN
    SELECT sm.*, p.name as product_name, p.inventory_qty
    FROM stock_movements sm
    JOIN products p ON p.id = sm.product_id
    WHERE sm.movement_type = 'purchase_invoice'
      AND sm.reference = invoice_id::text
      AND sm.type = 'IN'
  LOOP
    -- Check if we have enough inventory to reverse
    IF movement_rec.inventory_qty < movement_rec.quantity THEN
      RAISE WARNING 'Cannot fully reverse: Product % (%) has insufficient inventory. Has: %, Need: %',
        movement_rec.product_name, movement_rec.product_id, 
        movement_rec.inventory_qty, movement_rec.quantity;
      can_reverse := false;
      CONTINUE;
    END IF;
    
    -- Decrease product inventory
    UPDATE products
    SET 
      inventory_qty = inventory_qty - movement_rec.quantity,
      updated_at = NOW()
    WHERE id = movement_rec.product_id;
    
    -- Delete the stock movement
    DELETE FROM stock_movements
    WHERE id = movement_rec.id;
    
    RAISE NOTICE 'Reversed inventory for product %: -% units', 
      movement_rec.product_name, movement_rec.quantity;
  END LOOP;
  
  IF NOT can_reverse THEN
    RAISE EXCEPTION 'Cannot reverse invoice: insufficient inventory for some products';
  END IF;
  
  RAISE NOTICE 'Inventory reversal completed for invoice %', invoice_rec.invoice_number;
  RETURN true;
END;
$$;

-- =====================================================
-- Function 2: Reverse Journal Entry (Received → Draft)
-- =====================================================
CREATE OR REPLACE FUNCTION reverse_purchase_invoice_journal_entry(
  invoice_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  invoice_rec RECORD;
  entry_rec RECORD;
  reversal_entry_id UUID;
BEGIN
  -- Get invoice details
  SELECT * INTO invoice_rec
  FROM purchase_invoices
  WHERE id = invoice_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase invoice % not found', invoice_id;
  END IF;
  
  -- Find the journal entry
  SELECT * INTO entry_rec
  FROM journal_entries
  WHERE source_module = 'purchase_invoice'
    AND source_reference = invoice_id::text
  LIMIT 1;
  
  IF NOT FOUND THEN
    RAISE NOTICE 'No journal entry found for invoice %', invoice_rec.invoice_number;
    RETURN false;
  END IF;
  
  RAISE NOTICE 'Reversing journal entry % for invoice %', 
    entry_rec.entry_number, invoice_rec.invoice_number;
  
  -- Create reversing entry (debits become credits, credits become debits)
  reversal_entry_id := gen_random_uuid();
  
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
    reversal_entry_id,
    'REV-' || entry_rec.entry_number,
    NOW(),
    'REVERSO: ' || entry_rec.description,
    'purchase_invoice_reversal',
    invoice_id::text,
    'reversal',
    'posted',
    NOW()
  );
  
  -- Copy lines with reversed debits/credits
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
    reversal_entry_id,
    jl.account_id,
    jl.account_code,
    jl.account_name,
    jl.credit_amount,  -- Swap: credit becomes debit
    jl.debit_amount,   -- Swap: debit becomes credit
    'REVERSO: ' || jl.description
  FROM journal_lines jl
  WHERE jl.entry_id = entry_rec.id;
  
  -- Mark original entry as reversed (don't delete it for audit trail)
  UPDATE journal_entries
  SET 
    status = 'reversed',
    description = description || ' (REVERSADO)',
    updated_at = NOW()
  WHERE id = entry_rec.id;
  
  RAISE NOTICE 'Created reversing entry % for original entry %',
    reversal_entry_id, entry_rec.id;
  
  RETURN true;
END;
$$;

-- =====================================================
-- Function 3: Handle Backward Status Changes
-- =====================================================
CREATE OR REPLACE FUNCTION handle_purchase_invoice_reversal()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  reversed BOOLEAN;
BEGIN
  -- Only handle UPDATE operations where status changed backward
  IF TG_OP != 'UPDATE' THEN
    RETURN NEW;
  END IF;
  
  -- Received → Draft (reverse inventory and accounting)
  IF OLD.status = 'received' AND NEW.status = 'draft' THEN
    RAISE NOTICE 'Reversing invoice % from RECEIVED to DRAFT', NEW.invoice_number;
    
    BEGIN
      -- Reverse inventory first
      reversed := reverse_purchase_invoice_inventory(NEW.id);
      
      -- Then reverse accounting
      reversed := reverse_purchase_invoice_journal_entry(NEW.id);
      
      RAISE NOTICE 'Successfully reversed invoice % to DRAFT', NEW.invoice_number;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Failed to reverse invoice %: %', NEW.invoice_number, SQLERRM;
    END;
  END IF;
  
  -- Paid → Received (only status change, keep inventory/accounting)
  IF OLD.status = 'paid' AND NEW.status = 'received' THEN
    RAISE NOTICE 'Reverting invoice % from PAID to RECEIVED (no reversal needed)', 
      NEW.invoice_number;
    -- Future: remove payment records here if implemented
  END IF;
  
  -- Paid → Draft (reverse everything)
  IF OLD.status = 'paid' AND NEW.status = 'draft' THEN
    RAISE NOTICE 'Reversing invoice % from PAID to DRAFT', NEW.invoice_number;
    
    BEGIN
      -- Future: remove payment records
      
      -- Reverse inventory
      reversed := reverse_purchase_invoice_inventory(NEW.id);
      
      -- Reverse accounting
      reversed := reverse_purchase_invoice_journal_entry(NEW.id);
      
      RAISE NOTICE 'Successfully reversed invoice % to DRAFT', NEW.invoice_number;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Failed to reverse invoice %: %', NEW.invoice_number, SQLERRM;
    END;
  END IF;
  
  RETURN NEW;
END;
$$;

-- =====================================================
-- Update Main Trigger to Handle Both Directions
-- =====================================================
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER INSERT OR UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- Add reversal trigger
DROP TRIGGER IF EXISTS purchase_invoice_reversal_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_reversal_trigger
  BEFORE UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION handle_purchase_invoice_reversal();

-- =====================================================
-- Verification Queries
-- =====================================================

-- Check all triggers on purchase_invoices
SELECT 
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'purchase_invoices'
ORDER BY trigger_name;

-- Check functions
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name LIKE '%purchase%'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;

-- =====================================================
-- Manual Testing Queries
-- =====================================================

-- To manually reverse an invoice's inventory:
-- SELECT reverse_purchase_invoice_inventory('invoice-uuid-here');

-- To manually reverse an invoice's journal entry:
-- SELECT reverse_purchase_invoice_journal_entry('invoice-uuid-here');

-- Check reversed entries:
-- SELECT * FROM journal_entries WHERE status = 'reversed';
-- SELECT * FROM journal_entries WHERE type = 'reversal';

-- =====================================================
-- NOTES:
-- =====================================================
-- 1. Reversal creates REVERSING entries (audit trail preserved)
-- 2. Original entries marked as 'reversed' (not deleted)
-- 3. Inventory checked before reversal (prevents negative stock)
-- 4. Status flow: Draft ⟷ Received ⟷ Paid
-- 5. Going backward reverses inventory and accounting
-- 6. Two triggers: one BEFORE (reversal), one AFTER (forward)
-- =====================================================
