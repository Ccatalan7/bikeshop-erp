-- Forward migration only. Do not use this file for historical repairs.
--
-- Purpose:
--   * make public checkout consume the same canonical price/stock truth exposed
--     by the storefront;
--   * preserve prospective line-level cost/tax/service snapshots;
--   * serialize tenant/year WEB order numbering;
--   * expose one optimistic, replay-safe operational transition command;
--   * append immutable creation/payment/status/note receipts;
--   * close authenticated direct mutation of protected order fields/items; and
--   * prevent invoice SKU fallback from crossing a tenant boundary.
--
-- This migration intentionally performs no historical COGS, tax, stock, order,
-- invoice, payment, or journal backfill.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

alter table public.online_orders
  add column if not exists version bigint not null default 0,
  add column if not exists updated_by uuid;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.online_orders'::regclass
       and conname = 'online_orders_updated_by_fkey'
  ) then
    alter table public.online_orders
      add constraint online_orders_updated_by_fkey
      foreign key (updated_by) references auth.users(id) on delete set null;
  end if;
end $$;

alter table public.online_order_items
  add column if not exists unit_cost numeric(12,2),
  add column if not exists tax_rate numeric(5,2),
  add column if not exists is_service boolean,
  add column if not exists purchase_treatment text,
  add column if not exists product_type text;

comment on column public.online_order_items.unit_cost is
  'Immutable-at-checkout unit cost snapshot for prospective COGS. Null means no trustworthy historical snapshot exists.';
comment on column public.online_order_items.tax_rate is
  'Product tax-rate snapshot captured at checkout; it does not by itself select invoice tax treatment.';
comment on column public.online_order_items.is_service is
  'Service classification snapshot captured at checkout.';
comment on column public.online_order_items.purchase_treatment is
  'Inventory/workshop-consumable classification snapshot captured at checkout.';
comment on column public.online_order_items.product_type is
  'Product/service type snapshot captured at checkout.';

create table if not exists public.online_order_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null references public.online_orders(id) on delete restrict,
  event_type text not null check (event_type in (
    'order_created',
    'status_transition',
    'payment_transition',
    'internal_note_updated'
  )),
  from_status text,
  to_status text,
  from_payment_status text,
  to_payment_status text,
  changed boolean not null,
  expected_version bigint,
  result_version bigint not null,
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null,
  request_snapshot jsonb not null,
  response_snapshot jsonb not null,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  check (jsonb_typeof(request_snapshot) = 'object'),
  check (jsonb_typeof(response_snapshot) = 'object'),
  check (
    (event_type = 'status_transition' and to_status is not null)
    or (event_type = 'payment_transition' and to_payment_status is not null)
    or event_type in ('order_created', 'internal_note_updated')
  )
);

create index if not exists idx_online_order_events_order
  on public.online_order_events(
    tenant_id, order_id, occurred_at desc, id desc
  );

alter table public.online_order_events enable row level security;

drop policy if exists online_order_events_select
  on public.online_order_events;
create policy online_order_events_select
  on public.online_order_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.online_order_events
  from public, anon, authenticated, service_role;
grant select on public.online_order_events to authenticated;

create or replace function public.prevent_online_order_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Online order events are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_online_order_event_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_order_events_immutable
  on public.online_order_events;
create trigger trg_online_order_events_immutable
  before update or delete on public.online_order_events
  for each row execute function public.prevent_online_order_event_mutation();

create or replace function public.stamp_online_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.version := old.version + 1;
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end;
$$;

revoke all on function public.stamp_online_order_update()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_stamp_online_order_update
  on public.online_orders;
create trigger trg_stamp_online_order_update
  before update on public.online_orders
  for each row execute function public.stamp_online_order_update();

create or replace function public.capture_online_order_transition_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_key text;
  v_request jsonb;
  v_response jsonb;
begin
  if old.status is distinct from new.status then
    v_operation_key := nullif(
      current_setting('app.online_order_operation_key', true),
      ''
    );
    v_operation_key := coalesce(
      v_operation_key,
      'system:status:' || new.id::text || ':' || new.version::text || ':'
        || gen_random_uuid()::text
    );

    v_request := coalesce(
      nullif(current_setting('app.online_order_request_snapshot', true), '')::jsonb,
      jsonb_build_object(
        'source', 'database_trigger',
        'from_status', old.status,
        'to_status', new.status
      )
    );
    v_response := jsonb_build_object(
      'success', true,
      'order_id', new.id,
      'old_status', old.status,
      'new_status', new.status,
      'status', new.status,
      'payment_status', new.payment_status,
      'version', new.version,
      'invoice_id', new.sales_invoice_id,
      'changed', true
    );

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
    ) values (
      new.tenant_id,
      new.id,
      'status_transition',
      old.status,
      new.status,
      old.payment_status,
      new.payment_status,
      true,
      old.version,
      new.version,
      new.updated_by,
      v_operation_key,
      v_request,
      v_response
    );
  end if;

  if old.payment_status is distinct from new.payment_status then
    v_operation_key := 'system:payment:' || new.id::text || ':'
      || new.version::text || ':'
      || md5(concat_ws(
        ':',
        coalesce(old.payment_status, ''),
        coalesce(new.payment_status, ''),
        coalesce(new.payment_reference, '')
      ));
    v_request := jsonb_build_object(
      'source', 'database_trigger',
      'from_payment_status', old.payment_status,
      'to_payment_status', new.payment_status,
      'payment_method', new.payment_method,
      'payment_reference', new.payment_reference
    );
    v_response := jsonb_build_object(
      'success', true,
      'order_id', new.id,
      'status', new.status,
      'old_payment_status', old.payment_status,
      'new_payment_status', new.payment_status,
      'payment_status', new.payment_status,
      'version', new.version,
      'invoice_id', new.sales_invoice_id,
      'changed', true
    );

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
    ) values (
      new.tenant_id,
      new.id,
      'payment_transition',
      old.status,
      new.status,
      old.payment_status,
      new.payment_status,
      true,
      old.version,
      new.version,
      new.updated_by,
      v_operation_key,
      v_request,
      v_response
    );
  end if;

  return new;
