-- ============================================================================
-- FIX: Update auto_add_low_stock_to_purchase_list function
-- ============================================================================
-- Run this in Supabase SQL Editor
-- Fixes: column "suggested_qty" of relation "smart_purchase_list" does not exist
-- ============================================================================

create or replace function public.auto_add_low_stock_to_purchase_list()
returns trigger
language plpgsql
security definer
as $$
declare
  v_supplier_id uuid;
  v_supplier_name text;
  v_rotation_kpi numeric(5,2);
  v_avg_daily_consumption numeric(10,2);
  v_days_since_last_purchase integer;
  v_suggested_qty integer;
  v_priority numeric(5,2);
  v_lead_time_days integer;
  v_estimated_stockout_date timestamp with time zone;
  v_current_stock integer;
begin
  -- Sync inventory_qty to match stock_quantity (stock_quantity is source of truth)
  if NEW.stock_quantity != NEW.inventory_qty then
    NEW.inventory_qty := NEW.stock_quantity;
  end if;
  
  v_current_stock := coalesce(NEW.stock_quantity, NEW.inventory_qty, 0);
  
  -- AUTO-REMOVAL: If stock is now ABOVE minimum level, remove from pending list
  if v_current_stock > NEW.min_stock_level then
    delete from smart_purchase_list
    where product_id = NEW.id
    and status = 'pending'
    and tenant_id = NEW.tenant_id;
    
    if found then
      raise notice '🗑️ Auto-removed product % (%) from purchase list - stock restored to %', NEW.name, NEW.sku, v_current_stock;
    end if;
    
    return NEW;
  end if;
  
  -- AUTO-ADD: Trigger when stock is at or below minimum level
  if v_current_stock <= NEW.min_stock_level then
    
    -- Check if product is already in the purchase list with pending/ordered status
    if exists (
      select 1 from smart_purchase_list
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id
    ) then
      -- Already in list, just update the current stock
      update smart_purchase_list
      set current_stock = v_current_stock,
          updated_at = now()
      where product_id = NEW.id
      and status in ('pending', 'ordered')
      and tenant_id = NEW.tenant_id;
      
      return NEW;
    end if;
    
    -- Get supplier info
    select s.id, s.name into v_supplier_id, v_supplier_name
    from suppliers s
    where s.tenant_id = NEW.tenant_id
    and s.is_active = true
    order by s.created_at asc
    limit 1;
    
    -- Calculate rotation KPI (sales per day over last 30 days)
    -- NOTE: sales_invoices stores items in JSONB 'items' column, not a separate table
    -- Use text comparison to avoid UUID casting errors with null/empty product_ids
    select 
      coalesce(sum((item->>'quantity')::numeric), 0)::numeric / 30.0
    into v_avg_daily_consumption
    from sales_invoices si,
         jsonb_array_elements(si.items) as item
    where item->>'product_id' = NEW.id::text
    and si.tenant_id = NEW.tenant_id
    and si.date >= now() - interval '30 days'
    and si.status in ('confirmed', 'paid');
    
    v_rotation_kpi := coalesce(v_avg_daily_consumption * 100, 0);
    
    -- Days since last purchase
    -- NOTE: purchase_invoices stores items in JSONB 'items' column
    -- Use text comparison to avoid UUID casting errors with null/empty product_ids
    select extract(day from now() - max(pi.date))::integer
    into v_days_since_last_purchase
    from purchase_invoices pi,
         jsonb_array_elements(pi.items) as item
    where item->>'product_id' = NEW.id::text
    and pi.tenant_id = NEW.tenant_id;
    
    v_days_since_last_purchase := coalesce(v_days_since_last_purchase, 999);
    
    -- Lead time (use 7 days default)
    v_lead_time_days := 7;
    
    -- Calculate suggested quantity
    v_suggested_qty := greatest(
      NEW.max_stock_level - v_current_stock,
      ceil(coalesce(v_avg_daily_consumption, 0.1) * v_lead_time_days * 1.5)::integer,
      1
    );
    
    -- Calculate priority (0-100 scale)
    v_priority := least(100, greatest(0,
      (case when v_current_stock = 0 then 50 else 0 end) +
      (case when v_current_stock <= NEW.min_stock_level * 0.5 then 25 else 0 end) +
      least(v_rotation_kpi, 25)
    ));
    
    -- Estimate stockout date
    if v_avg_daily_consumption > 0 then
      v_estimated_stockout_date := now() + (v_current_stock / v_avg_daily_consumption) * interval '1 day';
    end if;
    
    -- Insert into purchase list with CORRECT column name: suggested_quantity
    insert into smart_purchase_list (
      tenant_id,
      product_id,
      product_name,
      product_sku,
      supplier_id,
      supplier_name,
      suggested_quantity,  -- FIXED: was suggested_qty
      status,
      priority,
      rotation_kpi,
      days_since_last_purchase,
      current_stock,
      min_stock_level,
      avg_daily_consumption,
      lead_time_days,
      estimated_stockout_date,
      notes,
      added_date
    ) values (
      NEW.tenant_id,
      NEW.id,
      NEW.name,
      NEW.sku,
      v_supplier_id,
      v_supplier_name,
      v_suggested_qty,
      'pending',
      v_priority,
      v_rotation_kpi,
      v_days_since_last_purchase,
      v_current_stock,
      NEW.min_stock_level,
      v_avg_daily_consumption,
      v_lead_time_days,
      v_estimated_stockout_date,
      'Auto-added: stock at or below minimum level',
      now()
    );
    
    raise notice '✅ Auto-added product % (%) to purchase list with priority %', NEW.name, NEW.sku, v_priority;
  end if;
  
  return NEW;
