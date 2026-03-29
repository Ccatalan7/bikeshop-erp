-- Deploy to Supabase: WhatsApp Cloud API integration foundation
-- Source of truth: supabase/sql/core_schema.sql (lines 21064-21865)

-- WHATSAPP CLOUD API INTEGRATION
-- Added: 2026-03-29
-- Purpose: Receive Meta webhooks, persist inbound/outbound message traceability,
--          bind WhatsApp contacts to support conversations, and automate job
--          lifecycle updates without bypassing the existing messaging system.
-- ============================================================================

create table if not exists whatsapp_channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  phone_number_id text not null,
  business_account_id text,
  display_name text,
  display_phone_number text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(phone_number_id),
  unique(tenant_id, phone_number_id)
);

create index if not exists idx_whatsapp_channels_tenant
  on public.whatsapp_channels(tenant_id);
create index if not exists idx_whatsapp_channels_active
  on public.whatsapp_channels(tenant_id, is_active);

alter table public.whatsapp_channels enable row level security;

drop policy if exists "whatsapp_channels_select" on public.whatsapp_channels;
drop policy if exists "whatsapp_channels_insert" on public.whatsapp_channels;
drop policy if exists "whatsapp_channels_update" on public.whatsapp_channels;
drop policy if exists "whatsapp_channels_delete" on public.whatsapp_channels;

create policy "whatsapp_channels_select" on public.whatsapp_channels
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_channels_insert" on public.whatsapp_channels
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "whatsapp_channels_update" on public.whatsapp_channels
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_channels_delete" on public.whatsapp_channels
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_whatsapp_channels_updated_at on public.whatsapp_channels;
create trigger trg_whatsapp_channels_updated_at
  before update on public.whatsapp_channels
  for each row execute procedure public.set_updated_at();

create table if not exists whatsapp_conversation_bindings (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  conversation_id uuid references public.conversations(id) on delete cascade not null,
  channel_id uuid references public.whatsapp_channels(id) on delete cascade not null,
  customer_id uuid references public.customers(id) on delete set null,
  external_wa_id text not null,
  external_phone_number text,
  contact_name text,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(channel_id, external_wa_id),
  unique(conversation_id, channel_id)
);

create index if not exists idx_whatsapp_bindings_tenant
  on public.whatsapp_conversation_bindings(tenant_id);
create index if not exists idx_whatsapp_bindings_conversation
  on public.whatsapp_conversation_bindings(conversation_id);
create index if not exists idx_whatsapp_bindings_customer
  on public.whatsapp_conversation_bindings(customer_id) where customer_id is not null;

alter table public.whatsapp_conversation_bindings enable row level security;

drop policy if exists "whatsapp_bindings_select" on public.whatsapp_conversation_bindings;
drop policy if exists "whatsapp_bindings_insert" on public.whatsapp_conversation_bindings;
drop policy if exists "whatsapp_bindings_update" on public.whatsapp_conversation_bindings;
drop policy if exists "whatsapp_bindings_delete" on public.whatsapp_conversation_bindings;

create policy "whatsapp_bindings_select" on public.whatsapp_conversation_bindings
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_bindings_insert" on public.whatsapp_conversation_bindings
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "whatsapp_bindings_update" on public.whatsapp_conversation_bindings
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_bindings_delete" on public.whatsapp_conversation_bindings
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop trigger if exists trg_whatsapp_bindings_updated_at on public.whatsapp_conversation_bindings;
create trigger trg_whatsapp_bindings_updated_at
  before update on public.whatsapp_conversation_bindings
  for each row execute procedure public.set_updated_at();

create table if not exists whatsapp_webhook_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  channel_id uuid references public.whatsapp_channels(id) on delete cascade not null,
  event_key text not null,
  event_type text not null check (event_type in ('message', 'status', 'unknown')),
  direction text not null default 'system' check (direction in ('inbound', 'outbound', 'system')),
  payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(channel_id, event_key)
);

create index if not exists idx_whatsapp_webhook_events_tenant
  on public.whatsapp_webhook_events(tenant_id);
create index if not exists idx_whatsapp_webhook_events_channel
  on public.whatsapp_webhook_events(channel_id, created_at desc);
create index if not exists idx_whatsapp_webhook_events_type
  on public.whatsapp_webhook_events(event_type, created_at desc);

alter table public.whatsapp_webhook_events enable row level security;

drop policy if exists "whatsapp_webhook_events_select" on public.whatsapp_webhook_events;
drop policy if exists "whatsapp_webhook_events_insert" on public.whatsapp_webhook_events;
drop policy if exists "whatsapp_webhook_events_update" on public.whatsapp_webhook_events;
drop policy if exists "whatsapp_webhook_events_delete" on public.whatsapp_webhook_events;

