-- Una nómina guardada como borrador suena en el teléfono de quien la paga.
--
-- El dueño, 2026-11-21: «Vicente es el que hace las nóminas … cuando él la
-- complete y la mande y quede el borrador, que me llegue una notificación …
-- así yo puedo transferirles en ese momento». Vicente arma la semana y la
-- guarda de una vez (`save_payroll_voucher_draft`, o
-- `prepare_payroll_voucher_draft_v2` desde Asistencias): en las nueve
-- semanas guardadas desde septiembre, `created_at` = `updated_at`. Guardar
-- es insertar la fila en borrador, y eso es lo que suena.
--
-- Mismo contrato que `trg_customer_quote_events_push_alert`
-- (20261103020000): el secreto vive en Vault, sin secreto no se encola nada,
-- y un fallo del aviso nunca hace fallar la nómina. `pg_net` despacha después
-- del commit, así que `push-notification` lee la nómina ya con sus líneas; la
-- vuelve a leer y decide con la fila (si ya no está en borrador, no suena),
-- elige a quién (quien puede pagar nóminas, menos quien la guardó) y no pone
-- montos: el total no descuenta los anticipos.
--
-- Una nómina vieja no suena: restaurar un respaldo reinserta filas con los
-- disparadores vivos, y sus borradores traen el `created_at` de su día.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.invoke_push_notification_for_payroll_voucher()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_webhook_secret text;
begin
  if new.status is distinct from 'draft'
     or new.created_at < now() - interval '1 hour' then
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
      'type', 'PAYROLL_VOUCHER',
      'table', 'payroll_vouchers',
      'schema', 'public',
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
    raise warning 'Payroll push alert could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_payroll_voucher()
  from public, anon, authenticated, service_role;

comment on function public.invoke_push_notification_for_payroll_voucher() is
  'Queues a phone alert to whoever pays payroll when a payroll is saved as a draft. Payroll fails open, dispatch fails closed.';

-- `create or replace` y no `drop` + `create`: el drop toma la tabla en modo
-- exclusivo y choca con el `pg_dump` de `test_production_shape.sh`, que otras
-- sesiones corren contra producción; crear o reemplazar pide SHARE ROW
-- EXCLUSIVE, que convive con él (2026-11-21).
create or replace trigger trg_payroll_vouchers_push_alert
  after insert on public.payroll_vouchers
  for each row
  when (new.status = 'draft')
  execute function public.invoke_push_notification_for_payroll_voucher();

comment on trigger trg_payroll_vouchers_push_alert on public.payroll_vouchers is
  'A payroll saved as a draft rings the phone of whoever pays it, so the transfers go out right away.';

commit;
