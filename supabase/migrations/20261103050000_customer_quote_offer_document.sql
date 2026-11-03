-- La oferta en PDF. El documento se dibuja desde lo que ve el cliente —la
-- proyección pública de la cotización—: en la tienda con el enlace de la
-- cotización y en el ERP para que el equipo lo mande por WhatsApp. Le faltaba
-- el membrete: el nombre y el contacto que la tienda ya publica, y que el
-- pedido congela al nacer (capture_online_order_storefront_snapshot).
--
-- Esa regla pasa a su propia función, storefront_identity_internal, y la usan
-- los dos: el pedido guarda exactamente lo mismo que antes y la cotización la
-- lee al dibujarse, con la dirección de la tienda (`store_url`) para decir
-- dónde se acepta.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.storefront_identity_internal(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_row record;
  company_name_value text;
  company_legal_name_value text;
  company_fantasy_name_value text;
  company_public_email_value text;
  company_support_phone_value text;
  store_name_value text;
  business_name_value text;
  store_tagline_value text;
  store_description_value text;
  logo_url_value text;
  contact_email_value text;
  contact_phone_value text;
  display_name_value text;
  legal_name_value text;
  tagline_value text;
  effective_logo_url_value text;
  support_email_value text;
  support_phone_value text;
begin
  select
    tenant.id,
    nullif(btrim(tenant.shop_name), '') as shop_name,
    nullif(btrim(tenant.logo_url), '') as logo_url
  into strict tenant_row
  from public.tenants tenant
  where tenant.id = p_tenant_id
    and tenant.is_active is true;

  select
    selected_company.name,
    selected_company.legal_name,
    selected_company.fantasy_name,
    selected_company.public_email,
    selected_company.support_phone
  into
    company_name_value,
    company_legal_name_value,
    company_fantasy_name_value,
    company_public_email_value,
    company_support_phone_value
  from (
    select
      nullif(btrim(company.name), '') as name,
      nullif(btrim(company.legal_name), '') as legal_name,
      nullif(btrim(company.fantasy_name), '') as fantasy_name,
      nullif(btrim(company.public_email), '') as public_email,
      nullif(btrim(company.support_phone), '') as support_phone
    from public.companies company
    where company.tenant_id = p_tenant_id
    order by company.is_default desc nulls last, company.created_at, company.id
    limit 1
  ) selected_company
  right join (select true as singleton) singleton on true;

  select
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_name'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'business_name'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_tagline'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'store_description'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'logo_url'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'contact_email'),
    max(nullif(btrim(setting.value), ''))
      filter (where setting.key = 'contact_phone')
  into
    store_name_value,
    business_name_value,
    store_tagline_value,
    store_description_value,
    logo_url_value,
    contact_email_value,
    contact_phone_value
  from public.website_settings setting
  where setting.tenant_id = p_tenant_id
    and setting.key in (
      'store_name',
      'business_name',
      'store_tagline',
      'store_description',
      'logo_url',
      'contact_email',
      'contact_phone'
    );

  display_name_value := left(coalesce(
    store_name_value,
    business_name_value,
    company_fantasy_name_value,
    tenant_row.shop_name,
    company_name_value,
    'Tienda'
  ), 200);
  legal_name_value := left(coalesce(
    company_legal_name_value,
    company_name_value,
    business_name_value,
    display_name_value
  ), 240);
  tagline_value := left(coalesce(
    store_tagline_value,
    store_description_value,
    ''
  ), 500);
  effective_logo_url_value := coalesce(logo_url_value, tenant_row.logo_url);
  if effective_logo_url_value !~* '^https://[^[:space:]]+$' then
    effective_logo_url_value := null;
  end if;
  -- Sólo campos que la tienda ya publica: quien tiene el enlace del pedido o
  -- de la cotización no ve el correo ni el teléfono internos de la empresa ni
  -- el correo del dueño.
  support_email_value := left(coalesce(
    contact_email_value,
    company_public_email_value,
    ''
  ), 254);
  support_phone_value := left(coalesce(
    contact_phone_value,
    company_support_phone_value,
    ''
  ), 60);

  return jsonb_strip_nulls(jsonb_build_object(
    'schemaVersion', 1,
    'displayName', display_name_value,
    'legalName', nullif(legal_name_value, ''),
    'tagline', nullif(tagline_value, ''),
    'logoUrl', effective_logo_url_value,
    'supportEmail', nullif(support_email_value, ''),
    'supportPhone', nullif(support_phone_value, '')
  ));
end;
$$;

revoke all on function public.storefront_identity_internal(uuid)
  from public, anon, authenticated, service_role;

-- El pedido congela la misma identidad, ahora desde su única regla.
create or replace function public.capture_online_order_storefront_snapshot(
  p_order_id uuid,
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.online_orders customer_order
    where customer_order.id = p_order_id
      and customer_order.tenant_id = p_tenant_id
  ) then
    raise exception 'Checkout order tenant mismatch'
      using errcode = '42501';
  end if;

  insert into public.online_order_storefront_snapshots (
    order_id,
    tenant_id,
    identity_snapshot
  )
  values (
    p_order_id,
    p_tenant_id,
    public.storefront_identity_internal(p_tenant_id)
  )
  on conflict (order_id) do nothing;
end;
$$;

revoke all on function
  public.capture_online_order_storefront_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Lo que ve el cliente, ahora con el membrete. Mismo cuerpo que
-- 20261103040000 más `storefront`.
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
    -- El membrete del PDF y dónde se acepta: lo que la tienda ya publica.
    'storefront', (select public.storefront_identity_internal(q.tenant_id)
                          || jsonb_strip_nulls(jsonb_build_object('storeUrl', (
                               select nullif(btrim(s.value), '')
                                 from public.website_settings s
                                where s.tenant_id = q.tenant_id and s.key = 'store_url'
                             )))
                     from q),
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

-- El mismo documento para el equipo: la cotización tal como la ve el
-- cliente, sin el enlace. El ERP dibuja el PDF desde aquí.
create or replace function public.customer_quote_offer_document_v1(
  p_tenant_id uuid,
  p_quote_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  if not exists (
    select 1 from public.customer_quotes q
     where q.id = p_quote_id and q.tenant_id = p_tenant_id
  ) then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  return public.customer_quote_public_projection_internal(p_quote_id);
end;
$$;

revoke all on function public.customer_quote_offer_document_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_offer_document_v1(uuid, uuid) to authenticated;

commit;
