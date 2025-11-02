-- Fix auto_add_low_stock_to_purchase_list() trigger to use JSONB items instead of non-existent tables
-- This fixes the error: relation "sales_invoice_items" does not exist

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
begin
  -- Only trigger when stock drops to or below minimum level
  if (NEW.stock_quantity <= NEW.min_stock_level) and 
     (OLD.stock_quantity is null or OLD.stock_quantity > NEW.min_stock_level) then
    
    -- Check if product is already in the purchase list with pending/ordered status
    if exists (
      select 1 from smart_purchase_list
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id
    ) then
      -- Already in list, just update the current stock
      update smart_purchase_list
      set current_stock = NEW.stock_quantity,
          updated_at = now()
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id;
      
      return NEW;
    end if;
    
    -- Get supplier info (use product's assigned supplier or first active supplier)
    select s.id, s.name into v_supplier_id, v_supplier_name
    from suppliers s
    where s.tenant_id = NEW.tenant_id
    and (s.id = NEW.supplier_id or NEW.supplier_id is null)
    and s.is_active = true
    order by 
      case when s.id = NEW.supplier_id then 0 else 1 end,
      s.created_at asc
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
      NEW.max_stock_level - NEW.stock_quantity,
      ceil(v_avg_daily_consumption * 30)::integer,
      1
    );
    
    -- Lead time (default 7 days)
    v_lead_time_days := 7;
    
    -- Estimated stockout date
    if v_avg_daily_consumption > 0 then
      v_estimated_stockout_date := now() + (NEW.stock_quantity / v_avg_daily_consumption || ' days')::interval;
    else
      v_estimated_stockout_date := null;
    end if;
    
    -- Calculate priority (0-100 scale, higher = more urgent)
    v_priority := least(100, greatest(0,
      (100 - ((NEW.stock_quantity::numeric / greatest(NEW.min_stock_level, 1)) * 50)) +
      (v_rotation_kpi * 10) +
      (v_days_since_last_purchase / 10.0)
    ));
    
    -- Insert into smart purchase list
    insert into smart_purchase_list (
      tenant_id,
      product_id,
      product_name,
      product_sku,
      current_stock,
      min_stock_level,
      suggested_quantity,
      supplier_id,
      supplier_name,
      priority,
      rotation_kpi,
      estimated_stockout_date,
      status
    ) values (
      NEW.tenant_id,
      NEW.id,
      NEW.name,
      NEW.sku,
      NEW.stock_quantity,
      NEW.min_stock_level,
      v_suggested_qty,
      v_supplier_id,
      v_supplier_name,
      v_priority,
      v_rotation_kpi,
      v_estimated_stockout_date,
      'pending'
    );
    
  end if;
  
  return NEW;
end;
$$;
