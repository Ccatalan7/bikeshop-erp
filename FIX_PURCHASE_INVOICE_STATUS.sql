-- ==========================================
-- FIX: Patch Function + Fix Invoice Statuses (Safe - No Triggers)
-- ==========================================

-- PART 1: Fix the bug in consume_purchase_invoice_inventory (missing tenant_id)
-- This fixes the function for FUTURE use. The data fix below bypasses triggers.

CREATE OR REPLACE FUNCTION public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
BEGIN
  PERFORM set_config('app.skip_stock_adjustment_trigger', 'true', true);
  
  IF p_invoice.id IS NULL THEN
    RAISE NOTICE 'consume_purchase_invoice_inventory: invoice ID is null';
    RETURN;
  END IF;

  v_items := p_invoice.items;
  IF v_items IS NULL OR jsonb_array_length(v_items) = 0 THEN
    RAISE NOTICE 'consume_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    RETURN;
  END IF;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  FOR v_item IN
    SELECT
      (item->>'product_id')::uuid AS product_id,
      (item->>'product_name')::text AS product_name,
      (item->>'quantity')::numeric AS quantity
    FROM jsonb_array_elements(v_items) AS item
  LOOP
    v_resolved_product_id := v_item.product_id;
    IF v_resolved_product_id IS NULL THEN CONTINUE; END IF;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);
    IF v_quantity_int = 0 THEN CONTINUE; END IF;

    SELECT is_set INTO v_is_set FROM products WHERE id = v_resolved_product_id;
    
    IF v_is_set THEN
        FOR v_child IN
            SELECT component_product_id, quantity_in_set
            FROM product_set_components
            WHERE set_product_id = v_resolved_product_id
        LOOP
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            UPDATE public.products
            SET inventory_qty = inventory_qty + v_child_qty,
                stock_quantity = stock_quantity + v_child_qty
            WHERE id = v_child.component_product_id;
            
            INSERT INTO public.stock_movements (
              tenant_id, product_id, quantity, movement_type, type, reference, notes, date, created_at, updated_at
            ) VALUES (
              p_invoice.tenant_id, v_child.component_product_id, v_child_qty,
              'purchase_invoice', 'IN', v_reference,
              format('Entrada por compra de set %s (Factura %s)', v_item.product_name, p_invoice.invoice_number),
              p_invoice.date, now(), now()
            );
        END LOOP;
    ELSE
        UPDATE public.products
        SET inventory_qty = inventory_qty + v_quantity_int,
            stock_quantity = stock_quantity + v_quantity_int
        WHERE id = v_resolved_product_id;

        INSERT INTO public.stock_movements (
          tenant_id, product_id, quantity, movement_type, type, reference, notes, date, created_at, updated_at
        ) VALUES (
          p_invoice.tenant_id, v_resolved_product_id, v_quantity_int,
          'purchase_invoice', 'IN', v_reference,
          format('Entrada según factura compra %s', p_invoice.invoice_number),
          p_invoice.date, now(), now()
        );
    END IF;
  END LOOP;

  RAISE NOTICE 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;

-- ==========================================
-- PART 2: Fix Invoice Statuses (TRIGGER DISABLED - Safe Manual Approach)
-- ==========================================
-- We disable the trigger to avoid cascading issues, then manually:
--   1. Add inventory (stock_quantity + stock_movements) for invoices not yet received
--   2. Update status to the correct final state

DO $$
DECLARE
    r RECORD;
    v_item RECORD;
    v_product_id UUID;
    v_quantity INTEGER;
    v_reference TEXT;
    v_is_set BOOLEAN;
    v_child RECORD;
    v_child_qty INTEGER;
    fixed_count INTEGER := 0;
    inventory_added INTEGER := 0;
