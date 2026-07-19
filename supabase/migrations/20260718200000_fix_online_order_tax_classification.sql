-- Prospective ecommerce tax hardening.
--
-- Public prices are gross, tax-included CLP amounts. Tax truth comes from the
-- immutable product tax-rate snapshot on each order line, never from the
-- payment rail. Existing orders/invoices are not backfilled or rewritten.

begin;

comment on column public.online_order_items.tax_rate is
  'Immutable checkout tax classification in canonical percentage form (0 exempt or 19 IVA). It drives the line net/IVA split; payment method never does.';

create or replace function public.calculate_online_order_tax_snapshot(
  p_order_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.online_order_items%rowtype;
  v_line_gross numeric(12,2);
  v_line_net numeric(12,2);
  v_line_tax numeric(12,2);
  v_line_tax_rate numeric(5,2);
  v_gross numeric(12,2) := 0;
  v_net numeric(12,2) := 0;
  v_tax numeric(12,2) := 0;
  v_item_count integer := 0;
  v_invoice_items jsonb := '[]'::jsonb;
begin
  if p_order_id is null or p_tenant_id is null then
    raise exception 'Online order and tenant are required for tax calculation'
      using errcode = '22004';
  end if;

  for v_item in
    select item.*
      from public.online_order_items item
     where item.order_id = p_order_id
       and item.tenant_id = p_tenant_id
     order by item.created_at, item.id
  loop
    v_item_count := v_item_count + 1;

    if v_item.quantity is null or v_item.quantity < 1 then
      raise exception 'Invalid quantity in online order tax snapshot for line %',
        v_item.id
        using errcode = '23514';
    end if;
    if v_item.unit_price is null
       or v_item.unit_price <= 0
       or v_item.unit_price <> public.clp_round(v_item.unit_price) then
      raise exception 'Online order line % requires a positive whole-CLP gross price',
        v_item.id
        using errcode = '23514';
    end if;
    if v_item.tax_rate is null or v_item.tax_rate not in (0, 0.19, 19) then
      raise exception 'Online order line % has missing or unsupported tax classification',
        v_item.id
        using errcode = '23514';
    end if;
    -- Older imports represented 19% as the fraction 0.19. Accept that known
    -- representation, but normalize the immutable checkout/invoice snapshot
    -- to the canonical percentage value 19.
    v_line_tax_rate := case
      when v_item.tax_rate = 0.19 then 19
      else v_item.tax_rate
    end;

    v_line_gross := public.clp_round(v_item.unit_price * v_item.quantity);
    if v_item.subtotal is null
       or v_item.subtotal <> public.clp_round(v_item.subtotal)
       or v_item.subtotal <> v_line_gross then
      raise exception 'Online order line % gross subtotal is inconsistent',
        v_item.id
        using errcode = '23514';
    end if;

    if v_line_tax_rate = 19 then
      v_line_net := public.clp_round(v_line_gross / 1.19);
      v_line_tax := v_line_gross - v_line_net;
    else
      v_line_net := v_line_gross;
      v_line_tax := 0;
    end if;

    v_gross := v_gross + v_line_gross;
    v_net := v_net + v_line_net;
    v_tax := v_tax + v_line_tax;
    v_invoice_items := v_invoice_items || jsonb_build_array(jsonb_build_object(
      'line_id', v_item.id,
      'product_id', v_item.product_id,
      'product_name', v_item.product_name,
      'product_sku', v_item.product_sku,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'price', v_item.unit_price,
      'subtotal', v_line_gross,
      'line_total', v_line_gross,
      'gross_amount', v_line_gross,
      'net_amount', v_line_net,
      'tax_amount', v_line_tax,
      'tax_rate', v_line_tax_rate,
      'discount', 0,
      'cost', v_item.unit_cost,
      'is_service', v_item.is_service,
      'purchase_treatment', v_item.purchase_treatment,
      'product_type', v_item.product_type,
      'is_catalog_product', v_item.product_id is not null
    ));
  end loop;

  if v_item_count = 0 or v_gross <= 0 then
    raise exception 'Online order has no valid tax-classified items'
      using errcode = '23514';
  end if;
  if v_gross <> v_net + v_tax then
    raise exception 'Online order tax breakdown does not reconcile'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'gross_amount', v_gross,
    'net_amount', v_net,
    'tax_amount', v_tax,
    'tax_treatment', case when v_tax > 0 then 'tax_included' else 'no_tax' end,
    'item_count', v_item_count,
    'items', v_invoice_items
  );
