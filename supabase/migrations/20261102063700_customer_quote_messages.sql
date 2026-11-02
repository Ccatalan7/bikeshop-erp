-- Mensajes al cliente de una cotización (etapa 3 del plan
-- https://claude.ai/artifact/DNSj2Me7W9wxewsrt8V8sR).
--
-- Cada hito de la historia (`customer_quote_events`) deja su mensaje en
-- `customer_quote_messages`, una fila por cotización, tipo y oferta:
--   * received: «Recibimos tu cotización» (sólo por correo: a quien no ha
--     escrito por WhatsApp no se le puede escribir sin plantilla de Meta);
--   * offer: la oferta lista, con su enlace para aceptar, pedir cambios o
--     rechazar;
--   * reminder: la oferta vence pronto (`reminder_hours_before`);
--   * accepted: la confirmación de lo aceptado.
-- El correo lo manda el worker que ya manda los del pedido
-- (`send-transactional-order-email`, cada minuto) con el mismo remitente y la
-- marca del tema del sitio: no hay credenciales nuevas. El enlace se emite al
-- reclamar el mensaje y viaja sólo al worker; la base guarda su huella.
-- Por WhatsApp, mientras no exista una plantilla aprobada con enlace, el
-- mensaje queda «needs_staff»: el ERP avisa y el equipo lo manda con un clic
-- (`customer_quote_issue_link_v1`) y lo marca enviado. Si el cliente dejó
-- correo, la oferta va también por correo como respaldo.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create table if not exists public.customer_quote_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  offer_id uuid references public.customer_quote_offers(id) on delete restrict,
  kind text not null,
  channel text not null,
  recipient text not null,
  state text not null default 'pending',
  attempt_count integer not null default 0,
  max_attempts integer not null default 6,
  available_at timestamptz not null default clock_timestamp(),
  lease_owner text,
  lease_until timestamptz,
  provider text,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  sent_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint customer_quote_messages_kind check (kind in ('received', 'offer', 'reminder', 'accepted')),
  constraint customer_quote_messages_channel check (channel in ('email', 'whatsapp')),
  constraint customer_quote_messages_state check (
    state in ('pending', 'sending', 'sent', 'failed', 'needs_staff', 'skipped')
  ),
  constraint customer_quote_messages_attempts check (attempt_count >= 0 and max_attempts between 1 and 20),
  constraint customer_quote_messages_sent_shape check ((state = 'sent') = (sent_at is not null)),
  constraint customer_quote_messages_lease_shape check (
    (state = 'sending') = (lease_owner is not null and lease_until is not null)
  ),
  constraint customer_quote_messages_error check (last_error is null or length(last_error) <= 500),
  constraint customer_quote_messages_once unique nulls not distinct (quote_id, kind, offer_id, channel)
);

create index if not exists customer_quote_messages_due_idx
  on public.customer_quote_messages (tenant_id, available_at)
  where state in ('pending', 'sending') and channel = 'email';
create index if not exists customer_quote_messages_quote_idx
  on public.customer_quote_messages (quote_id, created_at);

comment on table public.customer_quote_messages is
  'Los mensajes al cliente de cada cotización (recibida, oferta, recordatorio, aceptada) por correo o WhatsApp, con su estado de envío y hora. Una fila por cotización, tipo, oferta y canal.';

alter table public.customer_quote_messages enable row level security;
revoke all on public.customer_quote_messages from public, anon, authenticated;
grant select on public.customer_quote_messages to authenticated;
drop policy if exists customer_quote_messages_tenant_read on public.customer_quote_messages;
create policy customer_quote_messages_tenant_read on public.customer_quote_messages
  for select to authenticated using (tenant_id = (select public.user_tenant_id()));

