-- Read-back de 20261113093000_weather_places. Antes de desplegar tiene que
-- fallar contra producción (la tabla de lugares no existe).

select to_regclass('public.weather_places') as lugares,
       (select pg_get_constraintdef(oid) from pg_constraint
         where conrelid = to_regclass('public.weather_forecast_cache')
           and contype = 'p') as llave_del_cache;

select 1 / (case when
  to_regclass('public.weather_places') is not null
  and coalesce((select relrowsecurity from pg_class
                 where oid = to_regclass('public.weather_places')), false)
  -- Sin políticas: sólo la llave de servicio de la función la lee y la escribe.
  and not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'weather_places')
  and not exists (
    select 1
      from unnest(array['anon', 'authenticated']) as role_name,
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege(
             role_name, to_regclass('public.weather_places'), privilege))
  and has_table_privilege(
        'service_role', to_regclass('public.weather_places'), 'INSERT')
then 1 else 0 end) as lugares_solo_del_servidor;

select 1 / (case when (
  select pg_get_constraintdef(oid) from pg_constraint
   where conrelid = to_regclass('public.weather_forecast_cache')
     and contype = 'p'
) = 'PRIMARY KEY (tenant_id, place_key)'
  -- El lugar del local conserva su fila bajo la clave «shop».
  and not exists (
    select 1 from public.weather_forecast_cache where place_key is null)
then 1 else 0 end) as un_pronostico_por_local_y_lugar;