end;
$$;

comment on function public.calculate_online_order_tax_snapshot(uuid, uuid) is
  'Private deterministic ecommerce tax calculator. Gross CLP prices are split per immutable line tax_rate (canonical 0 or 19; legacy fraction 0.19 normalizes to 19); missing/unsupported classifications fail closed.';

revoke all on function public.calculate_online_order_tax_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;

-- The public catalog projection predates tax classification. Keep the broad
-- catalog RPC stable and expose only id + rate for the bounded set of already
-- public products the browser is rendering. Missing/unsupported values remain
-- visible to the client so it can block checkout instead of assuming IVA.
create or replace function public.get_public_product_tax_classifications(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns table (
  id uuid,
  tax_rate numeric
)
language sql
security definer
set search_path = public
stable
as $$
  select product.id, product.tax_rate
    from public.products product
   where p_tenant_id is not null
     and p_product_ids is not null
     and cardinality(p_product_ids) between 1 and 100
     and product.tenant_id = p_tenant_id
     and product.id = any(p_product_ids)
     and product.is_active = true
     and coalesce(product.is_published, false) = true
     and coalesce(product.show_on_website, false) = true
   order by product.id;
$$;

comment on function public.get_public_product_tax_classifications(uuid, uuid[]) is
  'Narrow public checkout projection for already-public products. Returns the raw tax classification so clients can fail closed on null/unsupported values; it never derives tax from payment method.';

revoke all on function public.get_public_product_tax_classifications(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_tax_classifications(uuid, uuid[])
  to anon, authenticated;

create or replace function public.create_public_online_order_unkeyed(
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
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_customer_id_text text;
  v_checkout_key text;
  v_created_response jsonb;
  v_tax_snapshot jsonb;
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
    coalesce(
      nullif(btrim(coalesce(p_order_data->>'shipping_country', '')), ''),
      'Chile'
    ),
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

  v_tax_snapshot := public.calculate_online_order_tax_snapshot(
    v_order_id,
    v_tenant_id
  );

  update public.online_orders
     set subtotal = (v_tax_snapshot->>'net_amount')::numeric,
         tax_amount = (v_tax_snapshot->>'tax_amount')::numeric,
         shipping_cost = 0,
         discount_amount = 0,
         total = (v_tax_snapshot->>'gross_amount')::numeric
   where id = v_order_id
     and tenant_id = v_tenant_id;

  select jsonb_build_object(
    'success', true,
    'order_id', orders.id,
    'status', orders.status,
    'payment_status', orders.payment_status,
    'version', orders.version,
    'invoice_id', orders.sales_invoice_id,
    'total', orders.total,
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
      'tax_source', 'product_line_snapshot'
    ),
    v_created_response
  from public.online_orders orders
  where orders.id = v_order_id
    and orders.tenant_id = v_tenant_id;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  -- The rail controls only when fulfillment begins. It never classifies tax.
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

revoke all on function public.create_public_online_order_unkeyed(jsonb, jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.process_online_order_internal(p_order_id uuid)
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
  v_gross_amount numeric(12,2);
  v_tax_treatment text;
  v_tax_snapshot jsonb;
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

  -- Existing invoices retain their immutable tax/accounting history. This
  -- branch only settles an already-created document when payment is observed.
  if v_order.sales_invoice_id is not null then
    perform 1
      from public.sales_invoices invoice
     where invoice.id = v_order.sales_invoice_id
       and invoice.tenant_id = v_tenant_id;
    if not found then
      raise exception 'Linked sales invoice is missing or belongs to another tenant: %',
        v_order.sales_invoice_id
        using errcode = '23503';
    end if;

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

      perform 1
        from public.sales_invoices
       where id = v_order.sales_invoice_id
         and tenant_id = v_tenant_id
         and status != 'paid';

      if found then
        update public.sales_invoices
           set status = 'paid',
               paid_amount = total,
               balance = 0,
               updated_at = now()
         where id = v_order.sales_invoice_id
           and tenant_id = v_tenant_id;

        if not exists (
          select 1
            from public.sales_payments
           where invoice_id = v_order.sales_invoice_id
             and tenant_id = v_tenant_id
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
            (
              select invoice_number
                from public.sales_invoices
               where id = v_order.sales_invoice_id
                 and tenant_id = v_tenant_id
            ),
            v_payment_method.id,
            v_order.total,
            coalesce(v_order.paid_at, now()),
            v_order.payment_reference,
            'Pago automático - Pedido online #' || v_order.order_number
              || ' (' || coalesce(v_payment_method.name, v_order.payment_method)
              || ')'
          );
        end if;
      end if;
    end if;

    return v_order.sales_invoice_id;
  end if;

  -- Shipping/discount do not yet have immutable tax classifications. Current
  -- public checkout creates both as zero; any other value must be reviewed
  -- instead of inventing its IVA treatment.
  if coalesce(v_order.shipping_cost, 0) <> 0
     or coalesce(v_order.discount_amount, 0) <> 0 then
    raise exception 'Online order shipping or discount lacks an immutable tax classification'
      using errcode = '23514';
  end if;

  v_tax_snapshot := public.calculate_online_order_tax_snapshot(
    p_order_id,
    v_tenant_id
  );
  v_gross_amount := (v_tax_snapshot->>'gross_amount')::numeric;
  v_net_amount := (v_tax_snapshot->>'net_amount')::numeric;
  v_iva_amount := (v_tax_snapshot->>'tax_amount')::numeric;
  v_tax_treatment := v_tax_snapshot->>'tax_treatment';
  v_items := v_tax_snapshot->'items';

  -- Do not silently repair or reclassify historical rows. A mismatched pending
  -- order is stopped for review before invoice, stock, or journal effects.
  if v_order.total is distinct from v_gross_amount
     or v_order.subtotal is distinct from v_net_amount
     or v_order.tax_amount is distinct from v_iva_amount then
    raise exception 'Online order monetary snapshot does not reconcile to its item tax snapshots'
      using errcode = '23514';
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

  if v_order.payment_status = 'paid' then
    v_invoice_status := 'paid';
    v_should_create_payment := true;
  elsif lower(v_order.payment_method) = 'mercadopago'
        and v_order.payment_status = 'pending' then
    v_invoice_status := 'confirmed';
    v_should_create_payment := false;
  else
    v_invoice_status := 'sent';
    v_should_create_payment := false;
  end if;

  v_invoice_date := case
    when v_order.payment_status = 'paid' then
      coalesce(v_order.paid_at, v_order.created_at, now())
    else coalesce(v_order.created_at, now())
  end;
  v_year := to_char(v_invoice_date, 'YY');

  perform pg_advisory_xact_lock(hashtextextended(
    'online_order_invoice_number:' || v_tenant_id::text || ':' || v_year,
    0
  ));
  select coalesce(
    max(cast(substring(invoice_number from '\d+$') as integer)),
    0
  ) + 1
    into v_next_number
    from public.sales_invoices
   where tenant_id = v_tenant_id
     and invoice_number ~ ('^INV-' || v_year || '-\d+$');

  v_invoice_number := 'INV-' || v_year || '-'
    || lpad(
      v_next_number::text,
      greatest(5, length(v_next_number::text)),
      '0'
    );

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
    v_gross_amount,
    v_iva_amount,
    v_order.total,
    case when v_should_create_payment then v_order.total else 0 end,
    case when v_should_create_payment then 0 else v_order.total end,
    v_items,
    'Pedido online #' || v_order.order_number || case
      when v_order.delivery_type = 'pickup' then ' (Retiro en tienda)'
      else ' (Envío)'
    end,
    'ecommerce'
  ) returning id into v_invoice_id;

  if v_invoice_status in ('paid', 'confirmed') then
    declare
      v_invoice_record public.sales_invoices%rowtype;
    begin
      select * into v_invoice_record
        from public.sales_invoices
       where id = v_invoice_id
         and tenant_id = v_tenant_id;
      perform public.consume_sales_invoice_inventory(v_invoice_record);
      perform public.create_sales_invoice_journal_entry(v_invoice_record);
    end;
  end if;

  update public.online_orders
     set sales_invoice_id = v_invoice_id,
         status = case
           when status = 'pending' then 'confirmed'
           else status
         end
   where id = p_order_id
     and tenant_id = v_tenant_id;

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
      'Pago automático - Pedido online #' || v_order.order_number
        || ' (' || coalesce(v_payment_method.name, v_order.payment_method) || ')'
    );
  end if;

  return v_invoice_id;
end;
$$;

revoke all on function public.process_online_order_internal(uuid)
  from public, anon, authenticated, service_role;

-- Confirmation receives each immutable line classification so its net/IVA
-- presentation can use the same snapshot as checkout and invoicing. The
-- existing access-token authorization and explicit PII allowlist are retained.
create or replace function public.get_public_online_order_by_access_token(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_access public.online_order_access_tokens%rowtype;
  v_order public.online_orders%rowtype;
  v_items jsonb;
begin
  if length(coalesce(p_token, '')) < 40 or length(p_token) > 128 then
    return null;
  end if;

  select access.*
    into v_access
    from public.online_order_access_tokens access
   where access.token_sha256 = encode(
     extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
     'hex'
   )
     and access.revoked_at is null
     and access.expires_at > clock_timestamp()
     and access.scopes @> array['view_order']::text[]
   for update;

  if not found then
    return null;
  end if;

  select orders.*
    into v_order
    from public.online_orders orders
   where orders.id = v_access.order_id
     and orders.tenant_id = v_access.tenant_id;

  if not found then
    return null;
  end if;

  update public.online_order_access_tokens access
     set last_used_at = clock_timestamp(),
         use_count = access.use_count + 1
   where access.id = v_access.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal,
    'taxRate', case when item.tax_rate = 0.19 then 19 else item.tax_rate end
  ) order by item.created_at, item.id), '[]'::jsonb)
    into v_items
    from public.online_order_items item
   where item.order_id = v_order.id
     and item.tenant_id = v_order.tenant_id;

  return jsonb_build_object(
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', v_order.id,
      'number', v_order.order_number,
      'status', v_order.status,
      'paymentStatus', v_order.payment_status,
      'paymentMethod', v_order.payment_method,
      'deliveryType', v_order.delivery_type,
      'createdAt', v_order.created_at,
      'updatedAt', v_order.updated_at,
      'readyForPickupAt', v_order.ready_for_pickup_at,
      'shippedAt', v_order.shipped_at,
      'deliveredAt', v_order.delivered_at,
      'cancelledAt', v_order.cancelled_at,
      'trackingCarrier', v_order.shipping_carrier,
      'trackingNumber', v_order.tracking_number,
      'trackingUrl', case
        when v_order.tracking_url ~* '^https://[^[:space:]]+$'
          then v_order.tracking_url
        else null
      end,
      'subtotal', v_order.subtotal,
      'taxAmount', v_order.tax_amount,
      'shippingCost', v_order.shipping_cost,
      'discountAmount', v_order.discount_amount,
      'total', v_order.total
    )),
    'items', v_items,
    'access', jsonb_build_object(
      'scopes', v_access.scopes,
      'expiresAt', v_access.expires_at
    )
  );
end;
$$;

revoke all on function public.get_public_online_order_by_access_token(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_online_order_by_access_token(text)
  to anon, authenticated, service_role;

comment on function public.get_public_online_order_by_access_token(text) is
  'Token-authorized redacted online-order projection, including immutable public line tax classification for deterministic confirmation totals.';

commit;