-- ---------------------------------------------------------------------------
-- Encolar
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_enqueue_message_internal(
  p_quote_id uuid,
  p_kind text,
  p_offer_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_count integer := 0;
  v_id uuid;
  v_channels text[];
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    return 0;
  end if;
  v_channels := case
    -- A quien eligió WhatsApp la oferta le llega por WhatsApp y, si dejó
    -- correo, también por correo como respaldo.
    when p_kind in ('offer', 'reminder') and v_quote.preferred_channel = 'whatsapp'
      then array_remove(array[
        'whatsapp',
        case when v_quote.customer_email is not null then 'email' end
      ], null)
    when p_kind in ('offer', 'reminder') then array['email']
    when v_quote.customer_email is not null then array['email']
    else array[]::text[]
  end;

  for i in 1 .. coalesce(array_length(v_channels, 1), 0) loop
    insert into public.customer_quote_messages (
      tenant_id, quote_id, offer_id, kind, channel, recipient, state
    ) values (
      v_quote.tenant_id, v_quote.id, p_offer_id, p_kind, v_channels[i],
      case v_channels[i] when 'email' then v_quote.customer_email else v_quote.customer_phone end,
      case v_channels[i] when 'email' then 'pending' else 'needs_staff' end
    )
    on conflict on constraint customer_quote_messages_once do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      perform public.customer_quote_log_internal(
        v_quote.id, 'message_queued', 'system', null, 'system', p_offer_id, null,
        jsonb_build_object('kind', p_kind, 'channel', v_channels[i], 'message_id', v_id)
      );
      if v_channels[i] = 'whatsapp' then
        perform public.customer_quote_notify_internal(
          v_quote.id,
          'customer_quote_whatsapp_pending',
          case p_kind
            when 'reminder' then 'Recordar la oferta por WhatsApp'
            else 'Enviar la oferta por WhatsApp'
          end,
          'customer_quote_message',
          v_id,
          'warning'
        );
      end if;
    end if;
    v_id := null;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.customer_quote_enqueue_message_internal(uuid, text, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.customer_quote_events_enqueue_messages()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.event_type = 'requested' and new.actor_kind = 'customer' then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'received', null);
  elsif new.event_type = 'offer_sent' then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'offer', new.offer_id);
  elsif new.event_type = 'accepted' then
    perform public.customer_quote_enqueue_message_internal(new.quote_id, 'accepted', new.offer_id);
  end if;
  return null;
end;
$$;

revoke all on function public.customer_quote_events_enqueue_messages()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customer_quote_events_enqueue_messages on public.customer_quote_events;
create trigger trg_customer_quote_events_enqueue_messages
  after insert on public.customer_quote_events
  for each row
  when (new.event_type in ('requested', 'offer_sent', 'accepted'))
  execute function public.customer_quote_events_enqueue_messages();

