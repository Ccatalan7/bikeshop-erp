-- ============================================================================
-- FIX: Update consume_sales_invoice_inventory to handle Product Sets
-- ============================================================================
-- Problem: Currently, selling a "Set" deducts inventory from the Set ID itself.
-- Solution: Detect if it's a Set, and if so, deduct from its COMPONENTS instead.

CREATE OR REPLACE FUNCTION public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item jsonb;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_reference text;
  v_items_count integer;
  v_is_set boolean;
  v_component record;
  v_qty_to_deduct integer;
  v_set_name text;
BEGIN
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  PERFORM set_config('app.skip_stock_adjustment_trigger', 'true', true);

  -- Early exit if invoice ID is null
  IF p_invoice.id IS NULL THEN
    RAISE NOTICE 'consume_sales_invoice_inventory: invoice ID is null';
    RETURN;
  END IF;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  RAISE NOTICE 'consume_sales_invoice_inventory: invoice %, status %', p_invoice.id, v_status;

  -- Only process if status is posted (not draft/cancelled)
  IF v_status = ANY (ARRAY['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) THEN
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
  SELECT jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    INTO v_items_count;
  
  RAISE NOTICE 'consume_sales_invoice_inventory: processing % items', v_items_count;

  -- Process each item
  FOR v_item IN
    SELECT 
      (item->>'product_id')::uuid as product_id,
      (item->>'product_sku')::text as product_sku,
      (item->>'quantity')::numeric as quantity
    FROM jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
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

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    IF v_resolved_product_id IS NULL THEN
      RAISE NOTICE 'consume_sales_invoice_inventory: skipping item - product_id is null, sku: %', v_item.product_sku;
      CONTINUE;
    END IF;

    IF v_quantity_int <= 0 THEN
      RAISE NOTICE 'consume_sales_invoice_inventory: skipping item - quantity <= 0, product: %', v_resolved_product_id;
      CONTINUE;
    END IF;

    -- CHECK IF PRODUCT IS A SET
    SELECT is_set, name
      INTO v_is_set, v_set_name
      FROM public.products
     WHERE id = v_resolved_product_id;

    IF v_is_set THEN
       RAISE NOTICE 'consume_sales_invoice_inventory: Product % (%) is a SET. Deducting components...', v_resolved_product_id, v_set_name;
       
       -- Iterate over components
       FOR v_component IN
         SELECT 
           component_product_id,
           quantity_in_set,
           component_label
         FROM public.product_set_components
         WHERE set_product_id = v_resolved_product_id
       LOOP
          v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;
          
          RAISE NOTICE '   - Deducting component % (Qty: %)', v_component.component_product_id, v_qty_to_deduct;

          -- Deduct Component Stock
          UPDATE public.products
             SET inventory_qty = coalesce(inventory_qty, 0) - v_qty_to_deduct,
                 stock_quantity = greatest(coalesce(stock_quantity, 0) - v_qty_to_deduct, 0),
                 updated_at = now()
           WHERE id = v_component.component_product_id;

          -- Log Component Movement
          INSERT INTO public.stock_movements (
            id, product_id, warehouse_id, type, movement_type, quantity,
            reference, notes, date, created_at, updated_at
          ) VALUES (
            gen_random_uuid(),
            v_component.component_product_id,
            null,
            'OUT',
            'sales_invoice_component', -- Distinct type for component usage
            -v_qty_to_deduct,
            v_reference,
            format('Salida por venta de Set "%s" (Factura %s)', 
                   v_set_name, 
                   coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
            ),
            coalesce(p_invoice.date, now()),
            now(),
            now()
          );
       END LOOP;

       -- Do NOT deduct stock from the parent SET itself, as it is virtual.
       -- Or optionally, you could deduct it if you track virtual stock, but usually Sets = 0.
       RAISE NOTICE 'consume_sales_invoice_inventory: Finished processing set %', v_resolved_product_id;

    ELSE
      -- STANDARD LOGIC: NOT A SET
      UPDATE public.products
         SET inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
             stock_quantity = greatest(coalesce(stock_quantity, 0) - v_quantity_int, 0),
             updated_at = now()
       WHERE id = v_resolved_product_id
         AND coalesce(is_service, false) = false;

      IF found THEN
        RAISE NOTICE 'consume_sales_invoice_inventory: reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
        
        -- Create stock movement record
        INSERT INTO public.stock_movements (
          id, product_id, warehouse_id, type, movement_type, quantity,
          reference, notes, date, created_at, updated_at
        ) VALUES (
          gen_random_uuid(),
          v_resolved_product_id,
          null,
          'OUT',
          'sales_invoice',
          -v_quantity_int, -- Negative for OUT movements
          v_reference,
          format('Salida por factura %s', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      ELSE
        RAISE NOTICE 'consume_sales_invoice_inventory: product % is a service or does not exist', v_resolved_product_id;
      END IF;
    END IF;

  END LOOP;

  RAISE NOTICE 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
END;
$$;
