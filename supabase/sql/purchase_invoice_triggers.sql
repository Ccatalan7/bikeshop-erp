-- =====================================================
-- Purchase Invoice Workflow Triggers - 5 Status System
-- =====================================================
-- Implements both Standard and Prepayment payment models
-- with DELETE-based reversals (Zoho Books style)
-- =====================================================

-- =====================================================
-- Create purchase_payments table if it doesn't exist
-- =====================================================

CREATE TABLE IF NOT EXISTS purchase_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_invoice_id UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  payment_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'transfer', 'check', 'card', 'other')),
  bank_account_id UUID REFERENCES accounts(id),
  reference TEXT,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_purchase_payments_invoice_id ON purchase_payments(purchase_invoice_id);
CREATE INDEX IF NOT EXISTS idx_purchase_payments_date ON purchase_payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_purchase_payments_bank_account ON purchase_payments(bank_account_id);

-- =====================================================
-- Drop existing triggers and functions (if they exist)
-- =====================================================

-- Drop triggers first (they depend on functions)
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;
DROP TRIGGER IF EXISTS recalculate_purchase_payments_trigger ON purchase_payments;

-- Now drop functions
DROP FUNCTION IF EXISTS consume_purchase_invoice_inventory(UUID);
DROP FUNCTION IF EXISTS reverse_purchase_invoice_inventory(UUID);
DROP FUNCTION IF EXISTS create_purchase_invoice_journal_entry(UUID);
DROP FUNCTION IF EXISTS create_prepaid_purchase_confirmation_entry(UUID);
DROP FUNCTION IF EXISTS settle_prepaid_inventory_on_order(UUID);
DROP FUNCTION IF EXISTS handle_purchase_invoice_change();
DROP FUNCTION IF EXISTS recalculate_purchase_invoice_payments();

-- =====================================================
-- Function 1: Consume inventory (increase stock)
-- =====================================================

CREATE OR REPLACE FUNCTION consume_purchase_invoice_inventory(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_item JSONB;
  v_product_id UUID;
  v_quantity NUMERIC;
  v_movement_id UUID;
  v_movement_type TEXT;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Determine movement type based on payment model
  v_movement_type := CASE 
    WHEN v_invoice.prepayment_model THEN 'purchase_invoice_prepaid'
    ELSE 'purchase_invoice'
  END;

  -- Process each item in the invoice
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_invoice.items)
  LOOP
    v_product_id := (v_item->>'product_id')::UUID;
    v_quantity := (v_item->>'quantity')::NUMERIC;

    IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
      CONTINUE;
    END IF;

    -- Create IN stock movement
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
      v_product_id,
      'IN',
      v_movement_type,
      v_quantity,
      p_invoice_id::TEXT,
      'Compra: ' || v_invoice.invoice_number,
      NOW()
    )
    RETURNING id INTO v_movement_id;

    -- Increase product inventory
    UPDATE products
    SET 
      inventory_qty = COALESCE(inventory_qty, 0) + v_quantity,
      updated_at = NOW()
    WHERE id = v_product_id;

    RAISE NOTICE 'Created IN movement % for product % (qty: %)', 
      v_movement_id, v_product_id, v_quantity;
  END LOOP;

  RAISE NOTICE 'Inventory increased for invoice %', v_invoice.invoice_number;
END;
$$;

-- =====================================================
-- Function 2: Reverse inventory (decrease stock)
-- =====================================================

CREATE OR REPLACE FUNCTION reverse_purchase_invoice_inventory(p_invoice_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_item JSONB;
  v_product_id UUID;
  v_quantity NUMERIC;
  v_current_qty INTEGER;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Process each item in reverse
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_invoice.items)
  LOOP
    v_product_id := (v_item->>'product_id')::UUID;
    v_quantity := (v_item->>'quantity')::NUMERIC;

    IF v_product_id IS NULL OR v_quantity IS NULL OR v_quantity <= 0 THEN
      CONTINUE;
    END IF;

    -- Check if sufficient inventory exists
    SELECT inventory_qty INTO v_current_qty
    FROM products
    WHERE id = v_product_id;

    IF v_current_qty < v_quantity THEN
      RAISE EXCEPTION 'Inventario insuficiente para producto % (disponible: %, necesario: %)',
        v_product_id, v_current_qty, v_quantity;
    END IF;

    -- Decrease product inventory
    UPDATE products
    SET 
      inventory_qty = inventory_qty - v_quantity,
      updated_at = NOW()
    WHERE id = v_product_id;

    RAISE NOTICE 'Decreased inventory for product % (qty: %)', v_product_id, v_quantity;
  END LOOP;

  -- Delete stock movements (DELETE-based reversal)
  DELETE FROM stock_movements
  WHERE reference = p_invoice_id::TEXT
    AND movement_type IN ('purchase_invoice', 'purchase_invoice_prepaid')
    AND type = 'IN';

  RAISE NOTICE 'Inventory reversed for invoice %', v_invoice.invoice_number;
