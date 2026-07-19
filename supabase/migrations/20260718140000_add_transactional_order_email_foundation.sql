-- Transactional ecommerce email foundation.
--
-- This migration is deliberately delivery-safe:
--   * every tenant defaults to dry-run rendering;
--   * no network request is made from PostgreSQL;
--   * customer messages are derived from immutable online_order_events;
--   * official tax-document email has no automatic producer until a real DTE
--     issuance ledger exists;
--   * all mutation entry points used by Edge Functions are service-role only.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create table if not exists public.transactional_email_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  enabled boolean not null default false,
  delivery_mode text not null default 'dry_run'
    check (delivery_mode in ('dry_run', 'send')),
  from_name text,
  from_email text,
  reply_to_email text,
  public_store_url text,
  created_at timestamp with time zone not null default clock_timestamp(),
  updated_at timestamp with time zone not null default clock_timestamp(),
  constraint transactional_email_settings_send_requires_identity check (
    not (enabled and delivery_mode = 'send')
    or (
      nullif(btrim(from_name), '') is not null
      and nullif(btrim(from_email), '') is not null
      and from_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
  ),
  constraint transactional_email_settings_reply_to_format check (
    reply_to_email is null
    or reply_to_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint transactional_email_settings_store_url_https check (
    public_store_url is null
    or public_store_url ~* '^https://[^[:space:]]+$'
  )
);

drop trigger if exists trg_transactional_email_settings_updated_at
  on public.transactional_email_settings;
create trigger trg_transactional_email_settings_updated_at
  before update on public.transactional_email_settings
  for each row execute function public.set_updated_at();

create table if not exists public.transactional_email_outbox (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null references public.online_orders(id) on delete restrict,
  order_event_id uuid references public.online_order_events(id) on delete restrict,
  source_event_key text not null,
  message_kind text not null check (message_kind in (
    'order_received',
    'payment_confirmed',
    'processing',
    'ready_for_pickup',
    'shipped',
    'delivered',
    'cancelled',
    'refund_completed',
    'payment_voucher_available',
    'tax_document_issued'
  )),
  template_key text not null,
  template_version integer not null default 1 check (template_version > 0),
  locale text not null default 'es-CL',
  recipient_email text not null,
  recipient_name text,
  sender_name text,
  sender_email text,
  reply_to_email text,
  subject text not null,
  render_payload jsonb not null,
  attachment_manifest jsonb not null default '[]'::jsonb,
  idempotency_key text not null,
  delivery_mode text not null default 'dry_run'
    check (delivery_mode in ('dry_run', 'send')),
  state text not null default 'pending' check (state in (
    'pending',
    'leased',
    'rendered',
    'submitted',
    'delivery_delayed',
    'delivered',
    'bounced',
    'complained',
    'failed',
    'dead_letter',
    'suppressed'
  )),
  suppression_reason text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 6 check (max_attempts between 1 and 20),
  available_at timestamp with time zone not null default clock_timestamp(),
  lease_owner text,
  lease_token uuid,
  lease_expires_at timestamp with time zone,
  provider text,
  provider_message_id text,
  last_error_class text,
  last_error_message text,
  rendered_subject text,
  rendered_html_sha256 text,
  rendered_text_sha256 text,
  last_attempt_at timestamp with time zone,
  rendered_at timestamp with time zone,
  submitted_at timestamp with time zone,
  delivered_at timestamp with time zone,
  bounced_at timestamp with time zone,
  complained_at timestamp with time zone,
  failed_at timestamp with time zone,
  created_at timestamp with time zone not null default clock_timestamp(),
  updated_at timestamp with time zone not null default clock_timestamp(),
  constraint transactional_email_outbox_render_payload_object
    check (jsonb_typeof(render_payload) = 'object'),
  constraint transactional_email_outbox_attachment_manifest_array
    check (jsonb_typeof(attachment_manifest) = 'array'),
  constraint transactional_email_outbox_recipient_format check (
    recipient_email = lower(btrim(recipient_email))
    and recipient_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint transactional_email_outbox_sender_format check (
    sender_email is null
    or sender_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint transactional_email_outbox_reply_to_format check (
    reply_to_email is null
    or reply_to_email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint transactional_email_outbox_send_requires_sender check (
    delivery_mode = 'dry_run'
    or (
      nullif(btrim(sender_name), '') is not null
      and nullif(btrim(sender_email), '') is not null
    )
  ),
  constraint transactional_email_outbox_lease_shape check (
    (state = 'leased' and lease_owner is not null and lease_token is not null and lease_expires_at is not null)
    or state <> 'leased'
  ),
  constraint transactional_email_outbox_hash_shapes check (
    (rendered_html_sha256 is null or rendered_html_sha256 ~ '^[0-9a-f]{64}$')
    and (rendered_text_sha256 is null or rendered_text_sha256 ~ '^[0-9a-f]{64}$')
  ),
  unique (idempotency_key),
  unique (tenant_id, source_event_key, template_key, recipient_email)
);

-- Keep the bootstrap snapshot/replay path idempotent when the supported
-- message taxonomy grows before first production deployment.
alter table public.transactional_email_outbox
  drop constraint if exists transactional_email_outbox_message_kind_check;
alter table public.transactional_email_outbox
  add constraint transactional_email_outbox_message_kind_check check (message_kind in (
    'order_received',
    'payment_confirmed',
    'processing',
    'ready_for_pickup',
    'shipped',
    'delivered',
    'cancelled',
    'refund_completed',
    'payment_voucher_available',
    'tax_document_issued'
  ));

create index if not exists idx_transactional_email_outbox_claim
  on public.transactional_email_outbox(delivery_mode, state, available_at, created_at)
  where state in ('pending', 'leased');
create index if not exists idx_transactional_email_outbox_order
  on public.transactional_email_outbox(tenant_id, order_id, created_at desc);
create index if not exists idx_transactional_email_outbox_provider_message
  on public.transactional_email_outbox(provider, provider_message_id)
  where provider_message_id is not null;
create index if not exists idx_transactional_email_outbox_event
  on public.transactional_email_outbox(order_event_id)
  where order_event_id is not null;

create table if not exists public.transactional_email_provider_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete restrict,
  outbox_id uuid references public.transactional_email_outbox(id) on delete restrict,
  provider text not null,
  provider_event_id text not null,
  provider_message_id text,
  event_type text not null check (event_type ~ '^email\.[a-z_]+$'),
  occurred_at timestamp with time zone not null,
  received_at timestamp with time zone not null default clock_timestamp(),
  signature_verified boolean not null check (signature_verified),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  sanitized_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(sanitized_payload) = 'object'),
  unique (provider, provider_event_id)
);

create index if not exists idx_transactional_email_provider_events_message
  on public.transactional_email_provider_events(provider, provider_message_id, occurred_at desc)
  where provider_message_id is not null;
create index if not exists idx_transactional_email_provider_events_outbox
  on public.transactional_email_provider_events(outbox_id, occurred_at desc)
  where outbox_id is not null;

create table if not exists public.transactional_email_suppressions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  normalized_email text not null,
  email_sha256 text not null check (email_sha256 ~ '^[0-9a-f]{64}$'),
  reason text not null check (reason in ('hard_bounce', 'complaint', 'provider_suppressed', 'manual')),
  provider text,
  source_provider_event_id uuid
    references public.transactional_email_provider_events(id) on delete restrict,
  suppressed_at timestamp with time zone not null default clock_timestamp(),
  lifted_at timestamp with time zone,
  lifted_by uuid references auth.users(id) on delete set null,
  lift_reason text,
  constraint transactional_email_suppressions_email_normalized check (
    normalized_email = lower(btrim(normalized_email))
  ),
  constraint transactional_email_suppressions_lift_shape check (
    lifted_at is null
    or nullif(btrim(lift_reason), '') is not null
  )
);

create unique index if not exists uq_transactional_email_active_suppression
  on public.transactional_email_suppressions(tenant_id, email_sha256)
  where lifted_at is null;
create index if not exists idx_transactional_email_suppressions_tenant
  on public.transactional_email_suppressions(tenant_id, suppressed_at desc);

create table if not exists public.online_order_access_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null references public.online_orders(id) on delete restrict,
  token_sha256 text not null check (token_sha256 ~ '^[0-9a-f]{64}$'),
  scopes text[] not null default array['view_order']::text[],
  expires_at timestamp with time zone not null,
  revoked_at timestamp with time zone,
  revoked_reason text,
  last_used_at timestamp with time zone,
  use_count bigint not null default 0 check (use_count >= 0),
  created_at timestamp with time zone not null default clock_timestamp(),
  created_by uuid references auth.users(id) on delete set null,
  constraint online_order_access_tokens_scopes check (
    cardinality(scopes) > 0
    and scopes <@ array['view_order', 'download_documents']::text[]
  ),
  constraint online_order_access_tokens_revoke_shape check (
    revoked_at is null
    or nullif(btrim(revoked_reason), '') is not null
  ),
  unique (token_sha256)
);

