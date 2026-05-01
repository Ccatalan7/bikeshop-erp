-- Promote the latest WhatsApp handoff context so reused support threads do not
-- keep showing stale invoice/job panels after a new order handoff.

create or replace function public.ensure_whatsapp_conversation_binding(
  p_tenant_id uuid,
  p_channel_id uuid,
  p_wa_id text,
  p_phone_number text default null,
  p_contact_name text default null,
  p_customer_id uuid default null,
  p_context_type text default null,
  p_context_id uuid default null,
  p_conversation_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_binding record;
  v_conversation_id uuid;
  v_binding_id uuid;
  v_customer_auth_user_id uuid;
  v_context_type text;
  v_context_id uuid;
  v_title text;
begin
  if p_tenant_id is null or p_channel_id is null or p_wa_id is null then
    raise exception 'tenant, channel and wa_id are required';
  end if;

  select * into v_binding
  from public.whatsapp_conversation_bindings
  where channel_id = p_channel_id
    and external_wa_id = p_wa_id
  limit 1;

  if found then
    v_conversation_id := v_binding.conversation_id;
    v_binding_id := v_binding.id;
  else
    if p_conversation_id is not null then
      select id into v_conversation_id
      from public.conversations
      where id = p_conversation_id
        and tenant_id = p_tenant_id
      limit 1;
    end if;

    if v_conversation_id is null then
      v_title := coalesce(nullif(trim(p_contact_name), ''), nullif(trim(p_phone_number), ''), 'WhatsApp');

      insert into public.conversations (
        tenant_id,
        type,
        title,
        status,
        last_message_at,
        updated_at
      ) values (
        p_tenant_id,
        'support',
        v_title,
        'pending',
        now(),
        now()
      ) returning id into v_conversation_id;
    end if;

    insert into public.whatsapp_conversation_bindings (
      tenant_id,
      conversation_id,
      channel_id,
      customer_id,
      external_wa_id,
      external_phone_number,
      contact_name
    ) values (
      p_tenant_id,
      v_conversation_id,
      p_channel_id,
      p_customer_id,
      p_wa_id,
      public.normalize_whatsapp_phone(p_phone_number),
      p_contact_name
    ) returning id into v_binding_id;
  end if;

  update public.whatsapp_conversation_bindings
  set customer_id = coalesce(p_customer_id, customer_id),
      external_phone_number = coalesce(public.normalize_whatsapp_phone(p_phone_number), external_phone_number),
      contact_name = coalesce(nullif(trim(p_contact_name), ''), contact_name),
      updated_at = now()
  where id = v_binding_id;

  if p_customer_id is not null then
    select auth_user_id into v_customer_auth_user_id
    from public.customers
    where id = p_customer_id
      and tenant_id = p_tenant_id
    limit 1;

    if v_customer_auth_user_id is not null then
      insert into public.conversation_participants (
        conversation_id,
        user_id,
        tenant_id,
        role
      ) values (
        v_conversation_id,
        v_customer_auth_user_id,
        p_tenant_id,
        'member'
      ) on conflict (conversation_id, user_id) do nothing;
    end if;
  end if;

  v_context_type := p_context_type;
  v_context_id := p_context_id;

  if v_context_type is null and p_customer_id is not null then
    v_context_type := 'customer';
    v_context_id := p_customer_id;
  end if;

  if v_context_type is not null and v_context_id is not null then
    update public.conversation_contexts
    set is_primary = false
    where conversation_id = v_conversation_id
      and tenant_id = p_tenant_id;

    insert into public.conversation_contexts (
      conversation_id,
      context_type,
      context_id,
      is_primary,
      tenant_id
    ) values (
      v_conversation_id,
      v_context_type,
      v_context_id,
      true,
      p_tenant_id
    ) on conflict (conversation_id, context_type, context_id) do update
      set is_primary = true;
  end if;

  update public.conversations
  set title = case
        when nullif(trim(p_contact_name), '') is not null
          and (
            title is null
            or trim(title) = ''
            or public.normalize_whatsapp_phone(title) = p_wa_id
            or public.normalize_whatsapp_phone(title) = public.normalize_whatsapp_phone(p_phone_number)
          )
          then trim(p_contact_name)
        else coalesce(title, nullif(trim(p_contact_name), ''), nullif(trim(p_phone_number), ''), title)
      end,
      context_type = coalesce(v_context_type, context_type),
      context_id = coalesce(v_context_id, context_id),
      updated_at = now()
  where id = v_conversation_id;

  return jsonb_build_object(
    'binding_id', v_binding_id,
    'conversation_id', v_conversation_id,
    'customer_id', p_customer_id,
    'channel_id', p_channel_id
  );
end;
$$;

grant execute on function public.ensure_whatsapp_conversation_binding(uuid, uuid, text, text, text, uuid, text, uuid, uuid) to authenticated;
