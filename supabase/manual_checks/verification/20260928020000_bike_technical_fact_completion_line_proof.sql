-- Read-back de 20260928020000_bike_technical_fact_completion_line_proof.
-- Antes de desplegar tiene que fallar contra producción. Se corre junto con
-- los read-back de 20260927030000, 20260927040000, 20260927050000,
-- 20260928002200 y 20260928010000, que siguen valiendo.

-- La llave, el comando y la línea cuentan lo mismo: `<datos>` es lo que se
-- escribe, la línea dice sus perforaciones y su rueda, y una línea de
-- General no elige bici en un trabajo de varias.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%The installed fact key does not match the facts it writes%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%The job line did not install %'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%service_configuration_data->>''hole_count''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%v_item.job_bike_id is null%) > 1%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%for share;%'
then 1 else 0 end) as instalado_probado_por_su_linea;

-- Mismos permisos: sólo el empleado autenticado ejecuta el comando.
select 1 / (case when
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as permisos_sin_cambio;
