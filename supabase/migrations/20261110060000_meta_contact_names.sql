-- Instagram and Messenger conversations showed «Instagram • 1B5849» instead
-- of the person's name (owner, 2026-11-09: «por qué se ven con ese código
-- raro y no con el nombre del cliente?»).
--
-- Meta's messaging webhook carries only the sender's scoped id. The name and
-- the username come from a separate Graph request (the User Profile API), and
-- the webhook never made it: it always passed null for both, so every title
-- fell back to the provider plus six characters of the id's hash.
--
-- From here:
-- - the webhook asks Meta for the profile of contacts that have none
--   (`claim_meta_contact_profiles_due`) and stores the answer
--   (`record_meta_contact_profile`);
-- - a named contact titles its conversation, which is what the inbox and the
--   chat header read. Message metadata does not change: its `contact_label`
--   stays the pseudonymous code and it carries no name, username or raw id,
--   as the integration has required since 2026-07-22
--   (`supabase/tests/meta_messaging_integration.sql`). The name lives in the
--   service-only binding and in the title;
-- - a contact Meta will not name yet keeps the code and is asked again a day
--   later. Under Standard Access Meta may refuse people without a role on the
--   app; the retry is what names them once the app review is approved.

alter table public.meta_conversation_bindings
  add column if not exists profile_checked_at timestamptz,
  add column if not exists profile_error text;

comment on column public.meta_conversation_bindings.profile_checked_at is
  'Last time Meta was asked for this contact''s profile. Null: ask on the next webhook.';
comment on column public.meta_conversation_bindings.profile_error is
  'Why the last profile request gave no name (a short code, never a message).';

create or replace function public.meta_contact_display_name(
  p_contact_name text,
  p_username text
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(
    nullif(btrim(p_contact_name), ''),
    '@' || nullif(btrim(ltrim(btrim(p_username), '@')), '')
  );
$$;

comment on function public.meta_contact_display_name(text, text) is
  'How a Meta contact is shown: the name, else @username, else null.';

create or replace function public.meta_contact_fallback_label(
  p_provider text,
  p_external_user_id text
)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select (case when p_provider = 'instagram' then 'Instagram' else 'Messenger' end)
    || ' • ' || upper(substr(md5(p_external_user_id), 1, 6));
$$;

comment on function public.meta_contact_fallback_label(text, text) is
  'Title of a Meta contact nobody has named yet: provider plus a short code.';

create or replace function public.ensure_meta_conversation_binding(
  p_channel_id uuid,
  p_external_user_id text,
  p_contact_name text default null,
  p_username text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_external_user_id text := btrim(coalesce(p_external_user_id, ''));
  v_channel public.meta_channels%rowtype;
  v_binding record;
  v_binding_id uuid;
  v_conversation_id uuid;
  v_previous_conversation_id uuid;
  v_title text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta conversation binding requires service role'
      using errcode = '42501';
  end if;
  if p_channel_id is null or v_external_user_id = '' then
    raise exception 'Meta channel and external user are required'
      using errcode = '22023';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = p_channel_id
    and channel.is_active;
  if not found then
    raise exception 'Active Meta channel not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'meta_binding:' || p_channel_id::text || ':' || v_external_user_id,
    0
  ));

  select
    binding.*,
    conversation.status as conversation_status
  into v_binding
  from public.meta_conversation_bindings binding
  join public.conversations conversation
    on conversation.id = binding.conversation_id
   and conversation.tenant_id = binding.tenant_id
  where binding.channel_id = p_channel_id
    and binding.external_user_id = v_external_user_id
  for update of binding, conversation;

  if found and v_binding.tenant_id is distinct from v_channel.tenant_id then
    raise exception 'Meta binding belongs to another tenant'
      using errcode = '23514';
  end if;

  if found and v_binding.conversation_status in ('pending', 'active') then
    v_binding_id := v_binding.id;
    v_conversation_id := v_binding.conversation_id;
  elsif found then
    v_binding_id := v_binding.id;
    v_previous_conversation_id := v_binding.conversation_id;
  end if;

  if v_conversation_id is null then
    -- A conversation reopened for a contact Meta already named keeps that
    -- name. The code is only for a contact nobody has named yet.
    v_title := coalesce(
      public.meta_contact_display_name(
        coalesce(nullif(btrim(p_contact_name), ''), v_binding.contact_name),
        coalesce(nullif(btrim(p_username), ''), v_binding.username)
      ),
      public.meta_contact_fallback_label(v_channel.provider, v_external_user_id)
    );

    insert into public.conversations (
      tenant_id,
      type,
      channel,
      counterparty_type,
      title,
      status,
      created_by,
      last_message_at,
      updated_at
    ) values (
      v_channel.tenant_id,
      'support',
      v_channel.provider,
      'customer',
      v_title,
      'pending',
      null,
      clock_timestamp(),
      clock_timestamp()
    ) returning id into v_conversation_id;
  end if;

  if v_binding_id is null then
    insert into public.meta_conversation_bindings (
      tenant_id,
      channel_id,
      conversation_id,
      external_user_id,
      contact_name,
      username
    ) values (
      v_channel.tenant_id,
      v_channel.id,
      v_conversation_id,
      v_external_user_id,
      nullif(btrim(p_contact_name), ''),
      nullif(btrim(p_username), '')
    ) returning id into v_binding_id;
  elsif v_previous_conversation_id is not null then
    update public.meta_conversation_bindings
    set conversation_id = v_conversation_id,
        contact_name = coalesce(nullif(btrim(p_contact_name), ''), contact_name),
        username = coalesce(nullif(btrim(p_username), ''), username),
        updated_at = clock_timestamp()
    where id = v_binding_id;
  else
    update public.meta_conversation_bindings
    set contact_name = coalesce(nullif(btrim(p_contact_name), ''), contact_name),
        username = coalesce(nullif(btrim(p_username), ''), username),
        updated_at = clock_timestamp()
    where id = v_binding_id;
  end if;

  update public.conversations
  set title = case
        when nullif(btrim(p_contact_name), '') is not null then btrim(p_contact_name)
        when nullif(btrim(title), '') is null
          then coalesce(nullif(btrim(p_username), ''), title)
        else title
      end,
      updated_at = clock_timestamp()
  where id = v_conversation_id;

  return jsonb_build_object(
    'tenant_id', v_channel.tenant_id,
    'channel_id', v_channel.id,
    'provider', v_channel.provider,
    'binding_id', v_binding_id,
    'conversation_id', v_conversation_id,
    'external_user_id', v_external_user_id,
    'rebound_from_conversation_id', v_previous_conversation_id
  );
