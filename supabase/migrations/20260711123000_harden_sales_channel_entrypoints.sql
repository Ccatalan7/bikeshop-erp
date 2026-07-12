-- Preventive sales-channel hardening. This migration does not rewrite or repair
-- any existing invoice, order, payment, stock movement, or journal entry.

begin;

alter table public.online_orders
  add column if not exists checkout_idempotency_key text,
  add column if not exists checkout_payload_hash text;

create unique index if not exists idx_online_orders_checkout_idempotency
  on public.online_orders(tenant_id, checkout_idempotency_key)
  where checkout_idempotency_key is not null;

comment on column public.online_orders.checkout_idempotency_key is
  'Client-generated checkout attempt key. Replays return the original order.';
comment on column public.online_orders.checkout_payload_hash is
  'Server-computed fingerprint used to reject reuse of a checkout key with different content.';

-- Preserve the already-deployed server-authoritative order creator as a private
-- implementation, then expose an idempotent wrapper under the public API name.
do $$
begin
  if to_regprocedure('public.create_public_online_order_unkeyed(jsonb,jsonb)') is null then
    alter function public.create_public_online_order(jsonb, jsonb)
      rename to create_public_online_order_unkeyed;
  end if;
end $$;

revoke all on function public.create_public_online_order_unkeyed(jsonb, jsonb)
  from public, anon, authenticated, service_role;

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
  v_checkout_key text;
  v_payload_hash text;
  v_existing_order record;
  v_order_id uuid;
  v_canonical_items jsonb;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload';
  end if;

  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array'
     or jsonb_array_length(p_order_items) = 0 then
    raise exception 'Order must include at least one item';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null then
    raise exception 'Invalid tenant_id';
  end if;

  v_checkout_key := nullif(btrim(coalesce(p_order_data->>'checkout_idempotency_key', '')), '');
  if v_checkout_key is not null and length(v_checkout_key) > 128 then
    raise exception 'Checkout idempotency key is too long';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'product_id', item.value->>'product_id',
        'quantity', item.value->>'quantity'
      )
      order by item.value->>'product_id', item.ordinality
    ),
    '[]'::jsonb
  )
  into v_canonical_items
  from jsonb_array_elements(p_order_items) with ordinality as item(value, ordinality);

  v_payload_hash := md5(jsonb_build_object(
    'tenant_id', v_tenant_id,
    'customer_id', nullif(p_order_data->>'customer_id', ''),
    'customer_email', lower(btrim(coalesce(p_order_data->>'customer_email', ''))),
    'customer_name', btrim(coalesce(p_order_data->>'customer_name', '')),
    'customer_phone', btrim(coalesce(p_order_data->>'customer_phone', '')),
    'customer_address', btrim(coalesce(p_order_data->>'customer_address', '')),
    'delivery_type', lower(btrim(coalesce(p_order_data->>'delivery_type', 'shipping'))),
    'payment_method', lower(btrim(coalesce(p_order_data->>'payment_method', 'transfer'))),
    'shipping_address_line1', btrim(coalesce(p_order_data->>'shipping_address_line1', '')),
    'shipping_address_line2', btrim(coalesce(p_order_data->>'shipping_address_line2', '')),
    'shipping_city', btrim(coalesce(p_order_data->>'shipping_city', '')),
    'shipping_state', btrim(coalesce(p_order_data->>'shipping_state', '')),
    'shipping_postal_code', btrim(coalesce(p_order_data->>'shipping_postal_code', '')),
    'shipping_country', btrim(coalesce(p_order_data->>'shipping_country', 'Chile')),
    'customer_notes', left(btrim(coalesce(p_order_data->>'customer_notes', '')), 1000),
    'items', v_canonical_items
  )::text);

  if v_checkout_key is not null then
    -- Serializes same-key checkouts without locking unrelated tenants/orders.
    perform pg_advisory_xact_lock(
      hashtextextended(v_tenant_id::text || ':' || v_checkout_key, 0)
    );

    select id, checkout_payload_hash
      into v_existing_order
      from public.online_orders
     where tenant_id = v_tenant_id
       and checkout_idempotency_key = v_checkout_key;

    if found then
      if v_existing_order.checkout_payload_hash is distinct from v_payload_hash then
        raise exception 'Checkout key was already used with different order content'
          using errcode = 'integrity_constraint_violation';
      end if;
      return v_existing_order.id;
    end if;
  end if;

  v_order_id := public.create_public_online_order_unkeyed(
    p_order_data - 'order_number' - 'subtotal' - 'tax_amount'
      - 'shipping_cost' - 'discount_amount' - 'total',
    p_order_items
  );

  update public.online_orders
     set checkout_idempotency_key = v_checkout_key,
         checkout_payload_hash = v_payload_hash,
         updated_at = now()
   where id = v_order_id
     and tenant_id = v_tenant_id;

  return v_order_id;
