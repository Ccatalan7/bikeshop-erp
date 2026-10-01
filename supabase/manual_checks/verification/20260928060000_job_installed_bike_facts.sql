-- Read-back de 20260928060000_job_installed_bike_facts. Antes de desplegar
-- tiene que fallar contra producción (no existen las funciones nuevas).

-- La regla interna existe y sólo la llaman los comandos del servidor; el
-- comando para reaplicar es del empleado autenticado.
select 1 / (case when
  to_regprocedure('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)') is not null
  and not has_function_privilege('authenticated',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.sync_job_installed_bike_facts_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.sync_job_installed_bike_facts_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as funciones_y_permisos;

-- La transición escribe lo instalado al terminar y su conflicto ya no es un
-- 40001 que PostgREST reintente sin fin; sus permisos no cambian.
select 1 / (case when
  pg_get_functiondef('public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)
    like '%apply_job_installed_bike_facts_internal%'
  and pg_get_functiondef('public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)
    like '%''installed_bike_facts''%'
  and pg_get_functiondef('public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)
    not like '%errcode = ''40001''%'
  and pg_get_functiondef('public.transition_mechanic_job_status(uuid,uuid,text)'::regprocedure)
    like '%errcode = ''PT409''%'
  and has_function_privilege('authenticated',
    'public.transition_mechanic_job_status(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.transition_mechanic_job_status(uuid,uuid,text)', 'EXECUTE')
then 1 else 0 end) as transicion_instala;

-- Con fuente `job_completion`, el parche toma el trabajo antes que la llave
-- (el orden de la transición), y la sincronización toma el trabajo
-- `for update`.
select 1 / (case when
  position('Lo instalado toma el trabajo antes que la llave' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
    between 1 and position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
  and pg_get_functiondef('public.sync_job_installed_bike_facts_v1(uuid)'::regprocedure)
    like '%for update%'
then 1 else 0 end) as orden_de_locks;
