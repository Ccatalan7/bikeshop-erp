-- FIX: Calendar View Description Display & Sync
-- 1. Updates sync_job_to_invoice to map item notes -> invoice item description
-- 2. Updates sync_job_to_invoice to map job notes -> invoice notes
-- 3. Adds trigger to sync mechanic_jobs updates (notes, status) to invoices

-- Function: Sync Job to Invoice (Updated)
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
  
  -- Get discount
  v_discount := coalesce(v_job.discount_amount, 0);
  
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
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'description', coalesce(v_item.notes, '') -- ✅ Fix: Map item notes to invoice item description
    );

    if coalesce(v_item.item_type, 'product') in ('service', 'adhoc') then
      v_labor_cost := v_labor_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    else
      v_parts_cost := v_parts_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    end if;
  end loop;
  
  -- Calculate totals with FRESH data
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
    total = v_total,
    balance = v_total - paid_amount,
    -- ✅ Fix: Map job fields to invoice fields
    notes = v_job.notes,
    work_description = coalesce(v_job.client_request, v_job.work_performed, v_job.diagnosis),
    updated_at = now()
  where id = v_invoice_id;
end;
$$;

-- Function: Trigger to sync mechanic_jobs changes (notes, etc) to invoice
create or replace function public.sync_job_changes_to_invoice_statement()
returns trigger
language plpgsql
as $$
declare
  v_job_record record; -- Use record instead of uuid loop for new table
  v_job_id uuid;
  v_invoice_id uuid;
  v_syncing_flag text;
begin
  -- Check prevention flag
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  if v_syncing_flag = 'true' then
    return null;
  end if;

  -- Handle UPDATE - sync if invoice exists
  for v_job_record in select distinct id from new_table
  loop
    v_job_id := v_job_record.id;
    
    select invoice_id into v_invoice_id from mechanic_jobs where id = v_job_id;
    
    if v_invoice_id is not null then
      perform public.sync_job_to_invoice(v_job_id);
    end if;
  end loop;
  
  return null;
end;
$$;

-- Trigger: On Mechanic Job Update
drop trigger if exists trg_mechanic_jobs_sync_invoice_update on mechanic_jobs;
create trigger trg_mechanic_jobs_sync_invoice_update
  after update on mechanic_jobs
  referencing new table as new_table
  for each statement
  execute procedure public.sync_job_changes_to_invoice_statement();
