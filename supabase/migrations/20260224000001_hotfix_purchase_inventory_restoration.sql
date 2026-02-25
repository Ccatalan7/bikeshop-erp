-- ============================================================================
-- HOTFIX: Fix restore_purchase_invoice_inventory 
-- ============================================================================
-- Drops conflicting legacy versions and correctly replaces the restore function.
-- ============================================================================

DROP FUNCTION IF EXISTS public.restore_purchase_invoice_inventory();
DROP FUNCTION IF EXISTS public.restore_purchase_invoice_inventory(uuid);

CREATE OR REPLACE FUNCTION public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
RETURNS VOID
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
  
  -- Set variables
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
BEGIN
  IF p_invoice.id IS NULL THEN
    RAISE NOTICE 'restore_purchase_invoice_inventory: invoice ID is null, returning';
    RETURN;
  END IF;

  v_items := p_invoice.items;
  IF v_items IS NULL OR jsonb_array_length(v_items) = 0 THEN
    RAISE NOTICE 'restore_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    RETURN;
  END IF;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  -- Delete ALL stock movements for this reference (cleans up both sets and normal products)
  -- The constraint on stock_movements should take care of tenant_id, but the invoice already filters it.
  DELETE FROM public.stock_movements
  WHERE reference = v_reference
  AND tenant_id = p_invoice.tenant_id;

  -- DECREASE inventory (restore = undo IN movement)
  FOR v_item IN
    SELECT
      (item->>'product_id')::uuid AS product_id,
      (item->>'quantity')::numeric AS quantity
    FROM jsonb_array_elements(v_items) AS item
  LOOP
    v_resolved_product_id := v_item.product_id;
    IF v_resolved_product_id IS NULL THEN
      CONTINUE;
    END IF;

    v_quantity_numeric := COALESCE(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    IF v_quantity_int = 0 THEN
      CONTINUE;
    END IF;

    -- CHECK IF PRODUCT IS A SET
    SELECT is_set INTO v_is_set FROM products WHERE id = v_resolved_product_id;

    IF v_is_set THEN
        -- SET LOGIC: Restore components
        FOR v_child IN
            SELECT 
                component_product_id, 
                quantity_in_set
            FROM product_set_components
            WHERE set_product_id = v_resolved_product_id
        LOOP
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            UPDATE public.products
            SET 
              inventory_qty = greatest(COALESCE(inventory_qty, 0) - v_child_qty, 0),
              stock_quantity = greatest(COALESCE(stock_quantity, 0) - v_child_qty, 0),
              updated_at = NOW()
            WHERE id = v_child.component_product_id;
        END LOOP;
        
    ELSE
        -- STANDARD LOGIC
        UPDATE public.products
        SET 
          inventory_qty = greatest(COALESCE(inventory_qty, 0) - v_quantity_int, 0),
          stock_quantity = greatest(COALESCE(stock_quantity, 0) - v_quantity_int, 0),
          updated_at = NOW()
        WHERE id = v_resolved_product_id;
    END IF;

  END LOOP;
  
  RAISE NOTICE 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;
