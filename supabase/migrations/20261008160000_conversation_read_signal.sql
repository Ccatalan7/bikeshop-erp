-- Leído en un dispositivo, leído en todos.
--
-- Con clientes y proveedores la lectura ya es de Viñabike, no de cada persona
-- (`conversations.staff_last_read_message_sequence`, 2026-05-18): abrir el chat
-- en el escritorio limpia el contador de todos. Pero la notificación que el
-- teléfono ya mostró se quedaba en la bandeja del sistema hasta tocarla. El
-- dueño, 2026-10-08: «cuando se lee en uno, que actualice eso automáticamente
-- para todos, como lo hace WhatsApp en la realidad».
--
-- Cuando el cursor de lectura del equipo avanza, este disparador le pide a
-- `push-notification` una señal silenciosa (sin título ni texto) para los
-- dispositivos del equipo; la app borra con ella la notificación de ese chat.
-- Mismo contrato que `trg_messages_push_notification`
-- (20260718240000): el secreto vive en Vault, sin secreto no se encola nada, y
-- un fallo del aviso nunca hace fallar la lectura.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.invoke_push_notification_for_conversation_read()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_webhook_secret text;
begin
  if new.type is distinct from 'support' then
    return new;
  end if;
  if coalesce(new.staff_last_read_message_sequence, 0)
       <= coalesce(old.staff_last_read_message_sequence, 0) then
    return new;
  end if;

  select secret.decrypted_secret
    into v_webhook_secret
    from vault.decrypted_secrets secret
   where secret.name = 'push_notification_webhook_secret'
     and nullif(secret.decrypted_secret, '') is not null
   order by secret.created_at desc
   limit 1;

  if nullif(v_webhook_secret, '') is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-webhook-secret', v_webhook_secret
    ),
    body := jsonb_build_object(
      'type', 'READ',
      'table', 'conversations',
      'schema', 'public',
      'record', jsonb_build_object(
        'id', new.id,
        'tenant_id', new.tenant_id,
        'staff_last_read_message_sequence', new.staff_last_read_message_sequence
      )
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'Conversation read signal could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_conversation_read()
  from public, anon, authenticated, service_role;

-- Producción tenía de vuelta `service_role=X` en la función hermana de los
-- mensajes pese a los dos `revoke` de julio (lo encontró
-- `push_notification_webhook_security` el 2026-10-08). Se reafirma aquí.
revoke all on function public.invoke_push_notification_for_message()
  from public, anon, authenticated, service_role;

comment on function public.invoke_push_notification_for_conversation_read() is
  'Queues a silent read signal for staff devices when the team read cursor of a support conversation advances; reads fail open, dispatch fails closed.';

drop trigger if exists trg_conversations_read_signal on public.conversations;

create trigger trg_conversations_read_signal
  after update of staff_last_read_message_sequence on public.conversations
  for each row
  when (
    new.staff_last_read_message_sequence
      is distinct from old.staff_last_read_message_sequence
  )
  execute function public.invoke_push_notification_for_conversation_read();

comment on trigger trg_conversations_read_signal on public.conversations is
  'Read on one device, read on all: staff devices drop the chat notification.';

commit;
