-- Durable, replay-safe Checkout Pro preference lifecycle.
--
-- A preference is a payable provider resource. Creating one without a local
-- receipt makes a lost HTTP acknowledgement indistinguishable from failure and
-- lets repeated clicks create several live payment links. This migration adds
-- one tenant-scoped lifecycle ledger, server-owned leases, lost-ack recovery
-- coordinates, reservation-aligned expiry, and a durable expiration worker.
--
-- No provider credential, payer identity, card data, webhook body, or raw API
-- response is stored here. Existing preferences are not invented/backfilled.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create table if not exists public.online_order_payment_preferences (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null,
  provider text not null default 'mercadopago'
    check (provider = 'mercadopago'),
  generation integer not null check (generation > 0 and generation <= 999999),
  external_reference text not null
    check (length(external_reference) between 1 and 150),
  request_fingerprint text not null
    check (request_fingerprint ~ '^[0-9a-f]{64}$'),
  amount numeric(12,2) not null check (amount > 0 and amount = trunc(amount)),
  currency text not null default 'CLP' check (currency = 'CLP'),
  state text not null check (state in (
    'creating', 'active', 'create_failed',
    'expiration_requested', 'expiring', 'expiration_failed', 'expired'
  )),
  provider_preference_id text,
  init_point text,
  sandbox_init_point text,
  effective_from timestamptz not null,
  expires_at timestamptz not null,
  provider_created_at timestamptz,
  provider_expires_at timestamptz,
  lease_token uuid,
  lease_owner text,
  lease_expires_at timestamptz,
  create_attempt_count integer not null default 0 check (create_attempt_count >= 0),
  expiration_attempt_count integer not null default 0
    check (expiration_attempt_count >= 0),
  expiration_requested_at timestamptz,
  expiration_reason text,
  expired_at timestamptz,
  next_attempt_at timestamptz not null default clock_timestamp(),
  last_error_code text,
  last_error_message text,
  last_provider_status integer,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint online_order_payment_preferences_order_tenant_fkey
    foreign key (tenant_id, order_id)
    references public.online_orders(tenant_id, id) on delete restrict,
  constraint online_order_payment_preferences_generation_key
    unique (tenant_id, order_id, provider, generation),
  constraint online_order_payment_preferences_external_reference_key
    unique (external_reference),
  check (expires_at > effective_from),
  check (provider_preference_id is null or (
    nullif(btrim(provider_preference_id), '') is not null
    and length(provider_preference_id) <= 160
  )),
  check (init_point is null or (
    length(init_point) <= 2048 and init_point ~ '^https://'
  )),
  check (sandbox_init_point is null or (
    length(sandbox_init_point) <= 2048 and sandbox_init_point ~ '^https://'
  )),
  check (lease_owner is null or (
    nullif(btrim(lease_owner), '') is not null and length(lease_owner) <= 160
  )),
  check (last_error_code is null or (
    nullif(btrim(last_error_code), '') is not null
    and length(last_error_code) <= 96
  )),
  check (last_error_message is null or (
    nullif(btrim(last_error_message), '') is not null
    and length(last_error_message) <= 320
  )),
  check (last_provider_status is null or last_provider_status between 100 and 599),
  check (
    state not in ('active', 'expiration_requested', 'expiring',
      'expiration_failed', 'expired')
    or provider_preference_id is not null
    or state in ('expiration_requested', 'expiring', 'expiration_failed', 'expired')
  ),
  check (
    state <> 'active'
    or (provider_preference_id is not null and init_point is not null)
  ),
  check (state <> 'expired' or expired_at is not null)
);

create unique index if not exists uq_online_order_payment_preferences_provider_id
  on public.online_order_payment_preferences(provider, provider_preference_id)
  where provider_preference_id is not null;
create index if not exists idx_online_order_payment_preferences_order
  on public.online_order_payment_preferences(
    tenant_id, order_id, generation desc, created_at desc
  );
create index if not exists idx_online_order_payment_preferences_expiration
  on public.online_order_payment_preferences(
    state, next_attempt_at, expires_at, created_at
  ) where state in ('expiration_requested', 'expiration_failed', 'expiring');

comment on table public.online_order_payment_preferences is
  'Durable Checkout Pro preference lifecycle. Links one server-owned order snapshot to provider preference IDs without storing provider credentials or raw responses.';
