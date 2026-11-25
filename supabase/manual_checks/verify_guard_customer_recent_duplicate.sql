-- 20261125191700: la base rechaza el mismo cliente creado otra vez en 10
-- minutos. Falla si el disparador no está, si la función no tiene el cuerpo
-- nuevo o si quedó al alcance de la API.
-- SQL plano, sin control de transacción: corre por el envoltorio de lectura.
select 1 / case
  when exists (
         select 1 from pg_trigger t
          where t.tgrelid = 'public.customers'::regclass
            and t.tgname = 'trg_guard_customer_recent_duplicate'
            and t.tgenabled = 'O'
            and not t.tgisinternal)
   and pg_get_functiondef('public.guard_customer_recent_duplicate()'::regprocedure)
         like '%interval ''10 minutes''%detail = ''customer_recent_duplicate''%hint = v_existing::text%'
   and pg_get_functiondef('public.guard_customer_recent_duplicate()'::regprocedure)
         like '%pg_advisory_xact_lock%'
   and not has_function_privilege('anon',
         'public.guard_customer_recent_duplicate()', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.guard_customer_recent_duplicate()', 'EXECUTE')
  then 1 else 0 end as customer_recent_duplicate_guard;