end;
$$;

revoke all on function public.capture_online_order_transition_event()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_capture_online_order_transition_event
  on public.online_orders;
create trigger trg_capture_online_order_transition_event
  after update of status, payment_status on public.online_orders
  for each row execute function public.capture_online_order_transition_event();

create or replace function public.generate_online_order_number(
  p_tenant_id uuid,
  p_at timestamptz default clock_timestamp()
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year text;
  v_next bigint;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants tenant where tenant.id = p_tenant_id
  ) then
    raise exception 'A valid tenant is required to generate an online order number'
      using errcode = '23503';
  end if;

  v_year := to_char(coalesce(p_at, clock_timestamp()), 'YY');
  perform pg_advisory_xact_lock(
    hashtextextended(
      'online_order_number:' || p_tenant_id::text || ':' || v_year,
      0
    )
  );

  select coalesce(max(
    substring(order_number from ('^WEB-' || v_year || '-([0-9]+)$'))::bigint
  ), 0) + 1
    into v_next
    from public.online_orders
   where tenant_id = p_tenant_id
     and order_number ~ ('^WEB-' || v_year || '-[0-9]+$');

  return 'WEB-' || v_year || '-' || lpad(
    v_next::text,
    greatest(5, length(v_next::text)),
    '0'
  );
end;
$$;

create or replace function public.generate_online_order_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if v_tenant_id is null then
    raise exception 'Tenant context is required to generate an online order number'
      using errcode = '42501';
  end if;
  return public.generate_online_order_number(v_tenant_id, clock_timestamp());
end;
$$;

revoke all on function public.generate_online_order_number(uuid, timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function public.generate_online_order_number()
  from public, anon, authenticated, service_role;

create or replace function public.auto_generate_order_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.order_number is null or btrim(new.order_number) = '' then
    new.order_number := public.generate_online_order_number(
      new.tenant_id,
      coalesce(new.created_at, clock_timestamp())
    );
  end if;
  return new;
end;
$$;

revoke all on function public.auto_generate_order_number()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_auto_generate_order_number on public.online_orders;
create trigger trg_auto_generate_order_number
  before insert on public.online_orders
  for each row execute function public.auto_generate_order_number();

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
  v_total numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_tax_amount numeric(12,2) := 0;
  v_customer_id_text text;
  v_checkout_key text;
  v_created_response jsonb;
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

    v_unit_price := round(coalesce(v_product.public_price, 0)::numeric, 2);
    v_line_total := round(v_unit_price * v_quantity, 2);
    if v_unit_price <= 0 or v_line_total <= 0 then
      raise exception 'Invalid price for product %', v_product.name;
    end if;

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
      v_product.tax_rate,
      (
        coalesce(v_product.is_service, false)
        or v_product.product_type = 'service'
      ),
      coalesce(v_product.purchase_treatment, 'inventory'),
      coalesce(v_product.product_type, 'product')
    );

    v_total := v_total + v_line_total;
  end loop;

  if v_total <= 0 then
    raise exception 'Invalid order total';
  end if;

  -- Existing tax treatment is preserved here. The per-line tax snapshot above
  -- makes a later fiscal correction possible without inventing product history.
  if v_payment_method = 'mercadopago' then
    v_subtotal := round(v_total / 1.19, 2);
    v_tax_amount := round(v_total - v_subtotal, 2);
  else
    v_subtotal := v_total;
    v_tax_amount := 0;
  end if;

  update public.online_orders
     set subtotal = v_subtotal,
         tax_amount = v_tax_amount,
         shipping_cost = 0,
         discount_amount = 0,
         total = v_total
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
      'item_count', jsonb_array_length(p_order_items)
    ),
    v_created_response
  from public.online_orders orders
  where orders.id = v_order_id
    and orders.tenant_id = v_tenant_id;

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