comment on column public.online_order_payment_preferences.external_reference is
  'Server-built vb1:<tenant_uuid>:<order_uuid>:<generation> provider correlation key; never accepted from the browser.';
comment on column public.online_order_payment_preferences.request_fingerprint is
  'SHA-256 of the normalized server-owned provider request used to reject conflicting replay.';

alter table public.online_order_payment_preferences enable row level security;

drop policy if exists online_order_payment_preferences_staff_read
  on public.online_order_payment_preferences;
create policy online_order_payment_preferences_staff_read
  on public.online_order_payment_preferences for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.online_order_payment_preferences
  from public, anon, authenticated, service_role;
grant select (
  id, tenant_id, order_id, provider, generation, external_reference,
  amount, currency, state, provider_preference_id, effective_from, expires_at,
  provider_created_at, provider_expires_at, create_attempt_count,
  expiration_attempt_count, expiration_requested_at, expiration_reason,
  expired_at, next_attempt_at, last_error_code, last_error_message,
  last_provider_status, created_at, updated_at
) on public.online_order_payment_preferences to authenticated;

create or replace function public.guard_online_order_payment_preference_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Payment preference evidence cannot be deleted'
      using errcode = '55000';
  end if;
  if current_setting('app.mercadopago_preference_write', true) <> 'true' then
    raise exception 'Payment preferences can only change through canonical commands'
      using errcode = '55000';
  end if;
  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id
    or new.tenant_id is distinct from old.tenant_id
    or new.order_id is distinct from old.order_id
    or new.provider is distinct from old.provider
    or new.generation is distinct from old.generation
    or new.external_reference is distinct from old.external_reference
    or new.request_fingerprint is distinct from old.request_fingerprint
    or new.amount is distinct from old.amount
    or new.currency is distinct from old.currency
    or new.effective_from is distinct from old.effective_from
    or new.expires_at is distinct from old.expires_at
    or new.created_at is distinct from old.created_at
  ) then
    raise exception 'Immutable payment preference identity or charge was changed'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_online_order_payment_preference_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_online_order_payment_preferences
  on public.online_order_payment_preferences;
create trigger trg_guard_online_order_payment_preferences
  before insert or update or delete on public.online_order_payment_preferences
  for each row execute function
    public.guard_online_order_payment_preference_mutation();

