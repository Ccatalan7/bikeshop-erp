begin;

select plan(9);

-- Una nómina guardada como borrador suena en el teléfono de quien la paga
-- (20261121150000). Una nómina que no nace en borrador no suena, editarla no
-- vuelve a sonar, una vieja reinsertada (restaurar un respaldo) no suena, y
-- sin el secreto de Vault no se encola nada aunque la nómina se guarde igual.
--
-- La cola se lee igual en `pg_net` (cuerpo bytea) y en la base desechable de
-- `scripts/db/test_production_shape.sh` (cuerpo jsonb). El prefijo `\x` se
-- compara con `left()`: en un `like '\x%'` la barra escapa la x, y el cuerpo
-- bytea de `pg_net` nunca calza.

insert into public.tenants (id, shop_name) values
  ('a7a70000-0000-4000-8000-000000000001', 'Taller avisos de nómina');

create temporary view payroll_pushes as
  select body ->> 'type' as kind,
         body ->> 'table' as source_table,
         body -> 'record' ->> 'id' as voucher_id,
         body -> 'record' ->> 'tenant_id' as tenant_id
    from (
      select (case when left(to_jsonb(q) ->> 'body', 2) = '\x'
                   then convert_from(decode(substr(to_jsonb(q) ->> 'body', 3), 'hex'), 'UTF8')
                   else to_jsonb(q) ->> 'body' end)::jsonb as body
        from net.http_request_queue q
       where to_jsonb(q) ->> 'url' like '%/functions/v1/push-notification'
    ) sent
   where body -> 'record' ->> 'tenant_id' = 'a7a70000-0000-4000-8000-000000000001';

select ok(
  not has_function_privilege('anon', 'public.invoke_push_notification_for_payroll_voucher()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.invoke_push_notification_for_payroll_voucher()', 'EXECUTE'),
  'nobody calls the alert by hand');
select ok(
  exists (select 1 from pg_trigger
           where tgrelid = 'public.payroll_vouchers'::regclass
             and tgname = 'trg_payroll_vouchers_push_alert' and not tgisinternal),
  'a saved payroll rings the phone of whoever pays it');

-- Sin secreto: la nómina se guarda y no se encola nada.
insert into public.payroll_vouchers (id, tenant_id, voucher_number, period_start, period_end, period_label)
values ('a7a70000-0000-4000-8000-0000000000b1', 'a7a70000-0000-4000-8000-000000000001',
        'NOM-90001', '2026-11-09', '2026-11-15', 'Semana 46 · 09 – 15 nov');
select is((select count(*)::integer from payroll_pushes), 0, 'without the secret nothing is queued');
select is(
  (select status from public.payroll_vouchers where id = 'a7a70000-0000-4000-8000-0000000000b1'),
  'draft', 'and the payroll is saved anyway');

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

insert into public.payroll_vouchers (id, tenant_id, voucher_number, period_start, period_end, period_label)
values ('a7a70000-0000-4000-8000-0000000000b2', 'a7a70000-0000-4000-8000-000000000001',
        'NOM-90002', '2026-11-16', '2026-11-22', 'Semana 47 · 16 – 22 nov');
select is(
  (select string_agg(kind || ':' || source_table || ':' || voucher_id, ',') from payroll_pushes),
  'PAYROLL_VOUCHER:payroll_vouchers:a7a70000-0000-4000-8000-0000000000b2',
  'a payroll saved as a draft rings once, naming only the payroll and its tenant');

update public.payroll_vouchers
   set notes = 'Horas corregidas', total_amount = 120000
 where id = 'a7a70000-0000-4000-8000-0000000000b2';
select is((select count(*)::integer from payroll_pushes), 1, 'editing the draft does not ring again');

insert into public.payroll_vouchers (id, tenant_id, voucher_number, period_start, period_end, status)
values ('a7a70000-0000-4000-8000-0000000000b3', 'a7a70000-0000-4000-8000-000000000001',
        'NOM-90003', '2026-11-02', '2026-11-08', 'paid');
select is(
  (select count(*)::integer from payroll_pushes where voucher_id = 'a7a70000-0000-4000-8000-0000000000b3'),
  0, 'a payroll that is not born a draft does not ring');

-- Restaurar un respaldo reinserta borradores con el día en que se hicieron.
insert into public.payroll_vouchers (id, tenant_id, voucher_number, period_start, period_end, created_at, updated_at)
values ('a7a70000-0000-4000-8000-0000000000b4', 'a7a70000-0000-4000-8000-000000000001',
        'NOM-90004', '2026-10-19', '2026-10-25', now() - interval '27 days', now() - interval '27 days');
select is(
  (select count(*)::integer from payroll_pushes where voucher_id = 'a7a70000-0000-4000-8000-0000000000b4'),
  0, 'an old draft inserted again does not ring');

select is(
  (select tenant_id from payroll_pushes where voucher_id = 'a7a70000-0000-4000-8000-0000000000b2'),
  'a7a70000-0000-4000-8000-000000000001',
  'the request carries the tenant of the row');

select * from finish();
rollback;