END;
$$;

-- =====================================================
-- Function 3: Create journal entry - STANDARD MODEL
-- =====================================================

CREATE OR REPLACE FUNCTION create_purchase_invoice_journal_entry(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inventory_account_id UUID;
  v_iva_account_id UUID;
  v_ap_account_id UUID;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs (adjust codes as needed)
  SELECT id INTO v_inventory_account_id FROM accounts WHERE code = '1150' LIMIT 1; -- Inventario
  SELECT id INTO v_iva_account_id FROM accounts WHERE code = '1140' LIMIT 1;      -- IVA Crédito Fiscal
  SELECT id INTO v_ap_account_id FROM accounts WHERE code = '2120' LIMIT 1;       -- Cuentas por Pagar

  IF v_inventory_account_id IS NULL OR v_iva_account_id IS NULL OR v_ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found (1150, 1140, 2120)';
  END IF;

  -- Create journal entry
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,
    entry_type,
    source_module,
    source_reference,
    status,
    notes,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'COMP-FC-' || v_invoice.invoice_number,
    v_invoice.confirmed_date,
    'purchase_invoice',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Compra según factura ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- Create journal lines
  -- DR: Inventario (subtotal)
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_invoice.subtotal,
    0,
    'Inventario - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  -- DR: IVA Crédito Fiscal
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    v_invoice.iva_amount,
    0,
    'IVA Crédito Fiscal',
    NOW()
  );

  -- CR: Cuentas por Pagar
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    0,
    v_invoice.total,
    'Cuentas por Pagar - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  RAISE NOTICE 'Created journal entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- =====================================================
-- Function 4: Create journal entry - PREPAYMENT MODEL
-- =====================================================

CREATE OR REPLACE FUNCTION create_prepaid_purchase_confirmation_entry(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inv_transit_account_id UUID;  -- Inventario en Tránsito (1155)
  v_iva_account_id UUID;
  v_ap_account_id UUID;
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs for prepayment model
  SELECT id INTO v_inv_transit_account_id FROM accounts WHERE code = '1155' LIMIT 1; -- Inventario en Tránsito
  SELECT id INTO v_iva_account_id FROM accounts WHERE code = '1140' LIMIT 1;         -- IVA Crédito Fiscal
  SELECT id INTO v_ap_account_id FROM accounts WHERE code = '2120' LIMIT 1;          -- Cuentas por Pagar

  IF v_inv_transit_account_id IS NULL OR v_iva_account_id IS NULL OR v_ap_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found for prepayment (1155, 1140, 2120)';
  END IF;

  -- Create journal entry
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,
    entry_type,
    source_module,
    source_reference,
    status,
    notes,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'CONF-COMP-FC-' || v_invoice.invoice_number,
    v_invoice.confirmed_date,
    'purchase_confirmation',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Confirmación de compra prepagada - Factura ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- Create journal lines
  -- DR: Inventario en Tránsito (subtotal)
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inv_transit_account_id,
    v_invoice.subtotal,
    0,
    'Inventario en Tránsito - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  -- DR: IVA Crédito Fiscal
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    v_invoice.iva_amount,
    0,
    'IVA Crédito Fiscal',
    NOW()
  );

  -- CR: Cuentas por Pagar
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_ap_account_id,
    0,
    v_invoice.total,
    'Cuentas por Pagar - ' || COALESCE(v_invoice.supplier_name, 'Proveedor'),
    NOW()
  );

  RAISE NOTICE 'Created prepaid confirmation entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- =====================================================
