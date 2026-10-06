-- A signed-in store customer could not pay by bank transfer (since
-- 20260711123000): the public checkout creates the order and then, for any
-- method but Mercado Pago, processes it through process_online_order, whose
-- guard rejects every authenticated caller who is not staff of the tenant
-- ("Order not found or access denied", 42501), and the whole order rolled
-- back. Guests pass because auth.uid() is null. Production has no transfer
-- order by a signed-in non-staff customer after that date.
--
-- The checkout has already verified that the customer belongs to the store
-- and to the session (create_public_online_order_unkeyed): it now processes
-- its own order through process_public_checkout_order, an internal function
-- no API role can call. process_online_order keeps its guard for the ERP.

create or replace function public.process_public_checkout_order(
  p_order_id uuid,
  p_tenant_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_invoice_id uuid;
  v_previous_context text := current_setting('app.online_order_id', true);
begin
  if not exists (
    select 1
    from public.online_orders customer_order
    where customer_order.id = p_order_id
      and customer_order.tenant_id = p_tenant_id
  ) then
    raise exception 'Order not found: %', p_order_id;
  end if;

  perform set_config('app.online_order_id', p_order_id::text, true);
  v_invoice_id := public.process_online_order_internal(p_order_id);
  perform public.finalize_online_inventory_reservations_for_invoice(
    p_order_id,
    v_invoice_id,
    p_tenant_id,
    false
  );
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  return v_invoice_id;
exception when others then
  perform set_config('app.online_order_id', coalesce(v_previous_context, ''), true);
  raise;
end;
$function$;

revoke all on function public.process_public_checkout_order(uuid, uuid)
  from public, anon, authenticated, service_role;

comment on function public.process_public_checkout_order(uuid, uuid) is
  'Processes an order the public checkout just created and verified (customer membership included), exactly as process_online_order does but without its staff-tenant guard. Called only by create_public_online_order_unkeyed; no API role may execute it.';

CREATE OR REPLACE FUNCTION public.create_public_online_order_unkeyed(p_order_data jsonb, p_order_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_customer_id_text text;
  v_checkout_key text;
  v_created_response jsonb;
  v_item_tax_snapshot jsonb;
  v_shipping_quote jsonb;
  v_expected_shipping_gross numeric(12,2);
  v_shipping_gross numeric(12,2);
  v_shipping_net numeric(12,2);
  v_shipping_tax numeric(12,2);
  v_shipping_tax_rate numeric(5,2);
  v_shipping_tier_id uuid;
  v_shipping_country text;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload';
  end if;

  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array'
     or jsonb_array_length(p_order_items) = 0 then
    raise exception 'Order must include at least one item';
  end if;
  if jsonb_array_length(p_order_items) > 50 then
    raise exception 'Order item limit exceeded';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null or not exists (
    select 1 from public.tenants tenant where tenant.id = v_tenant_id
  ) then
    raise exception 'Invalid tenant_id';
  end if;

  v_customer_name := btrim(coalesce(p_order_data->>'customer_name', ''));
  v_customer_email := lower(btrim(coalesce(p_order_data->>'customer_email', '')));
  v_customer_phone := nullif(btrim(coalesce(p_order_data->>'customer_phone', '')), '');
  v_customer_address := nullif(btrim(coalesce(p_order_data->>'customer_address', '')), '');
  v_delivery_type := lower(btrim(coalesce(
    nullif(p_order_data->>'delivery_type', ''),
    'shipping'
  )));
  v_payment_method := lower(btrim(coalesce(
    nullif(p_order_data->>'payment_method', ''),
    'transfer'
  )));
  v_checkout_key := nullif(
    btrim(coalesce(p_order_data->>'checkout_idempotency_key', '')),
    ''
  );
  v_shipping_country := btrim(coalesce(
    nullif(p_order_data->>'shipping_country', ''),
    'Chile'
  ));

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
  if v_delivery_type = 'shipping'
     and lower(v_shipping_country) not in ('chile', 'cl') then
    raise exception 'Online shipping is currently available only in Chile';
  end if;
  if v_payment_method not in (
    'mercadopago', 'mercado_pago', 'transfer', 'bank_transfer'
  ) then
    raise exception 'Invalid payment method: %', v_payment_method;
  end if;

  if v_payment_method = 'mercado_pago' then
    v_payment_method := 'mercadopago';
  elsif v_payment_method = 'bank_transfer' then
    v_payment_method := 'transfer';
  end if;

  if v_delivery_type = 'shipping'
     and coalesce(
       nullif(p_order_data->>'shipping_address_line1', ''),
       v_customer_address
     ) is null then
    raise exception 'Shipping address is required';
  end if;

  if p_order_data ? 'shipping_quote_cost' then
    begin
      v_expected_shipping_gross :=
        (p_order_data->>'shipping_quote_cost')::numeric;
    exception when others then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end;
    if v_expected_shipping_gross is null
       or v_expected_shipping_gross < 0
       or v_expected_shipping_gross
            <> public.clp_round(v_expected_shipping_gross) then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end if;
  end if;

  v_customer_id_text := nullif(p_order_data->>'customer_id', '');
  if v_customer_id_text is not null then
    v_customer_id := v_customer_id_text::uuid;
    if v_auth_uid is null or not exists (
      select 1
        from public.customers customer
       where customer.id = v_customer_id
         and customer.tenant_id = v_tenant_id
         and customer.auth_user_id = v_auth_uid
    ) then
      raise exception 'Invalid customer reference';
    end if;
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into public.online_orders (
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
    shipping_net_amount,
    shipping_tax_amount,
    shipping_tax_rate,
    shipping_rate_snapshot,
    discount_amount,
    total,
    status,
    payment_status,
    payment_method,
    customer_notes
  ) values (
    v_tenant_id,
    public.generate_online_order_number(v_tenant_id, clock_timestamp()),
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
    case when v_delivery_type = 'pickup' then null else 'Chile' end,
    0,
    0,
    0,
    0,
    0,
    0,
    '{}'::jsonb,
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

    select
      product.id,
      product.name,
      product.sku,
      coalesce(product.website_price, product.price) as public_price,
      product.cost,
      product.tax_rate,
      product.product_type,
      product.is_service,
      product.purchase_treatment,
      product.track_stock,
      product.is_set,
      product.inventory_qty,
      product.stock_quantity
      into v_product
      from public.products product
     where product.id = v_product_id
       and product.tenant_id = v_tenant_id
       and product.is_active = true
       and coalesce(product.is_published, false) = true
       and coalesce(product.show_on_website, false) = true
     for update;

    if not found then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;
    if v_product.tax_rate is null
       or v_product.tax_rate not in (0, 0.19, 19) then
      raise exception 'Product % has missing or unsupported tax classification',
        v_product.name
        using errcode = '23514';
    end if;

    if not (
      coalesce(v_product.is_service, false)
      or v_product.product_type = 'service'
    )
       and coalesce(v_product.track_stock, true) then
      if coalesce(v_product.is_set, false) then
        -- Canonical set headers are virtual. Validate their component map and
        -- availability after active reservations; the item-insert trigger then
        -- locks and reserves every physical component atomically.
        perform public.assert_valid_product_set_maps(
          v_tenant_id,
          jsonb_build_array(jsonb_build_object(
            'product_id', v_product.id,
            'quantity', v_quantity
          ))
        );
        if public.online_product_available_quantity(
          v_tenant_id,
          v_product.id
        ) < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      else
        if v_product.stock_quantity is not null
           and v_product.inventory_qty is not null
           and v_product.stock_quantity <> v_product.inventory_qty then
          raise exception 'Product stock columns disagree; checkout blocked for %',
            v_product.name;
        end if;
        if coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
           < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      end if;
    end if;

    if v_product.public_price is null
       or v_product.public_price <= 0
       or v_product.public_price <> public.clp_round(v_product.public_price) then
      raise exception 'Product % requires a positive whole-CLP website price',
        v_product.name
        using errcode = '23514';
    end if;
    v_unit_price := public.clp_round(v_product.public_price);
    v_line_total := public.clp_round(v_unit_price * v_quantity);

    insert into public.online_order_items (
      tenant_id,
      order_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      subtotal,
      unit_cost,
      tax_rate,
      is_service,
      purchase_treatment,
      product_type
    ) values (
      v_tenant_id,
      v_order_id,
      v_product.id,
      v_product.name,
      v_product.sku,
      v_quantity,
      v_unit_price,
      v_line_total,
      v_product.cost,
      case when v_product.tax_rate = 0.19 then 19 else v_product.tax_rate end,
      (
        coalesce(v_product.is_service, false)
        or v_product.product_type = 'service'
      ),
      coalesce(v_product.purchase_treatment, 'inventory'),
      coalesce(v_product.product_type, 'product')
    );
  end loop;

  v_item_tax_snapshot := public.calculate_online_order_tax_snapshot(
    v_order_id,
    v_tenant_id
  );
  v_shipping_quote := public.quote_online_shipping_internal(
    v_tenant_id,
    v_delivery_type,
    (v_item_tax_snapshot->>'gross_amount')::numeric,
    'CL'
  );
  v_shipping_gross := (v_shipping_quote->>'shipping_gross')::numeric;
  v_shipping_net := (v_shipping_quote->>'shipping_net')::numeric;
  v_shipping_tax := (v_shipping_quote->>'shipping_tax')::numeric;
  v_shipping_tax_rate := (v_shipping_quote->>'tax_rate')::numeric;
  v_shipping_tier_id := nullif(v_shipping_quote->>'tier_id', '')::uuid;

  if v_expected_shipping_gross is null then
    if v_shipping_gross > 0 then
      raise exception 'A current shipping quote is required before checkout'
        using errcode = '23514';
    end if;
    v_expected_shipping_gross := 0;
  end if;

  if v_expected_shipping_gross <> v_shipping_gross then
    raise exception 'Shipping quote changed; refresh checkout before paying'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    'true',
    true
  );
  update public.online_orders
     set subtotal = (v_item_tax_snapshot->>'net_amount')::numeric,
         tax_amount = (v_item_tax_snapshot->>'tax_amount')::numeric,
         shipping_cost = v_shipping_gross,
         shipping_net_amount = v_shipping_net,
         shipping_tax_amount = v_shipping_tax,
         shipping_tax_rate = v_shipping_tax_rate,
         shipping_rate_tier_id = v_shipping_tier_id,
         shipping_rate_snapshot = v_shipping_quote,
         discount_amount = 0,
         total = (v_item_tax_snapshot->>'gross_amount')::numeric
           + v_shipping_gross
   where id = v_order_id
     and tenant_id = v_tenant_id;
  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    '',
    true
  );

  select jsonb_build_object(
    'success', true,
    'order_id', orders.id,
    'status', orders.status,
    'payment_status', orders.payment_status,
    'version', orders.version,
    'invoice_id', orders.sales_invoice_id,
    'total', orders.total,
    'shipping_cost', orders.shipping_cost,
    'changed', true
  )
    into v_created_response
    from public.online_orders orders
   where orders.id = v_order_id
     and orders.tenant_id = v_tenant_id;

  insert into public.online_order_events (
    tenant_id,
    order_id,
    event_type,
    from_status,
    to_status,
    from_payment_status,
    to_payment_status,
    changed,
    expected_version,
    result_version,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot
  )
  select
    orders.tenant_id,
    orders.id,
    'order_created',
    null,
    orders.status,
    null,
    orders.payment_status,
    true,
    null,
    orders.version,
    v_auth_uid,
    'checkout-created:' || orders.id::text,
    jsonb_build_object(
      'source', 'public_checkout',
      'checkout_idempotency_key', v_checkout_key,
      'delivery_type', orders.delivery_type,
      'payment_method', orders.payment_method,
      'item_count', jsonb_array_length(p_order_items),
      'tax_source', 'product_line_snapshot',
      'shipping_quote', orders.shipping_rate_snapshot,
      'accepted_shipping_cost', v_expected_shipping_gross
    ),
    v_created_response
  from public.online_orders orders
  where orders.id = v_order_id
    and orders.tenant_id = v_tenant_id;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  if v_payment_method <> 'mercadopago' then
    perform public.process_public_checkout_order(v_order_id, v_tenant_id);
  end if;

  return v_order_id;
exception
  when others then
    perform pg_catalog.set_config(
      'app.online_order_shipping_quote_in_progress',
      '',
      true
    );
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$function$;

comment on function public.create_public_online_order_unkeyed(jsonb, jsonb) is
  'Private authoritative checkout implementation. Re-reads product price/tax/stock, derives set availability from canonical components, verifies the shipping quote and persists immutable tax/accounting snapshots atomically.';
