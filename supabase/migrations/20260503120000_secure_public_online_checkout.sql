-- Secure public checkout: move guest order creation behind server-side pricing,
-- hide website_settings secrets from public reads, and let confirmation pages read
-- a single order by UUID + storefront tenant.

create or replace function public.handle_new_online_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('app.public_order_rpc_in_progress', true) = 'true' then
    return NEW;
  end if;

  if lower(coalesce(NEW.payment_method, '')) not in ('mercadopago', 'mercado_pago') then
    perform public.process_online_order(NEW.id);
    raise notice 'Auto-created invoice for non-MercadoPago order %', NEW.order_number;
  else
    raise notice 'MercadoPago order % - invoice will be created on payment confirmation', NEW.order_number;
  end if;

  return NEW;
end;
$$;

create or replace function public.create_public_online_order(
  p_order_data jsonb,
  p_order_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_customer_id uuid;
  v_auth_uid uuid := auth.uid();
  v_customer_name text;
  v_customer_email text;
  v_customer_phone text;
  v_customer_address text;
  v_delivery_type text;
  v_payment_method text;
  v_order_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_product record;
  v_line_total numeric(12,2);
  v_total numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_tax_amount numeric(12,2) := 0;
  v_customer_id_text text;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload';
  end if;

  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) = 0 then
    raise exception 'Order must include at least one item';
  end if;

  if jsonb_array_length(p_order_items) > 50 then
    raise exception 'Order item limit exceeded';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null or not exists (select 1 from tenants where id = v_tenant_id) then
    raise exception 'Invalid tenant_id';
  end if;

  v_customer_name := btrim(coalesce(p_order_data->>'customer_name', ''));
  v_customer_email := lower(btrim(coalesce(p_order_data->>'customer_email', '')));
  v_customer_phone := nullif(btrim(coalesce(p_order_data->>'customer_phone', '')), '');
  v_customer_address := nullif(btrim(coalesce(p_order_data->>'customer_address', '')), '');
  v_delivery_type := lower(btrim(coalesce(nullif(p_order_data->>'delivery_type', ''), 'shipping')));
  v_payment_method := lower(btrim(coalesce(nullif(p_order_data->>'payment_method', ''), 'transfer')));

  if length(v_customer_name) < 2 or length(v_customer_name) > 160 then
    raise exception 'Invalid customer name';
  end if;

  if v_customer_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Invalid customer email';
  end if;

  if v_customer_phone is not null and length(v_customer_phone) > 40 then
    raise exception 'Invalid customer phone';
  end if;

  if v_delivery_type not in ('shipping', 'pickup') then
    raise exception 'Invalid delivery type: %', v_delivery_type;
  end if;

  if v_payment_method not in ('mercadopago', 'mercado_pago', 'transfer', 'bank_transfer') then
    raise exception 'Invalid payment method: %', v_payment_method;
  end if;

  if v_payment_method = 'mercado_pago' then
    v_payment_method := 'mercadopago';
  elsif v_payment_method = 'bank_transfer' then
    v_payment_method := 'transfer';
  end if;

  if v_delivery_type = 'shipping' and coalesce(nullif(p_order_data->>'shipping_address_line1', ''), v_customer_address) is null then
    raise exception 'Shipping address is required';
  end if;

  v_customer_id_text := nullif(p_order_data->>'customer_id', '');
  if v_customer_id_text is not null then
    v_customer_id := v_customer_id_text::uuid;

    if v_auth_uid is null or not exists (
      select 1
      from customers
      where id = v_customer_id
        and tenant_id = v_tenant_id
        and auth_user_id = v_auth_uid
    ) then
      raise exception 'Invalid customer reference';
    end if;
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into online_orders (
    tenant_id,
    order_number,
    customer_id,
    customer_email,
    customer_name,
    customer_phone,
    customer_address,
    delivery_type,
    shipping_address_line1,
    shipping_address_line2,
    shipping_city,
    shipping_state,
    shipping_postal_code,
    shipping_country,
    subtotal,
    tax_amount,
    shipping_cost,
    discount_amount,
    total,
    status,
    payment_status,
    payment_method,
    customer_notes
  ) values (
    v_tenant_id,
    coalesce(nullif(p_order_data->>'order_number', ''), ''),
    v_customer_id,
    v_customer_email,
    v_customer_name,
    v_customer_phone,
    v_customer_address,
    v_delivery_type,
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line1', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line2', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_city', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_state', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_postal_code', '')), ''),
    coalesce(nullif(btrim(coalesce(p_order_data->>'shipping_country', '')), ''), 'Chile'),
    0,
    0,
    0,
    0,
    0,
    'pending',
    'pending',
    v_payment_method,
    nullif(left(btrim(coalesce(p_order_data->>'customer_notes', '')), 1000), '')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_order_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::integer, 0);

    if v_product_id is null then
      raise exception 'Order item is missing product_id';
    end if;

    if v_quantity < 1 or v_quantity > 99 then
      raise exception 'Invalid quantity for product %', v_product_id;
    end if;

    select id, name, sku, price, product_type, track_stock, inventory_qty, stock_quantity
      into v_product
      from products
     where id = v_product_id
       and tenant_id = v_tenant_id
       and is_active = true
       and is_published = true
       and coalesce(show_on_website, true) = true
     limit 1;

    if not found then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;

    if coalesce(v_product.product_type, 'product') <> 'service'
       and coalesce(v_product.track_stock, true) = true
       and greatest(coalesce(v_product.inventory_qty, 0), coalesce(v_product.stock_quantity, 0)) < v_quantity then
      raise exception 'Insufficient stock for product %', v_product.name;
    end if;

    v_line_total := round(coalesce(v_product.price, 0)::numeric * v_quantity, 2);
    if v_line_total <= 0 then
      raise exception 'Invalid price for product %', v_product.name;
    end if;

    insert into online_order_items (
      tenant_id,
      order_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      subtotal
    ) values (
      v_tenant_id,
      v_order_id,
      v_product.id,
      v_product.name,
      v_product.sku,
      v_quantity,
      round(v_product.price::numeric, 2),
      v_line_total
    );

    v_total := v_total + v_line_total;
  end loop;

  if v_total <= 0 then
    raise exception 'Invalid order total';
  end if;

  if v_payment_method = 'mercadopago' then
    v_subtotal := round(v_total / 1.19, 2);
    v_tax_amount := round(v_total - v_subtotal, 2);
  else
    v_subtotal := v_total;
    v_tax_amount := 0;
  end if;

  update online_orders
     set subtotal = v_subtotal,
         tax_amount = v_tax_amount,
         shipping_cost = 0,
         discount_amount = 0,
         total = v_total,
         updated_at = now()
   where id = v_order_id;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  if v_payment_method <> 'mercadopago' then
    perform public.process_online_order(v_order_id);
  end if;

  return v_order_id;
