-- Read-back de 20261013210000: existe la boleta del envío con su RLS, el
-- comando que la registra es sólo para el personal, un pedido confirmado puede
-- pasar a «Despachado» y el correo «enviado» lleva el envío y la dirección.

select 1 / case
  when to_regclass('public.online_order_shipments') is not null
   and (select relrowsecurity from pg_class where oid = 'public.online_order_shipments'::regclass)
   and has_table_privilege('authenticated', 'public.online_order_shipments', 'select')
   and not has_table_privilege('authenticated', 'public.online_order_shipments', 'insert')
   and has_function_privilege('authenticated', 'public.record_online_order_shipment(uuid,bigint,text,jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.record_online_order_shipment(uuid,bigint,text,jsonb)', 'execute')
   and position(
     $$v_order.status = 'confirmed' and v_target in ('processing', 'shipped', 'cancelled')$$
     in pg_get_functiondef('public.transition_online_order_status(uuid,text,bigint,text,text,text,text,text)'::regprocedure)
   ) > 0
   and position(
     $$'shipment'$$
     in pg_get_functiondef('public.enqueue_transactional_email_from_order_event_id(uuid)'::regprocedure)
   ) > 0
  then 1 else 0 end as online_order_shipment_receipt;