create index if not exists idx_online_order_access_tokens_order
  on public.online_order_access_tokens(tenant_id, order_id, created_at desc);
create index if not exists idx_online_order_access_tokens_active
  on public.online_order_access_tokens(token_sha256, expires_at)
  where revoked_at is null;

alter table public.transactional_email_settings enable row level security;
alter table public.transactional_email_outbox enable row level security;
alter table public.transactional_email_provider_events enable row level security;
alter table public.transactional_email_suppressions enable row level security;
alter table public.online_order_access_tokens enable row level security;

drop policy if exists transactional_email_settings_select
  on public.transactional_email_settings;
create policy transactional_email_settings_select
  on public.transactional_email_settings
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists transactional_email_outbox_select
  on public.transactional_email_outbox;
create policy transactional_email_outbox_select
  on public.transactional_email_outbox
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists transactional_email_provider_events_select
  on public.transactional_email_provider_events;
create policy transactional_email_provider_events_select
  on public.transactional_email_provider_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists transactional_email_suppressions_select
  on public.transactional_email_suppressions;
create policy transactional_email_suppressions_select
  on public.transactional_email_suppressions
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.transactional_email_settings from public, anon, authenticated;
revoke all on public.transactional_email_outbox from public, anon, authenticated;
revoke all on public.transactional_email_provider_events from public, anon, authenticated;
revoke all on public.transactional_email_suppressions from public, anon, authenticated;
revoke all on public.online_order_access_tokens from public, anon, authenticated;
grant select on public.transactional_email_settings to authenticated;
grant select on public.transactional_email_outbox to authenticated;
grant select on public.transactional_email_provider_events to authenticated;
grant select on public.transactional_email_suppressions to authenticated;

