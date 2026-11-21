-- Read-back of 20261120210000. Fails before the migration and passes after:
-- the rule and the ERP commands do not exist before, the order creation and
-- the arrival only carry the on-order line and the system context once it is
-- applied, and the supplier order may have no quote only after it.

select
  (select count(*) from public.product_on_order_terms
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and is_active) as fichas_a_pedido,
  (select count(*) from public.product_on_order_offer_internal_v1(
     '5443b130-cc28-45af-a420-cd500b288890', null)) as se_venden_con_plazo_ahora;

-- La regla existe, es privada, y decide los listados, la ficha y la cotización.
select 1 / (case when
  to_regprocedure('public.product_on_order_offer_internal_v1(uuid, uuid[])') is not null
  and not has_function_privilege('anon',
    to_regprocedure('public.product_on_order_offer_internal_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and not has_function_privilege('authenticated',
    to_regprocedure('public.product_on_order_offer_internal_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and not has_function_privilege('service_role',
    to_regprocedure('public.product_on_order_offer_internal_v1(uuid, uuid[])')::oid, 'EXECUTE')
  and to_regprocedure('public.customer_quote_sold_out_modes_internal(uuid, uuid[])') is not null
  and not has_function_privilege('anon',
    to_regprocedure('public.customer_quote_sold_out_modes_internal(uuid, uuid[])')::oid, 'EXECUTE')
  and pg_get_functiondef(to_regprocedure(
    'public.catalog_on_order_product_ids_internal_v1(uuid)')::oid)
    like '%product_on_order_offer_internal_v1%'
  and pg_get_functiondef(to_regprocedure(
    'public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)')::oid)
    like '%customer_quote_sold_out_modes_internal%'
  and pg_get_functiondef(to_regprocedure(
    'public.get_public_sold_out_offers_v1(uuid, uuid[])')::oid)
    like '%maxQuantity%'
  and has_function_privilege('anon', to_regprocedure(
    'public.get_public_sold_out_offers_v1(uuid, uuid[])')::oid, 'EXECUTE')
then 1 else 0 end) as afirma_la_regla;

-- El pedido web crea la línea que llega del proveedor.
select 1 / (case when
  pg_get_functiondef(to_regprocedure(
    'public.create_public_online_order_unkeyed(jsonb, jsonb)')::oid)
    like '%product_on_order_offer_internal_v1%'
  and pg_get_functiondef(to_regprocedure(
    'public.create_public_online_order_unkeyed(jsonb, jsonb)')::oid)
    like '%on_order_supplier_id%'
  and has_function_privilege('anon', to_regprocedure(
    'public.create_public_online_order_with_access(jsonb, jsonb)')::oid, 'EXECUTE')
then 1 else 0 end) as afirma_el_pedido_con_plazo;

-- Del pago a la llegada sin cotización, y la llegada con el pago de Mercado
-- Pago procesado sin la sesión de quien aprieta el botón.
select 1 / (case when
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'customer_quote_purchase_orders'
      and column_name = 'quote_id') = 'YES'
  and to_regprocedure('public.online_order_on_order_notify_internal(uuid, text, text, text)') is not null
  and not has_function_privilege('authenticated', to_regprocedure(
    'public.online_order_on_order_notify_internal(uuid, text, text, text)')::oid, 'EXECUTE')
  and pg_get_functiondef(to_regprocedure(
    'public.customer_quote_order_paid_internal(uuid)')::oid)
    like '%online_order_on_order_notify_internal%'
  and pg_get_functiondef(to_regprocedure(
    'public.customer_quote_order_check_arrivals_internal(uuid)')::oid)
    like '%request.jwt.claim.sub%'
  and pg_get_functiondef(to_regprocedure(
    'public.customer_quote_orders_check_arrivals_v1()')::oid)
    not like '%join public.customer_quotes%'
  and pg_get_functiondef(to_regprocedure(
    'public.transactional_email_render_payload(online_orders, text, online_order_shipments)')::oid)
    like '%leadDaysMin%'
then 1 else 0 end) as afirma_el_camino_sin_cotizacion;

-- Los comandos del ERP: el equipo sí, un visitante no.
select 1 / (case when
  has_function_privilege('authenticated', to_regprocedure(
    'public.online_order_on_order_detail_v1(uuid, uuid)')::oid, 'EXECUTE')
  and has_function_privilege('authenticated', to_regprocedure(
    'public.online_order_on_order_check_arrivals_v1(uuid, uuid)')::oid, 'EXECUTE')
  and has_function_privilege('authenticated', to_regprocedure(
    'public.online_order_on_order_cancel_v1(uuid, uuid, jsonb)')::oid, 'EXECUTE')
  and not has_function_privilege('anon', to_regprocedure(
    'public.online_order_on_order_detail_v1(uuid, uuid)')::oid, 'EXECUTE')
  and not has_function_privilege('anon', to_regprocedure(
    'public.online_order_on_order_cancel_v1(uuid, uuid, jsonb)')::oid, 'EXECUTE')
  and pg_get_functiondef(to_regprocedure(
    'public.customer_quote_detail_v1(uuid, uuid)')::oid)
    like '%online_order_on_order_projection_internal%'
then 1 else 0 end) as afirma_los_comandos_del_erp;

-- Lo que hoy se vende con plazo es lo mismo que la tienda lee como a pedido.
select 1 / (case when (
  select count(*) from public.product_on_order_offer_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890', null)
) = cardinality(public.catalog_on_order_product_ids_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'))
then 1 else 0 end) as la_regla_y_los_listados_coinciden;