end;
$$;

create or replace function public.claim_meta_contact_profiles_due(
  p_provider text,
  p_external_account_id text,
  p_limit integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_channel public.meta_channels%rowtype;
  v_contacts jsonb;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta contact profile claims require service role'
      using errcode = '42501';
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.provider = v_provider
    and channel.external_account_id = btrim(coalesce(p_external_account_id, ''))
    and channel.is_active;
  if not found then
    return jsonb_build_object('channel_id', null, 'contacts', '[]'::jsonb);
  end if;

  -- Claiming stamps the attempt, so a burst of events asks Meta once.
  with due as (
    select binding.id
    from public.meta_conversation_bindings binding
    where binding.channel_id = v_channel.id
      and binding.tenant_id = v_channel.tenant_id
      and nullif(btrim(binding.contact_name), '') is null
      and nullif(btrim(binding.username), '') is null
      and (
        binding.profile_checked_at is null
        or binding.profile_checked_at < clock_timestamp() - interval '24 hours'
      )
    order by binding.last_inbound_at desc nulls last, binding.created_at desc
    limit greatest(1, least(coalesce(p_limit, 3), 10))
    for update skip locked
  ), claimed as (
    update public.meta_conversation_bindings binding
    set profile_checked_at = clock_timestamp()
    from due
    where binding.id = due.id
    returning binding.id, binding.external_user_id
  )
  select coalesce(
    jsonb_agg(jsonb_build_object(
      'binding_id', claimed.id,
      'external_user_id', claimed.external_user_id
    )),
    '[]'::jsonb
  ) into v_contacts
  from claimed;

  return jsonb_build_object(
    'channel_id', v_channel.id,
    'provider', v_channel.provider,
    'contacts', v_contacts
  );
end;
$$;

create or replace function public.record_meta_contact_profile(
  p_binding_id uuid,
  p_contact_name text default null,
  p_username text default null,
  p_error text default null,
  p_retry_soon boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_binding public.meta_conversation_bindings%rowtype;
  v_provider text;
  v_name text := nullif(btrim(coalesce(p_contact_name, '')), '');
  v_username text := nullif(btrim(ltrim(btrim(coalesce(p_username, '')), '@')), '');
  v_previous_display text;
  v_display text;
  v_fallback text;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta contact profiles require service role'
      using errcode = '42501';
  end if;

  select binding.* into v_binding
  from public.meta_conversation_bindings binding
  where binding.id = p_binding_id
  for update;
  if not found then
    raise exception 'Meta conversation binding not found' using errcode = 'P0002';
  end if;

  if v_name is null and v_username is null then
    -- No name this time. A transient failure is asked again on the next
    -- webhook; anything else waits a day.
    update public.meta_conversation_bindings
    set profile_error = left(nullif(btrim(coalesce(p_error, '')), ''), 120),
        profile_checked_at = case
          when coalesce(p_retry_soon, false) then null
          else clock_timestamp()
        end
    where id = v_binding.id;
    return jsonb_build_object('resolved', false);
  end if;

  select channel.provider into v_provider
  from public.meta_channels channel
  where channel.id = v_binding.channel_id
    and channel.tenant_id = v_binding.tenant_id;

  v_previous_display := public.meta_contact_display_name(
    v_binding.contact_name, v_binding.username
  );
  v_display := public.meta_contact_display_name(
    coalesce(v_name, v_binding.contact_name),
    coalesce(v_username, v_binding.username)
  );
  v_fallback := public.meta_contact_fallback_label(
    v_provider, v_binding.external_user_id
  );

  update public.meta_conversation_bindings
  set contact_name = coalesce(v_name, contact_name),
      username = coalesce(v_username, username),
      profile_error = null,
      profile_checked_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where id = v_binding.id;

  -- Only a title nobody chose is replaced: the code, or the name it had.
  update public.conversations conversation
  set title = v_display,
      updated_at = clock_timestamp()
  where conversation.id = v_binding.conversation_id
    and conversation.tenant_id = v_binding.tenant_id
    and conversation.title is distinct from v_display
    and (
      nullif(btrim(conversation.title), '') is null
      or conversation.title = v_fallback
      or conversation.title = v_previous_display
    );

  return jsonb_build_object(
    'resolved', true,
    'conversation_id', v_binding.conversation_id
  );
end;
$$;

revoke all on function public.claim_meta_contact_profiles_due(text, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.record_meta_contact_profile(uuid, text, text, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_meta_contact_profiles_due(text, text, integer)
  to service_role;
grant execute on function public.record_meta_contact_profile(uuid, text, text, text, boolean)
  to service_role;
