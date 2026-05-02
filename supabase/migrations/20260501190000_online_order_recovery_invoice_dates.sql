-- Preserve original online-order timing when a paid order is recovered later.
-- This keeps invoice, journal, payment, and stock movement dates aligned to the
-- payment/order date instead of the day staff clicks "Crear factura".

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
  v_invoice_date timestamp with time zone;
begin
  select * into v_order
  from public.online_orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception 'Order has no tenant_id: %', p_order_id;
  end if;

  if v_order.sales_invoice_id is not null then
    if v_order.payment_status = 'paid' then
      select * into v_payment_method
      from public.payment_methods
      where tenant_id = v_tenant_id
        and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
        and is_active = true
      limit 1;

      if v_payment_method is null then
        select * into v_payment_method
        from public.payment_methods
        where tenant_id = v_tenant_id
          and is_active = true
        order by sort_order
        limit 1;
      end if;

      perform 1 from public.sales_invoices
      where id = v_order.sales_invoice_id
        and status != 'paid';

      if found then
        update public.sales_invoices
        set status = 'paid',
            paid_amount = total,
            balance = 0,
            updated_at = now()
        where id = v_order.sales_invoice_id;

        if not exists (
          select 1 from public.sales_payments
          where invoice_id = v_order.sales_invoice_id
        ) and v_payment_method.id is not null then
          insert into public.sales_payments (
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
            (select invoice_number from public.sales_invoices where id = v_order.sales_invoice_id),
            v_payment_method.id,
            v_order.total,
            coalesce(v_order.paid_at, now()),
            v_order.payment_reference,
            'Pago automático - Pedido online #' || v_order.order_number ||
            ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
          );

          raise notice 'Created payment record for existing invoice (order: %)', v_order.order_number;
        end if;

        raise notice 'Updated existing invoice to paid status (order: %)', v_order.order_number;
      end if;
    end if;

    return v_order.sales_invoice_id;
  end if;

  select * into v_payment_method
  from public.payment_methods
  where tenant_id = v_tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
    and is_active = true
  limit 1;

  if v_payment_method is null then
    select * into v_payment_method
    from public.payment_methods
    where tenant_id = v_tenant_id
      and is_active = true
    order by sort_order
    limit 1;
  end if;

  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;

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

  v_invoice_date := case
    when v_order.payment_status = 'paid' then
      coalesce(v_order.paid_at, v_order.created_at, now())
    else
      coalesce(v_order.created_at, now())
  end;

  v_year := to_char(v_invoice_date, 'YY');

  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from public.sales_invoices
  where tenant_id = v_tenant_id
    and invoice_number ~ ('^INV-' || v_year || '-\d+$');

  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');

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
  from public.online_order_items oi
  where oi.order_id = p_order_id;

  if v_items is null then
    v_items := '[]'::jsonb;
  end if;

  insert into public.sales_invoices (
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
    v_invoice_date,
    v_invoice_date + interval '30 days',
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
      else ' (Envío)'
    end,
    'ecommerce'
  )
  returning id into v_invoice_id;

  raise notice 'Created invoice % (status: %, tax: %) for online order %',
    v_invoice_number, v_invoice_status, v_tax_treatment, v_order.order_number;

  if v_invoice_status in ('paid', 'confirmed') then
    declare
      v_invoice_record public.sales_invoices%rowtype;
    begin
      select * into v_invoice_record from public.sales_invoices where id = v_invoice_id;

      raise notice 'Calling consume_sales_invoice_inventory for invoice %', v_invoice_number;
      perform public.consume_sales_invoice_inventory(v_invoice_record);

      raise notice 'Calling create_sales_invoice_journal_entry for invoice %', v_invoice_number;
      perform public.create_sales_invoice_journal_entry(v_invoice_record);
    end;
  end if;

  update public.online_orders
  set sales_invoice_id = v_invoice_id,
      status = case
        when status = 'pending' then 'confirmed'
        else status
      end,
      updated_at = now()
  where id = p_order_id;

  if v_should_create_payment and v_payment_method.id is not null then
    insert into public.sales_payments (
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
      coalesce(v_order.paid_at, v_invoice_date),
      v_order.payment_reference,
      'Pago automático - Pedido online #' || v_order.order_number ||
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
