-- La historia que ve el cliente en su cotización dice cuándo le devolvimos
-- el pago (20261103030000 lo registra como `order_refunded`). Hasta hoy la
-- página mostraba «El pedido se anuló» y el reembolso sólo llegaba por correo.
-- Mismo cuerpo que el desplegado, con un tipo más en la lista de la historia.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.customer_quote_public_projection_internal(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (
    select * from public.customer_quotes where id = p_quote_id
  ), offer as (
    select o.* from public.customer_quote_offers o, q
     where o.id = q.current_offer_id
  )
  select jsonb_build_object(
    'quote', (select jsonb_strip_nulls(jsonb_build_object(
      'number', q.quote_number,
      'status', q.status,
      'customerName', q.customer_name,
      'notifyEmail', q.notify_email,
      'notifyWhatsapp', q.notify_whatsapp,
      -- Sólo si la cuenta tiene cada dato, nunca el dato: el enlace se puede
      -- reenviar.
      'canEmail', q.customer_email is not null,
      'canWhatsapp', q.customer_phone is not null,
      'requestedAt', q.requested_at,
      'offeredAt', q.offered_at,
      'expiresAt', q.expires_at,
      'acceptedAt', q.accepted_at,
      'rejectedAt', q.rejected_at,
      'expiredAt', q.expired_at,
      'cancelledAt', q.cancelled_at
    )) from q),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineNo', l.line_no, 'name', l.product_name, 'sku', l.product_sku,
        'quantity', l.quantity, 'kind', l.kind_at_request
      ) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = p_quote_id
    ), '[]'::jsonb),
    'offer', (select jsonb_strip_nulls(jsonb_build_object(
      'id', offer.id,
      'number', offer.offer_no,
      'status', offer.status,
      'sentAt', offer.sent_at,
      'validUntil', offer.valid_until,
      'subtotal', offer.subtotal,
      'taxAmount', offer.tax_amount,
      'total', offer.total,
      'notes', offer.notes_to_customer,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', ol.id, 'lineNo', ol.line_no, 'name', ol.product_name, 'sku', ol.product_sku,
          'quantityRequested', ol.quantity_requested, 'quantity', ol.quantity_offered,
          'availability', ol.availability, 'unitPrice', ol.unit_price,
          'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
          'leadDaysMin', ol.lead_days_min, 'leadDaysMax', ol.lead_days_max,
          'note', ol.customer_note
        )) order by ol.line_no)
          from public.customer_quote_offer_lines ol where ol.offer_id = offer.id
      ), '[]'::jsonb)
    )) from offer where offer.status <> 'draft'),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.event_type, 'at', e.occurred_at) order by e.id)
        from public.customer_quote_events e
       where e.quote_id = p_quote_id
         and e.event_type in (
           'requested', 'offer_sent', 'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
           'order_paid', 'order_sale_issued', 'order_ready', 'order_shipped', 'order_delivered', 'order_cancelled',
           'order_refunded'
         )
    ), '[]'::jsonb),
    -- El pedido que nació al aceptar: estado, entrega y qué viene a pedido.
    -- Sin su acceso: la página lo pide con el enlace (20261103010000).
    'order', (select jsonb_strip_nulls(jsonb_build_object(
      'number', o.order_number,
      'status', o.status,
      'paymentStatus', o.payment_status,
      'paymentMethod', o.payment_method,
      'deliveryType', o.delivery_type,
      'productsTotal', o.subtotal + o.tax_amount,
      'shippingCost', o.shipping_cost,
      'total', o.total,
      'waiting', public.customer_quote_order_waiting_internal(o.id),
      'readyForPickupAt', o.ready_for_pickup_at,
      'shippedAt', o.shipped_at,
      'deliveredAt', o.delivered_at,
      'cancelledAt', o.cancelled_at,
      'trackingCarrier', o.shipping_carrier,
      'trackingNumber', o.tracking_number,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'name', i.product_name,
          'quantity', i.quantity,
          'onOrder', i.fulfillment = 'on_order',
          'arrived', case when i.fulfillment = 'on_order' then i.arrived_at is not null end,
          'leadDaysMin', i.lead_days_min,
          'leadDaysMax', i.lead_days_max
        )) order by i.created_at, i.id)
          from public.online_order_items i
         where i.order_id = o.id
      ), '[]'::jsonb)
    ))
      from public.online_orders o, q
     where o.id = q.online_order_id and o.tenant_id = q.tenant_id)
  );
$function$;

revoke all on function public.customer_quote_public_projection_internal(uuid) from public, anon, authenticated;

commit;
