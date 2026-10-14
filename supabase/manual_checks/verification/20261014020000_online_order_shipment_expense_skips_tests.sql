-- Read-back de 20261014020000: el gasto del envío se niega para un pedido de
-- prueba y el escritor sigue siendo interno.

select 1 / case
  when position(
     'Un pedido de prueba no registra gastos.'
     in pg_get_functiondef('public.online_order_shipment_create_expense(public.online_order_shipments,public.online_orders,jsonb,uuid)'::regprocedure)
   ) > 0
   and not has_function_privilege('authenticated', 'public.online_order_shipment_create_expense(public.online_order_shipments,public.online_orders,jsonb,uuid)', 'execute')
  then 1 else 0 end as online_order_shipment_expense_skips_tests;