end;
$$;

-- ============================================================================
-- Also update process_online_order to ensure it's the latest version
-- ============================================================================
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
  select * into v_order from online_orders where id = p_order_id;
  
  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;
  
  v_tenant_id := v_order.tenant_id;
  if v_tenant_id is null then
    raise exception 'Order has no tenant_id: %', p_order_id;
  end if;
  
  if v_order.sales_invoice_id is not null then
    return v_order.sales_invoice_id;
  end if;
  
  select * into v_payment_method
  from payment_methods
  where tenant_id = v_tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'mercadopago'))
    and is_active = true
  limit 1;
  
  if v_payment_method is null then
    select * into v_payment_method
    from payment_methods
    where tenant_id = v_tenant_id and is_active = true
    order by sort_order limit 1;
  end if;
  
  -- TAX TREATMENT: Based on order's tax_amount (set by frontend per payment method)
  if v_order.tax_amount > 0 then
    v_tax_treatment := 'tax_included';
    v_net_amount := round(v_order.total / 1.19, 2);
    v_iva_amount := round(v_order.total - v_net_amount, 2);
  else
    v_tax_treatment := 'no_tax';
    v_net_amount := v_order.subtotal;
    v_iva_amount := 0;
  end if;
  
  -- INVOICE STATUS: Based on payment status
  -- NOTE: We use 'sent' for pending payments to avoid triggering journal entry creation
  -- Journal entries are created when payment is confirmed (status changes to 'paid')
  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
  else
    -- For pending payments (MercadoPago, transfer, etc.), use 'sent' status
    -- This avoids creating journal entries until payment is confirmed
    v_invoice_status := 'sent';
    v_should_create_payment := false;
  end if;
  
  v_year := to_char(now(), 'YY');
  select coalesce(max(cast(substring(invoice_number from '\d+$') as integer)), 0) + 1
  into v_next_number
  from sales_invoices
  where tenant_id = v_tenant_id and invoice_number ~ ('^INV-' || v_year || '-\d+$');
  
  v_invoice_number := 'INV-' || v_year || '-' || lpad(v_next_number::text, 5, '0');
  
  select jsonb_agg(jsonb_build_object(
    'product_id', oi.product_id, 'product_name', oi.product_name,
    'product_sku', oi.product_sku, 'quantity', oi.quantity,
    'price', oi.unit_price, 'subtotal', oi.subtotal
  )) into v_items from online_order_items oi where oi.order_id = p_order_id;
  
  if v_items is null then v_items := '[]'::jsonb; end if;
  
  insert into sales_invoices (
    tenant_id, invoice_number, customer_id, customer_name, date, due_date,
    status, tax_treatment, net_amount, subtotal, iva_amount, total,
    paid_amount, balance, items, reference
  ) values (
    v_tenant_id, v_invoice_number, v_order.customer_id, v_order.customer_name,
    now(), now() + interval '30 days', v_invoice_status, v_tax_treatment,
    v_net_amount, v_order.subtotal, v_iva_amount, v_order.total,
    case when v_should_create_payment then v_order.total else 0 end,
    case when v_should_create_payment then 0 else v_order.total end,
    v_items,
    'Pedido online #' || v_order.order_number || 
    case when v_order.delivery_type = 'pickup' then ' (Retiro en tienda)' else ' (Envío)' end
  ) returning id into v_invoice_id;
  
  raise notice 'Created invoice % (status: %, tax: %) for order %', 
    v_invoice_number, v_invoice_status, v_tax_treatment, v_order.order_number;
  
  update online_orders
  set sales_invoice_id = v_invoice_id, invoice_id = v_invoice_id,
      status = case when status = 'pending' then 'confirmed' else status end,
      updated_at = now()
  where id = p_order_id;
  
  if v_should_create_payment and v_payment_method.id is not null then
    insert into sales_payments (
      tenant_id, invoice_id, invoice_reference, payment_method_id,
      amount, payment_date, reference, notes
    ) values (
      v_tenant_id, v_invoice_id, v_invoice_number, v_payment_method.id,
      v_order.total, coalesce(v_order.paid_at, now()), v_order.payment_reference,
      'Pago automático - Pedido #' || v_order.order_number || ' (' || v_payment_method.name || ')'
    );
    raise notice 'Created payment for invoice %', v_invoice_number;
  end if;
  
  return v_invoice_id;
