-- =============================================================================
-- FIX: create_invoice_from_mechanic_job — job_bike_id missing from invoice items (Mar 19, 2026)
-- =============================================================================
-- ROOT CAUSE: When creating a new invoice from a mechanic job, the
-- create_invoice_from_mechanic_job function built the items JSON without
-- including job_bike_id or bike_name fields.
--
-- This caused two problems:
--   1. The generated invoice had items with job_bike_id=null
--   2. When sync_invoice_items_to_job ran (on invoice save), it read
--      job_bike_id=null from the invoice JSON and overwrote mechanic_job_items
--      with job_bike_id=null, losing the per-bike assignment.
--
-- FIX: Add job_bike_id and bike_name to the items JSON in create_invoice_from_mechanic_job.
-- Also added: product_sku, description, item_type, is_catalog_product for full parity
-- with sync_job_to_invoice (which already includes all these fields).
-- =============================================================================

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
  v_tenant_id uuid;
begin
  -- Get job details
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;
  
  if not found then
    raise notice 'Job % not found', p_job_id;
    return null;
  end if;
  
  v_tenant_id := v_job.tenant_id;
  
  -- Ensure job totals are current before creating invoice
  perform public.recalculate_mechanic_job_costs(p_job_id);

  -- If invoice already exists, refresh it from the current job items and return it
  if v_job.invoice_id is not null then
    perform public.sync_job_to_invoice(p_job_id);
    raise notice 'Job % already has invoice %, synced existing invoice', p_job_id, v_job.invoice_id;
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
  
  -- Use arrival_date instead of created_at for invoice date
  v_invoice_date := coalesce(v_job.arrival_date, v_job.created_at);
  
  -- Add items (products + services) from mechanic_job_items
  -- ✅ FIX: Include job_bike_id and bike_name in the items JSON
  -- Also include product_sku, description, item_type for full parity with sync_job_to_invoice
  for v_job_item in
    select 
      mji.product_id,
      mji.service_product_id,
      mji.product_name,
      mji.product_sku,
      mji.quantity,
      mji.unit_price,
      mji.total_price,
      mji.item_type,
      mji.notes,
      mji.job_bike_id,
      coalesce(
        nullif(concat_ws(' ', b.brand, b.model), ''),
        'Bicicleta'
      ) as bike_name
    from public.mechanic_job_items mji
    left join public.mechanic_job_bikes mjb on mjb.id = mji.job_bike_id
    left join public.bikes b on b.id = mjb.bike_id
    where mji.job_id = p_job_id
    order by mji.created_at
  loop
    v_item_counter := v_item_counter + 1;

    v_items := v_items || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'product_id', case when coalesce(v_job_item.item_type, 'product') = 'service'
                         then coalesce(v_job_item.service_product_id::text, '')
                         else coalesce(v_job_item.product_id::text, '')
                    end,
      'product_name', v_job_item.product_name,
      'product_sku', coalesce(v_job_item.product_sku, ''),
      'description', coalesce(v_job_item.notes, ''),
      'item_type', coalesce(v_job_item.item_type, 'product'),
      'is_catalog_product', case when v_job_item.item_type = 'adhoc' then false else true end,
      'quantity', v_job_item.quantity,
      'unit_price', v_job_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0),
      'cost', 0,
      'job_bike_id', v_job_item.job_bike_id,
      'bike_name', v_job_item.bike_name
    );

    v_subtotal := v_subtotal + coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0);
  end loop;

  -- Calculate IVA based on job's tax treatment
  if v_job.tax_treatment = 'tax_included' then
    -- Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
    v_iva := round(v_subtotal - (v_subtotal / 1.19), 2);
  else
    -- No tax: iva = 0
    v_iva := 0;
  end if;
  
  v_total := v_subtotal;  -- Total is always the subtotal (what customer pays)
  
  -- Generate invoice number using new sequential system
  v_invoice_number := public.get_next_document_number(v_tenant_id, 'sales_invoice');
  
  -- Create the invoice with status 'draft' for user review
  insert into public.sales_invoices (
    tenant_id,
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
    net_amount,
    tax_treatment,
    total,
    paid_amount,
    balance,
    items,
    created_at,
    updated_at
  ) values (
    v_tenant_id,
    v_invoice_number,
    v_customer.id,
    v_customer.name,
    v_customer.rut,
    v_invoice_date,
    v_invoice_date + interval '30 days',
    'Pega ' || v_job.job_number,
    'draft',
    v_subtotal,
    v_iva,
    case 
      when v_job.tax_treatment = 'tax_included' then v_subtotal / 1.19
      else v_subtotal
    end,
    v_job.tax_treatment,
    v_total,
    0,
    v_total,
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
  
  raise notice 'Created draft invoice % for job % (customer: %, date: %, total: $%, items: %)', 
    v_invoice_id, v_job.job_number, v_customer.name, v_invoice_date, v_total, v_item_counter;
  
  return v_invoice_id;
end;
$$;
