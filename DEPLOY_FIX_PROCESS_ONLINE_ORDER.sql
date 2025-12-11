-- ============================================================================
-- FIX: process_online_order - Handle webhook arriving after invoice creation
-- ============================================================================
-- This fixes the case where:
-- 1. User pays with MercadoPago
-- 2. Frontend callback creates invoice with status 'confirmed' (pending webhook)
-- 3. Webhook arrives and calls process_online_order
-- 4. Previously: Function returned early, invoice stayed 'confirmed'
-- 5. NOW: Function updates invoice to 'paid' and creates payment record
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
  raise notice '🛒 [PROCESS_ORDER] ========== START ==========';
  raise notice '🛒 [PROCESS_ORDER] Order ID: %', p_order_id;
  
  -- Get order details
  raise notice '🛒 [PROCESS_ORDER] Step 1: Fetching order...';
  select * into v_order
  from online_orders
  where id = p_order_id;
  
  if not found then
    raise exception '🛒 [PROCESS_ORDER] ❌ Order not found: %', p_order_id;
  end if;
  raise notice '🛒 [PROCESS_ORDER] Step 1: ✅ Order found: % | Status: % | Payment: %', 
    v_order.order_number, v_order.status, v_order.payment_status;
  
  -- CRITICAL: Get tenant_id from the order
  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception '🛒 [PROCESS_ORDER] ❌ Order has no tenant_id: %', p_order_id;
  end if;
  raise notice '🛒 [PROCESS_ORDER] Step 2: ✅ Tenant ID: %', v_tenant_id;
  
  -- Check if invoice already exists
  raise notice '🛒 [PROCESS_ORDER] Step 3: Checking if invoice exists...';
  raise notice '🛒 [PROCESS_ORDER] - sales_invoice_id: %', v_order.sales_invoice_id;
  
  if v_order.sales_invoice_id is not null then
    raise notice '🛒 [PROCESS_ORDER] Step 3: ⚠️ Invoice already exists! ID: %', v_order.sales_invoice_id;
    
    -- Invoice exists - check if we need to update it to 'paid' status
    -- This handles the case where webhook arrives after invoice was created
    if v_order.payment_status = 'paid' then
      raise notice '🛒 [PROCESS_ORDER] Step 3a: Order payment_status is PAID - checking if invoice needs update...';
      
      -- Get payment method for creating payment record
      select * into v_payment_method
      from payment_methods
      where tenant_id = v_tenant_id
        and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
        and is_active = true
      limit 1;
      
      -- If payment method not found, try fallback
      if v_payment_method is null then
        raise notice '🛒 [PROCESS_ORDER] Step 3b: Payment method % not found, using fallback...', v_order.payment_method;
        select * into v_payment_method
        from payment_methods
        where tenant_id = v_tenant_id
          and is_active = true
        order by sort_order
        limit 1;
      end if;
      raise notice '🛒 [PROCESS_ORDER] Step 3b: ✅ Payment method: % (ID: %)', 
        v_payment_method.name, v_payment_method.id;
      
      -- Check if invoice is not already paid
      perform 1 from sales_invoices 
      where id = v_order.sales_invoice_id 
        and status != 'paid';
        
      if found then
        raise notice '🛒 [PROCESS_ORDER] Step 3c: Invoice not paid yet - UPDATING TO PAID...';
        
        -- Update invoice to paid status
        update sales_invoices
        set status = 'paid',
            paid_amount = total,
            balance = 0,
            updated_at = now()
        where id = v_order.sales_invoice_id;
        raise notice '🛒 [PROCESS_ORDER] Step 3c: ✅ Invoice updated to PAID status';
        
        -- Create payment record if not exists
        if not exists (
          select 1 from sales_payments 
          where invoice_id = v_order.sales_invoice_id
        ) and v_payment_method.id is not null then
          raise notice '🛒 [PROCESS_ORDER] Step 3d: Creating payment record...';
          
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
          
          raise notice '🛒 [PROCESS_ORDER] Step 3d: ✅ Payment record created for existing invoice';
        else
          raise notice '🛒 [PROCESS_ORDER] Step 3d: ⚠️ Payment record already exists or no payment method';
        end if;
      else
        raise notice '🛒 [PROCESS_ORDER] Step 3c: ⚠️ Invoice already paid - no update needed';
      end if;
    else
      raise notice '🛒 [PROCESS_ORDER] Step 3a: Order payment_status is % (not paid) - no update needed', v_order.payment_status;
    end if;
    
    raise notice '🛒 [PROCESS_ORDER] ========== RETURNING EXISTING INVOICE ==========';
    return v_order.sales_invoice_id;
  end if;
  
  raise notice '🛒 [PROCESS_ORDER] Step 3: ✅ No existing invoice - creating new one...';
  
  -- Get payment method configuration
  raise notice '🛒 [PROCESS_ORDER] Step 4: Getting payment method...';
  select * into v_payment_method
  from payment_methods
  where tenant_id = v_tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
    and is_active = true
  limit 1;
  
  -- If payment method not found, try fallback
  if v_payment_method is null then
    raise notice '🛒 [PROCESS_ORDER] Step 4: Payment method % not found, using fallback...', v_order.payment_method;
    select * into v_payment_method
    from payment_methods
    where tenant_id = v_tenant_id
      and is_active = true
    order by sort_order
    limit 1;
  end if;
  raise notice '🛒 [PROCESS_ORDER] Step 4: ✅ Payment method: % (ID: %)', 
    v_payment_method.name, v_payment_method.id;
  
  -- ============================================================================
  -- DETERMINE TAX TREATMENT BASED ON PAYMENT METHOD
  -- ============================================================================
  raise notice '🛒 [PROCESS_ORDER] Step 5: Determining tax treatment...';
  raise notice '🛒 [PROCESS_ORDER] - Order tax_amount: %', v_order.tax_amount;
  
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
    raise notice '🛒 [PROCESS_ORDER] Step 5: ✅ TAX_INCLUDED - Net: %, IVA: %', v_net_amount, v_iva_amount;
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
    raise notice '🛒 [PROCESS_ORDER] Step 5: ✅ NO_TAX - Net: %, IVA: 0', v_net_amount;
  end if;
  
  -- ============================================================================
  -- DETERMINE INVOICE STATUS BASED ON PAYMENT METHOD + STATUS
  -- ============================================================================
  raise notice '🛒 [PROCESS_ORDER] Step 6: Determining invoice status...';
  raise notice '🛒 [PROCESS_ORDER] - Payment method: %', v_order.payment_method;
  raise notice '🛒 [PROCESS_ORDER] - Payment status: %', v_order.payment_status;
  
  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
    raise notice '🛒 [PROCESS_ORDER] Step 6: ✅ Status=PAID, will create payment record';
  elsif lower(v_order.payment_method) = 'mercadopago' and v_order.payment_status = 'pending' then
    v_invoice_status := 'confirmed';
    v_should_create_payment := false;
    raise notice '🛒 [PROCESS_ORDER] Step 6: ⚠️ Status=CONFIRMED (waiting for webhook)';
  else
    v_invoice_status := 'sent';
    v_should_create_payment := false;
    raise notice '🛒 [PROCESS_ORDER] Step 6: ⚠️ Status=SENT (manual confirmation needed)';
  end if;
  
  -- Generate invoice number PER TENANT in format: INV-25-00001
  raise notice '🛒 [PROCESS_ORDER] Step 7: Generating invoice number...';
  v_year := to_char(now(), 'YY');
  
  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from sales_invoices
  where tenant_id = v_tenant_id
    and invoice_number ~ ('^INV-' || v_year || '-\d+$');
  
  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');
  raise notice '🛒 [PROCESS_ORDER] Step 7: ✅ Invoice number: %', v_invoice_number;
  
  -- Build items JSONB array from order items
  raise notice '🛒 [PROCESS_ORDER] Step 8: Building items array...';
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
  
  -- Default to empty array if no items
  if v_items is null then
    v_items := '[]'::jsonb;
  end if;
  raise notice '🛒 [PROCESS_ORDER] Step 8: ✅ Items: % item(s)', jsonb_array_length(v_items);
  
  -- Create sales invoice WITH tenant_id
  raise notice '🛒 [PROCESS_ORDER] Step 9: Creating sales invoice...';
  raise notice '🛒 [PROCESS_ORDER] - Invoice: % | Status: % | Total: %', v_invoice_number, v_invoice_status, v_order.total;
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
  
  raise notice '🛒 [PROCESS_ORDER] Step 9: ✅ Invoice created! ID: %', v_invoice_id;
  
  -- Link invoice to order + update order status
  raise notice '🛒 [PROCESS_ORDER] Step 10: Linking invoice to order...';
  update online_orders
  set 
    sales_invoice_id = v_invoice_id,
    invoice_id = v_invoice_id,  -- Alias
    status = case 
      when status = 'pending' then 'confirmed' 
      else status 
    end,
    updated_at = now()
  where id = p_order_id;
  raise notice '🛒 [PROCESS_ORDER] Step 10: ✅ Order updated with invoice_id';
  
  -- Create payment record ONLY if payment is confirmed
  if v_should_create_payment and v_payment_method.id is not null then
    raise notice '🛒 [PROCESS_ORDER] Step 11: Creating payment record...';
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
    
    raise notice '🛒 [PROCESS_ORDER] Step 11: ✅ Payment record created!';
    raise notice '🛒 [PROCESS_ORDER] - Amount: % | Method: %', v_order.total, v_payment_method.name;
  elsif not v_should_create_payment then
    raise notice '🛒 [PROCESS_ORDER] Step 11: ⚠️ Skipping payment record (invoice status: %)', v_invoice_status;
  else
    raise notice '🛒 [PROCESS_ORDER] Step 11: ⚠️ No payment method available!';
  end if;
  
  raise notice '🛒 [PROCESS_ORDER] ========== COMPLETE ==========';
  raise notice '🛒 [PROCESS_ORDER] Invoice: % | Status: % | Total: %', v_invoice_number, v_invoice_status, v_order.total;
  
  return v_invoice_id;
end;
$$;

-- Grant permissions
grant execute on function public.process_online_order(uuid) to authenticated, service_role;

-- Done!
select '✅ process_online_order updated - now handles webhook arriving after invoice creation' as status;
