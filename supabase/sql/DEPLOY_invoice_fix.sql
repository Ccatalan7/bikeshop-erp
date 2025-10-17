-- ============================================================================
-- DEPLOYMENT: Fix invoice items from pega integration
-- Date: 2025-10-16
-- Description: Updates create_invoice_from_mechanic_job() to create proper
--              invoice items with correct field names matching InvoiceItem model
-- ============================================================================

create or replace function public.create_invoice_from_mechanic_job(p_job_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_customer record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_invoice_date timestamp with time zone;
  v_subtotal numeric(12,2) := 0;
  v_iva numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_items jsonb := '[]'::jsonb;
  v_item_counter integer := 0;
  v_job_item record;
  v_labor_record record;
begin
  -- Get job details
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;
  
  if not found then
    raise notice 'Job % not found', p_job_id;
    return null;
  end if;
  
  -- If invoice already exists, don't create another
  if v_job.invoice_id is not null then
    raise notice 'Job % already has invoice %', p_job_id, v_job.invoice_id;
    return v_job.invoice_id;
  end if;
  
  -- Get customer details
  select * into v_customer
  from public.customers
  where id = v_job.customer_id;
  
  if not found then
    raise notice 'Customer % not found for job %', v_job.customer_id, p_job_id;
    return null;
  end if;
  
  -- Set invoice date to job creation date
  v_invoice_date := v_job.created_at;
  
  -- Add parts/items from mechanic_job_items
  for v_job_item in
    select 
      product_id,
      product_name,
      quantity,
      unit_price,
      (quantity * unit_price) as line_total,
      notes
    from public.mechanic_job_items
    where job_id = p_job_id
    order by created_at
  loop
    v_item_counter := v_item_counter + 1;
    v_subtotal := v_subtotal + v_job_item.line_total;
    
    v_items := v_items || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'product_id', COALESCE(v_job_item.product_id::text, ''),
      'product_name', v_job_item.product_name,
      'quantity', v_job_item.quantity,
      'unit_price', v_job_item.unit_price,
      'discount', 0,
      'line_total', v_job_item.line_total,
      'cost', 0
    );
  end loop;
  
  -- Add labor costs as a service line item (if labor_cost > 0)
  if v_job.labor_cost > 0 then
    v_item_counter := v_item_counter + 1;
    v_subtotal := v_subtotal + v_job.labor_cost;
    
    v_items := v_items || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'product_id', '',
      'product_name', 'Mano de obra / Labor',
      'quantity', 1,
      'unit_price', v_job.labor_cost,
      'discount', 0,
      'line_total', v_job.labor_cost,
      'cost', 0
    );
  end if;
  
  -- Calculate IVA (19% for Chile)
  v_iva := round(v_subtotal * 0.19, 2);
  v_total := v_subtotal + v_iva;
  
  -- Generate invoice number (will be updated if needed)
  v_invoice_number := 'INV-' || to_char(v_invoice_date, 'YYYYMMDD') || '-' || gen_random_uuid()::text;
  
  -- Create the invoice
  insert into public.sales_invoices (
    invoice_number,
    customer_id,
    customer_name,
    customer_rut,
    date,
    due_date,
    reference,
    status,
    subtotal,
    iva_amount,
    total,
    paid_amount,
    balance,
    items,
    created_at,
    updated_at
  ) values (
    v_invoice_number,
    v_customer.id,
    v_customer.name,
    v_customer.rut,
    v_invoice_date,
    v_invoice_date + interval '30 days',  -- 30-day payment terms
    'Pega ' || v_job.job_number,
    'draft',
    v_subtotal,
    v_iva,
    v_total,
    0,  -- Not paid yet
    v_total,  -- Full balance pending
    v_items,
    now(),
    now()
  ) returning id into v_invoice_id;
  
  -- Link invoice to job
  update public.mechanic_jobs
  set invoice_id = v_invoice_id,
      is_invoiced = true,
      updated_at = now()
  where id = p_job_id;
  
  raise notice 'Created invoice % for job % (customer: %, total: $%)', 
    v_invoice_id, v_job.job_number, v_customer.name, v_total;
  
  return v_invoice_id;
end;
$$;

-- ============================================================================
-- Verification query (optional - run after deployment to test)
-- ============================================================================
-- SELECT create_invoice_from_mechanic_job('<your_test_job_id_here>');