revoke all on function public.create_public_online_order_unkeyed(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- Keep the deployed processing flow and trace triggers intact, but carry the
-- trusted checkout snapshots into the invoice JSON consumed by COGS/inventory.
-- IMPORTANT RESIDUAL: tax_treatment below still follows the historical
-- payment-method heuristic. Mercado Pago evidence can support a boleta, while
-- a bank transfer is not itself a fiscal document. Correct SII document/tax
-- classification needs a separate explicit fiscal contract and is not changed
-- or backfilled by this migration.
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

  -- Existing invoice-number semantics are retained, but concurrent processors
  -- for the same tenant/year now serialize before reading MAX.
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

  select jsonb_agg(
    jsonb_build_object(
      'product_id', item.product_id,
      'product_name', item.product_name,
      'product_sku', item.product_sku,
      'quantity', item.quantity,
      'price', item.unit_price,
      'subtotal', item.subtotal,
      'cost', item.unit_cost,
      'tax_rate', item.tax_rate,
      'is_service', item.is_service,
      'purchase_treatment', item.purchase_treatment,
      'product_type', item.product_type
    ) order by item.created_at, item.id
  )
    into v_items
    from public.online_order_items item
   where item.order_id = p_order_id
     and item.tenant_id = v_tenant_id;

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

create or replace function public.transition_online_order_status(
  p_order_id uuid,
  p_new_status text,
  p_expected_version bigint,
  p_operation_key text,
  p_tracking_number text default null,
  p_tracking_url text default null,
  p_carrier text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_target text := lower(btrim(coalesce(p_new_status, '')));
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_order public.online_orders%rowtype;
  v_updated public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_event public.online_order_events%rowtype;
  v_request jsonb;
  v_response jsonb;
  v_now timestamptz;
  v_tracking_number text := nullif(btrim(coalesce(p_tracking_number, '')), '');
  v_tracking_url text := nullif(btrim(coalesce(p_tracking_url, '')), '');
  v_carrier text := nullif(btrim(coalesce(p_carrier, '')), '');
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;
  if p_order_id is null or v_target = '' then
    raise exception 'Order and target status are required'
      using errcode = '22004';
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    raise exception 'Expected order version is required'
      using errcode = '22023';
  end if;
  if v_operation_key = '' or length(v_operation_key) > 160 then
    raise exception 'A valid operation key is required'
      using errcode = '22023';
  end if;
  if v_target not in (
    'pending',
    'confirmed',
    'processing',
    'ready_for_pickup',
    'shipped',
    'delivered',
    'cancelled'
  ) then
    raise exception 'Invalid status: %', v_target
      using errcode = '23514';
  end if;

  v_request := jsonb_build_object(
    'source', 'transition_online_order_status',
    'order_id', p_order_id,
    'target_status', v_target,
    'expected_version', p_expected_version,
    'tracking_number', v_tracking_number,
    'tracking_url', v_tracking_url,
    'carrier', v_carrier,
    'notes', nullif(btrim(coalesce(p_notes, '')), '')
  );

  -- Authorize before exposing a replay receipt.
  perform 1
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;

  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_tenant_id
     and event.operation_key = v_operation_key;
  if found then
    if v_event.order_id is distinct from p_order_id
       or v_event.event_type <> 'status_transition'
       or v_event.to_status is distinct from v_target
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'Operation key already belongs to another order transition'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;

  -- Re-check after waiting on the order lock.
  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_tenant_id
     and event.operation_key = v_operation_key;
  if found then
    if v_event.order_id is distinct from p_order_id
       or v_event.event_type <> 'status_transition'
       or v_event.to_status is distinct from v_target
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'Operation key already belongs to another order transition'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  if v_order.version <> p_expected_version then
    raise exception 'Order changed concurrently; expected version %, current version %',
      p_expected_version,
      v_order.version
      using errcode = '40001';
  end if;

  if v_order.status = v_target then
    v_response := jsonb_build_object(
      'success', true,
      'order_id', v_order.id,
      'old_status', v_order.status,
      'new_status', v_order.status,
      'status', v_order.status,
      'payment_status', v_order.payment_status,
      'version', v_order.version,
      'invoice_id', v_order.sales_invoice_id,
      'changed', false
    );
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
    ) values (
      v_order.tenant_id,
      v_order.id,
      'status_transition',
      v_order.status,
      v_order.status,
      v_order.payment_status,
      v_order.payment_status,
      false,
      p_expected_version,
      v_order.version,
      v_actor_id,
      v_operation_key,
      v_request,
      v_response
    ) returning * into v_event;

    return to_jsonb(v_event)
      || v_response
      || jsonb_build_object('replay', false);
  end if;

  if not (
    (v_order.status = 'pending' and v_target in ('confirmed', 'cancelled'))
    or (v_order.status = 'confirmed' and v_target in ('processing', 'cancelled'))
    or (
      v_order.status = 'processing'
      and v_target in ('ready_for_pickup', 'shipped', 'cancelled')
    )
    or (v_order.status = 'ready_for_pickup' and v_target = 'delivered')
    or (v_order.status = 'shipped' and v_target = 'delivered')
  ) then
    raise exception 'Invalid online order transition: % -> %',
      v_order.status,
      v_target
      using errcode = '23514';
  end if;

  if v_target = 'confirmed' and v_order.sales_invoice_id is null then
    if v_order.payment_status <> 'paid' then
      raise exception 'Cannot confirm an order without a linked invoice or verified payment'
        using errcode = '23514';
    end if;
  end if;

  if v_target in ('processing', 'ready_for_pickup', 'shipped', 'delivered') then
    if v_order.payment_status <> 'paid'
       or v_order.sales_invoice_id is null then
      raise exception 'Paid order and linked invoice are required before fulfillment'
        using errcode = '23514';
    end if;

    select invoice.* into v_invoice
      from public.sales_invoices invoice
     where invoice.id = v_order.sales_invoice_id
       and invoice.tenant_id = v_order.tenant_id
     for share;
    if not found
       or lower(coalesce(v_invoice.status, '')) not in ('paid', 'pagado', 'pagada')
       or coalesce(v_invoice.balance, v_invoice.total, 0) <> 0 then
      raise exception 'Linked invoice must be fully settled before fulfillment'
        using errcode = '23514';
    end if;
  end if;

  if v_target = 'ready_for_pickup' and v_order.delivery_type <> 'pickup' then
    raise exception 'Only pickup orders can become ready_for_pickup'
      using errcode = '23514';
  end if;
  if v_target = 'shipped' then
    if v_order.delivery_type <> 'shipping' then
      raise exception 'Only shipping orders can become shipped'
        using errcode = '23514';
    end if;
    if coalesce(
      v_tracking_number,
      v_tracking_url,
      v_carrier,
      nullif(btrim(coalesce(v_order.tracking_number, '')), ''),
      nullif(btrim(coalesce(v_order.tracking_url, '')), ''),
      nullif(btrim(coalesce(v_order.shipping_carrier, '')), '')
    ) is null then
      raise exception 'Shipping evidence requires tracking or carrier information'
        using errcode = '23514';
    end if;
  end if;
  if v_target = 'delivered'
     and (
       (v_order.delivery_type = 'pickup' and v_order.status <> 'ready_for_pickup')
       or (v_order.delivery_type = 'shipping' and v_order.status <> 'shipped')
     ) then
    raise exception 'Delivery must follow the correct pickup or shipping milestone'
      using errcode = '23514';
  end if;
  if v_target = 'cancelled'
     and nullif(btrim(coalesce(p_notes, '')), '') is null then
    raise exception 'Cancellation reason is required'
      using errcode = '23514';
  end if;

  perform set_config('app.online_order_operation_key', v_operation_key, true);
  perform set_config(
    'app.online_order_request_snapshot',
    v_request::text,
    true
  );

  if v_target = 'confirmed' and v_order.sales_invoice_id is null then
    perform public.process_online_order(v_order.id);
  elsif v_target = 'cancelled' then
    perform public.cancel_online_order(v_order.id, p_notes, 0);
  else
    v_now := clock_timestamp();
    update public.online_orders orders
       set status = v_target,
           ready_for_pickup_at = case
             when v_target = 'ready_for_pickup'
               then coalesce(orders.ready_for_pickup_at, v_now)
             else orders.ready_for_pickup_at
           end,
           shipped_at = case
             when v_target = 'shipped'
               then coalesce(orders.shipped_at, v_now)
             else orders.shipped_at
           end,
           delivered_at = case
             when v_target = 'delivered'
               then coalesce(orders.delivered_at, v_now)
             else orders.delivered_at
           end,
           tracking_number = case
             when v_target = 'shipped'
               then coalesce(v_tracking_number, orders.tracking_number)
             else orders.tracking_number
           end,
           tracking_url = case
             when v_target = 'shipped'
               then coalesce(v_tracking_url, orders.tracking_url)
             else orders.tracking_url
           end,
           shipping_carrier = case
             when v_target = 'shipped'
               then coalesce(v_carrier, orders.shipping_carrier)
             else orders.shipping_carrier
           end,
           notes = coalesce(nullif(btrim(coalesce(p_notes, '')), ''), orders.notes)
     where orders.id = v_order.id
       and orders.tenant_id = v_order.tenant_id;
  end if;

  select orders.* into v_updated
    from public.online_orders orders
   where orders.id = v_order.id
     and orders.tenant_id = v_order.tenant_id;

  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_order.tenant_id
     and event.operation_key = v_operation_key;
  if not found then
    raise exception 'Online order transition did not append its receipt'
      using errcode = '55000';
  end if;

  perform set_config('app.online_order_operation_key', '', true);
  perform set_config('app.online_order_request_snapshot', '', true);

  return to_jsonb(v_event)
    || v_event.response_snapshot
    || jsonb_build_object('replay', false);
exception
  when others then
    perform set_config('app.online_order_operation_key', '', true);
    perform set_config('app.online_order_request_snapshot', '', true);
    raise;
end;
$$;

revoke all on function public.transition_online_order_status(
  uuid, text, bigint, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.transition_online_order_status(
  uuid, text, bigint, text, text, text, text, text
) to authenticated;

comment on function public.transition_online_order_status(
  uuid, text, bigint, text, text, text, text, text
) is
  'Canonical optimistic and replay-safe online-order lifecycle command with explicit forward transitions, financial prerequisites, server timestamps, actor stamping, and immutable receipts.';

create or replace function public.update_online_order_status(
  p_order_id uuid,
  p_new_status text,
  p_tracking_number text default null,
  p_tracking_url text default null,
  p_carrier text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_version bigint;
  v_operation_key text;
  v_event public.online_order_events%rowtype;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;

  v_operation_key := 'legacy-order-status:' || md5(jsonb_build_object(
    'actor_id', v_actor_id,
    'order_id', p_order_id,
    'status', lower(btrim(coalesce(p_new_status, ''))),
    'tracking_number', nullif(btrim(coalesce(p_tracking_number, '')), ''),
    'tracking_url', nullif(btrim(coalesce(p_tracking_url, '')), ''),
    'carrier', nullif(btrim(coalesce(p_carrier, '')), ''),
    'notes', nullif(btrim(coalesce(p_notes, '')), '')
  )::text);

  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_tenant_id
     and event.operation_key = v_operation_key;
  if found then
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select orders.version into v_version
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;

  return public.transition_online_order_status(
    p_order_id,
    p_new_status,
    v_version,
    v_operation_key,
    p_tracking_number,
    p_tracking_url,
    p_carrier,
    p_notes
  );
end;
$$;

revoke all on function public.update_online_order_status(
  uuid, text, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.update_online_order_status(
  uuid, text, text, text, text, text
) to authenticated;

create or replace function public.update_online_order_internal_notes(
  p_order_id uuid,
  p_internal_notes text,
  p_expected_version bigint default null,
  p_operation_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := coalesce(
    nullif(btrim(coalesce(p_operation_key, '')), ''),
    'online-order-note:' || gen_random_uuid()::text
  );
  v_order public.online_orders%rowtype;
  v_updated public.online_orders%rowtype;
  v_event public.online_order_events%rowtype;
  v_request jsonb;
  v_response jsonb;
  v_changed boolean;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;
  if p_order_id is null then
    raise exception 'Order is required' using errcode = '22004';
  end if;
  if length(coalesce(p_internal_notes, '')) > 4000 then
    raise exception 'Internal notes exceed 4000 characters'
      using errcode = '22023';
  end if;
  if length(v_operation_key) > 160 then
    raise exception 'Operation key is too long' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'source', 'update_online_order_internal_notes',
    'order_id', p_order_id,
    'internal_notes', p_internal_notes,
    'expected_version', p_expected_version
  );

  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_tenant_id
     and event.operation_key = v_operation_key;
  if found then
    if v_event.order_id is distinct from p_order_id
       or v_event.event_type <> 'internal_note_updated'
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'Operation key already belongs to another note update'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;
  if p_expected_version is not null
     and v_order.version <> p_expected_version then
    raise exception 'Order changed concurrently; expected version %, current version %',
      p_expected_version,
      v_order.version
      using errcode = '40001';
  end if;

  v_changed := v_order.internal_notes is distinct from p_internal_notes;
  if v_changed then
    update public.online_orders orders
       set internal_notes = p_internal_notes
     where orders.id = v_order.id
       and orders.tenant_id = v_order.tenant_id
     returning orders.* into v_updated;
  else
    v_updated := v_order;
  end if;

  v_response := jsonb_build_object(
    'success', true,
    'order_id', v_updated.id,
    'status', v_updated.status,
    'payment_status', v_updated.payment_status,
    'version', v_updated.version,
    'invoice_id', v_updated.sales_invoice_id,
    'changed', v_changed
  );

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
  ) values (
    v_order.tenant_id,
    v_order.id,
    'internal_note_updated',
    v_order.status,
    v_updated.status,
    v_order.payment_status,
    v_updated.payment_status,
    v_changed,
    p_expected_version,
    v_updated.version,
    v_actor_id,
    v_operation_key,
    v_request,
    v_response
  ) returning * into v_event;

  return to_jsonb(v_event)
    || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.update_online_order_internal_notes(
  uuid, text, bigint, text
) from public, anon, authenticated, service_role;
grant execute on function public.update_online_order_internal_notes(
  uuid, text, bigint, text
) to authenticated;

-- Cancellation remains the accounting/inventory kernel invoked by the
-- canonical optimistic transition command. Interactive users cannot bypass
-- expected_version and operation_key by calling it directly; service-role
-- integrations retain the explicit low-level escape hatch.
revoke all on function public.cancel_online_order(uuid, text, numeric)
  from public, anon, authenticated, service_role;
grant execute on function public.cancel_online_order(uuid, text, numeric)
  to service_role;

-- Direct rows can no longer bypass canonical checkout, snapshots, totals, or
-- lifecycle receipts. Trusted checkout/provider/manual/cancellation/processing
-- functions remain SECURITY DEFINER and continue through the trace kernel.
drop policy if exists "online_orders_insert" on public.online_orders;
drop policy if exists "online_orders_update" on public.online_orders;
revoke insert, update on public.online_orders from public, anon, authenticated;

drop policy if exists "online_order_items_insert" on public.online_order_items;
drop policy if exists "online_order_items_update" on public.online_order_items;
drop policy if exists "online_order_items_delete" on public.online_order_items;
revoke insert, update, delete on public.online_order_items
  from public, anon, authenticated;

create or replace function public.consume_sales_invoice_inventory(
  p_invoice public.sales_invoices
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_reference text;
  v_net_quantity integer;
  v_items_count integer;
  v_is_set boolean;
  v_component record;
  v_qty_to_deduct integer;
  v_set_name text;
begin
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  if p_invoice.id is null then
    return;
  end if;
  if p_invoice.tenant_id is null then
    raise exception 'Sales invoice tenant is required for inventory consumption'
      using errcode = '23503';
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  if v_status = any(array[
    'draft', 'borrador', 'cancelled', 'cancelado', 'cancelada',
    'anulado', 'anulada'
  ]) then
    return;
  end if;

  v_reference := concat('sales_invoice:', p_invoice.id::text);
  select coalesce(sum(quantity), 0)::integer
    into v_net_quantity
    from public.stock_movements
   where tenant_id = p_invoice.tenant_id
     and reference = v_reference;
  if v_net_quantity < 0 then
    return;
  end if;

  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;

  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      item->>'product_sku' as product_sku,
      coalesce(
        nullif(item->>'purchase_treatment', ''),
        'inventory'
      ) as purchase_treatment,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
  loop
    v_resolved_product_id := v_item.product_id;

    if v_resolved_product_id is not null and not exists (
      select 1
        from public.products product
       where product.id = v_resolved_product_id
         and product.tenant_id = p_invoice.tenant_id
    ) then
      if exists (
        select 1 from public.products product
         where product.id = v_resolved_product_id
      ) then
        raise exception 'Sales invoice product belongs to another tenant'
          using errcode = '42501';
      end if;
      v_resolved_product_id := null;
    end if;

    if v_resolved_product_id is null
       and nullif(v_item.product_sku, '') is not null then
      select product.id
        into v_resolved_product_id
        from public.products product
       where product.tenant_id = p_invoice.tenant_id
         and product.sku = v_item.product_sku
       limit 1;

      if not found then
        if exists (
          select 1
            from public.products product
           where product.sku = v_item.product_sku
             and product.tenant_id <> p_invoice.tenant_id
        ) then
          raise exception 'Sales invoice SKU belongs to another tenant'
            using errcode = '42501';
        end if;
      end if;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);
    if v_resolved_product_id is null or v_quantity_int <= 0 then
      continue;
    end if;
    if v_item.purchase_treatment = 'workshop_consumable' then
      continue;
    end if;

    select product.is_set, product.name
      into v_is_set, v_set_name
      from public.products product
     where product.id = v_resolved_product_id
       and product.tenant_id = p_invoice.tenant_id
       and coalesce(product.track_stock, true) = true;
    if not found then
      continue;
    end if;

    if v_is_set then
      for v_component in
        select
          component.component_product_id,
          component.quantity_in_set
        from public.product_set_components component
        where component.tenant_id = p_invoice.tenant_id
          and component.set_product_id = v_resolved_product_id
      loop
        v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;

        update public.products product
           set inventory_qty = coalesce(
                 product.stock_quantity,
                 product.inventory_qty,
                 0
               ) - v_qty_to_deduct,
               stock_quantity = coalesce(
                 product.stock_quantity,
                 product.inventory_qty,
                 0
               ) - v_qty_to_deduct,
               updated_at = now()
         where product.id = v_component.component_product_id
           and product.tenant_id = p_invoice.tenant_id;

        if not found then
          raise exception 'Sales invoice set component is outside the current tenant'
            using errcode = '42501';
        end if;

        insert into public.stock_movements (
          tenant_id,
          id,
          product_id,
          warehouse_id,
          type,
          movement_type,
          quantity,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) values (
          p_invoice.tenant_id,
          gen_random_uuid(),
          v_component.component_product_id,
          null,
          'OUT',
          'sales_invoice_component',
          -v_qty_to_deduct,
          v_reference,
          format(
            'Salida por venta de Set "%s" (Factura %s)',
            v_set_name,
            coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
          ),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      end loop;
    else
      update public.products product
         set inventory_qty = coalesce(
               product.stock_quantity,
               product.inventory_qty,
               0
             ) - v_quantity_int,
             stock_quantity = coalesce(
               product.stock_quantity,
               product.inventory_qty,
               0
             ) - v_quantity_int,
             updated_at = now()
       where product.id = v_resolved_product_id
         and product.tenant_id = p_invoice.tenant_id
         and coalesce(product.is_service, false) = false
         and coalesce(product.track_stock, true) = true;

      if found then
        insert into public.stock_movements (
          tenant_id,
          id,
          product_id,
          warehouse_id,
          type,
          movement_type,
          quantity,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) values (
          p_invoice.tenant_id,
          gen_random_uuid(),
          v_resolved_product_id,
          null,
          'OUT',
          'sale',
          -v_quantity_int,
          v_reference,
          concat(
            'Salida por venta (Factura ',
            coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text),
            ')'
          ),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.consume_sales_invoice_inventory(
  public.sales_invoices
) from public, anon, authenticated, service_role;

-- Public list/search/featured/category RPCs all funnel through this function.
-- Availability therefore uses stock_quantity as the canonical balance and
-- inventory_qty only as a legacy fallback when stock_quantity itself is null.
create or replace function public.get_public_products(
  p_tenant_id uuid,
  p_category_ids uuid[] default null,
  p_product_ids uuid[] default null,
  p_sku text default null,
  p_search_term text default null,
  p_product_type text default null,
  p_only_in_stock boolean default true,
  p_sort_by text default 'name',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  tenant_id uuid,
  name text,
  sku text,
  barcode text,
  price numeric,
  cost numeric,
  inventory_qty integer,
  stock_quantity integer,
  image_url text,
  image_url_optimized text,
  image_urls text[],
  description text,
  website_description text,
  category text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand text,
  model text,
  manufacturer text,
  manufacturer_sku text,
  gtin text,
  product_type text,
  track_stock boolean,
  is_active boolean,
  is_published boolean,
  show_on_website boolean,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language sql
security definer
set search_path = public
stable
as $$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      case lower(coalesce(
        nullif(trim(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_stock_policy'
          limit 1
        ), '')), ''),
        case when p_only_in_stock then 'available_only' else 'all' end
      ))
        when 'all' then 'all'
        when 'both' then 'all'
        when 'out_of_stock_only' then 'out_of_stock_only'
        when 'out_of_stock' then 'out_of_stock_only'
        when 'sin_stock' then 'out_of_stock_only'
        else 'available_only'
      end as stock_policy,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_image'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_image,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_require_visible_category'
          limit 1
        ), 'false')) in ('true', '1', 'yes', 'si', 'sí') as require_visible_category,
      lower(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_include_uncategorized'
          limit 1
        ), 'true')) in ('true', '1', 'yes', 'si', 'sí') as include_uncategorized
    from (
      select trim(
        regexp_replace(
          unaccent(lower(trim(coalesce(p_search_term, '')))),
          '[^a-z0-9]+',
          ' ',
          'g'
        )
      ) as term
    ) s
    cross join lateral (
      select array_agg(token) as tokens
      from regexp_split_to_table(s.term, '\s+') as token_parts(token)
      where token <> ''
    ) t
  ),
  normalized as (
    select
      p.*,
      a.term,
      a.tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_name, p.name))), '[^a-z0-9]+', ' ', 'g')) as name_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.sku, ''))), '[^a-z0-9]+', ' ', 'g')) as sku_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.barcode, ''))), '[^a-z0-9]+', ' ', 'g')) as barcode_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.gtin, ''))), '[^a-z0-9]+', ' ', 'g')) as gtin_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.category_name, p.category, ''))), '[^a-z0-9]+', ' ', 'g')) as category_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.brand, ''))), '[^a-z0-9]+', ' ', 'g')) as brand_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.model, ''))), '[^a-z0-9]+', ' ', 'g')) as model_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer, ''))), '[^a-z0-9]+', ' ', 'g')) as manufacturer_n,
      trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer_sku, ''))), '[^a-z0-9]+', ' ', 'g')) as manufacturer_sku_n,
      trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_description, p.description))), '[^a-z0-9]+', ' ', 'g')) as description_n
    from public.products p
    cross join args a
    where p.tenant_id = p_tenant_id
      and p.is_active = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
      and (
        p_product_ids is null
        or cardinality(p_product_ids) = 0
        or p.id = any(p_product_ids)
      )
      and (
        p_category_ids is null
        or cardinality(p_category_ids) = 0
        or p.category_id = any(p_category_ids)
      )
      and (
        a.wanted_sku is null
        or lower(p.sku) = lower(a.wanted_sku)
      )
      and (
        a.wanted_product_type is null
        or p.product_type = a.wanted_product_type
      )
      and (
        not a.require_image
        or nullif(btrim(coalesce(p.website_image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.website_image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        or nullif(btrim(coalesce(p.image_url, '')), '') is not null
        or nullif(btrim(coalesce(p.image_url_optimized, '')), '') is not null
        or cardinality(coalesce(p.image_urls, array[]::text[])) > 0
      )
      and (
        not a.require_visible_category
        or (p.category_id is null and a.include_uncategorized)
        or exists (
          select 1
          from public.product_categories pc
          where pc.id = p.category_id
            and pc.tenant_id = p_tenant_id
            and pc.is_active = true
            and coalesce(pc.show_on_website, false) = true
        )
      )
      and (
        a.stock_policy = 'all'
        or coalesce(p.is_service, false)
        or p.product_type = 'service'
        or (
          a.stock_policy = 'available_only'
          and (
            coalesce(p.track_stock, true) = false
            or coalesce(p.stock_quantity, p.inventory_qty, 0) > 0
          )
        )
        or (
          a.stock_policy = 'out_of_stock_only'
          and coalesce(p.track_stock, true) = true
          and coalesce(p.stock_quantity, p.inventory_qty, 0) <= 0
        )
      )
  ),
  enriched as (
    select
      n.*,
      trim(concat_ws(
        ' ',
        case
          when n.name_n like '%pinon%'
            or n.category_n in ('pinones', 'cassette')
            then 'pinon pinones cassette freewheel rueda libre coronas'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cadena%'
            then 'cadena chain transmision'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%camara%'
            then 'camara tubo tube valvula neumatico'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cubierta%'
            or concat_ws(' ', n.name_n, n.category_n) like '%neumatico%'
            then 'cubierta neumatico tire goma'
          else null
        end
      )) as alias_n
    from normalized n
  ),
  matched as (
    select
      e.*,
      (
        case when e.term <> '' and e.sku_n = e.term then 1000 else 0 end +
        case when e.term <> '' and e.barcode_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.gtin_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.name_n = e.term then 850 else 0 end +
        case when e.term <> '' and e.name_n like e.term || '%' then 760 else 0 end +
        case when e.term <> '' and e.name_n like '%' || e.term || '%' then 650 else 0 end +
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end
      ) as phrase_strong_score,
      coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.sku_n = token then 120
            when token ~ '^[0-9]+$' and e.barcode_n = token then 120
            when token ~ '^[0-9]+$' and e.gtin_n = token then 120
            when token ~ '^[0-9]+$' and e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 70
            when token ~ '^[0-9]+$' and e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 58
            when token ~ '^[0-9]+$' then 0
            when e.name_n like token || '%' then 95
            when e.name_n like '%' || token || '%' then 76
            when e.category_n like '%' || token || '%' then 66
            when e.alias_n like '%' || token || '%' then 56
            when e.sku_n like '%' || token || '%' then 54
            when e.manufacturer_sku_n like '%' || token || '%' then 48
            when e.brand_n like '%' || token || '%' then 42
            when e.model_n like '%' || token || '%' then 38
            when e.manufacturer_n like '%' || token || '%' then 34
            when length(token) >= 4 and greatest(
              word_similarity(token, e.name_n),
              word_similarity(token, e.category_n),
              word_similarity(token, e.brand_n),
              word_similarity(token, e.model_n),
              word_similarity(token, e.manufacturer_n),
              word_similarity(token, e.alias_n)
            ) >= case when length(token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) as token_strong_score,
      coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 8
            when token !~ '^[0-9]+$' and e.description_n like '%' || token || '%' then 8
            when token !~ '^[0-9]+$' and length(token) >= 5 and word_similarity(token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) as weak_description_score
    from enriched e
    where e.term = ''
      or not exists (
        select 1
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
          and not (
            (
              token ~ '^[0-9]+$'
              and (
                e.sku_n = token
                or e.barcode_n = token
                or e.gtin_n = token
                or e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
              )
            )
            or (
              token !~ '^[0-9]+$'
              and (
                e.name_n like '%' || token || '%'
                or e.category_n like '%' || token || '%'
                or e.alias_n like '%' || token || '%'
                or e.sku_n like '%' || token || '%'
                or e.barcode_n like '%' || token || '%'
                or e.gtin_n like '%' || token || '%'
                or e.brand_n like '%' || token || '%'
                or e.model_n like '%' || token || '%'
                or e.manufacturer_n like '%' || token || '%'
                or e.manufacturer_sku_n like '%' || token || '%'
                or e.description_n like '%' || token || '%'
                or (
                  length(token) >= 4
                  and greatest(
                    word_similarity(token, e.name_n),
                    word_similarity(token, e.category_n),
                    word_similarity(token, e.brand_n),
                    word_similarity(token, e.model_n),
                    word_similarity(token, e.manufacturer_n),
                    word_similarity(token, e.alias_n)
                  ) >= case when length(token) >= 5 then 0.56 else 0.72 end
                )
                or (
                  length(token) >= 5
                  and word_similarity(token, e.description_n) >= 0.86
                )
              )
            )
          )
      )
  ),
  scored as (
    select
      m.*,
      (m.phrase_strong_score + m.token_strong_score) as strong_score,
      (
        m.phrase_strong_score +
        m.token_strong_score +
        m.weak_description_score +
        case when m.product_type = 'service' and not m.service_intent
          then -260 else 0 end
      ) as search_score
    from matched m
  ),
  ranked as (
    select s.*
    from scored s
    where s.term = ''
      or s.product_type <> 'service'
      or s.service_intent
      or s.strong_score > 0
      or not exists (
        select 1
        from scored product_match
        where product_match.product_type <> 'service'
          and product_match.strong_score > 0
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from ranked p
  )
  select
    p.id,
    p.tenant_id,
    coalesce(nullif(btrim(p.website_name), ''), p.name) as name,
    p.sku,
    p.barcode,
    coalesce(p.website_price, p.price) as price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    coalesce(nullif(btrim(p.website_image_url), ''), p.image_url) as image_url,
    coalesce(nullif(btrim(p.website_image_url_optimized), ''), p.image_url_optimized) as image_url_optimized,
    case
      when cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        then p.website_image_urls
      else p.image_urls
    end as image_urls,
    p.description,
    p.website_description,
    p.category,
    p.category_id,
    p.category_name,
    p.brand_id,
    p.brand,
    p.model,
    p.manufacturer,
    p.manufacturer_sku,
    p.gtin,
    p.product_type,
    p.track_stock,
    p.is_active,
    p.is_published,
    p.show_on_website,
    p.created_at,
    p.updated_at,
    p.row_total as total_count
  from counted p
  order by
    case when p.term <> '' then p.search_score end desc nulls last,
    case when p.term = '' and p.sort_by = 'price_asc'
      then coalesce(p.website_price, p.price) end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc'
      then coalesce(p.website_price, p.price) end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest'
      then p.created_at end desc nulls last,
    coalesce(nullif(btrim(p.website_name), ''), p.name) asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$$;

revoke all on function public.get_public_products(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) from public;
grant execute on function public.get_public_products(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
