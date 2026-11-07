-- Los avisos del taller y el pedido de reseña con título, pie y botón
-- (dueño, 2026-11-07: «estos mensajes… parecen de esos SPAM que te mandan
-- desde la cárcel», «whatsapp no tiene recursos más elegantes para adjuntar
-- info, links, etc?»).
--
-- Los avisos `_v1` (20261105130000) llevan en el texto un link largo al azar
-- (la ficha del cliente con su código para crear la cuenta) y la reseña
-- `resena_google_v1` el link de Google: en el teléfono se leen como estafa.
-- Las plantillas nuevas (`supabase/functions/_shared/whatsapp_templates.ts`)
-- sacan el link del texto:
-- * `taller_recibida_v2`, `taller_presupuesto_v2` y `taller_entregada_v2`:
--   título en negrita, el pie «Viñabike · Taller de bicicletas» y un botón
--   («Seguir mi trabajo», «Ver presupuesto», «Ver comprobante») que abre la
--   ficha con un código nuevo como sufijo del link fijo
--   `https://vinabike.cl/cuenta/vincular#c=`;
-- * `taller_lista_v2`: el mapa del taller arriba del mensaje (el punto de la
--   ficha de Google del sitio, `seo_geo_latitude`/`seo_geo_longitude`), el
--   horario de atención dicho en el texto y el botón «Ver mi trabajo»;
-- * `resena_google_v2`: el botón «Dejar una reseña» con el lugar de Google
--   como sufijo.
--
-- La base prefiere cada `_v2` apenas Meta la aprueba
-- (`whatsapp_template_reviews`); mientras tanto sale la `_v1` como hasta hoy,
-- y antes de ella las plantillas antiguas que ya tenían de respaldo. «Listo
-- para retirar» usa la `_v2` sólo si el sitio tiene el punto del taller.
--
-- Con botón, el código para crear la cuenta se genera siempre, aun para quien
-- ya tiene una: la página del código lo lleva a entrar con la suya. El
-- enlace de la `_v1` y del correo no cambia (`workshop_notice_link_internal`).

begin;

-- ---------------------------------------------------------------------------
-- 1. Lo que lleva el botón: un código nuevo para la ficha del cliente
-- ---------------------------------------------------------------------------

