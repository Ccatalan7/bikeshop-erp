-- COMPLETE FIX for inventory reduction issue
-- This script combines both fixes: enum conversion + trigger update
-- Run this ONCE in your Supabase SQL Editor

-- ============================================================================
-- PART 1: Fix the movement_type enum issue
-- ============================================================================

do $$
declare
  v_is_enum boolean;
  v_enum_values text[];
begin
  raise notice '=== PART 1: Fixing movement_type column type ===';
  
  -- Check if movement_type column uses an enum type
  select exists (
    select 1
    from pg_type t
    join pg_enum e on t.oid = e.enumtypid
    join pg_attribute a on a.atttypid = t.oid
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'stock_movements'
      and a.attname = 'movement_type'
      and t.typtype = 'e'
  ) into v_is_enum;

  if v_is_enum then
    raise notice 'movement_type is an enum, converting to text...';
    
    -- Get existing enum values for reference
    select array_agg(enumlabel::text order by enumsortorder)
    into v_enum_values
    from pg_type t
    join pg_enum e on t.oid = e.enumtypid
    join pg_attribute a on a.atttypid = t.oid
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'stock_movements'
      and a.attname = 'movement_type'
      and t.typtype = 'e';
    
    raise notice 'Existing enum values were: %', v_enum_values;
    
    -- Convert column to text
    alter table public.stock_movements 
      alter column movement_type type text using movement_type::text;
    
    raise notice '✓ Converted movement_type to text';
  else
    raise notice '✓ movement_type is already text';
  end if;
  
  -- Ensure the column is nullable
  alter table public.stock_movements alter column movement_type drop not null;
  
  raise notice '✓ Stock movements table is ready';
exception
  when others then
    raise exception 'Error fixing movement_type: %', SQLERRM;
end $$;

-- ============================================================================
-- PART 2: Update the consume inventory function with better logging
-- ============================================================================

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
  raise notice '=== consume_sales_invoice_inventory START ===';
  
  -- Early exit if invoice ID is null
  if p_invoice.id is null then
    raise notice 'ERROR: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  raise notice 'Invoice ID: %, Status: %', p_invoice.id, v_status;

  -- Only process if status is posted (not draft/cancelled)
  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
    raise notice 'Status is non-posted, skipping inventory reduction';
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
    raise notice 'Inventory already reduced for %, skipping', v_reference;
    return;
  end if;

  -- Count items
  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;
  
  raise notice 'Processing % items from invoice', v_items_count;

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
      
      raise notice '  Resolved product % by SKU %', v_resolved_product_id, v_item.product_sku;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null then
      raise notice '  SKIP: product_id is null (SKU: %)', v_item.product_sku;
      continue;
    end if;

    if v_quantity_int <= 0 then
      raise notice '  SKIP: quantity <= 0 for product %', v_resolved_product_id;
      continue;
    end if;

    -- Reduce inventory
    update public.products
       set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
           updated_at = now()
     where id = v_resolved_product_id
       and coalesce(is_service, false) = false;

    if found then
      raise notice '  ✓ Reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
      
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
        'sales_invoice',  -- Now this will work because movement_type is TEXT
        -v_quantity_int,
        v_reference,
        format('Salida por factura %s', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)),
        coalesce(p_invoice.date, now()),
        now(),
        now()
      );
      
      raise notice '  ✓ Created stock movement record';
    else
      raise notice '  SKIP: Product % is a service or does not exist', v_resolved_product_id;
    end if;
  end loop;

  raise notice '=== consume_sales_invoice_inventory COMPLETE ===';
end;
$$;

-- ============================================================================
-- PART 3: Update the trigger function with better logging
-- ============================================================================

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
  raise notice '=== TRIGGER handle_sales_invoice_change: % ===', TG_OP;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'Trigger depth > 1, preventing recursion';
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    raise notice 'INSERT invoice %, status: %', NEW.id, v_new_status;
    
    if not (v_new_status = any (v_non_posted)) then
      perform public.consume_sales_invoice_inventory(NEW);
    end if;
    
    perform public.create_sales_invoice_journal_entry(NEW);
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    raise notice 'UPDATE invoice %, status change: % -> %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    if v_old_posted and v_new_posted then
      raise notice 'Both posted: restore old, consume new';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      raise notice 'Changed to non-posted: restore inventory';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      raise notice 'Changed to posted: consume inventory';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      raise notice 'Both non-posted: no inventory change';
    end if;

    perform public.delete_sales_invoice_journal_entry(OLD.id);
    perform public.create_sales_invoice_journal_entry(NEW);
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice 'DELETE invoice %, status: %', OLD.id, v_old_status;
    
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;
    
    perform public.delete_sales_invoice_journal_entry(OLD.id);
    return OLD;
  end if;

  return NULL;
end;
$$;

-- ============================================================================
-- PART 4: Ensure the trigger is installed
-- ============================================================================

do $$
begin
  raise notice '=== PART 4: Installing trigger ===';
  
  drop trigger if exists trg_sales_invoices_change on public.sales_invoices;
  
  create trigger trg_sales_invoices_change
    after insert or update or delete on public.sales_invoices
    for each row execute procedure public.handle_sales_invoice_change();
    
  raise notice '✓ Trigger trg_sales_invoices_change installed successfully';
end $$;

-- ============================================================================
-- PART 5: Verification
-- ============================================================================

-- Check movement_type column
select 
  '1. movement_type column:' as check_step,
  c.data_type,
  c.is_nullable
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'stock_movements'
  and c.column_name = 'movement_type';

-- Check trigger
select 
  '2. Trigger installed:' as check_step,
  t.tgname as trigger_name,
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
where c.relname = 'sales_invoices'
  and t.tgname = 'trg_sales_invoices_change';

-- Success message
do $$
begin
  raise notice '';
  raise notice '════════════════════════════════════════════════════════════════';
  raise notice '✓ ALL FIXES APPLIED SUCCESSFULLY';
  raise notice '════════════════════════════════════════════════════════════════';
  raise notice '';
  raise notice 'You can now test by:';
  raise notice '1. Creating a sales invoice with status "draft"';
  raise notice '2. Marking it as "sent" (enviado)';
  raise notice '3. Checking that inventory is reduced';
  raise notice '4. Verifying a stock_movement record was created';
  raise notice '';
end $$;