-- Function 5: Settle prepaid inventory (on-order → in-stock)
-- =====================================================

CREATE OR REPLACE FUNCTION settle_prepaid_inventory_on_order(p_invoice_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice RECORD;
  v_entry_id UUID;
  v_inventory_account_id UUID;       -- Inventario (1150)
  v_inv_transit_account_id UUID;     -- Inventario en Tránsito (1155)
BEGIN
  -- Get invoice data
  SELECT * INTO v_invoice
  FROM purchase_invoices
  WHERE id = p_invoice_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice % not found', p_invoice_id;
  END IF;

  -- Get account IDs
  SELECT id INTO v_inventory_account_id FROM accounts WHERE code = '1150' LIMIT 1;
  SELECT id INTO v_inv_transit_account_id FROM accounts WHERE code = '1155' LIMIT 1;

  IF v_inventory_account_id IS NULL OR v_inv_transit_account_id IS NULL THEN
    RAISE EXCEPTION 'Required accounts not found for settlement (1150, 1155)';
  END IF;

  -- Create settlement journal entry
  INSERT INTO journal_entries (
    id,
    entry_number,
    entry_date,
    entry_type,
    source_module,
    source_reference,
    status,
    notes,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    'RECEP-PREPAID-' || v_invoice.invoice_number,
    v_invoice.received_date,
    'purchase_receipt',
    'purchase_invoices',
    p_invoice_id::TEXT,
    'posted',
    'Recepción de inventario prepagado - ' || v_invoice.invoice_number,
    NOW()
  )
  RETURNING id INTO v_entry_id;

  -- DR: Inventario (move from transit to stock)
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    v_invoice.subtotal,
    0,
    'Inventario recibido',
    NOW()
  );

  -- CR: Inventario en Tránsito
  INSERT INTO journal_lines (id, journal_entry_id, account_id, debit, credit, description, created_at)
  VALUES (
    gen_random_uuid(),
    v_entry_id,
    v_inv_transit_account_id,
    0,
    v_invoice.subtotal,
    'Inventario en tránsito a stock',
    NOW()
  );

  RAISE NOTICE 'Created settlement entry % for invoice %', v_entry_id, v_invoice.invoice_number;
  RETURN v_entry_id;
END;
$$;

-- =====================================================
-- Main Trigger Function: Handle all status changes
-- =====================================================

CREATE OR REPLACE FUNCTION handle_purchase_invoice_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_entry_id UUID;
BEGIN
  RAISE NOTICE 'Purchase invoice status change: % → %', OLD.status, NEW.status;

  -- =====================================================
  -- FORWARD TRANSITIONS
  -- =====================================================

  -- Enviada → Confirmada: Create accounting entry
  IF (OLD.status = 'sent' AND NEW.status = 'confirmed') THEN
    IF NEW.prepayment_model THEN
      -- Prepayment: use Inventory on Order account
      v_entry_id := create_prepaid_purchase_confirmation_entry(NEW.id);
    ELSE
      -- Standard: use Inventory account directly
      v_entry_id := create_purchase_invoice_journal_entry(NEW.id);
    END IF;
    
    RAISE NOTICE 'Created accounting entry for confirmed invoice';
  END IF;

  -- Confirmada → Recibida (Standard) OR Pagada → Recibida (Prepayment): Increase inventory
  IF (OLD.status IN ('confirmed', 'paid') AND NEW.status = 'received') THEN
    PERFORM consume_purchase_invoice_inventory(NEW.id);
    
    -- If prepayment model, also create settlement entry
    IF NEW.prepayment_model THEN
      v_entry_id := settle_prepaid_inventory_on_order(NEW.id);
    END IF;
    
    RAISE NOTICE 'Increased inventory for received invoice';
  END IF;

  -- =====================================================
  -- BACKWARD TRANSITIONS (DELETE-based reversals)
  -- =====================================================

  -- Confirmada → Enviada: Delete accounting entry
  IF (OLD.status = 'confirmed' AND NEW.status = 'sent') THEN
    DELETE FROM journal_entries
    WHERE source_module = 'purchase_invoices'
      AND source_reference = OLD.id::TEXT
      AND entry_type IN ('purchase_invoice', 'purchase_confirmation');
    
    RAISE NOTICE 'Deleted accounting entry for reverted invoice';
  END IF;

  -- Recibida → Confirmada (Standard) OR Recibida → Pagada (Prepayment): Reverse inventory
  IF (OLD.status = 'received' AND NEW.status IN ('confirmed', 'paid')) THEN
    PERFORM reverse_purchase_invoice_inventory(OLD.id);
    
    -- If prepayment model, also delete settlement entry
    IF OLD.prepayment_model THEN
      DELETE FROM journal_entries
      WHERE source_module = 'purchase_invoices'
        AND source_reference = OLD.id::TEXT
        AND entry_type = 'purchase_receipt';
    END IF;
    
    RAISE NOTICE 'Reversed inventory for reverted invoice';
  END IF;

  RETURN NEW;
