-- El previsualizado de una plantilla tiene que decir exactamente lo que le
-- llegará al cliente. Los cuerpos aprobados usan {{1}} para su nombre y {{2}}
-- para el del negocio, así que el segundo también viaja.

create or replace function public.assistant_prepare_customer_contact_v1(
  p_query text,
  p_limit integer default 5
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set statement_timeout to '4500ms'
as $function$
declare
  v_authority record;
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or p_limit is null or p_limit not between 1 and 5 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with matched as materialized (
    select customer.id, customer.name,
      customer.phone contact_phone
    from public.customers customer
    where customer.tenant_id = v_authority.tenant_id
      and not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', customer.name, customer.email)
        )) = 0
      )
    order by customer.updated_at desc nulls last, customer.name
    limit p_limit + 1
  ), with_conversation as materialized (
    select matched.id, matched.name, matched.contact_phone,
      conversation.id conversation_id,
      conversation.channel,
      (
        select max(message.created_at)
        from public.messages message
        where message.conversation_id = conversation.id
          and message.tenant_id = v_authority.tenant_id
          and message.message_direction = 'inbound'
      ) last_inbound_at
    from matched
    left join lateral (
      select conversation.id, conversation.channel
      from public.conversations conversation
      join public.conversation_contexts context
        on context.conversation_id = conversation.id
       and context.tenant_id = v_authority.tenant_id
       and context.context_type = 'customer'
       and context.context_id = matched.id
      where conversation.tenant_id = v_authority.tenant_id
      order by context.is_primary desc nulls last,
        conversation.last_message_at desc nulls last
      limit 1
    ) conversation on true
  ), numbered as (
    select with_conversation.*,
      -- La ventana de servicio de Meta: 24 horas desde el último mensaje
      -- ENTRANTE. Sin entrante no hay ventana, por antiguo que sea el hilo.
      (
        last_inbound_at is not null
        and statement_timestamp() - last_inbound_at < interval '24 hours'
      ) window_open,
      row_number() over (order by name) ordinal
    from with_conversation
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', id,
      'customerName', public.assistant_truncate_utf8_internal_v1(name, 160),
      'conversationId', conversation_id,
      'channel', coalesce(channel, 'whatsapp'),
      'lastInboundAt', last_inbound_at,
      'windowOpen', window_open,
      -- El teléfono NO viaja: el cliente autorizado ya lo tiene y el asistente
      -- no necesita verlo para preparar el contacto.
      'hasContactPhone', nullif(btrim(coalesce(contact_phone, '')), '') is not null,
      'contactMode', case when window_open then 'freeform' else 'template' end,
      -- El nombre del negocio completa el segundo parámetro de las plantillas,
      -- para que el previsualizado sea exactamente lo que recibirá el cliente.
      'businessName', (
        select public.assistant_truncate_utf8_internal_v1(
          coalesce(nullif(btrim(tenant.shop_name), ''), 'nuestro taller'), 80
        )
        from public.tenants tenant where tenant.id = v_authority.tenant_id
      )
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$function$;

;
