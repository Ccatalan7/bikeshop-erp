-- Harden the shared messaging/WhatsApp inbox around tenant, participant, and
-- provider trust boundaries.
--
-- Forward plan:
--   * repair historical message tenant ids from their parent conversation;
--   * make the parent conversation the authoritative tenant for every child;
--   * replace permissive messaging RLS with tenant/participant-aware policies;
--   * expose unread counts with invoker rights and only for auth.uid();
--   * make webhook evidence API-append-only and webhook RPCs service-only;
--   * preserve the strongest WhatsApp delivery state during webhook replay.
--
-- Recovery plan:
--   Roll back the application client if a caller was relying on a denied path.
--   Keep the repaired tenant ids and NOT NULL constraints: restoring nullable or
--   cross-tenant messaging rows would reintroduce the security defect. Policies
--   and grants can be replaced forward in a follow-up migration if required.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- The conversation is the canonical owner. Production inspection before this
-- migration found historical support messages with NULL/wrong tenant ids.
update public.messages m
set tenant_id = c.tenant_id
from public.conversations c
where c.id = m.conversation_id
  and m.tenant_id is distinct from c.tenant_id;

alter table public.conversations
  alter column tenant_id set not null;
alter table public.conversation_participants
  alter column tenant_id set not null;
alter table public.messages
  alter column conversation_id set not null,
  alter column tenant_id set not null;
alter table public.conversation_contexts
  alter column conversation_id set not null,
  alter column tenant_id set not null;

-- Resolving a conversation is a retained business event, never a destructive
-- delete. These fields make the actor and timestamp queryable without having
-- to infer them from mutable UI state. Historical resolved rows are preserved
-- and receive the best actor/timestamp already available on the conversation.
alter table public.conversations
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references auth.users(id)
    on delete set null,
  add column if not exists resolution_reason text;

update public.conversations
set resolved_at = coalesce(resolved_at, updated_at, now()),
    resolved_by = coalesce(resolved_by, accepted_by, created_by),
    resolution_reason = coalesce(
      nullif(btrim(resolution_reason), ''),
      'Resolución histórica previa al registro auditable'
    )
where status = 'resolved'
  and (
    resolved_at is null
    or resolved_by is null
    or nullif(btrim(resolution_reason), '') is null
  );

create or replace function public.messaging_is_staff_in_tenant(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_tenant_id is not null
    and exists (
      select 1
      from public.user_profiles up
      where up.user_id = auth.uid()
        and up.tenant_id = p_tenant_id
        and coalesce(up.is_active, true)
    );
$$;

create or replace function public.messaging_is_customer_in_tenant(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and p_tenant_id is not null
    and exists (
      select 1
      from public.customers customer
      where customer.auth_user_id = auth.uid()
        and customer.tenant_id = p_tenant_id
        and coalesce(customer.is_active, true)
    );
$$;

create or replace function public.messaging_user_belongs_to_tenant(
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_user_id is not null
    and p_tenant_id is not null
    and (
      exists (
        select 1
        from public.user_profiles up
        where up.user_id = p_user_id
          and up.tenant_id = p_tenant_id
          and coalesce(up.is_active, true)
      )
      or exists (
        select 1
        from public.customers customer
        where customer.auth_user_id = p_user_id
          and customer.tenant_id = p_tenant_id
          and coalesce(customer.is_active, true)
      )
    );
$$;

create or replace function public.messaging_is_conversation_participant(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversation_participants cp
      join public.conversations c on c.id = cp.conversation_id
      where cp.conversation_id = p_conversation_id
        and cp.user_id = auth.uid()
        and cp.tenant_id = c.tenant_id
    );
$$;

create or replace function public.messaging_can_access_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations c
      where c.id = p_conversation_id
        and (
          (
            c.type = 'internal'
            and (
              exists (
                select 1
                from public.conversation_participants cp
                where cp.conversation_id = c.id
                  and cp.user_id = auth.uid()
                  and cp.tenant_id = c.tenant_id
              )
              -- Required only for INSERT ... RETURNING before the creator adds
              -- the first participant. Internal messages remain strict-member.
              or (
                c.created_by = auth.uid()
                and public.messaging_is_staff_in_tenant(c.tenant_id)
                and not exists (
                  select 1
                  from public.conversation_participants any_cp
                  where any_cp.conversation_id = c.id
                )
              )
            )
          )
          or (
            c.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(c.tenant_id)
              or exists (
                select 1
                from public.conversation_participants cp
                where cp.conversation_id = c.id
                  and cp.user_id = auth.uid()
                  and cp.tenant_id = c.tenant_id
              )
              or (
                c.created_by = auth.uid()
                and public.messaging_is_customer_in_tenant(c.tenant_id)
              )
            )
          )
        )
    );
$$;

create or replace function public.messaging_can_read_conversation_messages(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations c
      where c.id = p_conversation_id
        and (
          exists (
            select 1
            from public.conversation_participants cp
            where cp.conversation_id = c.id
              and cp.user_id = auth.uid()
              and cp.tenant_id = c.tenant_id
          )
          or (
            c.type = 'support'
            and public.messaging_is_staff_in_tenant(c.tenant_id)
          )
        )
    );
$$;

create or replace function public.messaging_can_manage_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations c
      where c.id = p_conversation_id
        and (
          (
            c.type = 'support'
            and public.messaging_is_staff_in_tenant(c.tenant_id)
          )
          or (
            c.type = 'internal'
            and exists (
              select 1
              from public.conversation_participants cp
              where cp.conversation_id = c.id
                and cp.user_id = auth.uid()
                and cp.tenant_id = c.tenant_id
                and cp.role = 'admin'
            )
          )
        )
    );
$$;