-- Una oferta que vence pronto se recuerda una vez.
create or replace function public.remind_customer_quote_offers_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in
    select q.id, q.current_offer_id
      from public.customer_quotes q
      left join public.customer_quote_settings s on s.tenant_id = q.tenant_id
     where q.status = 'offered'
       and q.reminder_sent_at is null
       and coalesce(s.reminder_hours_before, 24) > 0
       and q.expires_at > clock_timestamp()
       and q.expires_at <= clock_timestamp() + make_interval(hours => coalesce(s.reminder_hours_before, 24))
       -- Una oferta enviada hace poco no se recuerda (vigencias cortas).
       and q.offered_at <= clock_timestamp() - interval '6 hours'
     for update of q skip locked
  loop
    update public.customer_quotes set reminder_sent_at = clock_timestamp() where id = v_row.id;
    perform public.customer_quote_enqueue_message_internal(v_row.id, 'reminder', v_row.current_offer_id);
    perform public.customer_quote_log_internal(
      v_row.id, 'reminder_sent', 'system', null, 'system', v_row.current_offer_id
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.remind_customer_quote_offers_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.remind_customer_quote_offers_v1() to service_role;

-- ---------------------------------------------------------------------------
-- El worker de correo (service_role)
-- ---------------------------------------------------------------------------

-- Lo que el correo dibuja de una cotización: la tienda con su marca, el
-- remitente, el cliente, la oferta con sus líneas y el enlace recién emitido.
create or replace function public.customer_quote_email_payload_internal(p_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message public.customer_quote_messages%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_store_url text;
  v_access jsonb;
  v_offer_id uuid;
begin
  select * into v_message from public.customer_quote_messages where id = p_message_id;
  select * into v_quote from public.customer_quotes where id = v_message.quote_id;
  select * into v_tenant from public.tenants where id = v_quote.tenant_id;
  select * into v_settings from public.transactional_email_settings where tenant_id = v_quote.tenant_id;
  v_store_url := public.transactional_email_store_url(v_settings.public_store_url, v_tenant.custom_domain);
  v_offer_id := coalesce(v_message.offer_id, v_quote.current_offer_id);
  v_access := public.customer_quote_issue_token_internal(
    v_quote.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
  );

  return jsonb_build_object(
    'messageId', v_message.id,
    'kind', v_message.kind,
    'recipient', v_message.recipient,
    'sender', jsonb_strip_nulls(jsonb_build_object(
      'enabled', coalesce(v_settings.enabled, false) and v_settings.delivery_mode = 'send',
      'name', v_settings.from_name,
      'email', v_settings.from_email,
      'replyTo', v_settings.reply_to_email
    )),
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value from public.website_settings setting
           where setting.tenant_id = v_quote.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = v_quote.tenant_id and setting.key = 'theme_primary_color'
         limit 1
      )
    )),
    'quote', jsonb_strip_nulls(jsonb_build_object(
      'number', v_quote.quote_number,
      'status', v_quote.status,
      'customerName', v_quote.customer_name,
      'requestedAt', v_quote.requested_at,
      'expiresAt', v_quote.expires_at
    )),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object('name', l.product_name, 'quantity', l.quantity) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = v_quote.id
    ), '[]'::jsonb),
    'offer', (
      select jsonb_strip_nulls(jsonb_build_object(
        'number', o.offer_no,
        'validUntil', o.valid_until,
        'subtotal', o.subtotal,
        'taxAmount', o.tax_amount,
        'total', o.total,
        'notes', o.notes_to_customer,
        'lines', coalesce((
          select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
            'name', ol.product_name,
            'availability', ol.availability,
            'quantityRequested', ol.quantity_requested,
            'quantity', ol.quantity_offered,
            'unitPrice', ol.unit_price,
            'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
            'leadDaysMin', ol.lead_days_min,
            'leadDaysMax', ol.lead_days_max,
            'note', ol.customer_note
          )) order by ol.line_no)
            from public.customer_quote_offer_lines ol where ol.offer_id = o.id
        ), '[]'::jsonb)
      ))
        from public.customer_quote_offers o
       where o.id = v_offer_id and o.status <> 'draft'
    ),
    'prepayPercent', (public.customer_quote_settings_internal(v_quote.tenant_id)).on_order_prepay_percent,
    'link', case
      when v_store_url is null then null
      else rtrim(v_store_url, '/') || '/cotizacion#t=' || (v_access ->> 'token')
    end
  );
end;
$$;

