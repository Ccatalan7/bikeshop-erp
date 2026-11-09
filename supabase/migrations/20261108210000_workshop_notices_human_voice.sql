-- Los avisos del taller con trato humano (dueño, 2026-11-08: «para de
-- centrarte tanto en que lo más importante es el número de trabajo… a un
-- cliente le importa una mierda eso… el contacto humano con el cliente es lo
-- primero»).
--
-- Las plantillas nuevas nombran la bici o el componente
-- (`workshop_notice_item_internal`, lo mismo que ya decía «Trabajo
-- recibido») en vez del número de trabajo, y el presupuesto ya no dice el
-- monto: el número y la plata siguen en el PDF y en la ficha del cliente.
--
--   taller_recibida_v3, taller_presupuesto_pdf_v2, taller_lista_v4,
--   taller_entregada_pdf_v2 y resena_google_v3
--
-- Se crearon en Meta el 2026-11-08 desde «Avisos y garantía» y la tarjeta de
-- reseñas. La base las prefiere apenas Meta las aprueba como UTILITY
-- (`workshop_notice_template_usable_internal`; la reseña, apenas Meta la
-- aprueba); mientras tanto sale la anterior de cada aviso, igual que hoy.
-- El texto de cada `format` es el cuerpo aprobado de su plantilla en
-- `supabase/functions/_shared/whatsapp_templates.ts`.

do $$
declare
  v_expected constant jsonb := jsonb_build_object(
    'workshop_notice_template_v2_internal', '2ec57d90a9fc7ad2316090f47e9a6c6c',
    'workshop_notice_dispatch_whatsapp_internal', '02ece0f1289effc755a661b64af1ec11',
    'process_whatsapp_review_requests_v1', 'ec297f7ca497db43eff6452481bccbac');
  v_name text;
