-- Un pedido web suena en el teléfono del equipo aunque la app esté cerrada.
--
-- Hasta hoy un pedido nuevo dejaba sólo el aviso dentro del ERP
-- (`erp_notifications`, 20260501200000): lo veía quien tuviera la app abierta.
-- El dueño, 2026-10-09: que el taller se entere al tiro, para que nadie se
-- quede esperando respuesta.
--
-- Avisa cuando hay algo que hacer, no por cada carrito:
--   * un pedido que se paga por transferencia (o cualquier medio que no sea
--     Mercado Pago) avisa al crearse: hay que mirar la cartola y confirmarlo;
--   * uno de Mercado Pago avisa cuando el pago queda `paid`: hay que
--     prepararlo. Al crearse no avisa: 41 de 63 nunca se pagaron (2026-10-09).
-- Confirmar una transferencia la hace el equipo mismo: no avisa.
--
-- Mismo contrato que `trg_messages_push_notification` (20260718240000): el
-- secreto vive en Vault, sin secreto no se encola nada, y un fallo del aviso
-- nunca hace fallar el pedido. `push-notification` vuelve a leer el pedido y
-- decide con la fila, no con lo que diga este cuerpo.
--
-- Con la app abierta el push no se muestra (lo ignora el shell: no trae
-- chat) y manda el aviso durable del ERP. Ese aviso nacía sólo al crear el
-- pedido, así que un pago de Mercado Pago pasaba sin aviso para quien estaba
-- usando el ERP (revisión de Codex, 2026-10-09). Por eso el pago también deja
-- su aviso durable, `online_order_paid`, uno por pedido; si el pedido ya
-- estaba cancelado, es una advertencia para devolver el pago
-- (`online_order_paid_after_cancellation`).

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.create_online_order_paid_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
  v_cancelled boolean;
begin
  if new.payment_method is distinct from 'mercadopago'
     or new.payment_status is distinct from 'paid'
     or old.payment_status is not distinct from 'paid' then
    return new;
  end if;

  -- Un pago que llega después de cancelar el pedido no es una venta: hay que
  -- devolverlo (Mercado Pago lo clasifica después como
  -- `approved_payment_for_cancelled_order`). Revisión de Codex, 2026-10-09.
  v_cancelled := new.status = 'cancelled';

  v_body := coalesce(nullif(new.order_number, ''), 'Pedido web')
    || ' · '
    || coalesce(nullif(new.customer_name, ''), 'Cliente');
  if coalesce(new.total, 0) > 0 then
    v_body := v_body || ' · $' || trim(to_char(new.total, 'FM999G999G999G990'));
  end if;

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    new.tenant_id,
    case when v_cancelled
      then 'online_order_paid_after_cancellation'
      else 'online_order_paid'
    end,
    case when v_cancelled
      then 'Pago de un pedido cancelado: devolverlo'
      else 'Venta online pagada'
    end,
    v_body,
    '/website/orders?order=' || new.id::text,
    'online_order',
    new.id,
    case when v_cancelled then 'warning' else 'success' end,
    jsonb_build_object(
      'order_id', new.id,
      'order_number', new.order_number,
      'customer_name', new.customer_name,
      'total', new.total,
      'payment_method', new.payment_method,
      'payment_status', new.payment_status,
      'delivery_type', new.delivery_type
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return new;
exception
  when others then
    -- El aviso nunca deshace la confirmación del pago.
    raise warning 'Online order paid notification could not be recorded';
    return new;
end;
$$;

revoke all on function public.create_online_order_paid_erp_notification()
  from public, anon, authenticated, service_role;

comment on function public.create_online_order_paid_erp_notification() is
  'Records one durable ERP alert when a Mercado Pago web order becomes paid (a warning to refund when the order was already cancelled), so a team member using the ERP sees it; never blocks the payment.';

drop trigger if exists trg_online_order_paid_erp_notification
  on public.online_orders;

create trigger trg_online_order_paid_erp_notification
  after update of payment_status on public.online_orders
  for each row
  execute function public.create_online_order_paid_erp_notification();

create or replace function public.invoke_push_notification_for_online_order()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_event text;
  v_webhook_secret text;
begin
  if tg_op = 'INSERT' then
    if coalesce(new.payment_method, '') in ('mercadopago', 'smoke_test')
       or new.payment_status = 'paid' then
      return new;
    end if;
    v_event := 'awaiting_payment';
  else
    if new.payment_method is distinct from 'mercadopago'
       or new.payment_status is distinct from 'paid'
       or old.payment_status is not distinct from 'paid' then
      return new;
    end if;
    v_event := 'paid';
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
      'type', 'ONLINE_ORDER',
      'table', 'online_orders',
      'schema', 'public',
      'event', v_event,
      'record', jsonb_build_object(
        'id', new.id,
        'tenant_id', new.tenant_id
      )
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'Online order push alert could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_online_order()
  from public, anon, authenticated, service_role;

comment on function public.invoke_push_notification_for_online_order() is
  'Queues a staff phone alert for a web order that needs action: created with a non-Mercado Pago payment, or paid through Mercado Pago. Orders fail open, dispatch fails closed.';

drop trigger if exists trg_online_orders_push_alert on public.online_orders;

create trigger trg_online_orders_push_alert
  after insert or update of payment_status on public.online_orders
  for each row
  execute function public.invoke_push_notification_for_online_order();

comment on trigger trg_online_orders_push_alert on public.online_orders is
  'A web order that needs the team rings the staff phones even with the app closed.';

commit;
