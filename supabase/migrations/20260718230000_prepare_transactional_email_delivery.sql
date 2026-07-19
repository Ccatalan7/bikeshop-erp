-- Operational activation contract for transactional ecommerce email.
--
-- This migration is intentionally delivery-safe:
--   * Viñabike starts in dry_run with the verified sender identity;
--   * the scheduler exists but is disabled until an explicit phase change;
--   * no credential value is embedded in SQL;
--   * the worker secret must exist both as an Edge secret and in Supabase Vault;
--   * switching to send remains an explicit service-role-only operation.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if to_regclass('public.transactional_email_settings') is null
     or to_regclass('public.transactional_email_outbox') is null then
    raise exception
      'Transactional email foundation must be deployed before delivery activation';
  end if;
end $$;

-- Seed only the public, verified business identity. Runtime mode is never
-- promoted here. Replaying the bootstrap may refresh identity but must preserve
-- an already reviewed enabled/delivery_mode decision.
insert into public.transactional_email_settings (
  tenant_id,
  enabled,
  delivery_mode,
  from_name,
  from_email,
  reply_to_email,
  public_store_url
)
select
  tenant.id,
  true,
  'dry_run',
  'Ventas Viñabike',
  'ventas@vinabike.cl',
  'ventas@vinabike.cl',
  'https://vinabike.cl'
from public.tenants tenant
where tenant.id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
on conflict (tenant_id) do update
set from_name = excluded.from_name,
    from_email = excluded.from_email,
    reply_to_email = excluded.reply_to_email,
    public_store_url = excluded.public_store_url;

create table if not exists public.transactional_email_worker_runtime (
  singleton boolean primary key default true check (singleton),
  tenant_id uuid references public.tenants(id) on delete restrict,
  enabled boolean not null default false,
  delivery_mode text not null default 'dry_run'
    check (delivery_mode in ('dry_run', 'send')),
  batch_size integer not null default 20 check (batch_size between 1 and 50),
  last_request_id bigint,
  last_requested_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone not null default clock_timestamp(),
  updated_at timestamp with time zone not null default clock_timestamp()
);

alter table public.transactional_email_worker_runtime
  add column if not exists tenant_id uuid references public.tenants(id) on delete restrict;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.transactional_email_worker_runtime'::regclass
       and conname = 'transactional_email_worker_runtime_enabled_tenant'
  ) then
    alter table public.transactional_email_worker_runtime
      add constraint transactional_email_worker_runtime_enabled_tenant
      check (not enabled or tenant_id is not null);
  end if;
end;
$$;

insert into public.transactional_email_worker_runtime (
  singleton,
  enabled,
  delivery_mode,
  batch_size
) values (true, false, 'dry_run', 20)
on conflict (singleton) do nothing;

drop trigger if exists trg_transactional_email_worker_runtime_updated_at
  on public.transactional_email_worker_runtime;
create trigger trg_transactional_email_worker_runtime_updated_at
  before update on public.transactional_email_worker_runtime
  for each row execute function public.set_updated_at();

alter table public.transactional_email_worker_runtime enable row level security;
revoke all on public.transactional_email_worker_runtime
  from public, anon, authenticated, service_role;
grant select on public.transactional_email_worker_runtime to service_role;

create table if not exists public.transactional_email_delivery_phase_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  from_phase text not null check (from_phase in ('disabled', 'dry_run', 'send')),
  to_phase text not null check (to_phase in ('disabled', 'dry_run', 'send')),
  from_batch_size integer not null check (from_batch_size between 1 and 50),
  to_batch_size integer not null check (to_batch_size between 1 and 50),
  source text not null default 'service_role_phase_command',
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamp with time zone not null default clock_timestamp()
);

create index if not exists idx_transactional_email_delivery_phase_events_tenant_time
  on public.transactional_email_delivery_phase_events(tenant_id, occurred_at desc);

alter table public.transactional_email_delivery_phase_events enable row level security;

drop policy if exists transactional_email_delivery_phase_events_select
  on public.transactional_email_delivery_phase_events;
create policy transactional_email_delivery_phase_events_select
  on public.transactional_email_delivery_phase_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.transactional_email_delivery_phase_events
  from public, anon, authenticated, service_role;