revoke all on function public.customer_quote_email_payload_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.claim_customer_quote_messages_v1(
  p_tenant_id uuid,
  p_worker_id text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
begin
  if p_tenant_id is null or nullif(btrim(coalesce(p_worker_id, '')), '') is null then
    raise exception 'A tenant and a worker id are required' using errcode = '22023';
  end if;
  with due as (
    select m.id
      from public.customer_quote_messages m
     where m.tenant_id = p_tenant_id
       and m.channel = 'email'
       and m.attempt_count < m.max_attempts
       and m.available_at <= clock_timestamp()
       and (m.state = 'pending' or (m.state = 'sending' and m.lease_until < clock_timestamp()))
     order by m.available_at
     limit greatest(1, least(coalesce(p_limit, 10), 25))
     for update skip locked
  ), leased as (
    update public.customer_quote_messages m
       set state = 'sending',
           lease_owner = p_worker_id,
           lease_until = clock_timestamp() + interval '120 seconds',
           attempt_count = m.attempt_count + 1,
           updated_at = clock_timestamp()
      from due
     where m.id = due.id
    returning m.id
  )
  select array_agg(leased.id) into v_ids from leased;
  return coalesce((
    select jsonb_agg(public.customer_quote_email_payload_internal(id))
      from unnest(coalesce(v_ids, array[]::uuid[])) as id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.claim_customer_quote_messages_v1(uuid, text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_customer_quote_messages_v1(uuid, text, integer) to service_role;

comment on function public.claim_customer_quote_messages_v1(uuid, text, integer) is
  'El worker de correo toma hasta 25 correos de cotización vencidos de ese taller (los arrienda 120 s) y recibe lo que cada uno dibuja, con un enlace recién emitido.';

create or replace function public.complete_customer_quote_message_v1(
  p_message_id uuid,
  p_worker_id text,
  p_outcome text,
  p_provider_message_id text default null,
  p_error text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message public.customer_quote_messages%rowtype;
begin
  select * into v_message from public.customer_quote_messages
   where id = p_message_id and lease_owner = p_worker_id and state = 'sending'
   for update;
  if not found then
    return 'not_leased';
  end if;
  if p_outcome = 'sent' then
    update public.customer_quote_messages
       set state = 'sent', sent_at = clock_timestamp(), provider = 'resend',
           provider_message_id = left(p_provider_message_id, 200),
           lease_owner = null, lease_until = null, last_error = null, updated_at = clock_timestamp()
     where id = p_message_id;
  elsif p_outcome = 'retry' and v_message.attempt_count < v_message.max_attempts then
    update public.customer_quote_messages
       set state = 'pending', lease_owner = null, lease_until = null,
           available_at = clock_timestamp() + make_interval(mins => least(60, 2 ^ v_message.attempt_count)::integer),
           last_error = left(p_error, 500), updated_at = clock_timestamp()
     where id = p_message_id;
  elsif p_outcome = 'skipped' then
    update public.customer_quote_messages
       set state = 'skipped', lease_owner = null, lease_until = null,
           last_error = left(p_error, 500), updated_at = clock_timestamp()
     where id = p_message_id;
  else
    update public.customer_quote_messages
       set state = 'failed', lease_owner = null, lease_until = null,
           last_error = left(coalesce(p_error, 'failed'), 500), updated_at = clock_timestamp()
     where id = p_message_id;
    perform public.customer_quote_notify_internal(
      v_message.quote_id, 'customer_quote_message_failed', 'No salió el correo de la cotización',
      'customer_quote_message', v_message.id, 'warning'
    );
  end if;
  return (select state from public.customer_quote_messages where id = p_message_id);
end;
$$;

revoke all on function public.complete_customer_quote_message_v1(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_customer_quote_message_v1(uuid, text, text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- El equipo: el enlace para mandarlo a mano y marcarlo enviado
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_issue_link_v1(p_tenant_id uuid, p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_quote public.customer_quotes%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_access jsonb;
  v_store_url text;
begin
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  select * into v_tenant from public.tenants where id = p_tenant_id;
  select * into v_settings from public.transactional_email_settings where tenant_id = p_tenant_id;
  v_store_url := coalesce(
    public.transactional_email_store_url(v_settings.public_store_url, v_tenant.custom_domain),
    'https://vinabike.cl'
  );
  v_access := public.customer_quote_issue_token_internal(
    v_quote.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days', v_actor
  );
  return jsonb_build_object(
    'url', rtrim(v_store_url, '/') || '/cotizacion#t=' || (v_access ->> 'token'),
    'expires_at', v_access ->> 'expires_at'
  );
end;
$$;

revoke all on function public.customer_quote_issue_link_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_issue_link_v1(uuid, uuid) to authenticated;

comment on function public.customer_quote_issue_link_v1(uuid, uuid) is
  'Un enlace nuevo de 60 días para que el equipo mande la cotización por WhatsApp o lo copie. Sólo se guarda su huella.';

create or replace function public.customer_quote_mark_message_sent_v1(
  p_tenant_id uuid,
  p_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_message public.customer_quote_messages%rowtype;
begin
  select * into v_message from public.customer_quote_messages m
   where m.id = p_message_id and m.tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Message not found or not accessible' using errcode = 'P0002';
  end if;
  if v_message.state = 'needs_staff' then
    update public.customer_quote_messages
       set state = 'sent', sent_at = clock_timestamp(), sent_by = v_actor,
           provider = 'staff', updated_at = clock_timestamp()
     where id = p_message_id;
    perform public.customer_quote_log_internal(
      v_message.quote_id, 'note', 'staff', v_actor, 'whatsapp', v_message.offer_id, null,
      jsonb_build_object('message', 'sent_by_staff', 'kind', v_message.kind, 'message_id', v_message.id)
    );
    update public.erp_notifications
       set read_at = coalesce(read_at, clock_timestamp())
     where tenant_id = p_tenant_id
       and type = 'customer_quote_whatsapp_pending'
       and entity_type = 'customer_quote_message'
       and entity_id = p_message_id;
  end if;
  return public.customer_quote_detail_v1(p_tenant_id, v_message.quote_id);
end;
$$;

revoke all on function public.customer_quote_mark_message_sent_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_mark_message_sent_v1(uuid, uuid) to authenticated;

-- El detalle del ERP muestra también los mensajes (mismo cuerpo que
-- 20261102041700 más la clave `messages`).
create or replace function public.customer_quote_detail_v1(p_tenant_id uuid, p_quote_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_draft uuid;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  select o.id into v_draft from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.status = 'draft';

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'request_idempotency_key',
    'settings', to_jsonb(public.customer_quote_settings_internal(p_tenant_id)),
    'requested', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no)
                             from public.customer_quote_lines l where l.quote_id = p_quote_id), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(to_jsonb(o) || jsonb_build_object(
        'lines', coalesce((
          select jsonb_agg(to_jsonb(ol) || jsonb_build_object(
            'supplier_name', s.name,
            'stock_now', p.inventory_qty
          ) order by ol.line_no)
            from public.customer_quote_offer_lines ol
            left join public.suppliers s on s.id = ol.supplier_id
            left join public.products p on p.id = ol.product_id
           where ol.offer_id = o.id
        ), '[]'::jsonb)
      ) order by o.offer_no desc)
        from public.customer_quote_offers o
       where o.quote_id = p_quote_id and o.status <> 'cancelled'
    ), '[]'::jsonb),
    'draftOfferId', v_draft,
    'tasks', coalesce((
      select jsonb_agg(to_jsonb(t) || jsonb_build_object(
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone
      ) order by t.created_at)
        from public.customer_quote_supplier_tasks t
        left join public.suppliers s on s.id = t.supplier_id
       where t.quote_id = p_quote_id and t.status <> 'cancelled'
    ), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'kind', m.kind, 'channel', m.channel, 'recipient', m.recipient,
        'state', m.state, 'sent_at', m.sent_at, 'created_at', m.created_at,
        'offer_id', m.offer_id, 'last_error', m.last_error
      ) order by m.created_at)
        from public.customer_quote_messages m where m.quote_id = p_quote_id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.id)
        from public.customer_quote_events e where e.quote_id = p_quote_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.customer_quote_detail_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_detail_v1(uuid, uuid) to authenticated;

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; quote reminders were not scheduled';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'vinabike_remind_customer_quote_offers'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_remind_customer_quote_offers',
    '13 * * * *',
    $job$select public.remind_customer_quote_offers_v1()$job$
  );
end
$$;

commit;
