-- La vista previa del correo antes de registrar el despacho.
--
-- 2026-10-13: el dueño pidió ver el correo «va en camino» antes de que salga,
-- «como lo hacemos con la plantilla de WhatsApp antes de enviarla». Para que
-- la vista previa sea el correo y no una copia que se desvíe:
--   · `transactional_email_render_payload` arma el contenido del correo de un
--     pedido; lo usan la cola (`enqueue_transactional_email_from_order_event_id`)
--     y la vista previa. `transactional_email_subject` arma el asunto.
--   · `online_order_shipment_from_input` lee la boleta (campos permitidos,
--     código sin espacios, transportista y código obligatorios); lo usan el
--     registro (`record_online_order_shipment`) y la vista previa.
--   · `preview_online_order_shipment_email` devuelve, sin escribir nada, a
--     quién va, de quién, el asunto, si se enviará de verdad y el contenido
--     con el que la función `preview-transactional-order-email` dibuja el
--     mismo HTML que mandaría el worker.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. Lo que dice un correo de un pedido, en un solo lugar: lo usan el envío
--    real (la cola) y la vista previa, así que la vista previa es el correo.
-- ---------------------------------------------------------------------------
create or replace function public.transactional_email_render_payload(
  p_order public.online_orders,
  p_message_kind text,
  p_shipment public.online_order_shipments default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $function$
declare
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
begin
  select * into v_tenant
  from public.tenants
  where id = p_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = p_order.tenant_id;

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
  where item.order_id = p_order.id
    and item.tenant_id = p_order.tenant_id;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', p_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_order.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'currency', coalesce(v_tenant.currency, 'CLP'),
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      -- La marca del correo es la del tema del editor del sitio.
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_primary_color'
         limit 1
      ),
      'headingFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_heading_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      ),
      'bodyFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_body_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      )
    )),
    'customer', jsonb_build_object('name', p_order.customer_name),
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', p_order.id,
      'number', p_order.order_number,
      'status', p_order.status,
      'paymentStatus', p_order.payment_status,
      'createdAt', p_order.created_at,
      'deliveryType', p_order.delivery_type,
      'subtotal', p_order.subtotal,
      'shippingCost', p_order.shipping_cost,
      'discountAmount', p_order.discount_amount,
      'total', p_order.total,
      'trackingCarrier', p_order.shipping_carrier,
      'trackingNumber', p_order.tracking_number,
      'trackingUrl', case
        when p_order.tracking_url ~* '^https://[^[:space:]]+$' then p_order.tracking_url
        else null
      end,
      'refundedAmount', case
        when p_message_kind = 'refund_completed' then p_order.refund_amount
        else null
      end,
      'refundedAt', case
        when p_message_kind = 'refund_completed' then p_order.refunded_at
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
  if p_message_kind = 'shipped' then
    v_payload := v_payload || jsonb_build_object(
      'shipment', case
        when p_shipment is null then null
        else jsonb_strip_nulls(jsonb_build_object(
          'carrier', p_shipment.carrier,
          'carrierCode', p_shipment.carrier_code,
          'service', p_shipment.service,
          'trackingNumber', p_shipment.tracking_number,
          'trackingUrl', p_shipment.tracking_url,
          'admittedAt', p_shipment.admitted_at
        ))
      end,
      'delivery', jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(btrim(p_order.customer_name), ''),
        'addressLine1', nullif(btrim(p_order.shipping_address_line1), ''),
        'addressLine2', nullif(btrim(p_order.shipping_address_line2), ''),
        'city', nullif(btrim(p_order.shipping_city), ''),
        'state', nullif(btrim(p_order.shipping_state), '')
      ))
    );
  end if;

  return v_payload;
end;
$function$;

comment on function public.transactional_email_render_payload(public.online_orders, text, public.online_order_shipments) is
  'The render payload of an online-order email. Shared by the queue (enqueue_transactional_email_from_order_event_id) and the staff preview, so a preview is the email that would be sent.';