grant select on public.transactional_email_delivery_phase_events to authenticated;

create or replace function public.prevent_transactional_email_delivery_phase_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Transactional email delivery phase events are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_transactional_email_delivery_phase_event_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_transactional_email_delivery_phase_events_immutable
  on public.transactional_email_delivery_phase_events;
create trigger trg_transactional_email_delivery_phase_events_immutable
  before update or delete on public.transactional_email_delivery_phase_events
  for each row execute function public.prevent_transactional_email_delivery_phase_event_mutation();

-- Sender identity and phase changes use the audited configuration function;
-- the Edge service role does not receive a parallel direct-write path.
revoke insert, update, delete on public.transactional_email_settings
  from service_role;
grant select on public.transactional_email_settings to service_role;

create or replace function public.configure_transactional_email_delivery_phase(
  p_tenant_id uuid,
  p_phase text,
  p_batch_size integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, pg_catalog
as $$
declare
  v_phase text := lower(btrim(coalesce(p_phase, '')));
  v_settings public.transactional_email_settings%rowtype;
  v_runtime public.transactional_email_worker_runtime%rowtype;
  v_from_phase text;
  v_worker_secret_present boolean := false;
  v_actor_id uuid;
begin
  if v_phase not in ('disabled', 'dry_run', 'send') then
    raise exception 'Unsupported transactional email delivery phase';
  end if;
  if p_batch_size not between 1 and 50 then
    raise exception 'Transactional email batch size must be between 1 and 50';
  end if;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Tenant transactional email settings are missing';
  end if;

  select * into v_runtime
  from public.transactional_email_worker_runtime
  where singleton
  for update;

  if not found then
    raise exception 'Transactional email worker runtime is missing';
  end if;

  v_from_phase := case
    when not v_runtime.enabled then 'disabled'
    else v_runtime.delivery_mode
  end;

  if v_phase = 'send'
     and not (
       v_runtime.enabled
       and v_runtime.tenant_id = p_tenant_id
       and v_runtime.delivery_mode in ('dry_run', 'send')
     ) then
    raise exception
      'Transactional email send phase requires prior dry-run activation for the same tenant';
  end if;

  if v_phase <> 'disabled' then
    select exists (
      select 1
      from vault.decrypted_secrets secret
      where secret.name = 'transactional_email_worker_secret'
        and nullif(secret.decrypted_secret, '') is not null
    ) into v_worker_secret_present;

    if not v_worker_secret_present then
      raise exception
        'Vault secret transactional_email_worker_secret is required before enabling the worker';
    end if;
  end if;

  if v_phase = 'send' then
    if nullif(btrim(v_settings.from_name), '') is null
       or nullif(btrim(v_settings.from_email), '') is null
       or nullif(btrim(v_settings.reply_to_email), '') is null
       or v_settings.public_store_url !~* '^https://[^[:space:]]+$' then
      raise exception
        'Send phase requires sender, reply-to and HTTPS public store identity';
    end if;

    if p_tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
       and (
         v_settings.from_name <> 'Ventas Viñabike'
         or lower(v_settings.from_email) <> 'ventas@vinabike.cl'
         or lower(v_settings.reply_to_email) <> 'ventas@vinabike.cl'
         or rtrim(v_settings.public_store_url, '/') <> 'https://vinabike.cl'
       ) then
      raise exception
        'Viñabike transactional sender differs from the reviewed deployment manifest';
    end if;
  end if;

  update public.transactional_email_settings
  set enabled = v_phase <> 'disabled',
      delivery_mode = case when v_phase = 'send' then 'send' else 'dry_run' end
  where tenant_id = p_tenant_id;

  update public.transactional_email_worker_runtime
  set tenant_id = p_tenant_id,
      enabled = v_phase <> 'disabled',
      delivery_mode = case when v_phase = 'send' then 'send' else 'dry_run' end,
      batch_size = p_batch_size,
      last_error = null
  where singleton;

  -- Service-role jobs normally have no auth user. Keep the audit FK valid even
  -- if a pooled session carries a stale/non-user JWT subject.
  v_actor_id := auth.uid();
  if v_actor_id is not null
     and not exists (select 1 from auth.users where id = v_actor_id) then
    v_actor_id := null;
  end if;

  insert into public.transactional_email_delivery_phase_events (
    tenant_id,
    from_phase,
    to_phase,
    from_batch_size,
    to_batch_size,
    source,
    actor_id
  ) values (
    p_tenant_id,
    v_from_phase,
    v_phase,
    v_runtime.batch_size,
    p_batch_size,
    'service_role_phase_command',
    v_actor_id
  );

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'phase', v_phase,
    'scheduler_enabled', v_phase <> 'disabled',
    'delivery_mode', case when v_phase = 'send' then 'send' else 'dry_run' end,
    'batch_size', p_batch_size
  );
