-- Read-back de 20260923201000_products_functions_not_for_anon.
-- Antes de desplegar tiene que fallar contra producción (anónimo las ejecuta).

select p.oid::regprocedure::text as funcion,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as con_sesion,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as servicio
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('search_products', 'match_products_semantic')
 order by 1;

select 1 / (case when
  not has_function_privilege('anon', 'public.search_products(text,uuid,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.match_products_semantic(vector,uuid,double precision,integer)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.search_products(text,uuid,integer)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.match_products_semantic(vector,uuid,double precision,integer)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.match_products_semantic(vector,uuid,double precision,integer)', 'EXECUTE')
then 1 else 0 end) as anonimo_fuera_erp_dentro;
