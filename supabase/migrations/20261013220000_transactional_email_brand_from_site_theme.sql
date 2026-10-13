-- El correo al cliente lleva la marca del sitio.
--
-- 2026-10-13: el dueño pidió que el correo «va en camino» se vea profesional y
-- vistoso, «es nuestra cara visible del cliente». La marca del sitio vive en el
-- tema del editor (`website_settings`: `theme_primary_color` como ARGB o hex,
-- `theme_heading_font`, `theme_body_font`); el correo la toma de ahí al
-- encolarse, en vez de colores fijos en la plantilla, para que cambiar el tema
-- del sitio cambie también los correos. Mismo cuerpo que 20261013210000 salvo
-- esas tres llaves de `store`.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

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
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      -- La marca del correo es la del tema del editor del sitio.
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = v_order.tenant_id
           and setting.key = 'theme_primary_color'
         limit 1
      ),
      'headingFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = v_order.tenant_id
           and setting.key = 'theme_heading_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      ),
      'bodyFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = v_order.tenant_id
           and setting.key = 'theme_body_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      )
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
