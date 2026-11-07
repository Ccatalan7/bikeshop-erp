-- Correo que trabaja: el resumen de la mañana en el celular (2026-11-06).
--
-- La propuesta aprobada pone el resumen de la mañana «en Inicio y en el
-- celular». Inicio lo lee desde 20261106260000; esto lo manda a los teléfonos
-- de la oficina a las 8:00 de cada tenant, de lunes a sábado, sólo si hay
-- algo que hacer y una sola vez por día:
--
-- * `mail_morning_summary_internal` es el cálculo, el mismo para Inicio
--   (`mail_morning_summary_v1`, que exige personal del taller) y para el aviso
--   (`push-notification`, con la llave de servicio).
-- * `dispatch_mail_morning_summary_v1` corre a las 11 y 12 UTC (las 8:00 de
--   Chile en horario de verano y de invierno) y, para cada tenant con casillas
--   encendidas cuya hora local es las 8, anota el día y encola el aviso por el
--   mismo camino que los pedidos web y las cotizaciones: el secreto vive en
--   Vault, sin secreto no se encola nada y un fallo nunca se propaga.
-- * Suena en administración, encargados, contabilidad y caja; no en los
--   teléfonos del taller.

begin;

create or replace function public.mail_morning_summary_internal(p_tenant uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := p_tenant;
  v_result jsonb;
begin
  with base as (
    select m as msg, m.received_at, m.kind, m.direction, m.facts,
           public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant and m.received_at > now() - interval '45 days'
  ), today as (
    select b.* from base b where public.mail_in_view_internal('today', b.msg, b.st)
  ), amounts as (
    select b.*, case when coalesce(b.facts->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
                     then (b.facts->>'amount')::numeric end as amount
      from base b
     where b.kind = 'transfer'
  )
  select jsonb_build_object(
    'today', (select count(*) from today),
    'payments', (select count(*) from today where st->>'action' = 'register_payment'),
    'payments_since', (select min(received_at) from today where st->>'action' = 'register_payment'),
    'payments_amount', (select coalesce(sum(a.amount), 0) from amounts a
                         where public.mail_in_view_internal('today', a.msg, a.st)),
    'invoices', (select count(*) from today where st->>'action' in ('register_purchase', 'register_expense')),
    'invoices_since', (select min(received_at) from today where st->>'action' in ('register_purchase', 'register_expense')),
    'statements', (select count(*) from today where st->>'action' = 'import_statement'),
    'statements_since', (select min(received_at) from today where st->>'action' = 'import_statement'),
    -- Un reclamo al que nos toca responder es un seguimiento, no un cliente:
    -- las líneas cuentan lo mismo que los grupos de «Para hoy».
    'customers', (select count(*) from today where st->>'action' = 'reply' and kind <> 'claim'),
    'customers_since', (select min(received_at) from today where st->>'action' = 'reply' and kind <> 'claim'),
    'follow_ups', (select count(*) from today where st->>'action' = 'remind' or kind = 'claim'),
    'follow_ups_since', (select min(received_at) from today where st->>'action' = 'remind' or kind = 'claim'),
    'reviews', (select count(*) from today where st->>'action' = 'reply_review'),
    'reviews_since', (select min(received_at) from today where st->>'action' = 'reply_review'),
    'security', (select count(*) from today where st->>'action' = 'review'),
    'security_since', (select min(received_at) from today where st->>'action' = 'review'),
    'transfers_24h', (select count(*) from amounts where received_at > now() - interval '24 hours'),
    'transfers_24h_amount', (select coalesce(sum(amount), 0) from amounts
                              where received_at > now() - interval '24 hours'),
    'transfers_24h_done', (select count(*) from amounts where received_at > now() - interval '24 hours'
                            and coalesce((st->>'done')::boolean, false)),
    'arrived_24h', (select count(*) from base where direction = 'in'
                     and received_at > now() - interval '24 hours' and kind not in ('promo', 'noise')),
    'archived_week', (select count(*) from base where direction = 'in'
                       and received_at > now() - interval '7 days' and kind in ('promo', 'noise'))
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.mail_morning_summary_v1()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
begin
  return public.mail_morning_summary_internal(public.mail_require_staff_internal());
end;
$$;

-- Un aviso por tenant y por día local, aunque el cron corra dos veces.
create table if not exists public.mail_morning_push_log (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  local_date date not null,
  queued_at timestamptz not null default now(),
  primary key (tenant_id, local_date)
);
alter table public.mail_morning_push_log enable row level security;
revoke all on public.mail_morning_push_log from anon, authenticated;
grant all on public.mail_morning_push_log to service_role;

create or replace function public.dispatch_mail_morning_summary_v1()
returns integer
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_tenant record;
  v_local timestamp;
  v_summary jsonb;
  v_secret text;
  v_queued integer := 0;
begin
  for v_tenant in
    select t.id, coalesce(nullif(t.timezone, ''), 'America/Santiago') as tz
      from public.tenants t
     where coalesce(t.is_active, true)
       and exists (select 1 from public.mail_mailboxes mb where mb.tenant_id = t.id and mb.is_active)
  loop
    begin
      v_local := now() at time zone v_tenant.tz;
      continue when extract(hour from v_local) <> 8 or extract(isodow from v_local) = 7;
      continue when exists (select 1 from public.mail_morning_push_log l
                             where l.tenant_id = v_tenant.id and l.local_date = v_local::date);
      v_summary := public.mail_morning_summary_internal(v_tenant.id);
      continue when coalesce((v_summary->>'today')::integer, 0) = 0;

      if v_secret is null then
        select secret.decrypted_secret into v_secret
          from vault.decrypted_secrets secret
         where secret.name = 'push_notification_webhook_secret'
           and nullif(secret.decrypted_secret, '') is not null
         order by secret.created_at desc
         limit 1;
      end if;
      if nullif(v_secret, '') is null then
        return v_queued;
      end if;

      insert into public.mail_morning_push_log (tenant_id, local_date)
      values (v_tenant.id, v_local::date)
      on conflict do nothing;

      perform net.http_post(
        url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/push-notification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-push-webhook-secret', v_secret
        ),
        body := jsonb_build_object(
          'type', 'MAIL_SUMMARY',
          'table', 'mail_messages',
          'schema', 'public',
          'record', jsonb_build_object('tenant_id', v_tenant.id)
        ),
        timeout_milliseconds := 5000
      );
      v_queued := v_queued + 1;
    exception
      when others then
        raise warning 'Mail morning summary could not be queued';
    end;
  end loop;
  return v_queued;
end;
$$;

revoke all on function public.mail_morning_summary_internal(uuid) from public, anon, authenticated;
grant execute on function public.mail_morning_summary_internal(uuid) to service_role;
revoke all on function public.mail_morning_summary_v1() from public, anon;
grant execute on function public.mail_morning_summary_v1() to authenticated;
revoke all on function public.dispatch_mail_morning_summary_v1() from public, anon, authenticated;
grant execute on function public.dispatch_mail_morning_summary_v1() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'vinabike_mail_morning_summary'$q$;
    execute $q$select cron.schedule('vinabike_mail_morning_summary', '0 11,12 * * *', 'select public.dispatch_mail_morning_summary_v1();')$q$;
  end if;
end;
$$;

commit;
