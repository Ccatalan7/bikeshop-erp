-- FIX: "Manual" Adjustments for Purchases
-- 
-- Problem: When a purchase invoice is received, the system updates stock but 
-- the logging trigger (track_product_stock_changes) doesn't know it's a purchase,
-- so it defaults to recording it as a "Manual Adjustment".
--
-- Solution:
-- 1. Update the logging function to recognize 'purchase' context.
-- 2. Add a trigger to purchase_invoices to SET this context before processing.

-- PART 1: Update the tracking function to handle 'purchase' types
create or replace function track_product_stock_changes()
returns trigger as $$
declare
  v_adjustment_type text;
  v_reason text;
  v_reference text;
  v_context text;
begin
  -- Services and non-stock-tracked items should not generate stock adjustments.
  if coalesce(NEW.product_type, 'product') = 'service'
     or coalesce(NEW.track_stock, true) = false then
    return NEW;
  end if;

  -- CRITICAL: Only track MANUAL changes, not automatic ones from invoice triggers
  -- Skip if this update is triggered by invoice consumption functions
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;

  -- Only track if stock_quantity actually changed
  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    
    v_context := current_setting('app.stock_adjustment_context', true);

    -- Determine adjustment type based on context
    if v_context = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(current_setting('app.import_reason', true), 'Stock updated via import');
      v_reference := current_setting('app.import_reference', true);
    
    elsif v_context = 'purchase' then
      -- ✅ NEW: Handle purchase context
      v_adjustment_type := 'purchase'; 
      v_reason := 'Compra recibida (Invoice ' || coalesce(current_setting('app.stock_adjustment_reference', true), 'Unknown') || ')';
      v_reference := current_setting('app.stock_adjustment_reference', true);

    else
      v_adjustment_type := 'manual';
      v_reason := 'Ajuste Manual'; -- Changed label to match user expectation
      v_reference := null;
    end if;

    -- Insert into stock_adjustments (which now syncs to stock_movements via Migration 2)
    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity - OLD.stock_quantity,
      OLD.stock_quantity,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );

  elsif (TG_OP = 'INSERT' and NEW.stock_quantity > 0) then
    -- Track initial stock logic (unchanged)
    v_context := current_setting('app.stock_adjustment_context', true);
    
    if v_context = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(current_setting('app.import_reason', true), 'Initial stock via import');
      v_reference := current_setting('app.import_reference', true);
    else
      v_adjustment_type := 'initial';
      v_reason := 'Initial stock on product creation';
      v_reference := null;
    end if;

    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity,
      0,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  end if;

  return NEW;
end;
$$ language plpgsql security definer;


-- PART 2: Helper trigger to SET the context when Purchase Invoices are processed
create or replace function public.set_purchase_context_on_status_change()
returns trigger
language plpgsql
as $$
begin
  -- When status changes to 'received', we are about to update stock.
  -- Set the context variables so the product trigger knows it's a purchase.
  if NEW.status = 'received' and (OLD.status is distinct from 'received') then
    
    perform set_config('app.stock_adjustment_context', 'purchase', true);
    perform set_config('app.stock_adjustment_reference', coalesce(NEW.invoice_number, NEW.id::text), true);
    
    -- Note: The scope of set_config with is_local=true is the current transaction.
    -- Since triggers run in the same transaction, the subsequent product update will see this.
  end if;
  
  return NEW;
end;
$$;

drop trigger if exists trg_set_purchase_context on purchase_invoices;
create trigger trg_set_purchase_context
  before update of status
  on purchase_invoices
  for each row
  execute function public.set_purchase_context_on_status_change();
