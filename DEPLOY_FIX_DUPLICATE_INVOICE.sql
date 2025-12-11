-- ============================================================================
-- FIX: Prevent duplicate invoice creation from race conditions
-- ============================================================================
-- Problem: Both webhook and page callback can race to create invoice
-- Solution: Add FOR UPDATE lock on order row to serialize access
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
  -- This ensures only one process can create an invoice for this order
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
    raise notice '🛒 [PROCESS_ORDER] Invoice already exists for order %, returning existing invoice', v_order.order_number;
    
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
            payment_date,
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
          
          raise notice '🛒 [PROCESS_ORDER] Created payment record for existing invoice (order: %)', v_order.order_number;
        end if;
        
        raise notice '🛒 [PROCESS_ORDER] Updated existing invoice to paid status (order: %)', v_order.order_number;
      end if;
    end if;
    
    return v_order.sales_invoice_id;
  end if;
  
  raise notice '🛒 [PROCESS_ORDER] Creating NEW invoice for order %', v_order.order_number;
  
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
  
  -- ============================================================================
  -- DETERMINE TAX TREATMENT BASED ON PAYMENT METHOD
  -- ============================================================================
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;
  
  -- ============================================================================
  -- DETERMINE INVOICE STATUS BASED ON PAYMENT METHOD + STATUS
  -- ============================================================================
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
  
  -- Generate invoice number PER TENANT
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
  
  raise notice '🛒 [PROCESS_ORDER] Created invoice % for order %', v_invoice_number, v_order.order_number;
  
  -- Link invoice to order
  update online_orders
  set sales_invoice_id = v_invoice_id,
      order_status = case 
        when v_invoice_status = 'paid' then 'processing'
        else 'pending'
      end,
      updated_at = now()
  where id = p_order_id;
  
  -- Create payment record if paid
  if v_should_create_payment and v_payment_method.id is not null then
    insert into sales_payments (
      tenant_id,
      invoice_id,
      invoice_reference,
      payment_method_id,
      amount,
      payment_date,
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
    
    raise notice '🛒 [PROCESS_ORDER] Created payment record for new invoice (order: %)', v_order.order_number;
  end if;
  
  return v_invoice_id;
end;
$$;

-- Verify function was updated
select '✅ process_online_order updated with FOR UPDATE lock!' as status;