revoke all on function public.transactional_email_render_payload(public.online_orders, text, public.online_order_shipments)
  from public, anon, authenticated, service_role;

create or replace function public.transactional_email_subject(
  p_message_kind text,
  p_order_number text
)
returns text
language sql
immutable
set search_path = public
as $function$
  select case p_message_kind
    when 'order_received' then format('Recibimos tu pedido %s', p_order_number)
    when 'payment_confirmed' then format('Pago confirmado · %s', p_order_number)
    when 'processing' then format('Estamos preparando tu pedido %s', p_order_number)
    when 'ready_for_pickup' then format('Tu pedido %s está listo para retiro', p_order_number)
    when 'shipped' then format('Tu pedido %s ya fue enviado', p_order_number)
    when 'delivered' then format('Tu pedido %s fue entregado', p_order_number)
    when 'cancelled' then format('Actualización de tu pedido %s', p_order_number)
    when 'refund_completed' then format('Reembolso completado · %s', p_order_number)
  end;
$function$;

revoke all on function public.transactional_email_subject(text, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. La cola arma el correo con el mismo constructor. Mismo cuerpo que
--    20261013220000 salvo que el contenido y el asunto salen de 1.
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
  v_shipment public.online_order_shipments%rowtype;
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

  if v_message_kind = 'shipped' then
    select shipment.* into v_shipment
      from public.online_order_shipments shipment
     where shipment.tenant_id = v_order.tenant_id
       and shipment.order_id = v_order.id
     order by shipment.created_at desc
     limit 1;
  end if;

  v_subject := public.transactional_email_subject(v_message_kind, v_order.order_number);
  v_payload := public.transactional_email_render_payload(v_order, v_message_kind, v_shipment);

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

-- ---------------------------------------------------------------------------
-- 3. Leer la boleta: un dueño para el registro y la vista previa.
-- ---------------------------------------------------------------------------
create or replace function public.online_order_shipment_from_input(p_shipment jsonb)
returns public.online_order_shipments
language plpgsql
stable
set search_path = public, pg_temp
as $function$
declare
  v_shipment public.online_order_shipments%rowtype;
begin
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

  v_shipment.carrier := nullif(btrim(coalesce(p_shipment->>'carrier', '')), '');
  v_shipment.carrier_code := nullif(btrim(coalesce(p_shipment->>'carrier_code', '')), '');
  v_shipment.service := nullif(btrim(coalesce(p_shipment->>'service', '')), '');
  v_shipment.tracking_number :=
    nullif(regexp_replace(coalesce(p_shipment->>'tracking_number', ''), '\s', '', 'g'), '');
  v_shipment.tracking_url := nullif(btrim(coalesce(p_shipment->>'tracking_url', '')), '');
  v_shipment.branch := nullif(btrim(coalesce(p_shipment->>'branch', '')), '');
  v_shipment.receipt_path := nullif(btrim(coalesce(p_shipment->>'receipt_path', '')), '');
  begin
    v_shipment.admitted_at :=
      nullif(btrim(coalesce(p_shipment->>'admitted_at', '')), '')::timestamptz;
  exception when others then
    raise exception 'Shipment admitted_at is not a date' using errcode = '22023';
  end;
  begin
    v_shipment.cost := nullif(btrim(coalesce(p_shipment->>'cost', '')), '')::numeric;
  exception when others then
    raise exception 'Shipment cost is not a number' using errcode = '22023';
  end;
  v_shipment.extracted := coalesce(
    case when jsonb_typeof(p_shipment->'extracted') = 'object' then p_shipment->'extracted' end,
    '{}'::jsonb
  );
  v_shipment.checks := coalesce(
    case when jsonb_typeof(p_shipment->'checks') = 'object' then p_shipment->'checks' end,
    '{}'::jsonb
  );

  if v_shipment.carrier is null then
    raise exception 'Indica el transportista del envío.' using errcode = '22023';
  end if;
  if v_shipment.tracking_number is null then
    raise exception 'Indica el número de seguimiento del envío.' using errcode = '22023';
  end if;
  return v_shipment;
end;
$function$;

revoke all on function public.online_order_shipment_from_input(jsonb)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Registrar el despacho: mismo comando que 20261013210000, leyendo la
--    boleta con 3.
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
  v_draft public.online_order_shipments%rowtype;
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

  -- La boleta se lee igual aquí y en la vista previa del correo.
  v_draft := public.online_order_shipment_from_input(p_shipment);
  v_carrier := v_draft.carrier;
  v_carrier_code := v_draft.carrier_code;
  v_service := v_draft.service;
  v_tracking := v_draft.tracking_number;
  v_tracking_url := v_draft.tracking_url;
  v_admitted_at := v_draft.admitted_at;
  v_branch := v_draft.branch;
  v_cost := v_draft.cost;
  v_receipt_path := v_draft.receipt_path;

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
    v_draft.extracted,
    v_draft.checks,
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
-- 5. La vista previa del correo «va en camino». No escribe nada.
-- ---------------------------------------------------------------------------
create or replace function public.preview_online_order_shipment_email(
  p_order_id uuid,
  p_shipment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_order public.online_orders%rowtype;
  v_shipment public.online_order_shipments%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_recipient text;
  v_valid_recipient boolean;
  v_delivery_mode text := 'dry_run';
  v_suppression_reason text;
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id using errcode = '42501';
  end if;
  if coalesce(v_order.delivery_type, '') <> 'shipping' then
    raise exception 'Sólo un pedido con despacho a domicilio se despacha.' using errcode = '23514';
  end if;
  if v_order.status not in ('confirmed', 'processing') then
    raise exception 'El pedido ya no espera despacho (está %).', v_order.status using errcode = '23514';
  end if;

  v_shipment := public.online_order_shipment_from_input(p_shipment);
  v_shipment.tenant_id := v_tenant_id;
  v_shipment.order_id := v_order.id;

  -- El pedido como lo deja el despacho (transition_online_order_status).
  v_order.status := 'shipped';
  v_order.tracking_number := coalesce(v_shipment.tracking_number, v_order.tracking_number);
  v_order.tracking_url := coalesce(v_shipment.tracking_url, v_order.tracking_url);
  v_order.shipping_carrier := coalesce(v_shipment.carrier, v_order.shipping_carrier);

  select * into v_tenant
    from public.tenants
   where id = v_order.tenant_id;

  select * into v_settings
    from public.transactional_email_settings
   where tenant_id = v_order.tenant_id;
  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  v_valid_recipient := v_recipient ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$';
  if v_valid_recipient then
    select suppression.reason into v_suppression_reason
      from public.transactional_email_suppressions suppression
     where suppression.tenant_id = v_order.tenant_id
       and suppression.email_sha256 = encode(
         extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'),
         'hex'
       )
       and suppression.lifted_at is null
     order by suppression.suppressed_at desc
     limit 1;
  end if;

  return jsonb_build_object(
    'templateKey', 'shipped',
    'templateVersion', 1,
    'recipient', case when v_valid_recipient then v_recipient end,
    'recipientName', nullif(btrim(v_order.customer_name), ''),
    'senderName', nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    'senderEmail', nullif(lower(btrim(v_settings.from_email)), ''),
    'replyTo', nullif(lower(btrim(v_settings.reply_to_email)), ''),
    'subject', public.transactional_email_subject('shipped', v_order.order_number),
    'deliveryMode', v_delivery_mode,
    'suppressed', v_suppression_reason,
    'payload', public.transactional_email_render_payload(v_order, 'shipped', v_shipment)
  );
end;
$function$;

comment on function public.preview_online_order_shipment_email(uuid, jsonb) is
  'Staff preview of the shipped email for a shipping receipt draft: recipient, sender, subject, delivery mode and the render payload the worker would use. Writes nothing.';

revoke all on function public.preview_online_order_shipment_email(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.preview_online_order_shipment_email(uuid, jsonb)
  to authenticated;

commit;
