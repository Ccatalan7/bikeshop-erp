-- Fix 1: Sales invoice journal entry not being created for online orders
-- Fix 2: process_online_order must directly call inventory/journal functions
--        because handle_sales_invoice_change has pg_trigger_depth() > 1 check
--        that blocks processing when called from within another trigger

-- Deploy to Supabase SQL Editor

-- ============================================================================
-- FIX 1: SALES INVOICE JOURNAL ENTRY FUNCTION
-- ============================================================================
create or replace function public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos Operacionales';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1105';
  v_inventory_account_name text := 'Inventarios';
  v_inventory_account_id uuid;
  v_cogs_account_code text := '5100';
  v_cogs_account_name text := 'Costo de Ventas';
  v_cogs_account_id uuid;
  v_invoice_number text;
  v_customer_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
  v_total_cost numeric(12,2);
  v_tenant_id uuid;
begin
  if p_invoice.id is null then
    raise notice 'create_sales_invoice_journal_entry: invoice.id is null, skipping';
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    raise notice 'create_sales_invoice_journal_entry: invoice % status is %, skipping', p_invoice.id, p_invoice.status;
    return;
  end if;

  v_tenant_id := p_invoice.tenant_id;

  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_invoice_journal_entry: No tenant_id on invoice %, skipping', p_invoice.id;
    return;
  end if;

  -- Check for existing journal entry using invoice_number (consistent with INSERT)
  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.invoice_number
              and tenant_id = v_tenant_id
       )
    into v_exists;

  if v_exists then
    raise notice 'create_sales_invoice_journal_entry: Entry already exists for invoice %, skipping', p_invoice.invoice_number;
    return;
  end if;
  
  raise notice 'create_sales_invoice_journal_entry: Creating entry for invoice % (status: %)', p_invoice.invoice_number, p_invoice.status;

  -- ✅ CRITICAL: Use net_amount (tax-adjusted) if available, fallback to subtotal
  v_subtotal := coalesce(p_invoice.net_amount, p_invoice.subtotal, 0);
  v_iva := coalesce(p_invoice.iva_amount, 0);
  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    raise notice 'create_sales_invoice_journal_entry: invoice % has total = 0, skipping', p_invoice.invoice_number;
    return;
  end if;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_tenant_id,
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_tenant_id,
    v_iva_account_code,
    v_iva_account_name,
    'liability',
    'currentLiability',
    'IVA generado en ventas',
    null
  );

  select coalesce(sum((item->>'cost')::numeric), 0)
    into v_total_cost
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
   where (item->>'cost') is not null
     and (item->>'cost') <> '';

  if v_total_cost > 0 then
    v_inventory_account_id := public.ensure_account(
      v_tenant_id,
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_tenant_id,
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  end if;

  v_invoice_number := coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := coalesce(nullif(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.invoice_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    v_description,
    v_total,
    0,
    now(),
    now()
  );

  if v_subtotal <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_revenue_account_id,
      v_revenue_account_code,
      v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0,
      v_subtotal,
      now(),
      now()
    );
  end if;

  if v_iva <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_cogs_account_id,
      v_cogs_account_code,
      v_cogs_account_name,
      format('Costo de ventas %s', v_invoice_number),
      v_total_cost,
      0,
      now(),
      now()
    ), (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Salida inventario factura %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;
  
  raise notice 'create_sales_invoice_journal_entry: Successfully created entry % for invoice %', v_entry_id, p_invoice.invoice_number;
end;
$$;

-- Now manually create journal entries for the existing INV-25- invoices that are missing them
DO $$
DECLARE
  v_invoice sales_invoices%rowtype;
BEGIN
  FOR v_invoice IN 
    SELECT si.* 
    FROM sales_invoices si
    WHERE si.invoice_number LIKE 'INV-25-%'
      AND si.status IN ('paid', 'confirmed')
      AND NOT EXISTS (
        SELECT 1 FROM journal_entries je 
        WHERE je.source_module = 'sales_invoices' 
          AND je.source_reference = si.invoice_number
      )
  LOOP
    RAISE NOTICE 'Creating missing journal entry for invoice %', v_invoice.invoice_number;
    PERFORM public.create_sales_invoice_journal_entry(v_invoice);
  END LOOP;
END $$;

-- Verify
SELECT 
  si.invoice_number,
  si.status,
  si.total,
  je.entry_number as sale_journal,
  pje.entry_number as payment_journal
FROM sales_invoices si
LEFT JOIN journal_entries je ON je.source_module = 'sales_invoices' AND je.source_reference = si.invoice_number
LEFT JOIN journal_entries pje ON pje.source_module = 'sales_payments' AND pje.source_reference = si.invoice_number
WHERE si.invoice_number LIKE 'INV-25-%'
ORDER BY si.created_at DESC;

-- ============================================================================
-- FIX 2: PROCESS_ONLINE_ORDER - Directly call inventory/journal functions
-- The handle_sales_invoice_change trigger has pg_trigger_depth() > 1 check
-- which blocks processing when called from within another trigger chain
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
    -- Invoice exists - check if we need to update it to 'paid' status
    -- This handles the case where webhook arrives after invoice was created
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
  
  -- Create sales invoice WITH tenant_id
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
  
  -- ============================================================================
  -- CRITICAL: Directly call inventory and journal functions here
  -- The trigger handle_sales_invoice_change has pg_trigger_depth() > 1 check
  -- which blocks processing when called from within another trigger
  -- So we call these functions directly to ensure they run
  -- ============================================================================
  if v_invoice_status in ('paid', 'confirmed') then
    declare
      v_invoice_record sales_invoices%rowtype;
    begin
      select * into v_invoice_record from sales_invoices where id = v_invoice_id;
      
      -- Consume inventory (deduct stock)
      raise notice 'Calling consume_sales_invoice_inventory for invoice %', v_invoice_number;
      perform public.consume_sales_invoice_inventory(v_invoice_record);
      
      -- Create sale journal entry
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

-- Grant execute permission
grant execute on function public.process_online_order(uuid) to authenticated;
grant execute on function public.process_online_order(uuid) to service_role;

-- ============================================================================
-- VERIFICATION: Check the current stock of "test" product before next test
-- ============================================================================
SELECT p.name, p.sku, p.stock_quantity, p.inventory_qty
FROM products p
WHERE p.sku = 'TES-TES-97277';
