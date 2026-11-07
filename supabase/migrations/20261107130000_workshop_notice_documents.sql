-- El presupuesto y el comprobante en PDF arriba del aviso de WhatsApp
-- (dueño, 2026-11-07, sobre el lienzo premium de los avisos: «perfecto, me
-- gustaron todos menos el que tiene esa "imagen" de la bici»).
--
-- * `taller_presupuesto_pdf_v1`: el presupuesto en PDF, el monto en el texto
--   y dos respuestas rápidas. «Aprobar presupuesto» aprueba de verdad: la
--   base pide a whatsapp-send la tarjeta del presupuesto (`approve_quote`),
--   que verifica el trabajo y pone la clave de un solo uso en la respuesta;
--   al tocarla, `apply_whatsapp_job_action` aprueba la cotización como si la
--   hubiera aprobado en el ERP. «Tengo una consulta» sólo abre la conversación.
-- * `taller_entregada_pdf_v1`: el comprobante de entrega y garantía en PDF
--   (el mismo de la cuenta del cliente) y el botón «Guardar en mi cuenta».
--
-- El PDF lo dibuja el servidor de la tienda (`POST /cuenta/aviso.pdf`) con
-- un código de un solo uso que la base deja en el aviso
-- (`workshop_notice_document_tokens`, sólo su huella): whatsapp-send lo canjea
-- al enviar, sube el PDF a Meta y lo manda por id. El código viaja en el
-- cuerpo de las peticiones, nunca en una dirección.
--
-- Se prefieren sólo cuando la tienda ya los dibuja
-- (`company_settings.workshop_notice_documents_enabled = 'true'`, se enciende
-- después de desplegar la tienda), Meta las aprobó y el trabajo puede llevar
-- su PDF: un presupuesto en cotización pendiente y vigente, con líneas y
-- total, o una entrega con su comprobante. Si no, sale la `_v2` con botón.

begin;

-- ---------------------------------------------------------------------------
-- 1. El código de un solo uso de cada PDF
-- ---------------------------------------------------------------------------

-- Fuera del respaldo a propósito, como los avisos: un código vence en dos días
-- y restaurar no debe revivirlo.
create table if not exists public.workshop_notice_document_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  notice_id uuid not null,
  job_id uuid not null,
  kind text not null,
  token_sha256 text not null,
  expires_at timestamptz not null,
  reads integer not null default 0,
  last_read_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  constraint workshop_notice_document_tokens_kind check (kind in ('quote', 'delivery')),
  constraint workshop_notice_document_tokens_hash check (token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint workshop_notice_document_tokens_hash_key unique (token_sha256),
  constraint workshop_notice_document_tokens_reads check (reads >= 0)
);

create index if not exists workshop_notice_document_tokens_notice
  on public.workshop_notice_document_tokens (tenant_id, notice_id);

comment on table public.workshop_notice_document_tokens is
  'El código de un solo uso con que la tienda dibuja el PDF de un aviso del taller por WhatsApp (presupuesto o comprobante). Sólo su huella; vence en dos días.';

alter table public.workshop_notice_document_tokens enable row level security;
revoke all on public.workshop_notice_document_tokens from public, anon, authenticated;
grant all on public.workshop_notice_document_tokens to service_role;

