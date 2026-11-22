-- El pedido abierto de un proveedor sale solo en la mañana, con su PDF.
--
-- El dueño, 2026-11-21, sobre el pedido abierto por proveedor
-- (20261122010000): «Conviene seguir acumulando hasta la mañana siguiente y
-- ahí enviarlo en la mañana, que lo procesen rápido … y que ahí después lo
-- envíen como a las 3». Lo vendido a pedido se junta en el borrador del
-- proveedor (PED) y, el primer día hábil a la hora de envío del proveedor
-- (09:30 si nadie la cambia), la base se lo manda por WhatsApp con su PDF y
-- lo deja «Enviado». Lo que se paga después de esa hora abre el pedido del
-- día hábil siguiente.
--
-- * Días hábiles: lunes a viernes menos los feriados nacionales de Chile
--   (`chile_public_holidays`: 2026 y 2027 sembrados de date.nager.at y
--   contrastados con la prensa; cada hora se piden los años que falten y,
--   el día 1 de cada mes, el año en curso y el siguiente, por si una ley
--   agrega uno). Un pedido atrasado sale el primer día hábil a su hora, nunca
--   de noche.
-- * La hora es de cada proveedor (`suppliers.order_send_time`, entre 07:00 y
--   20:00); sin hora, el pedido lo manda una persona desde «Enviar al
--   proveedor».
-- * El PDF lo dibuja el servidor de la tienda (`POST /cuenta/aviso.pdf`) con
--   un código de un solo uso (`supplier_order_document_tokens`, sólo su
--   huella), como los avisos del taller (20261107130000), con el mismo dibujo
--   que adjunta el asistente de compras (`buildPurchaseOrderPdf`). Viaja en la
--   plantilla aprobada `documento_adjunto_v1` («Hola {{1}}, te enviamos el
--   documento adjunto desde Viñabike…»): sirve dentro y fuera de las 24 h.
-- * Al encolar el mensaje el pedido queda «Enviado»: lo que se pague después
--   ya no entra en él. Si WhatsApp no lo entrega, vuelve a borrador y avisa.
--   Un pedido enviado no vuelve a borrador desde una app (la guardia): quien
--   lo tenía abierto en el asistente recibe el motivo.
-- * Cada envío, logrado o no, deja su fila (`supplier_order_dispatches`), un
--   aviso en el ERP y suena en el teléfono de quien compra.
--
-- Se enciende por tienda (`company_settings.supplier_order_auto_send_enabled
-- = 'true'`) después de desplegar la tienda y whatsapp-send: un envío nunca
-- pide un PDF que nadie sabe dibujar.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------------------
-- 1. Los días hábiles de Chile
-- ---------------------------------------------------------------------------

create table if not exists public.chile_public_holidays (
  holiday_date date primary key,
  name text not null,
  source text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint chile_public_holidays_name check (char_length(btrim(name)) between 1 and 120)
);

comment on table public.chile_public_holidays is
  'Feriados nacionales de Chile (sin los regionales). Un día hábil es de lunes a viernes y no está aquí: lo usa el envío de la mañana del pedido a proveedor (20261122030000).';

alter table public.chile_public_holidays enable row level security;
revoke all on public.chile_public_holidays from public, anon, authenticated;
grant select on public.chile_public_holidays to authenticated;
grant all on public.chile_public_holidays to service_role;
drop policy if exists chile_public_holidays_read on public.chile_public_holidays;
create policy chile_public_holidays_read on public.chile_public_holidays
  for select to authenticated using (true);

insert into public.chile_public_holidays (holiday_date, name, source) values
  ('2026-01-01', 'Año Nuevo', 'date.nager.at; prensa 2026-11-22'),
  ('2026-04-03', 'Viernes Santo', 'date.nager.at; prensa 2026-11-22'),
  ('2026-04-04', 'Sábado Santo', 'date.nager.at; prensa 2026-11-22'),
  ('2026-05-01', 'Día del Trabajo', 'date.nager.at; prensa 2026-11-22'),
  ('2026-05-21', 'Día de las Glorias Navales', 'date.nager.at; prensa 2026-11-22'),
  ('2026-06-21', 'Día Nacional de los Pueblos Indígenas', 'date.nager.at; prensa 2026-11-22'),
  ('2026-06-29', 'San Pedro y San Pablo', 'date.nager.at; prensa 2026-11-22'),
  ('2026-07-16', 'Virgen del Carmen', 'date.nager.at; prensa 2026-11-22'),
  ('2026-08-15', 'Asunción de la Virgen', 'date.nager.at; prensa 2026-11-22'),
  ('2026-09-18', 'Fiestas Patrias', 'date.nager.at; prensa 2026-11-22'),
  ('2026-09-19', 'Día de las Glorias del Ejército', 'date.nager.at; prensa 2026-11-22'),
  ('2026-10-12', 'Encuentro de Dos Mundos', 'date.nager.at; prensa 2026-11-22'),
  ('2026-10-31', 'Día de las Iglesias Evangélicas y Protestantes', 'date.nager.at; prensa 2026-11-22'),
  ('2026-11-01', 'Día de Todos los Santos', 'date.nager.at; prensa 2026-11-22'),
  ('2026-12-08', 'Inmaculada Concepción', 'date.nager.at; prensa 2026-11-22'),
  ('2026-12-25', 'Navidad', 'date.nager.at; prensa 2026-11-22'),
  ('2027-01-01', 'Año Nuevo', 'date.nager.at 2026-11-22'),
  ('2027-03-26', 'Viernes Santo', 'date.nager.at 2026-11-22'),
  ('2027-03-27', 'Sábado Santo', 'date.nager.at 2026-11-22'),
  ('2027-05-01', 'Día del Trabajo', 'date.nager.at 2026-11-22'),
  ('2027-05-21', 'Día de las Glorias Navales', 'date.nager.at 2026-11-22'),
  ('2027-06-21', 'Día Nacional de los Pueblos Indígenas', 'date.nager.at 2026-11-22'),
  ('2027-06-28', 'San Pedro y San Pablo', 'date.nager.at 2026-11-22'),
  ('2027-07-16', 'Virgen del Carmen', 'date.nager.at 2026-11-22'),
  ('2027-08-15', 'Asunción de la Virgen', 'date.nager.at 2026-11-22'),
  ('2027-09-17', 'Feriado adicional de Fiestas Patrias', 'date.nager.at 2026-11-22'),
  ('2027-09-18', 'Fiestas Patrias', 'date.nager.at 2026-11-22'),
  ('2027-09-19', 'Día de las Glorias del Ejército', 'date.nager.at 2026-11-22'),
  ('2027-10-11', 'Encuentro de Dos Mundos', 'date.nager.at 2026-11-22'),
  ('2027-10-31', 'Día de las Iglesias Evangélicas y Protestantes', 'date.nager.at 2026-11-22'),
  ('2027-11-01', 'Día de Todos los Santos', 'date.nager.at 2026-11-22'),
  ('2027-12-08', 'Inmaculada Concepción', 'date.nager.at 2026-11-22'),
  ('2027-12-25', 'Navidad', 'date.nager.at 2026-11-22')
on conflict (holiday_date) do nothing;

create or replace function public.chile_business_day_internal(p_day date)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_day is not null
     and extract(isodow from p_day) < 6
     and not exists (
       select 1 from public.chile_public_holidays holiday
        where holiday.holiday_date = p_day
     );
$$;

revoke all on function public.chile_business_day_internal(date)
  from public, anon, authenticated;
grant execute on function public.chile_business_day_internal(date) to service_role;

-- Los años que faltan se piden a date.nager.at por pg_net; la respuesta llega
-- después del commit y la recoge la pasada siguiente. Si nunca llega, un año
-- sin feriados se trata como de lunes a viernes: el pedido sale igual.
create table if not exists public.chile_public_holiday_requests (
  request_id bigint primary key,
  year integer not null,
  requested_at timestamptz not null default clock_timestamp(),
  collected_at timestamptz,
  outcome text
);