end;
$$;

-- ============================================================================
-- FIX: Update create_sales_invoice_journal_entry to pass tenant_id to ensure_account
-- This is critical for webhook/service role context where user_tenant_id() returns null
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
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    return;
  end if;

  v_tenant_id := p_invoice.tenant_id;
  
  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_invoice_journal_entry: No tenant_id on invoice %, skipping', p_invoice.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.id::text
       )
    into v_exists;

  if v_exists then
    return;
  end if;

  v_subtotal := coalesce(p_invoice.net_amount, p_invoice.subtotal, 0);
  v_iva := coalesce(p_invoice.iva_amount, 0);
  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    return;
  end if;

  -- FIX: Pass tenant_id to ensure_account (use overloaded version)
  v_receivable_account_id := public.ensure_account(
    v_tenant_id,  -- ADDED: explicit tenant_id
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_tenant_id,  -- ADDED: explicit tenant_id
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_tenant_id,  -- ADDED: explicit tenant_id
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
      v_tenant_id,  -- ADDED: explicit tenant_id
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_tenant_id,  -- ADDED: explicit tenant_id
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
      format('IVA factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 and v_cogs_account_id is not null and v_inventory_account_id is not null then
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
      format('Costo de venta %s', v_invoice_number),
      v_total_cost,
      0,
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
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Reducción inventario %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;

  raise notice 'Created journal entry for sales invoice %', p_invoice.invoice_number;
end;
$$;

-- ============================================================================
-- FIX: Update create_sales_payment_journal_entry to pass tenant_id to ensure_account
-- ============================================================================
create or replace function public.create_sales_payment_journal_entry(p_payment public.sales_payments)
returns void as $$
declare
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_description text;
  v_tenant_id uuid;
begin
  if p_payment.invoice_id is null then
    return;
  end if;

  v_tenant_id := p_payment.tenant_id;
  
  -- CRITICAL: Validate tenant_id for service role context (webhooks)
  if v_tenant_id is null then
    raise warning 'create_sales_payment_journal_entry: No tenant_id on payment %, skipping', p_payment.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_payments'
              and source_reference = p_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         customer_name,
         total
    into v_invoice
    from public.sales_invoices
   where id = p_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account (DYNAMIC!)
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = p_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', p_payment.id;
  end if;

  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  -- FIX: Pass tenant_id to ensure_account (use overloaded version)
  v_receivable_account_id := public.ensure_account(
    v_tenant_id,  -- ADDED: explicit tenant_id
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

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
    coalesce(p_payment.date, now()),
    v_description,
    'payment',
    'sales_payments',
    v_invoice.invoice_number,
    'posted',
    p_payment.amount,
    p_payment.amount,
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
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    v_description,
    p_payment.amount,
    0,
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
    0,
    p_payment.amount,
    now(),
    now()
  );

  raise notice 'Created journal entry for sales payment %', p_payment.id;
end;
$$ language plpgsql;

select '✅ All functions updated successfully!' as result;
