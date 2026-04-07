-- Stamp sales invoice source metadata for website and mechanic-job flows.
-- Source of truth also updated in supabase/sql/core_schema.sql.

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

  -- Draft invoices can be created for future work planning.

  -- Calculate IVA based on job's tax treatment
  if v_job.tax_treatment = 'tax_included' then
    -- Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
    v_iva := round(v_subtotal - (v_subtotal / 1.19), 2);
  else
    -- No tax: iva = 0
    v_iva := 0;
  end if;

  v_total := v_subtotal;

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
    source,
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
    'mechanic_job',
    now(),
    now()
  ) returning id into v_invoice_id;

  -- Link invoice to job
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


create or replace function public.process_online_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_items jsonb;
  v_next_number integer;
  v_year text;
  v_payment_method record;
  v_tenant_id uuid;
  v_net_amount numeric(12,2);
  v_iva_amount numeric(12,2);
  v_tax_treatment text;
  v_invoice_status text;
  v_should_create_payment boolean;
begin
  -- Get order details WITH ROW LOCK to prevent race conditions
  select * into v_order
  from online_orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  -- Get tenant_id from the order
  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception 'Order has no tenant_id: %', p_order_id;
  end if;

  -- Check if invoice already exists
  if v_order.sales_invoice_id is not null then
    -- Invoice exists - check if we need to update it to 'paid' status
    if v_order.payment_status = 'paid' then
      -- Get payment method for creating payment record
      select * into v_payment_method
      from payment_methods
      where tenant_id = v_tenant_id
        and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
        and is_active = true
      limit 1;

      -- If payment method not found, try fallback
      if v_payment_method is null then
        select * into v_payment_method
        from payment_methods
        where tenant_id = v_tenant_id
          and is_active = true
        order by sort_order
        limit 1;
      end if;

      -- Check if invoice is not already paid
      perform 1 from sales_invoices
      where id = v_order.sales_invoice_id
        and status != 'paid';

      if found then
        -- Update invoice to paid status
        update sales_invoices
        set status = 'paid',
            paid_amount = total,
            balance = 0,
            updated_at = now()
        where id = v_order.sales_invoice_id;

        -- Create payment record if not exists
        if not exists (
          select 1 from sales_payments
          where invoice_id = v_order.sales_invoice_id
        ) and v_payment_method.id is not null then
          insert into sales_payments (
            tenant_id,
            invoice_id,
            invoice_reference,
            payment_method_id,
            amount,
            date,
            reference,
            notes
          ) values (
            v_tenant_id,
            v_order.sales_invoice_id,
            (select invoice_number from sales_invoices where id = v_order.sales_invoice_id),
            v_payment_method.id,
            v_order.total,
            coalesce(v_order.paid_at, now()),
            v_order.payment_reference,
            'Pago automatico - Pedido online #' || v_order.order_number ||
            ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
          );

          raise notice 'Created payment record for existing invoice (order: %)', v_order.order_number;
        end if;

        raise notice 'Updated existing invoice to paid status (order: %)', v_order.order_number;
      end if;
    end if;

    return v_order.sales_invoice_id;
  end if;

  -- Get payment method configuration
  select * into v_payment_method
  from payment_methods
  where tenant_id = v_tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
    and is_active = true
  limit 1;

  -- If payment method not found, try fallback
  if v_payment_method is null then
    select * into v_payment_method
    from payment_methods
    where tenant_id = v_tenant_id
      and is_active = true
    order by sort_order
    limit 1;
  end if;

  -- Determine tax treatment based on payment method
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;

  -- Determine invoice status based on payment method + status
  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
  elsif lower(v_order.payment_method) = 'mercadopago' and v_order.payment_status = 'pending' then
    v_invoice_status := 'confirmed';
    v_should_create_payment := false;
  else
    v_invoice_status := 'sent';
    v_should_create_payment := false;
  end if;

  -- Generate invoice number PER TENANT in format: INV-25-00001
  v_year := to_char(now(), 'YY');

  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from sales_invoices
  where tenant_id = v_tenant_id
    and invoice_number ~ ('^INV-' || v_year || '-\d+$');

  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');

  -- Build items JSONB array from order items
  select jsonb_agg(
    jsonb_build_object(
      'product_id', oi.product_id,
      'product_name', oi.product_name,
      'product_sku', oi.product_sku,
      'quantity', oi.quantity,
      'price', oi.unit_price,
      'subtotal', oi.subtotal
    )
  ) into v_items
  from online_order_items oi
  where oi.order_id = p_order_id;

  if v_items is null then
    v_items := '[]'::jsonb;
  end if;

  -- Create sales invoice. Only 'paid' status triggers inventory deduction + journal entry.
  insert into sales_invoices (
    tenant_id,
    invoice_number,
    customer_id,
    customer_name,
    date,
    due_date,
    status,
    tax_treatment,
    net_amount,
    subtotal,
    iva_amount,
    total,
    paid_amount,
    balance,
    items,
    reference,
    source
  ) values (
    v_tenant_id,
    v_invoice_number,
    v_order.customer_id,
    v_order.customer_name,
    now(),
    now() + interval '30 days',
    v_invoice_status,
    v_tax_treatment,
    v_net_amount,
    v_order.subtotal,
    v_iva_amount,
    v_order.total,
    case when v_should_create_payment then v_order.total else 0 end,
    case when v_should_create_payment then 0 else v_order.total end,
    v_items,
    'Pedido online #' || v_order.order_number ||
    case
      when v_order.delivery_type = 'pickup' then ' (Retiro en tienda)'
      else ' (Envio)'
    end,
    'ecommerce'
  )
  returning id into v_invoice_id;

  raise notice 'Created invoice % (status: %, tax: %) for online order %',
    v_invoice_number, v_invoice_status, v_tax_treatment, v_order.order_number;

  -- Directly call inventory and journal functions here because nested triggers block the usual path.
  if v_invoice_status in ('paid', 'confirmed') then
    declare
      v_invoice_record sales_invoices%rowtype;
    begin
      select * into v_invoice_record from sales_invoices where id = v_invoice_id;

      raise notice 'Calling consume_sales_invoice_inventory for invoice %', v_invoice_number;
      perform public.consume_sales_invoice_inventory(v_invoice_record);

      raise notice 'Calling create_sales_invoice_journal_entry for invoice %', v_invoice_number;
      perform public.create_sales_invoice_journal_entry(v_invoice_record);
    end;
  end if;

  -- Link invoice to order + update order status
  update online_orders
  set
    sales_invoice_id = v_invoice_id,
    status = case
      when status = 'pending' then 'confirmed'
      else status
    end,
    updated_at = now()
  where id = p_order_id;

  -- Create payment record ONLY if payment is confirmed
  if v_should_create_payment and v_payment_method.id is not null then
    insert into sales_payments (
      tenant_id,
      invoice_id,
      invoice_reference,
      payment_method_id,
      amount,
      date,
      reference,
      notes
    ) values (
      v_tenant_id,
      v_invoice_id,
      v_invoice_number,
      v_payment_method.id,
      v_order.total,
      coalesce(v_order.paid_at, now()),
      v_order.payment_reference,
      'Pago automatico - Pedido online #' || v_order.order_number ||
      ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
    );

    raise notice 'Created payment record for invoice % (method: %)',
      v_invoice_number, v_payment_method.name;
  elsif not v_should_create_payment then
    raise notice 'Invoice % pending manual payment confirmation (method: %)',
      v_invoice_number, v_order.payment_method;
  end if;

  return v_invoice_id;
end;
$$;