create or replace function public.prevent_transactional_email_outbox_direct_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Transactional email outbox rows cannot be deleted'
      using errcode = 'check_violation';
  end if;

  if current_setting('app.transactional_email_mutation', true) <> 'true' then
    raise exception 'Transactional email outbox can only be changed by its canonical commands'
      using errcode = 'insufficient_privilege';
  end if;

  new.id := old.id;
  new.tenant_id := old.tenant_id;
  new.order_id := old.order_id;
  new.order_event_id := old.order_event_id;
  new.source_event_key := old.source_event_key;
  new.message_kind := old.message_kind;
  new.template_key := old.template_key;
  new.template_version := old.template_version;
  new.locale := old.locale;
  new.recipient_email := old.recipient_email;
  new.recipient_name := old.recipient_name;
  new.sender_name := old.sender_name;
  new.sender_email := old.sender_email;
  new.reply_to_email := old.reply_to_email;
  new.subject := old.subject;
  new.render_payload := old.render_payload;
  new.attachment_manifest := old.attachment_manifest;
  new.idempotency_key := old.idempotency_key;
  new.delivery_mode := old.delivery_mode;
  new.created_at := old.created_at;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists trg_transactional_email_outbox_guard
  on public.transactional_email_outbox;
create trigger trg_transactional_email_outbox_guard
  before update or delete on public.transactional_email_outbox
  for each row execute function public.prevent_transactional_email_outbox_direct_mutation();

create or replace function public.prevent_transactional_email_provider_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Transactional email provider events are append-only'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_transactional_email_provider_events_immutable
  on public.transactional_email_provider_events;
create trigger trg_transactional_email_provider_events_immutable
  before update or delete on public.transactional_email_provider_events
  for each row execute function public.prevent_transactional_email_provider_event_mutation();

