-- Read-back of 20261009020000_online_order_push_alert.sql
-- (plain SQL, no transaction control: it runs through the read-only hosted
-- wrapper).

select
  (select routine.prosecdef
     from pg_proc routine
    where routine.oid =
      'public.invoke_push_notification_for_online_order()'::regprocedure)
    as security_definer,
  (select trigger.tgenabled::text
     from pg_trigger trigger
    where trigger.tgrelid = 'public.online_orders'::regclass
      and trigger.tgname = 'trg_online_orders_push_alert'
      and not trigger.tgisinternal) as trigger_enabled,
  has_function_privilege(
    'service_role',
    'public.invoke_push_notification_for_online_order()',
    'EXECUTE'
  ) as service_role_can_execute,
  has_function_privilege(
    'authenticated',
    'public.invoke_push_notification_for_online_order()',
    'EXECUTE'
  ) as authenticated_can_execute;

select 1 / (
  case
    when (
      select trigger.tgenabled::text
        from pg_trigger trigger
       where trigger.tgrelid = 'public.online_orders'::regclass
         and trigger.tgname = 'trg_online_orders_push_alert'
         and not trigger.tgisinternal
    ) = 'O' then 1
    else 0
  end
) as afirma_disparador_activo;

select 1 / (
  case
    when position(
      'push_notification_webhook_secret' in pg_get_functiondef(
        'public.invoke_push_notification_for_online_order()'::regprocedure
      )
    ) > 0 then 1
    else 0
  end
) as afirma_secreto_de_vault;

select 1 / (
  case
    when not has_function_privilege(
           'anon',
           'public.invoke_push_notification_for_online_order()',
           'EXECUTE')
     and not has_function_privilege(
           'authenticated',
           'public.invoke_push_notification_for_online_order()',
           'EXECUTE')
     and not has_function_privilege(
           'service_role',
           'public.invoke_push_notification_for_online_order()',
           'EXECUTE')
    then 1
    else 0
  end
) as afirma_sin_permisos_de_cliente;

select 1 / (
  case
    when (
      select trigger.tgenabled::text
        from pg_trigger trigger
       where trigger.tgrelid = 'public.online_orders'::regclass
         and trigger.tgname = 'trg_online_order_paid_erp_notification'
         and not trigger.tgisinternal
    ) = 'O'
     and not has_function_privilege(
           'authenticated',
           'public.create_online_order_paid_erp_notification()',
           'EXECUTE')
     and not has_function_privilege(
           'service_role',
           'public.create_online_order_paid_erp_notification()',
           'EXECUTE')
    then 1
    else 0
  end
) as afirma_aviso_durable_del_pago;
