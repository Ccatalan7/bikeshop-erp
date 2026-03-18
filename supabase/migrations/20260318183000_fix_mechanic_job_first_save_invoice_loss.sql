-- Fix first-save pega invoice data loss
-- Root cause:
-- 1. A trigger auto-created a draft invoice immediately on mechanic_jobs INSERT.
-- 2. That happened before mechanic_job_items existed, so the invoice started empty.
-- 3. Later saves could sync that empty invoice back into the pega workflow.
--
-- Fix:
-- - If an invoice already exists for a job, refresh it from current job items.
-- - Stop auto-creating invoices on mechanic_jobs insert.
-- - Let the Flutter save flow create/sync the invoice only after all items are written.

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
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;

  if not found then
    raise notice 'Job % not found', p_job_id;
    return null;
  end if;

  v_tenant_id := v_job.tenant_id;

  perform public.recalculate_mechanic_job_costs(p_job_id);

  if v_job.invoice_id is not null then
    perform public.sync_job_to_invoice(p_job_id);
    raise notice 'Job % already has invoice %, synced existing invoice', p_job_id, v_job.invoice_id;
    return v_job.invoice_id;
  end if;

  select * into v_customer
  from public.customers
  where id = v_job.customer_id;

  if not found then
    raise notice 'Customer % not found for job %', v_job.customer_id, p_job_id;
    return null;
  end if;

  v_invoice_date := coalesce(v_job.arrival_date, v_job.created_at);

  for v_job_item in
    select
      product_id,
      service_product_id,
      product_name,
      quantity,
      unit_price,
      total_price,
      item_type
    from public.mechanic_job_items
    where job_id = p_job_id
    order by created_at
  loop
    v_item_counter := v_item_counter + 1;

    v_items := v_items || jsonb_build_object(
      'id', gen_random_uuid()::text,
      'product_id', case when coalesce(v_job_item.item_type, 'product') = 'service'
                         then coalesce(v_job_item.service_product_id::text, '')
                         else coalesce(v_job_item.product_id::text, '')
                    end,
      'product_name', v_job_item.product_name,
      'quantity', v_job_item.quantity,
      'unit_price', v_job_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0),
      'cost', 0
    );

    v_subtotal := v_subtotal + coalesce(v_job_item.total_price, v_job_item.quantity * v_job_item.unit_price, 0);
  end loop;

  if v_job.tax_treatment = 'tax_included' then
    v_iva := round(v_subtotal - (v_subtotal / 1.19), 2);
  else
    v_iva := 0;
  end if;

  v_total := v_subtotal;
  v_invoice_number := public.get_next_document_number(v_tenant_id, 'sales_invoice');

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

  update public.mechanic_jobs
  set invoice_id = v_invoice_id,
      is_invoiced = true,
      updated_at = now()
  where id = p_job_id;

  raise notice 'Created draft invoice % for job % (customer: %, date: %, total: $%)',
    v_invoice_id, v_job.job_number, v_customer.name, v_invoice_date, v_total;

  return v_invoice_id;
end;
$$;

drop trigger if exists trg_auto_create_invoice_for_job on public.mechanic_jobs;
drop function if exists public.auto_create_invoice_for_new_job() cascade;
