-- Read-back de 20260928010000_bike_technical_fact_completion_guard.
-- Antes de desplegar tiene que fallar contra producción. Se corre junto con
-- los read-back de 20260927030000, 20260927040000 y 20260927050000, que
-- siguen valiendo.

-- El trabajo terminado se toma `for share` antes que la bici; lo instalado
-- nombra una línea de ese trabajo y de esa bici; cada fuente escribe lo suyo.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%j.status in (''FINALIZADO'', ''ENTREGADO'')%for share;%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%An installed fact needs the job line that installed it%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%The job line is not part of this job and bicycle%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Spoke holes change only when the job that installs the wheel is finished%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%is not installed by a job%'
then 1 else 0 end) as instalado_desde_una_linea_terminada;

-- Mismos permisos: sólo el empleado autenticado ejecuta el comando.
select 1 / (case when
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as permisos_sin_cambio;