-- El código sin el link: el botón lo agrega al final de la dirección fija de
-- la plantilla. Mismo código que el de la `_v1` (120 días, recepción o
-- entrega), sólo que también para quien ya tiene cuenta.
create or replace function public.workshop_notice_claim_code_internal(
  p_job public.mechanic_jobs,
  p_kind text,
  p_actor uuid
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_customer_id uuid;
  v_raw text;
begin
  select customer.id into v_customer_id
    from public.customers customer
   where customer.id = p_job.customer_id
     and customer.tenant_id = p_job.tenant_id
     and customer.is_active is true;
  if v_customer_id is null then
    return null;
  end if;

  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_portal_claim_codes (
    tenant_id, customer_id, job_id, purpose, code_sha256, expires_at, created_by
  ) values (
    p_job.tenant_id,
    v_customer_id,
    p_job.id,
    case when p_kind = 'delivered' then 'delivery' else 'reception' end,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '120 days',
    p_actor
  );
  return v_raw;
end;
$$;

revoke all on function public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. El taller en el mapa y su horario dicho como se dice
-- ---------------------------------------------------------------------------

-- El punto, el nombre y la dirección del taller para el mapa del mensaje.
-- El punto lo deja la ficha de Google del sitio (`google-public-data-refresh`).
-- Sin punto, nombre o dirección: null, y «Listo para retirar» sale sin mapa.
create or replace function public.workshop_notice_location_internal(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_latitude text;
  v_longitude text;
  v_name text;
  v_address text;
begin
  select btrim(max(setting.value) filter (where setting.key = 'seo_geo_latitude')),
         btrim(max(setting.value) filter (where setting.key = 'seo_geo_longitude')),
         nullif(btrim(max(setting.value) filter (where setting.key = 'store_name')), ''),
         nullif(btrim(regexp_replace(
           coalesce(max(setting.value) filter (where setting.key = 'contact_address'), ''),
           ',[[:space:]]*Chile[[:space:]]*$', '', 'i')), '')
    into v_latitude, v_longitude, v_name, v_address
    from public.website_settings setting
   where setting.tenant_id = p_tenant_id
     and setting.key in ('seo_geo_latitude', 'seo_geo_longitude', 'store_name', 'contact_address');

  if coalesce(v_latitude, '') !~ '^-?[0-9]{1,2}(\.[0-9]{1,8})?$'
     or coalesce(v_longitude, '') !~ '^-?[0-9]{1,3}(\.[0-9]{1,8})?$'
     or v_name is null
     or v_address is null then
    return null;
  end if;
  if abs(v_latitude::numeric) > 90 or abs(v_longitude::numeric) > 180 then
    return null;
  end if;
  return jsonb_build_object(
    'latitude', v_latitude,
    'longitude', v_longitude,
    'name', left(v_name, 100),
    'address', left(v_address, 200));
end;
$$;

revoke all on function public.workshop_notice_location_internal(uuid)
  from public, anon, authenticated, service_role;

-- El horario de atención como lo dice una persona, desde el horario de la
-- ficha de Google del sitio (`business_hours_json`, días 0 = domingo): «de
-- lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30». Junta los
-- días seguidos con el mismo horario. Con dos turnos en un día, un cierre
-- después de medianoche o sin horario: null (el aviso dice «en nuestro
-- horario de atención»).
create or replace function public.workshop_notice_hours_internal(p_tenant_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_raw text;
  v_periods jsonb;
  v_period jsonb;
  v_day integer;
  v_opens text;
  v_closes text;
  -- 1 = lunes … 7 = domingo.
  v_by_day text[] := array[null, null, null, null, null, null, null]::text[];
  v_names text[] := array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  v_plural text[] := array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];
  v_groups text[] := array[]::text[];
  v_first integer := 1;
  v_last integer;
  v_count integer;
begin
  select setting.value into v_raw
    from public.website_settings setting
   where setting.tenant_id = p_tenant_id
     and setting.key = 'business_hours_json';
  begin
    v_periods := v_raw::jsonb -> 'periods';
  exception when others then
    return null;
  end;
  if v_periods is null or jsonb_typeof(v_periods) <> 'array' or jsonb_array_length(v_periods) = 0 then
    return null;
  end if;

  for v_period in select value from jsonb_array_elements(v_periods)
  loop
    v_opens := v_period #>> '{open,time}';
    v_closes := v_period #>> '{close,time}';
    if coalesce(v_period #>> '{open,day}', '') !~ '^[0-6]$'
       or (v_period #>> '{close,day}') is distinct from (v_period #>> '{open,day}')
       or coalesce(v_opens, '') !~ '^([01][0-9]|2[0-3])[0-5][0-9]$'
       or coalesce(v_closes, '') !~ '^([01][0-9]|2[0-3])[0-5][0-9]$'
       or v_closes <= v_opens then
      return null;
    end if;
    v_day := (v_period #>> '{open,day}')::integer;
    v_day := case when v_day = 0 then 7 else v_day end;
    if v_by_day[v_day] is not null then
      return null;
    end if;
    v_by_day[v_day] := format('de %s:%s a %s:%s',
      substr(v_opens, 1, 2)::integer, substr(v_opens, 3, 2),
      substr(v_closes, 1, 2)::integer, substr(v_closes, 3, 2));
  end loop;

  while v_first <= 7 loop
    if v_by_day[v_first] is null then
      v_first := v_first + 1;
      continue;
    end if;
    v_last := v_first;
    while v_last < 7 and v_by_day[v_last + 1] is not distinct from v_by_day[v_first] loop
      v_last := v_last + 1;
    end loop;
    v_groups := v_groups || (case
      when v_last = v_first then 'los ' || v_plural[v_first]
      when v_last = v_first + 1 then 'los ' || v_plural[v_first] || ' y ' || v_plural[v_last]
      else 'de ' || v_names[v_first] || ' a ' || v_names[v_last]
    end || ' ' || v_by_day[v_first]);
    v_first := v_last + 1;
  end loop;

  v_count := coalesce(array_length(v_groups, 1), 0);
  return case
    when v_count = 0 then null
    when v_count = 1 then v_groups[1]
    else array_to_string(v_groups[1:v_count - 1], ', ') || ' y ' || v_groups[v_count]
  end;
end;
$$;

revoke all on function public.workshop_notice_hours_internal(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Con qué plantilla sale cada aviso
-- ---------------------------------------------------------------------------

-- La primera aprobada en el orden de cada aviso: la `_v2` con botón, la
-- `_v1` y, para el presupuesto y la bici lista, la de antes. Ninguna: null
-- (el aviso espera).
create or replace function public.workshop_notice_template_internal(
  p_tenant_id uuid,
  p_kind text,
  p_intake_kind text
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
    when 'quote_ready' then array['taller_presupuesto_v2', 'taller_presupuesto_v1',
                                  'seguimiento_presupuesto_bicicleta']
    when 'ready' then array['taller_lista_v2', 'taller_lista_v1', 'bicicleta_lista_retiro']
    when 'delivered' then array['taller_entregada_v2', 'taller_entregada_v1']
  end;
  v_name text;
begin
  foreach v_name in array coalesce(v_choices, array[]::text[])
  loop
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

revoke all on function public.workshop_notice_template_internal(uuid, text, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. El envío: el texto, el mapa y el botón de cada plantilla
-- ---------------------------------------------------------------------------

-- Igual que en 20261105130000 salvo lo que arma cada plantilla: la `_v2`
-- manda su botón con el código (componente `button`, índice 0) y la bici
-- lista, el mapa (componente `header` de tipo `location`). El texto que
-- guarda la bandeja es el cuerpo aprobado de cada una, sin el código.
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
  v_template := case when v_reason is null
    then public.workshop_notice_template_internal(v_notice.tenant_id, v_notice.kind, v_job.intake_kind)
  end;

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

  if v_reason is null and v_template in ('taller_entregada_v1', 'taller_entregada_v2') then
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
    elsif v_template in ('taller_recibida_v2', 'taller_presupuesto_v2', 'taller_lista_v2', 'taller_entregada_v2') then
      v_code := public.workshop_notice_claim_code_internal(v_job, v_notice.kind, v_actor);
      if v_code is null then
        v_reason := 'no_customer';
      end if;
    end if;
  end if;

  if v_reason is null then
    if v_template = 'taller_recibida_v2' then
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

      v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
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
          'job_id', v_job.id)));
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

-- ---------------------------------------------------------------------------
-- 5. El pedido de reseña con botón
-- ---------------------------------------------------------------------------

-- Igual que en 20261008200000 salvo la plantilla: `resena_google_v2` apenas
-- Meta la aprueba (el lugar de Google va en el botón), y mientras tanto la
-- `_v1` con el link en el texto.
create or replace function public.process_whatsapp_review_requests_v1(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_local_hour integer := extract(hour from (p_now at time zone 'America/Santiago'))::integer;
  v_row record;
  v_phone text;
  v_place text;
  v_channel uuid;
  v_reason text;
  v_name text;
  v_link text;
  v_template text;
  v_caption text;
  v_components jsonb;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
  v_sent integer := 0;
  v_skipped integer := 0;
begin
  -- Nadie recibe un pedido de reseña de noche: lo que llega fuera de la
  -- ventana espera a la siguiente pasada dentro de ella (la entrega sigue
  -- vigente 3 días).
  if v_local_hour < 10 or v_local_hour >= 20 then
    return jsonb_build_object('sent', 0, 'skipped', 0, 'outside_hours', true);
  end if;

  for v_row in
    select e.id as event_id, e.tenant_id, e.job_id, e.actor_id,
           j.status as job_status, j.customer_id,
           c.name as customer_name, c.phone as customer_phone
      from public.mechanic_job_delivery_events e
      join public.company_settings s
        on s.tenant_id = e.tenant_id
       and s.key = 'whatsapp_review_request_enabled'
       and s.value = 'true'
      join public.mechanic_jobs j
        on j.id = e.job_id and j.tenant_id = e.tenant_id
      left join public.customers c
        on c.id = j.customer_id and c.tenant_id = j.tenant_id
     where e.event_kind = 'delivered'
       and e.source = 'status_transition'
       and e.occurred_at > p_now - interval '3 days'
       and e.occurred_at <= p_now - interval '3 hours'
       and not exists (
         select 1 from public.whatsapp_review_requests r
          where r.tenant_id = e.tenant_id and r.job_id = e.job_id)
     order by e.occurred_at
     limit 20
  loop
    v_reason := null;
    v_message := null;
    v_phone := public.normalize_whatsapp_phone(v_row.customer_phone);
    v_name := nullif(btrim(coalesce(v_row.customer_name, '')), '');

    select nullif(btrim(value), '') into v_place
      from public.website_settings
     where tenant_id = v_row.tenant_id and key = 'google_maps_place_id';
    select id into v_channel
      from public.whatsapp_channels
     where tenant_id = v_row.tenant_id and is_active
     order by created_at
     limit 1;

    if v_row.job_status is distinct from 'ENTREGADO' then
      v_reason := 'job_not_delivered';
    elsif v_row.customer_id is null or v_name is null then
      v_reason := 'no_customer';
    elsif v_phone is null or v_phone !~ '^569[0-9]{8}$' then
      v_reason := 'no_mobile';
    elsif v_row.actor_id is null then
      v_reason := 'no_actor';
    elsif exists (
      select 1 from public.whatsapp_review_requests r
       where r.tenant_id = v_row.tenant_id
         and r.status = 'sent'
         and r.created_at > p_now - interval '365 days'
         and (r.customer_id = v_row.customer_id or r.phone = v_phone)) then
      v_reason := 'asked_this_year';
    elsif v_place is null or v_place !~ '^[A-Za-z0-9_-]{10,}$' then
      v_reason := 'no_review_link';
    elsif v_channel is null then
      v_reason := 'no_channel';
    end if;

    if v_reason is null then
      -- El lugar va sin codificar en el botón: el patrón de arriba sólo deja
      -- letras, números, guion y guion bajo.
      if public.whatsapp_template_approved_internal(v_row.tenant_id, 'resena_google_v2') then
        v_template := 'resena_google_v2';
        v_caption := format(
          'Hola %s, gracias por elegir Viñabike. Si te gustó el servicio, una reseña en Google nos ayuda mucho.',
          v_name);
        v_components := jsonb_build_array(
          jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_name))),
          jsonb_build_object(
            'type', 'button',
            'sub_type', 'url',
            'index', '0',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_place))));
      else
        v_template := 'resena_google_v1';
        v_link := 'https://search.google.com/local/writereview?placeid=' || v_place;
        v_caption := format(
          'Hola %s, ya entregamos tu bicicleta en Viñabike. ¿Cómo te fue con el servicio? Puedes contarnos con una reseña en Google: %s Gracias por preferirnos.',
          v_name, v_link);
        v_components := jsonb_build_array(jsonb_build_object(
          'type', 'body',
          'parameters', jsonb_build_array(
            jsonb_build_object('type', 'text', 'text', v_name),
            jsonb_build_object('type', 'text', 'text', v_link))));
      end if;

      begin
        -- Como quien entregó la bici: la cola, la conversación y la bandeja
        -- aplican sus reglas de equipo y de tienda a esa persona.
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_row.actor_id, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', v_row.actor_id::text, true);

        v_binding := public.ensure_whatsapp_conversation_binding(
          p_tenant_id => v_row.tenant_id,
          p_channel_id => v_channel,
          p_wa_id => v_phone,
          p_phone_number => v_phone,
          p_contact_name => v_name,
          p_customer_id => v_row.customer_id,
          p_context_type => 'job',
          p_context_id => v_row.job_id,
          p_conversation_id => null);
        v_conversation := (v_binding->>'conversation_id')::uuid;

        -- El texto es el cuerpo aprobado de la plantilla con sus parámetros;
        -- el envío lo acorta al nombre de pila igual que en las demás
        -- plantillas (`template_purpose`).
        v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
          'conversationId', v_conversation,
          'phoneNumber', v_phone,
          'contactName', v_name,
          'customerId', v_row.customer_id,
          'contextType', 'job',
          'contextId', v_row.job_id,
          'type', 'template',
          'templateName', v_template,
          'templateLanguage', 'es_CL',
          'caption', v_caption,
          'templateComponents', v_components,
          'metadata', jsonb_build_object(
            'source', 'review_request',
            'client_message_id', 'review-request:' || v_row.job_id,
            'template_purpose', 'google_review_request',
            'template_name', v_template,
            'template_language', 'es_CL',
            'message_category', 'utility',
            'job_id', v_row.job_id)));
        v_message := nullif(v_result->>'message_id', '')::uuid;
        if v_message is null then
          v_reason := 'send_not_accepted';
        end if;
      exception when others then
        v_reason := left('send_failed: ' || sqlerrm, 240);
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;

    insert into public.whatsapp_review_requests(
      tenant_id, job_id, delivery_event_id, customer_id, phone, actor_id,
      status, reason, message_id)
    values (
      v_row.tenant_id, v_row.job_id, v_row.event_id, v_row.customer_id, v_phone,
      v_row.actor_id,
      case when v_reason is null then 'sent' else 'skipped' end,
      v_reason, v_message)
    on conflict (tenant_id, job_id) do nothing;

    if v_reason is null then
      v_sent := v_sent + 1;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object('sent', v_sent, 'skipped', v_skipped);
