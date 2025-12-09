-- ============================================================================
-- DEPLOY: Website Invoice Automation - Tax & Payment Method Handling
-- ============================================================================
-- Deploy: Run this in Supabase SQL Editor
-- Changes: core_schema.sql lines ~3648-3658, ~14008-14237, ~14337-14472
-- 
-- This migration:
-- 1. Adds MercadoPago payment method (with IVA tax_included)
-- 2. Updates process_online_order() for smart tax/status handling
-- 3. Adds confirm_online_order_payment() for manual transfer confirmation
-- 4. Adds trigger for auto-invoice on non-MercadoPago orders
-- ============================================================================

-- ============================================================================
-- STEP 1: Add MercadoPago to seed function for new tenants
-- ============================================================================
drop function if exists public.seed_payment_methods_for_tenant(uuid);

create or replace function public.seed_payment_methods_for_tenant(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_account_id uuid;
  v_bank_account_id uuid;
  v_count int;
begin
  perform set_config('request.jwt.claim.sub', p_tenant_id::text, true);
  
  select id into v_cash_account_id
  from accounts where tenant_id = p_tenant_id and code = '1101' limit 1;

  if v_cash_account_id is null then
    insert into accounts (tenant_id, code, name, type, category, is_active)
    values (p_tenant_id, '1101', 'Caja', 'asset', 'currentAsset', true)
    returning id into v_cash_account_id;
  end if;

  select id into v_bank_account_id
  from accounts where tenant_id = p_tenant_id and code = '1110' limit 1;

  if v_bank_account_id is null then
    insert into accounts (tenant_id, code, name, type, category, is_active)
    values (p_tenant_id, '1110', 'Banco', 'asset', 'currentAsset', true)
    returning id into v_bank_account_id;
  end if;

  v_count := 0;
  
  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'cash') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'cash', 'Efectivo', v_cash_account_id, false, 'no_tax', 'cash', 1, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'transfer') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'transfer', 'Transferencia', v_bank_account_id, true, 'no_tax', 'bank', 2, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'check') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'check', 'Cheque', v_bank_account_id, true, 'no_tax', 'receipt', 3, true);
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'card') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'card', 'Tarjeta de Crédito/Débito', v_bank_account_id, false, 'tax_included', 'credit_card', 4, true);
    v_count := v_count + 1;
  end if;

  -- NEW: MercadoPago with IVA
  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'mercadopago') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (p_tenant_id, 'mercadopago', 'MercadoPago', v_bank_account_id, true, 'tax_included', 'payment', 5, true);
    v_count := v_count + 1;
  end if;

  return format('✓ Created %s payment methods for tenant %s', v_count, p_tenant_id);
end;
$$;

-- Add MercadoPago to Viñabike tenant
do $$
declare
  v_bank_account_id uuid;
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
begin
  select id into v_bank_account_id
  from accounts where tenant_id = v_tenant_id and code = '1110' limit 1;

  if v_bank_account_id is null then
    insert into accounts (tenant_id, code, name, type, category, is_active)
    values (v_tenant_id, '1110', 'Banco', 'asset', 'currentAsset', true)
    returning id into v_bank_account_id;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = v_tenant_id and code = 'mercadopago') then
    insert into payment_methods (tenant_id, code, name, account_id, requires_reference, default_tax_treatment, icon, sort_order, is_active)
    values (v_tenant_id, 'mercadopago', 'MercadoPago', v_bank_account_id, true, 'tax_included', 'payment', 5, true);
    raise notice '✅ Created MercadoPago payment method for Viñabike';
  else
    raise notice '⚠️ MercadoPago already exists for Viñabike';
  end if;
end $$;


-- ============================================================================
-- STEP 2: Enhanced process_online_order with tax/status logic
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
-- STEP 3: Function to manually confirm wire transfer payments
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
  select * into v_order from online_orders
  where id = p_order_id and tenant_id = public.user_tenant_id();
  
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id;
  end if;
  
  if v_order.sales_invoice_id is null then
    raise exception 'Order has no invoice. Call process_online_order first.';
  end if;
  
  select * into v_invoice from sales_invoices where id = v_order.sales_invoice_id;
  
  if not found then
    raise exception 'Invoice not found: %', v_order.sales_invoice_id;
  end if;
  
  if v_invoice.status = 'paid' then
    raise notice 'Invoice already paid';
    return null;
  end if;
  
  select id into v_payment_method_id from payment_methods
  where tenant_id = v_order.tenant_id
    and lower(code) = lower(coalesce(v_order.payment_method, 'transfer'))
    and is_active = true limit 1;
  
  if v_payment_method_id is null then
    select id into v_payment_method_id from payment_methods
    where tenant_id = v_order.tenant_id
      and lower(code) in ('transfer', 'transferencia') and is_active = true limit 1;
  end if;
  
  if v_payment_method_id is null then
    raise exception 'No payment method found for tenant %', v_order.tenant_id;
  end if;
  
  update sales_invoices
  set status = 'confirmed', updated_at = now()
  where id = v_invoice.id and status != 'paid';
  
  insert into sales_payments (
    tenant_id, invoice_id, invoice_reference, payment_method_id,
    amount, payment_date, reference, notes
  ) values (
    v_order.tenant_id, v_invoice.id, v_invoice.invoice_number, v_payment_method_id,
    v_order.total, p_payment_date, p_payment_reference,
    'Confirmación manual - Transferencia - Pedido #' || v_order.order_number
  ) returning id into v_payment_id;
  
  update online_orders
  set payment_status = 'paid', paid_at = p_payment_date,
      payment_reference = coalesce(p_payment_reference, payment_reference),
      updated_at = now()
  where id = p_order_id;
  
  raise notice 'Payment confirmed for order %', v_order.order_number;
  return v_payment_id;
end;
$$;

grant execute on function public.confirm_online_order_payment(uuid, text, timestamp with time zone) to authenticated;


-- ============================================================================
-- STEP 4: Auto-invoice trigger for non-MercadoPago orders
-- ============================================================================
create or replace function public.handle_new_online_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(coalesce(NEW.payment_method, '')) not in ('mercadopago', 'mercado_pago') then
    perform public.process_online_order(NEW.id);
    raise notice 'Auto-created invoice for non-MercadoPago order %', NEW.order_number;
  else
    raise notice 'MercadoPago order % - invoice on payment confirmation', NEW.order_number;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_online_order_auto_invoice on online_orders;
create trigger trg_online_order_auto_invoice
  after insert on online_orders
  for each row
  execute function public.handle_new_online_order();


-- ============================================================================
-- VERIFICATION
-- ============================================================================
select code, name, default_tax_treatment, is_active
from payment_methods
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
order by sort_order;

select '✅ Website Invoice Automation deployed successfully!' as result;
