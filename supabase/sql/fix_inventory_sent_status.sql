-- ============================================================================
-- Fix: Inventory Deducted Twice When Reverting from Confirmed to Sent
-- ============================================================================
-- Problem: When changing invoice status from "confirmed" → "sent", the system:
--   1. Restores inventory (correct) ✅
--   2. Then deducts it again (wrong) ❌
--
-- Root Cause: The consume_sales_invoice_inventory() function doesn't skip "sent" status
--
-- Solution: Add "sent"/"enviado"/"issued" to the list of non-posted statuses
-- ============================================================================

CREATE OR REPLACE FUNCTION public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reference TEXT;
  v_item RECORD;
  v_resolved_product_id UUID;
  v_quantity_int INTEGER;
  v_status TEXT;
  v_items_count INTEGER;
BEGIN
  -- Early exit if invoice ID is null
  IF p_invoice.id IS NULL THEN
    RAISE NOTICE 'consume_sales_invoice_inventory: invoice ID is null';
    RETURN;
  END IF;

  v_status := lower(COALESCE(p_invoice.status, 'draft'));
  RAISE NOTICE 'consume_sales_invoice_inventory: invoice %, status %', p_invoice.id, v_status;

  -- ⭐ FIX: Add "sent"/"enviado"/"issued" to non-posted statuses
  -- Only "confirmed" and "paid" should consume inventory
  IF v_status = ANY (ARRAY[
    'draft', 'borrador',
    'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ]) THEN
    RAISE NOTICE 'consume_sales_invoice_inventory: status is non-posted, skipping';
    RETURN;
  END IF;

  -- Check if inventory reduction already done
  v_reference := concat('sales_invoice:', p_invoice.id::text);
  IF EXISTS (
    SELECT 1
    FROM public.stock_movements
    WHERE reference = v_reference
      AND type = 'OUT'
  ) THEN
    RAISE NOTICE 'consume_sales_invoice_inventory: inventory already reduced for %', v_reference;
    RETURN;
  END IF;

  -- Count items
  SELECT jsonb_array_length(COALESCE(p_invoice.items, '[]'::jsonb))
  INTO v_items_count;
  
  RAISE NOTICE 'consume_sales_invoice_inventory: processing % items', v_items_count;

  -- Process each item
  FOR v_item IN
    SELECT 
      (item->>'product_id')::UUID AS product_id,
      (item->>'product_sku')::TEXT AS product_sku,
      (item->>'quantity')::NUMERIC AS quantity
    FROM jsonb_array_elements(COALESCE(p_invoice.items, '[]'::jsonb)) item
  LOOP
    v_resolved_product_id := v_item.product_id;

    -- Try to resolve by SKU if product_id is null
    IF v_resolved_product_id IS NULL AND v_item.product_sku IS NOT NULL AND v_item.product_sku != '' THEN
      SELECT id
      INTO v_resolved_product_id
      FROM public.products
      WHERE sku = v_item.product_sku
      LIMIT 1;
      
      RAISE NOTICE 'consume_sales_invoice_inventory: resolved product % by SKU %', v_resolved_product_id, v_item.product_sku;
    END IF;

    v_quantity_int := COALESCE(v_item.quantity::INT, 0);

    IF v_resolved_product_id IS NULL THEN
      RAISE NOTICE 'consume_sales_invoice_inventory: skipping item - product_id is null, sku: %', v_item.product_sku;
      CONTINUE;
    END IF;

    IF v_quantity_int <= 0 THEN
      RAISE NOTICE 'consume_sales_invoice_inventory: skipping item - quantity <= 0, product: %', v_resolved_product_id;
      CONTINUE;
    END IF;

    -- Reduce inventory
    UPDATE public.products
    SET inventory_qty = COALESCE(inventory_qty, 0) - v_quantity_int,
        updated_at = NOW()
    WHERE id = v_resolved_product_id
      AND COALESCE(is_service, FALSE) = FALSE;

    IF FOUND THEN
      RAISE NOTICE 'consume_sales_invoice_inventory: reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
      
      -- Create stock movement record
      INSERT INTO public.stock_movements (
        id,
        product_id,
        warehouse_id,
        type,
        movement_type,
        quantity,
        reference,
        notes,
        date,
        created_at,
        updated_at
      ) VALUES (
        gen_random_uuid(),
        v_resolved_product_id,
        NULL,
        'OUT',
        'sales_invoice',
        -v_quantity_int, -- Negative for OUT movements
        v_reference,
        format('Salida por factura %s', COALESCE(NULLIF(p_invoice.invoice_number, ''), p_invoice.id::TEXT)),
        COALESCE(p_invoice.date, NOW()),
        NOW(),
        NOW()
      );
    ELSE
      RAISE NOTICE 'consume_sales_invoice_inventory: product % is a service or does not exist', v_resolved_product_id;
    END IF;
  END LOOP;

  RAISE NOTICE 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;

-- ============================================================================
-- Verification
-- ============================================================================
-- After running this, test the flow:
-- 1. Create an invoice in "draft" → inventory unchanged ✅
-- 2. Change to "sent" → inventory unchanged ✅
-- 3. Change to "confirmed" → inventory deducted ✅
-- 4. Change back to "sent" → inventory restored ✅ (no double deduction)
-- 5. Change to "confirmed" again → inventory deducted ✅
-- ============================================================================