create policy "whatsapp_webhook_events_select" on public.whatsapp_webhook_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_webhook_events_insert" on public.whatsapp_webhook_events
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "whatsapp_webhook_events_update" on public.whatsapp_webhook_events
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "whatsapp_webhook_events_delete" on public.whatsapp_webhook_events
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

alter table public.messages add column if not exists external_provider text;
alter table public.messages add column if not exists external_message_id text;
alter table public.messages add column if not exists message_direction text;
alter table public.messages add column if not exists external_status text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_external_provider_check'
  ) then
    alter table public.messages
      add constraint messages_external_provider_check
      check (external_provider in ('whatsapp') or external_provider is null);
  end if;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_message_direction_check'
  ) then
    alter table public.messages
      add constraint messages_message_direction_check
      check (message_direction in ('inbound', 'outbound') or message_direction is null);
  end if;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_external_status_check'
  ) then
    alter table public.messages
      add constraint messages_external_status_check
      check (external_status in ('accepted', 'sent', 'delivered', 'read', 'failed') or external_status is null);
  end if;
exception
  when duplicate_object then null;
end $$;

create index if not exists idx_messages_external_provider
  on public.messages(external_provider) where external_provider is not null;
create unique index if not exists idx_messages_external_message_id
  on public.messages(external_message_id) where external_message_id is not null;

create or replace function public.normalize_whatsapp_phone(p_phone text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text;
begin
  if p_phone is null then
    return null;
  end if;

  v_digits := regexp_replace(p_phone, '[^0-9]', '', 'g');

  if v_digits = '' then
    return null;
  end if;

  if v_digits like '56%' then
    return v_digits;
  end if;

  if length(v_digits) = 9 and left(v_digits, 1) = '9' then
    return '56' || v_digits;
  end if;

  if length(v_digits) = 8 then
    return '569' || v_digits;
  end if;

  return v_digits;
end;
$$;

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
        'active',
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
      not exists (
        select 1
        from public.conversation_contexts
        where conversation_id = v_conversation_id
      ),
      p_tenant_id
    ) on conflict (conversation_id, context_type, context_id) do nothing;
  end if;

  update public.conversations
  set title = coalesce(title, nullif(trim(p_contact_name), ''), nullif(trim(p_phone_number), ''), title),
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

