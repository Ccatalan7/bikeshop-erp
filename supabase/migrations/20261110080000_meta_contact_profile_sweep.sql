-- Meta was asked for the name of an Instagram or Messenger contact only when
-- a webhook event of that account arrived (20261110060000). So conversations
-- that already existed kept «Instagram • 1B5849» until somebody wrote again
-- (owner, 2026-11-09: «y qué pasa con los mensajes que ya se enviaron de
-- insta? … aún veo los mismos códigos raros en vez de los nombres»), and a
-- contact Meta refused was asked again only if the account had traffic a day
-- later.
--
-- From here a schedule asks too, with no message needed. It works like the
-- WhatsApp outbox (20260903220000): the database mints a single-use, hashed
-- ticket for a channel that has contacts due and posts it to the
-- `meta-contact-profiles` function, which redeems it with the service role
-- before it asks Meta. No shared secret exists, and nobody but the database
-- can start a sweep.
--
-- Who is due is one rule, `meta_contact_profile_due`, read by the schedule and
-- by the claim the webhook already made.

create or replace function public.meta_contact_profile_due(
  p_contact_name text,
  p_username text,
  p_profile_checked_at timestamptz
)
returns boolean
language sql
set search_path = public, pg_temp
as $$
  select nullif(btrim(p_contact_name), '') is null
    and nullif(btrim(p_username), '') is null
    and (
      p_profile_checked_at is null
      or p_profile_checked_at < clock_timestamp() - interval '24 hours'
    );
$$;

comment on function public.meta_contact_profile_due(text, text, timestamptz) is
  'A Meta contact is due for a profile request: no name, no username, and not asked in the last day.';

-- Same claim as 20261110060000; only the rule moved to its one owner.
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
      and public.meta_contact_profile_due(
        binding.contact_name, binding.username, binding.profile_checked_at
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

revoke all on function public.claim_meta_contact_profiles_due(text, text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_meta_contact_profiles_due(text, text, integer)
  to service_role;

-- Where the schedule posts, and its switch.
create table if not exists public.meta_contact_profile_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  endpoint text not null
    check (endpoint ~ '^https://[^/]+/functions/v1/meta-contact-profiles$')
);
insert into public.meta_contact_profile_runtime (singleton, endpoint)
values (
  true,
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/meta-contact-profiles'
)
on conflict (singleton) do nothing;
alter table public.meta_contact_profile_runtime enable row level security;
revoke all on public.meta_contact_profile_runtime from public, anon, authenticated;
grant all on public.meta_contact_profile_runtime to service_role;

comment on table public.meta_contact_profile_runtime is
  'Private switch and endpoint of the scheduled Meta contact-name sweep.';

-- The ticket of a channel's pending sweep: one row per channel, replaced by
-- the next dispatch and deleted when redeemed. Only its hash is kept.
create table if not exists public.meta_contact_profile_sweeps (
  channel_id uuid primary key
    references public.meta_channels(id) on delete cascade,
  tenant_id uuid not null
    references public.tenants(id) on delete cascade,
  token_hash text not null,
  lease_until timestamptz not null,
  dispatched_at timestamptz not null default clock_timestamp()
);
alter table public.meta_contact_profile_sweeps enable row level security;
revoke all on public.meta_contact_profile_sweeps from public, anon, authenticated;
grant all on public.meta_contact_profile_sweeps to service_role;

comment on table public.meta_contact_profile_sweeps is
  'Private single-use tickets of the scheduled Meta contact-name sweep. The token is never stored, only its hash.';

create or replace function public.dispatch_meta_contact_profile_sweeps()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_endpoint text;
  v_channel record;
  v_token text;
  v_count integer := 0;
begin
  select runtime.endpoint into v_endpoint
  from public.meta_contact_profile_runtime runtime
  where runtime.singleton and runtime.enabled;
  if v_endpoint is null then
    return 0;
  end if;

  -- Nothing is posted for a channel with nobody due, or with a ticket still
  -- out: a quiet account costs one indexed read per run and no request.
  for v_channel in
    select channel.id, channel.tenant_id
    from public.meta_channels channel
    where channel.is_active
      and exists (
        select 1
        from public.meta_conversation_bindings binding
        where binding.channel_id = channel.id
          and binding.tenant_id = channel.tenant_id
          and public.meta_contact_profile_due(
            binding.contact_name, binding.username, binding.profile_checked_at
          )
      )
      and not exists (
        select 1
        from public.meta_contact_profile_sweeps sweep
        where sweep.channel_id = channel.id
          and sweep.lease_until > clock_timestamp()
      )
    order by channel.id
    limit 20
  loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.meta_contact_profile_sweeps as sweep (
      channel_id, tenant_id, token_hash, lease_until, dispatched_at
    ) values (
      v_channel.id,
      v_channel.tenant_id,
      encode(extensions.digest(v_token, 'sha256'), 'hex'),
      clock_timestamp() + interval '2 minutes',
      clock_timestamp()
    )
    on conflict (channel_id) do update
    set tenant_id = excluded.tenant_id,
        token_hash = excluded.token_hash,
        lease_until = excluded.lease_until,
        dispatched_at = excluded.dispatched_at;
    perform net.http_post(
      url := v_endpoint,
      headers := '{"Content-Type":"application/json","x-region":"sa-east-1"}'::jsonb,
      body := jsonb_build_object('channel_id', v_channel.id, 'token', v_token),
      timeout_milliseconds := 60000
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

comment on function public.dispatch_meta_contact_profile_sweeps() is
  'Scheduled: posts a single-use ticket to meta-contact-profiles for each active Meta channel with contacts due for a name.';

create or replace function public.redeem_meta_contact_profile_sweep(
  p_channel_id uuid,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_tenant_id uuid;
  v_channel public.meta_channels%rowtype;
begin
  if v_role <> 'service_role' then
    raise exception 'Meta contact profile sweeps require service role'
      using errcode = '42501';
  end if;

  -- Single use: the ticket is gone once it opens a sweep.
  delete from public.meta_contact_profile_sweeps sweep
  where sweep.channel_id = p_channel_id
    and sweep.lease_until > clock_timestamp()
    and sweep.token_hash
      = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  returning sweep.tenant_id into v_tenant_id;
  if not found then
    return null;
  end if;

  select channel.* into v_channel
  from public.meta_channels channel
  where channel.id = p_channel_id
    and channel.tenant_id = v_tenant_id
    and channel.is_active;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'provider', v_channel.provider,
    'external_account_id', v_channel.external_account_id
  );
end;
$$;

comment on function public.redeem_meta_contact_profile_sweep(uuid, text) is
  'Service only: exchanges a dispatched ticket for the Meta account to sweep. Null when the ticket is wrong, used or expired.';

revoke all on function public.dispatch_meta_contact_profile_sweeps()
  from public, anon, authenticated, service_role;
revoke all on function public.redeem_meta_contact_profile_sweep(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.dispatch_meta_contact_profile_sweeps()
  to service_role;
grant execute on function public.redeem_meta_contact_profile_sweep(uuid, text)
  to service_role;

-- Off the quarter hours other schedules use. A new contact is still asked at
-- once by the webhook; this covers the conversations that already existed,
-- the daily retry of a refusal and the quick retry of an outage.
select cron.schedule(
  'vinabike_meta_contact_profiles',
  '7,22,37,52 * * * *',
  'select public.dispatch_meta_contact_profile_sweeps();'
);
