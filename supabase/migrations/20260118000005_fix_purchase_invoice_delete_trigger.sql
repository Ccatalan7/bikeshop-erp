-- FIX: Missing Delete Trigger for Purchase Invoices
-- 
-- Problem: Deleting a 'received' purchase invoice deletes the record 
-- but leaves the inventory artificially high (Ghost Stock).
--
-- Solution: Add a BEFORE DELETE trigger that:
-- 1. Checks if the invoice boosted stock (status = received/paid).
-- 2. Decrements the stock for all items.
-- 3. Logs a 'correction' adjustment so the history explains the drop.

create or replace function public.handle_purchase_invoice_deletion()
returns trigger
language plpgsql
security definer
as $$
declare
  v_item jsonb;
  v_product_id uuid;
  v_details jsonb;
  v_quantity numeric;
  v_current_stock numeric;
  v_new_stock numeric;
begin
  -- Only reverse stock if the invoice was actually received (stock was added)
  if OLD.status in ('received', 'paid') then
    
    -- 1. Disable the generic product tracking trigger to avoid "Manual Adjustment" noise
    --    We will insert our own specific adjustment record instead.
    perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

    -- 2. Loop through all items in the invoice
    for v_item in select * from jsonb_array_elements(OLD.items)
    loop
      begin
        v_product_id := (nullif(v_item->>'product_id', '')::uuid);
        v_quantity := (v_item->>'quantity')::numeric;
      exception when others then
        v_product_id := null;
      end;

      if v_product_id is not null and v_quantity > 0 then
        -- 3. Revert the stock (Subtract the quantity that was added)
        update products 
        set stock_quantity = greatest(stock_quantity - v_quantity, 0), -- Prevent negative stock
            inventory_qty = greatest(inventory_qty - v_quantity, 0),
            updated_at = now()
        where id = v_product_id
        returning stock_quantity into v_new_stock;

        -- Calculate what it was before this subtraction
        v_current_stock := v_new_stock + v_quantity;

        -- 4. Log the Reversal in Stock Adjustments
        --    Migration 2 will pick this up and sync it to stock_movements view
        insert into stock_adjustments (
          tenant_id,
          product_id,
          adjustment_type, -- New type for clarity
          quantity,        -- Negative value implies OUT
          stock_before,
          stock_after,
          reason,
          reference,
          created_by
        ) values (
          OLD.tenant_id,
          v_product_id,
          'correction',     -- Label it as a correction
          -v_quantity,      -- Negative because we are removing stock
          v_current_stock,
          v_new_stock,
          'Reversal: Purchase Invoice Deleted #' || OLD.invoice_number,
          OLD.id::text,     -- Save the ID of the deleted invoice as ref
          auth.uid()
        );
      end if;
    end loop;
  end if;

  return OLD;
end;
$$;

-- Create the trigger
drop trigger if exists trg_handle_purchase_invoice_deletion on purchase_invoices;
create trigger trg_handle_purchase_invoice_deletion
  before delete on purchase_invoices
  for each row
  execute function public.handle_purchase_invoice_deletion();
