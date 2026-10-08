-- Read-back of 20261008160000_conversation_read_signal.sql (plain SQL, no
-- transaction control: it runs through the read-only hosted wrapper).

select
  to_regprocedure('public.invoke_push_notification_for_conversation_read()')
    is not null as read_signal_function,
  exists (
    select 1
      from pg_trigger trigger
     where trigger.tgrelid = 'public.conversations'::regclass
       and trigger.tgname = 'trg_conversations_read_signal'
       and trigger.tgenabled = 'O'
       and not trigger.tgisinternal
  ) as read_signal_trigger_enabled,
  has_function_privilege(
    'service_role',
    'public.invoke_push_notification_for_message()',
    'EXECUTE'
  ) as message_trigger_service_exec,
  has_function_privilege(
    'authenticated',
    'public.invoke_push_notification_for_conversation_read()',
    'EXECUTE'
  ) as read_signal_client_exec;

select 1 / (
  case
    when to_regprocedure(
      'public.invoke_push_notification_for_conversation_read()'
    ) is not null then 1
    else 0
  end
) as afirma_funcion_de_lectura;

select 1 / (
  case
    when exists (
      select 1
        from pg_trigger trigger
       where trigger.tgrelid = 'public.conversations'::regclass
         and trigger.tgname = 'trg_conversations_read_signal'
         and trigger.tgenabled = 'O'
         and not trigger.tgisinternal
    ) then 1
    else 0
  end
) as afirma_disparador_activo;

select 1 / (
  case
    when not has_function_privilege(
      'authenticated',
      'public.invoke_push_notification_for_conversation_read()',
      'EXECUTE'
    )
    and not has_function_privilege(
      'service_role',
      'public.invoke_push_notification_for_message()',
      'EXECUTE'
    ) then 1
    else 0
  end
) as afirma_funciones_sin_llamada_directa;