create or replace function public.begin_mercadopago_preference_creation(
  p_order_id uuid,
  p_request_fingerprint text,
  p_lease_token uuid,
  p_lease_owner text,
  p_lease_seconds integer default 45
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.online_orders%rowtype;
  v_preference public.online_order_payment_preferences%rowtype;
  v_now timestamptz := clock_timestamp();
  v_deadline timestamptz;
  v_generation integer;
  v_ttl_minutes integer := 30;
  v_setting text;
  v_external_reference text;
begin
  if p_order_id is null
     or coalesce(p_request_fingerprint, '') !~ '^[0-9a-f]{64}$'
     or p_lease_token is null
     or nullif(btrim(coalesce(p_lease_owner, '')), '') is null
     or length(btrim(p_lease_owner)) > 160
     or p_lease_seconds not between 15 and 120 then
    raise exception 'Invalid Mercado Pago preference creation request'
      using errcode = '22023';
  end if;

  select * into v_order
  from public.online_orders orders
  where orders.id = p_order_id
  for update;

  if not found then
    raise exception 'Online order not found for payment preference'
      using errcode = '23503';
  end if;
  if lower(coalesce(v_order.payment_method, '')) not in ('mercadopago', 'mercado_pago') then
    raise exception 'Online order is not configured for Mercado Pago'
      using errcode = '23514';
  end if;
  if v_order.status <> 'pending'
     or v_order.payment_status not in ('pending', 'failed')
     or v_order.cancelled_at is not null
     or v_order.paid_at is not null then
    raise exception 'Online order is no longer payable'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.sales_channel_payment_events event
    where event.tenant_id = v_order.tenant_id
      and event.order_id = v_order.id
      and event.provider = 'mercadopago'
      and event.provider_status = 'approved'
      and event.outcome in ('payment_validated', 'applied')
  ) then
    raise exception 'A provider-approved payment already exists for this order'
      using errcode = '23514';
  end if;

  select * into v_preference
  from public.online_order_payment_preferences preference
  where preference.tenant_id = v_order.tenant_id
    and preference.order_id = v_order.id
    and preference.provider = 'mercadopago'
  order by preference.generation desc
  limit 1
  for update;

  if found and v_preference.expires_at <= v_now then
    perform set_config('app.mercadopago_preference_write', 'true', true);
    update public.online_order_payment_preferences preference
    set state = 'expired',
        expired_at = coalesce(preference.expired_at, v_now),
        lease_token = null,
        lease_owner = null,
        lease_expires_at = null,
        updated_at = v_now
    where preference.id = v_preference.id;
    perform set_config('app.mercadopago_preference_write', '', true);
    v_preference := null;
  end if;

  if to_regprocedure(
    'public.renew_online_order_inventory_reservations(uuid)'
  ) is null then
    raise exception 'Inventory reservation renewal is unavailable'
      using errcode = '55000';
  end if;

  -- Revalidate inventory on every click, including an active replay and a
  -- recovery after a lost provider acknowledgement. The existing provider
  -- term is never extended here; renewal only proves that returning/recovering
  -- that link is still backed by physical availability.
  begin
    v_deadline := public.renew_online_order_inventory_reservations(v_order.id);
  exception when check_violation then
    if v_preference.id is null
       or v_preference.state not in ('active', 'creating') then
      raise;
    end if;

    -- Do not roll back into a still-live provider link when inventory changed.
    -- Returning an explicit unavailable receipt lets this transaction retain
    -- the expiry request; the Edge Function returns 409 without exposing the
    -- old checkout URL, and the worker closes any acknowledged or lost-ACK
    -- provider resource by its durable external reference.
    perform set_config('app.mercadopago_preference_write', 'true', true);
    update public.online_order_payment_preferences preference
    set state = 'expiration_requested',
        expiration_requested_at = coalesce(
          preference.expiration_requested_at, v_now
        ),
        expiration_reason = 'inventory_revalidation_failed',
        next_attempt_at = v_now,
        lease_token = null,
        lease_owner = null,
        lease_expires_at = null,
        last_error_code = 'inventory_revalidation_failed',
        last_error_message =
          'Inventory no longer backs this provider preference.',
        updated_at = v_now
    where preference.id = v_preference.id
    returning * into v_preference;
    perform set_config('app.mercadopago_preference_write', '', true);

    return to_jsonb(v_preference) || jsonb_build_object(
      'action', 'unavailable',
      'reason', 'inventory_revalidation_failed',
      'replay', false
    );
  end;

  if v_preference.id is not null
     and v_preference.request_fingerprint = p_request_fingerprint
     and v_preference.expires_at > v_now + interval '90 seconds' then
    if v_preference.state = 'active' then
      return to_jsonb(v_preference) || jsonb_build_object(
        'action', 'replay', 'replay', true
      );
    end if;
    if v_preference.state = 'creating' then
      if v_preference.lease_expires_at > v_now
         and v_preference.lease_token is distinct from p_lease_token then
        return jsonb_build_object(
          'id', v_preference.id,
          'action', 'busy',
          'retry_after_seconds', greatest(
            1,
            ceil(extract(epoch from (v_preference.lease_expires_at - v_now)))::integer
          )
        );
      end if;

      perform set_config('app.mercadopago_preference_write', 'true', true);
      update public.online_order_payment_preferences preference
      set lease_token = p_lease_token,
          lease_owner = btrim(p_lease_owner),
          lease_expires_at = v_now + make_interval(secs => p_lease_seconds),
          create_attempt_count = preference.create_attempt_count + 1,
          last_error_code = null,
          last_error_message = null,
          updated_at = v_now
      where preference.id = v_preference.id
      returning * into v_preference;
      perform set_config('app.mercadopago_preference_write', '', true);

      return to_jsonb(v_preference) || jsonb_build_object(
        'action', 'recover_or_create', 'replay', false
      );
    end if;
  end if;

  if v_preference.id is not null
     and v_preference.state in ('active', 'creating') then
    perform set_config('app.mercadopago_preference_write', 'true', true);
    update public.online_order_payment_preferences preference
    set state = 'expiration_requested',
        expiration_requested_at = coalesce(preference.expiration_requested_at, v_now),
        expiration_reason = 'superseded_request_fingerprint',
        next_attempt_at = v_now,
        lease_token = null,
        lease_owner = null,
        lease_expires_at = null,
        updated_at = v_now
    where preference.id = v_preference.id;
    perform set_config('app.mercadopago_preference_write', '', true);
  end if;

  select setting.value into v_setting
  from public.website_settings setting
  where setting.tenant_id = v_order.tenant_id
    and setting.key = 'online_order_reservation_minutes_mercadopago'
  limit 1;
  if coalesce(v_setting, '') ~ '^[0-9]{1,3}$' then
    v_ttl_minutes := greatest(5, least(60, v_setting::integer));
  end if;

  -- Service-only/untracked orders intentionally have no inventory reservation.
  -- They still receive the bounded server TTL; tracked out-of-stock orders fail
  -- inside the renewal RPC before this fallback can be reached.
  v_deadline := case
    when v_deadline is null then v_now + make_interval(mins => v_ttl_minutes)
    else least(v_deadline, v_now + make_interval(mins => v_ttl_minutes))
  end;
  if v_deadline <= v_now + interval '90 seconds' then
    raise exception 'Inventory reservation expires too soon to initiate payment'
      using errcode = '23514';
  end if;

  select coalesce(max(preference.generation), 0) + 1
  into v_generation
  from public.online_order_payment_preferences preference
  where preference.tenant_id = v_order.tenant_id
    and preference.order_id = v_order.id
    and preference.provider = 'mercadopago';
  if v_generation > 999999 then
    raise exception 'Payment preference generation limit reached'
      using errcode = '54000';
  end if;

  v_external_reference := format(
    'vb1:%s:%s:%s', v_order.tenant_id, v_order.id, v_generation
  );

  perform set_config('app.mercadopago_preference_write', 'true', true);
  insert into public.online_order_payment_preferences (
    tenant_id, order_id, generation, external_reference,
    request_fingerprint, amount, currency, state,
    effective_from, expires_at, lease_token, lease_owner,
    lease_expires_at, create_attempt_count, next_attempt_at
  ) values (
    v_order.tenant_id, v_order.id, v_generation, v_external_reference,
    p_request_fingerprint, v_order.total, 'CLP', 'creating',
    v_now, v_deadline, p_lease_token, btrim(p_lease_owner),
    v_now + make_interval(secs => p_lease_seconds), 1, v_now
  ) returning * into v_preference;
  perform set_config('app.mercadopago_preference_write', '', true);

  return to_jsonb(v_preference) || jsonb_build_object(
    'action', 'recover_or_create', 'replay', false
  );
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

