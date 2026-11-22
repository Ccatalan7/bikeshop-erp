-- 20261122040000: la hora de envío se lee y se cambia desde la ficha. Falla si
-- faltan los comandos, si perdieron su permiso o si una visita los alcanza.
-- SQL plano, sin control de transacción: corre por el envoltorio de lectura.
select 1 / case
  when to_regprocedure('public.supplier_order_send_settings_v1(uuid,uuid)') is not null
   and to_regprocedure('public.set_supplier_order_send_time_v1(uuid,uuid,text)') is not null
   and has_function_privilege('authenticated',
         'public.supplier_order_send_settings_v1(uuid,uuid)', 'EXECUTE')
   and has_function_privilege('authenticated',
         'public.set_supplier_order_send_time_v1(uuid,uuid,text)', 'EXECUTE')
   and not has_function_privilege('anon',
         'public.set_supplier_order_send_time_v1(uuid,uuid,text)', 'EXECUTE')
   and not has_function_privilege('anon',
         'public.supplier_order_send_settings_v1(uuid,uuid)', 'EXECUTE')
  then 1 else 0 end as send_time_commands;