create or replace function public.workshop_notice_document_token_internal(
  p_notice public.workshop_customer_notices,
  p_kind text
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_raw text := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
begin
  insert into public.workshop_notice_document_tokens (
    tenant_id, notice_id, job_id, kind, token_sha256, expires_at
  ) values (
    p_notice.tenant_id,
    p_notice.id,
    p_notice.job_id,
    p_kind,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '2 days'
  );
  return v_raw;
end;
$$;

revoke all on function public.workshop_notice_document_token_internal(public.workshop_customer_notices, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. El presupuesto como lo dibuja el PDF
-- ---------------------------------------------------------------------------

-- El total: las líneas menos el descuento, como el presupuesto del ERP, en
-- pesos enteros. En los 28 presupuestos de los 90 días anteriores coincide
-- con `total_cost`.
create or replace function public.workshop_notice_quote_total_internal(p_job public.mechanic_jobs)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select round(greatest(coalesce(sum(item.total_price), 0) - coalesce(p_job.discount_amount, 0), 0))
    from public.mechanic_job_items item
   where item.job_id = p_job.id
     and item.tenant_id = p_job.tenant_id;
$$;

revoke all on function public.workshop_notice_quote_total_internal(public.mechanic_jobs)
  from public, anon, authenticated, service_role;

-- «$59.990».
create or replace function public.workshop_notice_money_internal(p_amount numeric)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select '$' || replace(to_char(round(coalesce(p_amount, 0)), 'FM999,999,999,990'), ',', '.');
$$;

revoke all on function public.workshop_notice_money_internal(numeric)
  from public, anon, authenticated, service_role;

-- Lo que ve el cliente del presupuesto: cada línea con su nombre, cantidad y
-- precio, el descuento y el total. Nunca las notas internas de una línea ni
-- el costo.
create or replace function public.job_quote_document_projection_internal(
  p_job_id uuid,
  p_tenant_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'job_id', job.id,
    'job_number', job.job_number,
    'valid_until', job.quotation_valid_until,
    'customer', jsonb_build_object('name', nullif(btrim(customer.name), '')),
    'item', public.workshop_notice_item_internal(job),
    'client_request', nullif(btrim(job.client_request), ''),
    'diagnosis', nullif(btrim(job.diagnosis), ''),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
          'kind', case item.item_type
            when 'service' then 'service'
            when 'product' then 'part'
            else 'other'
          end,
          'name', coalesce(nullif(btrim(item.product_name), ''), nullif(btrim(item.description), ''), 'Ítem'),
          'quantity', item.quantity,
          'unit_price', item.unit_price,
          'total', item.total_price)
        order by item.created_at, item.id)
        from public.mechanic_job_items item
       where item.job_id = job.id
         and item.tenant_id = job.tenant_id
    ), '[]'::jsonb),
    'subtotal', (
      select round(coalesce(sum(item.total_price), 0))
        from public.mechanic_job_items item
       where item.job_id = job.id
         and item.tenant_id = job.tenant_id
    ),
    'discount', round(coalesce(job.discount_amount, 0)),
    'total', public.workshop_notice_quote_total_internal(job),
    'storefront', public.storefront_identity_internal(job.tenant_id)
  )
    from public.mechanic_jobs job
    left join public.customers customer
      on customer.id = job.customer_id
     and customer.tenant_id = job.tenant_id
   where job.id = p_job_id
     and job.tenant_id = p_tenant_id
     and job.deleted_at is null;
$$;

revoke all on function public.job_quote_document_projection_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Lo que lee la tienda con el código
-- ---------------------------------------------------------------------------

-- El PDF de un aviso para quien tiene su código: el presupuesto o el
-- comprobante, con lo mismo que ve el cliente en su cuenta. Un código
-- vencido, gastado (diez lecturas: un envío con sus reintentos) o
-- desconocido no dice nada.
create or replace function public.workshop_notice_document_v1(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_row public.workshop_notice_document_tokens%rowtype;
  v_notice public.workshop_customer_notices%rowtype;
  v_document_id uuid;
  v_quote jsonb;
begin
  if coalesce(p_token, '') !~ '^[A-Za-z0-9_-]{43}$' then
    return null;
  end if;
  select * into v_row
    from public.workshop_notice_document_tokens token
   where token.token_sha256 = encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
   for update;
  if not found or v_row.expires_at <= clock_timestamp() or v_row.reads >= 10 then
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
  'El presupuesto o el comprobante de un aviso del taller por WhatsApp, para la tienda que dibuja su PDF con el código de un solo uso del aviso.';

-- ---------------------------------------------------------------------------
-- 4. Cuándo un aviso lleva su PDF
-- ---------------------------------------------------------------------------

-- La tienda ya dibuja los PDF de los avisos: se enciende después de
-- desplegarla, para que un aviso nunca pida un PDF que nadie sabe dibujar.
create or replace function public.workshop_notice_documents_enabled_internal(p_tenant_id uuid)
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
       and setting.key = 'workshop_notice_documents_enabled'
     limit 1
  ), false);
$$;

