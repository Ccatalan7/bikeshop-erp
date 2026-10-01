-- Read-back de 20260928052000_bike_conflicts_without_postgrest_retry. Antes
-- de desplegar tiene que fallar contra producción (siguen con 40001).

-- Los cinco conflictos de la ficha usan PT409 y ninguno 40001, que PostgREST
-- 14 reintenta sin fin.
select 1 / (case when
  (length(pg_get_functiondef('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure))
    - length(replace(pg_get_functiondef('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure), 'errcode = ''PT409''', '')))
    / length('errcode = ''PT409''') = 4
  and (length(pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
    - length(replace(pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure), 'errcode = ''PT409''', '')))
    / length('errcode = ''PT409''') = 1
  and pg_get_functiondef('public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)'::regprocedure)
    not like '%serialization_failure%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    not like '%serialization_failure%'
then 1 else 0 end) as conflictos_sin_reintento;

-- Los permisos no cambian: el comando público sigue siendo del empleado, el
-- interno sólo de service_role.
select 1 / (case when
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.save_bike_aggregate_internal(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)', 'EXECUTE')
then 1 else 0 end) as permisos_iguales;
