-- Migration: Allow General Items
-- Updates sync_invoice_items_to_job to allow items to not be assigned to a specific bike.

CREATE OR REPLACE FUNCTION public.sync_invoice_items_to_job(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  v_job_id uuid;
  v_invoice record;
  v_item jsonb;
  v_subtotal numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_parts_cost numeric(12,2) := 0;
  v_product_id uuid;
  v_product_type text;
  v_product_name text;
  v_quantity numeric(12,2);
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_tenant_id uuid;
  v_job_bike_id uuid;
  v_default_bike_id uuid;
begin
  -- Prevent circular sync: if we're already deep in triggers, skip
  if pg_trigger_depth() > 2 then
    raise notice 'sync_invoice_items_to_job: trigger depth too deep (%), skipping to prevent circular sync', pg_trigger_depth();
    return;
  end if;

  -- Find the job linked to this invoice
  select id into v_job_id
  from mechanic_jobs
  where invoice_id = p_invoice_id;
  
  if v_job_id is null then
    return;
  end if;
  
  -- Get invoice details
  select * into v_invoice
  from sales_invoices
  where id = p_invoice_id;
  
  if not found then
    return;
  end if;
  
  v_tenant_id := v_invoice.tenant_id;
  
  -- Get the default (first) bike for validation purposes, but don't force it for all items
  select id into v_default_bike_id
  from mechanic_job_bikes
  where job_id = v_job_id
  order by order_index
  limit 1;
  
  -- Set a flag to prevent reverse sync
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  
  -- Delete existing job items (we'll recreate them from invoice)
  delete from mechanic_job_items where job_id = v_job_id;
  
  -- Process each invoice item
  for v_item in select * from jsonb_array_elements(v_invoice.items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::numeric, 1);
    v_unit_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_line_total := coalesce((v_item->>'line_total')::numeric, v_quantity * v_unit_price, 0);
    v_product_name := v_item->>'product_name';

    -- Resolve job_bike_id from item JSON
    v_job_bike_id := nullif(v_item->>'job_bike_id', '')::uuid;
    
    -- If job_bike_id is provided, validate it exists for this job. If it doesn't, we fallback to default OR null it out.
    -- Let's fallback to null (General) if the assigned bike was deleted, to be safe.
    if v_job_bike_id is not null then
      if not exists (
        select 1 from mechanic_job_bikes 
        where id = v_job_bike_id and job_id = v_job_id
      ) then
        v_job_bike_id := null;
      end if;
    end if;

    -- Determine product info (if exists)
    v_product_type := null;
    v_product_name := null;
    if v_product_id is not null then
      select product_type, name
      into v_product_type, v_product_name
      from products
      where id = v_product_id;
      if not found then
        v_product_type := null;
        v_product_name := null;
      end if;
    end if;

    if v_product_id is null or v_product_type = 'service' then
      v_labor_cost := v_labor_cost + v_line_total;
    else
      v_parts_cost := v_parts_cost + v_line_total;
    end if;

    insert into mechanic_job_items (
      tenant_id,
      job_id,
      job_bike_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      total_price,
      notes,
      description,
      item_type,
      service_product_id,
      created_at,
      updated_at
    ) values (
      v_tenant_id,
      v_job_id,
      v_job_bike_id,
      case when v_product_type = 'service' then null else v_product_id end,
      coalesce(v_product_name, v_item->>'product_name'),
      coalesce(v_item->>'product_sku', ''),
      case when v_quantity is null or v_quantity = 0 then 1 else v_quantity end,
      v_unit_price,
      v_line_total,
      coalesce(v_item->>'description', ''),
      coalesce(v_item->>'description', ''),
      case when v_product_id is null or v_product_type = 'service' then 'service' else 'product' end,
      case when v_product_id is null or v_product_type = 'service' then v_product_id else null end,
      now(),
      now()
    );
  end loop;
  
  v_subtotal := v_parts_cost + v_labor_cost;
  
  -- Update job costs
  update mechanic_jobs
  set 
    labor_cost = v_labor_cost,
    parts_cost = v_parts_cost,
    final_cost = v_subtotal,
    estimated_cost = v_subtotal,
    total_cost = v_invoice.total,
    tax_amount = v_invoice.iva_amount,
    updated_at = now()
  where id = v_job_id;
  
  -- Clear the sync flag
  perform set_config('app.syncing_invoice_to_job', '', true);
  
end;
$$;