end;
$$;

revoke all on function public.create_public_online_order(jsonb, jsonb) from public;
grant execute on function public.create_public_online_order(jsonb, jsonb)
  to anon, authenticated, service_role;

-- Keep existing callers on the same function name while enforcing tenant
-- ownership before entering the original SECURITY DEFINER implementation.
do $$
begin
  if to_regprocedure('public.process_online_order_internal(uuid)') is null then
    alter function public.process_online_order(uuid)
      rename to process_online_order_internal;
  end if;
end $$;

revoke all on function public.process_online_order_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.process_online_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id
    from public.online_orders
   where id = p_order_id;

  if not found then
    raise exception 'Order not found: %', p_order_id;
  end if;

  if auth.uid() is not null
     and v_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = 'insufficient_privilege';
  end if;

  return public.process_online_order_internal(p_order_id);
end;
$$;

-- Durable provider-event evidence. One row records each provider payment/status
-- observation and connects it to the order, invoice, and invoice trace operation.
create table if not exists public.sales_channel_payment_events (
  id bigint generated by default as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  provider text not null,
  external_payment_id text not null,
  provider_status text not null,
  order_id uuid not null references public.online_orders(id) on delete restrict,
  invoice_id uuid references public.sales_invoices(id) on delete restrict,
  operation_id uuid references public.inventory_accounting_operations(id) on delete restrict,
  amount numeric(14,2),
  currency text,
  outcome text not null check (outcome in (
    'applied',
    'recorded_pending',
    'recorded_failed',
    'ignored_stale',
    'rejected_amount',
    'rejected_currency',
    'rejected_conflicting_payment'
  )),
  validation_error text,
  provider_payload jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, provider, external_payment_id, provider_status)
);

create index if not exists idx_sales_channel_payment_events_order
  on public.sales_channel_payment_events(tenant_id, order_id, created_at desc);
create index if not exists idx_sales_channel_payment_events_invoice
  on public.sales_channel_payment_events(tenant_id, invoice_id, created_at desc)
  where invoice_id is not null;

alter table public.sales_channel_payment_events enable row level security;

drop policy if exists sales_channel_payment_events_select
  on public.sales_channel_payment_events;
create policy sales_channel_payment_events_select
  on public.sales_channel_payment_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.sales_channel_payment_events from public, anon, authenticated;
grant select on public.sales_channel_payment_events to authenticated;

create or replace function public.prevent_sales_channel_payment_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Sales channel payment events are append-only'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_sales_channel_payment_events_immutable
  on public.sales_channel_payment_events;
create trigger trg_sales_channel_payment_events_immutable
  before update or delete on public.sales_channel_payment_events
  for each row execute function public.prevent_sales_channel_payment_event_mutation();

