-- Read-back of 20261102100000. Fails before the migration and passes after.

select
  position('mechanic_jobs' in pg_get_functiondef(
    'public.customer_quote_inbox_v1(uuid, text, integer, integer)'::regprocedure)) > 0 as lee_el_taller;

select 1 / (case when
  pg_get_functiondef('public.customer_quote_inbox_v1(uuid, text, integer, integer)'::regprocedure)
    like '%''workshop''::text as source%'
  and pg_get_functiondef('public.customer_quote_inbox_v1(uuid, text, integer, integer)'::regprocedure)
    like '%converted_to_billable%'
then 1 else 0 end) as afirma_bandeja_con_taller;

select 1 / (case when
  (select prosecdef from pg_proc
    where oid = 'public.customer_quote_inbox_v1(uuid, text, integer, integer)'::regprocedure)
  and has_function_privilege('authenticated',
    'public.customer_quote_inbox_v1(uuid, text, integer, integer)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.customer_quote_inbox_v1(uuid, text, integer, integer)', 'EXECUTE')
then 1 else 0 end) as afirma_permisos;
