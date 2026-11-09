-- Las respuestas que salen solas cuando el cliente toca un botón del
-- presupuesto (dueño, 2026-11-08, al aprobar los textos: «mucho mejor wn,
-- súbelas»):
--
-- * «Aprobar presupuesto», una vez aplicado: «Gracias, Camila, quedó aprobado.
--   Ya nos ponemos manos a la obra con tu Trek Marlin 7 y te avisamos por
--   aquí apenas terminemos.»
-- * «Tengo una consulta»: «Claro, Camila. Cuéntanos tu consulta por aquí y te
--   respondemos lo antes posible.»
--
-- El toque del cliente abre la ventana de 24 horas de WhatsApp, así que son
-- mensajes normales: no necesitan plantilla ni revisión de Meta. Salen por la
-- bandeja de salida a nombre de quien atiende el trabajo, como los avisos, y
-- una falla al encolarlas nunca deshace la aprobación ni el ingreso del
-- mensaje. Un toque repetido no manda otra (la clave es el mensaje del
-- cliente, y un segundo «Aprobar» vuelve como repetido antes de llegar aquí).

do $$
begin
  -- El cuerpo que se reemplaza es el de 20261108200000. Si alguien lo
  -- cambió, se revisa antes de pisarlo.
  if (select md5(p.prosrc)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'apply_whatsapp_job_action')
     is distinct from '60ff9def3ffbb564bdf5aeceef28552c' then
    raise exception 'apply_whatsapp_job_action cambió desde 20261108200000; revisarla antes de reemplazarla';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Encolar la respuesta, a nombre de quien atiende el trabajo
-- ---------------------------------------------------------------------------

create or replace function public.whatsapp_card_reply_internal(
  p_tenant_id uuid,
  p_conversation_id uuid,
  p_customer_id uuid,
  p_phone text,
  p_job_id uuid,
  p_kind text,
  p_key text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_first text;
  v_item text;
  v_text text;
  v_actor uuid;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_result jsonb;
begin
  select * into v_job
    from public.mechanic_jobs job
   where job.id = p_job_id and job.tenant_id = p_tenant_id;
  select * into v_customer
    from public.customers customer
   where customer.id = p_customer_id and customer.tenant_id = p_tenant_id;
  v_first := public.customer_first_name_internal(v_customer.name);
  v_actor := public.workshop_notice_actor_internal(p_tenant_id, null, v_job.created_by);
  if v_job.id is null or v_first is null or v_actor is null
     or nullif(btrim(coalesce(p_phone, '')), '') is null then
    return null;
  end if;
  v_item := public.workshop_notice_item_internal(v_job);
  v_text := case p_kind
    when 'quote_approved' then format(
      'Gracias, %s, quedó aprobado. Ya nos ponemos manos a la obra con tu %s y te avisamos por aquí apenas terminemos.',
      v_first, v_item)
    when 'question' then format(
      'Claro, %s. Cuéntanos tu consulta por aquí y te respondemos lo antes posible.',
      v_first)
  end;
  if v_text is null then
    return null;
  end if;

  begin
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', v_actor, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_actor::text, true);
    v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
      'conversationId', p_conversation_id,
      'phoneNumber', p_phone,
      'contactName', v_customer.name,
      'customerId', v_customer.id,
      'contextType', 'job',
      'contextId', v_job.id,
      'type', 'text',
      'text', v_text,
      'metadata', jsonb_build_object(
        'source', 'workshop_card_reply',
        'client_message_id', p_key,
        'card_reply_kind', p_kind,
        'job_id', v_job.id)));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
    return nullif(v_result->>'message_id', '')::uuid;
  exception when others then
    -- Una respuesta de cortesía nunca deshace el toque que la pidió.
    raise warning 'whatsapp_card_reply_internal(%): %', p_kind, sqlerrm;
    return null;
  end;
end;
$$;