create or replace function public.transactional_email_store_url(
  p_configured_url text,
  p_custom_domain text
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when btrim(coalesce(p_configured_url, '')) ~* '^https://[^[:space:]]+$'
      then rtrim(btrim(p_configured_url), '/')
    when btrim(coalesce(p_custom_domain, '')) ~* '^[a-z0-9.-]+$'
      then 'https://' || lower(btrim(p_custom_domain))
    else null
  end;
$$;

create or replace function public.enqueue_transactional_email_from_order_event_id(
  p_event_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_event public.online_order_events%rowtype;
  v_order public.online_orders%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_message_kind text;
  v_subject text;
  v_recipient text;
  v_source_event_key text;
  v_idempotency_key text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
  v_outbox_id uuid;
begin
  select * into v_event
  from public.online_order_events
  where id = p_event_id;

  if not found or not coalesce(v_event.changed, false) then
    return null;
  end if;

  select * into v_order
  from public.online_orders
  where id = v_event.order_id
    and tenant_id = v_event.tenant_id;

  if not found then
    raise exception 'Online order event % has no matching order', p_event_id;
  end if;

  v_message_kind := case
    when v_event.event_type = 'order_created' then 'order_received'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'paid'
      and v_order.payment_status = 'paid' then 'payment_confirmed'
    when v_event.event_type = 'payment_transition'
      and v_event.to_payment_status = 'refunded'
      and v_order.payment_status = 'refunded'
      and v_order.refunded_at is not null
      and coalesce(v_order.refund_amount, 0) > 0 then 'refund_completed'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'processing'
      and v_order.status = 'processing' then 'processing'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'ready_for_pickup'
      and v_order.status = 'ready_for_pickup' then 'ready_for_pickup'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'shipped'
      and v_order.status = 'shipped' then 'shipped'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'delivered'
      and v_order.status = 'delivered' then 'delivered'
    when v_event.event_type = 'status_transition'
      and v_event.to_status = 'cancelled'
      and v_order.status = 'cancelled' then 'cancelled'
    else null
  end;

  -- There are intentionally no automatic payment_voucher_available or
  -- tax_document_issued branches. A Mercado Pago status is payment evidence,
  -- not by itself an immutable official voucher artifact, and internal
  -- sales_invoices are not Chilean DTE evidence.
  if v_message_kind is null then
    return null;
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;

  select * into v_tenant
  from public.tenants
  where id = v_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = v_order.tenant_id;

  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', item.product_name,
      'sku', item.product_sku,
      'quantity', item.quantity,
      'unitPrice', item.unit_price,
      'subtotal', item.subtotal
    ) order by item.created_at, item.id
  ), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id
    and item.tenant_id = v_order.tenant_id;

  v_subject := case v_message_kind
    when 'order_received' then format('Recibimos tu pedido %s', v_order.order_number)
    when 'payment_confirmed' then format('Pago confirmado · %s', v_order.order_number)
    when 'processing' then format('Estamos preparando tu pedido %s', v_order.order_number)
    when 'ready_for_pickup' then format('Tu pedido %s está listo para retiro', v_order.order_number)
    when 'shipped' then format('Tu pedido %s ya fue enviado', v_order.order_number)
    when 'delivered' then format('Tu pedido %s fue entregado', v_order.order_number)
    when 'cancelled' then format('Actualización de tu pedido %s', v_order.order_number)
    when 'refund_completed' then format('Reembolso completado · %s', v_order.order_number)
  end;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', v_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else null
      end,
      'storeUrl', v_store_url,
      'currency', coalesce(v_tenant.currency, 'CLP'),
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago')
    )),
    'customer', jsonb_build_object('name', v_order.customer_name),
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', v_order.id,
      'number', v_order.order_number,
      'status', v_order.status,
      'paymentStatus', v_order.payment_status,
      'createdAt', v_order.created_at,
      'deliveryType', v_order.delivery_type,
      'subtotal', v_order.subtotal,
      'shippingCost', v_order.shipping_cost,
      'discountAmount', v_order.discount_amount,
      'total', v_order.total,
      'trackingCarrier', v_order.shipping_carrier,
      'trackingNumber', v_order.tracking_number,
      'trackingUrl', case
        when v_order.tracking_url ~* '^https://[^[:space:]]+$' then v_order.tracking_url
        else null
      end,
      'refundedAmount', case
        when v_message_kind = 'refund_completed' then v_order.refund_amount
        else null
      end,
      'refundedAt', case
        when v_message_kind = 'refund_completed' then v_order.refunded_at
        else null
      end
    )),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'order_receipt',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pedido · No constituye documento tributario'
    )
  );

  v_source_event_key := 'online_order_event:' || v_event.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_event.tenant_id::text || ':' || v_event.order_id::text || ':' ||
      v_source_event_key || ':' || v_message_kind || ':' || v_recipient,
      'UTF8'
    ),
    'sha256'
  ), 'hex');

  select suppression.reason into v_suppression_reason
  from public.transactional_email_suppressions suppression
  where suppression.tenant_id = v_event.tenant_id
    and suppression.email_sha256 = encode(
      extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'),
      'hex'
    )
    and suppression.lifted_at is null
  order by suppression.suppressed_at desc
  limit 1;

  if v_suppression_reason is not null then
    v_state := 'suppressed';
  end if;

  insert into public.transactional_email_outbox (
    tenant_id,
    order_id,
    order_event_id,
    source_event_key,
    message_kind,
    template_key,
    template_version,
    recipient_email,
    recipient_name,
    sender_name,
    sender_email,
    reply_to_email,
    subject,
    render_payload,
    idempotency_key,
    delivery_mode,
    state,
    suppression_reason
  ) values (
    v_event.tenant_id,
    v_event.order_id,
    v_event.id,
    v_source_event_key,
    v_message_kind,
    v_message_kind,
    1,
    v_recipient,
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    nullif(lower(btrim(v_settings.from_email)), ''),
    nullif(lower(btrim(v_settings.reply_to_email)), ''),
    v_subject,
    v_payload,
    v_idempotency_key,
    v_delivery_mode,
    v_state,
    v_suppression_reason
  )
  on conflict (idempotency_key) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select id into v_outbox_id
    from public.transactional_email_outbox
    where idempotency_key = v_idempotency_key;
  end if;

  return v_outbox_id;
end;
$$;

create or replace function public.enqueue_transactional_email_from_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_transactional_email_from_order_event_id(new.id);
  return new;
end;
$$;

drop trigger if exists trg_enqueue_transactional_email_from_order_event
  on public.online_order_events;
create trigger trg_enqueue_transactional_email_from_order_event
  after insert on public.online_order_events
  for each row
  when (new.changed)
  execute function public.enqueue_transactional_email_from_order_event();

