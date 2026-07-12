-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-10
-- Phase 1: fix posted sales-invoice item edits and purchase restore audit noise.
-- Canonical mirror: supabase/sql/core_schema.sql
-- Production evidence: confirmed sales edits currently skip stock; purchase restore
-- updates generate phantom manual adjustments when the automatic-update guard is absent.

begin;

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
  v_net_quantity integer;
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
  select coalesce(sum(quantity), 0)::integer
    into v_net_quantity
    from public.stock_movements
   where reference = v_reference;

  if v_net_quantity < 0 then
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
      coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')::text as purchase_treatment,
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

    if v_item.purchase_treatment = 'workshop_consumable' then
      continue;
    end if;

    -- CHECK IF PRODUCT IS A SET
    select is_set, name
      into v_is_set, v_set_name
      from public.products
     where id = v_resolved_product_id
       and coalesce(track_stock, true) = true;

    if not found then
      continue;
    end if;

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
             set inventory_qty = coalesce(stock_quantity, inventory_qty, 0) - v_qty_to_deduct,
                 stock_quantity = coalesce(stock_quantity, inventory_qty, 0) - v_qty_to_deduct,
                 updated_at = now()
           where id = v_component.component_product_id;

          if found then
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
          end if;
       end loop;

    else
      -- STANDARD LOGIC: NOT A SET
      update public.products
         set inventory_qty = coalesce(stock_quantity, inventory_qty, 0) - v_quantity_int,
             stock_quantity = coalesce(stock_quantity, inventory_qty, 0) - v_quantity_int,
             updated_at = now()
       where id = v_resolved_product_id
         and coalesce(is_service, false) = false
         and coalesce(track_stock, true) = true;

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

-- Stable comparison of only the invoice fields that can change physical stock.
-- Price, tax, cost, notes, and line ordering must not create stock reversals.
create or replace function public.invoice_inventory_signature(p_items jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(
    jsonb_agg(item_signature order by item_signature::text),
    '[]'::jsonb
  )
  from (
    select jsonb_build_object(
      'product_id', nullif(item->>'product_id', ''),
      'product_sku', nullif(item->>'product_sku', ''),
      'quantity', coalesce(nullif(item->>'quantity', '')::numeric, 0),
      'purchase_treatment', coalesce(nullif(item->>'purchase_treatment', ''), 'inventory'),
      'is_service', coalesce(nullif(item->>'is_service', '')::boolean, false)
    ) as item_signature
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) item
  ) normalized_items;
$$;

create or replace function public.handle_sales_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  raise notice 'handle_sales_invoice_change: TG_OP=%', TG_OP;

  -- 🔄 CIRCULAR SYNC GUARD: Skip if already syncing in either direction
  if current_setting('app.syncing_job_to_invoice', true) = 'true' or
     current_setting('app.syncing_invoice_to_job', true) = 'true' then
    raise notice 'handle_sales_invoice_change: skipping due to active sync';
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

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

    -- Only process if status is "confirmed" or "paid" (NOT "draft" or "sent")
    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked trabajo with invoice data
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));

    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      -- A posted document remains the stock owner. If its item snapshot changes,
      -- reverse the previously posted snapshot and apply the new one atomically.
      -- Both helpers use the same invoice reference, so retries remain net-idempotent.
      if public.invoice_inventory_signature(OLD.items)
           is distinct from public.invoice_inventory_signature(NEW.items) then
        raise notice 'handle_sales_invoice_change: posted items changed, replacing inventory snapshot';
        perform public.restore_sales_invoice_inventory(OLD);
        perform public.consume_sales_invoice_inventory(NEW);
      else
        raise notice 'handle_sales_invoice_change: both posted without item changes, no inventory change';
      end if;
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

    -- JOURNAL ENTRY HANDLING (DELETE-based reversals, Zoho Books style)
    if v_old_posted and not v_new_posted then
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;

      -- Soft-delete associated payments
      raise notice 'handle_sales_invoice_change: reverting to non-posted, soft-deleting payments';
      update public.sales_payments
      set deleted_at = now()
      where invoice_id = OLD.id
        and deleted_at is null;

    elsif not v_old_posted and v_new_posted then
      -- Draft/Sent → Confirmed: CREATE journal entry
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);

    elsif v_old_posted and v_new_posted then
      -- Both posted: delete old, create new (amounts might have changed)
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      -- Both non-posted: no journal entry action
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked trabajo with invoice changes
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice '🔵 handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;

    -- DELETE invoice journal entry (using invoice_number as reference)
    delete from public.journal_entries
    where source_module = 'sales_invoices'
      and source_reference = OLD.invoice_number;

    -- DELETE all payment journal entries for this invoice
    delete from public.journal_entries
    where source_module = 'sales_payments'
      and source_reference in (
        select sp.id::text
          from public.sales_payments sp
         where sp.invoice_id = OLD.id
      );

    raise notice '🔵 handle_sales_invoice_change: DELETE completed, now cascade trigger should fire';
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  -- Drop and recreate trigger to ensure it uses latest function
  drop trigger if exists trg_sales_invoices_change on public.sales_invoices;

  create trigger trg_sales_invoices_change
    after insert or update or delete on public.sales_invoices
    for each row execute procedure public.handle_sales_invoice_change();

  raise notice 'Trigger trg_sales_invoices_change created successfully';
