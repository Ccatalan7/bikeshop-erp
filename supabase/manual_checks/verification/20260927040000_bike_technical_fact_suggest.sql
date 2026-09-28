-- Read-back de 20260927040000_bike_technical_fact_suggest.
-- Antes de desplegar tiene que fallar contra producción: el comando todavía no
-- sabe sugerir. Se corre junto con el read-back de 20260927030000, que sigue
-- valiendo para la firma, los permisos y las correcciones anteriores.

-- El comando sugiere sin confirmar, con su propia fuente, no sugiere el aro y
-- una sugerencia sola no renueva «Última confirmación».
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%v_op = ''suggest''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%''service_wizard''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Bicycle wheel size has no confirmation mark to hold a suggestion%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%when v_confirmed_any then clock_timestamp()%'
  and has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as comando_sugiere;