end;
$$;

create or replace function public.claim_transactional_email_outbox_for_tenant(
  p_tenant_id uuid,
  p_worker_id text,
  p_delivery_mode text default 'dry_run',
  p_batch_size integer default 20,
  p_lease_seconds integer default 120
)
returns setof public.transactional_email_outbox
language plpgsql
security definer
set search_path = public
as $$
declare
  v_runtime public.transactional_email_worker_runtime%rowtype;
begin
  if p_tenant_id is null then
    raise exception 'Transactional email worker tenant is required';
  end if;
  if nullif(btrim(p_worker_id), '') is null then
    raise exception 'Worker id is required';
  end if;
  if p_delivery_mode not in ('dry_run', 'send') then
    raise exception 'Invalid delivery mode: %', p_delivery_mode;
  end if;
  if p_batch_size not between 1 and 50 then
    raise exception 'Batch size must be between 1 and 50';
  end if;
  if p_lease_seconds not between 15 and 900 then
    raise exception 'Lease seconds must be between 15 and 900';
  end if;

  select * into v_runtime
  from public.transactional_email_worker_runtime
  where singleton;

  if not found
     or not v_runtime.enabled
     or v_runtime.tenant_id is distinct from p_tenant_id
     or v_runtime.delivery_mode is distinct from p_delivery_mode then
    raise exception 'Transactional email worker runtime does not authorize this tenant and mode'
      using errcode = '42501';
  end if;

  perform set_config('app.transactional_email_mutation', 'true', true);

  -- Suppress claimable rows that predate a hard bounce or complaint. A live
  -- lease may already be in flight and is therefore left for webhook/lease
  -- reconciliation; pending and expired leases fail closed here.
  update public.transactional_email_outbox outbox
  set state = 'suppressed',
      suppression_reason = suppression.reason,
      last_error_class = coalesce(outbox.last_error_class, 'recipient_suppressed'),
      last_error_message = coalesce(
        outbox.last_error_message,
        'Recipient is present in the active transactional suppression ledger'
      ),
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null
  from public.transactional_email_suppressions suppression
  where outbox.tenant_id = p_tenant_id
    and outbox.delivery_mode = p_delivery_mode
    and suppression.tenant_id = outbox.tenant_id
    and suppression.email_sha256 = encode(
      extensions.digest(convert_to(outbox.recipient_email, 'UTF8'), 'sha256'),
      'hex'
    )
    and suppression.lifted_at is null
    and (
      outbox.state = 'pending'
      or (
        outbox.state = 'leased'
        and outbox.lease_expires_at < clock_timestamp()
      )
    );

  update public.transactional_email_outbox
  set state = 'dead_letter',
      failed_at = coalesce(failed_at, clock_timestamp()),
      last_error_class = coalesce(last_error_class, 'attempts_exhausted'),
      last_error_message = coalesce(
        last_error_message,
        'Maximum delivery attempts exhausted'
      ),
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null
  where tenant_id = p_tenant_id
    and delivery_mode = p_delivery_mode
    and state in ('pending', 'leased')
    and attempt_count >= max_attempts
    and (state = 'pending' or lease_expires_at < clock_timestamp());

  return query
  with candidates as (
    select outbox.id
    from public.transactional_email_outbox outbox
    where outbox.tenant_id = p_tenant_id
      and outbox.delivery_mode = p_delivery_mode
      and outbox.attempt_count < outbox.max_attempts
      and outbox.available_at <= clock_timestamp()
      and (
        outbox.state = 'pending'
        or (
          outbox.state = 'leased'
          and outbox.lease_expires_at < clock_timestamp()
        )
      )
    order by outbox.available_at, outbox.created_at, outbox.id
    for update skip locked
    limit p_batch_size
  )
  update public.transactional_email_outbox outbox
  set state = 'leased',
      lease_owner = btrim(p_worker_id),
      lease_token = gen_random_uuid(),
      lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
      attempt_count = outbox.attempt_count + 1,
      last_attempt_at = clock_timestamp()
  from candidates
  where outbox.id = candidates.id
  returning outbox.*;
