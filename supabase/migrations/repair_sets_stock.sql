-- ============================================================================
-- REPAIR SCRIPT: FORCE SYNC ALL SETS
-- ============================================================================
-- The trigger we added only works for FUTURE updates.
-- Use this script to fix all CURRENT inconsistencies in the database.
-- ============================================================================

DO $$
DECLARE
  v_set_id UUID;
  v_new_stock INTEGER;
  v_count INTEGER := 0;
BEGIN
  -- Looping through all products that are sets
  FOR v_set_id IN
    SELECT id FROM public.products WHERE is_set = true
  LOOP
    -- Calculate correct stock based on components
    v_new_stock := public.get_full_sets_count(v_set_id);
    
    -- Update the product if different
    UPDATE public.products
    SET 
      inventory_qty = v_new_stock,
      stock_quantity = v_new_stock,
      updated_at = now()
    WHERE id = v_set_id
      AND (inventory_qty != v_new_stock OR stock_quantity != v_new_stock);
      
    IF FOUND THEN
      v_count := v_count + 1;
      RAISE NOTICE 'Fixed Set % -> New Stock: %', v_set_id, v_new_stock;
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Sync Complete. Fixed % sets.', v_count;
END $$;