revoke all on function public.whatsapp_card_reply_internal(uuid, uuid, uuid, text, uuid, text, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. «Tengo una consulta»: al guardarse el toque del cliente
-- ---------------------------------------------------------------------------

-- La respuesta rápida llega con `respuesta:1` (whatsapp-send numera así las
-- que no aprueban nada) y apunta a la tarjeta del presupuesto. Se responde
-- después de guardar el mensaje del cliente, así queda debajo en el chat
-- (`message_sequence`).
create or replace function public.whatsapp_card_question_reply_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message jsonb := new.metadata #> '{raw_payload,message}';
  v_card public.messages%rowtype;
  v_binding public.whatsapp_conversation_bindings%rowtype;
begin
  if coalesce(v_message #>> '{button,payload}', v_message #>> '{interactive,button_reply,id}')
       is distinct from 'respuesta:1'
     or nullif(v_message #>> '{context,id}', '') is null then
    return null;
  end if;
  select * into v_card
    from public.messages card
   where card.tenant_id = new.tenant_id
     and card.conversation_id = new.conversation_id
     and card.external_provider = 'whatsapp'
     and card.message_direction = 'outbound'
     and card.external_message_id = v_message #>> '{context,id}'
     and card.type = 'action_request'
     and card.metadata->>'template_name' in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2')
   limit 1;
  if v_card.id is null then
    return null;
  end if;
  select * into v_binding
    from public.whatsapp_conversation_bindings binding
   where binding.tenant_id = new.tenant_id
     and binding.conversation_id = new.conversation_id
   order by binding.created_at
   limit 1;
  if v_binding.id is null then
    return null;
  end if;
  perform public.whatsapp_card_reply_internal(
    new.tenant_id, new.conversation_id, v_binding.customer_id,
    v_binding.external_wa_id,
    nullif(coalesce(nullif(v_card.metadata->>'target_id', ''), v_card.metadata->>'jobId'), '')::uuid,
    'question', 'card-reply:' || new.external_message_id);
  return null;
exception when others then
  raise warning 'whatsapp_card_question_reply_v1: %', sqlerrm;
  return null;
end;
$$;

revoke all on function public.whatsapp_card_question_reply_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_messages_whatsapp_card_question_reply on public.messages;
create trigger trg_messages_whatsapp_card_question_reply
  after insert on public.messages
  for each row
  when (new.message_direction = 'inbound' and new.external_provider = 'whatsapp')
  execute function public.whatsapp_card_question_reply_v1();

-- ---------------------------------------------------------------------------
-- 3. «Aprobar presupuesto»: el gracias, una vez aplicado
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_whatsapp_job_action(p_job_id uuid, p_action text, p_external_message_id text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_reply_to_external_message_id text DEFAULT NULL::text, p_action_revision_ms bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_event record;
  v_job record;
  v_outbound record;
  v_action_token text;
  v_sender_wa_id text;
  v_expected_token text;
  v_action_family text;
  v_terminal_status text;
  v_quotation_status text;
  v_reason text;
  v_operation_key uuid;
  v_transition_result jsonb;
  v_action_response jsonb;
  v_status_code text;
  v_status_id uuid;
  v_previous_status text;
begin
  if nullif(btrim(coalesce(p_external_message_id, '')), '') is null then
    raise exception 'WhatsApp external_message_id is required'
      using errcode = '22023';
  end if;

  if v_action not in (
    'approve_quote', 'approve_budget', 'approve_estimate',
    'reject_quote', 'reject_budget', 'reject_estimate',
    'confirm_delivery', 'cancel_delivery'
  ) then
    raise exception 'Unsupported WhatsApp job action: %', p_action
      using errcode = '22023';
  end if;

  -- Do not trust caller-supplied payload. Prove the operation from the raw,
  -- uniquely keyed event plus the canonical inbound message and binding.
  select
    event.id as event_id,
    event.tenant_id,
    event.channel_id,
    event.payload as event_payload,
    message.id as message_id,
    coalesce(message.metadata, '{}'::jsonb) as message_metadata,
    message.conversation_id,
    binding.id as binding_id,
    binding.customer_id,
    binding.external_wa_id,
    binding.external_phone_number,
    conversation.status as conversation_status,
    event.payload #>> '{message,context,id}' as reply_to_external_message_id
  into v_event
  from public.whatsapp_webhook_events event
  join public.messages message
    on message.external_provider = 'whatsapp'
   and message.external_message_id = p_external_message_id
   and message.message_direction = 'inbound'
   and message.tenant_id = event.tenant_id
  join public.conversations conversation
    on conversation.id = message.conversation_id
   and conversation.tenant_id = event.tenant_id
   and conversation.type = 'support'
  join public.whatsapp_conversation_bindings binding
    on binding.conversation_id = conversation.id
   and binding.channel_id = event.channel_id
   and binding.tenant_id = event.tenant_id
  join public.whatsapp_channels channel
    on channel.id = binding.channel_id
   and channel.tenant_id = binding.tenant_id
   and channel.is_active
  join public.customers customer
    on customer.id = binding.customer_id
   and customer.tenant_id = event.tenant_id
   and coalesce(customer.is_active, true)
  where event.event_key = 'message:' || p_external_message_id
    and event.event_type = 'message'
    and event.direction = 'inbound'
    and event.payload #>> '{message,id}' = p_external_message_id
  for update of event, message, conversation;

  if not found then
    raise exception 'WhatsApp message, binding, customer, and tenant are not linked'
      using errcode = '42501';
  end if;

  v_action_token := coalesce(
    v_event.event_payload #>> '{message,interactive,button_reply,id}',
    v_event.event_payload #>> '{message,interactive,list_reply,id}',
    v_event.event_payload #>> '{message,button,payload}'
  );
  if p_action_revision_ms is null or p_action_revision_ms <= 0
     or nullif(btrim(coalesce(p_reply_to_external_message_id, '')), '') is null then
    raise exception 'WhatsApp job action requires a bound request revision'
      using errcode = '42501';
  end if;

  v_expected_token := format(
    'job:%s:%s:%s',
    p_job_id,
    v_action,
    p_action_revision_ms
  );
  if v_action_token is distinct from v_expected_token then
    raise exception 'WhatsApp action token does not match the requested job action'
      using errcode = '42501';
  end if;

  if v_event.reply_to_external_message_id
       is distinct from p_reply_to_external_message_id then
    raise exception 'WhatsApp reply is not bound to the action request'
      using errcode = '42501';
  end if;

  v_sender_wa_id := nullif(
    v_event.event_payload #>> '{message,from}',
    ''
  );
  if v_sender_wa_id is null
     or (
       public.normalize_whatsapp_phone(v_sender_wa_id)
         is distinct from public.normalize_whatsapp_phone(v_event.external_wa_id)
       and public.normalize_whatsapp_phone(v_sender_wa_id)
         is distinct from public.normalize_whatsapp_phone(v_event.external_phone_number)
     ) then
    raise exception 'WhatsApp sender does not match the bound customer'
      using errcode = '42501';
  end if;

  -- The canonical inbound message carries the atomic automation receipt. A
  -- terminal replay returns before mutable current-state checks, preserving
  -- the exact committed result after a lost acknowledgement.
  if v_event.message_metadata #>> '{whatsapp_job_action,external_message_id}'
       = p_external_message_id
     and v_event.message_metadata #>> '{whatsapp_job_action,job_id}'
       = p_job_id::text
     and v_event.message_metadata #>> '{whatsapp_job_action,action}'
       = v_action
     and v_event.message_metadata #>> '{whatsapp_job_action,reply_to_external_message_id}'
       = p_reply_to_external_message_id
     and v_event.message_metadata #>> '{whatsapp_job_action,action_revision_ms}'
       = p_action_revision_ms::text then
    return coalesce(
      v_event.message_metadata #> '{whatsapp_job_action,response}',
      '{}'::jsonb
    ) || jsonb_build_object(
      'job_id', p_job_id,
      'action', v_action,
      'external_message_id', p_external_message_id,
      'message_id', v_event.message_id,
      'event_id', v_event.event_id,
      'duplicate', true
    );
  end if;

  if coalesce(v_event.conversation_status, '')
       not in ('pending', 'active') then
    raise exception 'WhatsApp action request conversation is closed'
      using errcode = '23514';
  end if;

  v_action_family := case
    when v_action in (
      'approve_quote', 'approve_budget', 'approve_estimate',
      'reject_quote', 'reject_budget', 'reject_estimate'
    ) then 'quote'
    else 'delivery'
  end;
  v_terminal_status := case
    when v_action in (
      'approve_quote', 'approve_budget', 'approve_estimate',
      'confirm_delivery'
    ) then 'accepted'
    else 'declined'
  end;

  -- The reply must point at the exact outbound card and its server nonce. It
  -- must also still be the latest pending request for this job/action family.
  select
    outbound.id,
    outbound.created_at,
    coalesce(outbound.metadata, '{}'::jsonb) as metadata
  into v_outbound
  from public.messages outbound
  where outbound.conversation_id = v_event.conversation_id
    and outbound.tenant_id = v_event.tenant_id
    and outbound.type = 'action_request'
    and outbound.message_direction = 'outbound'
    and outbound.external_provider = 'whatsapp'
    and coalesce(outbound.external_status, 'accepted') <> 'failed'
    and outbound.external_message_id = p_reply_to_external_message_id
    and coalesce(
      nullif(outbound.metadata->>'target_id', ''),
      nullif(outbound.metadata->>'jobId', '')
    ) = p_job_id::text
    and outbound.metadata->>'action_revision_ms' = p_action_revision_ms::text
    and (
      outbound.metadata->>'action_token' = v_action_token
      or outbound.metadata->>'action_reject_token' = v_action_token
    )
    and coalesce(outbound.metadata->'action_allowed_actions', '[]'::jsonb)
      @> jsonb_build_array(v_action)
  for update;

  if not found then
    raise exception 'WhatsApp action request does not match its outbound card'
      using errcode = '42501';
  end if;
  if lower(coalesce(v_outbound.metadata->>'status', 'pending')) <> 'pending' then
    -- Tocar otra vez el botón que ya se aplicó es la misma decisión, no un
    -- rechazo: se responde como repetida, con su recibo, sin tocar el trabajo.
    -- Sólo una respuesta real deja `responded_at`.
    if lower(v_outbound.metadata->>'status') = v_terminal_status
       and v_outbound.metadata ? 'responded_at' then
      v_action_response := jsonb_build_object(
        'job_id', p_job_id,
        'action', v_action,
        'external_message_id', p_external_message_id,
        'message_id', v_event.message_id,
        'event_id', v_event.event_id,
        'duplicate', true,
        'repeated_answer', true,
        'answered_by_external_message_id',
          v_outbound.metadata->>'response_external_message_id'
      );

      update public.messages
      set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'whatsapp_job_action', jsonb_build_object(
          'external_message_id', p_external_message_id,
          'reply_to_external_message_id', p_reply_to_external_message_id,
          'action_revision_ms', p_action_revision_ms,
          'job_id', p_job_id,
          'action', v_action,
          'applied_at', clock_timestamp(),
          'response', v_action_response
        )
      )
      where id = v_event.message_id;

      return v_action_response;
    end if;
    raise exception 'WhatsApp action request already has a terminal response'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.messages newer
    where newer.conversation_id = v_event.conversation_id
      and newer.tenant_id = v_event.tenant_id
      and newer.type = 'action_request'
      and newer.message_direction = 'outbound'
      and newer.external_provider = 'whatsapp'
      and coalesce(newer.external_status, 'accepted') <> 'failed'
      and coalesce(
        nullif(newer.metadata->>'target_id', ''),
        nullif(newer.metadata->>'jobId', '')
      ) = p_job_id::text
      and case v_action_family
        when 'quote' then
          coalesce(newer.metadata->'action_allowed_actions', '[]'::jsonb)
            ?| array[
              'approve_quote', 'approve_budget', 'approve_estimate',
              'reject_quote', 'reject_budget', 'reject_estimate'
            ]
        else
          coalesce(newer.metadata->'action_allowed_actions', '[]'::jsonb)
            ?| array['confirm_delivery', 'cancel_delivery']
      end
      and (newer.created_at, newer.id) > (v_outbound.created_at, v_outbound.id)
  ) then
    raise exception 'WhatsApp action request was superseded by a newer card'
      using errcode = '23514';
  end if;

  select
    job.id,
    job.tenant_id,
    job.customer_id,
    job.status,
    job.status_id,
    job.job_type,
    job.workflow_kind,
    job.quotation_status,
    job.quotation_valid_until
  into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.tenant_id = v_event.tenant_id
    and job.customer_id = v_event.customer_id
    and job.deleted_at is null
    and (
      exists (
        select 1
        from public.conversations conversation
        where conversation.id = v_event.conversation_id
          and conversation.tenant_id = job.tenant_id
          and conversation.context_type = 'job'
          and conversation.context_id = job.id
      )
      or exists (
        select 1
        from public.conversation_contexts context
        where context.conversation_id = v_event.conversation_id
          and context.tenant_id = job.tenant_id
          and context.context_type = 'job'
          and context.context_id = job.id
      )
    );

  if not found then
    raise exception 'WhatsApp message, customer, tenant, and job are not linked'
      using errcode = '42501';
  end if;

  if v_action in (
    'approve_quote', 'approve_budget', 'approve_estimate',
    'reject_quote', 'reject_budget', 'reject_estimate'
  ) then
    -- Serialize quotation currency before entering its canonical command, then
    -- fail closed instead of using the command's privileged manual-expiry
    -- override reason.
    select
      job.id,
      job.tenant_id,
      job.customer_id,
      job.status,
      job.status_id,
      job.job_type,
      job.workflow_kind,
      job.quotation_status,
      job.quotation_valid_until
    into v_job
    from public.mechanic_jobs job
    where job.id = p_job_id
      and job.tenant_id = v_event.tenant_id
      and job.customer_id = v_event.customer_id
      and job.deleted_at is null
    for update;

    if v_job.workflow_kind <> 'quotation'
       or v_job.job_type <> 'quotation' then
      raise exception 'El trabajo no es una cotización.'
        using errcode = '23514';
    end if;
    if v_job.quotation_status is distinct from 'pending' then
      raise exception 'La cotización ya no está pendiente'
        using errcode = '23514';
    end if;
    if v_job.quotation_valid_until is not null
       and v_job.quotation_valid_until < clock_timestamp() then
      raise exception 'La cotización venció y requiere revisión del taller'
        using errcode = '23514';
    end if;

    v_quotation_status := case
      when v_action in (
        'approve_quote', 'approve_budget', 'approve_estimate'
      ) then 'approved'
      else 'rejected'
    end;
    v_reason := case v_quotation_status
      when 'approved' then 'Cotización aprobada por cliente vía WhatsApp ('
        || p_external_message_id || ')'
      else 'Cotización rechazada por cliente vía WhatsApp ('
        || p_external_message_id || ')'
    end;
    v_operation_key := md5(
      'whatsapp-job-quotation:' || p_external_message_id
    )::uuid;

    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      v_event.tenant_id::text,
      true
    );
    v_transition_result := public.transition_mechanic_job_quotation(
      p_job_id,
      v_quotation_status,
      v_reason,
      v_operation_key
    );
    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      '',
      true
    );

    v_action_response := jsonb_build_object(
      'job_id', p_job_id,
      'action', v_action,
      'quotation_status', v_quotation_status,
      'external_message_id', p_external_message_id,
      'message_id', v_event.message_id,
      'event_id', v_event.event_id,
      'operation_key', v_operation_key,
      'duplicate', false,
      'canonical_result', v_transition_result
    );

    update public.messages
    set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'status', v_terminal_status,
      'responded_at', clock_timestamp(),
      'responded_via', 'whatsapp',
      'response_external_message_id', p_external_message_id
    )
    where id = v_outbound.id;

    update public.messages
    set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'whatsapp_job_action', jsonb_build_object(
        'external_message_id', p_external_message_id,
        'reply_to_external_message_id', p_reply_to_external_message_id,
        'action_revision_ms', p_action_revision_ms,
        'job_id', p_job_id,
        'action', v_action,
        'quotation_status', v_quotation_status,
        'operation_key', v_operation_key,
        'applied_at', clock_timestamp(),
        'response', v_action_response
      )
    )
    where id = v_event.message_id;

    -- Lo primero que ve el cliente después de aprobar (dueño, 2026-11-08):
    -- un gracias con su bici, no un silencio. Va dentro de la ventana de
    -- 24 horas que abre su toque, así que es un mensaje normal.
    if v_quotation_status = 'approved' then
      perform public.whatsapp_card_reply_internal(
        v_event.tenant_id, v_event.conversation_id, v_event.customer_id,
        v_event.external_wa_id, p_job_id, 'quote_approved',
        'card-reply:' || p_external_message_id);
    end if;

    return v_action_response;
  end if;

  -- A positive delivery acknowledgement uses the same audited canonical
  -- status command as Jobs Table. A negative reply records the customer
  -- decision but deliberately does not move the work backwards.
  v_previous_status := v_job.status;
  if v_action = 'confirm_delivery' then
    if not public.mechanic_job_resolves_completion(
      v_job.status,
      v_job.status_id
    ) then
      raise exception 'El trabajo aún no está terminado para confirmar entrega'
        using errcode = '23514';
    end if;

    v_status_code := 'ENTREGADO';
    select status.id
    into v_status_id
    from public.job_statuses status
    where status.tenant_id = v_event.tenant_id
      and upper(btrim(status.code)) = v_status_code
      and status.is_active
    order by status.sort_order
    limit 1;

    if v_status_id is null then
      raise exception 'Status % not found for tenant %',
        v_status_code, v_event.tenant_id;
    end if;

    v_transition_result := public.transition_mechanic_job_status(
      p_job_id,
      v_status_id,
      'whatsapp-job-status:' || p_external_message_id
    );
    v_status_code := coalesce(
      v_transition_result->>'status',
      v_status_code
    );
  else
    v_status_code := v_previous_status;
    v_status_id := v_job.status_id;
    v_transition_result := null;
  end if;

  v_action_response := jsonb_build_object(
    'job_id', p_job_id,
    'action', v_action,
    'previous_status', v_previous_status,
    'status_code', v_status_code,
    'status_id', v_status_id,
    'external_message_id', p_external_message_id,
    'message_id', v_event.message_id,
    'event_id', v_event.event_id,
    'duplicate', false,
    'canonical_result', v_transition_result
  );

  update public.messages
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
    'status', v_terminal_status,
    'responded_at', clock_timestamp(),
    'responded_via', 'whatsapp',
    'response_external_message_id', p_external_message_id
  )
  where id = v_outbound.id;

  update public.messages
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
    'whatsapp_job_action', jsonb_build_object(
      'external_message_id', p_external_message_id,
      'reply_to_external_message_id', p_reply_to_external_message_id,
      'action_revision_ms', p_action_revision_ms,
      'job_id', p_job_id,
      'action', v_action,
      'previous_status', v_previous_status,
      'status_code', v_status_code,
      'applied_at', clock_timestamp(),
      'response', v_action_response
    )
  )
  where id = v_event.message_id;

  return v_action_response;
exception
  when others then
    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      '',
      true
    );
    raise;
end;
$function$
;

revoke all on function public.apply_whatsapp_job_action(uuid, text, text, jsonb, text, bigint) from public, anon, authenticated;
grant execute on function public.apply_whatsapp_job_action(uuid, text, text, jsonb, text, bigint) to service_role;