exception
  when others then
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$$;

grant execute on function public.create_public_online_order(jsonb, jsonb) to anon, authenticated;

create or replace function public.get_public_online_order(
  p_order_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order jsonb;
begin
  select to_jsonb(o) || jsonb_build_object('online_order_items', coalesce(items.items, '[]'::jsonb))
  into v_order
  from online_orders o
  left join lateral (
    select jsonb_agg(to_jsonb(oi) order by oi.created_at) as items
    from online_order_items oi
    where oi.order_id = o.id
      and oi.tenant_id = o.tenant_id
  ) items on true
  where o.id = p_order_id
    and o.tenant_id = p_tenant_id;

  return v_order;
end;
$$;

grant execute on function public.get_public_online_order(uuid, uuid) to anon, authenticated;

drop policy if exists "public_website_settings_select" on website_settings;
drop policy if exists "public_website_settings_select_authenticated" on website_settings;

create policy "public_website_settings_select" on website_settings
  for select
  to anon
  using (
    tenant_id is not null and
    lower(key) not like '%access_token%' and
    lower(key) not like '%secret%' and
    lower(key) not like '%password%' and
    lower(key) not like '%private%'
  );

create policy "public_website_settings_select_authenticated" on website_settings
  for select
  to authenticated
  using (
    tenant_id is not null and
    lower(key) not like '%access_token%' and
    lower(key) not like '%secret%' and
    lower(key) not like '%password%' and
    lower(key) not like '%private%'
  );

drop policy if exists "public_online_orders_insert" on online_orders;
drop policy if exists "public_online_orders_insert_authenticated" on online_orders;
drop policy if exists "public_online_order_items_insert" on online_order_items;
drop policy if exists "public_online_order_items_insert_authenticated" on online_order_items;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'orders') then
    execute 'drop policy if exists "public_orders_insert" on orders';
  end if;
end $$;

do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'order_items') then
    execute 'drop policy if exists "public_order_items_insert" on order_items';
  end if;
end $$;
