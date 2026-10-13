-- El despacho de un pedido web se registra con la boleta del envío.
--
-- 2026-10-13: el taller despachó WEB-26-00021 por Correos de Chile y el
-- compañero mandó la foto de la boleta (sucursal, código de seguimiento,
-- servicio, destinatario, valor). El dueño pidió que el ERP la reciba, la lea
-- con IA, actualice el pedido y le avise al cliente con un correo cuidado.
--
-- La lectura la hace la app (IA multimodal por gemini-proxy) y la persona la
-- confirma; la base guarda lo que se registró y lo que se leyó:
--   · `online_order_shipments`: un registro por boleta (transportista,
--     servicio, código, enlace de la página de seguimiento, admisión, valor
--     pagado, la foto en `vinabike-files`, lo que leyó la IA y su cotejo con el
--     pedido). Sólo lo leen las personas del taller.
--   · `record_online_order_shipment`: registra la boleta y pasa el pedido a
--     «Despachado» en la misma transacción, con recibo e idempotencia por la
--     clave de operación. El correo «va en camino» sale por el mismo evento
--     de siempre (`enqueue_transactional_email_from_order_event_id`).
--   · Un pedido confirmado puede pasar directo a «Despachado» cuando trae la
--     evidencia del envío: la boleta prueba que se preparó, y pasar por
--     «En preparación» mandaba dos correos seguidos al cliente.
--   · El correo «enviado» lleva el servicio, la fecha de admisión, la
--     dirección de entrega y el logo de la ficha de la empresa cuando el
--     tenant no tiene uno propio.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. La boleta del envío.
-- ---------------------------------------------------------------------------
create table if not exists public.online_order_shipments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_id uuid not null references public.online_orders(id) on delete cascade,
  carrier text not null check (btrim(carrier) <> '' and char_length(carrier) <= 80),
  carrier_code text check (
    carrier_code is null
    or carrier_code in ('correos_chile', 'chilexpress', 'starken', 'blue_express', 'pullman_cargo', 'other')
  ),
  service text check (service is null or char_length(service) <= 120),
  tracking_number text check (tracking_number is null or char_length(tracking_number) <= 80),
  tracking_url text check (
    tracking_url is null or (tracking_url ~* '^https://[^[:space:]]+$' and char_length(tracking_url) <= 500)
  ),
  admitted_at timestamptz,
  branch text check (branch is null or char_length(branch) <= 160),
  cost numeric(12, 2) check (cost is null or cost >= 0),
  receipt_path text check (receipt_path is null or char_length(receipt_path) <= 300),
  extracted jsonb not null default '{}'::jsonb check (jsonb_typeof(extracted) = 'object'),
  checks jsonb not null default '{}'::jsonb check (jsonb_typeof(checks) = 'object'),
  operation_key text not null check (btrim(operation_key) <> '' and char_length(operation_key) <= 160),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (tenant_id, operation_key)
);

create index if not exists online_order_shipments_order_idx
  on public.online_order_shipments (tenant_id, order_id, created_at desc);

alter table public.online_order_shipments enable row level security;
revoke all on table public.online_order_shipments
  from public, anon, authenticated, service_role;
grant select on table public.online_order_shipments to authenticated, service_role;

drop policy if exists online_order_shipments_select on public.online_order_shipments;
create policy online_order_shipments_select
  on public.online_order_shipments
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

comment on table public.online_order_shipments is
  'Shipping receipts of online orders: carrier, service, tracking code, admission, cost, the receipt photo in vinabike-files and what the AI read from it. Written only by record_online_order_shipment.';

