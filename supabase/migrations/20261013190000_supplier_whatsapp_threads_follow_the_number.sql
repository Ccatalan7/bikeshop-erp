-- Un chat de WhatsApp de un proveedor llega a Proveedores aunque el número
-- sea nuevo para el ERP.
--
-- 2026-10-13, Comercial Ciclo: el vendedor nuevo (Diego) escribió al número
-- del ERP. El webhook nunca miraba proveedores: un número sin cliente entraba
-- como chat de cliente. El taller lo agregó como contacto principal del
-- proveedor y el chat se quedó en Mensajería, porque guardar un contacto sólo
-- ataba hilos que ya eran del proveedor, y el tipo de contraparte de una
-- conversación es inmutable. Peor: con su número atado a un chat de cliente,
-- escribirle desde el panel de proveedores fallaba («already bound to another
-- counterparty capability»).
--
-- La inmutabilidad protege una frontera real: un cliente con portal puede leer
-- su chat, y nunca uno de proveedor. Esta migración no la abre; agrega un solo
-- paso permitido, cliente → proveedor, y sólo para un chat que no tiene ninguna
-- identidad de cliente (sin cliente en el vínculo, sin participante cliente,
-- sin contexto de cliente, no creado por un cliente). El hilo se conserva
-- entero: mismos mensajes, archivos, reacciones y lecturas.
--
--   · `whatsapp_number_supplier`: el proveedor de un número — contacto activo
--     o teléfono de la ficha —, sólo si es uno solo.
--   · Guardar un contacto activo con número (o el teléfono de la ficha) mueve
--     los chats de cliente sin identidad de ese número al proveedor.
--   · Un mensaje entrante de un número de proveedor, sin vínculo previo, abre
--     el chat directo en Proveedores.
--   · `assign_whatsapp_conversation_to_supplier`: desde el chat, «Es de un
--     proveedor» crea el contacto con el número y el nombre de WhatsApp y
--     mueve el chat.
--   · Cada movimiento queda en `messaging_counterparty_moves`.
--   · Respaldo: los chats de cliente sin identidad cuyo número ya es de un
--     proveedor (el 2026-10-13, uno: Diego, Comercial Ciclo).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. El proveedor de un número.
-- ---------------------------------------------------------------------------
create or replace function public.whatsapp_number_supplier(
  p_tenant_id uuid,
  p_phone text
)
returns table (supplier_id uuid, supplier_contact_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with candidates as (
    select contact.supplier_id,
           contact.id as contact_id,
           contact.is_primary,
           contact.created_at
      from public.supplier_contacts contact
      join public.suppliers supplier
        on supplier.tenant_id = contact.tenant_id
       and supplier.id = contact.supplier_id
     where contact.tenant_id = p_tenant_id
       and contact.is_active
       and coalesce(supplier.is_active, true)
       and contact.phone_digits is not null
       and coalesce(public.phone_digits_match(contact.phone_digits, p_phone), false)
    union all
    select supplier.id,
           null::uuid,
           false,
           supplier.created_at
      from public.suppliers supplier
     where supplier.tenant_id = p_tenant_id
       and coalesce(supplier.is_active, true)
       and coalesce(public.phone_digits_match(supplier.phone, p_phone), false)
  )
  select candidate.supplier_id,
         (array_agg(
            candidate.contact_id
            order by candidate.contact_id is null,
                     candidate.is_primary desc,
                     candidate.created_at
          ))[1]
    from candidates candidate
   group by candidate.supplier_id
  having (select count(distinct other.supplier_id) from candidates other) = 1;
$$;

comment on function public.whatsapp_number_supplier(uuid, text) is
  'The supplier a phone belongs to — an active contact''s number or the supplier''s own phone — and its contact, only when exactly one supplier matches.';

revoke all on function public.whatsapp_number_supplier(uuid, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. ¿El chat tiene identidad de cliente? Lo que decide la frontera.
-- ---------------------------------------------------------------------------
create or replace function public.conversation_has_customer_identity(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
      select 1
        from public.whatsapp_conversation_bindings binding
       where binding.conversation_id = conversation.id
         and binding.customer_id is not null
    )
    or exists (
      select 1
        from public.conversation_participants participant
        join public.customers customer
          on customer.auth_user_id = participant.user_id
         and customer.tenant_id = conversation.tenant_id
       where participant.conversation_id = conversation.id
         and not exists (
           select 1
             from public.user_profiles staff
            where staff.user_id = participant.user_id
              and staff.tenant_id = conversation.tenant_id
              and coalesce(staff.is_active, true)
         )
    )
    or exists (
      select 1
        from public.customers customer
       where customer.auth_user_id = conversation.created_by
         and customer.tenant_id = conversation.tenant_id
    )
    or (
      conversation.context_type is not null
      and conversation.context_type not in ('supplier', 'purchase_invoice')
    )
    or exists (
      select 1
        from public.conversation_contexts context
       where context.conversation_id = conversation.id
         and context.context_type not in ('supplier', 'purchase_invoice')
    )
  from public.conversations conversation
  where conversation.id = p_conversation_id;
$$;

comment on function public.conversation_has_customer_identity(uuid) is
  'True when a conversation is tied to a customer: a customer on its WhatsApp binding, a customer participant, a customer author, or a customer-side context.';

revoke all on function public.conversation_has_customer_identity(uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Bitácora de movimientos.
-- ---------------------------------------------------------------------------
create table if not exists public.messaging_counterparty_moves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id)
    on delete cascade,
  from_counterparty text not null check (from_counterparty = 'customer'),
  to_counterparty text not null check (to_counterparty = 'supplier'),
  supplier_id uuid not null,
  supplier_contact_id uuid references public.supplier_contacts(id)
    on delete set null,
  source text not null check (
    source in ('supplier_contact', 'supplier_phone', 'chat_command', 'backfill')
  ),
  actor_id uuid references auth.users(id) on delete set null,
  moved_at timestamptz not null default clock_timestamp()
);

create index if not exists messaging_counterparty_moves_conversation_idx
  on public.messaging_counterparty_moves (conversation_id);

alter table public.messaging_counterparty_moves enable row level security;
revoke all on table public.messaging_counterparty_moves
  from public, anon, authenticated, service_role;
grant select on table public.messaging_counterparty_moves to service_role;

comment on table public.messaging_counterparty_moves is
  'Append-only evidence: a customer WhatsApp conversation without customer identity moved to a supplier, by a contact save, a supplier phone, the chat command or the 2026-10-13 backfill.';

-- ---------------------------------------------------------------------------
-- 4. La frontera: inmutable, salvo el único paso que hace el comando.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_conversation_counterparty()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if tg_op = 'INSERT' then
    if new.counterparty_type is null then
      new.counterparty_type := case
        when new.type = 'internal' then 'internal'
        when new.context_type in ('supplier', 'purchase_invoice') then 'supplier'
        else 'customer'
      end;
    end if;
  else
    if new.counterparty_type is distinct from old.counterparty_type then
      -- El único cambio permitido: un chat de cliente sin identidad de
      -- cliente pasa a proveedor, dentro de
      -- move_whatsapp_conversation_to_supplier_internal.
      if not (
        old.counterparty_type = 'customer'
        and new.counterparty_type = 'supplier'
        and new.type = 'support'
        and coalesce(
          current_setting('app.messaging_counterparty_move', true), ''
        ) = old.id::text
        and not public.conversation_has_customer_identity(old.id)
      ) then
        raise exception 'Conversation counterparty_type is immutable'
          using errcode = '23514';
      end if;
    end if;
    if new.is_group is distinct from old.is_group then
      raise exception 'Conversation is_group is immutable'
        using errcode = '23514';
    end if;
  end if;

  if new.type <> 'internal' and new.is_group then
    raise exception 'Only internal conversations can be groups'
      using errcode = '23514';
  end if;

  if new.type = 'internal' and new.counterparty_type <> 'internal' then
    raise exception 'Internal conversations require an internal counterparty'
      using errcode = '23514';
  end if;

  if new.type = 'support' and new.counterparty_type = 'supplier'
     and new.context_type is not null
     and new.context_type not in ('supplier', 'purchase_invoice') then
    raise exception 'Supplier conversations only accept supplier or purchase contexts'
      using errcode = '23514';
  end if;

  if new.type = 'support' and new.counterparty_type = 'customer'
     and new.context_type in ('supplier', 'purchase_invoice') then
    raise exception 'Customer conversations cannot accept supplier contexts'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Mover un chat al proveedor.
-- ---------------------------------------------------------------------------
create or replace function public.move_whatsapp_conversation_to_supplier_internal(
  p_conversation_id uuid,
  p_supplier_id uuid,
  p_supplier_contact_id uuid,
  p_source text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
  v_contact_id uuid := p_supplier_contact_id;
  v_actor uuid := auth.uid();
begin
  select conversation.*
    into v_conversation
    from public.conversations conversation
   where conversation.id = p_conversation_id
   for update;

  if not found
     or v_conversation.type <> 'support'
     or v_conversation.counterparty_type <> 'customer'
     or coalesce(v_conversation.channel, '') <> 'whatsapp'
     or public.conversation_has_customer_identity(v_conversation.id) then
    return false;
  end if;

  if not exists (
    select 1
      from public.suppliers supplier
     where supplier.tenant_id = v_conversation.tenant_id
       and supplier.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform set_config(
    'app.messaging_counterparty_move', v_conversation.id::text, true
  );

  update public.conversations conversation
     set counterparty_type = 'supplier',
         context_type = 'supplier',
         context_id = p_supplier_id,
         updated_at = now()
   where conversation.id = v_conversation.id;

  perform set_config('app.messaging_counterparty_move', '', true);

  insert into public.conversation_contexts (
    conversation_id, context_type, context_id, is_primary, tenant_id
  ) values (
    v_conversation.id, 'supplier', p_supplier_id, true, v_conversation.tenant_id
  ) on conflict (conversation_id, context_type, context_id) do update
    set is_primary = true;

  if v_contact_id is null then
    select number_supplier.supplier_contact_id
      into v_contact_id
      from public.whatsapp_conversation_bindings binding
      cross join lateral public.whatsapp_number_supplier(
        binding.tenant_id, binding.external_phone_number
      ) number_supplier
     where binding.conversation_id = v_conversation.id
       and number_supplier.supplier_id = p_supplier_id
     limit 1;
  end if;

  if v_contact_id is not null then
    update public.whatsapp_conversation_bindings binding
       set supplier_contact_id = v_contact_id
     where binding.conversation_id = v_conversation.id
       and binding.supplier_contact_id is null;
  end if;

  insert into public.messaging_counterparty_moves (
    tenant_id, conversation_id, from_counterparty, to_counterparty,
    supplier_id, supplier_contact_id, source, actor_id
  ) values (
    v_conversation.tenant_id, v_conversation.id, 'customer', 'supplier',
    p_supplier_id, v_contact_id, p_source, v_actor
  );

  return true;
end;
$$;

revoke all on function public.move_whatsapp_conversation_to_supplier_internal(
  uuid, uuid, uuid, text
) from public, anon, authenticated, service_role;

-- Los chats de cliente sin identidad de un número pasan a su proveedor,
-- cuando ese número es sólo de ese proveedor.
create or replace function public.claim_supplier_whatsapp_threads_internal(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_phone text,
  p_source text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_candidate record;
  v_moved integer := 0;
begin
  if nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), '') is null then
    return 0;
  end if;

  for v_candidate in
    select distinct binding.conversation_id, number_supplier.supplier_contact_id
      from public.whatsapp_conversation_bindings binding
      join public.conversations conversation
        on conversation.id = binding.conversation_id
       and conversation.tenant_id = binding.tenant_id
      cross join lateral public.whatsapp_number_supplier(
        binding.tenant_id, binding.external_phone_number
      ) number_supplier
     where binding.tenant_id = p_tenant_id
       and binding.external_phone_number is not null
       and coalesce(public.phone_digits_match(binding.external_phone_number, p_phone), false)
       and conversation.counterparty_type = 'customer'
       and number_supplier.supplier_id = p_supplier_id
  loop
    if public.move_whatsapp_conversation_to_supplier_internal(
      v_candidate.conversation_id,
      p_supplier_id,
      v_candidate.supplier_contact_id,
      p_source
    ) then
      v_moved := v_moved + 1;
    end if;
  end loop;

  return v_moved;
end;
$$;

revoke all on function public.claim_supplier_whatsapp_threads_internal(
  uuid, uuid, text, text
) from public, anon, authenticated, service_role;

create or replace function public.supplier_contacts_claim_customer_threads()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  -- La fuente la fija quien guarda: el comando del chat dice chat_command.
  perform public.claim_supplier_whatsapp_threads_internal(
    new.tenant_id,
    new.supplier_id,
    new.phone,
    coalesce(
      nullif(current_setting('app.messaging_counterparty_move_source', true), ''),
      'supplier_contact'
    )
  );
  return new;
end;
$$;

revoke all on function public.supplier_contacts_claim_customer_threads()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supplier_contacts_claim_customer_threads
  on public.supplier_contacts;
create trigger trg_supplier_contacts_claim_customer_threads
  after insert or update of phone, is_active on public.supplier_contacts
  for each row
  when (new.is_active and new.phone_digits is not null)
  execute function public.supplier_contacts_claim_customer_threads();

create or replace function public.suppliers_claim_customer_threads()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.claim_supplier_whatsapp_threads_internal(
    new.tenant_id, new.id, new.phone, 'supplier_phone'
  );
  return new;
end;
$$;

revoke all on function public.suppliers_claim_customer_threads()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_suppliers_claim_customer_threads
  on public.suppliers;
create trigger trg_suppliers_claim_customer_threads
  after insert or update of phone, is_active on public.suppliers
  for each row
  when (coalesce(new.is_active, true) and new.phone is not null)
  execute function public.suppliers_claim_customer_threads();

-- ---------------------------------------------------------------------------
-- 6. Entrada: un número de proveedor sin vínculo abre su chat en Proveedores.
--    Mismo cuerpo que producción (20260820040000) salvo ese bloque.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ingest_whatsapp_inbound_message(p_phone_number_id text, p_external_message_id text, p_wa_id text, p_phone_number text, p_contact_name text, p_message_type text, p_message_body text, p_payload jsonb DEFAULT '{}'::jsonb, p_context_type text DEFAULT NULL::text, p_context_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_channel record;
  v_customer record;
  v_binding jsonb;
  v_conversation_id uuid;
  v_message_id uuid;
  v_event_key text;
  v_row_count integer;
  v_ui_message_type text;
  v_reaction jsonb;
  v_reaction_emoji text;
  v_reaction_target_wamid text;
  v_target_message record;
  v_reaction_id uuid;
  v_context_type text := p_context_type;
  v_context_id uuid := p_context_id;
  v_bound_counterparty text;
  v_bound_status text;
  v_bound_found boolean;
  v_number_supplier_id uuid;
begin
  select * into v_channel
  from public.whatsapp_channels
  where phone_number_id = p_phone_number_id
    and is_active = true
  limit 1;

  if not found then
    raise exception 'WhatsApp channel not found for phone_number_id %', p_phone_number_id;
  end if;

  select id, auth_user_id, tenant_id
    into v_customer
  from public.customers
  where tenant_id = v_channel.tenant_id
    and public.normalize_whatsapp_phone(phone) = public.normalize_whatsapp_phone(p_phone_number)
  order by updated_at desc nulls last, created_at desc
  limit 1;

  v_event_key := 'message:' || p_external_message_id;

  insert into public.whatsapp_webhook_events (
    tenant_id,
    channel_id,
    event_key,
    event_type,
    direction,
    payload
  ) values (
    v_channel.tenant_id,
    v_channel.id,
    v_event_key,
    'message',
    'inbound',
    p_payload
  ) on conflict (channel_id, event_key) do nothing;

  get diagnostics v_row_count = row_count;

  if v_row_count = 0 then
    return jsonb_build_object(
      'duplicate', true,
      'event_key', v_event_key,
      'external_message_id', p_external_message_id
    );
  end if;

  if lower(coalesce(p_message_type, '')) = 'unsupported' then
    return jsonb_build_object(
      'duplicate', false,
      'ignored', true,
      'ignored_reason', 'unsupported_whatsapp_message_type',
      'event_key', v_event_key,
      'external_message_id', p_external_message_id,
      'tenant_id', v_channel.tenant_id,
      'channel_id', v_channel.id
    );
  end if;

  -- Una reacción anota un mensaje que ya existe: nunca crea uno. Se resuelve y
  -- se guarda aparte, y se sale antes del INSERT en `messages` — que es
  -- justamente lo que producía el mensaje basura y el no-leído falso.
  if lower(coalesce(p_message_type, '')) = 'reaction' then
    v_reaction := p_payload -> 'message' -> 'reaction';
    v_reaction_emoji := btrim(coalesce(v_reaction ->> 'emoji', ''));
    v_reaction_target_wamid := v_reaction ->> 'message_id';

    if v_reaction_target_wamid is null then
      return jsonb_build_object(
        'duplicate', false,
        'ignored', true,
        'ignored_reason', 'reaction_without_target',
        'event_key', v_event_key,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    select m.id, m.conversation_id, m.tenant_id
      into v_target_message
    from public.messages m
    where m.tenant_id = v_channel.tenant_id
      and m.external_message_id = v_reaction_target_wamid
    limit 1;

    -- Una reacción a un mensaje anterior a esta integración no tiene dónde
    -- colgarse. El evento crudo ya quedó guardado arriba; no se inventa nada.
    if not found then
      return jsonb_build_object(
        'duplicate', false,
        'ignored', true,
        'ignored_reason', 'reaction_target_not_found',
        'event_key', v_event_key,
        'target_external_message_id', v_reaction_target_wamid,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    -- Emoji vacío es cómo WhatsApp dice «quité mi reacción».
    if v_reaction_emoji = '' then
      delete from public.message_reactions
      where message_id = v_target_message.id
        and reactor_key = 'wa:' || coalesce(public.normalize_whatsapp_phone(p_wa_id), '');

      return jsonb_build_object(
        'duplicate', false,
        'reaction', true,
        'reaction_removed', true,
        'message_id', v_target_message.id,
        'conversation_id', v_target_message.conversation_id,
        'tenant_id', v_channel.tenant_id
      );
    end if;

    insert into public.message_reactions (
      tenant_id,
      message_id,
      conversation_id,
      reactor_wa_id,
      reactor_name,
      emoji,
      external_provider,
      external_message_id
    ) values (
      v_target_message.tenant_id,
      v_target_message.id,
      v_target_message.conversation_id,
      public.normalize_whatsapp_phone(p_wa_id),
      p_contact_name,
      v_reaction_emoji,
      'whatsapp',
      p_external_message_id
    )
    on conflict (message_id, reactor_key) do update
      set emoji = excluded.emoji,
          reactor_name = coalesce(excluded.reactor_name, public.message_reactions.reactor_name),
          external_message_id = excluded.external_message_id,
          updated_at = now()
    returning id into v_reaction_id;

    -- Una reacción es tráfico entrante del contacto, así que reabre la ventana
    -- de 24 h igual que cualquier mensaje suyo. No mueve `last_message_at`: no
    -- es un mensaje y no debe reordenar la bandeja.
    update public.whatsapp_conversation_bindings
    set last_inbound_at = now(),
        updated_at = now()
    where tenant_id = v_channel.tenant_id
      and conversation_id = v_target_message.conversation_id;

    return jsonb_build_object(
      'duplicate', false,
      'reaction', true,
      'reaction_id', v_reaction_id,
      'emoji', v_reaction_emoji,
      'message_id', v_target_message.id,
      'conversation_id', v_target_message.conversation_id,
      'tenant_id', v_channel.tenant_id
    );
  end if;

  -- Un número de proveedor sin cliente abre su chat en Proveedores
  -- (2026-10-13). Sólo cuando no hay un hilo abierto de ese número: un chat
  -- vivo conserva su contexto, y uno de cliente con identidad no se toca.
  if v_customer.id is null and p_context_type is null then
    select conversation.counterparty_type, conversation.status
      into v_bound_counterparty, v_bound_status
      from public.whatsapp_conversation_bindings binding
      join public.conversations conversation
        on conversation.id = binding.conversation_id
       and conversation.tenant_id = binding.tenant_id
     where binding.channel_id = v_channel.id
       and binding.external_wa_id = public.normalize_whatsapp_phone(p_wa_id);

    v_bound_found := found;

    if not v_bound_found
       or (v_bound_counterparty = 'supplier'
           and coalesce(v_bound_status, '') not in ('pending', 'active')) then
      select number_supplier.supplier_id
        into v_number_supplier_id
        from public.whatsapp_number_supplier(
          v_channel.tenant_id, coalesce(p_phone_number, p_wa_id)
        ) number_supplier;
      if v_number_supplier_id is not null then
        v_context_type := 'supplier';
        v_context_id := v_number_supplier_id;
      end if;
    end if;
  end if;

  v_binding := public.ensure_whatsapp_conversation_binding(
    v_channel.tenant_id,
    v_channel.id,
    p_wa_id,
    p_phone_number,
    p_contact_name,
    v_customer.id,
    v_context_type,
    v_context_id,
    null
  );

  v_conversation_id := (v_binding->>'conversation_id')::uuid;

  v_ui_message_type := case lower(coalesce(p_message_type, 'text'))
    when 'image' then 'image'
    when 'document' then 'file'
    when 'audio' then 'file'
    when 'video' then 'file'
    when 'sticker' then 'image'
    when 'interactive' then 'text'
    else 'text'
  end;

  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    metadata,
    external_provider,
    external_message_id,
    message_direction,
    created_at
  ) values (
    v_conversation_id,
    null,
    v_channel.tenant_id,
    coalesce(p_message_body, ''),
    v_ui_message_type,
    jsonb_strip_nulls(jsonb_build_object(
      'provider', 'whatsapp',
      'wa_id', p_wa_id,
      'phone_number', public.normalize_whatsapp_phone(p_phone_number),
      'contact_name', p_contact_name,
      'message_type', p_message_type,
      'raw_payload', p_payload
    )),
    'whatsapp',
    p_external_message_id,
    'inbound',
    now()
  ) returning id into v_message_id;

  update public.whatsapp_conversation_bindings
  set last_inbound_at = now(),
      updated_at = now()
  where id = (v_binding->>'binding_id')::uuid;

  update public.conversations
  set last_message_at = now(),
      updated_at = now(),
      status = case when status = 'pending' then 'active' else status end
  where id = v_conversation_id;

  return jsonb_build_object(
    'duplicate', false,
    'message_id', v_message_id,
    'conversation_id', v_conversation_id,
    'binding_id', (v_binding->>'binding_id')::uuid,
    'customer_id', v_customer.id,
    'tenant_id', v_channel.tenant_id
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Desde el chat: «Es de un proveedor». Crea el contacto con el número y el
--    nombre de WhatsApp (por save_supplier_contact, con su recibo) y mueve el
--    chat. Un chat unido a un cliente se niega con un motivo legible.
-- ---------------------------------------------------------------------------
create or replace function public.assign_whatsapp_conversation_to_supplier(
  p_conversation_id uuid,
  p_supplier_id uuid,
  p_operation_id uuid,
  p_contact jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_conversation public.conversations%rowtype;
  v_supplier public.suppliers%rowtype;
  v_phone text;
  v_profile_name text;
  v_contact_id uuid;
  v_contact_created boolean := false;
  v_saved jsonb;
  v_name text;
  v_is_primary boolean;
begin
  if v_actor_id is null or v_tenant_id is null
     or not public.messaging_is_staff_in_tenant(v_tenant_id) then
    raise exception 'Messaging staff access is required' using errcode = '42501';
  end if;
  if p_conversation_id is null or p_supplier_id is null or p_operation_id is null then
    raise exception 'Conversation, supplier and operation id are required'
      using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_contact, '{}'::jsonb)) <> 'object'
     or exists (
       select 1
         from jsonb_object_keys(coalesce(p_contact, '{}'::jsonb)) key
        where key not in ('name', 'role', 'is_primary')
     )
     or (p_contact ? 'is_primary'
         and jsonb_typeof(p_contact->'is_primary') not in ('boolean', 'null')) then
    raise exception 'Contact accepts name, role and is_primary'
      using errcode = '22023';
  end if;

  select supplier.*
    into v_supplier
    from public.suppliers supplier
   where supplier.tenant_id = v_tenant_id
     and supplier.id = p_supplier_id;
  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  select conversation.*
    into v_conversation
    from public.conversations conversation
   where conversation.id = p_conversation_id
     and conversation.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Conversation not found in tenant' using errcode = 'P0002';
  end if;

  -- Reintento: el chat ya quedó en este proveedor.
  if v_conversation.counterparty_type = 'supplier'
     and public.conversation_supplier_id(v_conversation.id) = p_supplier_id then
    return jsonb_build_object(
      'conversation_id', v_conversation.id,
      'supplier_id', p_supplier_id,
      'supplier_name', v_supplier.name,
      'supplier_contact_id', (
        select binding.supplier_contact_id
          from public.whatsapp_conversation_bindings binding
         where binding.conversation_id = v_conversation.id
         limit 1
      ),
      'moved', true,
      'contact_created', false,
      'replay', true
    );
  end if;

  if v_conversation.type <> 'support'
     or coalesce(v_conversation.channel, '') <> 'whatsapp'
     or v_conversation.counterparty_type <> 'customer' then
    raise exception 'Sólo un chat de WhatsApp de Mensajería se puede pasar a un proveedor.'
      using errcode = '23514';
  end if;
  if public.conversation_has_customer_identity(v_conversation.id) then
    raise exception 'Este chat está unido a un cliente; no se puede pasar a Proveedores.'
      using errcode = '23514';
  end if;

  select binding.external_phone_number, nullif(btrim(binding.contact_name), '')
    into v_phone, v_profile_name
    from public.whatsapp_conversation_bindings binding
   where binding.conversation_id = v_conversation.id
     and binding.external_phone_number is not null
   order by binding.updated_at desc
   limit 1;
  if v_phone is null then
    raise exception 'El chat no tiene un número de WhatsApp.' using errcode = '23514';
  end if;

  select contact.id
    into v_contact_id
    from public.supplier_contacts contact
   where contact.tenant_id = v_tenant_id
     and contact.supplier_id = p_supplier_id
     and contact.phone_digits is not null
     and public.phone_digits_match(contact.phone_digits, v_phone)
   order by contact.is_active desc, contact.is_primary desc, contact.created_at
   limit 1;

  perform set_config('app.messaging_counterparty_move_source', 'chat_command', true);

  if v_contact_id is null then
    v_name := coalesce(
      nullif(btrim(p_contact->>'name'), ''),
      v_profile_name,
      'Contacto de WhatsApp'
    );
    v_is_primary := coalesce((p_contact->>'is_primary')::boolean, false);
    v_saved := public.save_supplier_contact(
      v_tenant_id,
      p_supplier_id,
      null,
      null,
      p_operation_id,
      jsonb_build_object(
        'name', left(v_name, 160),
        'role', nullif(btrim(p_contact->>'role'), ''),
        'phone', '+' || regexp_replace(v_phone, '[^0-9]', '', 'g'),
        'is_primary', v_is_primary
      )
    );
    v_contact_id := (v_saved->'contact'->>'id')::uuid;
    v_contact_created := coalesce((v_saved->>'idempotent_replay')::boolean, false) = false;
  end if;

  -- Si el número también es de otro proveedor, guardar el contacto no lo
  -- mueve solo; quien lo eligió desde el chat ya decidió.
  if (select conversation.counterparty_type
        from public.conversations conversation
       where conversation.id = v_conversation.id) = 'customer' then
    perform public.move_whatsapp_conversation_to_supplier_internal(
      v_conversation.id, p_supplier_id, v_contact_id, 'chat_command'
    );
  end if;

  perform set_config('app.messaging_counterparty_move_source', '', true);

  if (select conversation.counterparty_type
        from public.conversations conversation
       where conversation.id = v_conversation.id) <> 'supplier' then
    raise exception 'El chat no se pudo pasar a Proveedores.' using errcode = '23514';
  end if;

  update public.whatsapp_conversation_bindings binding
     set supplier_contact_id = v_contact_id
   where binding.conversation_id = v_conversation.id
     and binding.supplier_contact_id is null;

  return jsonb_build_object(
    'conversation_id', v_conversation.id,
    'supplier_id', p_supplier_id,
    'supplier_name', v_supplier.name,
    'supplier_contact_id', v_contact_id,
    'moved', true,
    'contact_created', v_contact_created,
    'replay', false
  );
end;
$$;

comment on function public.assign_whatsapp_conversation_to_supplier(uuid, uuid, uuid, jsonb) is
  'Staff command: a customer WhatsApp chat without customer identity belongs to a supplier. Saves the number as that supplier''s contact (or reuses it) and moves the chat to the supplier inbox. Idempotent per operation id.';

revoke all on function public.assign_whatsapp_conversation_to_supplier(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.assign_whatsapp_conversation_to_supplier(uuid, uuid, uuid, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Respaldo: los chats de cliente sin identidad cuyo número ya es de un
--    solo proveedor.
-- ---------------------------------------------------------------------------
select count(*) filter (where moved) as backfilled_conversations
  from (
    select public.move_whatsapp_conversation_to_supplier_internal(
             candidate.conversation_id,
             candidate.supplier_id,
             candidate.supplier_contact_id,
             'backfill'
           ) as moved
      from (
        select distinct on (binding.conversation_id)
               binding.conversation_id,
               number_supplier.supplier_id,
               number_supplier.supplier_contact_id
          from public.whatsapp_conversation_bindings binding
          join public.conversations conversation
            on conversation.id = binding.conversation_id
           and conversation.tenant_id = binding.tenant_id
          cross join lateral public.whatsapp_number_supplier(
            binding.tenant_id, binding.external_phone_number
          ) number_supplier
         where conversation.counterparty_type = 'customer'
           and binding.external_phone_number is not null
         order by binding.conversation_id
      ) candidate
  ) moves;

commit;