alter table public.chile_public_holiday_requests enable row level security;
revoke all on public.chile_public_holiday_requests from public, anon, authenticated;
grant all on public.chile_public_holiday_requests to service_role;

create or replace function public.chile_public_holidays_refresh_internal(
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = public, net, pg_temp
as $$
declare
  v_request record;
  v_payload jsonb;
  v_added integer := 0;
  v_count integer;
  v_year integer;
  v_this_year integer := extract(year from (p_now at time zone 'America/Santiago'))::integer;
  v_first_of_month boolean := extract(day from (p_now at time zone 'America/Santiago')) = 1;
  v_asked integer := 0;
  v_id bigint;
begin
  if to_regclass('net._http_response') is null then
    return jsonb_build_object('skipped', 'pg_net unavailable');
  end if;

  -- 1. Lo que contestó date.nager.at.
  for v_request in
    select request.request_id, request.year, request.requested_at,
           response.status_code, response.content, response.timed_out, response.error_msg
      from public.chile_public_holiday_requests request
      left join net._http_response response on response.id = request.request_id
     where request.collected_at is null
  loop
    if v_request.status_code = 200 then
      begin
        v_payload := v_request.content::jsonb;
      exception when others then
        v_payload := null;
      end;
      if jsonb_typeof(v_payload) = 'array' then
        insert into public.chile_public_holidays (holiday_date, name, source)
        select (holiday.value ->> 'date')::date,
               left(btrim(holiday.value ->> 'localName'), 120),
               'date.nager.at ' || to_char(p_now at time zone 'America/Santiago', 'YYYY-MM-DD')
          from jsonb_array_elements(v_payload) holiday
         where holiday.value ->> 'date' ~ '^\d{4}-\d{2}-\d{2}$'
           and substr(holiday.value ->> 'date', 1, 4)::integer = v_request.year
           and lower(coalesce(holiday.value ->> 'global', 'false')) = 'true'
           and nullif(btrim(holiday.value ->> 'localName'), '') is not null
        on conflict (holiday_date) do nothing;
        get diagnostics v_count = row_count;
        v_added := v_added + v_count;
      end if;
      update public.chile_public_holiday_requests
         set collected_at = p_now,
             outcome = case when jsonb_typeof(v_payload) = 'array' then 'ok' else 'unreadable' end
       where request_id = v_request.request_id;
    elsif v_request.status_code is not null or v_request.timed_out
          or v_request.error_msg is not null
          or v_request.requested_at < p_now - interval '1 day' then
      update public.chile_public_holiday_requests
         set collected_at = p_now,
             outcome = left(coalesce('http ' || v_request.status_code::text,
                                     v_request.error_msg, 'no answer'), 120)
       where request_id = v_request.request_id;
    end if;
  end loop;

  -- 2. Los años que faltan; el día 1, también los que ya están.
  foreach v_year in array array[v_this_year, v_this_year + 1] loop
    if (
         not exists (
           select 1 from public.chile_public_holidays holiday
            where holiday.holiday_date between make_date(v_year, 1, 1) and make_date(v_year, 12, 31)
         )
         or v_first_of_month
       )
       and not exists (
         select 1 from public.chile_public_holiday_requests request
          where request.year = v_year
            and request.requested_at > p_now - interval '20 hours'
       ) then
      v_id := net.http_get(
        url := format('https://date.nager.at/api/v3/PublicHolidays/%s/CL', v_year),
        timeout_milliseconds := 10000
      );
      insert into public.chile_public_holiday_requests (request_id, year, requested_at)
      values (v_id, v_year, p_now)
      on conflict (request_id) do nothing;
      v_asked := v_asked + 1;
    end if;
  end loop;

  delete from public.chile_public_holiday_requests
   where collected_at < p_now - interval '60 days';

  return jsonb_build_object('added', v_added, 'asked', v_asked);
end;
$$;

revoke all on function public.chile_public_holidays_refresh_internal(timestamptz)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. La hora de envío de cada proveedor
-- ---------------------------------------------------------------------------

alter table public.suppliers
  add column if not exists order_send_time time default time '09:30';

alter table public.suppliers
  drop constraint if exists suppliers_order_send_time_hours;
alter table public.suppliers
  add constraint suppliers_order_send_time_hours
  check (order_send_time is null or order_send_time between time '07:00' and time '20:00');

comment on column public.suppliers.order_send_time is
  'A qué hora de un día hábil le sale solo su pedido abierto (lo vendido a pedido), por WhatsApp con su PDF (20261122030000). Null: lo manda una persona desde «Enviar al proveedor».';

-- La primera hora de envío de un día hábil después de [p_after], en la hora
-- de Chile.
create or replace function public.supplier_order_next_send_at_internal(
  p_after timestamptz,
  p_send_time time
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_day date;
  v_at timestamptz;
begin
  if p_after is null or p_send_time is null then
    return null;
  end if;
  v_day := (p_after at time zone 'America/Santiago')::date;
  for v_step in 0..60 loop
    if public.chile_business_day_internal(v_day) then
      v_at := (v_day + p_send_time) at time zone 'America/Santiago';
      if v_at > p_after then
        return v_at;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return null;
end;
$$;

revoke all on function public.supplier_order_next_send_at_internal(timestamptz, time)
  from public, anon, authenticated;

-- Se enciende por tienda, después de desplegar la tienda y whatsapp-send.
create or replace function public.supplier_order_auto_send_enabled_internal(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select btrim(setting.value) = 'true'
      from public.company_settings setting
     where setting.tenant_id = p_tenant_id
       and setting.key = 'supplier_order_auto_send_enabled'
     limit 1
  ), false);
$$;

revoke all on function public.supplier_order_auto_send_enabled_internal(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Cada envío de la mañana
-- ---------------------------------------------------------------------------

-- Fuera del respaldo a propósito, como los avisos del taller: restaurar no
-- debe volver a mandar ni a contar un envío.
create table if not exists public.supplier_order_dispatches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  purchase_invoice_id uuid not null,
  due_at timestamptz not null,
  state text not null default 'queued',
  reason text,
  message_id uuid,
  conversation_id uuid,
  order_count integer not null default 0,
  line_count integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  settled_at timestamptz,
  constraint supplier_order_dispatches_state
    check (state in ('queued', 'sent', 'failed', 'skipped', 'unknown')),
  constraint supplier_order_dispatches_counts check (order_count >= 0 and line_count >= 0)
);

create index if not exists supplier_order_dispatches_invoice
  on public.supplier_order_dispatches (tenant_id, purchase_invoice_id, due_at desc);
create index if not exists supplier_order_dispatches_open
  on public.supplier_order_dispatches (created_at)
  where state in ('queued', 'sent');

comment on table public.supplier_order_dispatches is
  'Cada envío automático del pedido abierto de un proveedor (20261122030000): queued (en la cola de WhatsApp, el pedido ya «Enviado»), sent, failed (no llegó: el pedido volvió a borrador), skipped (no salió: falta teléfono, canal o plantilla) o unknown (WhatsApp no dijo).';

alter table public.supplier_order_dispatches enable row level security;
revoke all on public.supplier_order_dispatches from public, anon, authenticated;
grant select on public.supplier_order_dispatches to authenticated;
grant all on public.supplier_order_dispatches to service_role;
drop policy if exists supplier_order_dispatches_read on public.supplier_order_dispatches;
create policy supplier_order_dispatches_read on public.supplier_order_dispatches
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

-- ---------------------------------------------------------------------------
-- 4. El PDF: el código de un solo uso y lo que lee la tienda
-- ---------------------------------------------------------------------------

create table if not exists public.supplier_order_document_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  dispatch_id uuid not null references public.supplier_order_dispatches(id) on delete cascade,
  purchase_invoice_id uuid not null,
  token_sha256 text not null,
  expires_at timestamptz not null,
  reads integer not null default 0,
  last_read_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  constraint supplier_order_document_tokens_hash check (token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint supplier_order_document_tokens_hash_key unique (token_sha256),
  constraint supplier_order_document_tokens_reads check (reads >= 0)
);

create index if not exists supplier_order_document_tokens_dispatch
  on public.supplier_order_document_tokens (dispatch_id);

comment on table public.supplier_order_document_tokens is
  'El código de un solo uso con que la tienda dibuja el PDF del pedido que sale solo en la mañana (20261122030000). Sólo su huella; vence en dos días.';

alter table public.supplier_order_document_tokens enable row level security;
revoke all on public.supplier_order_document_tokens from public, anon, authenticated;
grant all on public.supplier_order_document_tokens to service_role;

create or replace function public.supplier_order_document_token_internal(
  p_dispatch public.supplier_order_dispatches
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_raw text := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
begin
  insert into public.supplier_order_document_tokens (
    tenant_id, dispatch_id, purchase_invoice_id, token_sha256, expires_at
  ) values (
    p_dispatch.tenant_id,
    p_dispatch.id,
    p_dispatch.purchase_invoice_id,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '2 days'
  );
  return v_raw;
end;
$$;

revoke all on function public.supplier_order_document_token_internal(public.supplier_order_dispatches)
  from public, anon, authenticated, service_role;

-- El pedido como lo dibuja el PDF (`PurchaseOrderDocument.fromProjection`):
-- sus líneas tal como están guardadas, quién pide y a quién. Los números los
-- formatea el núcleo compartido, el mismo del asistente de compras.
create or replace function public.purchase_order_document_projection_internal(
  p_purchase_invoice_id uuid,
  p_tenant_id uuid,
  p_issued_at timestamptz
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'order_number', invoice.invoice_number,
    'issued_at', p_issued_at,
    'buyer', jsonb_build_object(
      'city', nullif(btrim(regexp_replace(
        coalesce(public.workshop_notice_location_internal(invoice.tenant_id) ->> 'address', ''),
        '^.*,', '')), '')
    ),
    'storefront', public.storefront_identity_internal(invoice.tenant_id),
    'supplier', jsonb_build_object(
      'name', coalesce(nullif(btrim(supplier.name), ''), invoice.supplier_name),
      'legal_name', nullif(btrim(supplier.legal_name), ''),
      'rut', coalesce(nullif(btrim(supplier.rut), ''), nullif(btrim(invoice.supplier_rut), '')),
      'contact', nullif(concat_ws(' · ',
        nullif(btrim(supplier.sales_rep_name), ''),
        nullif(btrim(supplier.sales_rep_phone), ''),
        nullif(btrim(supplier.sales_rep_email), '')), ''),
      'payment_terms', supplier.payment_terms
    ),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
          'product_id', line.value ->> 'product_id',
          'name', coalesce(nullif(btrim(line.value ->> 'product_name'), ''),
                           nullif(btrim(line.value ->> 'description'), ''), 'Producto'),
          'sku', nullif(btrim(line.value ->> 'product_sku'), ''),
          'quantity', coalesce((line.value ->> 'quantity')::numeric, 0),
          'unit_cost', coalesce((line.value ->> 'unit_cost')::numeric, 0))
        order by line.ordinality)
        from jsonb_array_elements(
          case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
        ) with ordinality as line(value, ordinality)
    ), '[]'::jsonb),
    'note', nullif(btrim(invoice.notes), '')
  )
    from public.purchase_invoices invoice
    left join public.suppliers supplier
      on supplier.id = invoice.supplier_id
     and supplier.tenant_id = invoice.tenant_id
   where invoice.id = p_purchase_invoice_id
     and invoice.tenant_id = p_tenant_id;