create or replace function public.apply_mercadopago_payment_event(
  p_order_id uuid,
  p_tenant_id uuid,
  p_payment_id text,
  p_provider_status text,
  p_amount numeric,
  p_currency text,
  p_paid_at timestamp with time zone default null,
  p_provider_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.online_orders%rowtype;
  v_existing_event public.sales_channel_payment_events%rowtype;
  v_status text := lower(btrim(coalesce(p_provider_status, '')));
  v_currency text := upper(btrim(coalesce(p_currency, '')));
  v_payment_id text := btrim(coalesce(p_payment_id, ''));
  v_outcome text;
  v_error text;
  v_invoice_id uuid;
  v_operation_id uuid;
  v_payment_status text;
begin
  if p_order_id is null or p_tenant_id is null or v_payment_id = '' or v_status = '' then
    raise exception 'MercadoPago event is missing required identifiers';
  end if;

  select * into v_order
    from public.online_orders
   where id = p_order_id
     and tenant_id = p_tenant_id
   for update;

  if not found then
    raise exception 'Online order not found for MercadoPago event';
  end if;

  select * into v_existing_event
    from public.sales_channel_payment_events
   where tenant_id = p_tenant_id
     and provider = 'mercadopago'
     and external_payment_id = v_payment_id
     and provider_status = v_status;

  if found then
    return jsonb_build_object(
      'event_id', v_existing_event.id,
      'outcome', v_existing_event.outcome,
      'order_id', v_existing_event.order_id,
      'invoice_id', v_existing_event.invoice_id,
      'replay', true
    );
  end if;

  if v_currency <> 'CLP' then
    v_outcome := 'rejected_currency';
    v_error := format('Expected CLP, received %s', coalesce(nullif(v_currency, ''), '<empty>'));
  elsif p_amount is null or round(p_amount, 2) <> round(v_order.total, 2) then
    v_outcome := 'rejected_amount';
    v_error := format('Expected %s CLP, received %s', v_order.total, coalesce(p_amount::text, '<null>'));
  elsif v_status = 'approved'
        and v_order.payment_status = 'paid'
        and nullif(v_order.payment_reference, '') is distinct from v_payment_id then
    v_outcome := 'rejected_conflicting_payment';
    v_error := format('Order already paid by a different provider payment: %s', v_order.payment_reference);
  elsif v_order.payment_status = 'paid' and v_status <> 'approved' then
    v_outcome := 'ignored_stale';
  elsif v_status = 'approved' then
    update public.online_orders
       set payment_status = 'paid',
           payment_method = 'mercadopago',
           payment_reference = v_payment_id,
           paid_at = coalesce(p_paid_at, now()),
           updated_at = now()
     where id = v_order.id;

    v_invoice_id := public.process_online_order(v_order.id);

    update public.sales_payments
       set idempotency_key = 'mercadopago:' || v_payment_id,
           updated_at = now()
     where invoice_id = v_invoice_id
       and tenant_id = p_tenant_id
       and deleted_at is null
       and idempotency_key is null;

    select operation.id into v_operation_id
      from public.inventory_accounting_operations operation
     where operation.tenant_id = p_tenant_id
       and operation.document_type = 'sales_invoice'
       and operation.document_id = v_invoice_id
     order by operation.created_at desc
     limit 1;

    v_outcome := 'applied';
  else
    v_payment_status := case
      when v_status in ('rejected', 'cancelled') then 'failed'
      else 'pending'
    end;

    update public.online_orders
       set payment_status = v_payment_status,
           payment_method = 'mercadopago',
           payment_reference = v_payment_id,
           paid_at = null,
           updated_at = now()
     where id = v_order.id;

    v_invoice_id := v_order.sales_invoice_id;
    v_outcome := case when v_payment_status = 'failed'
      then 'recorded_failed' else 'recorded_pending' end;
  end if;

  insert into public.sales_channel_payment_events (
    tenant_id,
    provider,
    external_payment_id,
    provider_status,
    order_id,
    invoice_id,
    operation_id,
    amount,
    currency,
    outcome,
    validation_error,
    provider_payload
  ) values (
    p_tenant_id,
    'mercadopago',
    v_payment_id,
    v_status,
    v_order.id,
    coalesce(v_invoice_id, v_order.sales_invoice_id),
    v_operation_id,
    p_amount,
    nullif(v_currency, ''),
    v_outcome,
    v_error,
    coalesce(p_provider_payload, '{}'::jsonb)
  )
  returning id into v_existing_event.id;

  return jsonb_build_object(
    'event_id', v_existing_event.id,
    'outcome', v_outcome,
    'order_id', v_order.id,
    'invoice_id', coalesce(v_invoice_id, v_order.sales_invoice_id),
    'operation_id', v_operation_id,
    'replay', false,
    'validation_error', v_error
  );
end;
$$;

revoke all on function public.apply_mercadopago_payment_event(
  uuid, uuid, text, text, numeric, text, timestamp with time zone, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_mercadopago_payment_event(
  uuid, uuid, text, text, numeric, text, timestamp with time zone, jsonb
) to service_role;

-- These administrative/process functions were implicitly executable by PUBLIC.
-- Keep only the roles that actually own each application path.
revoke all on function public.process_online_order(uuid) from public, anon;
grant execute on function public.process_online_order(uuid) to authenticated, service_role;

revoke all on function public.confirm_online_order_payment(uuid, text, timestamp with time zone)
  from public, anon;
grant execute on function public.confirm_online_order_payment(uuid, text, timestamp with time zone)
  to authenticated, service_role;

revoke all on function public.cancel_online_order(uuid, text, numeric) from public, anon;
grant execute on function public.cancel_online_order(uuid, text, numeric)
  to authenticated, service_role;

-- The unused legacy writer has never stored a production row and bypasses the
-- movement ledger. Close it instead of allowing an untraceable stock mutation.
alter table public.order_items disable trigger trg_order_item_insert;
revoke insert, update, delete on public.orders from anon, authenticated, service_role;
revoke insert, update, delete on public.order_items from anon, authenticated, service_role;

commit;
