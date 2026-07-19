-- Close UUID-only public order access and make the checkout access token the
-- single bearer credential used by confirmation and payment-preference flows.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- The legacy reader serializes the complete online_orders row, including
-- customer PII, addresses, notes and payment/provider fields. An order UUID is
-- an identifier, not an authorization secret.
revoke all on function public.get_public_online_order(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Public callers must receive the access token atomically with the order. The
-- UUID-only entry point would otherwise still allow creating an order without
-- retaining a credential that can read it afterwards.
revoke all on function public.create_public_online_order(jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_public_online_order(jsonb, jsonb)
  to service_role;

create or replace function public.create_public_online_order_with_access(
  p_order_data jsonb,
  p_order_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tenant_id uuid;
  v_checkout_key text;
  v_existing_order_id uuid;
  v_order_id uuid;
  v_order_tenant_id uuid;
  v_access jsonb;
  v_replay boolean := false;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload' using errcode = '22023';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null then
    raise exception 'Invalid tenant_id' using errcode = '22023';
  end if;

  v_checkout_key := lower(btrim(coalesce(
    p_order_data->>'checkout_idempotency_key',
    ''
  )));

  -- This key is also proof that a replay belongs to the browser that created
  -- the checkout. Require a random UUIDv4 instead of accepting predictable
  -- labels used by older callers.
  if v_checkout_key !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  then
    raise exception 'A random checkout idempotency key is required'
      using errcode = '22023';
  end if;

  -- Match the advisory key used by create_public_online_order. Taking it here
  -- makes replay detection and access-token issuance one transaction. PostgreSQL
  -- transaction advisory locks are re-entrant when the wrapped function takes
  -- the same lock again.
  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':' || v_checkout_key, 0)
  );

  select orders.id
    into v_existing_order_id
    from public.online_orders orders
   where orders.tenant_id = v_tenant_id
     and orders.checkout_idempotency_key = v_checkout_key;
  v_replay := found;

  v_order_id := public.create_public_online_order(
    p_order_data || jsonb_build_object(
      'checkout_idempotency_key',
      v_checkout_key
    ),
    p_order_items
  );

  select orders.tenant_id
    into v_order_tenant_id
    from public.online_orders orders
   where orders.id = v_order_id;

  if not found or v_order_tenant_id is distinct from v_tenant_id then
    raise exception 'Checkout order tenant mismatch' using errcode = '42501';
  end if;
  if v_replay and v_existing_order_id is distinct from v_order_id then
    raise exception 'Checkout replay returned a different order'
      using errcode = '23505';
  end if;

  -- Raw token material is returned once. issue_online_order_access_token stores
  -- only SHA-256, an expiry, scopes and audit counters.
  v_access := public.issue_online_order_access_token(
    v_order_id,
    array['view_order']::text[],
    clock_timestamp() + interval '30 days'
  );

  return jsonb_build_object(
    'order_id', v_order_id,
    'access_token', v_access->>'token',
    'expires_at', v_access->>'expires_at',
    'replay', v_replay
  );
end;
$$;

revoke all on function public.create_public_online_order_with_access(jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_public_online_order_with_access(jsonb, jsonb)
  to anon, authenticated, service_role;

-- Re-declare the token reader with the exact public projection needed by the
-- confirmation/payment UI. PII and internal/provider fields stay excluded.
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
    'subtotal', item.subtotal
  ) order by item.created_at, item.id), '[]'::jsonb)
    into v_items
    from public.online_order_items item
   where item.order_id = v_order.id
     and item.tenant_id = v_order.tenant_id;

  -- Explicit allowlist: never expose tenant/customer identifiers, email,
  -- phone, address, payment reference, invoice id, customer/internal notes,
  -- generic notes or provider payloads.
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

comment on function public.create_public_online_order_with_access(jsonb, jsonb) is
  'Atomic public checkout/replay. Returns the order id and one raw 30-day view token while persisting only its hash.';
comment on function public.get_public_online_order_by_access_token(text) is
  'Token-authorized redacted online-order projection. No UUID-only or tenant-id-only public access is permitted.';

commit;