end;
$$;

create or replace function public.invoke_transactional_email_worker()
returns bigint
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_runtime public.transactional_email_worker_runtime%rowtype;
  v_worker_secret text;
  v_request_id bigint;
begin
  select * into v_runtime
  from public.transactional_email_worker_runtime
  where singleton;

  if not found or not v_runtime.enabled or v_runtime.tenant_id is null then
    return null;
  end if;

  select secret.decrypted_secret into v_worker_secret
  from vault.decrypted_secrets secret
  where secret.name = 'transactional_email_worker_secret'
  order by secret.created_at desc
  limit 1;

  if nullif(v_worker_secret, '') is null then
    update public.transactional_email_worker_runtime
    set last_error = 'Missing Vault secret transactional_email_worker_secret'
    where singleton;
    return null;
  end if;

  select net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/send-transactional-order-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-transactional-email-worker-secret', v_worker_secret
    ),
    body := jsonb_build_object(
      'action', 'process',
      'tenant_id', v_runtime.tenant_id,
      'mode', v_runtime.delivery_mode,
      'limit', v_runtime.batch_size
    ),
    timeout_milliseconds := 15000
  ) into v_request_id;

  update public.transactional_email_worker_runtime
  set last_request_id = v_request_id,
      last_requested_at = clock_timestamp(),
      last_error = null
  where singleton;

  return v_request_id;
exception
  when others then
    update public.transactional_email_worker_runtime
    set last_error = left(sqlerrm, 2000)
    where singleton;
    return null;
end;
$$;

revoke all on function public.configure_transactional_email_delivery_phase(
  uuid, text, integer
) from public, anon, authenticated;
grant execute on function public.configure_transactional_email_delivery_phase(
  uuid, text, integer
) to service_role;

revoke all on function public.claim_transactional_email_outbox_for_tenant(
  uuid, text, text, integer, integer
) from public, anon, authenticated;
grant execute on function public.claim_transactional_email_outbox_for_tenant(
  uuid, text, text, integer, integer
) to service_role;

revoke all on function public.invoke_transactional_email_worker()
  from public, anon, authenticated;
grant execute on function public.invoke_transactional_email_worker()
  to service_role;

do $$
begin
  if to_regclass('cron.job') is null then
    raise notice
      'pg_cron is unavailable; transactional email worker schedule was not installed';
    return;
  end if;

  perform cron.unschedule(job.jobid)
  from cron.job job
  where job.jobname = 'vinabike_transactional_email_worker';

  perform cron.schedule(
    'vinabike_transactional_email_worker',
    '* * * * *',
    'select public.invoke_transactional_email_worker();'
  );
exception
  when others then
    raise notice
      'Could not install transactional email worker schedule: %', sqlerrm;
end $$;

comment on table public.transactional_email_worker_runtime is
  'Fail-closed single-tenant Edge worker scheduler configuration. Disabled until an explicit dry_run phase.';
comment on table public.transactional_email_delivery_phase_events is
  'Append-only audit trail for every explicit transactional email delivery phase command.';
comment on function public.configure_transactional_email_delivery_phase(uuid, text, integer) is
  'Service-role-only phase gate: disabled -> dry_run -> send. It never stores or returns secret values.';
comment on function public.claim_transactional_email_outbox_for_tenant(uuid, text, text, integer, integer) is
  'Runtime-gated tenant-scoped outbox claim; prevents one activated tenant from leasing another tenant email.';
comment on function public.invoke_transactional_email_worker() is
  'Cron-safe pg_net invocation using a dedicated worker secret from Supabase Vault.';

commit;
