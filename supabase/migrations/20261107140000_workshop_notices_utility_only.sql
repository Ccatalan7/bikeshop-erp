-- Los avisos del taller salen sólo con plantillas de servicio, y la página
-- de avisos ve todas las plantillas del taller (2026-11-07).
--
-- * Meta dejó `taller_lista_v2` (el mapa, el horario y el botón) como
--   MARKETING al crearla, aunque se pidió UTILITY: la categoría la pone Meta
--   al revisar el texto. Un mensaje de publicidad cuesta más, Meta no se lo
--   entrega a quien ya recibió mucha publicidad (error 131049) y supone que el
--   cliente aceptó recibirla. Un aviso del taller no es publicidad: ahora
--   elige sólo entre las aprobadas que Meta deja como UTILITY. Una revisión
--   sin categoría (filas viejas) sigue valiendo.
-- * `taller_lista_v3`: el mismo mapa, horario y botón, con «Puedes retirarlo
--   …» en vez de «Te esperamos …», que es la frase que más se parece a una
--   invitación. La base la prefiere apenas Meta la aprueba como UTILITY.
-- * «Avisos y garantía» pedía a la base sólo las plantillas `_v1` y las de
--   antes, así que mostraba «Falta crearla en Meta» para las `_v2` que ya
--   estaban en revisión, y su botón las habría pedido otra vez. Ahora lee
--   todas las del taller (`taller_*` y las dos de antes), con su categoría.

begin;

-- ---------------------------------------------------------------------------
-- 1. Una plantilla sirve para un aviso si Meta la aprobó como de servicio
-- ---------------------------------------------------------------------------

create or replace function public.workshop_notice_template_usable_internal(
  p_tenant_id uuid,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.whatsapp_template_reviews review
     where review.tenant_id = p_tenant_id
       and review.template_name = p_name
       and review.template_language = 'es_CL'
       and review.status = 'APPROVED'
       and coalesce(review.category, 'UTILITY') = 'UTILITY'
       and review.checked_at > clock_timestamp() - interval '7 days');
$$;

revoke all on function public.workshop_notice_template_usable_internal(uuid, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. La elección: `taller_lista_v3` primero, y sólo las de servicio
-- ---------------------------------------------------------------------------

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
    when 'ready' then array['taller_lista_v3', 'taller_lista_v2', 'taller_lista_v1',
                            'bicicleta_lista_retiro']
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
    continue when v_name in ('taller_lista_v2', 'taller_lista_v3')
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
$$;

revoke all on function public.workshop_notice_template_v2_internal(uuid, text, text, boolean)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. El envío: `taller_lista_v3` lleva lo mismo que la `_v2`
-- ---------------------------------------------------------------------------

-- Igual que en 20261107130000 salvo `taller_lista_v3`: el mapa, el horario
-- en el texto y el código de la cuenta en el botón, como la `_v2`.
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

  if v_reason is null and v_template in ('taller_lista_v2', 'taller_lista_v3') then
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
                         'taller_lista_v3', 'taller_entregada_v2', 'taller_entregada_pdf_v1') then
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

-- ---------------------------------------------------------------------------
-- 4. La página de avisos ve todas las plantillas del taller
-- ---------------------------------------------------------------------------

-- Igual que en 20261105130000 salvo `templates`: todas las `taller_*` y las
-- dos de antes, con la categoría que les dejó Meta.
create or replace function public.workshop_customer_notice_overview_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings record;
begin
  if not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'workshop_notices_not_allowed' using errcode = '42501';
  end if;
  select * into v_settings from public.workshop_notice_settings_internal(p_tenant_id);
  return jsonb_build_object(
    'started_at', v_settings.started_at,
    'can_edit', public.can_edit_tenant_settings(p_tenant_id),
    'email_switch', coalesce((
      select btrim(setting.value) <> 'false' from public.company_settings setting
       where setting.tenant_id = p_tenant_id and setting.key = 'workshop_notices_email_enabled'
    ), true),
    'whatsapp_switch', coalesce((
      select btrim(setting.value) <> 'false' from public.company_settings setting
       where setting.tenant_id = p_tenant_id and setting.key = 'workshop_notices_whatsapp_enabled'
    ), true),
    'email_ready', exists (
      select 1 from public.transactional_email_settings email
       where email.tenant_id = p_tenant_id and email.enabled
         and email.delivery_mode = 'send' and email.from_email is not null),
    'whatsapp_ready', exists (
      select 1 from public.whatsapp_channels channel
       where channel.tenant_id = p_tenant_id and channel.is_active),
    'counts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', kind, 'channel', channel, 'state', state, 'reason', reason, 'count', total)
             order by kind, channel, state, reason)
        from (
          select notice.kind, notice.channel, notice.state, notice.reason, count(*) as total
            from public.workshop_customer_notices notice
           where notice.tenant_id = p_tenant_id
             and notice.created_at > clock_timestamp() - interval '30 days'
           group by 1, 2, 3, 4
        ) grouped
    ), '[]'::jsonb),
    'last_sent_at', (
      select max(notice.sent_at) from public.workshop_customer_notices notice
       where notice.tenant_id = p_tenant_id and notice.state = 'sent'),
    'templates', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', review.template_name, 'status', review.status,
               'category', review.category,
               'rejected_reason', review.rejected_reason, 'checked_at', review.checked_at)
             order by review.template_name)
        from public.whatsapp_template_reviews review
       where review.tenant_id = p_tenant_id
         and review.template_language = 'es_CL'
         and (left(review.template_name, 7) = 'taller_'
              or review.template_name in ('seguimiento_presupuesto_bicicleta', 'bicicleta_lista_retiro'))
    ), '[]'::jsonb),
    'warranty', (
      select jsonb_build_object('service_days', policy.service_days, 'parts_months', policy.parts_months)
        from public.workshop_warranty_policy_v1(p_tenant_id) policy
    )
  );
end;
$$;

revoke all on function public.workshop_customer_notice_overview_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.workshop_customer_notice_overview_v1(uuid) to authenticated;

commit;