begin
  -- Los cuerpos que se reemplazan son los de 20261107140000 y
  -- 20261107120000, sin cambios desde entonces. Si alguien los cambió, se
  -- revisan antes de pisarlos.
  for v_name in select jsonb_object_keys(v_expected) loop
    if (select md5(p.prosrc)
          from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = v_name)
       is distinct from v_expected->>v_name then
      raise exception '% cambió desde su última migración; revisarla antes de reemplazarla', v_name;
    end if;
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.workshop_notice_template_v2_internal(p_tenant_id uuid, p_kind text, p_intake_kind text, p_document_ready boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_choices text[] := case p_kind
    when 'received' then array['taller_recibida_v3', 'taller_recibida_v2', 'taller_recibida_v1']
    when 'quote_ready' then array['taller_presupuesto_pdf_v2', 'taller_presupuesto_pdf_v1',
                                  'taller_presupuesto_v2', 'taller_presupuesto_v1',
                                  'seguimiento_presupuesto_bicicleta']
    when 'ready' then array['taller_lista_v4', 'taller_lista_v3', 'taller_lista_v2',
                            'taller_lista_v1', 'bicicleta_lista_retiro']
    when 'delivered' then array['taller_entregada_pdf_v2', 'taller_entregada_pdf_v1',
                                'taller_entregada_v2', 'taller_entregada_v1']
  end;
  v_name text;
begin
  foreach v_name in array coalesce(v_choices, array[]::text[])
  loop
    -- El PDF, sólo cuando el trabajo puede llevarlo.
    continue when v_name in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2',
                             'taller_entregada_pdf_v1', 'taller_entregada_pdf_v2')
      and p_document_ready is not true;
    -- El mapa necesita el punto del taller.
    continue when v_name in ('taller_lista_v2', 'taller_lista_v3', 'taller_lista_v4')
      and public.workshop_notice_location_internal(p_tenant_id) is null;
    -- «tu bicicleta está lista»: sólo cuando lo que dejó es una bici.
    continue when v_name = 'bicicleta_lista_retiro'
      and coalesce(p_intake_kind, 'bike') = 'component';
    if public.workshop_notice_template_usable_internal(p_tenant_id, v_name) then
      return v_name;
    end if;
  end loop;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_notice_dispatch_whatsapp_internal(p_notice_id uuid, p_now timestamp with time zone, p_in_hours boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  if v_reason is null and v_template in ('taller_lista_v2', 'taller_lista_v3', 'taller_lista_v4') then
    v_location := public.workshop_notice_location_internal(v_notice.tenant_id);
    v_hours := coalesce(public.workshop_notice_hours_internal(v_notice.tenant_id),
      'en nuestro horario de atención');
    if v_location is null then
      v_reason := 'no_store_location';
    end if;
  end if;

  if v_reason is null
     and v_template in ('taller_entregada_v1', 'taller_entregada_v2', 'taller_entregada_pdf_v1',
                        'taller_entregada_pdf_v2') then
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
                         'taller_lista_v3', 'taller_entregada_v2', 'taller_entregada_pdf_v1',
                         'taller_recibida_v3', 'taller_lista_v4', 'taller_entregada_pdf_v2') then
      v_code := public.workshop_notice_claim_code_internal(v_job, v_notice.kind, v_actor);
      if v_code is null then
        v_reason := 'no_customer';
      end if;
    end if;
  end if;

  -- El PDF: el código de un solo uso con que la tienda lo dibuja al enviar.
  if v_reason is null and v_template in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2') then
    v_total := public.workshop_notice_quote_total_internal(v_job);
    v_amount := public.workshop_notice_money_internal(v_total);
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'quote');
  elsif v_reason is null and v_template in ('taller_entregada_pdf_v1', 'taller_entregada_pdf_v2') then
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'delivery');
  end if;

  if v_reason is null then
    -- Trato humano (2026-11-08): la bici o el componente en vez del número
    -- de trabajo, y el presupuesto sin el monto, que va en el PDF.
    if v_template = 'taller_recibida_v3' then
      v_params := array[v_name, v_item];
      v_caption := format(
        'Hola %s, ya tenemos tu %s en el taller. Te iremos contando por aquí cómo va el trabajo, y si te surge cualquier duda, respóndenos en este mismo chat.',
        v_name, v_item);
    elsif v_template = 'taller_presupuesto_pdf_v2' then
      v_params := array[v_name, v_item];
      v_caption := format(
        'Hola %s, te dejamos el presupuesto para tu %s en el PDF adjunto. Revísalo con calma: si quieres cambiar algo o tienes alguna duda, cuéntanos por aquí y lo conversamos. Si está todo en orden, puedes aprobarlo directamente desde este mensaje.',
        v_name, v_item);
    elsif v_template = 'taller_lista_v4' then
      v_params := array[v_name, v_item, v_hours];
      v_caption := format(
        'Hola %s, terminamos el trabajo en tu %s y ya está todo listo para el retiro. Puedes pasar %s. Si necesitas coordinar el retiro, avísanos por aquí.',
        v_name, v_item, v_hours);
    elsif v_template = 'taller_entregada_pdf_v2' then
      v_params := array[v_name, v_item, v_until];
      v_caption := format(
        'Hola %s, gracias por dejar tu %s en nuestras manos. Te dejamos el comprobante del trabajo: el servicio tiene garantía hasta el %s, así que si antes de esa fecha algo no funciona como debería, escríbenos por aquí y lo revisamos.',
        v_name, v_item, v_until);
    elsif v_template = 'taller_presupuesto_pdf_v1' then
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
    elsif v_template = 'taller_lista_v3' then
      v_params := array[v_name, v_number, v_hours];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo. Puedes retirarlo %s. Si necesitas coordinar el retiro, respóndenos por aquí.',
        v_name, v_number, v_hours);
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
      if v_template in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2') then
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
$function$
;

CREATE OR REPLACE FUNCTION public.process_whatsapp_review_requests_v1(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
  v_job public.mechanic_jobs%rowtype;
  v_item text;
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
      if public.whatsapp_template_approved_internal(v_row.tenant_id, 'resena_google_v3') then
        -- Trato humano (2026-11-08): nombra la bici en vez de la tienda.
        select * into v_job
          from public.mechanic_jobs job
         where job.id = v_row.job_id and job.tenant_id = v_row.tenant_id;
        v_item := public.workshop_notice_item_internal(v_job);
        v_template := 'resena_google_v3';
        v_caption := format(
          'Hola %s, ojalá estés disfrutando tu %s. Si quedaste conforme con el servicio, una reseña en Google nos ayuda mucho.',
          v_name, v_item);
        v_components := jsonb_build_array(
          jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(
              jsonb_build_object('type', 'text', 'text', v_name),
              jsonb_build_object('type', 'text', 'text', v_item))),
          jsonb_build_object(
            'type', 'button',
            'sub_type', 'url',
            'index', '0',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_place))));
      elsif public.whatsapp_template_approved_internal(v_row.tenant_id, 'resena_google_v2') then
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
$function$
;


revoke all on function public.workshop_notice_template_v2_internal(uuid, text, text, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamptz, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.process_whatsapp_review_requests_v1(timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.process_whatsapp_review_requests_v1(timestamptz) to service_role;

comment on function public.process_whatsapp_review_requests_v1(timestamptz) is
  'Pide por WhatsApp una reseña de Google a quien retiró su bicicleta (3 h a 3 días después, 10-20 h de Chile, una vez al año por cliente): resena_google_v3, que nombra la bici, apenas Meta la aprueba; si no, resena_google_v2 con botón o la v1.';
