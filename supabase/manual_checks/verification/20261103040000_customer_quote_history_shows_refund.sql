-- Read-back of 20261103040000. Fails before the migration and passes after.

select 1 / (case when
  pg_get_functiondef('public.customer_quote_public_projection_internal(uuid)'::regprocedure)
    like '%''order_refunded''%'
  and not has_function_privilege('anon', 'public.customer_quote_public_projection_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_historia_con_devolucion;
