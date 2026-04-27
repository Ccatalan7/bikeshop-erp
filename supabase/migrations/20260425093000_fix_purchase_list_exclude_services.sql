-- Fix: services / non-stock items must never be auto-added to smart_purchase_list
-- Source of truth: supabase/sql/core_schema.sql

begin;

create or replace function public.auto_add_low_stock_to_purchase_list()
returns trigger
language plpgsql
security definer
as $$
declare
  v_supplier_id uuid;
  v_supplier_name text;
  v_rotation_kpi numeric(5,2);
  v_avg_daily_consumption numeric(10,2);
  v_days_since_last_purchase integer;
  v_suggested_qty integer;
  v_priority numeric(5,2);
  v_lead_time_days integer;
  v_estimated_stockout_date timestamp with time zone;
  v_current_stock integer;
begin
  -- Sync inventory_qty to match stock_quantity (stock_quantity is source of truth)
  -- This ensures both columns stay in sync for backward compatibility
  if NEW.stock_quantity != NEW.inventory_qty then
    NEW.inventory_qty := NEW.stock_quantity;
  end if;

  -- Use whichever column is set (prefer stock_quantity as source of truth)
  v_current_stock := coalesce(NEW.stock_quantity, NEW.inventory_qty, 0);

  -- Services and non-stock-tracked items must NEVER be added to the smart
  -- purchase list. If they were previously auto-added (legacy bug), clean them
  -- up opportunistically whenever this trigger fires.
  if coalesce(NEW.product_type, 'product') = 'service'
     or coalesce(NEW.track_stock, true) = false then
    delete from smart_purchase_list
    where product_id = NEW.id
      and tenant_id = NEW.tenant_id
      and status in ('pending', 'ordered');
    return NEW;
  end if;

  -- AUTO-REMOVAL: If stock is now ABOVE minimum level, remove from pending list
  if v_current_stock > NEW.min_stock_level then
    delete from smart_purchase_list
    where product_id = NEW.id
    and status = 'pending'
    and tenant_id = NEW.tenant_id;

    if found then
      raise notice '🗑️ Auto-removed product % (%) from purchase list - stock restored to %', NEW.name, NEW.sku, v_current_stock;
    end if;

    return NEW;
  end if;

  -- AUTO-ADD: Trigger when stock is at or below minimum level
  if v_current_stock <= NEW.min_stock_level then

    -- Check if product is already in the purchase list with pending/ordered status
    if exists (
      select 1 from smart_purchase_list
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id
    ) then
      -- Already in list, just update the current stock
      update smart_purchase_list
      set current_stock = v_current_stock,
          updated_at = now()
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id;

      return NEW;
    end if;

    -- Get supplier info (use default supplier if product has one)
    select s.id, s.name into v_supplier_id, v_supplier_name
    from suppliers s
    where s.tenant_id = NEW.tenant_id
    and s.is_active = true
    order by s.created_at asc
    limit 1;

    -- Calculate rotation KPI (sales per day over last 30 days)
    -- Use JSONB items array since we don't have a separate line items table
    select
      coalesce(
        (select count(*)::numeric / 30.0
         from sales_invoices si,
         jsonb_array_elements(si.items) as item
         where item->>'product_id' = NEW.id::text
         and si.tenant_id = NEW.tenant_id
         and si.date >= now() - interval '30 days'),
        0
      ) into v_rotation_kpi;

    -- Average daily consumption
    v_avg_daily_consumption := greatest(v_rotation_kpi, 0.1);

    -- Days since last purchase
    -- Use JSONB items array since we don't have a separate line items table
    select
      extract(day from now() - max(pi.date))::integer into v_days_since_last_purchase
    from purchase_invoices pi,
    jsonb_array_elements(pi.items) as item
    where item->>'product_id' = NEW.id::text
    and pi.tenant_id = NEW.tenant_id;

    v_days_since_last_purchase := coalesce(v_days_since_last_purchase, 999);

    -- Suggested quantity: enough to reach max stock or at least cover 30 days
    v_suggested_qty := greatest(
      NEW.max_stock_level - v_current_stock,
      ceil(v_avg_daily_consumption * 30)::integer,
      1
    );

    -- Lead time (default 7 days, could be supplier-specific in the future)
    v_lead_time_days := 7;

    -- Estimated stockout date
    if v_avg_daily_consumption > 0 then
      v_estimated_stockout_date := now() + (v_current_stock / v_avg_daily_consumption || ' days')::interval;
    else
      v_estimated_stockout_date := null;
    end if;

    -- Calculate priority (0-100 scale)
    -- Formula: rotation * 0.6 + urgency * 0.3 + days_since_purchase * 0.1
    v_priority := least(100, greatest(0,
      (v_rotation_kpi * 10 * 0.6) + -- rotation scaled to 0-100
      (case
        when v_current_stock = 0 then 100
        when coalesce(NEW.min_stock_level, 0) = 0 then 50 -- Default urgency when min_stock_level is 0 or null
        else (1 - (v_current_stock::numeric / NEW.min_stock_level)) * 100
      end * 0.3) + -- urgency
      (least(v_days_since_last_purchase, 100) * 0.1) -- days since last purchase capped at 100
    ));

    -- Insert into smart purchase list
    insert into smart_purchase_list (
      tenant_id,
      product_id,
      product_name,
      product_sku,
      supplier_id,
      supplier_name,
      suggested_quantity,
      status,
      priority,
      rotation_kpi,
      days_since_last_purchase,
      current_stock,
      min_stock_level,
      avg_daily_consumption,
      lead_time_days,
      estimated_stockout_date,
      notes,
      added_date
    ) values (
      NEW.tenant_id,
      NEW.id,
      NEW.name,
      NEW.sku,
      v_supplier_id,
      v_supplier_name,
      v_suggested_qty,
      'pending',
      v_priority,
      v_rotation_kpi,
      v_days_since_last_purchase,
      v_current_stock,
      NEW.min_stock_level,
      v_avg_daily_consumption,
      v_lead_time_days,
      v_estimated_stockout_date,
      'Auto-added: stock at or below minimum level',
      now()
    );

    raise notice '✅ Auto-added product % (%) to purchase list with priority %', NEW.name, NEW.sku, v_priority;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_auto_add_low_stock on products;
create trigger trg_auto_add_low_stock
  after insert or update of stock_quantity, inventory_qty
  on products
  for each row
  execute function public.auto_add_low_stock_to_purchase_list();

-- Legacy cleanup: remove invalid active purchase-list rows for services and
-- non-stock items (they can never be actioned by the module anyway).
delete from smart_purchase_list spl
using products p
where p.id = spl.product_id
  and p.tenant_id = spl.tenant_id
  and spl.status in ('pending', 'ordered')
  and (
    coalesce(p.product_type, 'product') = 'service'
    or coalesce(p.track_stock, true) = false
  );

commit;

