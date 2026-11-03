begin;

select plan(8);

-- Una cotización suena en el teléfono del equipo (20261103020000) cuando el
-- cliente la pide desde el sitio o pide cambios a la oferta. La que arma el
-- equipo no suena, mirar no suena, y sin el secreto de Vault no se encola
-- nada aunque la cotización se guarde igual.
--
-- La cola se lee igual en `pg_net` (cuerpo bytea) y en la base desechable de
-- `scripts/db/test_production_shape.sh` (cuerpo jsonb).

insert into public.tenants (id, shop_name) values
  ('c0c60000-0000-4000-8000-000000000001', 'Taller avisos de cotización');

insert into public.customer_quotes (
  id, tenant_id, quote_number, source, customer_name, customer_email, notify_email, notify_whatsapp
) values
  ('c0c60000-0000-4000-8000-0000000000a1', 'c0c60000-0000-4000-8000-000000000001',
   'COT-26-09001', 'web', 'Ana Pérez', 'ana@example.invalid', true, false),
  ('c0c60000-0000-4000-8000-0000000000a2', 'c0c60000-0000-4000-8000-000000000001',
   'COT-26-09002', 'staff', 'Luis Soto', 'luis@example.invalid', true, false);

create temporary view quote_pushes as
  select body ->> 'type' as kind, body ->> 'event' as event, body -> 'record' ->> 'id' as quote_id
    from (
      select (case when to_jsonb(q) ->> 'body' like '\x%'
                   then convert_from(decode(substr(to_jsonb(q) ->> 'body', 3), 'hex'), 'UTF8')
                   else to_jsonb(q) ->> 'body' end)::jsonb as body
        from net.http_request_queue q
       where to_jsonb(q) ->> 'url' like '%/functions/v1/push-notification'
    ) sent
   where body -> 'record' ->> 'id' in ('c0c60000-0000-4000-8000-0000000000a1',
                                        'c0c60000-0000-4000-8000-0000000000a2');

select ok(
  not has_function_privilege('anon', 'public.invoke_push_notification_for_customer_quote()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.invoke_push_notification_for_customer_quote()', 'EXECUTE'),
  'nobody calls the alert by hand');
select ok(
  exists (select 1 from pg_trigger
           where tgrelid = 'public.customer_quote_events'::regclass
             and tgname = 'trg_customer_quote_events_push_alert' and not tgisinternal),
  'the history of a quote rings the phones');

-- Sin secreto: la cotización se guarda y no se encola nada.
select public.customer_quote_log_internal(
  'c0c60000-0000-4000-8000-0000000000a1', 'requested', 'customer', null, 'web', null, null, '{}'::jsonb);
select is((select count(*)::integer from quote_pushes), 0, 'without the secret nothing is queued');
select is(
  (select count(*)::integer from public.customer_quote_events
    where quote_id = 'c0c60000-0000-4000-8000-0000000000a1' and event_type = 'requested'),
  1, 'and the quote keeps its history');

-- El secreto de prueba: en la base desechable `vault` es una tabla.
do $$
begin
  if to_regprocedure('vault.create_secret(text, text, text, uuid)') is not null then
    begin
      perform vault.create_secret('test-push-secret', 'push_notification_webhook_secret');
    exception when unique_violation then
      null;
    end;
  else
    insert into vault.decrypted_secrets (name, decrypted_secret)
    values ('push_notification_webhook_secret', 'test-push-secret');
  end if;
end;
$$;

select public.customer_quote_log_internal(
  'c0c60000-0000-4000-8000-0000000000a1', 'requested', 'customer', null, 'web', null, null, '{}'::jsonb);
select is(
  (select string_agg(kind || ':' || event, ',') from quote_pushes
    where quote_id = 'c0c60000-0000-4000-8000-0000000000a1'),
  'CUSTOMER_QUOTE:requested', 'a quote from the site rings once');

select public.customer_quote_log_internal(
  'c0c60000-0000-4000-8000-0000000000a2', 'requested', 'staff', null, 'erp', null, null, '{}'::jsonb);
select is(
  (select count(*)::integer from quote_pushes where quote_id = 'c0c60000-0000-4000-8000-0000000000a2'),
  0, 'one the team made at the counter does not ring');

select public.customer_quote_log_internal(
  'c0c60000-0000-4000-8000-0000000000a1', 'viewed', 'customer', null, 'web', null, null, '{}'::jsonb);
select is(
  (select count(*)::integer from quote_pushes where quote_id = 'c0c60000-0000-4000-8000-0000000000a1'),
  1, 'the customer looking at it does not ring');

select public.customer_quote_log_internal(
  'c0c60000-0000-4000-8000-0000000000a1', 'changes_requested', 'customer', null, 'web', null, null, '{}'::jsonb);
select is(
  (select string_agg(event, ',' order by event) from quote_pushes
    where quote_id = 'c0c60000-0000-4000-8000-0000000000a1'),
  'changes_requested,requested', 'asking for changes rings again');

select * from finish();
rollback;
