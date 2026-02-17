-- Fix for Description Sync (Job -> Invoice)
-- Issue: sync_job_to_invoice was not mapping 'notes' (Job Item Description) to 'description' (Invoice Item Description).
-- Fix: Add 'description' field to the JSONB object when building invoice items.

create or replace function public.sync_job_to_invoice(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_job record;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_iva_amount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_syncing_flag text;
begin
  -- Check if we're currently syncing invoice → job (prevent circular sync)
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  if v_syncing_flag = 'true' then
    raise notice 'sync_job_to_invoice: skipping due to invoice→job sync in progress';
    return;
  end if;

  -- Get the job and its linked invoice
  select * into v_job
  from mechanic_jobs
  where id = p_job_id;
  
  if not found then
    raise notice 'Job % not found', p_job_id;
    return;
  end if;
  
  v_invoice_id := v_job.invoice_id;
  
  if v_invoice_id is null then
    raise notice 'Job % has no linked invoice', p_job_id;
    return;
  end if;
  
  select coalesce(discount_amount, 0)
  into v_discount
  from mechanic_jobs
  where id = p_job_id;
  
  -- Build invoice items array from mechanic_job_items (products + services)
  for v_item in 
    select * from mechanic_job_items where job_id = p_job_id
  loop
    v_items := v_items || jsonb_build_object(
      'product_id', case when coalesce(v_item.item_type, 'product') = 'service'
                         then coalesce(v_item.service_product_id::text, '')
                         else v_item.product_id::text
                    end,
      'product_name', v_item.product_name,
      'description', coalesce(v_item.notes, ''), -- ✅ MAP NOTES TO DESCRIPTION
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0)
    );

    if coalesce(v_item.item_type, 'product') in ('service', 'adhoc') then
      v_labor_cost := v_labor_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    else
      v_parts_cost := v_parts_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    end if;
  end loop;
  
  -- Calculate totals with FRESH data (not using stale v_job record)
  v_subtotal := v_parts_cost + v_labor_cost - v_discount;
  
  -- Calculate IVA based on job's tax treatment
  if v_job.tax_treatment = 'tax_included' then
    v_iva_amount := round(v_subtotal - (v_subtotal / 1.19), 0);
  else
    v_iva_amount := 0;
  end if;
  
  v_total := v_subtotal;
  
  -- Update the invoice with fresh calculations
  perform set_config('app.syncing_job_to_invoice', 'true', true);

  update sales_invoices
  set
    items = v_items,
    subtotal = v_subtotal,
    iva_amount = v_iva_amount,
    net_amount = case 
      when v_job.tax_treatment = 'tax_included' then v_subtotal / 1.19
      else v_subtotal
    end,
    tax_treatment = v_job.tax_treatment,
    total = v_total,
    discount_amount = v_discount,
    updated_at = now()
  where id = v_invoice_id;
  
  -- Let the payment recalculation function handle balance and status
  perform public.recalculate_sales_invoice_payments(v_invoice_id);

  -- Clear job → invoice flag now that invoice update is done
  perform set_config('app.syncing_job_to_invoice', '', true);
  
  raise notice 'Synced job % to invoice % (% items, subtotal: $%, total: $%)', p_job_id, v_invoice_id, jsonb_array_length(v_items), v_subtotal, v_total;
end;
$$;
