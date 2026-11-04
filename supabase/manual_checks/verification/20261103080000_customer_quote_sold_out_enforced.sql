-- Read-back of 20261103080000. Fails before the migration and passes after.

select 1 / (case when
  pg_get_functiondef('public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)'::regprocedure)
    like '%not_offered_sold_out%'
  and pg_get_functiondef('public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)'::regprocedure)
    like '%customer_quote_sold_out_mode_internal%'
  and not has_function_privilege('authenticated',
    'public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)', 'EXECUTE')
then 1 else 0 end) as afirma_la_solicitud_respeta_lo_que_se_ofrece;
