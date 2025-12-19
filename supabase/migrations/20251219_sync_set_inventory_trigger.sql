-- ============================================================================
-- TRIGGER: Sync Set Inventory from Component Updates
-- ============================================================================
-- Ensures that when a component product's stock changes, any parent Sets
-- that contain this component are automatically recalculated.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_set_inventory_from_component()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_set_id UUID;
  v_new_set_stock INTEGER;
BEGIN
  -- If app.skip_sync_set_inventory is set, skip this trigger to avoid recursion loops
  -- (though strictly speaking, updating the parent set shouldn't trigger this again for the component)
  IF current_setting('app.skip_sync_set_inventory', true) = 'true' THEN
    RETURN OLD; -- Trigger is AFTER UPDATE, return value ignored but good practice
  END IF;

  -- Find all parent sets that contain this product as a component
  FOR v_set_id IN
    SELECT set_product_id
    FROM public.product_set_components
    WHERE component_product_id = NEW.id
  LOOP
    -- Calculate how many full sets can be made from ALL components now
    -- We use the existing helper function: public.get_full_sets_count(set_id)
    v_new_set_stock := public.get_full_sets_count(v_set_id);

    RAISE NOTICE 'Syncing Set %: Component % changed stock to %. New Set Stock: %', 
      v_set_id, NEW.id, NEW.stock_quantity, v_new_set_stock;

    -- Update the parent set's inventory
    -- We set app.skip_stock_adjustment_trigger to true to avoid creating stock movements for this automatic sync
    -- We also set app.skip_sync_set_inventory to true to verify no recursion happens (though unrelated)
    PERFORM set_config('app.skip_stock_adjustment_trigger', 'true', true);

    UPDATE public.products
    SET 
      inventory_qty = v_new_set_stock,
      stock_quantity = v_new_set_stock,
      updated_at = now()
    WHERE id = v_set_id
      AND (inventory_qty != v_new_set_stock OR stock_quantity != v_new_set_stock); -- Only update if changed
      
  END LOOP;

  RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_sync_set_inventory_from_component ON public.products;

CREATE TRIGGER trg_sync_set_inventory_from_component
  AFTER UPDATE OF inventory_qty, stock_quantity
  ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_set_inventory_from_component();
