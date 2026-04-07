-- Fix sales invoice inventory side effects when editing invoices.
--
-- Problem 1:
--   restore_sales_invoice_inventory() updated products directly without setting
--   app.skip_stock_adjustment_trigger, so legitimate invoice reversals were being
--   recorded as bogus "Ajuste Manual" rows in stock_adjustments/stock_movements.
--
-- Problem 2:
--   handle_sales_invoice_change() restored + re-consumed inventory on ANY
--   posted->posted update, but inventory should only move on status transitions.
--
-- Expected behavior:
--   - non-posted -> posted   => consume inventory
--   - posted -> non-posted   => restore inventory
--   - posted -> posted       => NO inventory movement
--   - non-posted -> non-posted => NO inventory movement

create or replace function public.restore_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_movement record;
  v_has_inventory_qty boolean := false;
  v_has_stock_quantity boolean := false;
  v_has_is_service boolean := false;
  v_has_track_stock boolean := false;
  v_has_updated_at boolean := false;
  v_update_assignments text := '';
  v_update_sql text;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    return;
  end if;

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  v_reference := concat('sales_invoice:', p_invoice.id::text);

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'inventory_qty'
         )
    into v_has_inventory_qty;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'stock_quantity'
         )
    into v_has_stock_quantity;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'is_service'
         )
    into v_has_is_service;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'track_stock'
         )
    into v_has_track_stock;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'updated_at'
         )
    into v_has_updated_at;

  if not v_has_inventory_qty and not v_has_stock_quantity then
    delete from public.stock_movements
     where reference = v_reference;
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    return;
  end if;

  if v_has_inventory_qty then
    v_update_assignments := v_update_assignments || 'inventory_qty = coalesce(inventory_qty, 0) + $1';
  end if;

  if v_has_stock_quantity then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'stock_quantity = coalesce(stock_quantity, 0) + $1';
  end if;

  if v_has_updated_at then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'updated_at = now()';
  end if;

  if v_update_assignments = '' then
    delete from public.stock_movements
     where reference = v_reference;
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    return;
  end if;

  v_update_sql := 'update public.products set ' || v_update_assignments || ' where id = $2';

  if v_has_is_service then
    v_update_sql := v_update_sql || ' and coalesce(is_service, false) = false';
  end if;

  if v_has_track_stock then
    v_update_sql := v_update_sql || ' and coalesce(track_stock, true) = true';
  end if;

  for v_movement in
    select product_id, quantity
      from public.stock_movements
     where reference = v_reference
  loop
    if v_movement.product_id is null or v_movement.quantity = 0 then
      continue;
    end if;

    v_quantity_int := abs(coalesce(v_movement.quantity::int, 0));

    if v_quantity_int = 0 then
      continue;
    end if;

    execute v_update_sql using v_quantity_int, v_movement.product_id;
  end loop;

  delete from public.stock_movements
   where reference = v_reference;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
end;
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

  if current_setting('app.syncing_job_to_invoice', true) = 'true' or
     current_setting('app.syncing_invoice_to_job', true) = 'true' then
    raise notice 'handle_sales_invoice_change: skipping due to active sync';
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

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

    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));

    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    if v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: both posted, no inventory change';
    elsif v_old_posted and not v_new_posted then
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    if v_old_posted and not v_new_posted then
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;

      raise notice 'handle_sales_invoice_change: reverting to non-posted, soft-deleting payments';
      update public.sales_payments
      set deleted_at = now()
      where invoice_id = OLD.id
        and deleted_at is null;

    elsif not v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);

    elsif v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice '🔵 handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;

    delete from public.journal_entries
    where source_module = 'sales_invoices'
      and source_reference = OLD.invoice_number;

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

  return null;
end;
$$;