revoke all on function public.workshop_notice_documents_enabled_internal(uuid)
  from public, anon, authenticated, service_role;

-- El aviso puede llevar su PDF: un presupuesto que se puede aprobar por
-- WhatsApp (cotización pendiente y vigente, con líneas y total; es lo que
-- exige `apply_whatsapp_job_action`), o una entrega con su comprobante.
create or replace function public.workshop_notice_document_ready_internal(
  p_kind text,
  p_job public.mechanic_jobs
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_job.id is null or not public.workshop_notice_documents_enabled_internal(p_job.tenant_id) then
    return false;
  end if;
  if p_kind = 'quote_ready' then
    return p_job.workflow_kind = 'quotation'
      and p_job.job_type = 'quotation'
      and p_job.quotation_status = 'pending'
      and (p_job.quotation_valid_until is null or p_job.quotation_valid_until > clock_timestamp())
      and exists (
        select 1 from public.mechanic_job_items item
         where item.job_id = p_job.id and item.tenant_id = p_job.tenant_id)
      and public.workshop_notice_quote_total_internal(p_job) > 0;
  elsif p_kind = 'delivered' then
    return exists (
      select 1 from public.mechanic_job_delivery_documents document
       where document.tenant_id = p_job.tenant_id and document.job_id = p_job.id);
  end if;
  return false;
end;
$$;

revoke all on function public.workshop_notice_document_ready_internal(text, public.mechanic_jobs)
  from public, anon, authenticated, service_role;

-- La primera aprobada en el orden de cada aviso: la del PDF si el trabajo
-- puede llevarlo, la `_v2` con botón, la `_v1` y, para el presupuesto y la
-- bici lista, la de antes.
create or replace function public.workshop_notice_template_v2_internal(
  p_tenant_id uuid,
  p_kind text,
  p_intake_kind text,
  p_document_ready boolean
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_choices text[] := case p_kind
    when 'received' then array['taller_recibida_v2', 'taller_recibida_v1']
    when 'quote_ready' then array['taller_presupuesto_pdf_v1', 'taller_presupuesto_v2',
                                  'taller_presupuesto_v1', 'seguimiento_presupuesto_bicicleta']
    when 'ready' then array['taller_lista_v2', 'taller_lista_v1', 'bicicleta_lista_retiro']
    when 'delivered' then array['taller_entregada_pdf_v1', 'taller_entregada_v2', 'taller_entregada_v1']
  end;
  v_name text;
begin
  foreach v_name in array coalesce(v_choices, array[]::text[])
  loop
    -- El PDF, sólo cuando el trabajo puede llevarlo.
    continue when v_name in ('taller_presupuesto_pdf_v1', 'taller_entregada_pdf_v1')
      and p_document_ready is not true;
    -- El mapa necesita el punto del taller.
    continue when v_name = 'taller_lista_v2'
      and public.workshop_notice_location_internal(p_tenant_id) is null;
    -- «tu bicicleta está lista»: sólo cuando lo que dejó es una bici.
    continue when v_name = 'bicicleta_lista_retiro'
      and coalesce(p_intake_kind, 'bike') = 'component';
    if public.whatsapp_template_approved_internal(p_tenant_id, v_name) then
      return v_name;
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function public.workshop_notice_template_v2_internal(uuid, text, text, boolean)
  from public, anon, authenticated, service_role;

-- La elección de siempre, sin PDF (la usan las lecturas y las pruebas).
create or replace function public.workshop_notice_template_internal(
  p_tenant_id uuid,
  p_kind text,
  p_intake_kind text
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.workshop_notice_template_v2_internal(p_tenant_id, p_kind, p_intake_kind, false);
$$;

revoke all on function public.workshop_notice_template_internal(uuid, text, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. El envío con el PDF
-- ---------------------------------------------------------------------------

-- Igual que en 20261107120000 salvo las dos plantillas con PDF: el código de
-- un solo uso va en `templateDocumentToken`, y el presupuesto pide además la
-- tarjeta `approve_quote` del trabajo con su monto.
create or replace function public.workshop_notice_dispatch_whatsapp_internal(
  p_notice_id uuid,
  p_now timestamptz,
  p_in_hours boolean
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_notice public.workshop_customer_notices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_reason text;
  v_template text;
  v_actor uuid;
  v_channel uuid;
  v_link text;
  v_code text;
  v_location jsonb;
  v_hours text;
  v_name text;
  v_item text;
  v_number text;
  v_until text;
  v_params text[];
  v_caption text;
  v_components jsonb;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
  v_document_ready boolean := false;
  v_document_token text;
  v_total numeric;
  v_amount text;
  v_request jsonb;
begin
  select * into v_notice
    from public.workshop_customer_notices notice
   where notice.id = p_notice_id
     and notice.channel = 'whatsapp'
     and notice.state = 'pending'
   for update skip locked;
  if not found then
    return null;
  end if;

  select * into v_job
    from public.mechanic_jobs job
   where job.id = v_notice.job_id and job.tenant_id = v_notice.tenant_id;
  v_reason := public.workshop_notice_stale_reason_internal(v_notice.kind, v_job);
  if v_reason is null then
    v_document_ready := public.workshop_notice_document_ready_internal(v_notice.kind, v_job);
    v_template := public.workshop_notice_template_v2_internal(
      v_notice.tenant_id, v_notice.kind, v_job.intake_kind, v_document_ready);
  end if;

  if v_reason is null and p_now >= v_notice.expires_at then
    v_reason := case when v_template is null then 'template_not_approved' else 'expired' end;
  end if;
  if v_reason is not null then
    update public.workshop_customer_notices
       set state = 'skipped', reason = v_reason, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'skipped';
  end if;
  -- De noche, o sin plantilla aprobada todavía: espera la siguiente pasada.
  if not p_in_hours or v_template is null then
    return 'pending';
  end if;

  select * into v_customer
    from public.customers customer
   where customer.id = v_job.customer_id and customer.tenant_id = v_job.tenant_id;
  v_name := nullif(btrim(coalesce(v_customer.name, '')), '');
  v_actor := public.workshop_notice_actor_internal(v_notice.tenant_id, v_notice.actor_id, v_job.created_by);
  select channel.id into v_channel
    from public.whatsapp_channels channel
   where channel.tenant_id = v_notice.tenant_id and channel.is_active
   order by channel.created_at
   limit 1;

  v_reason := case
    when v_name is null then 'no_customer'
    when v_actor is null then 'no_actor'
    when v_channel is null then 'no_channel'
  end;

  if v_reason is null then
    v_number := coalesce(nullif(btrim(v_job.job_number), ''), 'de taller');
    v_item := public.workshop_notice_item_internal(v_job);
  end if;

  if v_reason is null and v_template = 'taller_lista_v2' then
    v_location := public.workshop_notice_location_internal(v_notice.tenant_id);
    v_hours := coalesce(public.workshop_notice_hours_internal(v_notice.tenant_id),
      'en nuestro horario de atención');
    if v_location is null then
      v_reason := 'no_store_location';
    end if;
  end if;

  if v_reason is null
     and v_template in ('taller_entregada_v1', 'taller_entregada_v2', 'taller_entregada_pdf_v1') then
    select public.workshop_notice_date_internal(document.service_warranty_expires_at)
      into v_until
      from public.mechanic_job_delivery_documents document
     where document.tenant_id = v_job.tenant_id and document.job_id = v_job.id;
    if v_until is null then
      select public.workshop_notice_date_internal(event.warranty_expires_at)
        into v_until
        from public.mechanic_job_delivery_events event
       where event.id = v_notice.source_id;
    end if;
    if v_until is null then
      v_reason := 'no_warranty';
    end if;
  end if;

  -- El link o el código, al final: cada uno deja un código de cuenta nuevo,
  -- y un aviso que no sale no debe dejar códigos sueltos.
  if v_reason is null then
    if v_template in ('taller_recibida_v1', 'taller_presupuesto_v1', 'taller_lista_v1', 'taller_entregada_v1') then
      v_link := public.workshop_notice_link_internal(v_job, v_notice.kind, v_actor);
      if v_link is null then
        v_reason := 'no_store_url';
      end if;
    elsif v_template in ('taller_recibida_v2', 'taller_presupuesto_v2', 'taller_lista_v2',
                         'taller_entregada_v2', 'taller_entregada_pdf_v1') then
      v_code := public.workshop_notice_claim_code_internal(v_job, v_notice.kind, v_actor);
      if v_code is null then
        v_reason := 'no_customer';
      end if;
    end if;
  end if;

  -- El PDF: el código de un solo uso con que la tienda lo dibuja al enviar.
  if v_reason is null and v_template = 'taller_presupuesto_pdf_v1' then
    v_total := public.workshop_notice_quote_total_internal(v_job);
    v_amount := public.workshop_notice_money_internal(v_total);
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'quote');
  elsif v_reason is null and v_template = 'taller_entregada_pdf_v1' then
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'delivery');
  end if;

  if v_reason is null then
    if v_template = 'taller_presupuesto_pdf_v1' then
      v_params := array[v_name, v_number, v_amount];
      v_caption := format(
        'Hola %s, te enviamos el presupuesto de tu trabajo %s por %s. ¿Lo apruebas?',
        v_name, v_number, v_amount);
    elsif v_template = 'taller_entregada_pdf_v1' then
      v_params := array[v_name, v_number, v_until];
      v_caption := format(
        'Hola %s, tu trabajo %s quedó entregado. Te dejamos tu comprobante; la garantía del servicio vale hasta el %s. Gracias por confiar en Viñabike.',
        v_name, v_number, v_until);
    elsif v_template = 'taller_recibida_v2' then
      v_params := array[v_name, v_item, v_number];
      v_caption := format(
        'Hola %s, recibimos tu %s. Tu número de trabajo es %s y te avisaremos por aquí cuando esté listo.',
        v_name, v_item, v_number);
    elsif v_template = 'taller_presupuesto_v2' then
      v_params := array[v_name, v_number];
      v_caption := format(
        'Hola %s, el presupuesto de tu trabajo %s está listo. Revísalo y respóndenos por aquí para aprobarlo o hacer una consulta.',
        v_name, v_number);
    elsif v_template = 'taller_lista_v2' then
      v_params := array[v_name, v_number, v_hours];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo para retirar. Te esperamos %s. Si necesitas coordinar el retiro, respóndenos por aquí.',
        v_name, v_number, v_hours);
    elsif v_template = 'taller_entregada_v2' then
      v_params := array[v_name, v_number, v_until];
      v_caption := format(
        'Hola %s, tu trabajo %s quedó entregado. La garantía del servicio vale hasta el %s. Gracias por confiar en Viñabike.',
        v_name, v_number, v_until);
    elsif v_template = 'taller_recibida_v1' then
      v_params := array[v_name, v_item, v_number, v_link];
      v_caption := format(
        'Hola %s, recibimos tu %s en Viñabike. Tu número de trabajo es %s y aquí puedes seguir su estado: %s Te avisaremos por este medio cuando esté listo.',
        v_name, v_item, v_number, v_link);
    elsif v_template = 'taller_presupuesto_v1' then
      v_params := array[v_name, v_number, v_link];
      v_caption := format(
        'Hola %s, el presupuesto de tu trabajo %s está listo. Puedes verlo aquí: %s Para aprobarlo o hacer una consulta, responde este mensaje.',
        v_name, v_number, v_link);
    elsif v_template = 'taller_lista_v1' then
      v_params := array[v_name, v_number, v_link];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo para retirar en Viñabike. El detalle está aquí: %s Si necesitas coordinar el retiro, responde este mensaje.',
        v_name, v_number, v_link);
    elsif v_template = 'taller_entregada_v1' then
      v_params := array[v_name, v_number, v_until, v_link];
      v_caption := format(
        'Hola %s, gracias por retirar tu trabajo %s. La garantía del servicio vale hasta el %s y tu comprobante está aquí: %s Gracias por confiar en Viñabike.',
        v_name, v_number, v_until, v_link);
    elsif v_template = 'seguimiento_presupuesto_bicicleta' then
      v_params := array[v_name, 'Viñabike'];
      v_caption := format(
        'Hola %s, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en %s. Responde este mensaje para continuar.',
        v_name, 'Viñabike');
    elsif v_template = 'bicicleta_lista_retiro' then
      v_params := array[v_name, 'Viñabike'];
      v_caption := format(
        'Hola %s, tu bicicleta está lista para retiro en %s. Responde este mensaje si necesitas coordinar algo.',
        v_name, 'Viñabike');
    end if;

    v_components := jsonb_build_array(jsonb_build_object(
      'type', 'body',
      'parameters', (
        select jsonb_agg(jsonb_build_object('type', 'text', 'text', value) order by ord)
          from unnest(v_params) with ordinality as param(value, ord)
      )));
    if v_location is not null then
      v_components := jsonb_build_array(jsonb_build_object(
        'type', 'header',
        'parameters', jsonb_build_array(jsonb_build_object(
          'type', 'location', 'location', v_location)))) || v_components;
    end if;
    if v_code is not null then
      v_components := v_components || jsonb_build_array(jsonb_build_object(
        'type', 'button',
        'sub_type', 'url',
        'index', '0',
        'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_code))));
    end if;
  end if;

  if v_reason is null then
    begin
      -- Como quien hizo el cambio: la cola, la conversación y la bandeja
      -- aplican sus reglas de equipo y de tienda a esa persona.
      perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_actor, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_actor::text, true);

      v_binding := public.ensure_whatsapp_conversation_binding(
        p_tenant_id => v_notice.tenant_id,
        p_channel_id => v_channel,
        p_wa_id => v_notice.recipient,
        p_phone_number => v_notice.recipient,
        p_contact_name => v_name,
        p_customer_id => v_customer.id,
        p_context_type => 'job',
        p_context_id => v_job.id,
        p_conversation_id => null);
      v_conversation := (v_binding->>'conversation_id')::uuid;

      v_request := jsonb_build_object(
        'conversationId', v_conversation,
        'phoneNumber', v_notice.recipient,
        'contactName', v_name,
        'customerId', v_customer.id,
        'contextType', 'job',
        'contextId', v_job.id,
        'type', 'template',
        'templateName', v_template,
        'templateLanguage', 'es_CL',
        'caption', v_caption,
        'templateComponents', v_components,
        'metadata', jsonb_build_object(
          'source', 'workshop_notice',
          'client_message_id', 'workshop-notice:' || v_notice.id,
          'template_purpose', 'workshop_' || v_notice.kind,
          'template_name', v_template,
          'template_language', 'es_CL',
          'message_category', 'utility',
          'workshop_notice_id', v_notice.id,
          'job_id', v_job.id));
      if v_document_token is not null then
        v_request := v_request || jsonb_build_object('templateDocumentToken', v_document_token);
      end if;
      -- «Aprobar presupuesto» aprueba de verdad: whatsapp-send verifica el
      -- trabajo, pone la clave de un solo uso en la respuesta rápida y deja
      -- la tarjeta del presupuesto en la conversación
      -- (`apply_whatsapp_job_action`).
      if v_template = 'taller_presupuesto_pdf_v1' then
        v_request := v_request || jsonb_build_object(
          'actionType', 'approve_quote',
          'actionKind', 'job',
          'actionTargetId', v_job.id,
          'amount', v_total);
      end if;
      v_result := public.enqueue_whatsapp_message_v1(v_request);
      v_message := nullif(v_result->>'message_id', '')::uuid;
      if v_message is null then
        v_reason := 'send_not_accepted';
      end if;
    exception when others then
      v_reason := left('send_failed: ' || sqlerrm, 280);
    end;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  end if;

  if v_message is not null then
    update public.workshop_customer_notices
       set state = 'sent', sent_at = clock_timestamp(), template_name = v_template,
           message_id = v_message, attempt_count = attempt_count + 1,
           reason = null, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'sent';
  end if;

  update public.workshop_customer_notices
     set state = case when v_reason like 'send_%' then 'failed' else 'skipped' end,
         reason = v_reason, template_name = v_template,
         attempt_count = attempt_count + 1, updated_at = clock_timestamp()
   where id = v_notice.id;
  return case when v_reason like 'send_%' then 'failed' else 'skipped' end;
end;
$$;

revoke all on function public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamptz, boolean)
  from public, anon, authenticated, service_role;

commit;
