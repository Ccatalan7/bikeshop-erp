-- La vuelta desde Mercado Pago abre el pedido aunque llegue a otra pestaña o
-- a otro navegador (2026-11-15).
--
-- El acceso al pedido vive en el sessionStorage de la pestaña donde se hizo
-- el checkout. Mercado Pago puede devolver al cliente a otra pestaña o, desde
-- su app, a otro navegador: ahí `/pedido/:id` decía «Esta sesión no tiene
-- acceso a ese pedido» aunque el pago estuviera hecho, y GA4 no contaba la
-- compra (WEB-26-00022, 2026-11-11).
--
-- La dirección de vuelta trae `preference_id`: la preferencia que el servidor
-- creó para ese pedido (`<collector>-<uuid>`, guardada en
-- `online_order_payment_preferences`), que sólo conocen el comprador, Mercado
-- Pago y la tienda. Quien la presenta junto con el id del pedido estuvo en ese
-- pago, así que recibe un acceso nuevo de sólo lectura, igual al del checkout
-- (`view_order`, 30 días), y la página sigue su camino de siempre: verifica el
-- pago con `mercadopago-get-payment`, cierra el carrito y mide la compra. La
-- proyección que abre ese acceso ya es la redactada: sin nombre, correo,
-- teléfono ni dirección.
--
-- Límites: sólo pedidos con Mercado Pago; la preferencia tiene que ser de ese
-- pedido, del mismo tenant y de los últimos 30 días; un pedido no recibe más
-- de 20 accesos en una hora. Todo rechazo responde null, sin decir por qué.

create or replace function public.issue_public_online_order_return_access_v1(
  p_order_id uuid,
  p_preference_id text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_order public.online_orders%rowtype;
  v_receipt jsonb;
begin
  if p_order_id is null
     or p_preference_id is null
     or p_preference_id !~ '^[0-9]{1,20}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  select customer_order.*
    into v_order
    from public.online_orders customer_order
   where customer_order.id = p_order_id;

  if not found or v_order.payment_method is distinct from 'mercadopago' then
    return null;
  end if;

  if not exists (
    select 1
      from public.online_order_payment_preferences preference
     where preference.order_id = v_order.id
       and preference.tenant_id = v_order.tenant_id
       and preference.provider = 'mercadopago'
       and preference.provider_preference_id = p_preference_id
       and preference.created_at > clock_timestamp() - interval '30 days'
  ) then
    return null;
  end if;

  if (
    select count(*)
      from public.online_order_access_tokens access
     where access.order_id = v_order.id
       and access.tenant_id = v_order.tenant_id
       and access.created_at > clock_timestamp() - interval '1 hour'
  ) >= 20 then
    return null;
  end if;

  v_receipt := public.issue_online_order_access_token(
    v_order.id,
    array['view_order']::text[],
    clock_timestamp() + interval '30 days'
  );

  -- La misma forma que el recibo del checkout
  -- (`create_public_online_order_with_access`), para que la página lo guarde
  -- con `saveOrderAccess`.
  return jsonb_build_object(
    'order_id', v_order.id,
    'access_token', v_receipt->>'token',
    'expires_at', v_receipt->>'expires_at',
    'replay', false
  );
end;
$$;

revoke all on function public.issue_public_online_order_return_access_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.issue_public_online_order_return_access_v1(uuid, text)
  to anon, authenticated, service_role;

comment on function public.issue_public_online_order_return_access_v1(uuid, text) is
  'Mercado Pago return in a tab without the checkout session: the order id plus the server-created preference id of that order (last 30 days) issue a new view_order access token, at most 20 per order per hour; any mismatch answers null.';
