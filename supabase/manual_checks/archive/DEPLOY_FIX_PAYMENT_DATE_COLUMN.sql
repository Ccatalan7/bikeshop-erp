-- FIX: process_online_order and confirm_online_order_payment
-- Problem: Functions use 'payment_date' column but sales_payments table uses 'date'
-- Error: "column payment_date of relation sales_payments does not exist"
-- 
-- Run this in Supabase SQL Editor

-- ============================================================================
-- FIX 1: process_online_order
-- ============================================================================
create or replace function public.process_online_order(p_order_id uuid)
returns uuid -- Returns sales_invoice_id
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
  
  -- CRITICAL: Get tenant_id from the order
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
        -- FIX: Changed 'payment_date' to 'date' (correct column name in sales_payments)
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
            date,  -- FIX: was 'payment_date'
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
  
  -- Determine tax treatment
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;
  
  -- Determine invoice status
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
  
  -- Generate invoice number
  v_year := to_char(now(), 'YY');
  
  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from sales_invoices
  where tenant_id = v_tenant_id
    and invoice_number ~ ('^INV-' || v_year || '-\d+$');
  
  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');
  
  -- Build items JSONB array
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
  
  -- Create sales invoice
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
    reference
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
      else ' (Envío)'
    end
  )
  returning id into v_invoice_id;
  
  raise notice 'Created invoice % (status: %, tax: %) for online order %', 
    v_invoice_number, v_invoice_status, v_tax_treatment, v_order.order_number;
  
  -- Link invoice to order
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
  -- FIX: Changed 'payment_date' to 'date' (correct column name in sales_payments)
  if v_should_create_payment and v_payment_method.id is not null then
    insert into sales_payments (
      tenant_id,
      invoice_id,
      invoice_reference,
      payment_method_id,
      amount,
      date,  -- FIX: was 'payment_date'
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
      'Pago automático - Pedido online #' || v_order.order_number ||
      ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
    );
    
    raise notice 'Created payment record for invoice % (method: %)', 
      v_invoice_number, v_payment_method.name;
  end if;
  
  return v_invoice_id;
end;
$$;

-- ============================================================================
-- FIX 2: confirm_online_order_payment
-- ============================================================================
create or replace function public.confirm_online_order_payment(
  p_order_id uuid,
  p_payment_reference text default null,
  p_payment_date timestamp with time zone default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_invoice record;
  v_payment_method_id uuid;
  v_payment_id uuid;
begin
  -- Get order with tenant context
  select * into v_order
  from online_orders
  where id = p_order_id
    and tenant_id = public.user_tenant_id();
  
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;
  
  if v_order.sales_invoice_id is null then
    raise exception 'Order has no invoice. Call process_online_order first.';
  end if;
  
  select * into v_invoice
  from sales_invoices
  where id = v_order.sales_invoice_id;
  
  if not found then
    raise exception 'Invoice not found: %', v_order.sales_invoice_id;
  end if;
  
  if v_invoice.status = 'paid' then
    raise notice 'Invoice already paid';
    return null;
  end if;
  
  -- Get payment method
  select id into v_payment_method_id
  from payment_methods
  where tenant_id = v_order.tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'transfer'))
    and is_active = true
  limit 1;
  
  if v_payment_method_id is null then
    select id into v_payment_method_id
    from payment_methods
    where tenant_id = v_order.tenant_id
      and lower(code) in ('transfer', 'transferencia', 'bank_transfer')
      and is_active = true
    limit 1;
  end if;
  
  if v_payment_method_id is null then
    raise exception 'No payment method found for tenant %', v_order.tenant_id;
  end if;
  
  -- Update invoice to confirmed
  update sales_invoices
  set 
    status = 'confirmed',
    updated_at = now()
  where id = v_invoice.id
    and status != 'paid';
  
  -- Create payment record
  -- FIX: Changed 'payment_date' to 'date' (correct column name in sales_payments)
  insert into sales_payments (
    tenant_id,
    invoice_id,
    invoice_reference,
    payment_method_id,
    amount,
    date,  -- FIX: was 'payment_date'
    reference,
    notes
  ) values (
    v_order.tenant_id,
    v_invoice.id,
    v_invoice.invoice_number,
    v_payment_method_id,
    v_order.total,
    p_payment_date,
    p_payment_reference,
    'Confirmación manual - Transferencia bancaria - Pedido #' || v_order.order_number
  )
  returning id into v_payment_id;
  
  -- Update order payment status
  update online_orders
  set 
    payment_status = 'paid',
    paid_at = p_payment_date,
    payment_reference = coalesce(p_payment_reference, payment_reference),
    updated_at = now()
  where id = p_order_id;
  
  raise notice 'Payment confirmed for order % (invoice %)', 
    v_order.order_number, v_invoice.invoice_number;
  
  return v_payment_id;
end;
$$;

grant execute on function public.process_online_order(uuid) to authenticated, service_role;
grant execute on function public.confirm_online_order_payment(uuid, text, timestamp with time zone) to authenticated;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
select '✅ Fixed payment_date -> date column reference in online order functions' as status;
