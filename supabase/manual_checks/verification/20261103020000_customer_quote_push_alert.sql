-- Read-back of 20261103020000. Fails before the migration and passes after.

select
  exists (select 1 from pg_trigger
           where tgrelid = 'public.customer_quote_events'::regclass
             and tgname = 'trg_customer_quote_events_push_alert' and not tgisinternal)
    as suena_el_telefono;

select 1 / (case when
  exists (select 1 from pg_trigger
           where tgrelid = 'public.customer_quote_events'::regclass
             and tgname = 'trg_customer_quote_events_push_alert' and not tgisinternal)
  and not has_function_privilege('anon', 'public.invoke_push_notification_for_customer_quote()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.invoke_push_notification_for_customer_quote()', 'EXECUTE')
  and pg_get_functiondef('public.invoke_push_notification_for_customer_quote()'::regprocedure)
    like '%CUSTOMER_QUOTE%'
then 1 else 0 end) as afirma_aviso_de_cotizacion;