-- ---------------------------------------------------------------------------
-- 2. Confirmado → Despachado cuando trae la evidencia del envío (la regla de
--    «shipped» sigue exigiendo despacho a domicilio, pago, venta saldada y
--    transportista o seguimiento). Mismo cuerpo que producción salvo esa línea.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transition_online_order_status(p_order_id uuid, p_new_status text, p_expected_version bigint, p_operation_key text, p_tracking_number text DEFAULT NULL::text, p_tracking_url text DEFAULT NULL::text, p_carrier text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
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
    or (v_order.status = 'confirmed' and v_target in ('processing', 'shipped', 'cancelled'))
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
$function$;

-- ---------------------------------------------------------------------------
-- 3. Registrar el despacho con su boleta.
-- ---------------------------------------------------------------------------
create or replace function public.record_online_order_shipment(
  p_order_id uuid,
  p_expected_version bigint,
  p_operation_key text,
  p_shipment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_existing public.online_order_shipments%rowtype;
  v_order public.online_orders%rowtype;
  v_shipment public.online_order_shipments%rowtype;
  v_carrier text;
  v_carrier_code text;
  v_service text;
  v_tracking text;
  v_tracking_url text;
  v_admitted_at timestamptz;
  v_branch text;
  v_cost numeric;
  v_receipt_path text;
  v_transition jsonb;
begin
  if v_actor_id is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  if p_order_id is null or p_expected_version is null then
    raise exception 'Order and expected version are required' using errcode = '22023';
  end if;
  if v_operation_key = '' or char_length(v_operation_key) > 160 then
    raise exception 'A valid operation key is required' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_shipment, 'null'::jsonb)) <> 'object'
     or exists (
       select 1 from jsonb_object_keys(p_shipment) key
        where key not in (
          'carrier', 'carrier_code', 'service', 'tracking_number', 'tracking_url',
          'admitted_at', 'branch', 'cost', 'receipt_path', 'extracted', 'checks'
        )
     ) then
    raise exception 'Shipment accepts carrier, carrier_code, service, tracking_number, tracking_url, admitted_at, branch, cost, receipt_path, extracted and checks'
      using errcode = '22023';
  end if;

  -- Reintento con la misma clave: el mismo recibo.
  select shipment.* into v_existing
    from public.online_order_shipments shipment
   where shipment.tenant_id = v_tenant_id
     and shipment.operation_key = v_operation_key;
  if found then
    if v_existing.order_id <> p_order_id then
      raise exception 'Operation key already belongs to another order' using errcode = '23505';
    end if;
    return to_jsonb(v_existing) || jsonb_build_object(
      'order_status', (select status from public.online_orders where id = p_order_id),
      'order_version', (select version from public.online_orders where id = p_order_id),
      'replay', true
    );
  end if;

  v_carrier := nullif(btrim(coalesce(p_shipment->>'carrier', '')), '');
  v_carrier_code := nullif(btrim(coalesce(p_shipment->>'carrier_code', '')), '');
  v_service := nullif(btrim(coalesce(p_shipment->>'service', '')), '');
  v_tracking := nullif(regexp_replace(coalesce(p_shipment->>'tracking_number', ''), '\s', '', 'g'), '');
  v_tracking_url := nullif(btrim(coalesce(p_shipment->>'tracking_url', '')), '');
  v_branch := nullif(btrim(coalesce(p_shipment->>'branch', '')), '');
  v_receipt_path := nullif(btrim(coalesce(p_shipment->>'receipt_path', '')), '');
  begin
    v_admitted_at := nullif(btrim(coalesce(p_shipment->>'admitted_at', '')), '')::timestamptz;
  exception when others then
    raise exception 'Shipment admitted_at is not a date' using errcode = '22023';
  end;
  begin
    v_cost := nullif(btrim(coalesce(p_shipment->>'cost', '')), '')::numeric;
  exception when others then
    raise exception 'Shipment cost is not a number' using errcode = '22023';
  end;

  if v_carrier is null then
    raise exception 'Indica el transportista del envío.' using errcode = '22023';
  end if;
  if v_tracking is null then
    raise exception 'Indica el número de seguimiento del envío.' using errcode = '22023';
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id using errcode = '42501';
  end if;
  if coalesce(v_order.delivery_type, '') <> 'shipping' then
    raise exception 'Sólo un pedido con despacho a domicilio se despacha.' using errcode = '23514';
  end if;
  if v_order.status not in ('confirmed', 'processing') then
    raise exception 'El pedido ya no espera despacho (está %).', v_order.status using errcode = '23514';
  end if;

  -- La foto tiene que estar en la carpeta de este pedido, y subida.
  if v_receipt_path is not null then
    if v_receipt_path !~ ('^' || v_tenant_id::text || '/evidence/online_order_shipment/'
                          || p_order_id::text || '/[A-Za-z0-9._-]+$') then
      raise exception 'The receipt must live in this order''s evidence folder' using errcode = '22023';
    end if;
    if not exists (
      select 1 from storage.objects object
       where object.bucket_id = 'vinabike-files'
         and object.name = v_receipt_path
    ) then
      raise exception 'The receipt photo was not uploaded' using errcode = '22023';
    end if;
  end if;

  insert into public.online_order_shipments (
    tenant_id, order_id, carrier, carrier_code, service, tracking_number,
    tracking_url, admitted_at, branch, cost, receipt_path, extracted, checks,
    operation_key, created_by
  ) values (
    v_tenant_id, p_order_id, v_carrier, v_carrier_code, v_service, v_tracking,
    v_tracking_url, v_admitted_at, v_branch, v_cost, v_receipt_path,
    coalesce(case when jsonb_typeof(p_shipment->'extracted') = 'object' then p_shipment->'extracted' end, '{}'::jsonb),
    coalesce(case when jsonb_typeof(p_shipment->'checks') = 'object' then p_shipment->'checks' end, '{}'::jsonb),
    v_operation_key, v_actor_id
  ) returning * into v_shipment;

  -- El cambio de estado y su correo, por el comando de siempre.
  v_transition := public.transition_online_order_status(
    p_order_id,
    'shipped',
    p_expected_version,
    v_operation_key,
    v_tracking,
    v_tracking_url,
    v_carrier,
    null
  );

  return to_jsonb(v_shipment) || jsonb_build_object(
    'order_status', (select status from public.online_orders where id = p_order_id),
    'order_version', (select version from public.online_orders where id = p_order_id),
    'replay', false
  );