create or replace function public.messaging_context_belongs_to_tenant(
  p_context_type text,
  p_context_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case lower(coalesce(p_context_type, ''))
    when 'job' then exists (
      select 1 from public.mechanic_jobs row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'invoice' then exists (
      select 1 from public.sales_invoices row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'bike' then exists (
      select 1 from public.bikes row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'product' then exists (
      select 1 from public.products row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'order' then exists (
      select 1 from public.online_orders row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'customer' then exists (
      select 1 from public.customers row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'supplier' then exists (
      select 1 from public.suppliers row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    when 'purchase_invoice' then exists (
      select 1 from public.purchase_invoices row
      where row.id = p_context_id and row.tenant_id = p_tenant_id
    )
    else false
  end;
$$;

create or replace function public.messaging_customer_can_reference_context(
  p_context_type text,
  p_context_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.messaging_is_customer_in_tenant(p_tenant_id)
    and public.messaging_context_belongs_to_tenant(
      p_context_type,
      p_context_id,
      p_tenant_id
    )
    and case lower(coalesce(p_context_type, ''))
      when 'customer' then exists (
        select 1 from public.customers customer
        where customer.id = p_context_id
          and customer.tenant_id = p_tenant_id
          and customer.auth_user_id = auth.uid()
      )
      when 'job' then exists (
        select 1
        from public.mechanic_jobs job
        join public.customers customer on customer.id = job.customer_id
        where job.id = p_context_id
          and job.tenant_id = p_tenant_id
          and customer.tenant_id = p_tenant_id
          and customer.auth_user_id = auth.uid()
      )
      when 'invoice' then exists (
        select 1
        from public.sales_invoices invoice
        join public.customers customer on customer.id = invoice.customer_id
        where invoice.id = p_context_id
          and invoice.tenant_id = p_tenant_id
          and customer.tenant_id = p_tenant_id
          and customer.auth_user_id = auth.uid()
      )
      when 'bike' then exists (
        select 1
        from public.bikes bike
        join public.customers customer on customer.id = bike.customer_id
        where bike.id = p_context_id
          and bike.tenant_id = p_tenant_id
          and customer.tenant_id = p_tenant_id
          and customer.auth_user_id = auth.uid()
      )
      when 'order' then exists (
        select 1
        from public.online_orders online_order
        join public.customers customer on customer.id = online_order.customer_id
        where online_order.id = p_context_id
          and online_order.tenant_id = p_tenant_id
          and customer.tenant_id = p_tenant_id
          and customer.auth_user_id = auth.uid()
      )
      when 'product' then true
      else false
    end;
$$;

create or replace function public.messaging_can_add_participant(
  p_conversation_id uuid,
  p_user_id uuid,
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations c
      where c.id = p_conversation_id
        and c.tenant_id = p_tenant_id
        and public.messaging_user_belongs_to_tenant(p_user_id, c.tenant_id)
        and (
          (
            c.type = 'internal'
            and public.messaging_is_staff_in_tenant(c.tenant_id)
            and exists (
              select 1
              from public.user_profiles target_staff
              where target_staff.user_id = p_user_id
                and target_staff.tenant_id = c.tenant_id
                and coalesce(target_staff.is_active, true)
            )
            and (
              c.created_by = auth.uid()
              or exists (
                select 1
                from public.conversation_participants actor_cp
                where actor_cp.conversation_id = c.id
                  and actor_cp.user_id = auth.uid()
                  and actor_cp.tenant_id = c.tenant_id
                  and actor_cp.role = 'admin'
              )
            )
          )
          or (
            c.type = 'support'
            and (
              public.messaging_is_staff_in_tenant(c.tenant_id)
              or (
                p_user_id = auth.uid()
                and c.created_by = auth.uid()
                and public.messaging_is_customer_in_tenant(c.tenant_id)
              )
            )
          )
        )
    );
$$;

-- Keep the employee RPC guard unchanged by default. A customer quotation
-- decision receives a transaction-local tenant capability only after
-- respond_to_action_request proves the exact customer, participant,
-- conversation, job, and tenant graph. No client role can grant itself this
-- capability through an exposed function.
create or replace function public.assert_workshop_rpc_tenant(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_actor uuid := auth.uid();
  v_customer_quote_tenant text := nullif(
    current_setting(
      'app.messaging_customer_quote_transition_tenant',
      true
    ),
    ''
  );
  v_customer_messaging_tenant text := nullif(
    current_setting(
      'app.messaging_customer_workshop_transition_tenant',
      true
    ),
    ''
  );
begin
  if p_tenant_id is null then
    raise exception 'Workshop tenant is required' using errcode = '42501';
  end if;

  if v_role = 'anon' then
    raise exception 'Authenticated workshop access is required'
      using errcode = '42501';
  end if;

  if v_actor is not null
     and public.user_tenant_id() is distinct from p_tenant_id
     and v_customer_quote_tenant is distinct from p_tenant_id::text
     and v_customer_messaging_tenant is distinct from p_tenant_id::text then
    raise exception 'Workshop record does not belong to the active tenant'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_workshop_rpc_tenant(uuid)
  from public, anon, authenticated, service_role;

-- Read access intentionally survives archival so the retained audit trail can
-- still be inspected. Write access is a stricter, reusable capability for
-- direct messages and private-attachment reserve/finalize commands.
create or replace function public.messaging_can_write_conversation(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.conversations conversation
      where conversation.id = p_conversation_id
        and conversation.status in ('pending', 'active')
        and public.messaging_can_read_conversation_messages(conversation.id)
    );
$$;

-- Canonicalize every child tenant from the parent conversation and make the
-- tenant/creator identity immutable after insert.
create or replace function public.enforce_messaging_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_tenant_id uuid;
  v_parent_status text;
  v_parent_type text;
  v_parent_channel text;
  v_resolution_event_capability text;
  v_is_trusted_provider_inbound boolean := false;
begin
  if tg_table_name = 'conversations' then
    if tg_op = 'UPDATE' then
      if new.tenant_id is distinct from old.tenant_id then
        raise exception 'Conversation tenant_id is immutable'
          using errcode = '23514';
      end if;
      if new.created_by is distinct from old.created_by then
        raise exception 'Conversation created_by is immutable'
          using errcode = '23514';
      end if;
    elsif new.tenant_id is null then
      new.tenant_id := public.user_tenant_id();
    end if;

    if new.tenant_id is null then
      raise exception 'Conversation tenant_id is required'
        using errcode = '23502';
    end if;

    if tg_op = 'INSERT'
       and auth.uid() is not null
       and coalesce(auth.jwt()->>'role', '') = 'authenticated' then
      new.created_by := auth.uid();
    end if;
    return new;
  end if;

  if new.conversation_id is null then
    raise exception '% conversation_id is required', tg_table_name
      using errcode = '23502';
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT' then
    -- Serialize the open/closed decision with archive_conversation. If this
    -- insert wins the row lock it commits before archival; if archival wins,
    -- this read resumes on the terminal row and the insert fails closed.
    select c.tenant_id, c.status, c.type, c.channel
    into v_parent_tenant_id, v_parent_status, v_parent_type, v_parent_channel
    from public.conversations c
    where c.id = new.conversation_id
    for share;
  else
    select c.tenant_id, c.status, c.type, c.channel
    into v_parent_tenant_id, v_parent_status, v_parent_type, v_parent_channel
    from public.conversations c
    where c.id = new.conversation_id;
  end if;

  if v_parent_tenant_id is null then
    raise exception 'Parent conversation not found'
      using errcode = '23503';
  end if;

  if new.tenant_id is null then
    new.tenant_id := v_parent_tenant_id;
  elsif new.tenant_id is distinct from v_parent_tenant_id then
    raise exception '% tenant_id must match its conversation', tg_table_name
      using errcode = '23514';
  end if;

  if tg_table_name = 'messages' and tg_op = 'INSERT'
     and coalesce(v_parent_status, '') not in ('pending', 'active') then
    v_resolution_event_capability := nullif(
      current_setting(
        'app.messaging_resolution_event_conversation_id',
        true
      ),
      ''
    );
    v_is_trusted_provider_inbound := coalesce(
      coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
      and v_parent_type = 'support'
      and v_parent_channel = 'whatsapp'
      and new.sender_id is null
      and coalesce(new.type, '') in ('text', 'image', 'file')
      and coalesce(new.external_provider, '') = 'whatsapp'
      and coalesce(new.message_direction, '') = 'inbound'
      and nullif(btrim(coalesce(new.external_message_id, '')), '') is not null
      and exists (
        select 1
        from public.whatsapp_webhook_events event
        join public.whatsapp_conversation_bindings binding
          on binding.channel_id = event.channel_id
         and binding.tenant_id = event.tenant_id
         and binding.conversation_id = new.conversation_id
        where event.tenant_id = new.tenant_id
          and event.event_key = 'message:' || new.external_message_id
          and event.event_type = 'message'
          and event.direction = 'inbound'
          and event.payload #>> '{message,id}' = new.external_message_id
      ),
      false
    );

    if not coalesce((
      (
        v_resolution_event_capability = new.conversation_id::text
        and new.type = 'system'
        and coalesce(new.metadata, '{}'::jsonb)->>'event'
          = 'conversation_resolved'
      )
      or v_is_trusted_provider_inbound
    ), false) then
      raise exception 'Conversation is closed to new messages'
        using errcode = '23514';
    end if;
  end if;

  if tg_table_name = 'conversation_contexts' then
    if not public.messaging_context_belongs_to_tenant(
      new.context_type,
      new.context_id,
      v_parent_tenant_id
    ) then
      raise exception 'Messaging context does not belong to the conversation tenant'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conversations_tenant_consistency
  on public.conversations;
create trigger trg_conversations_tenant_consistency
before insert or update on public.conversations
for each row execute function public.enforce_messaging_tenant_consistency();

drop trigger if exists trg_conversation_participants_tenant_consistency
  on public.conversation_participants;
create trigger trg_conversation_participants_tenant_consistency
before insert or update on public.conversation_participants
for each row execute function public.enforce_messaging_tenant_consistency();

drop trigger if exists trg_messages_tenant_consistency on public.messages;
create trigger trg_messages_tenant_consistency
before insert or update on public.messages
for each row execute function public.enforce_messaging_tenant_consistency();

drop trigger if exists trg_conversation_contexts_tenant_consistency
  on public.conversation_contexts;
create trigger trg_conversation_contexts_tenant_consistency
before insert or update on public.conversation_contexts
for each row execute function public.enforce_messaging_tenant_consistency();

-- The message insert already passed the tenant/participant RLS boundary. The
-- legacy timestamp trigger then tried to update its parent as the caller and
-- caused legitimate customer and non-admin participant inserts to roll back.
-- Keep the trigger API-private and update only the exact tenant-owned parent.
create or replace function public.update_conversation_timestamp()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sender_is_staff boolean := false;
  v_message_direction text := to_jsonb(new)->>'message_direction';
begin
  if new.sender_id is not null then
    select exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = new.sender_id
        and profile.tenant_id = new.tenant_id
        and coalesce(profile.is_active, true)
    ) into v_sender_is_staff;
  end if;

  update public.conversations conversation
  set last_message_at = new.created_at,
      updated_at = new.created_at,
      staff_last_read_at = case
        when conversation.type = 'support'
          and v_sender_is_staff
          and coalesce(new.type, 'text') <> 'system'
          and coalesce(v_message_direction, 'outbound') <> 'inbound'
        then greatest(
          coalesce(conversation.staff_last_read_at, '1970-01-01'::timestamptz),
          new.created_at
        )
        else conversation.staff_last_read_at
      end
  where conversation.id = new.conversation_id
    and conversation.tenant_id = new.tenant_id;

  if not found then
    raise exception 'Message tenant does not match its parent conversation'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

-- Participant labels are visible only inside a conversation graph the caller
-- can already read. Do not turn auth.users into a cross-tenant directory and
-- never derive a display name from a private email address.
create or replace function public.get_public_user_info(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_visible_tenant_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'User id is required' using errcode = '22004';
  end if;

  -- Self lookup is allowed only through a current tenant membership.
  if p_user_id = auth.uid() then
    select tenant_id into v_visible_tenant_id
    from (
      select profile.tenant_id, 1 as priority
      from public.user_profiles profile
      where profile.user_id = p_user_id
        and coalesce(profile.is_active, true)
      union all
      select customer.tenant_id, 2
      from public.customers customer
      where customer.auth_user_id = p_user_id
        and coalesce(customer.is_active, true)
    ) membership
    order by priority
    limit 1;
  else
    -- A target is public to this caller only after an accessible conversation
    -- proves that the target participates in or authored that exact graph.
    select conversation.tenant_id into v_visible_tenant_id
    from public.conversations conversation
    where public.messaging_can_read_conversation_messages(conversation.id)
      and (
        exists (
          select 1
          from public.conversation_participants participant
          where participant.conversation_id = conversation.id
            and participant.tenant_id = conversation.tenant_id
            and participant.user_id = p_user_id
        )
        or exists (
          select 1
          from public.messages message
          where message.conversation_id = conversation.id
            and message.tenant_id = conversation.tenant_id
            and message.sender_id = p_user_id
        )
      )
    order by conversation.last_message_at desc nulls last
    limit 1;
  end if;

  if v_visible_tenant_id is null then
    raise exception 'User is not visible in an accessible conversation'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', employee.user_id,
    'name', coalesce(
      nullif(btrim(concat_ws(' ', employee.first_name, employee.last_name)), ''),
      'Soporte'
    ),
    'avatar_url', employee.photo_url,
    'role', 'employee'
  ) into v_result
  from public.employees employee
  where employee.user_id = p_user_id
    and employee.tenant_id = v_visible_tenant_id
  limit 1;

  if v_result is null then
    select jsonb_build_object(
      'id', profile.user_id,
      'name', coalesce(
        nullif(btrim(concat_ws(' ', employee.first_name, employee.last_name)), ''),
        'Soporte'
      ),
      'avatar_url', employee.photo_url,
      'role', 'employee'
    ) into v_result
    from public.user_profiles profile
    join public.employees employee
      on employee.id = profile.employee_id
     and employee.tenant_id = profile.tenant_id
    where profile.user_id = p_user_id
      and profile.tenant_id = v_visible_tenant_id
      and coalesce(profile.is_active, true)
    limit 1;
  end if;

  if v_result is null then
    select jsonb_build_object(
      'id', customer.auth_user_id,
      'name', coalesce(nullif(btrim(customer.name), ''), 'Cliente'),
      'avatar_url', customer.image_url,
      'role', 'customer'
    ) into v_result
    from public.customers customer
    where customer.auth_user_id = p_user_id
      and customer.tenant_id = v_visible_tenant_id
      and coalesce(customer.is_active, true)
    limit 1;
  end if;

  if v_result is null then
    select jsonb_build_object(
      'id', auth_user.id,
      'name', coalesce(
        nullif(btrim(auth_user.raw_user_meta_data->>'full_name'), ''),
        nullif(btrim(auth_user.raw_user_meta_data->>'name'), ''),
        'Usuario'
      ),
      'avatar_url', auth_user.raw_user_meta_data->>'avatar_url',
      'role', 'unknown'
    ) into v_result
    from auth.users auth_user
    where auth_user.id = p_user_id;
  end if;

  return coalesce(
    v_result,
    jsonb_build_object(
      'id', p_user_id,
      'name', 'Usuario',
      'avatar_url', null,
      'role', 'unknown'
    )
  );
end;
$$;

-- A resolved conversation is retained as evidence. Every transition records
-- its actor/timestamp and emits one immutable-from-client system message. The
-- state is terminal here so an accidental table update cannot silently reopen
-- a closed support case and erase its operational meaning.
create or replace function public.prepare_conversation_resolution_audit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'resolved' then
      raise exception 'Conversations must be resolved after creation'
        using errcode = '23514';
    end if;

    new.resolved_at := null;
    new.resolved_by := null;
    new.resolution_reason := null;
    return new;
  end if;

  if old.status = 'resolved' and new.status is distinct from old.status then
    raise exception 'Resolved conversations are retained and cannot be reopened'
      using errcode = '23514';
  end if;

  if new.status = 'resolved' and old.status is distinct from 'resolved' then
    if auth.uid() is null then
      raise exception 'Authenticated actor required to resolve conversation'
        using errcode = '42501';
    end if;

    new.resolved_at := now();
    new.resolved_by := auth.uid();
    new.resolution_reason := coalesce(
      nullif(btrim(new.resolution_reason), ''),
      'Conversación archivada desde la bandeja de mensajería'
    );
  elsif new.resolved_at is distinct from old.resolved_at
     or new.resolved_by is distinct from old.resolved_by
     or new.resolution_reason is distinct from old.resolution_reason then
    raise exception 'Conversation resolution audit fields are immutable'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conversations_resolution_audit
  on public.conversations;
create trigger trg_conversations_resolution_audit
before insert or update on public.conversations
for each row execute function public.prepare_conversation_resolution_audit();

create or replace function public.append_conversation_resolution_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform pg_catalog.set_config(
    'app.messaging_resolution_event_conversation_id',
    new.id::text,
    true
  );
  insert into public.messages (
    conversation_id,
    sender_id,
    tenant_id,
    content,
    type,
    metadata,
    created_at
  ) values (
    new.id,
    new.resolved_by,
    new.tenant_id,
    'Conversación archivada',
    'system',
    jsonb_build_object(
      'event', 'conversation_resolved',
      'previous_status', old.status,
      'resolved_at', new.resolved_at,
      'resolved_by', new.resolved_by,
      'reason', new.resolution_reason
    ),
    new.resolved_at
  );
  perform pg_catalog.set_config(
    'app.messaging_resolution_event_conversation_id',
    '',
    true
  );

  return new;
exception
  when others then
    perform pg_catalog.set_config(
      'app.messaging_resolution_event_conversation_id',
      '',
      true
    );
    raise;
end;
$$;

drop trigger if exists trg_append_conversation_resolution_event
  on public.conversations;
create trigger trg_append_conversation_resolution_event
after update on public.conversations
for each row
when (new.status = 'resolved' and old.status is distinct from new.status)
execute function public.append_conversation_resolution_event();

-- The binding graph must be tenant-consistent. Authenticated callers are
-- limited to staff in that tenant; service-role webhook/send workers remain
-- able to resolve bindings without a user subject.
create or replace function public.enforce_whatsapp_binding_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_channel_tenant_id uuid;
  v_conversation_tenant_id uuid;
begin
  select channel.tenant_id
  into v_channel_tenant_id
  from public.whatsapp_channels channel
  where channel.id = new.channel_id;

  select conversation.tenant_id
  into v_conversation_tenant_id
  from public.conversations conversation
  where conversation.id = new.conversation_id
    and conversation.type = 'support'
    and conversation.channel = 'whatsapp';

  if v_channel_tenant_id is null or v_conversation_tenant_id is null then
    raise exception 'WhatsApp binding channel/conversation not found'
      using errcode = '23503';
  end if;

  if new.tenant_id is distinct from v_channel_tenant_id
     or new.tenant_id is distinct from v_conversation_tenant_id then
    raise exception 'WhatsApp binding tenant graph mismatch'
      using errcode = '23514';
  end if;

  if new.customer_id is not null
     and not exists (
       select 1 from public.customers customer
       where customer.id = new.customer_id
         and customer.tenant_id = new.tenant_id
     ) then
    raise exception 'WhatsApp binding customer belongs to another tenant'
      using errcode = '23514';
  end if;

  if coalesce(auth.jwt()->>'role', '') = 'authenticated'
     and not public.messaging_is_staff_in_tenant(new.tenant_id) then
    raise exception 'Authenticated caller cannot manage this WhatsApp tenant'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_whatsapp_bindings_tenant_consistency
  on public.whatsapp_conversation_bindings;
create trigger trg_whatsapp_bindings_tenant_consistency
before insert or update on public.whatsapp_conversation_bindings
for each row execute function public.enforce_whatsapp_binding_tenant_consistency();

-- Replace every legacy/migration-era policy on the canonical messaging tables.
do $$
declare
  v_policy record;
begin
  for v_policy in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'conversations',
        'conversation_participants',
        'messages',
        'conversation_contexts',
        'whatsapp_webhook_events'
      )
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      v_policy.policyname,
      v_policy.schemaname,
      v_policy.tablename
    );
  end loop;
end;
$$;

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;
alter table public.conversation_contexts enable row level security;
alter table public.whatsapp_webhook_events enable row level security;

create policy conversations_select_scoped
on public.conversations
for select
to authenticated
using (public.messaging_can_access_conversation(id));

create policy conversations_insert_scoped
on public.conversations
for insert
to authenticated
with check (
  auth.uid() is not null
  and created_by = auth.uid()
  and (
    (
      public.messaging_is_staff_in_tenant(tenant_id)
      and (
        (type = 'internal' and channel = 'internal')
        or (type = 'support' and channel = 'website_portal')
      )
    )
    or (
      type = 'support'
      and channel = 'website_portal'
      and status = 'pending'
      and accepted_by is null
      and accepted_at is null
      and public.messaging_is_customer_in_tenant(tenant_id)
      and (
        context_type is null
        or (
          context_id is not null
          and public.messaging_customer_can_reference_context(
            context_type,
            context_id,
            tenant_id
          )
        )
      )
    )
  )
);

create policy conversations_update_scoped
on public.conversations
for update
to authenticated
using (public.messaging_can_manage_conversation(id))
with check (
  public.messaging_can_manage_conversation(id)
  and (
    public.messaging_is_staff_in_tenant(tenant_id)
    or public.messaging_is_conversation_participant(id)
  )
);

create policy conversation_participants_select_scoped
on public.conversation_participants
for select
to authenticated
using (
  public.messaging_can_access_conversation(conversation_id)
  and exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and c.tenant_id = conversation_participants.tenant_id
  )
);

create policy conversation_participants_insert_scoped
on public.conversation_participants
for insert
to authenticated
with check (
  public.messaging_can_add_participant(
    conversation_id,
    user_id,
    tenant_id
  )
);

create policy messages_select_scoped
on public.messages
for select
to authenticated
using (
  public.messaging_can_read_conversation_messages(conversation_id)
  and exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and c.tenant_id = messages.tenant_id
  )
);

create policy messages_insert_scoped
on public.messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and external_provider is null
  and external_message_id is null
  and external_status is null
  and message_direction is null
  and (
    (
      type = 'text'
      -- Direct client inserts are deliberately limited to human-authored text.
      -- Attachment locators must come from the private upload/finalize path so
      -- an untrusted participant cannot make another client auto-load an
      -- arbitrary tracking URL from message metadata.
      and not coalesce(metadata, '{}'::jsonb) ?| array[
        'url',
        'media_url',
        'image_url',
        'file_url',
        'documentUrl',
        'document_url',
        'storage_url',
        'public_url',
        'whatsapp_media_url',
        'download_url',
        'storageBucket',
        'storage_bucket',
        'storagePath',
        'storage_path',
        -- Reserved renderer/command keys. A text sender may keep benign
        -- delivery UX metadata (client_message_id, share_kind, route), but it
        -- cannot smuggle a privileged action/quotation card through metadata.
        'type',
        'action_type',
        'target_id',
        'status',
        'response_note',
        'quote_id',
        'quoteId',
        'invoice_id',
        'invoiceId',
        'job_id',
        'jobId',
        'quotation_operation_key',
        'quotationOperationKey'
      ]
      and jsonb_typeof(coalesce(metadata, '{}'::jsonb)) = 'object'
    )
    or (
      type = 'action_request'
      and public.messaging_is_staff_in_tenant(tenant_id)
    )
  )
  and public.messaging_can_write_conversation(conversation_id)
  and exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and c.tenant_id = messages.tenant_id
  )
);

create policy conversation_contexts_select_scoped
on public.conversation_contexts
for select
to authenticated
using (
  public.messaging_can_read_conversation_messages(conversation_id)
  and exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and c.tenant_id = conversation_contexts.tenant_id
  )
);

create policy conversation_contexts_insert_scoped
on public.conversation_contexts
for insert
to authenticated
with check (
  public.messaging_context_belongs_to_tenant(
    context_type,
    context_id,
    tenant_id
  )
  and exists (
    select 1
    from public.conversations c
    where c.id = conversation_id
      and c.tenant_id = conversation_contexts.tenant_id
      and (
        public.messaging_can_manage_conversation(c.id)
        or (
          c.type = 'support'
          and c.created_by = auth.uid()
          and public.messaging_is_conversation_participant(c.id)
          and public.messaging_customer_can_reference_context(
            context_type,
            context_id,
            tenant_id
          )
        )
      )
  )
);

create policy conversation_contexts_update_scoped
on public.conversation_contexts
for update
to authenticated
using (public.messaging_can_manage_conversation(conversation_id))
with check (
  public.messaging_can_manage_conversation(conversation_id)
  and public.messaging_context_belongs_to_tenant(
    context_type,
    context_id,
    tenant_id
  )
);

create policy conversation_contexts_delete_scoped
on public.conversation_contexts
for delete
to authenticated
using (public.messaging_can_manage_conversation(conversation_id));

create policy whatsapp_webhook_events_staff_select
on public.whatsapp_webhook_events
for select
to authenticated
using (public.messaging_is_staff_in_tenant(tenant_id));

-- Minimum table privileges. RLS owns row scope; trusted service workers bypass
-- RLS but webhook evidence remains append-only through the API grant surface.
revoke all on table public.conversations from public, anon, authenticated;
revoke all on table public.conversation_participants from public, anon, authenticated;
revoke all on table public.messages from public, anon, authenticated;
revoke all on table public.conversation_contexts from public, anon, authenticated;
revoke all on table public.whatsapp_webhook_events from public, anon, authenticated, service_role;

grant select, insert, update on table public.conversations to authenticated;
grant select, insert on table public.conversation_participants to authenticated;
grant select, insert on table public.messages to authenticated;
grant select, insert, update, delete on table public.conversation_contexts to authenticated;
grant select on table public.whatsapp_webhook_events to authenticated;
grant select, insert on table public.whatsapp_webhook_events to service_role;

-- Invoker rights make base-table RLS authoritative. The explicit auth.uid()
-- predicate prevents even same-tenant staff from enumerating another user's
-- unread projection.
create or replace view public.conversation_unread_counts
with (security_invoker = true, security_barrier = true)
as
with participant_scope as (
  select
    cp.conversation_id,
    cp.user_id,
    cp.last_read_at,
    c.type as conversation_type,
    c.tenant_id,
    c.staff_last_read_at,
    public.messaging_is_staff_in_tenant(c.tenant_id) as participant_is_staff
  from public.conversation_participants cp
  join public.conversations c on c.id = cp.conversation_id
  where cp.user_id = auth.uid()
    and cp.tenant_id = c.tenant_id
  union all
  select
    c.id as conversation_id,
    auth.uid() as user_id,
    null::timestamptz as last_read_at,
    c.type as conversation_type,
    c.tenant_id,
    c.staff_last_read_at,
    true as participant_is_staff
  from public.conversations c
  where c.type = 'support'
    and public.messaging_is_staff_in_tenant(c.tenant_id)
    and public.messaging_can_read_conversation_messages(c.id)
    and not exists (
      select 1
      from public.conversation_participants cp
      where cp.conversation_id = c.id
        and cp.tenant_id = c.tenant_id
        and cp.user_id = auth.uid()
    )
)
select
  ps.conversation_id,
  ps.user_id,
  coalesce(count(m.id), 0)::integer as unread_count
from participant_scope ps
left join public.messages m
  on m.conversation_id = ps.conversation_id
  and m.tenant_id = ps.tenant_id
  and m.created_at > case
    when ps.conversation_type = 'support' and ps.participant_is_staff then
      greatest(
        coalesce(ps.last_read_at, '1970-01-01'::timestamptz),
        coalesce(ps.staff_last_read_at, '1970-01-01'::timestamptz)
      )
    else coalesce(ps.last_read_at, '1970-01-01'::timestamptz)
  end
  and coalesce(m.type, 'text') <> 'system'
  and case
    when ps.conversation_type = 'support' and ps.participant_is_staff then
      m.message_direction = 'inbound'
      or (
        m.message_direction is null
        and (
          m.sender_id is null
          or exists (
            select 1
            from public.customers sender_customer
            where sender_customer.auth_user_id = m.sender_id
              and sender_customer.tenant_id = ps.tenant_id
          )
        )
      )
    else m.sender_id is distinct from ps.user_id
  end
group by ps.conversation_id, ps.user_id;

revoke all on table public.conversation_unread_counts
  from public, anon, authenticated;
grant select on table public.conversation_unread_counts to authenticated;

create or replace function public.mark_conversation_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_conversation record;
  v_is_staff boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select id, type, tenant_id
  into v_conversation
  from public.conversations
  where id = p_conversation_id;

  if not found then
    return;
  end if;

  v_is_staff := public.messaging_is_staff_in_tenant(v_conversation.tenant_id);

  if not public.messaging_can_read_conversation_messages(p_conversation_id) then
    raise exception 'Not allowed to mark this conversation as read'
      using errcode = '42501';
  end if;

  update public.conversation_participants
  set last_read_at = v_now
  where conversation_id = p_conversation_id
    and user_id = v_user_id
    and tenant_id = v_conversation.tenant_id;

  if v_conversation.type = 'support' and v_is_staff then
    update public.conversations
    set staff_last_read_at = v_now
    where id = p_conversation_id
      and tenant_id = v_conversation.tenant_id;
  end if;
end;
$$;

-- Operational replacement for the legacy delete_conversation RPC. It is
-- tenant-scoped, idempotent, and deliberately retains messages, participants,
-- contexts, provider receipts, and workshop/accounting links.
create or replace function public.archive_conversation(
  p_conversation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id
  for update;

  if not found then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;

  if not public.messaging_can_manage_conversation(p_conversation_id) then
    raise exception 'Not authorized to archive this conversation'
      using errcode = '42501';
  end if;

  if v_conversation.status = 'resolved' then
    return jsonb_build_object(
      'conversation_id', v_conversation.id,
      'status', v_conversation.status,
      'resolved_at', v_conversation.resolved_at,
      'resolved_by', v_conversation.resolved_by,
      'changed', false
    );
  end if;

  update public.conversations
  set status = 'resolved',
      resolution_reason = 'Conversación archivada desde la bandeja de mensajería',
      updated_at = now()
  where id = v_conversation.id;

  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;

  return jsonb_build_object(
    'conversation_id', v_conversation.id,
    'status', v_conversation.status,
    'resolved_at', v_conversation.resolved_at,
    'resolved_by', v_conversation.resolved_by,
    'changed', true
  );
end;
$$;

create or replace function public.whatsapp_delivery_status_rank(p_status text)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  select case lower(coalesce(p_status, ''))
    when 'read' then 50
    when 'delivered' then 40
    when 'failed' then 30
    when 'sent' then 20
    when 'accepted' then 10
    else 0
  end;
$$;

create or replace function public.replay_whatsapp_message_status(
  p_external_message_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event record;
  v_message record;
  v_effective_status text;
  v_effective_metadata jsonb;
begin
  select
    lower(coalesce(payload->>'status', split_part(event_key, ':', 3))) as status,
    payload
  into v_event
  from public.whatsapp_webhook_events
  where event_type = 'status'
    and left(event_key, length('status:' || p_external_message_id || ':')) =
      'status:' || p_external_message_id || ':'
    and lower(coalesce(payload->>'status', split_part(event_key, ':', 3)))
      in ('accepted', 'sent', 'delivered', 'read', 'failed')
  order by
    public.whatsapp_delivery_status_rank(
      lower(coalesce(payload->>'status', split_part(event_key, ':', 3)))
    ) desc,
    coalesce(
      nullif(payload->>'timestamp', '')::bigint,
      extract(epoch from created_at)::bigint
    ) desc,
    created_at desc
  limit 1;

  if not found or v_event.status is null or v_event.status = '' then
    return jsonb_build_object(
      'applied', false,
      'reason', 'no_status_event',
      'external_message_id', p_external_message_id
    );
  end if;

  select id, conversation_id, external_status, metadata
  into v_message
  from public.messages
  where external_provider = 'whatsapp'
    and external_message_id = p_external_message_id
  for update;

  if not found then
    return jsonb_build_object(
      'applied', false,
      'reason', 'message_not_found',
      'external_message_id', p_external_message_id,
      'status', v_event.status
    );
  end if;

  if public.whatsapp_delivery_status_rank(v_message.external_status)
     > public.whatsapp_delivery_status_rank(v_event.status) then
    v_effective_status := v_message.external_status;
    v_effective_metadata := coalesce(v_message.metadata, '{}'::jsonb);
  else
    v_effective_status := v_event.status;
    v_effective_metadata := coalesce(v_message.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'whatsapp_status', v_event.status,
        'whatsapp_status_payload', v_event.payload,
        'whatsapp_status_updated_at', now()
      );
  end if;

  update public.messages
  set external_status = v_effective_status,
      metadata = v_effective_metadata
  where id = v_message.id;

  return jsonb_build_object(
    'applied', true,
    'message_id', v_message.id,
    'conversation_id', v_message.conversation_id,
    'external_message_id', p_external_message_id,
    'status', v_effective_status
  );
end;
$$;

-- Apply a customer job decision only from an exact durable inbound/outbound
-- WhatsApp evidence pair. Server nonce, reply context and latest-card checks
-- bind the decision; canonical transition receipts make replay idempotent.
drop function if exists public.apply_whatsapp_job_action(
  uuid, text, text, jsonb
);
create or replace function public.apply_whatsapp_job_action(
  p_job_id uuid,
  p_action text,
  p_external_message_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_reply_to_external_message_id text default null,
  p_action_revision_ms bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
$$;

-- Customer/staff action responses may update only a visible action-request
-- message, may not swap its action identity, and may only close the request
-- with one of the two explicit terminal decisions.
create or replace function public.respond_to_action_request(
  p_message_id uuid,
  p_action_type text,
  p_status text,
  p_metadata_updates jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_message record;
  v_stored_action_type text;
  v_current_status text;
  v_sanitized_updates jsonb;
  v_response_note text;
  v_target_text text;
  v_customer_id uuid;
  v_conversation_tenant_id uuid;
  v_conversation_status text;
  v_job record;
  v_quotation_status text;
  v_reason text;
  v_status_id uuid;
  v_transition_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if lower(coalesce(p_action_type, '')) not in (
    'approve_quote',
    'pay_now',
    'confirm_delivery'
  ) then
    raise exception 'Unsupported action request type'
      using errcode = '22023';
  end if;

  if lower(coalesce(p_status, '')) not in ('accepted', 'declined') then
    raise exception 'Unsupported action request status'
      using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata_updates, '{}'::jsonb)) <> 'object'
     or coalesce(p_metadata_updates, '{}'::jsonb) - 'response_note'
       <> '{}'::jsonb then
    raise exception 'Unsupported action response metadata'
      using errcode = '22023';
  end if;

  v_response_note := nullif(btrim(coalesce(
    p_metadata_updates->>'response_note',
    ''
  )), '');
  if v_response_note is not null and char_length(v_response_note) > 1000 then
    raise exception 'Action response note is too long'
      using errcode = '22023';
  end if;
  if lower(p_status) <> 'declined' and v_response_note is not null then
    raise exception 'Response note is only allowed for declined actions'
      using errcode = '22023';
  end if;

  select
    message.id,
    message.conversation_id,
    message.type,
    coalesce(message.metadata, '{}'::jsonb) as metadata
  into v_message
  from public.messages message
  where message.id = p_message_id
  for update;

  if not found then
    raise exception 'Action request message not found'
      using errcode = 'P0002';
  end if;

  if v_message.type <> 'action_request' then
    raise exception 'Message is not an action request'
      using errcode = '22023';
  end if;

  if not public.messaging_can_read_conversation_messages(
    v_message.conversation_id
  ) then
    raise exception 'Not authorized to respond to this action request'
      using errcode = '42501';
  end if;

  -- Action cards in a support thread are customer-facing commands. Shared
  -- inbox staff can read those threads, but they must never click/answer on
  -- behalf of the customer. Require the authenticated user to be both the
  -- explicit participant and the tenant-owned customer for this conversation.
  select conversation.tenant_id, conversation.status, customer.id
  into v_conversation_tenant_id, v_conversation_status, v_customer_id
  from public.conversations conversation
  join public.conversation_participants participant
    on participant.conversation_id = conversation.id
   and participant.user_id = auth.uid()
   and participant.tenant_id = conversation.tenant_id
  join public.customers customer
    on customer.auth_user_id = participant.user_id
   and customer.tenant_id = conversation.tenant_id
   and coalesce(customer.is_active, true)
  where conversation.id = v_message.conversation_id
    and conversation.type = 'support'
  limit 1
  for share of conversation;

  if not found then
    raise exception 'Only the linked customer can answer this action request'
      using errcode = '42501';
  end if;

  v_stored_action_type := lower(coalesce(
    v_message.metadata->>'action_type',
    ''
  ));
  if v_stored_action_type <> lower(p_action_type) then
    raise exception 'Action request type mismatch'
      using errcode = '22023';
  end if;

  v_current_status := lower(coalesce(
    v_message.metadata->>'status',
    'pending'
  ));
  if v_current_status in ('accepted', 'declined') then
    if v_current_status = lower(p_status) then
      return;
    end if;
    if v_current_status <> lower(p_status) then
      raise exception 'Action request already has a terminal response'
        using errcode = '23514';
    end if;
  end if;
  if v_current_status not in ('pending', 'accepted', 'declined') then
    raise exception 'Action request has an invalid current status'
      using errcode = '23514';
  end if;

  if coalesce(v_conversation_status, '') not in ('pending', 'active') then
    raise exception 'Action request conversation is closed'
      using errcode = '23514';
  end if;

  v_target_text := case v_stored_action_type
    when 'approve_quote' then coalesce(
      nullif(v_message.metadata->>'jobId', ''),
      nullif(v_message.metadata->>'target_id', '')
    )
    else nullif(v_message.metadata->>'target_id', '')
  end;
  if v_target_text is null
     or v_target_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'Action request has no valid target'
      using errcode = '22023';
  end if;

  if v_stored_action_type = 'approve_quote' then
    select
      job.id,
      job.tenant_id,
      job.customer_id,
      job.job_type,
      job.workflow_kind,
      job.quotation_status,
      job.quotation_valid_until,
      conversation.tenant_id as conversation_tenant_id
    into v_job
    from public.mechanic_jobs job
    join public.conversations conversation
      on conversation.id = v_message.conversation_id
    where job.id = v_target_text::uuid
      and job.deleted_at is null
      and conversation.type = 'support'
      and conversation.tenant_id = job.tenant_id
      and exists (
        select 1
        from public.conversation_participants cp
        where cp.conversation_id = conversation.id
          and cp.user_id = auth.uid()
          and cp.tenant_id = conversation.tenant_id
      )
      and exists (
        select 1
        from public.customers customer
        where customer.id = job.customer_id
          and customer.tenant_id = job.tenant_id
          and customer.auth_user_id = auth.uid()
          and coalesce(customer.is_active, true)
      )
      and (
        (
          conversation.context_type = 'job'
          and conversation.context_id = job.id
        )
        or exists (
          select 1
          from public.conversation_contexts context
          where context.conversation_id = conversation.id
            and context.tenant_id = conversation.tenant_id
            and context.context_type = 'job'
          and context.context_id = job.id
        )
      )
    for update of job;

    if not found then
      raise exception 'Customer, conversation, and quotation are not linked'
        using errcode = '42501';
    end if;

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

    v_quotation_status := case lower(p_status)
      when 'accepted' then 'approved'
      when 'declined' then 'rejected'
    end;
    v_reason := coalesce(
      v_response_note,
      case lower(p_status)
        when 'accepted' then 'Aprobado por el cliente desde mensajería'
        else 'Rechazado por el cliente desde mensajería'
      end
    );

    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      v_job.tenant_id::text,
      true
    );
    perform public.transition_mechanic_job_quotation(
      v_job.id,
      v_quotation_status,
      v_reason,
      p_message_id
    );
    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      '',
      true
    );
  elsif v_stored_action_type = 'pay_now' then
    if not exists (
      select 1
      from public.sales_invoices invoice
      where invoice.id = v_target_text::uuid
        and invoice.tenant_id = v_conversation_tenant_id
        and invoice.customer_id = v_customer_id
        and (
          exists (
            select 1
            from public.conversations conversation
            where conversation.id = v_message.conversation_id
              and conversation.tenant_id = invoice.tenant_id
              and conversation.context_type = 'invoice'
              and conversation.context_id = invoice.id
          )
          or exists (
            select 1
            from public.conversation_contexts context
            where context.conversation_id = v_message.conversation_id
              and context.tenant_id = invoice.tenant_id
              and context.context_type = 'invoice'
              and context.context_id = invoice.id
          )
        )
    ) then
      raise exception 'Customer, conversation, and invoice are not linked'
        using errcode = '42501';
    end if;
  elsif v_stored_action_type = 'confirm_delivery' then
    -- Do not pre-lock the job: the canonical command owns the global
    -- invoice -> job lock order. Revalidation and the message update remain in
    -- this transaction, so either both ledger/message effects commit or none.
    select job.id, job.tenant_id, job.customer_id, job.status, job.status_id
    into v_job
    from public.mechanic_jobs job
    where job.id = v_target_text::uuid
      and job.deleted_at is null
      and job.tenant_id = v_conversation_tenant_id
      and job.customer_id = v_customer_id
      and (
        exists (
          select 1
          from public.conversations conversation
          where conversation.id = v_message.conversation_id
            and conversation.tenant_id = job.tenant_id
            and conversation.context_type = 'job'
            and conversation.context_id = job.id
        )
        or exists (
          select 1
          from public.conversation_contexts context
          where context.conversation_id = v_message.conversation_id
            and context.tenant_id = job.tenant_id
            and context.context_type = 'job'
            and context.context_id = job.id
        )
      );

    if not found then
      raise exception 'Customer, conversation, and delivery job are not linked'
        using errcode = '42501';
    end if;

    if lower(p_status) = 'accepted' then
      if not public.mechanic_job_resolves_completion(
        v_job.status,
        v_job.status_id
      ) then
        raise exception 'El trabajo aún no está terminado para confirmar entrega'
          using errcode = '23514';
      end if;

      select status.id
      into v_status_id
      from public.job_statuses status
      where status.tenant_id = v_job.tenant_id
        and upper(btrim(status.code)) = 'ENTREGADO'
        and status.is_active
      order by status.sort_order
      limit 1;
      if v_status_id is null then
        raise exception 'Status ENTREGADO not found for tenant %',
          v_job.tenant_id;
      end if;

      perform pg_catalog.set_config(
        'app.messaging_customer_workshop_transition_tenant',
        v_job.tenant_id::text,
        true
      );
      v_transition_result := public.transition_mechanic_job_status(
        v_job.id,
        v_status_id,
        'messaging-delivery:' || p_message_id::text
      );
      perform pg_catalog.set_config(
        'app.messaging_customer_workshop_transition_tenant',
        '',
        true
      );
    end if;
  end if;

  v_sanitized_updates := case
    when lower(p_status) = 'declined' and v_response_note is not null then
      jsonb_build_object('response_note', v_response_note)
    else '{}'::jsonb
  end;

  update public.messages
  set metadata = v_message.metadata
    || v_sanitized_updates
    || jsonb_build_object(
      'action_type', v_stored_action_type,
      'status', lower(p_status),
      'responded_at', now(),
      'responded_by', auth.uid()
    )
  where id = p_message_id;
exception
  when others then
    perform pg_catalog.set_config(
      'app.messaging_customer_quote_transition_tenant',
      '',
      true
    );
    perform pg_catalog.set_config(
      'app.messaging_customer_workshop_transition_tenant',
      '',
      true
    );
    raise;
end;
$$;

-- Repair every projection whose append-only raw event is stronger. The live
-- preflight found exactly two sent projections with a read event; this bounded
-- predicate is safe to replay and also covers any identical race before deploy.
do $$
declare
  v_external_message_id text;
begin
  for v_external_message_id in
    select distinct message.external_message_id
    from public.messages message
    where message.external_provider = 'whatsapp'
      and message.external_message_id is not null
      and exists (
        select 1
        from public.whatsapp_webhook_events event
        where event.event_type = 'status'
          and left(
            event.event_key,
            length('status:' || message.external_message_id || ':')
          ) = 'status:' || message.external_message_id || ':'
          and public.whatsapp_delivery_status_rank(
            lower(coalesce(
              event.payload->>'status',
              split_part(event.event_key, ':', 3)
            ))
          ) > public.whatsapp_delivery_status_rank(message.external_status)
      )
  loop
    perform public.replay_whatsapp_message_status(v_external_message_id);
  end loop;
end;
$$;

-- SECURITY DEFINER functions otherwise inherit EXECUTE for PUBLIC. Keep only
-- the intended caller on each function.
revoke all on function public.messaging_is_staff_in_tenant(uuid)
  from public, anon;
revoke all on function public.messaging_is_customer_in_tenant(uuid)
  from public, anon;
revoke all on function public.messaging_user_belongs_to_tenant(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.messaging_is_conversation_participant(uuid)
  from public, anon;
revoke all on function public.messaging_can_access_conversation(uuid)
  from public, anon;
revoke all on function public.messaging_can_read_conversation_messages(uuid)
  from public, anon;
revoke all on function public.messaging_can_write_conversation(uuid)
  from public, anon;
revoke all on function public.messaging_can_manage_conversation(uuid)
  from public, anon;
revoke all on function public.messaging_context_belongs_to_tenant(text, uuid, uuid)
  from public, anon;
revoke all on function public.messaging_customer_can_reference_context(text, uuid, uuid)
  from public, anon;
revoke all on function public.messaging_can_add_participant(uuid, uuid, uuid)
  from public, anon;
revoke all on function public.enforce_messaging_tenant_consistency()
  from public, anon, authenticated, service_role;
revoke all on function public.update_conversation_timestamp()
  from public, anon, authenticated, service_role;
revoke all on function public.get_public_user_info(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.prepare_conversation_resolution_audit()
  from public, anon, authenticated, service_role;
revoke all on function public.append_conversation_resolution_event()
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_whatsapp_binding_tenant_consistency()
  from public, anon, authenticated, service_role;
revoke all on function public.whatsapp_delivery_status_rank(text)
  from public, anon, authenticated, service_role;
-- Trigger-only push dispatch must never become an API RPC. The production
-- schema snapshot can recreate functions with PostgreSQL's default PUBLIC
-- EXECUTE ACL, so restate the denial in this hardening boundary as well.
revoke all on function public.invoke_push_notification_for_message()
  from public, anon, authenticated, service_role;

grant execute on function public.messaging_is_staff_in_tenant(uuid)
  to authenticated;
grant execute on function public.messaging_is_customer_in_tenant(uuid)
  to authenticated;
grant execute on function public.messaging_is_conversation_participant(uuid)
  to authenticated;
grant execute on function public.messaging_can_access_conversation(uuid)
  to authenticated;
grant execute on function public.messaging_can_read_conversation_messages(uuid)
  to authenticated;
grant execute on function public.messaging_can_write_conversation(uuid)
  to authenticated;
grant execute on function public.messaging_can_manage_conversation(uuid)
  to authenticated;
grant execute on function public.messaging_context_belongs_to_tenant(text, uuid, uuid)
  to authenticated;
grant execute on function public.messaging_customer_can_reference_context(text, uuid, uuid)
  to authenticated;
grant execute on function public.messaging_can_add_participant(uuid, uuid, uuid)
  to authenticated;
grant execute on function public.get_public_user_info(uuid)
  to authenticated;

revoke all on function public.mark_conversation_read(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

revoke all on function public.archive_conversation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.archive_conversation(uuid) to authenticated;

-- This legacy RPC physically deleted the entire conversation graph. It stays
-- defined only so old schema history remains reproducible, but no API role can
-- execute it. The UI must use archive_conversation instead.
revoke all on function public.delete_conversation(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.respond_to_action_request(
  uuid, text, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.respond_to_action_request(
  uuid, text, text, jsonb
) to authenticated;

-- Legacy invoice confirmation confused a financial invoice with a workshop
-- quotation and did not prove tenant/customer ownership. Keep it unavailable
-- to every public/client API role while callers move to canonical commands.
revoke all on function public.confirm_invoice_approval(uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.ensure_whatsapp_conversation_binding(
  uuid, uuid, text, text, text, uuid, text, uuid, uuid
) from public, anon;
grant execute on function public.ensure_whatsapp_conversation_binding(
  uuid, uuid, text, text, text, uuid, text, uuid, uuid
) to authenticated, service_role;

revoke all on function public.mark_whatsapp_job_quote_sent(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_whatsapp_job_quote_sent(uuid, text, jsonb)
  to service_role;

revoke all on function public.apply_whatsapp_job_action(
  uuid, text, text, jsonb, text, bigint
)
  from public, anon, authenticated;
grant execute on function public.apply_whatsapp_job_action(
  uuid, text, text, jsonb, text, bigint
)
  to service_role;

-- A generic API wrapper around set_config allowed any authenticated client to
-- mint arbitrary session capabilities. Import workflows already own their
-- context inside atomic server commands; no API role may set a custom GUC.
revoke all on function public.set_config(text, text, boolean)
  from public, anon, authenticated, service_role;

revoke all on function public.ingest_whatsapp_inbound_message(
  text, text, text, text, text, text, text, jsonb, text, uuid
) from public, anon, authenticated;
grant execute on function public.ingest_whatsapp_inbound_message(
  text, text, text, text, text, text, text, jsonb, text, uuid
) to service_role;

revoke all on function public.replay_whatsapp_message_status(text)
  from public, anon, authenticated;
grant execute on function public.replay_whatsapp_message_status(text)
  to service_role;

revoke all on function public.record_whatsapp_message_status(
  text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.record_whatsapp_message_status(
  text, text, text, jsonb
) to service_role;

commit;