create or replace function public.mark_whatsapp_job_quote_sent(
  p_job_id uuid,
  p_external_message_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_status_id uuid;
begin
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;

  if not found then
    raise exception 'Job not found: %', p_job_id;
  end if;

  select id into v_status_id
  from public.job_statuses
  where tenant_id = v_job.tenant_id
    and code = 'ESPERANDO_APROBACION'
    and is_active = true
  order by sort_order
  limit 1;

  update public.mechanic_jobs
  set status = coalesce(
        case
          when v_status_id is not null then 'ESPERANDO_APROBACION'
          else status
        end,
        status
      ),
      status_id = coalesce(v_status_id, status_id),
      diagnostic_sent_at = coalesce(diagnostic_sent_at, now()),
      requires_approval = true,
      updated_at = now()
  where id = p_job_id;

  perform public.log_mechanic_job_timeline(
    p_job_id,
    'whatsapp_quote_sent',
    null,
    p_external_message_id,
    'Quote sent to customer via WhatsApp'
  );

  return jsonb_build_object(
    'job_id', p_job_id,
    'status_code', case when v_status_id is not null then 'ESPERANDO_APROBACION' else v_job.status end,
    'diagnostic_sent_at', now(),
    'external_message_id', p_external_message_id,
    'payload', p_payload
  );
end;
$$;

create or replace function public.apply_whatsapp_job_action(
  p_job_id uuid,
  p_action text,
  p_external_message_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job record;
  v_status_code text;
  v_status_id uuid;
  v_description text;
begin
  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id;

  if not found then
    raise exception 'Job not found: %', p_job_id;
  end if;

  case lower(p_action)
    when 'approve_quote', 'approve_budget', 'approve_estimate' then
      v_status_code := 'EN_CURSO';
      v_description := 'Customer approved the work via WhatsApp';
    when 'reject_quote', 'reject_budget', 'reject_estimate' then
      v_status_code := 'CANCELADO';
      v_description := 'Customer rejected the work via WhatsApp';
    when 'confirm_delivery' then
      v_status_code := 'ENTREGADO';
      v_description := 'Customer confirmed delivery via WhatsApp';
    when 'cancel_delivery' then
      v_status_code := 'FINALIZADO';
      v_description := 'Customer asked to keep the job open for delivery follow-up';
    else
      raise exception 'Unsupported WhatsApp job action: %', p_action;
  end case;

  select id into v_status_id
  from public.job_statuses
  where tenant_id = v_job.tenant_id
    and code = v_status_code
    and is_active = true
  order by sort_order
  limit 1;

  if v_status_id is null then
    raise exception 'Status % not found for tenant %', v_status_code, v_job.tenant_id;
  end if;

  update public.mechanic_jobs
  set status = v_status_code,
      status_id = v_status_id,
      approved_by_customer = case
        when lower(p_action) in ('approve_quote', 'approve_budget', 'approve_estimate') then true
        else approved_by_customer
      end,
      approved_at = case
        when lower(p_action) in ('approve_quote', 'approve_budget', 'approve_estimate') then coalesce(approved_at, now())
        else approved_at
      end,
      requires_approval = case
        when lower(p_action) in ('approve_quote', 'approve_budget', 'approve_estimate', 'reject_quote', 'reject_budget', 'reject_estimate') then false
        else requires_approval
      end,
      quotation_status = case
        when job_type = 'quotation' and lower(p_action) in ('approve_quote', 'approve_budget', 'approve_estimate') then 'approved'
        when job_type = 'quotation' and lower(p_action) in ('reject_quote', 'reject_budget', 'reject_estimate') then 'rejected'
        else quotation_status
      end,
      updated_at = now()
  where id = p_job_id;

  perform public.log_mechanic_job_timeline(
    p_job_id,
    'whatsapp_action',
    null,
    lower(p_action),
    v_description
  );

  return jsonb_build_object(
    'job_id', p_job_id,
    'action', lower(p_action),
    'status_code', v_status_code,
    'status_id', v_status_id,
    'external_message_id', p_external_message_id,
    'payload', p_payload
  );
end;
$$;

create or replace function public.ingest_whatsapp_inbound_message(
  p_phone_number_id text,
  p_external_message_id text,
  p_wa_id text,
  p_phone_number text,
  p_contact_name text,
  p_message_type text,
  p_message_body text,
  p_payload jsonb default '{}'::jsonb,
  p_context_type text default null,
  p_context_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel record;
  v_customer record;
  v_binding jsonb;
  v_conversation_id uuid;
  v_message_id uuid;
  v_event_key text;
  v_row_count integer;
  v_ui_message_type text;
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

  v_binding := public.ensure_whatsapp_conversation_binding(
    v_channel.tenant_id,
    v_channel.id,
    p_wa_id,
    p_phone_number,
    p_contact_name,
    v_customer.id,
    p_context_type,
    p_context_id,
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
$$;

create or replace function public.record_whatsapp_message_status(
  p_phone_number_id text,
  p_external_message_id text,
  p_status text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_channel record;
  v_message record;
  v_event_key text;
  v_row_count integer;
  v_job_id uuid;
begin
  select * into v_channel
  from public.whatsapp_channels
  where phone_number_id = p_phone_number_id
    and is_active = true
  limit 1;

  if not found then
    raise exception 'WhatsApp channel not found for phone_number_id %', p_phone_number_id;
  end if;

  v_event_key := 'status:' || p_external_message_id || ':' || lower(coalesce(p_status, 'unknown')) || ':' || coalesce(p_payload->>'timestamp', '');

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
    'status',
    'system',
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

  update public.messages
  set external_status = lower(p_status),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'whatsapp_status', lower(p_status),
        'whatsapp_status_payload', p_payload,
        'whatsapp_status_updated_at', now()
      )
  where external_provider = 'whatsapp'
    and external_message_id = p_external_message_id
  returning id, conversation_id into v_message;

  if v_message.conversation_id is not null and lower(p_status) = 'read' then
    select cc.context_id into v_job_id
    from public.conversation_contexts cc
    where cc.conversation_id = v_message.conversation_id
      and cc.context_type = 'job'
    order by cc.is_primary desc, cc.added_at asc
    limit 1;

    if v_job_id is not null then
      perform public.log_mechanic_job_timeline(
        v_job_id,
        'whatsapp_read',
        null,
        p_external_message_id,
        'Customer read a WhatsApp message linked to this job'
      );
    end if;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'message_id', v_message.id,
    'conversation_id', v_message.conversation_id,
    'status', lower(p_status)
  );
end;
$$;

grant execute on function public.ensure_whatsapp_conversation_binding(uuid, uuid, text, text, text, uuid, text, uuid, uuid) to authenticated;
grant execute on function public.mark_whatsapp_job_quote_sent(uuid, text, jsonb) to authenticated;
grant execute on function public.mark_whatsapp_job_quote_sent(uuid, text, jsonb) to service_role;
grant execute on function public.apply_whatsapp_job_action(uuid, text, text, jsonb) to authenticated;
grant execute on function public.apply_whatsapp_job_action(uuid, text, text, jsonb) to service_role;
grant execute on function public.ingest_whatsapp_inbound_message(text, text, text, text, text, text, text, jsonb, text, uuid) to service_role;
grant execute on function public.record_whatsapp_message_status(text, text, text, jsonb) to service_role;