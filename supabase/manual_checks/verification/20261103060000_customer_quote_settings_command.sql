-- Read-back of 20261103060000. Fails before the migration and passes after.

select
  has_function_privilege('authenticated', 'public.customer_quote_settings_v1(uuid)', 'EXECUTE')
    as el_equipo_lee_los_ajustes,
  (select count(*) from public.customer_quote_settings) as talleres_con_ajustes_propios;

select 1 / (case when
  has_function_privilege('authenticated', 'public.customer_quote_settings_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_settings_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.customer_quote_setting_value_internal(jsonb, text, integer, integer, integer)', 'EXECUTE')
  and pg_get_functiondef('public.update_customer_quote_settings_v1(uuid, jsonb)'::regprocedure)
    like '%can_edit_tenant_settings%'
  and pg_get_functiondef('public.update_customer_quote_settings_v1(uuid, jsonb)'::regprocedure)
    like '%quote_deposit_unsupported%'
  and not exists (select 1 from public.customer_quote_settings s where s.on_order_prepay_percent <> 100)
then 1 else 0 end) as afirma_ajustes_de_cotizaciones;
