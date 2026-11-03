-- Read-back of 20261103030000. Fails before the migration and passes after.

select
  has_function_privilege('authenticated', 'public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)', 'EXECUTE')
    as el_equipo_anula_y_devuelve;

select 1 / (case when
  has_function_privilege('authenticated', 'public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)', 'EXECUTE')
  and pg_get_functiondef('public.customer_quote_order_cancel_v1(uuid, uuid, jsonb)'::regprocedure)
    like '%online_order_correction_actor_allowed%'
  and pg_get_functiondef('public.customer_quote_order_waiting_internal(uuid)'::regprocedure)
    like '%cancelled%'
  and pg_get_constraintdef((select oid from pg_constraint
                             where conrelid = 'public.customer_quote_events'::regclass
                               and conname = 'customer_quote_events_type'))
    like '%order_refunded%'
then 1 else 0 end) as afirma_anular_y_devolver;
