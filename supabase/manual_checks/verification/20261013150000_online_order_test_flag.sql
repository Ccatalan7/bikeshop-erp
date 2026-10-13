-- Read-back de 20261013150000: la marca de prueba existe, el comando la
-- cambia sólo para usuarios autenticados, y en Viñabike quedan marcadas las 77
-- órdenes anteriores a WEB-26-00021 y no WEB-26-00021.

select 1 / case
  when exists (
     select 1
     from information_schema.columns column_row
     where column_row.table_schema = 'public'
       and column_row.table_name = 'online_orders'
       and column_row.column_name = 'is_test'
       and column_row.is_nullable = 'NO'
       and column_row.column_default = 'false'
   )
   and has_function_privilege('authenticated', 'public.set_online_order_test_flag(uuid,boolean,bigint,text)', 'execute')
   and not has_function_privilege('anon', 'public.set_online_order_test_flag(uuid,boolean,bigint,text)', 'execute')
   and pg_get_constraintdef((
     select constraint_row.oid
     from pg_constraint constraint_row
     where constraint_row.conrelid = 'public.online_order_events'::regclass
       and constraint_row.conname = 'online_order_events_event_type_check'
   )) like '%test_flag_changed%'
   and (
     select count(*)
     from public.online_orders orders
     where orders.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and orders.is_test
       and orders.created_at < '2026-10-12 18:52:14.961371+00'
   ) = (
     select count(*)
     from public.online_orders orders
     where orders.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and orders.created_at < '2026-10-12 18:52:14.961371+00'
   )
   and exists (
     select 1
     from public.online_orders orders
     where orders.id = '24328d78-5af2-48c6-9366-94371fa0d90a'
       and orders.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and orders.is_test is false
   )
  then 1 else 0 end as online_order_test_flag_ready;