END;
$$;

-- =====================================================
-- Create/Replace Trigger
-- =====================================================

DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- =====================================================
-- Payment Tracking Trigger
-- =====================================================

CREATE OR REPLACE FUNCTION recalculate_purchase_invoice_payments()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_invoice_id UUID;
  v_total_paid NUMERIC;
  v_invoice_total NUMERIC;
  v_new_status TEXT;
BEGIN
  -- Get invoice ID
  v_invoice_id := COALESCE(NEW.purchase_invoice_id, OLD.purchase_invoice_id);

  IF v_invoice_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Calculate total paid
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM purchase_payments
  WHERE purchase_invoice_id = v_invoice_id;

  -- Get invoice total
  SELECT total INTO v_invoice_total
  FROM purchase_invoices
  WHERE id = v_invoice_id;

  -- Determine new status
  IF v_total_paid >= v_invoice_total THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    -- Partial payment - keep current status
    SELECT status INTO v_new_status
    FROM purchase_invoices
    WHERE id = v_invoice_id;
  ELSE
    -- No payment - revert to received
    v_new_status := 'received';
  END IF;

  -- Update invoice
  UPDATE purchase_invoices
  SET 
    paid_amount = v_total_paid,
    balance = v_invoice_total - v_total_paid,
    status = v_new_status,
    paid_date = CASE WHEN v_new_status = 'paid' THEN NOW() ELSE NULL END,
    updated_at = NOW()
  WHERE id = v_invoice_id;

  RAISE NOTICE 'Updated invoice % payments: paid=%, balance=%, status=%',
    v_invoice_id, v_total_paid, v_invoice_total - v_total_paid, v_new_status;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS recalculate_purchase_payments_trigger ON purchase_payments;

CREATE TRIGGER recalculate_purchase_payments_trigger
  AFTER INSERT OR UPDATE OR DELETE
  ON purchase_payments
  FOR EACH ROW
  EXECUTE FUNCTION recalculate_purchase_invoice_payments();

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Purchase Invoice Triggers Created Successfully!';
  RAISE NOTICE '';
  RAISE NOTICE '📋 Trigger Functions:';
  RAISE NOTICE '   1. consume_purchase_invoice_inventory() - Increase stock';
  RAISE NOTICE '   2. reverse_purchase_invoice_inventory() - Decrease stock';
  RAISE NOTICE '   3. create_purchase_invoice_journal_entry() - Standard accounting';
  RAISE NOTICE '   4. create_prepaid_purchase_confirmation_entry() - Prepaid accounting';
  RAISE NOTICE '   5. settle_prepaid_inventory_on_order() - Prepaid settlement';
  RAISE NOTICE '   6. handle_purchase_invoice_change() - Main workflow trigger';
  RAISE NOTICE '   7. recalculate_purchase_invoice_payments() - Payment tracking';
  RAISE NOTICE '';
  RAISE NOTICE '🔄 Workflow Modes:';
  RAISE NOTICE '   - Standard: Borrador → Enviada → Confirmada → Recibida → Pagada';
  RAISE NOTICE '   - Prepayment: Borrador → Enviada → Confirmada → Pagada → Recibida';
  RAISE NOTICE '';
  RAISE NOTICE '✨ Features:';
  RAISE NOTICE '   - DELETE-based reversals (Zoho Books style)';
  RAISE NOTICE '   - Automatic inventory management';
  RAISE NOTICE '   - Dual accounting entries (standard vs prepaid)';
  RAISE NOTICE '   - Payment tracking with balance calculation';
END $$;
