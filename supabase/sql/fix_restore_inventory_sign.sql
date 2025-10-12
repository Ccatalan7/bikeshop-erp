-- ============================================================================
-- Fix: restore_sales_invoice_inventory Using Wrong Sign
-- ============================================================================
-- Problem: stock_movements.quantity is stored as NEGATIVE for OUT movements
--          When restoring, it does inventory + (-2) = inventory - 2 (WRONG!)
--          Should do inventory + ABS(-2) = inventory + 2 (CORRECT!)
--
-- Solution: Use ABS() to get the absolute value, or negate the negative
-- ============================================================================

CREATE OR REPLACE FUNCTION public.restore_sales_invoice_inventory(p_invoice public.sales_invoices)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reference TEXT;
  v_movement RECORD;
  v_has_inventory_qty BOOLEAN := FALSE;
  v_has_stock_quantity BOOLEAN := FALSE;
  v_has_is_service BOOLEAN := FALSE;
  v_has_track_stock BOOLEAN := FALSE;
  v_has_updated_at BOOLEAN := FALSE;
  v_update_assignments TEXT := '';
  v_update_sql TEXT;
  v_quantity_int INTEGER;
BEGIN
  IF p_invoice.id IS NULL THEN
    RETURN;
  END IF;

  v_reference := concat('sales_invoice:', p_invoice.id::text);

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'inventory_qty'
  ) INTO v_has_inventory_qty;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'stock_quantity'
  ) INTO v_has_stock_quantity;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'is_service'
  ) INTO v_has_is_service;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'track_stock'
  ) INTO v_has_track_stock;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'products'
      AND column_name = 'updated_at'
  ) INTO v_has_updated_at;

  IF NOT v_has_inventory_qty AND NOT v_has_stock_quantity THEN
    DELETE FROM public.stock_movements
    WHERE reference = v_reference;
    RETURN;
  END IF;

  -- ⭐ FIX: Use ABS() to ensure we're ADDING back inventory, not subtracting
  IF v_has_inventory_qty THEN
    v_update_assignments := v_update_assignments || 'inventory_qty = coalesce(inventory_qty, 0) + ABS($1)';
  END IF;

  IF v_has_stock_quantity THEN
    IF v_update_assignments <> '' THEN
      v_update_assignments := v_update_assignments || ', ';
    END IF;
    v_update_assignments := v_update_assignments || 'stock_quantity = coalesce(stock_quantity, 0) + ABS($1)';
  END IF;

  IF v_has_updated_at THEN
    IF v_update_assignments <> '' THEN
      v_update_assignments := v_update_assignments || ', ';
    END IF;
    v_update_assignments := v_update_assignments || 'updated_at = now()';
  END IF;

  IF v_update_assignments = '' THEN
    DELETE FROM public.stock_movements
    WHERE reference = v_reference;
    RETURN;
  END IF;

  v_update_sql := 'UPDATE public.products SET ' || v_update_assignments || ' WHERE id = $2';

  IF v_has_is_service THEN
    v_update_sql := v_update_sql || ' AND coalesce(is_service, false) = false';
  END IF;

  IF v_has_track_stock THEN
    v_update_sql := v_update_sql || ' AND coalesce(track_stock, true) = true';
  END IF;

  FOR v_movement IN
    SELECT product_id, quantity
    FROM public.stock_movements
    WHERE reference = v_reference
  LOOP
    IF v_movement.product_id IS NULL OR v_movement.quantity = 0 THEN
      CONTINUE;
    END IF;

    v_quantity_int := COALESCE(v_movement.quantity::INT, 0);

    IF v_quantity_int = 0 THEN
      CONTINUE;
    END IF;

    -- Execute the update - ABS() in the SQL ensures positive addition
    EXECUTE v_update_sql USING v_quantity_int, v_movement.product_id;
    
    RAISE NOTICE 'Restored inventory for product %: added % units', v_movement.product_id, ABS(v_quantity_int);
  END LOOP;

  -- Delete the stock movements after restoring
  DELETE FROM public.stock_movements
  WHERE reference = v_reference;
  
  RAISE NOTICE 'Cleaned up stock movements for invoice %', p_invoice.id;
END;
$$;

-- ============================================================================
-- What Changed:
-- ============================================================================
-- Line 81: Changed from '+ $1' to '+ ABS($1)'
-- Line 88: Changed from '+ $1' to '+ ABS($1)'
--
-- This ensures that even if stock_movements.quantity is -2 (negative),
-- we add ABS(-2) = 2 (positive) back to inventory!
-- ============================================================================