$$;

revoke all on function public.purchase_order_document_projection_internal(uuid, uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- Lo que lee la tienda con el código: el presupuesto o el comprobante de un
-- aviso del taller (20261107130000) o, desde 20261122030000, el pedido de la
-- mañana. Un código vencido, gastado (diez lecturas: un envío con sus
-- reintentos) o desconocido no dice nada.
create or replace function public.workshop_notice_document_v1(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
  v_row public.workshop_notice_document_tokens%rowtype;
  v_order_token public.supplier_order_document_tokens%rowtype;
  v_notice public.workshop_customer_notices%rowtype;
  v_document_id uuid;
  v_quote jsonb;
  v_order jsonb;
begin
  if coalesce(p_token, '') !~ '^[A-Za-z0-9_-]{43}$' then
    return null;
  end if;
  v_hash := encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex');

  select * into v_row
    from public.workshop_notice_document_tokens token
   where token.token_sha256 = v_hash
   for update;
  if not found then
    -- El pedido de la mañana a un proveedor.
    select * into v_order_token
      from public.supplier_order_document_tokens token
     where token.token_sha256 = v_hash
     for update;
    if not found or v_order_token.expires_at <= clock_timestamp() or v_order_token.reads >= 10 then
      return null;
    end if;
    update public.supplier_order_document_tokens
       set reads = reads + 1, last_read_at = clock_timestamp()
     where id = v_order_token.id;
    v_order := public.purchase_order_document_projection_internal(
      v_order_token.purchase_invoice_id, v_order_token.tenant_id, v_order_token.created_at);
    if v_order is null or jsonb_array_length(v_order -> 'lines') = 0 then
      return null;
    end if;
    return jsonb_build_object('kind', 'supplier_order', 'document', v_order);
  end if;

  if v_row.expires_at <= clock_timestamp() or v_row.reads >= 10 then
    return null;
  end if;
  update public.workshop_notice_document_tokens
     set reads = reads + 1, last_read_at = clock_timestamp()
   where id = v_row.id;

  if v_row.kind = 'delivery' then
    select document.id into v_document_id
      from public.mechanic_job_delivery_documents document
     where document.tenant_id = v_row.tenant_id
       and document.job_id = v_row.job_id;
    if v_document_id is null then
      return null;
    end if;
    return jsonb_build_object(
      'kind', 'delivery',
      'document', public.job_delivery_document_projection_internal(v_document_id));
  end if;

  select * into v_notice
    from public.workshop_customer_notices notice
   where notice.id = v_row.notice_id
     and notice.tenant_id = v_row.tenant_id;
  v_quote := public.job_quote_document_projection_internal(v_row.job_id, v_row.tenant_id);
  if v_quote is null then
    return null;
  end if;
  return jsonb_build_object(
    'kind', 'quote',
    'document', v_quote || jsonb_build_object('issued_at', coalesce(v_notice.source_at, v_row.created_at)));
end;
$$;

revoke all on function public.workshop_notice_document_v1(text) from public;
grant execute on function public.workshop_notice_document_v1(text) to anon, authenticated, service_role;

comment on function public.workshop_notice_document_v1(text) is
  'El PDF que viaja en una plantilla de WhatsApp que manda la base sola, para la tienda que lo dibuja con su código de un solo uso: el presupuesto o el comprobante de un aviso del taller, o el pedido de la mañana a un proveedor.';

-- ---------------------------------------------------------------------------
-- 5. El chat del proveedor y «Enviado», un solo dueño cada uno
-- ---------------------------------------------------------------------------

-- El chat de WhatsApp del proveedor donde va el PDF: el de su vendedor (el
-- teléfono de la ficha) y, si no, el más reciente; sólo uno abierto, porque
-- en uno cerrado no se puede escribir. El asistente (`_v1`) y el envío de la
-- mañana leen éste.
create or replace function public.supplier_order_chat_internal(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_supplier public.suppliers%rowtype;
  v_digits text;
  v_chat record;
begin
  select * into v_supplier from public.suppliers
   where id = p_supplier_id and tenant_id = p_tenant_id;
  if not found then
    return null;
  end if;
  v_digits := right(regexp_replace(coalesce(v_supplier.sales_rep_phone, ''), '\D', '', 'g'), 8);

  select c.id as conversation_id,
         b.last_inbound_at,
         b.external_phone_number,
         b.external_wa_id
    into v_chat
    from public.conversations c
    left join public.whatsapp_conversation_bindings b
      on b.conversation_id = c.id
     and b.tenant_id = c.tenant_id
   where c.tenant_id = p_tenant_id
     and c.context_type = 'supplier'
     and c.context_id = p_supplier_id
     and c.channel = 'whatsapp'
     and c.status in ('pending', 'active')
   order by (length(v_digits) = 8
             and right(regexp_replace(coalesce(b.external_phone_number, ''), '\D', '', 'g'), 8) = v_digits) desc,
            b.last_inbound_at desc nulls last,
            c.updated_at desc nulls last
   limit 1;

  return jsonb_build_object(
    'conversation_id', v_chat.conversation_id,
    'wa_id', v_chat.external_wa_id,
    'phone_number', v_chat.external_phone_number,
    'last_inbound_at', v_chat.last_inbound_at,
    'sales_rep_phone', nullif(btrim(v_supplier.sales_rep_phone), '')
  );
end;
$$;

revoke all on function public.supplier_order_chat_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.purchase_order_supplier_chat_v1(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_chat jsonb;
  v_last timestamptz;
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Supplier not found or not accessible' using errcode = '42501';
  end if;
  v_chat := public.supplier_order_chat_internal(p_tenant_id, p_supplier_id);
  if v_chat is null then
    raise exception 'Supplier not found or not accessible' using errcode = 'P0002';
  end if;
  if v_chat ->> 'conversation_id' is null then
    return jsonb_build_object('conversation_id', null, 'last_inbound_at', null, 'window_open', false);
  end if;
  v_last := (v_chat ->> 'last_inbound_at')::timestamptz;
  return jsonb_build_object(
    'conversation_id', (v_chat ->> 'conversation_id')::uuid,
    'last_inbound_at', v_last,
    'window_open', coalesce(v_last > clock_timestamp() - interval '24 hours', false)
  );
end;
$function$;

revoke all on function public.purchase_order_supplier_chat_v1(uuid, uuid) from public, anon;
grant execute on function public.purchase_order_supplier_chat_v1(uuid, uuid) to authenticated;

-- Marca enviado el pedido y da por atendidos los avisos «Pagado: pedir lo
-- que viene a pedido» de sus ventas. Lo llaman el asistente (después de
-- comparar lo que salió) y el envío de la mañana.
create or replace function public.purchase_order_mark_sent_internal(
  p_tenant_id uuid,
  p_purchase_invoice_id uuid
)
returns public.purchase_invoices
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_invoice public.purchase_invoices%rowtype;
begin
  perform set_config('app.supplier_order_send', p_purchase_invoice_id::text, true);
  update public.purchase_invoices
     set status = 'sent',
         sent_date = clock_timestamp(),
         updated_at = clock_timestamp()
   where id = p_purchase_invoice_id
     and tenant_id = p_tenant_id
     and status = 'draft'
  returning * into v_invoice;
  perform set_config('app.supplier_order_send', '', true);

  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = p_tenant_id
     and n.type = 'customer_quote_order_to_purchase'
     and n.entity_type = 'online_order'
     and n.entity_id in (
       select po.online_order_id
         from public.customer_quote_purchase_orders po
        where po.purchase_invoice_id = p_purchase_invoice_id
          and po.tenant_id = p_tenant_id
     );
  return v_invoice;
end;
$function$;

revoke all on function public.purchase_order_mark_sent_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.purchase_order_mark_sent_v1(
  p_tenant_id uuid,
  p_purchase_invoice_id uuid,
  p_sent_lines jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_invoice public.purchase_invoices%rowtype;
  v_changed text;
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Purchase order not found or not accessible' using errcode = '42501';
  end if;
  if p_sent_lines is null or jsonb_typeof(p_sent_lines) <> 'array' then
    raise exception 'Invalid sent lines' using errcode = '22023';
  end if;

  select * into v_invoice from public.purchase_invoices
   where id = p_purchase_invoice_id
     and tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Purchase order not found or not accessible' using errcode = 'P0002';
  end if;
  if v_invoice.status = 'sent' then
    return to_jsonb(v_invoice) || jsonb_build_object('replay', true);
  end if;
  if v_invoice.status <> 'draft' then
    raise exception 'Este pedido ya no es un borrador.' using errcode = '55000';
  end if;

  -- Lo que dice el pedido menos lo que salió, producto por producto.
  with difference as (
    select both_sides.product_id,
           sum(both_sides.quantity) as quantity,
           min(both_sides.name) as name
      from (
        select e.value ->> 'product_id' as product_id,
               coalesce((e.value ->> 'quantity')::numeric, 0) as quantity,
               coalesce(e.value ->> 'product_name', e.value ->> 'description') as name
          from jsonb_array_elements(
            case when jsonb_typeof(v_invoice.items) = 'array' then v_invoice.items else '[]'::jsonb end
          ) e
        union all
        select x ->> 'product_id',
               -coalesce((x ->> 'quantity')::numeric, 0),
               null
          from jsonb_array_elements(p_sent_lines) x
      ) both_sides
     group by both_sides.product_id
  )
  select string_agg(coalesce(difference.name, 'un producto'), ', '
                    order by coalesce(difference.name, 'un producto'))
    into v_changed
    from difference
   where difference.quantity <> 0;
  if v_changed is not null then
    raise exception 'El pedido cambió mientras se enviaba (%): vuelve a abrirlo y mándale lo que falta.',
      v_changed
      using errcode = '55000', hint = 'supplier_order_changed';
  end if;

  v_invoice := public.purchase_order_mark_sent_internal(p_tenant_id, v_invoice.id);
  return to_jsonb(v_invoice) || jsonb_build_object('replay', false);
end;
$function$;

revoke all on function public.purchase_order_mark_sent_v1(uuid, uuid, jsonb) from public, anon;
grant execute on function public.purchase_order_mark_sent_v1(uuid, uuid, jsonb) to authenticated;

-- La guardia de 20261122010000, más una regla: un pedido con ventas web que
-- ya salió no vuelve a borrador desde una app. El asistente que lo tenía
-- abierto cuando salió solo recibe el motivo en vez de reabrirlo con otras
-- líneas; sólo el envío de la mañana, cuando WhatsApp no lo entregó, lo
-- devuelve a borrador.
create or replace function public.supplier_open_order_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_need record;
  v_have numeric;
begin
  if old.status = 'sent' and new.status = 'draft' then
    if exists (
         select 1 from public.customer_quote_purchase_orders po
          where po.purchase_invoice_id = new.id
            and po.tenant_id = new.tenant_id
       )
       and coalesce(current_setting('app.supplier_order_send', true), '') <> new.id::text then
      raise exception 'Este pedido ya se le envió al proveedor: lo nuevo va en el próximo pedido. Vuelve a abrir el asistente para verlo.'
        using errcode = '55000', hint = 'supplier_order_already_sent';
    end if;
    return new;
  end if;
  if old.status is distinct from 'draft' then
    return new;
  end if;
  if not exists (
    select 1 from public.customer_quote_purchase_orders po
     where po.purchase_invoice_id = new.id
       and po.tenant_id = new.tenant_id
  ) then
    return new;
  end if;

  if new.status = 'sent'
     and coalesce(current_setting('app.supplier_order_send', true), '') <> new.id::text then
    raise exception 'Actualiza el ERP: este pedido se envía con su PDF desde «Enviar al proveedor».'
      using errcode = '55000', hint = 'supplier_order_send_required';
  end if;

  if new.status = 'draft' and new.items is distinct from old.items then
    for v_need in
      select i.product_id::text as product_id,
             min(i.product_name) as product_name,
             sum(i.quantity) as quantity,
             string_agg(distinct o.order_number, ', ') as orders
        from public.customer_quote_purchase_orders po
        join public.online_orders o
          on o.id = po.online_order_id
         and o.tenant_id = po.tenant_id
        join public.online_order_items i
          on i.order_id = o.id
         and i.tenant_id = o.tenant_id
       where po.purchase_invoice_id = new.id
         and po.tenant_id = new.tenant_id
         and o.status <> 'cancelled'
         and o.payment_status = 'paid'
         and i.fulfillment = 'on_order'
         and i.arrived_at is null
         and i.on_order_supplier_id = po.supplier_id
       group by i.product_id
    loop
      select coalesce(sum((e.value ->> 'quantity')::numeric), 0)
        into v_have
        from jsonb_array_elements(
          case when jsonb_typeof(new.items) = 'array' then new.items else '[]'::jsonb end
        ) e
       where e.value ->> 'product_id' = v_need.product_id;
      if v_have < v_need.quantity then
        raise exception 'No se puede sacar % de este pedido: lo pagó %. Vuelve a abrirlo para ver lo último.',
          v_need.product_name, v_need.orders
          using errcode = '23514', hint = 'supplier_order_line_needed';
      end if;
    end loop;
  end if;
  return new;
end;
$function$;

revoke all on function public.supplier_open_order_guard()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. El envío
-- ---------------------------------------------------------------------------

-- «Hola …»: el saludo del contacto principal del proveedor (su ficha, «Cómo
-- saludarle»); si no, el primer nombre de su vendedor o de su contacto; si no,
-- el primero de su nombre. Lo mismo que elige el asistente de compras
-- (`getSupplierPrimaryContactGreeting`).
create or replace function public.supplier_order_greeting_internal(
  p_tenant_id uuid,
  p_supplier_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_supplier public.suppliers%rowtype;
  v_greeting text;
  v_rep text;
begin
  select public.contact_greeting_name_internal(contact.name, contact.greeting_style, contact.greeting_custom_name)
    into v_greeting
    from public.supplier_contacts contact
   where contact.tenant_id = p_tenant_id
     and contact.supplier_id = p_supplier_id
     and contact.is_primary
     and contact.is_active
   limit 1;
  if nullif(btrim(v_greeting), '') is not null then
    return btrim(v_greeting);
  end if;
  select * into v_supplier from public.suppliers
   where id = p_supplier_id and tenant_id = p_tenant_id;
  v_rep := nullif(btrim(v_supplier.sales_rep_name), '');
  if v_rep = 'Contacto de WhatsApp' then
    v_rep := null;
  end if;
  return coalesce(
    nullif(split_part(coalesce(v_rep, ''), ' ', 1), ''),
    nullif(split_part(btrim(coalesce(v_supplier.contact_person, '')), ' ', 1), ''),
    public.contact_greeting_name_internal(v_supplier.name, 'first_name', null)
  );
end;
$$;

revoke all on function public.supplier_order_greeting_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Quién lo manda: quien armó el pedido si sigue en el equipo; si no, un
-- administrador. La cola y la conversación aplican sus reglas a esa persona.
create or replace function public.supplier_order_actor_internal(
  p_tenant_id uuid,
  p_created_by uuid
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select profile.user_id
    from public.user_profiles profile
   where profile.tenant_id = p_tenant_id
     and profile.is_active is true
     and (profile.user_id = p_created_by or profile.role in ('owner', 'admin'))
   order by (profile.user_id = p_created_by) desc nulls last,
            (profile.role = 'owner') desc,
            profile.created_at
   limit 1;
$$;

revoke all on function public.supplier_order_actor_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Por qué no salió, como lo lee una persona.
create or replace function public.supplier_order_dispatch_reason_text_internal(p_reason text)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case
    when p_reason = 'no_phone' then 'el proveedor no tiene el celular de su vendedor en la ficha'
    when p_reason = 'no_channel' then 'WhatsApp no está conectado'
    when p_reason = 'no_actor' then 'no hay un administrador activo que lo envíe'
    when p_reason = 'template_not_approved' then 'Meta no tiene aprobada la plantilla del PDF'
    when p_reason = 'no_greeting' then 'no sabemos cómo saludar al proveedor: falta el nombre de su vendedor'
    when p_reason like 'send_failed%' then 'WhatsApp no aceptó el mensaje'
    when p_reason like 'delivery_failed%' then 'WhatsApp no lo pudo entregar'
    else 'no pudo salir'
  end;
$$;

revoke all on function public.supplier_order_dispatch_reason_text_internal(text)
  from public, anon, authenticated;

-- «mañana», «el lunes 24» o «el 3 de diciembre»: cuándo sale el siguiente.
create or replace function public.supplier_order_when_text_internal(
  p_at timestamptz,
  p_now timestamptz
)
returns text
language sql
stable
set search_path = pg_catalog, pg_temp
as $$
  with local as (
    select (p_at at time zone 'America/Santiago') as at_local,
           (p_now at time zone 'America/Santiago')::date as today
  )
  select case
    when p_at is null then null
    when local.at_local::date = local.today then 'hoy a las ' || to_char(local.at_local, 'HH24:MI')
    when local.at_local::date = local.today + 1 then 'mañana a las ' || to_char(local.at_local, 'HH24:MI')
    when local.at_local::date < local.today + 7 then
      'el ' || (array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'])
        [extract(isodow from local.at_local)::integer]
        || ' ' || extract(day from local.at_local)::integer
        || ' a las ' || to_char(local.at_local, 'HH24:MI')
    else
      'el ' || extract(day from local.at_local)::integer || ' de '
        || (array['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
                  'septiembre', 'octubre', 'noviembre', 'diciembre'])
           [extract(month from local.at_local)::integer]
        || ' a las ' || to_char(local.at_local, 'HH24:MI')
  end
    from local;
$$;

revoke all on function public.supplier_order_when_text_internal(timestamptz, timestamptz)
  from public, anon, authenticated;

-- El aviso del ERP de un envío ya resuelto; el teléfono dice lo mismo
-- (`push-notification` › `supplier_order_push.ts` lee este aviso).
create or replace function public.supplier_order_dispatch_notify_internal(
  p_dispatch_id uuid,
  p_now timestamptz default clock_timestamp()
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dispatch public.supplier_order_dispatches%rowtype;
  v_invoice public.purchase_invoices%rowtype;
  v_supplier public.suppliers%rowtype;
  v_name text;
  v_number text;
  v_what text;
  v_next timestamptz;
  v_type text;
  v_title text;
  v_body text;
  v_severity text;
begin
  select * into v_dispatch from public.supplier_order_dispatches where id = p_dispatch_id;
  if not found or v_dispatch.state = 'queued' then
    return;
  end if;
  select * into v_invoice from public.purchase_invoices
   where id = v_dispatch.purchase_invoice_id and tenant_id = v_dispatch.tenant_id;
  select * into v_supplier from public.suppliers
   where id = v_dispatch.supplier_id and tenant_id = v_dispatch.tenant_id;
  v_name := coalesce(nullif(btrim(v_supplier.name), ''), nullif(btrim(v_invoice.supplier_name), ''), 'el proveedor');
  v_number := coalesce(nullif(btrim(v_invoice.invoice_number), ''), 'El pedido');
  v_what := v_dispatch.line_count
    || case when v_dispatch.line_count = 1 then ' producto' else ' productos' end
    || case when v_dispatch.order_count > 1 then ' de ' || v_dispatch.order_count || ' ventas' else '' end;

  if v_dispatch.state = 'sent' then
    v_type := 'supplier_order_sent';
    v_severity := 'success';
    v_title := 'Pedido enviado a ' || v_name;
    v_body := v_number || ' · ' || v_what || '. Salió solo a las '
      || to_char(v_dispatch.due_at at time zone 'America/Santiago', 'HH24:MI') || ' con su PDF.';
  elsif v_dispatch.state = 'unknown' then
    v_type := 'supplier_order_unknown';
    v_severity := 'warning';
    v_title := 'Revisa el pedido a ' || v_name;
    v_body := v_number || ' · ' || v_what || '. WhatsApp no confirmó si llegó: míralo en el chat del proveedor.';
  else
    v_type := 'supplier_order_not_sent';
    v_severity := 'warning';
    v_next := public.supplier_order_next_send_at_internal(
      greatest(v_dispatch.due_at, p_now), v_supplier.order_send_time);
    v_title := 'No salió el pedido a ' || v_name;
    v_body := v_number || ': ' || public.supplier_order_dispatch_reason_text_internal(v_dispatch.reason)
      || '. Mándalo desde «Enviar al proveedor»'
      || coalesce('; si no, sale solo ' || public.supplier_order_when_text_internal(v_next, p_now), '')
      || '.';
  end if;

  insert into public.erp_notifications (
    tenant_id, type, title, body, route, entity_type, entity_id, severity, data
  ) values (
    v_dispatch.tenant_id,
    v_type,
    v_title,
    v_body,
    '/purchases/assistant?supplier=' || v_dispatch.supplier_id::text
      || '&order=' || v_dispatch.purchase_invoice_id::text,
    'supplier_order_dispatch',
    v_dispatch.id,
    v_severity,
    jsonb_build_object(
      'dispatch_id', v_dispatch.id,
      'purchase_invoice_id', v_dispatch.purchase_invoice_id,
      'supplier_id', v_dispatch.supplier_id,
      'state', v_dispatch.state,
      'reason', v_dispatch.reason
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;
exception
  when others then
    raise warning 'Supplier order notice could not be recorded';
end;
$$;

revoke all on function public.supplier_order_dispatch_notify_internal(uuid, timestamptz)
  from public, anon, authenticated, service_role;

-- Un envío: el pedido abierto [p_invoice_id] por la hora [p_due_at]. Una sola
-- vez por hora de envío: si no sale, el siguiente intento es el del día hábil
-- siguiente (o «Enviar al proveedor»).
create or replace function public.supplier_order_dispatch_internal(
  p_invoice_id uuid,
  p_due_at timestamptz,
  p_now timestamptz default clock_timestamp()
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_head record;
  v_invoice public.purchase_invoices%rowtype;
  v_supplier public.suppliers%rowtype;
  v_dispatch public.supplier_order_dispatches%rowtype;
  v_orders integer;
  v_lines integer;
  v_reason text;
  v_actor uuid;
  v_channel uuid;
  v_chat jsonb;
  v_phone text;
  v_contact text;
  v_greeting text;
  v_conversation uuid;
  v_binding jsonb;
  v_token text;
  v_caption text;
  v_request jsonb;
  v_result jsonb;
  v_message uuid;
begin
  select invoice.tenant_id, invoice.supplier_id into v_head
    from public.purchase_invoices invoice
   where invoice.id = p_invoice_id;
  if not found or v_head.supplier_id is null then
    return null;
  end if;
  -- El mismo candado con que una venta pagada suma al pedido abierto
  -- (`customer_quote_order_prepare_purchases_internal`): lo que se pague
  -- mientras sale espera, y va en el siguiente.
  perform pg_advisory_xact_lock(
    hashtextextended('supplier-open-order:' || v_head.tenant_id::text || ':' || v_head.supplier_id::text, 0));

  select * into v_invoice from public.purchase_invoices
   where id = p_invoice_id and tenant_id = v_head.tenant_id
   for update;
  if not found or v_invoice.status <> 'draft' then
    return null;
  end if;
  if exists (
    select 1 from public.supplier_order_dispatches dispatch
     where dispatch.purchase_invoice_id = v_invoice.id
       and dispatch.tenant_id = v_invoice.tenant_id
       and dispatch.due_at >= p_due_at
  ) then
    return null;
  end if;

  select count(*) into v_orders
    from public.customer_quote_purchase_orders po
    join public.online_orders o
      on o.id = po.online_order_id
     and o.tenant_id = po.tenant_id
   where po.purchase_invoice_id = v_invoice.id
     and po.tenant_id = v_invoice.tenant_id
     and o.status <> 'cancelled';
  v_lines := case when jsonb_typeof(v_invoice.items) = 'array' then jsonb_array_length(v_invoice.items) else 0 end;
  -- Ya no es un pedido abierto, o no lleva nada: no hay qué mandar.
  if v_orders = 0 or v_lines = 0 then
    return null;
  end if;

  select * into v_supplier from public.suppliers
   where id = v_invoice.supplier_id and tenant_id = v_invoice.tenant_id;

  insert into public.supplier_order_dispatches (
    tenant_id, supplier_id, purchase_invoice_id, due_at, state, order_count, line_count
  ) values (
    v_invoice.tenant_id, v_invoice.supplier_id, v_invoice.id, p_due_at, 'queued', v_orders, v_lines
  ) returning * into v_dispatch;

  v_actor := public.supplier_order_actor_internal(v_invoice.tenant_id, v_invoice.created_by);
  select channel.id into v_channel
    from public.whatsapp_channels channel
   where channel.tenant_id = v_invoice.tenant_id and channel.is_active
   order by channel.created_at
   limit 1;
  v_chat := public.supplier_order_chat_internal(v_invoice.tenant_id, v_invoice.supplier_id);
  v_conversation := nullif(v_chat ->> 'conversation_id', '')::uuid;
  -- El número del chat tal como lo tiene ligado (la cola no deja cambiarlo);
  -- sin chat, el celular del vendedor.
  v_phone := coalesce(
    case when v_conversation is not null
         then coalesce(nullif(btrim(v_chat ->> 'wa_id'), ''),
                       public.normalize_whatsapp_phone(v_chat ->> 'phone_number')) end,
    public.normalize_whatsapp_phone(v_chat ->> 'sales_rep_phone'));
  v_greeting := public.supplier_order_greeting_internal(v_invoice.tenant_id, v_invoice.supplier_id);
  v_contact := coalesce(nullif(btrim(v_supplier.sales_rep_name), ''), v_supplier.name);

  v_reason := case
    when v_actor is null then 'no_actor'
    when v_channel is null then 'no_channel'
    when v_phone is null or v_phone !~ '^[0-9]{8,15}$' then 'no_phone'
    when not public.whatsapp_template_approved_internal(v_invoice.tenant_id, 'documento_adjunto_v1') then 'template_not_approved'
    when nullif(btrim(v_greeting), '') is null then 'no_greeting'
  end;

  if v_reason is null then
    v_token := public.supplier_order_document_token_internal(v_dispatch);
    v_caption := format(
      'Hola %s, te enviamos el documento adjunto desde Viñabike. Si tienes dudas, responde este mensaje.',
      v_greeting);
    begin
      perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_actor, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_actor::text, true);

      -- Sin chat abierto con el proveedor se abre uno con el celular de su
      -- vendedor, ligado al proveedor.
      if v_conversation is null then
        v_binding := public.ensure_whatsapp_conversation_binding(
          p_tenant_id => v_invoice.tenant_id,
          p_channel_id => v_channel,
          p_wa_id => v_phone,
          p_phone_number => v_phone,
          p_contact_name => v_contact,
          p_customer_id => null,
          p_context_type => 'supplier',
          p_context_id => v_supplier.id,
          p_conversation_id => null);
        v_conversation := (v_binding ->> 'conversation_id')::uuid;
      end if;

      v_request := jsonb_build_object(
        'conversationId', v_conversation,
        'phoneNumber', v_phone,
        'contactName', v_contact,
        'contextType', 'purchase_order',
        'contextId', v_invoice.id,
        'type', 'template',
        'templateName', 'documento_adjunto_v1',
        'templateLanguage', 'es_CL',
        'caption', v_caption,
        'templateComponents', jsonb_build_array(jsonb_build_object(
          'type', 'body',
          'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_greeting)))),
        'templateDocumentToken', v_token,
        'metadata', jsonb_build_object(
          'source', 'supplier_order_dispatch',
          'client_message_id', 'supplier-order:' || v_dispatch.id,
          'template_purpose', 'document_attached',
          'template_name', 'documento_adjunto_v1',
          'template_language', 'es_CL',
          'message_category', 'utility',
          -- El saludo ya está resuelto: whatsapp-send no lo recorta.
          'greeting_name_source', 'contact_preference',
          'purchase_invoice_id', v_invoice.id,
          'supplier_order_dispatch_id', v_dispatch.id));
      v_result := public.enqueue_whatsapp_message_v1(v_request);
      v_message := nullif(v_result ->> 'message_id', '')::uuid;
      if v_message is null then
        v_reason := 'send_failed: not accepted';
      end if;
    exception when others then
      v_reason := left('send_failed: ' || sqlerrm, 280);
    end;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  end if;

  if v_message is not null then
    perform public.purchase_order_mark_sent_internal(v_invoice.tenant_id, v_invoice.id);
    update public.supplier_order_dispatches
       set message_id = v_message,
           conversation_id = v_conversation,
           updated_at = clock_timestamp()
     where id = v_dispatch.id;
    return 'queued';
  end if;

  update public.supplier_order_dispatches
     set state = 'skipped',
         reason = v_reason,
         conversation_id = v_conversation,
         settled_at = clock_timestamp(),
         updated_at = clock_timestamp()
   where id = v_dispatch.id;
  perform public.supplier_order_dispatch_notify_internal(v_dispatch.id, p_now);
  return 'skipped';
end;
$$;

revoke all on function public.supplier_order_dispatch_internal(uuid, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

-- Lo que dijo WhatsApp de cada envío de los dos últimos días: aceptado
-- (salió), fallido (no llegó: el pedido vuelve a borrador) o sin respuesta
-- de la cola (no se sabe).
create or replace function public.supplier_order_dispatches_settle_internal(
  p_now timestamptz default clock_timestamp()
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
  v_settled integer := 0;
begin
  for v_row in
    select dispatch.id, dispatch.tenant_id, dispatch.state, dispatch.purchase_invoice_id,
           message.external_status, outbox.state as outbox_state, outbox.last_error
      from public.supplier_order_dispatches dispatch
      left join public.messages message
        on message.id = dispatch.message_id
       and message.tenant_id = dispatch.tenant_id
      left join public.whatsapp_outbox outbox
        on outbox.message_id = dispatch.message_id
       and outbox.tenant_id = dispatch.tenant_id
     where dispatch.state in ('queued', 'sent')
       and greatest(dispatch.created_at, dispatch.due_at) > p_now - interval '2 days'
       and dispatch.message_id is not null
     for update of dispatch skip locked
  loop
    if v_row.external_status = 'failed' or v_row.outbox_state = 'failed' then
      -- No llegó: el pedido vuelve a ser el abierto del proveedor.
      perform set_config('app.supplier_order_send', v_row.purchase_invoice_id::text, true);
      update public.purchase_invoices
         set status = 'draft', sent_date = null, updated_at = clock_timestamp()
       where id = v_row.purchase_invoice_id
         and tenant_id = v_row.tenant_id
         and status = 'sent';
      perform set_config('app.supplier_order_send', '', true);
      update public.supplier_order_dispatches
         set state = 'failed',
             reason = left('delivery_failed: ' || coalesce(v_row.last_error, 'whatsapp'), 280),
             settled_at = clock_timestamp(),
             updated_at = clock_timestamp()
       where id = v_row.id;
      perform public.supplier_order_dispatch_notify_internal(v_row.id, p_now);
      v_settled := v_settled + 1;
    elsif v_row.state = 'queued'
          and (v_row.external_status in ('accepted', 'sent', 'delivered', 'read')
               or v_row.outbox_state = 'accepted') then
      update public.supplier_order_dispatches
         set state = 'sent', settled_at = clock_timestamp(), updated_at = clock_timestamp()
       where id = v_row.id;
      perform public.supplier_order_dispatch_notify_internal(v_row.id, p_now);
      v_settled := v_settled + 1;
    elsif v_row.state = 'queued' and v_row.outbox_state = 'outcome_unknown' then
      update public.supplier_order_dispatches
         set state = 'unknown', settled_at = clock_timestamp(), updated_at = clock_timestamp()
       where id = v_row.id;
      perform public.supplier_order_dispatch_notify_internal(v_row.id, p_now);
      v_settled := v_settled + 1;
    end if;
  end loop;
  return v_settled;
end;
$$;

revoke all on function public.supplier_order_dispatches_settle_internal(timestamptz)
  from public, anon, authenticated, service_role;

-- La pasada de cada minuto: primero lo que contestó WhatsApp, después los
-- pedidos abiertos a los que les toca salir. Un día hábil, desde la hora del
-- proveedor y hasta las 20:00: un pedido atrasado nunca sale de noche.
create or replace function public.process_supplier_order_dispatches_v1(
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_local timestamp := p_now at time zone 'America/Santiago';
  v_settled integer;
  v_row record;
  v_state text;
  v_queued integer := 0;
  v_skipped integer := 0;
begin
  v_settled := public.supplier_order_dispatches_settle_internal(p_now);

  if public.chile_business_day_internal(v_local::date) and v_local::time < time '20:00' then
    for v_row in
      select candidate.id, candidate.due_at
        from (
          select invoice.id,
                 invoice.created_at,
                 public.supplier_order_next_send_at_internal(
                   greatest(invoice.created_at, coalesce(last_try.due_at, invoice.created_at)),
                   supplier.order_send_time) as due_at
            from public.purchase_invoices invoice
            join public.suppliers supplier
              on supplier.id = invoice.supplier_id
             and supplier.tenant_id = invoice.tenant_id
            left join lateral (
              select max(dispatch.due_at) as due_at
                from public.supplier_order_dispatches dispatch
               where dispatch.purchase_invoice_id = invoice.id
                 and dispatch.tenant_id = invoice.tenant_id
            ) last_try on true
           where invoice.id in (
                   select po.purchase_invoice_id
                     from public.customer_quote_purchase_orders po
                     join public.online_orders o
                       on o.id = po.online_order_id
                      and o.tenant_id = po.tenant_id
                    where o.status <> 'cancelled'
                 )
             and invoice.status = 'draft'
             and supplier.order_send_time is not null
             and v_local::time >= supplier.order_send_time
             and public.supplier_order_auto_send_enabled_internal(invoice.tenant_id)
        ) candidate
       where candidate.due_at is not null
         and candidate.due_at <= p_now
       order by candidate.created_at
       limit 25
    loop
      v_state := public.supplier_order_dispatch_internal(v_row.id, v_row.due_at, p_now);
      if v_state = 'queued' then
        v_queued := v_queued + 1;
      elsif v_state = 'skipped' then
        v_skipped := v_skipped + 1;
      end if;
    end loop;
  end if;

  return jsonb_build_object('settled', v_settled, 'queued', v_queued, 'skipped', v_skipped);
end;
$$;

revoke all on function public.process_supplier_order_dispatches_v1(timestamptz)
  from public, anon, authenticated;
grant execute on function public.process_supplier_order_dispatches_v1(timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- 7. Lo que muestran Pedidos web y el asistente
-- ---------------------------------------------------------------------------

-- Cuándo sale solo un pedido abierto; null si no sale solo (enviado, sin hora
-- del proveedor, sin ventas web o con el envío apagado).
create or replace function public.supplier_open_order_send_at_internal(
  p_purchase_invoice_id uuid,
  p_tenant_id uuid
)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when invoice.status = 'draft'
     and supplier.order_send_time is not null
     and public.supplier_order_auto_send_enabled_internal(invoice.tenant_id)
     and exists (
       select 1
         from public.customer_quote_purchase_orders po
         join public.online_orders o
           on o.id = po.online_order_id
          and o.tenant_id = po.tenant_id
        where po.purchase_invoice_id = invoice.id
          and po.tenant_id = invoice.tenant_id
          and o.status <> 'cancelled'
     )
    then public.supplier_order_next_send_at_internal(
      greatest(invoice.created_at, coalesce((
        select max(dispatch.due_at)
          from public.supplier_order_dispatches dispatch
         where dispatch.purchase_invoice_id = invoice.id
           and dispatch.tenant_id = invoice.tenant_id
      ), invoice.created_at)),
      supplier.order_send_time)
  end
    from public.purchase_invoices invoice
    join public.suppliers supplier
      on supplier.id = invoice.supplier_id
     and supplier.tenant_id = invoice.tenant_id
   where invoice.id = p_purchase_invoice_id
     and invoice.tenant_id = p_tenant_id;
$$;

revoke all on function public.supplier_open_order_send_at_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- El último envío automático de un pedido, como lo muestra la app.
create or replace function public.supplier_order_last_dispatch_internal(
  p_purchase_invoice_id uuid,
  p_tenant_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'state', dispatch.state,
    'reason', public.supplier_order_dispatch_reason_text_internal(dispatch.reason),
    'due_at', dispatch.due_at,
    'settled_at', dispatch.settled_at
  )
    from public.supplier_order_dispatches dispatch
   where dispatch.purchase_invoice_id = p_purchase_invoice_id
     and dispatch.tenant_id = p_tenant_id
   order by dispatch.due_at desc, dispatch.created_at desc
   limit 1;
$$;

revoke all on function public.supplier_order_last_dispatch_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Para el asistente de compras: si el pedido sale solo, cuándo, y qué pasó
-- con el último envío.
create or replace function public.supplier_open_order_schedule_v1(
  p_tenant_id uuid,
  p_purchase_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Purchase order not found or not accessible' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'send_at', public.supplier_open_order_send_at_internal(p_purchase_invoice_id, p_tenant_id),
    'last_dispatch', public.supplier_order_last_dispatch_internal(p_purchase_invoice_id, p_tenant_id)
  );
end;
$$;

revoke all on function public.supplier_open_order_schedule_v1(uuid, uuid) from public, anon;
grant execute on function public.supplier_open_order_schedule_v1(uuid, uuid) to authenticated;

comment on function public.supplier_open_order_schedule_v1(uuid, uuid) is
  'Cuándo sale solo el pedido abierto de un proveedor (null si no sale solo) y el último envío automático (20261122030000).';

create or replace function public.online_order_on_order_projection_internal(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'id', o.id,
    'number', o.order_number,
    'status', o.status,
    'payment_status', o.payment_status,
    'payment_method', o.payment_method,
    'delivery_type', o.delivery_type,
    'total', o.total,
    'shipping_cost', o.shipping_cost,
    'paid_at', o.paid_at,
    'tracking_number', o.tracking_number,
    'shipping_carrier', o.shipping_carrier,
    'sales_invoice_id', o.sales_invoice_id,
    'invoice_number', (
      select si.invoice_number from public.sales_invoices si
       where si.id = o.sales_invoice_id and si.tenant_id = o.tenant_id
    ),
    'quote_id', (
      select q.id from public.customer_quotes q
       where q.online_order_id = o.id and q.tenant_id = o.tenant_id
    ),
    'waiting', public.customer_quote_order_waiting_internal(o.id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'product_id', i.product_id,
        'product_name', i.product_name,
        'product_sku', i.product_sku,
        'quantity', i.quantity,
        'fulfillment', i.fulfillment,
        'arrived_at', i.arrived_at,
        'supplier_id', i.on_order_supplier_id,
        'supplier_name', s.name,
        'lead_days_min', i.lead_days_min,
        'lead_days_max', i.lead_days_max,
        'stock_now', p.stock_quantity
      ) order by i.created_at, i.id)
        from public.online_order_items i
        left join public.suppliers s on s.id = i.on_order_supplier_id and s.tenant_id = i.tenant_id
        left join public.products p on p.id = i.product_id and p.tenant_id = i.tenant_id
       where i.order_id = o.id and i.tenant_id = o.tenant_id
    ), '[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', po.id,
        'supplier_id', po.supplier_id,
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone,
        'purchase_invoice_id', pi.id,
        'number', pi.invoice_number,
        'status', pi.status,
        'total', pi.total,
        'sent_at', pi.sent_date,
        'orders', (
          select count(*)
            from public.customer_quote_purchase_orders other
            join public.online_orders other_order
              on other_order.id = other.online_order_id
             and other_order.tenant_id = other.tenant_id
           where other.purchase_invoice_id = pi.id
             and other.tenant_id = pi.tenant_id
             and other_order.status <> 'cancelled'
        ),
        -- Cuándo sale solo (20261122030000) y cómo le fue al último envío.
        'send_at', public.supplier_open_order_send_at_internal(pi.id, pi.tenant_id),
        'last_dispatch', public.supplier_order_last_dispatch_internal(pi.id, pi.tenant_id),
        'created_at', po.created_at
      ) order by po.created_at)
        from public.customer_quote_purchase_orders po
        left join public.suppliers s on s.id = po.supplier_id and s.tenant_id = po.tenant_id
        left join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
       where po.online_order_id = o.id and po.tenant_id = o.tenant_id
    ), '[]'::jsonb)
  )
    from public.online_orders o
   where o.id = p_order_id;
$function$;

revoke all on function public.online_order_on_order_projection_internal(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. El teléfono de quien compra
-- ---------------------------------------------------------------------------

-- Mismo contrato que `trg_payroll_voucher_push_alert` (20261121150000): el
-- secreto vive en Vault, sin secreto no se encola nada y un fallo del aviso
-- nunca hace fallar el envío. `push-notification` relee la fila y su aviso
-- del ERP, y no suena por una fila vieja (restaurar reinserta con los
-- disparadores vivos).
create or replace function public.invoke_push_notification_for_supplier_order_dispatch()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_webhook_secret text;
begin
  if new.state not in ('sent', 'failed', 'skipped', 'unknown')
     or (tg_op = 'UPDATE' and old.state is not distinct from new.state)
     or new.updated_at < now() - interval '1 hour' then
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
      'type', 'SUPPLIER_ORDER_DISPATCH',
      'table', 'supplier_order_dispatches',
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
    raise warning 'Supplier order push alert could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_supplier_order_dispatch()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_order_dispatch_push_alert on public.supplier_order_dispatches;
create trigger trg_supplier_order_dispatch_push_alert
  after insert or update of state on public.supplier_order_dispatches
  for each row
  execute function public.invoke_push_notification_for_supplier_order_dispatch();

-- ---------------------------------------------------------------------------
-- 9. Las pasadas
-- ---------------------------------------------------------------------------

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; the supplier order dispatch was not scheduled';
    return;
  end if;
  for v_job in
    select jobid from cron.job
     where jobname in ('vinabike_supplier_order_dispatch', 'vinabike_chile_public_holidays')
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_supplier_order_dispatch',
    '* * * * *',
    $job$select public.process_supplier_order_dispatches_v1()$job$
  );
  perform cron.schedule(
    'vinabike_chile_public_holidays',
    '17 * * * *',
    $job$select public.chile_public_holidays_refresh_internal()$job$
  );
end
$$;

commit;