end;
$$;

revoke all on function public.process_whatsapp_review_requests_v1(timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.process_whatsapp_review_requests_v1(timestamptz) to service_role;

comment on function public.process_whatsapp_review_requests_v1(timestamptz) is
  'Pide por WhatsApp una reseña de Google a quien retiró su bicicleta (3 h a 3 días después, 10-20 h de Chile, una vez al año por cliente), con el botón de resena_google_v2 apenas Meta la aprueba.';

-- ---------------------------------------------------------------------------
-- 6. Un correo que falla sin tiempo para reintentar queda fallido
-- ---------------------------------------------------------------------------

-- Igual que en 20261105130000 salvo el reintento. Antes, un correo de aviso
-- que fallaba cerca de su plazo se reprogramaba después de vencer: la fila
-- violaba `workshop_customer_notices_window` (`expires_at > available_at`),
-- la llamada del worker se caía y el aviso quedaba tomado hasta que su
-- arriendo vencía. Lo destapó el pgTAP de los avisos al correr dos días
-- después de sus fechas fijas. Sin tiempo para el próximo intento, el aviso
-- queda `failed` con el error del proveedor, como cuando se acaban los
-- intentos.
create or replace function public.complete_workshop_customer_notice_v1(
  p_notice_id uuid,
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
  v_notice public.workshop_customer_notices%rowtype;
  v_next_at timestamptz;
begin
  select * into v_notice from public.workshop_customer_notices
   where id = p_notice_id and lease_owner = p_worker_id and state = 'sending'
   for update;
  if not found then
    return 'not_leased';
  end if;
  v_next_at := clock_timestamp()
    + make_interval(mins => least(60, 2 ^ v_notice.attempt_count)::integer);
  if p_outcome = 'sent' then
    update public.workshop_customer_notices
       set state = 'sent', sent_at = clock_timestamp(),
           provider_message_id = left(p_provider_message_id, 200),
           lease_owner = null, lease_until = null, reason = null, updated_at = clock_timestamp()
     where id = p_notice_id;
  elsif p_outcome = 'retry'
        and v_notice.attempt_count < v_notice.max_attempts
        and v_next_at < v_notice.expires_at then
    update public.workshop_customer_notices
       set state = 'pending', lease_owner = null, lease_until = null,
           available_at = v_next_at,
           reason = left(p_error, 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  elsif p_outcome = 'skipped' then
    update public.workshop_customer_notices
       set state = 'skipped', lease_owner = null, lease_until = null,
           reason = left(coalesce(p_error, 'skipped'), 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  else
    update public.workshop_customer_notices
       set state = 'failed', lease_owner = null, lease_until = null,
           reason = left(coalesce(p_error, 'failed'), 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  end if;
  return (select state from public.workshop_customer_notices where id = p_notice_id);
end;
$$;

revoke all on function public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)
  to service_role;

commit;
