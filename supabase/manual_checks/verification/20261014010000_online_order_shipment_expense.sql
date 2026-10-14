-- Read-back de 20261014010000: el despacho registra el gasto de su costo en
-- la misma transacción (o después, una vez), la app ve el plan antes, los
-- internos no se exponen y la fecha de admisión se revisa en el registro y en
-- la vista previa.

select 1 / case
  when exists (
     select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'online_order_shipments'
        and column_name = 'expense_id'
   )
   and has_function_privilege('authenticated', 'public.record_online_order_shipment(uuid,bigint,text,jsonb,jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.record_online_order_shipment(uuid,bigint,text,jsonb,jsonb)', 'execute')
   and to_regprocedure('public.record_online_order_shipment(uuid,bigint,text,jsonb)') is null
   and has_function_privilege('authenticated', 'public.record_online_order_shipment_expense(uuid,jsonb)', 'execute')
   and has_function_privilege('authenticated', 'public.online_order_shipment_expense_options(text)', 'execute')
   and not has_function_privilege('authenticated', 'public.online_order_shipment_create_expense(public.online_order_shipments,public.online_orders,jsonb,uuid)', 'execute')
   and not has_function_privilege('authenticated', 'public.online_order_shipment_expense_plan(uuid,text)', 'execute')
   and position(
     'online_order_shipment_check_admission'
     in pg_get_functiondef('public.preview_online_order_shipment_email(uuid,jsonb)'::regprocedure)
   ) > 0
   and position(
     'online_order_shipment_create_expense'
     in pg_get_functiondef('public.record_online_order_shipment(uuid,bigint,text,jsonb,jsonb)'::regprocedure)
   ) > 0
  then 1 else 0 end as online_order_shipment_expense;