create or replace function public.finalize_mercadopago_preference_creation(
  p_preference_record_id uuid,
  p_lease_token uuid,
  p_provider_preference_id text,
  p_init_point text,
  p_sandbox_init_point text,
  p_provider_created_at timestamptz,
  p_provider_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preference public.online_order_payment_preferences%rowtype;
  v_order public.online_orders%rowtype;
  v_now timestamptz := clock_timestamp();
  v_target_state text;
begin
  if p_preference_record_id is null or p_lease_token is null
     or nullif(btrim(coalesce(p_provider_preference_id, '')), '') is null
     or length(btrim(p_provider_preference_id)) > 160
     or nullif(btrim(coalesce(p_init_point, '')), '') is null
     or length(btrim(p_init_point)) > 2048
     or p_init_point !~ '^https://([^/]+[.])?mercadopago[.](com([.][a-z]{2})?|[a-z]{2})/'
     or (p_sandbox_init_point is not null and (
       length(btrim(p_sandbox_init_point)) > 2048
       or p_sandbox_init_point !~ '^https://([^/]+[.])?mercadopago[.](com([.][a-z]{2})?|[a-z]{2})/'
     ))
     or p_provider_expires_at is null then
    raise exception 'Invalid Mercado Pago preference provider result'
      using errcode = '22023';
  end if;

  select * into v_preference
  from public.online_order_payment_preferences preference
  where preference.id = p_preference_record_id
  for update;
  if not found then
    raise exception 'Payment preference receipt not found'
      using errcode = '23503';
  end if;

  if v_preference.provider_preference_id = btrim(p_provider_preference_id)
     and v_preference.state in ('active', 'expiration_requested', 'expiring',
       'expiration_failed', 'expired') then
    return to_jsonb(v_preference) || jsonb_build_object('replay', true);
  end if;
  if v_preference.state not in ('creating', 'expiration_requested')
     or v_preference.lease_token is distinct from p_lease_token then
    raise exception 'Payment preference creation lease is no longer owned'
      using errcode = '40001';
  end if;
  if abs(extract(epoch from (p_provider_expires_at - v_preference.expires_at))) > 60 then
    raise exception 'Provider preference expiry differs from inventory reservation'
      using errcode = '23514';
  end if;

  select * into v_order
  from public.online_orders orders
  where orders.id = v_preference.order_id
    and orders.tenant_id = v_preference.tenant_id
  for update;
  if not found then
    raise exception 'Online order disappeared during preference creation'
      using errcode = '23503';
  end if;

  v_target_state := case
    when v_preference.state = 'expiration_requested'
      or v_order.status <> 'pending'
      or v_order.payment_status not in ('pending', 'failed')
      or v_order.cancelled_at is not null
      or v_order.paid_at is not null
      or v_preference.expires_at <= v_now
    then 'expiring'
    else 'active'
  end;

  perform set_config('app.mercadopago_preference_write', 'true', true);
  update public.online_order_payment_preferences preference
  set state = v_target_state,
      provider_preference_id = btrim(p_provider_preference_id),
      init_point = btrim(p_init_point),
      sandbox_init_point = nullif(btrim(coalesce(p_sandbox_init_point, '')), ''),
      provider_created_at = p_provider_created_at,
      provider_expires_at = p_provider_expires_at,
      lease_token = case when v_target_state = 'expiring'
        then p_lease_token else null end,
      lease_owner = case when v_target_state = 'expiring'
        then 'inline-create-finalizer' else null end,
      lease_expires_at = case when v_target_state = 'expiring'
        then v_now + interval '90 seconds' else null end,
      expiration_attempt_count = preference.expiration_attempt_count
        + case when v_target_state = 'expiring' then 1 else 0 end,
      expiration_requested_at = case when v_target_state = 'expiring'
        then coalesce(preference.expiration_requested_at, v_now)
        else preference.expiration_requested_at end,
      expiration_reason = case when v_target_state = 'expiring'
        then coalesce(preference.expiration_reason, 'order_no_longer_payable')
        else preference.expiration_reason end,
      next_attempt_at = v_now,
      last_error_code = null,
      last_error_message = null,
      updated_at = v_now
  where preference.id = v_preference.id
  returning * into v_preference;
  perform set_config('app.mercadopago_preference_write', '', true);

  return to_jsonb(v_preference) || jsonb_build_object(
    'replay', false,
    'payable', v_target_state = 'active'
  );
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

create or replace function public.record_mercadopago_preference_create_failure(
  p_preference_record_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_error_code text,
  p_error_message text,
  p_provider_status integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preference public.online_order_payment_preferences%rowtype;
  v_now timestamptz := clock_timestamp();
  v_outcome text := lower(btrim(coalesce(p_outcome, '')));
begin
  if v_outcome not in ('definite_failure', 'outcome_unknown') then
    raise exception 'Invalid payment preference failure outcome'
      using errcode = '22023';
  end if;
  select * into v_preference
  from public.online_order_payment_preferences preference
  where preference.id = p_preference_record_id
  for update;
  if not found or v_preference.lease_token is distinct from p_lease_token then
    raise exception 'Payment preference creation lease is no longer owned'
      using errcode = '40001';
  end if;

  perform set_config('app.mercadopago_preference_write', 'true', true);
  update public.online_order_payment_preferences preference
  set state = case when v_outcome = 'definite_failure'
        then 'create_failed' else 'creating' end,
      lease_token = null,
      lease_owner = null,
      lease_expires_at = null,
      next_attempt_at = v_now,
      last_error_code = left(coalesce(
        nullif(btrim(p_error_code), ''), v_outcome
      ), 96),
      last_error_message = left(coalesce(
        nullif(btrim(p_error_message), ''),
        'Mercado Pago preference creation did not complete.'
      ), 320),
      last_provider_status = p_provider_status,
      updated_at = v_now
  where preference.id = v_preference.id
  returning * into v_preference;
  perform set_config('app.mercadopago_preference_write', '', true);
  return to_jsonb(v_preference) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

create or replace function public.request_mercadopago_preference_expiration()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_now timestamptz := clock_timestamp();
begin
  if new.status = 'cancelled' and old.status is distinct from new.status then
    v_reason := 'order_cancelled';
  elsif new.payment_status in ('paid', 'refunded')
     and old.payment_status is distinct from new.payment_status then
    v_reason := 'payment_' || new.payment_status;
  else
    return new;
  end if;

  perform set_config('app.mercadopago_preference_write', 'true', true);
  update public.online_order_payment_preferences preference
  set state = case
        when preference.expires_at <= v_now then 'expired'
        else 'expiration_requested' end,
      expiration_requested_at = coalesce(preference.expiration_requested_at, v_now),
      expiration_reason = coalesce(preference.expiration_reason, v_reason),
      expired_at = case when preference.expires_at <= v_now
        then coalesce(preference.expired_at, v_now) else preference.expired_at end,
      next_attempt_at = v_now,
      lease_token = null,
      lease_owner = null,
      lease_expires_at = null,
      updated_at = v_now
  where preference.tenant_id = new.tenant_id
    and preference.order_id = new.id
    and preference.provider = 'mercadopago'
    and preference.state in (
      'creating', 'active', 'expiration_requested', 'expiration_failed'
    );
  perform set_config('app.mercadopago_preference_write', '', true);
  return new;
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

revoke all on function public.request_mercadopago_preference_expiration()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_request_mercadopago_preference_expiration
  on public.online_orders;
create trigger trg_request_mercadopago_preference_expiration
  after update of status, payment_status on public.online_orders
  for each row execute function
    public.request_mercadopago_preference_expiration();

create or replace function public.claim_mercadopago_preference_expirations(
  p_worker_id text,
  p_limit integer default 20,
  p_lease_seconds integer default 90
)
returns setof public.online_order_payment_preferences
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(btrim(coalesce(p_worker_id, '')), '') is null
     or length(btrim(p_worker_id)) > 160
     or p_limit not between 1 and 50
     or p_lease_seconds not between 30 and 300 then
    raise exception 'Invalid preference expiration worker claim'
      using errcode = '22023';
  end if;

  perform set_config('app.mercadopago_preference_write', 'true', true);
  update public.online_order_payment_preferences preference
  set state = 'expired',
      expired_at = coalesce(preference.expired_at, clock_timestamp()),
      lease_token = null,
      lease_owner = null,
      lease_expires_at = null,
      updated_at = clock_timestamp()
  where preference.state in (
      'active', 'expiration_requested', 'expiration_failed', 'expiring'
    )
    and preference.expires_at <= clock_timestamp();

  return query
  with candidates as (
    select preference.id
    from public.online_order_payment_preferences preference
    where (
        preference.state in ('expiration_requested', 'expiration_failed')
        or (
          preference.state = 'expiring'
          and preference.lease_expires_at <= clock_timestamp()
        )
      )
      and preference.next_attempt_at <= clock_timestamp()
      and preference.expires_at > clock_timestamp()
    order by preference.next_attempt_at, preference.created_at, preference.id
    for update skip locked
    limit p_limit
  )
  update public.online_order_payment_preferences preference
  set state = 'expiring',
      lease_token = gen_random_uuid(),
      lease_owner = btrim(p_worker_id),
      lease_expires_at = clock_timestamp() + make_interval(secs => p_lease_seconds),
      expiration_attempt_count = preference.expiration_attempt_count + 1,
      updated_at = clock_timestamp()
  from candidates
  where preference.id = candidates.id
  returning preference.*;
  perform set_config('app.mercadopago_preference_write', '', true);
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

create or replace function public.complete_mercadopago_preference_expiration(
  p_preference_record_id uuid,
  p_lease_token uuid,
  p_result text,
  p_provider_preference_id text default null,
  p_error_code text default null,
  p_error_message text default null,
  p_provider_status integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preference public.online_order_payment_preferences%rowtype;
  v_result text := lower(btrim(coalesce(p_result, '')));
  v_now timestamptz := clock_timestamp();
  v_backoff_seconds integer;
begin
  if v_result not in ('expired', 'provider_absent', 'retry') then
    raise exception 'Invalid preference expiration completion result'
      using errcode = '22023';
  end if;
  select * into v_preference
  from public.online_order_payment_preferences preference
  where preference.id = p_preference_record_id
  for update;
  if not found then
    raise exception 'Payment preference receipt not found'
      using errcode = '23503';
  end if;
  if v_preference.state = 'expired' then
    return to_jsonb(v_preference) || jsonb_build_object('replay', true);
  end if;
  if v_preference.state <> 'expiring'
     or v_preference.lease_token is distinct from p_lease_token then
    raise exception 'Preference expiration lease is no longer owned'
      using errcode = '40001';
  end if;

  if p_provider_preference_id is not null
     and v_preference.provider_preference_id is not null
     and btrim(p_provider_preference_id) <> v_preference.provider_preference_id then
    raise exception 'Expiration result conflicts with durable provider identity'
      using errcode = '23000';
  end if;
  v_backoff_seconds := least(
    1800,
    greatest(30, (30 * power(2, least(v_preference.expiration_attempt_count, 6)))::integer)
  );

  perform set_config('app.mercadopago_preference_write', 'true', true);
  update public.online_order_payment_preferences preference
  set state = case when v_result in ('expired', 'provider_absent')
        then 'expired' else 'expiration_failed' end,
      provider_preference_id = coalesce(
        preference.provider_preference_id,
        nullif(btrim(coalesce(p_provider_preference_id, '')), '')
      ),
      expired_at = case when v_result in ('expired', 'provider_absent')
        then v_now else preference.expired_at end,
      next_attempt_at = case when v_result = 'retry'
        then v_now + make_interval(secs => v_backoff_seconds) else v_now end,
      lease_token = null,
      lease_owner = null,
      lease_expires_at = null,
      last_error_code = case when v_result = 'retry'
        then left(coalesce(nullif(btrim(p_error_code), ''), 'provider_retry'), 96)
        else null end,
      last_error_message = case when v_result = 'retry'
        then left(coalesce(nullif(btrim(p_error_message), ''),
          'Mercado Pago preference expiration will retry.'), 320)
        else null end,
      last_provider_status = p_provider_status,
      updated_at = v_now
  where preference.id = v_preference.id
  returning * into v_preference;
  perform set_config('app.mercadopago_preference_write', '', true);

  return to_jsonb(v_preference) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.mercadopago_preference_write', '', true);
  raise;
end;
$$;

revoke all on function public.begin_mercadopago_preference_creation(
  uuid, text, uuid, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.begin_mercadopago_preference_creation(
  uuid, text, uuid, text, integer
) to service_role;
revoke all on function public.finalize_mercadopago_preference_creation(
  uuid, uuid, text, text, text, timestamptz, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function public.finalize_mercadopago_preference_creation(
  uuid, uuid, text, text, text, timestamptz, timestamptz
) to service_role;
revoke all on function public.record_mercadopago_preference_create_failure(
  uuid, uuid, text, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.record_mercadopago_preference_create_failure(
  uuid, uuid, text, text, text, integer
) to service_role;
revoke all on function public.claim_mercadopago_preference_expirations(
  text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.claim_mercadopago_preference_expirations(
  text, integer, integer
) to service_role;
revoke all on function public.complete_mercadopago_preference_expiration(
  uuid, uuid, text, text, text, text, integer
) from public, anon, authenticated, service_role;
grant execute on function public.complete_mercadopago_preference_expiration(
  uuid, uuid, text, text, text, text, integer
) to service_role;

create table if not exists public.mercadopago_preference_worker_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  batch_size integer not null default 20 check (batch_size between 1 and 50),
  last_request_id bigint,
  last_requested_at timestamptz,
  last_error text,
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.mercadopago_preference_worker_runtime(singleton, enabled)
values (true, false) on conflict (singleton) do nothing;
alter table public.mercadopago_preference_worker_runtime enable row level security;
revoke all on public.mercadopago_preference_worker_runtime
  from public, anon, authenticated, service_role;
grant select on public.mercadopago_preference_worker_runtime to service_role;

create or replace function public.configure_mercadopago_preference_worker(
  p_enabled boolean,
  p_batch_size integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_secret_present boolean := false;
  v_runtime public.mercadopago_preference_worker_runtime%rowtype;
begin
  if p_batch_size not between 1 and 50 then
    raise exception 'Mercado Pago worker batch size must be between 1 and 50'
      using errcode = '22023';
  end if;
  if p_enabled then
    select exists (
      select 1 from vault.decrypted_secrets secret
      where secret.name = 'mercadopago_preference_worker_secret'
        and nullif(secret.decrypted_secret, '') is not null
    ) into v_secret_present;
    if not v_secret_present then
      raise exception 'Vault secret mercadopago_preference_worker_secret is required'
        using errcode = '55000';
    end if;
  end if;
  update public.mercadopago_preference_worker_runtime
  set enabled = p_enabled,
      batch_size = p_batch_size,
      last_error = null,
      updated_at = clock_timestamp()
  where singleton
  returning * into v_runtime;
  return to_jsonb(v_runtime);
end;
$$;

create or replace function public.invoke_mercadopago_preference_worker()
returns bigint
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_runtime public.mercadopago_preference_worker_runtime%rowtype;
  v_worker_secret text;
  v_request_id bigint;
begin
  select * into v_runtime
  from public.mercadopago_preference_worker_runtime where singleton;
  if not found or not v_runtime.enabled then return null; end if;

  select secret.decrypted_secret into v_worker_secret
  from vault.decrypted_secrets secret
  where secret.name = 'mercadopago_preference_worker_secret'
  order by secret.created_at desc limit 1;
  if nullif(v_worker_secret, '') is null then
    update public.mercadopago_preference_worker_runtime
    set last_error = 'Missing Vault secret mercadopago_preference_worker_secret',
        updated_at = clock_timestamp()
    where singleton;
    return null;
  end if;

  select net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/mercadopago-expire-preferences',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-mercadopago-preference-worker-secret', v_worker_secret
    ),
    body := jsonb_build_object('action', 'process', 'limit', v_runtime.batch_size),
    timeout_milliseconds := 15000
  ) into v_request_id;
  update public.mercadopago_preference_worker_runtime
  set last_request_id = v_request_id,
      last_requested_at = clock_timestamp(),
      last_error = null,
      updated_at = clock_timestamp()
  where singleton;
  return v_request_id;
exception when others then
  update public.mercadopago_preference_worker_runtime
  set last_error = left(sqlerrm, 2000), updated_at = clock_timestamp()
  where singleton;
  return null;
end;
$$;

revoke all on function public.configure_mercadopago_preference_worker(boolean, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.configure_mercadopago_preference_worker(boolean, integer)
  to service_role;
revoke all on function public.invoke_mercadopago_preference_worker()
  from public, anon, authenticated, service_role;
grant execute on function public.invoke_mercadopago_preference_worker()
  to service_role;

do $$
begin
  if to_regclass('cron.job') is null then
    raise notice 'pg_cron unavailable; Mercado Pago preference worker schedule not installed';
    return;
  end if;
  perform cron.unschedule(job.jobid)
  from cron.job job
  where job.jobname = 'vinabike_mercadopago_preference_worker';
  perform cron.schedule(
    'vinabike_mercadopago_preference_worker',
    '* * * * *',
    'select public.invoke_mercadopago_preference_worker();'
  );
exception when others then
  raise notice 'Could not install Mercado Pago preference worker: %', sqlerrm;
end $$;

comment on function public.begin_mercadopago_preference_creation(
  uuid, text, uuid, text, integer
) is 'Service-only begin/replay command. Renews inventory reservation for a new generation and never accepts amount, tenant, reference, or expiry from the browser.';
comment on function public.finalize_mercadopago_preference_creation(
  uuid, uuid, text, text, text, timestamptz, timestamptz
) is 'Commits the provider preference identity after exact recovery/create validation, or queues immediate expiry if the order stopped being payable.';
comment on function public.request_mercadopago_preference_expiration() is
  'Queues every live Checkout Pro preference for closure when its order is cancelled, paid, or refunded.';
comment on function public.claim_mercadopago_preference_expirations(
  text, integer, integer
) is 'Claims tenant-scoped provider preference expiry work with SKIP LOCKED leases.';
comment on table public.mercadopago_preference_worker_runtime is
  'Fail-closed pg_cron to Edge worker gate. It remains disabled until the dedicated Vault/Edge secret exists and an explicit service-role activation succeeds.';

commit;
