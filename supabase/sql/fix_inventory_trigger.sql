-- Fix for inventory reduction when sales invoice status changes to 'sent'/'enviado'
-- This script replaces the existing trigger with a more robust version

-- Drop and recreate the consume_sales_invoice_inventory function with better logging
create or replace function public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_items_count integer;
begin
  -- Early exit if invoice ID is null
  if p_invoice.id is null then
    raise notice 'consume_sales_invoice_inventory: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  raise notice 'consume_sales_invoice_inventory: invoice %, status %', p_invoice.id, v_status;

  -- Only process if status is posted (not draft/cancelled)
  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
    raise notice 'consume_sales_invoice_inventory: status is non-posted, skipping';
    return;
  end if;

  -- Check if inventory reduction already done
  v_reference := concat('sales_invoice:', p_invoice.id::text);
  if exists (
       select 1
         from public.stock_movements
        where reference = v_reference
          and type = 'OUT'
     ) then
    raise notice 'consume_sales_invoice_inventory: inventory already reduced for %', v_reference;
    return;
  end if;

  -- Count items
  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;
  
  raise notice 'consume_sales_invoice_inventory: processing % items', v_items_count;

  -- Process each item
  for v_item in
    select 
      (item->>'product_id')::uuid as product_id,
      (item->>'product_sku')::text as product_sku,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
  loop
    v_resolved_product_id := v_item.product_id;

    -- Try to resolve by SKU if product_id is null
    if v_resolved_product_id is null and v_item.product_sku is not null and v_item.product_sku != '' then
      select id
        into v_resolved_product_id
        from public.products
       where sku = v_item.product_sku
       limit 1;
      
      raise notice 'consume_sales_invoice_inventory: resolved product % by SKU %', v_resolved_product_id, v_item.product_sku;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null then
      raise notice 'consume_sales_invoice_inventory: skipping item - product_id is null, sku: %', v_item.product_sku;
      continue;
    end if;

    if v_quantity_int <= 0 then
      raise notice 'consume_sales_invoice_inventory: skipping item - quantity <= 0, product: %', v_resolved_product_id;
      continue;
    end if;

    -- Reduce inventory (check both inventory_qty and stock_quantity columns)
    update public.products
       set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
           updated_at = now()
     where id = v_resolved_product_id
       and coalesce(is_service, false) = false;

    if found then
      raise notice 'consume_sales_invoice_inventory: reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
      
      -- Create stock movement record
      insert into public.stock_movements (
        id,
        product_id,
        warehouse_id,
        type,
        movement_type,
        quantity,
        reference,
        notes,
        date,
        created_at,
        updated_at
      ) values (
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
    else
      raise notice 'consume_sales_invoice_inventory: product % is a service or does not exist', v_resolved_product_id;
    end if;
  end loop;

  raise notice 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

-- Simplified trigger function with better logic
create or replace function public.handle_sales_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada'];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  raise notice 'handle_sales_invoice_change: TG_OP=%', TG_OP;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'handle_sales_invoice_change: trigger depth > 1, returning';
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    raise notice 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- If inserted with posted status, consume inventory
    if not (v_new_status = any (v_non_posted)) then
      perform public.consume_sales_invoice_inventory(NEW);
    end if;
    
    -- Create journal entry
    perform public.create_sales_invoice_journal_entry(NEW);
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      -- Both statuses are posted: restore old inventory, consume new
      raise notice 'handle_sales_invoice_change: both posted, restore and consume';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      -- Changed from posted to non-posted: restore inventory
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      -- Changed from non-posted to posted: consume inventory
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      -- Both non-posted: no inventory change
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    -- Update journal entries
    perform public.delete_sales_invoice_journal_entry(OLD.id);
    perform public.create_sales_invoice_journal_entry(NEW);
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice 'handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;
    
    perform public.delete_sales_invoice_journal_entry(OLD.id);
    return OLD;
  end if;

  return NULL;
end;
$$;

-- Ensure the trigger exists
do $$
begin
  -- Drop existing trigger if it exists
  drop trigger if exists trg_sales_invoices_change on public.sales_invoices;
  
  -- Create the trigger
  create trigger trg_sales_invoices_change
    after insert or update or delete on public.sales_invoices
    for each row execute procedure public.handle_sales_invoice_change();
    
  raise notice 'Trigger trg_sales_invoices_change created successfully';
end $$;

-- Test query to check if the trigger is properly installed
select 
  t.tgname as trigger_name,
  c.relname as table_name,
  p.proname as function_name,
  case 
    when t.tgtype & 2 = 2 then 'BEFORE'
    when t.tgtype & 64 = 64 then 'INSTEAD OF'
    else 'AFTER'
  end as timing,
  array_to_string(
    array[
      case when t.tgtype & 4 = 4 then 'INSERT' end,
      case when t.tgtype & 8 = 8 then 'DELETE' end,
      case when t.tgtype & 16 = 16 then 'UPDATE' end
    ]::text[], 
    ' OR '
  ) as events
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc p on p.oid = t.tgfoid
where c.relname = 'sales_invoices'
  and t.tgname = 'trg_sales_invoices_change';
