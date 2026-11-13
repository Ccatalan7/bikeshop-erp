-- Read-back de 20261112193700_weather_forecast_cache. Antes de desplegar tiene
-- que fallar contra producción (la tabla no existe).

select to_regclass('public.weather_forecast_cache') as tabla,
       (select relrowsecurity from pg_class
         where oid = to_regclass('public.weather_forecast_cache')) as con_rls,
       (select count(*) from pg_policies
         where schemaname = 'public'
           and tablename = 'weather_forecast_cache') as politicas;

select 1 / (case when
  to_regclass('public.weather_forecast_cache') is not null
  and coalesce((select relrowsecurity from pg_class
                 where oid = to_regclass('public.weather_forecast_cache')), false)
  -- Sin políticas: sólo la llave de servicio de la función la lee y la escribe.
  and not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'weather_forecast_cache')
  and not exists (
    select 1
      from unnest(array['anon', 'authenticated']) as role_name,
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege(
             role_name, to_regclass('public.weather_forecast_cache'), privilege))
  and has_table_privilege(
        'service_role', to_regclass('public.weather_forecast_cache'), 'SELECT')
  and has_table_privilege(
        'service_role', to_regclass('public.weather_forecast_cache'), 'INSERT')
  and has_table_privilege(
        'service_role', to_regclass('public.weather_forecast_cache'), 'UPDATE')
then 1 else 0 end) as cache_del_clima_solo_del_servidor;

select 1 / (case when (
  select count(*) from pg_constraint
   where conrelid = to_regclass('public.weather_forecast_cache')
     and (
       (contype = 'p' and pg_get_constraintdef(oid) = 'PRIMARY KEY (tenant_id)')
       or (contype = 'f' and pg_get_constraintdef(oid) like
             'FOREIGN KEY (tenant_id) REFERENCES %tenants(id) ON DELETE CASCADE')
       or conname in ('weather_forecast_cache_latitude_is_real',
                      'weather_forecast_cache_longitude_is_real'))
) = 4 then 1 else 0 end) as una_fila_por_tienda_y_coordenadas_reales;
