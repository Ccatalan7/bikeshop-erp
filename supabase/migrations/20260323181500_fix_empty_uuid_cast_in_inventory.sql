-- Fix invalid input syntax for type uuid when casting empty strings

-- 1. Sales Invoice Inventory
create or replace function public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
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
begin
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  -- Early exit if invoice ID is null
  if p_invoice.id is null then
    raise notice 'consume_sales_invoice_inventory: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  
  -- Only process if status is posted
  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
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
    return;
  end if;

  -- Count items
  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;

  -- Process each item
  for v_item in
    select 
      nullif(item->>'product_id', '')::uuid as product_id,
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
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null or v_quantity_int <= 0 then
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set, name
      into v_is_set, v_set_name
      from public.products
     where id = v_resolved_product_id;

    if v_is_set then
       -- Iterate over components
       for v_component in
         select 
           component_product_id,
           quantity_in_set
         from public.product_set_components
         where set_product_id = v_resolved_product_id
       loop
          v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;
          
          -- Deduct Component Stock
          update public.products
             set inventory_qty = coalesce(inventory_qty, 0) - v_qty_to_deduct,
                 stock_quantity = greatest(coalesce(stock_quantity, 0) - v_qty_to_deduct, 0),
                 updated_at = now()
           where id = v_component.component_product_id;

          -- Log Component Movement (FIXED: Includes tenant_id)
          insert into public.stock_movements (
            tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
            reference, notes, date, created_at, updated_at
          ) values (
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
       end loop;

    else
      -- STANDARD LOGIC: NOT A SET
      update public.products
         set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
             stock_quantity = greatest(coalesce(stock_quantity, 0) - v_quantity_int, 0),
             updated_at = now()
       where id = v_resolved_product_id
         and coalesce(is_service, false) = false;

      if found then
        -- Create stock movement record (FIXED: Includes tenant_id)
        insert into public.stock_movements (
          tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
          reference, notes, date, created_at, updated_at
        ) values (
          p_invoice.tenant_id, -- ✅ Added tenant_id
          gen_random_uuid(),
          v_resolved_product_id,
          null,
          'OUT',
          'sale',
          -v_quantity_int,
          v_reference,
          concat('Salida por venta (Factura ', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text), ')'),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      end if;
    end if;
  end loop;

  raise notice 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;


-- 2. Purchase Invoice Inventory (Consume)
create or replace function public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
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
begin
  -- CRITICAL: Set flag to skip stock_adjustment trigger for automatic changes
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  
  if p_invoice.id is null then
    raise notice 'consume_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'consume_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      (item->>'product_name')::text as product_name,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      raise notice 'consume_purchase_invoice_inventory: skipping item with null product_id';
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      raise notice 'consume_purchase_invoice_inventory: skipping item % with zero quantity', v_resolved_product_id;
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set into v_is_set from products where id = v_resolved_product_id;
    
    if v_is_set then
        -- LOGIC FOR SETS: Explode into components
        raise notice 'consume_purchase_invoice_inventory: exploding set % into components', v_resolved_product_id;
        
        for v_child in
            select 
                component_product_id, 
                quantity_in_set
            from product_set_components
            where set_product_id = v_resolved_product_id
        loop
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            -- Update Component Inventory
            update public.products
            set 
              inventory_qty = inventory_qty + v_child_qty,
              stock_quantity = stock_quantity + v_child_qty
            where id = v_child.component_product_id;
            
            -- Record Stock Movement for Component
            insert into public.stock_movements (
              tenant_id,
              product_id,
              quantity,
              movement_type,
              type,
              reference,
              notes,
              date,
              created_at,
              updated_at
            ) values (
              p_invoice.tenant_id,
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
        end loop;
        
    else
        -- STANDARD LOGIC: Update product inventory directly
        update public.products
        set 
          inventory_qty = inventory_qty + v_quantity_int,
          stock_quantity = stock_quantity + v_quantity_int
        where id = v_resolved_product_id;

        -- Record stock movement
        insert into public.stock_movements (
          tenant_id,
          product_id,
          quantity,
          movement_type,
          type,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) values (
          p_invoice.tenant_id,
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
    end if;

  end loop;

  raise notice 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;


-- 3. Purchase Invoice Inventory (Restore)
create or replace function public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
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
begin
  if p_invoice.id is null then
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'restore_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  -- Delete ALL stock movements for this reference (cleans up both sets and normal products)
  delete from public.stock_movements
  where reference = v_reference;

  -- DECREASE inventory (restore = undo IN movement)
  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set into v_is_set from products where id = v_resolved_product_id;

    if v_is_set then
        -- SET LOGIC: Restore components
        for v_child in
            select 
                component_product_id, 
                quantity_in_set
            from product_set_components
            where set_product_id = v_resolved_product_id
        loop
            v_child_qty := v_quantity_int * v_child.quantity_in_set;
            
            update public.products
            set 
              inventory_qty = greatest(inventory_qty - v_child_qty, 0),
              stock_quantity = greatest(stock_quantity - v_child_qty, 0)
            where id = v_child.component_product_id;
        end loop;
        
    else
        -- STANDARD LOGIC
        update public.products
        set 
          inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
          stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
        where id = v_resolved_product_id;
    end if;

  end loop;
end;
$$;


-- 4. Calculate stock_at_receipt
create or replace function public.backfill_stock_at_receipt_for_received_items()
returns void
language plpgsql
security definer
as $$
declare
  v_item record;
  v_purchased_qty integer;
  v_invoice_item jsonb;
begin
  -- Loop through all received items that don't have stock_at_receipt yet
  for v_item in 
    select 
      spl.id,
      spl.product_id,
      spl.stock_at_order,
      spl.linked_purchase_invoice_id,
      spl.tenant_id
    from smart_purchase_list spl
    where spl.status = 'received'
      and spl.stock_at_receipt is null
      and spl.linked_purchase_invoice_id is not null
      and spl.stock_at_order is not null
  loop
    -- Get the purchased quantity from the invoice
    select 
      sum((item->>'quantity')::integer) into v_purchased_qty
    from purchase_invoices pi,
         jsonb_array_elements(pi.items) as item
    where pi.id = v_item.linked_purchase_invoice_id
      and nullif(item->>'product_id', '')::uuid = v_item.product_id;
    
    if v_purchased_qty is not null then
      -- Calculate stock_at_receipt = stock_at_order + purchased_quantity
      update smart_purchase_list
      set stock_at_receipt = v_item.stock_at_order + v_purchased_qty
      where id = v_item.id;
      
      raise notice '✅ Backfilled stock_at_receipt for product % (was %, purchased %, now %)', 
        v_item.product_id, v_item.stock_at_order, v_purchased_qty, v_item.stock_at_order + v_purchased_qty;
    end if;
  end loop;
end;
$$;