BEGIN
    -- CRITICAL: Disable user-defined triggers to prevent cascade issues
    PERFORM set_config('app.skip_stock_adjustment_trigger', 'true', true);
    ALTER TABLE purchase_invoices DISABLE TRIGGER trg_purchase_invoices_change;
    ALTER TABLE purchase_invoices DISABLE TRIGGER trg_handle_purchase_invoice_deletion;
    
    RAISE NOTICE '=== Triggers disabled. Starting safe fix. ===';

    FOR r IN 
        SELECT id, invoice_number, status, balance, prepayment_model, items, tenant_id, date
        FROM purchase_invoices 
        WHERE 
            balance < 1 
            AND status NOT IN ('paid', 'cancelled')
    LOOP
        RAISE NOTICE 'Processing: % (Status: %, Balance: %)', r.invoice_number, r.status, r.balance;

        -- Step 1: Add inventory if invoice was never "received"
        -- Check if stock movements already exist for this invoice
        v_reference := format('purchase_invoice:%s', r.id);
        
        IF NOT EXISTS (SELECT 1 FROM stock_movements WHERE reference = v_reference LIMIT 1) THEN
            -- No stock movements exist -> inventory was never added. Add it now.
            RAISE NOTICE '  Adding inventory for % ...', r.invoice_number;
            
            FOR v_item IN
                SELECT
                    (item->>'product_id')::uuid AS product_id,
                    (item->>'product_name')::text AS product_name,
                    (item->>'quantity')::numeric AS quantity
                FROM jsonb_array_elements(r.items) AS item
            LOOP
                v_product_id := v_item.product_id;
                IF v_product_id IS NULL THEN CONTINUE; END IF;
                
                v_quantity := abs(coalesce(v_item.quantity, 0)::integer);
                IF v_quantity = 0 THEN CONTINUE; END IF;

                SELECT is_set INTO v_is_set FROM products WHERE id = v_product_id;
                
                IF v_is_set THEN
                    FOR v_child IN
                        SELECT component_product_id, quantity_in_set
                        FROM product_set_components
                        WHERE set_product_id = v_product_id
                    LOOP
                        v_child_qty := v_quantity * v_child.quantity_in_set;
                        UPDATE products
                        SET inventory_qty = inventory_qty + v_child_qty,
                            stock_quantity = stock_quantity + v_child_qty
                        WHERE id = v_child.component_product_id;
                        
                        INSERT INTO stock_movements (
                            tenant_id, product_id, quantity, movement_type, type, reference, notes, date, created_at, updated_at
                        ) VALUES (
                            r.tenant_id, v_child.component_product_id, v_child_qty,
                            'purchase_invoice', 'IN', v_reference,
                            format('Entrada por compra de set %s (Factura %s)', v_item.product_name, r.invoice_number),
                            r.date, now(), now()
                        );
                    END LOOP;
                ELSE
                    UPDATE products
                    SET inventory_qty = inventory_qty + v_quantity,
                        stock_quantity = stock_quantity + v_quantity
                    WHERE id = v_product_id;
                    
                    INSERT INTO stock_movements (
                        tenant_id, product_id, quantity, movement_type, type, reference, notes, date, created_at, updated_at
                    ) VALUES (
                        r.tenant_id, v_product_id, v_quantity,
                        'purchase_invoice', 'IN', v_reference,
                        format('Entrada según factura compra %s', r.invoice_number),
                        r.date, now(), now()
                    );
                END IF;
            END LOOP;
            
            inventory_added := inventory_added + 1;
            RAISE NOTICE '  ✓ Inventory added for %', r.invoice_number;
        ELSE
            RAISE NOTICE '  Stock movements already exist for % - skipping inventory', r.invoice_number;
        END IF;

        -- Step 2: Update status directly (no trigger fires)
        UPDATE purchase_invoices
        SET 
            status = 'paid',
            received_date = COALESCE(received_date, NOW()),
            paid_date = COALESCE(paid_date, NOW()),
            updated_at = NOW()
        WHERE id = r.id;

        fixed_count := fixed_count + 1;
        RAISE NOTICE '  ✓ Status updated to PAID for %', r.invoice_number;
    END LOOP;

    -- Re-enable triggers
    ALTER TABLE purchase_invoices ENABLE TRIGGER trg_purchase_invoices_change;
    ALTER TABLE purchase_invoices ENABLE TRIGGER trg_handle_purchase_invoice_deletion;
    
    RAISE NOTICE '=== Triggers re-enabled. ===';
    RAISE NOTICE '---------------------------------------------------';
    RAISE NOTICE 'Completed: % invoices fixed, % had inventory added.', fixed_count, inventory_added;
END $$;
