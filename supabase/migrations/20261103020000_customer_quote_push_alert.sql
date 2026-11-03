-- Una cotización suena en el teléfono del equipo aunque la app esté cerrada.
--
-- El plan aprobado («Cotizaciones y pedidos a pedido», 2026-11-02) dice que
-- cada cotización nueva avisa en el ERP y al teléfono del taller. Hasta hoy
-- dejaba sólo el aviso dentro del ERP (`customer_quote_requested`), que ve
-- quien tiene la app abierta, y el cliente esperaba la respuesta mientras
-- nadie preguntaba a los proveedores.
--
-- Suena cuando la cotización vuelve a manos del equipo por algo del cliente:
--   * la pide desde el sitio (`requested`);
--   * pide cambios a la oferta (`changes_requested`).
-- La que arma el equipo en el mesón no suena: la hizo él. Aceptar tampoco
-- suena aquí: el pedido web que nace al aceptar ya suena como pedido
-- (`trg_online_orders_push_alert`).
--
-- Mismo contrato que `trg_online_orders_push_alert` (20261009020000): el
-- secreto vive en Vault, sin secreto no se encola nada, y un fallo del aviso
-- nunca hace fallar la cotización. `push-notification` vuelve a leer la
-- cotización y decide con la fila: si cuando llega ya no está por confirmar,
-- no suena.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.invoke_push_notification_for_customer_quote()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_webhook_secret text;
begin
  if new.actor_kind is distinct from 'customer'
     or new.event_type not in ('requested', 'changes_requested') then
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
      'type', 'CUSTOMER_QUOTE',
      'table', 'customer_quotes',
      'schema', 'public',
      'event', new.event_type,
      'record', jsonb_build_object(
        'id', new.quote_id,
        'tenant_id', new.tenant_id
      )
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'Customer quote push alert could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_customer_quote()
  from public, anon, authenticated, service_role;

comment on function public.invoke_push_notification_for_customer_quote() is
  'Queues a staff phone alert when a customer sends a quote from the site or asks for changes to its offer. Quotes fail open, dispatch fails closed.';

drop trigger if exists trg_customer_quote_events_push_alert
  on public.customer_quote_events;

create trigger trg_customer_quote_events_push_alert
  after insert on public.customer_quote_events
  for each row
  when (new.actor_kind = 'customer'
        and new.event_type in ('requested', 'changes_requested'))
  execute function public.invoke_push_notification_for_customer_quote();

comment on trigger trg_customer_quote_events_push_alert on public.customer_quote_events is
  'A quote the customer puts in the team''s hands rings the staff phones even with the app closed.';

commit;
