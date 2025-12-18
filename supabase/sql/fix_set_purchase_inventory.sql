-- ============================================================================
-- FIX: Support Product Sets in Purchase Inventory Logic
-- ============================================================================
-- 1. Updates consume_purchase_invoice_inventory to "explode" sets into components
-- 2. Updates restore_purchase_invoice_inventory to reverse this logic
-- ============================================================================

-- Function: Consume inventory (Purchase = IN)
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
              inventory_qty = inventory_qty + v_child_qty,
              stock_quantity = stock_quantity + v_child_qty
            WHERE id = v_child.component_product_id;
            
            -- Record Stock Movement for Component
            INSERT INTO public.stock_movements (
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
              v_child.component_product_id,
              v_child_qty,
              'purchase_invoice',
              'IN',
              v_reference,
              format('Entrada por compra de set %s (Factura %s)', v_item.product_name, p_invoice.invoice_number),
              p_invoice.date,
              now(),
              now()
            );
        END LOOP;
        
    ELSE
        -- STANDARD LOGIC: Update product inventory directly
        UPDATE public.products
        SET 
          inventory_qty = inventory_qty + v_quantity_int,
          stock_quantity = stock_quantity + v_quantity_int
        WHERE id = v_resolved_product_id;

        -- Record stock movement
        INSERT INTO public.stock_movements (
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


-- Function: Restore inventory (Undo Purchase = OUT)
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
  DELETE FROM public.stock_movements
  WHERE reference = v_reference;

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
              inventory_qty = greatest(inventory_qty - v_child_qty, 0),
              stock_quantity = greatest(stock_quantity - v_child_qty, 0)
            WHERE id = v_child.component_product_id;
        END LOOP;
        
    ELSE
        -- STANDARD LOGIC
        UPDATE public.products
        SET 
          inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
          stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
        WHERE id = v_resolved_product_id;
    END IF;

  END LOOP;
  
  RAISE NOTICE 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;