exception
  when others then
    raise notice 'Error creating trigger: %', SQLERRM;
end $$;

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
    raise notice 'restore_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  -- Purchase restore is an automatic document operation, never a manual stock
  -- adjustment. Without this guard, the products trigger creates phantom
  -- "Ajuste Manual" rows alongside the real purchase reversal.
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  -- DECREASE inventory (restore = undo IN movement) based on the current net ledger
  for v_item in
    select product_id, sum(quantity)::numeric as quantity
      from public.stock_movements
     where reference = v_reference
     group by product_id
    having sum(quantity) > 0
  loop
    if v_item.product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    update public.products
    set
      inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
      stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
    where id = v_item.product_id;

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
      v_item.product_id,
      -v_quantity_int,
      'purchase_invoice_reversal',
      'OUT',
      v_reference,
      concat(
        'Reversión de entrada por factura de compra ',
        coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
      ),
      coalesce(p_invoice.date, now()),
      now(),
      now()
    );

  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  raise notice 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    raise;
end;
$$;
create or replace function public.handle_purchase_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_new_status text;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;

    -- Inventory: ONLY if inserted directly as 'received' (rare case)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;

    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;

    perform public.recalculate_purchase_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;

    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    -- Different logic for standard vs prepayment models:
    --
    -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid
    --   Inventory added at 'received', stays through 'paid'
    --   So: received<->paid transitions do NOT change inventory
    --
    -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED
    --   Inventory added at 'received' (after payment)
    --   So: received<->paid transitions DO change inventory

    if NEW.prepayment_model then
      -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'
      if v_old_status != 'received' AND v_new_status = 'received' then
        -- Transitioning TO received (from any status): add inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status != 'received' then
        -- Transitioning FROM received (to any status): remove inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received without item changes, no inventory change';
        end if;
      end if;

    else
      -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses
      if v_old_status <> 'received' AND v_new_status = 'received' then
        -- Transitioning TO received from confirmed/sent/draft: add inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then
        -- Transitioning FROM received to confirmed/sent/draft: remove inventory
        -- Note: received→paid does NOT remove (goods stay in standard flow)
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [STANDARD] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [STANDARD] received without item changes, no inventory change';
        end if;
      end if;
    end if;

    -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
    -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
    -- It should NOT be recreated when moving between confirmed→received→paid
    -- It should ONLY be recreated if staying at same status but amounts changed

    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);

    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);

    elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
      -- Staying at same confirmed+ status but invoice data might have changed
      -- Only recreate journal if amounts changed (not just status transition)
      if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
         OLD.tax IS DISTINCT FROM NEW.tax OR
         OLD.total IS DISTINCT FROM NEW.total OR
         OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
        raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
        perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
        perform public.create_purchase_invoice_journal_entry(NEW);
      end if;
    end if;

    -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)
    -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)
    -- If items, total, subtotal, tax, or other fields changed → call recalculate
    if OLD.items IS DISTINCT FROM NEW.items OR
       OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
       OLD.tax IS DISTINCT FROM NEW.tax OR
       OLD.total IS DISTINCT FROM NEW.total OR
       OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
       OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then
      raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';
      perform public.recalculate_purchase_invoice_payments(NEW.id);
    else
      raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;

    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
    end if;

    return OLD;
  end if;

  return NULL;
end;
$$;

commit;