create or replace function public.claim_transactional_email_outbox(
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
begin
  if nullif(btrim(p_worker_id), '') is null then
    raise exception 'Worker id is required';
  end if;
  if p_delivery_mode not in ('dry_run', 'send') then
    raise exception 'Invalid delivery mode: %', p_delivery_mode;
  end if;
  if p_batch_size not between 1 and 100 then
    raise exception 'Batch size must be between 1 and 100';
  end if;
  if p_lease_seconds not between 15 and 900 then
    raise exception 'Lease seconds must be between 15 and 900';
  end if;

  perform set_config('app.transactional_email_mutation', 'true', true);

  -- Re-check the durable suppression ledger at claim time. This closes the
  -- window where a message was queued before another delivery hard-bounced.
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
  where suppression.tenant_id = outbox.tenant_id
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
      last_error_message = coalesce(last_error_message, 'Maximum delivery attempts exhausted'),
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null
  where state in ('pending', 'leased')
    and attempt_count >= max_attempts
    and (state = 'pending' or lease_expires_at < clock_timestamp());

  return query
  with candidates as (
    select outbox.id
    from public.transactional_email_outbox outbox
    where outbox.delivery_mode = p_delivery_mode
      and outbox.attempt_count < outbox.max_attempts
      and outbox.available_at <= clock_timestamp()
      and (
        outbox.state = 'pending'
        or (outbox.state = 'leased' and outbox.lease_expires_at < clock_timestamp())
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

create or replace function public.complete_transactional_email_attempt(
  p_outbox_id uuid,
  p_worker_id text,
  p_lease_token uuid,
  p_outcome text,
  p_provider text default null,
  p_provider_message_id text default null,
  p_error_class text default null,
  p_error_message text default null,
  p_retry_after_seconds integer default null,
  p_rendered_subject text default null,
  p_rendered_html_sha256 text default null,
  p_rendered_text_sha256 text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_outbox public.transactional_email_outbox%rowtype;
  v_retry_seconds integer;
  v_next_state text;
begin
  if p_outcome not in ('rendered', 'submitted', 'retry', 'permanent_failure', 'suppressed') then
    raise exception 'Invalid attempt outcome: %', p_outcome;
  end if;

  select * into v_outbox
  from public.transactional_email_outbox
  where id = p_outbox_id
  for update;

  if not found then
    raise exception 'Transactional email outbox row not found: %', p_outbox_id;
  end if;

  if p_rendered_html_sha256 is not null
     and p_rendered_html_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid rendered HTML SHA-256';
  end if;
  if p_rendered_text_sha256 is not null
     and p_rendered_text_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid rendered text SHA-256';
  end if;

  -- A signed provider webhook may win the race against the worker's database
  -- acknowledgement. Treat the exact same provider acknowledgement as an
  -- idempotent completion replay instead of rejecting the now-cleared lease.
  if p_outcome = 'submitted'
     and v_outbox.state in (
       'submitted',
       'delivery_delayed',
       'delivered',
       'bounced',
       'complained',
       'failed',
       'suppressed'
     )
     and v_outbox.provider = lower(btrim(p_provider))
     and v_outbox.provider_message_id = btrim(p_provider_message_id) then
    perform set_config('app.transactional_email_mutation', 'true', true);
    update public.transactional_email_outbox
    set rendered_subject = coalesce(nullif(p_rendered_subject, ''), rendered_subject),
        rendered_html_sha256 = coalesce(p_rendered_html_sha256, rendered_html_sha256),
        rendered_text_sha256 = coalesce(p_rendered_text_sha256, rendered_text_sha256),
        rendered_at = coalesce(rendered_at, clock_timestamp()),
        submitted_at = coalesce(submitted_at, clock_timestamp())
    where id = p_outbox_id;

    return jsonb_build_object(
      'outbox_id', p_outbox_id,
      'state', v_outbox.state,
      'attempt_count', v_outbox.attempt_count,
      'retry_after_seconds', null,
      'replay', true
    );
  end if;

  if v_outbox.state <> 'leased'
     or v_outbox.lease_owner is distinct from btrim(p_worker_id)
     or v_outbox.lease_token is distinct from p_lease_token then
    raise exception 'Transactional email lease is stale or belongs to another worker'
      using errcode = 'serialization_failure';
  end if;

  if p_outcome = 'submitted'
     and (nullif(btrim(p_provider), '') is null
          or nullif(btrim(p_provider_message_id), '') is null) then
    raise exception 'Submitted email requires provider and provider message id';
  end if;

  v_retry_seconds := greatest(
    5,
    least(
      86400,
      coalesce(
        p_retry_after_seconds,
        least(3600, (15 * power(2, greatest(v_outbox.attempt_count - 1, 0)))::integer)
      )
    )
  );

  v_next_state := case p_outcome
    when 'rendered' then 'rendered'
    when 'submitted' then 'submitted'
    when 'retry' then case
      when v_outbox.attempt_count >= v_outbox.max_attempts then 'dead_letter'
      else 'pending'
    end
    when 'permanent_failure' then 'failed'
    when 'suppressed' then 'suppressed'
  end;

  perform set_config('app.transactional_email_mutation', 'true', true);

  update public.transactional_email_outbox
  set state = v_next_state,
      provider = case when p_outcome = 'submitted' then btrim(p_provider) else provider end,
      provider_message_id = case
        when p_outcome = 'submitted' then btrim(p_provider_message_id)
        else provider_message_id
      end,
      last_error_class = nullif(btrim(p_error_class), ''),
      last_error_message = left(nullif(btrim(p_error_message), ''), 2000),
      rendered_subject = coalesce(nullif(p_rendered_subject, ''), rendered_subject),
      rendered_html_sha256 = coalesce(p_rendered_html_sha256, rendered_html_sha256),
      rendered_text_sha256 = coalesce(p_rendered_text_sha256, rendered_text_sha256),
      rendered_at = case
        when p_outcome in ('rendered', 'submitted') then coalesce(rendered_at, clock_timestamp())
        else rendered_at
      end,
      submitted_at = case
        when p_outcome = 'submitted' then coalesce(submitted_at, clock_timestamp())
        else submitted_at
      end,
      failed_at = case
        when v_next_state in ('failed', 'dead_letter') then coalesce(failed_at, clock_timestamp())
        else failed_at
      end,
      available_at = case
        when v_next_state = 'pending' then clock_timestamp() + make_interval(secs => v_retry_seconds)
        else available_at
      end,
      suppression_reason = case
        when p_outcome = 'suppressed' then coalesce(nullif(btrim(p_error_class), ''), 'suppressed')
        else suppression_reason
      end,
      lease_owner = null,
      lease_token = null,
      lease_expires_at = null
  where id = p_outbox_id;

  return jsonb_build_object(
    'outbox_id', p_outbox_id,
    'state', v_next_state,
    'attempt_count', v_outbox.attempt_count,
    'retry_after_seconds', case when v_next_state = 'pending' then v_retry_seconds else null end
  );
end;
$$;

create or replace function public.record_transactional_email_provider_event(
  p_provider text,
  p_provider_event_id text,
  p_provider_message_id text,
  p_outbox_id_hint uuid,
  p_event_type text,
  p_occurred_at timestamp with time zone,
  p_payload_sha256 text,
  p_sanitized_payload jsonb default '{}'::jsonb,
  p_is_permanent boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_existing public.transactional_email_provider_events%rowtype;
  v_outbox public.transactional_email_outbox%rowtype;
  v_event_id uuid;
  v_target_state text;
  v_should_update boolean := false;
  v_suppression_reason text;
begin
  if nullif(btrim(p_provider), '') is null
     or nullif(btrim(p_provider_event_id), '') is null
     or p_event_type !~ '^email\.[a-z_]+$'
     or p_payload_sha256 !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(coalesce(p_sanitized_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'Invalid transactional email provider event';
  end if;

  select * into v_existing
  from public.transactional_email_provider_events
  where provider = lower(btrim(p_provider))
    and provider_event_id = btrim(p_provider_event_id);

  if found then
    if v_existing.payload_sha256 <> p_payload_sha256
       or v_existing.event_type <> p_event_type
       or v_existing.provider_message_id is distinct from nullif(
         btrim(p_provider_message_id),
         ''
       ) then
      raise exception
        'Transactional email provider event id conflicts with different evidence'
        using errcode = '23000';
    end if;
    return jsonb_build_object(
      'provider_event_id', v_existing.id,
      'outbox_id', v_existing.outbox_id,
      'replay', true
    );
  end if;

  if p_outbox_id_hint is not null then
    select * into v_outbox
    from public.transactional_email_outbox
    where id = p_outbox_id_hint
    for update;

    -- The UUID tag is only a hint. Once an outbox row has provider identity,
    -- a conflicting signed event must not be allowed to mutate that row.
    if found
       and nullif(btrim(p_provider_message_id), '') is not null
       and v_outbox.provider_message_id is not null
       and (
         v_outbox.provider is distinct from lower(btrim(p_provider))
         or v_outbox.provider_message_id is distinct from btrim(p_provider_message_id)
       ) then
      v_outbox := null;
    end if;
  end if;

  if v_outbox.id is null and nullif(btrim(p_provider_message_id), '') is not null then
    select * into v_outbox
    from public.transactional_email_outbox
    where provider = lower(btrim(p_provider))
      and provider_message_id = btrim(p_provider_message_id)
    order by created_at desc
    limit 1
    for update;
  end if;

  insert into public.transactional_email_provider_events (
    tenant_id,
    outbox_id,
    provider,
    provider_event_id,
    provider_message_id,
    event_type,
    occurred_at,
    signature_verified,
    payload_sha256,
    sanitized_payload
  ) values (
    v_outbox.tenant_id,
    v_outbox.id,
    lower(btrim(p_provider)),
    btrim(p_provider_event_id),
    nullif(btrim(p_provider_message_id), ''),
    p_event_type,
    coalesce(p_occurred_at, clock_timestamp()),
    true,
    p_payload_sha256,
    coalesce(p_sanitized_payload, '{}'::jsonb)
  )
  returning id into v_event_id;

  if v_outbox.id is null then
    return jsonb_build_object(
      'provider_event_id', v_event_id,
      'outbox_id', null,
      'replay', false,
      'matched', false
    );
  end if;

  v_target_state := case p_event_type
    when 'email.sent' then 'submitted'
    when 'email.delivery_delayed' then 'delivery_delayed'
    when 'email.delivered' then 'delivered'
    when 'email.bounced' then 'bounced'
    when 'email.complained' then 'complained'
    when 'email.failed' then 'failed'
    when 'email.suppressed' then 'suppressed'
    else null
  end;

  v_should_update := case
    when v_target_state is null then false
    when v_target_state in ('bounced', 'complained', 'suppressed') then true
    when v_target_state = 'failed'
      then v_outbox.state not in ('delivered', 'bounced', 'complained', 'suppressed', 'dead_letter')
    when v_target_state = 'delivered'
      then v_outbox.state not in ('bounced', 'complained', 'suppressed', 'dead_letter')
    when v_target_state = 'delivery_delayed'
      then v_outbox.state in ('submitted', 'delivery_delayed')
    when v_target_state = 'submitted'
      then v_outbox.state in ('leased', 'submitted')
    else false
  end;

  if v_should_update
     or (
       v_outbox.id is not null
       and nullif(btrim(p_provider_message_id), '') is not null
       and v_outbox.provider_message_id is null
     ) then
    perform set_config('app.transactional_email_mutation', 'true', true);
    update public.transactional_email_outbox
    set state = case when v_should_update then v_target_state else state end,
        provider = case
          when nullif(btrim(p_provider_message_id), '') is not null
            then coalesce(provider, lower(btrim(p_provider)))
          else provider
        end,
        provider_message_id = case
          when nullif(btrim(p_provider_message_id), '') is not null
            then coalesce(provider_message_id, btrim(p_provider_message_id))
          else provider_message_id
        end,
        delivered_at = case
          when v_target_state = 'delivered' then coalesce(delivered_at, p_occurred_at, clock_timestamp())
          else delivered_at
        end,
        submitted_at = case
          when v_target_state = 'submitted'
            then coalesce(submitted_at, p_occurred_at, clock_timestamp())
          else submitted_at
        end,
        bounced_at = case
          when v_target_state = 'bounced' then coalesce(bounced_at, p_occurred_at, clock_timestamp())
          else bounced_at
        end,
        complained_at = case
          when v_target_state = 'complained' then coalesce(complained_at, p_occurred_at, clock_timestamp())
          else complained_at
        end,
        failed_at = case
          when v_target_state in ('failed', 'suppressed') then coalesce(failed_at, p_occurred_at, clock_timestamp())
          else failed_at
        end,
        last_error_class = case
          when v_target_state in ('bounced', 'complained', 'failed', 'suppressed') then p_event_type
          else last_error_class
        end,
        last_error_message = case
          when v_target_state in ('bounced', 'complained', 'failed', 'suppressed')
            then left(coalesce(p_sanitized_payload->>'reason', p_event_type), 2000)
          else last_error_message
        end,
        suppression_reason = case
          when v_target_state in ('complained', 'suppressed')
            or (v_target_state = 'bounced' and p_is_permanent)
            then case
              when v_target_state = 'complained' then 'complaint'
              when v_target_state = 'suppressed' then 'provider_suppressed'
              else 'hard_bounce'
            end
          else suppression_reason
        end,
        lease_owner = case when v_should_update then null else lease_owner end,
        lease_token = case when v_should_update then null else lease_token end,
        lease_expires_at = case when v_should_update then null else lease_expires_at end
    where id = v_outbox.id;
  end if;

  if v_target_state in ('complained', 'suppressed')
     or (v_target_state = 'bounced' and p_is_permanent) then
    v_suppression_reason := case
      when v_target_state = 'complained' then 'complaint'
      when v_target_state = 'suppressed' then 'provider_suppressed'
      else 'hard_bounce'
    end;

    insert into public.transactional_email_suppressions (
      tenant_id,
      normalized_email,
      email_sha256,
      reason,
      provider,
      source_provider_event_id
    ) values (
      v_outbox.tenant_id,
      v_outbox.recipient_email,
      encode(extensions.digest(convert_to(v_outbox.recipient_email, 'UTF8'), 'sha256'), 'hex'),
      v_suppression_reason,
      lower(btrim(p_provider)),
      v_event_id
    )
    on conflict (tenant_id, email_sha256) where lifted_at is null
    do update set
      reason = excluded.reason,
      provider = excluded.provider,
      source_provider_event_id = excluded.source_provider_event_id,
      suppressed_at = excluded.suppressed_at;

    -- A new hard-bounce/complaint suppression also covers messages that were
    -- queued before the provider event arrived. Active leases may already be
    -- in flight, so only pending or expired leases are changed here.
    perform set_config('app.transactional_email_mutation', 'true', true);
    update public.transactional_email_outbox pending
    set state = 'suppressed',
        suppression_reason = v_suppression_reason,
        last_error_class = coalesce(pending.last_error_class, p_event_type),
        last_error_message = coalesce(
          pending.last_error_message,
          left(coalesce(p_sanitized_payload->>'reason', p_event_type), 2000)
        ),
        lease_owner = null,
        lease_token = null,
        lease_expires_at = null
    where pending.tenant_id = v_outbox.tenant_id
      and pending.recipient_email = v_outbox.recipient_email
      and (
        pending.state = 'pending'
        or (
          pending.state = 'leased'
          and pending.lease_expires_at < clock_timestamp()
        )
      );
  end if;

  return jsonb_build_object(
    'provider_event_id', v_event_id,
    'outbox_id', v_outbox.id,
    'state', case when v_should_update then v_target_state else v_outbox.state end,
    'replay', false,
    'matched', true
  );
end;
$$;

create or replace function public.issue_online_order_access_token(
  p_order_id uuid,
  p_scopes text[] default array['view_order']::text[],
  p_expires_at timestamp with time zone default (clock_timestamp() + interval '30 days')
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.online_orders%rowtype;
  v_raw_token text;
  v_token_id uuid;
begin
  if cardinality(p_scopes) = 0
     or not (p_scopes <@ array['view_order', 'download_documents']::text[]) then
    raise exception 'Invalid online order access-token scopes';
  end if;
  if p_expires_at <= clock_timestamp()
     or p_expires_at > clock_timestamp() + interval '90 days' then
    raise exception 'Access-token expiry must be within the next 90 days';
  end if;

  select * into v_order
  from public.online_orders
  where id = p_order_id;
  if not found then
    raise exception 'Online order not found: %', p_order_id;
  end if;

  v_raw_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');

  insert into public.online_order_access_tokens (
    tenant_id,
    order_id,
    token_sha256,
    scopes,
    expires_at,
    created_by
  ) values (
    v_order.tenant_id,
    v_order.id,
    encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex'),
    p_scopes,
    p_expires_at,
    auth.uid()
  )
  returning id into v_token_id;

  return jsonb_build_object(
    'token_id', v_token_id,
    'token', v_raw_token,
    'order_id', v_order.id,
    'tenant_id', v_order.tenant_id,
    'scopes', p_scopes,
    'expires_at', p_expires_at
  );
end;
$$;

create or replace function public.revoke_online_order_access_token(
  p_token_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Revocation reason is required';
  end if;

  update public.online_order_access_tokens
  set revoked_at = coalesce(revoked_at, clock_timestamp()),
      revoked_reason = coalesce(revoked_reason, btrim(p_reason))
  where id = p_token_id;

  return found;
end;
$$;

create or replace function public.get_public_online_order_by_access_token(
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_access public.online_order_access_tokens%rowtype;
  v_order public.online_orders%rowtype;
  v_items jsonb;
begin
  if length(coalesce(p_token, '')) < 40 or length(p_token) > 128 then
    return null;
  end if;

  select * into v_access
  from public.online_order_access_tokens
  where token_sha256 = encode(
    extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > clock_timestamp()
    and scopes @> array['view_order']::text[]
  for update;

  if not found then
    return null;
  end if;

  select * into v_order
  from public.online_orders
  where id = v_access.order_id
    and tenant_id = v_access.tenant_id;

  if not found then
    return null;
  end if;

  update public.online_order_access_tokens
  set last_used_at = clock_timestamp(),
      use_count = use_count + 1
  where id = v_access.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal
  ) order by item.created_at, item.id), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id
    and item.tenant_id = v_order.tenant_id;

  -- Explicit projection: no email, phone, address, payment reference, customer
  -- notes, internal notes, generic notes, or raw provider payloads.
  return jsonb_build_object(
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', v_order.id,
      'number', v_order.order_number,
      'status', v_order.status,
      'paymentStatus', v_order.payment_status,
      'deliveryType', v_order.delivery_type,
      'createdAt', v_order.created_at,
      'readyForPickupAt', v_order.ready_for_pickup_at,
      'shippedAt', v_order.shipped_at,
      'deliveredAt', v_order.delivered_at,
      'cancelledAt', v_order.cancelled_at,
      'trackingCarrier', v_order.shipping_carrier,
      'trackingNumber', v_order.tracking_number,
      'trackingUrl', case
        when v_order.tracking_url ~* '^https://[^[:space:]]+$' then v_order.tracking_url
        else null
      end,
      'subtotal', v_order.subtotal,
      'shippingCost', v_order.shipping_cost,
      'discountAmount', v_order.discount_amount,
      'total', v_order.total
    )),
    'items', v_items,
    'access', jsonb_build_object(
      'scopes', v_access.scopes,
      'expiresAt', v_access.expires_at
    )
  );
end;
$$;

revoke all on function public.enqueue_transactional_email_from_order_event_id(uuid)
  from public, anon, authenticated;
revoke all on function public.claim_transactional_email_outbox(text, text, integer, integer)
  from public, anon, authenticated;
revoke all on function public.complete_transactional_email_attempt(
  uuid, text, uuid, text, text, text, text, text, integer, text, text, text
) from public, anon, authenticated;
revoke all on function public.record_transactional_email_provider_event(
  text, text, text, uuid, text, timestamp with time zone, text, jsonb, boolean
) from public, anon, authenticated;
revoke all on function public.issue_online_order_access_token(
  uuid, text[], timestamp with time zone
) from public, anon, authenticated;
revoke all on function public.revoke_online_order_access_token(uuid, text)
  from public, anon, authenticated;
revoke all on function public.get_public_online_order_by_access_token(text)
  from public, anon, authenticated;

grant execute on function public.enqueue_transactional_email_from_order_event_id(uuid)
  to service_role;
grant execute on function public.claim_transactional_email_outbox(text, text, integer, integer)
  to service_role;
grant execute on function public.complete_transactional_email_attempt(
  uuid, text, uuid, text, text, text, text, text, integer, text, text, text
) to service_role;
grant execute on function public.record_transactional_email_provider_event(
  text, text, text, uuid, text, timestamp with time zone, text, jsonb, boolean
) to service_role;
grant execute on function public.issue_online_order_access_token(
  uuid, text[], timestamp with time zone
) to service_role;
grant execute on function public.revoke_online_order_access_token(uuid, text)
  to service_role;
grant execute on function public.get_public_online_order_by_access_token(text)
  to anon, authenticated, service_role;

comment on table public.transactional_email_outbox is
  'Durable tenant-scoped transactional email outbox. Payload and identity columns are immutable after enqueue.';
comment on table public.transactional_email_provider_events is
  'Append-only signed provider delivery evidence. Duplicate webhook deliveries are keyed by provider_event_id.';
comment on table public.online_order_access_tokens is
  'Hashed, expiring, revocable guest access tokens. Raw token values are returned once and never stored.';
comment on function public.get_public_online_order_by_access_token(text) is
  'Returns an explicit redacted order projection; it never exposes the underlying online_orders row.';

commit;
