-- Read-back de 20261013230000: existe la vista previa del correo de despacho,
-- es sólo para el personal, y la cola y el registro usan los dueños
-- compartidos (el contenido del correo y la lectura de la boleta).

select 1 / case
  when has_function_privilege('authenticated', 'public.preview_online_order_shipment_email(uuid,jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.preview_online_order_shipment_email(uuid,jsonb)', 'execute')
   and not has_function_privilege('authenticated', 'public.transactional_email_render_payload(public.online_orders,text,public.online_order_shipments)', 'execute')
   and position(
     'transactional_email_render_payload'
     in pg_get_functiondef('public.enqueue_transactional_email_from_order_event_id(uuid)'::regprocedure)
   ) > 0
   and position(
     'online_order_shipment_from_input'
     in pg_get_functiondef('public.record_online_order_shipment(uuid,bigint,text,jsonb)'::regprocedure)
   ) > 0
  then 1 else 0 end as online_order_shipment_email_preview;
