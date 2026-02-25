-- ============================================================================
-- HOTFIX: Fix consume_purchase_invoice_inventory and enforce tenant_id
-- ============================================================================
-- 1. Drops legacy signatures of the function that were causing conflicts.
-- 2. Rewrites the single correct function (taking a `purchase_invoices` row)
--    to guarantee `tenant_id` is passed to `stock_movements`, fixing the 
--    silent trigger crash caused by the NOT NULL constraint on stock movements.
-- 3. Restores the tracking context trigger that was missing in production.
-- ============================================================================

-- DROP conflicting legacy versions
DROP FUNCTION IF EXISTS public.consume_purchase_invoice_inventory();
DROP FUNCTION IF EXISTS public.consume_purchase_invoice_inventory(uuid);

-- CREATE OR REPLACE the correct parameterized version
CREATE OR REPLACE FUNCTION public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
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
  
  -- Set handling variables
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
BEGIN
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  PERFORM set_config('app.skip_stock_adjustment_trigger', 'true', true);
  
  IF p_invoice.id IS NULL THEN
    RAISE NOTICE 'consume_purchase_invoice_inventory: invoice ID is null, returning';
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
    IF v_resolved_product_id IS NULL THEN
      RAISE NOTICE 'consume_purchase_invoice_inventory: skipping item with null product_id';
      CONTINUE;
    END IF;

    v_quantity_numeric := COALESCE(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    IF v_quantity_int = 0 THEN
      RAISE NOTICE 'consume_purchase_invoice_inventory: skipping item % with zero quantity', v_resolved_product_id;
      CONTINUE;
    END IF;

    -- CHECK IF PRODUCT IS A SET
    SELECT is_set INTO v_is_set FROM products WHERE id = v_resolved_product_id;
    
    IF v_is_set THEN
        -- LOGIC FOR SETS: Explode into components
        RAISE NOTICE 'consume_purchase_invoice_inventory: exploding set % into components', v_resolved_product_id;
        
        FOR v_child IN
            SELECT 
                component_product_id, 
                quantity_in_set
            FROM product_set_components
            WHERE set_product_id = v_resolved_product_id
        LOOP
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            -- Update Component Inventory
            UPDATE public.products
            SET 
              inventory_qty = COALESCE(inventory_qty, 0) + v_child_qty,
              stock_quantity = COALESCE(stock_quantity, 0) + v_child_qty,
              updated_at = NOW()
            WHERE id = v_child.component_product_id;
            
            -- Record Stock Movement for Component (Includes tenant_id!)
            INSERT INTO public.stock_movements (
              tenant_id,
              product_id,
              quantity,
              movement_type,
              type,
              reference,
              notes,
              date,
              created_at,
              updated_at
            ) VALUES (
              p_invoice.tenant_id,
              v_child.component_product_id,
              v_child_qty,
              'purchase_invoice',
              'IN',
              v_reference,
              format('Entrada por compra de set %s (Factura %s)', v_item.product_name, p_invoice.invoice_number),
              p_invoice.date,
              NOW(),
              NOW()
            );
        END LOOP;
        
    ELSE
        -- STANDARD LOGIC: Update product inventory directly
        UPDATE public.products
        SET 
          inventory_qty = COALESCE(inventory_qty, 0) + v_quantity_int,
          stock_quantity = COALESCE(stock_quantity, 0) + v_quantity_int,
          updated_at = NOW()
        WHERE id = v_resolved_product_id;

        -- Record stock movement (Includes tenant_id!)
        INSERT INTO public.stock_movements (
          tenant_id,
          product_id,
          quantity,
          movement_type,
          type,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) VALUES (
          p_invoice.tenant_id,
          v_resolved_product_id,
          v_quantity_int,
          'purchase_invoice',
          'IN',
          v_reference,
          format('Entrada según factura compra %s', p_invoice.invoice_number),
          p_invoice.date,
          now(),
          now()
        );
    END IF;

  END LOOP;

  RAISE NOTICE 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;


-- ============================================================================
-- MISSING TRIGGER FIX: Set stock context so stock tracking recognizes purchases
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_purchase_context_on_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- When status changes to 'received', we are about to update stock.
  -- Set the context variables so the product trigger knows it's a purchase.
  IF NEW.status = 'received' AND (OLD.status IS DISTINCT FROM 'received') THEN
    
    PERFORM set_config('app.stock_adjustment_context', 'purchase', true);
    PERFORM set_config('app.stock_adjustment_reference', COALESCE(NEW.invoice_number, NEW.id::text), true);
    
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_purchase_context ON purchase_invoices;
CREATE TRIGGER trg_set_purchase_context
  BEFORE UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.set_purchase_context_on_status_change();