end;
$$;

comment on function public.record_online_order_shipment(uuid, bigint, text, jsonb) is
  'Records a shipping receipt for an online order and moves it to shipped in one transaction; the shipped email follows from the status event. Idempotent per operation key.';

revoke all on function public.record_online_order_shipment(uuid, bigint, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_shipment(uuid, bigint, text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El correo «enviado»: servicio, admisión, dirección y logo. Mismo cuerpo
--    que producción salvo esos dos bloques.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_transactional_email_from_order_event_id(p_event_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_event public.online_order_events%rowtype;
  v_order public.online_orders%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_message_kind text;
  v_subject text;
  v_recipient text;
  v_source_event_key text;
  v_idempotency_key text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
  v_outbox_id uuid;
begin
  select * into v_event
  from public.online_order_events
  where id = p_event_id;

  if not found or not coalesce(v_event.changed, false) then
    return null;
  end if;

  select * into v_order
  from public.online_orders
  where id = v_event.order_id
    and tenant_id = v_event.tenant_id;

  if not found then
    raise exception 'Online order event % has no matching order', p_event_id;
  end if;

  v_message_kind := case
    when v_event.event_type = 'order_created' then 'order_received'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'paid'
      and v_order.payment_status = 'paid' then 'payment_confirmed'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'refunded'
      and v_order.payment_status = 'refunded'
      and v_order.refunded_at is not null
      and coalesce(v_order.refund_amount, 0) > 0 then 'refund_completed'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'processing'
      and v_order.status = 'processing' then 'processing'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'ready_for_pickup'
      and v_order.status = 'ready_for_pickup' then 'ready_for_pickup'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'shipped'
      and v_order.status = 'shipped' then 'shipped'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'delivered'
      and v_order.status = 'delivered' then 'delivered'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'cancelled'
      and v_order.status = 'cancelled' then 'cancelled'
    else null
  end;

  -- There are intentionally no automatic payment_voucher_available or
  -- tax_document_issued branches. A Mercado Pago status is payment evidence,
  -- not by itself an immutable official voucher artifact, and internal
  -- sales_invoices are not Chilean DTE evidence.
  if v_message_kind is null then
    return null;
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;

  select * into v_tenant
  from public.tenants
  where id = v_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = v_order.tenant_id;

  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', item.product_name,
      'sku', item.product_sku,
      'quantity', item.quantity,
      'unitPrice', item.unit_price,
      'subtotal', item.subtotal
    ) order by item.created_at, item.id
  ), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id
    and item.tenant_id = v_order.tenant_id;

  v_subject := case v_message_kind
    when 'order_received' then format('Recibimos tu pedido %s', v_order.order_number)
    when 'payment_confirmed' then format('Pago confirmado · %s', v_order.order_number)
    when 'processing' then format('Estamos preparando tu pedido %s', v_order.order_number)
    when 'ready_for_pickup' then format('Tu pedido %s está listo para retiro', v_order.order_number)
    when 'shipped' then format('Tu pedido %s ya fue enviado', v_order.order_number)
    when 'delivered' then format('Tu pedido %s fue entregado', v_order.order_number)
    when 'cancelled' then format('Actualización de tu pedido %s', v_order.order_number)
    when 'refund_completed' then format('Reembolso completado · %s', v_order.order_number)
  end;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', v_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = v_order.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'currency', coalesce(v_tenant.currency, 'CLP'),
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago')
    )),
    'customer', jsonb_build_object('name', v_order.customer_name),
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', v_order.id,
      'number', v_order.order_number,
      'status', v_order.status,
      'paymentStatus', v_order.payment_status,
      'createdAt', v_order.created_at,
      'deliveryType', v_order.delivery_type,
      'subtotal', v_order.subtotal,
      'shippingCost', v_order.shipping_cost,
      'discountAmount', v_order.discount_amount,
      'total', v_order.total,
      'trackingCarrier', v_order.shipping_carrier,
      'trackingNumber', v_order.tracking_number,
      'trackingUrl', case
        when v_order.tracking_url ~* '^https://[^[:space:]]+$' then v_order.tracking_url
        else null
      end,
      'refundedAmount', case
        when v_message_kind = 'refund_completed' then v_order.refund_amount
        else null
      end,
      'refundedAt', case
        when v_message_kind = 'refund_completed' then v_order.refunded_at
        else null
      end
    )),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'order_receipt',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pedido · No constituye documento tributario'
    )
  );

  -- «Va en camino» cuenta con qué se envió y adónde (20261013210000).
  if v_message_kind = 'shipped' then
    v_payload := v_payload || jsonb_build_object(
      'shipment', (
        select jsonb_strip_nulls(jsonb_build_object(
          'carrier', shipment.carrier,
          'carrierCode', shipment.carrier_code,
          'service', shipment.service,
          'trackingNumber', shipment.tracking_number,
          'trackingUrl', shipment.tracking_url,
          'admittedAt', shipment.admitted_at
        ))
          from public.online_order_shipments shipment
         where shipment.tenant_id = v_order.tenant_id
           and shipment.order_id = v_order.id
         order by shipment.created_at desc
         limit 1
      ),
      'delivery', jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(btrim(v_order.customer_name), ''),
        'addressLine1', nullif(btrim(v_order.shipping_address_line1), ''),
        'addressLine2', nullif(btrim(v_order.shipping_address_line2), ''),
        'city', nullif(btrim(v_order.shipping_city), ''),
        'state', nullif(btrim(v_order.shipping_state), '')
      ))
    );
  end if;

  v_source_event_key := 'online_order_event:' || v_event.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_event.tenant_id::text || ':' || v_event.order_id::text || ':' ||
      v_source_event_key || ':' || v_message_kind || ':' || v_recipient,
      'UTF8'
    ),
    'sha256'
  ), 'hex');

  select suppression.reason into v_suppression_reason
  from public.transactional_email_suppressions suppression
  where suppression.tenant_id = v_event.tenant_id
    and suppression.email_sha256 = encode(
      extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'),
      'hex'
    )
    and suppression.lifted_at is null
  order by suppression.suppressed_at desc
  limit 1;

  if v_suppression_reason is not null then
    v_state := 'suppressed';
  end if;

  insert into public.transactional_email_outbox (
    tenant_id,
    order_id,
    order_event_id,
    source_event_key,
    message_kind,
    template_key,
    template_version,
    recipient_email,
    recipient_name,
    sender_name,
    sender_email,
    reply_to_email,
    subject,
    render_payload,
    idempotency_key,
    delivery_mode,
    state,
    suppression_reason
  ) values (
    v_event.tenant_id,
    v_event.order_id,
    v_event.id,
    v_source_event_key,
    v_message_kind,
    v_message_kind,
    1,
    v_recipient,
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    nullif(lower(btrim(v_settings.from_email)), ''),
    nullif(lower(btrim(v_settings.reply_to_email)), ''),
    v_subject,
    v_payload,
    v_idempotency_key,
    v_delivery_mode,
    v_state,
    v_suppression_reason
  )
  on conflict (idempotency_key) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select id into v_outbox_id
    from public.transactional_email_outbox
    where idempotency_key = v_idempotency_key;
  end if;

  return v_outbox_id;
end;
$function$;

commit;
