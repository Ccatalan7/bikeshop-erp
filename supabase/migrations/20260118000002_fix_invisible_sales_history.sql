-- FIX: Invisible Sales History (Missing Tenant ID)
-- 
-- Root Cause: The function `consume_sales_invoice_inventory` was inserting records into 
-- `stock_movements` without specifying `tenant_id`. These records defaulted to NULL 
-- and were filtered out by the UI which queries by specific tenant_id.

-- 1. Fix the function to include tenant_id in INSERTs
CREATE OR REPLACE FUNCTION public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item record;
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
  
  -- Only process if status is posted
  IF v_status = ANY (ARRAY['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) THEN
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
    RETURN;
  END IF;

  -- Count items
  SELECT jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    INTO v_items_count;

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
    END IF;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    IF v_resolved_product_id IS NULL OR v_quantity_int <= 0 THEN
      CONTINUE;
    END IF;

    -- CHECK IF PRODUCT IS A SET
    SELECT is_set, name
      INTO v_is_set, v_set_name
      FROM public.products
     WHERE id = v_resolved_product_id;

    IF v_is_set THEN
       -- Iterate over components
       FOR v_component IN
         SELECT 
           component_product_id,
           quantity_in_set
         FROM public.product_set_components
         WHERE set_product_id = v_resolved_product_id
       LOOP
          v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;
          
          -- Deduct Component Stock
          UPDATE public.products
             SET inventory_qty = coalesce(inventory_qty, 0) - v_qty_to_deduct,
                 stock_quantity = greatest(coalesce(stock_quantity, 0) - v_qty_to_deduct, 0),
                 updated_at = now()
           WHERE id = v_component.component_product_id;

          -- Log Component Movement (FIXED: Includes tenant_id)
          INSERT INTO public.stock_movements (
            tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
            reference, notes, date, created_at, updated_at
          ) VALUES (
            p_invoice.tenant_id, -- ✅ Added tenant_id
            gen_random_uuid(),
            v_component.component_product_id,
            null,
            'OUT',
            'sales_invoice_component',
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

    ELSE
      -- STANDARD LOGIC: NOT A SET
      UPDATE public.products
         SET inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
             stock_quantity = greatest(coalesce(stock_quantity, 0) - v_quantity_int, 0),
             updated_at = now()
       WHERE id = v_resolved_product_id
         AND coalesce(is_service, false) = false;

      IF found THEN
        -- Create stock movement record (FIXED: Includes tenant_id)
        INSERT INTO public.stock_movements (
          tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
          reference, notes, date, created_at, updated_at
        ) VALUES (
          p_invoice.tenant_id, -- ✅ Added tenant_id
          gen_random_uuid(),
          v_resolved_product_id,
          null,
          'OUT',
          'sales_invoice',
          -v_quantity_int,
          v_reference,
          format('Salida por factura %s', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      END IF;
    END IF;

  END LOOP;
END;
$$;

-- 2. Backfill: Reveal the invisible records
--    Update any stock_movements with NULL tenant_id by grabbing it from the related product
UPDATE public.stock_movements sm
   SET tenant_id = p.tenant_id
  FROM public.products p
 WHERE sm.product_id = p.id
   AND sm.tenant_id IS NULL;
