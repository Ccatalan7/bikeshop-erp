-- Deployment status: NOT DEPLOYED
--
-- Online-order corrections are an explicit saga. An external refund is never
-- claimed by a database transaction: provider/manual evidence is committed
-- first, then the existing return, credit-note and customer-refund kernels are
-- applied atomically and replay-safely in a second transaction.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Older deployed schemas kept the scaffold's global order-number constraint.
-- Sequence allocation is tenant-local, so that constraint makes a second
-- tenant collide on WEB-YY-00001. Audit before replacing it; never discard or
-- silently rename historical orders.
do $$
begin
  if exists (
    select 1
    from public.online_orders orders
    group by orders.tenant_id, orders.order_number
    having count(*) > 1
  ) then
    raise exception 'Cannot scope online order numbers: duplicate tenant/order_number pairs exist'
      using errcode = '23505';
  end if;
  alter table public.online_orders
    drop constraint if exists online_orders_order_number_key;
end;
$$;

create unique index if not exists uq_online_orders_tenant_order_number
  on public.online_orders(tenant_id, order_number);

-- Some deployed schemas predate the composite payment-method key even though
-- id is already globally unique. Add the tenant form required by every new
-- tenant-scoped foreign key without rewriting any row.
create unique index if not exists uq_payment_methods_tenant_id_id
  on public.payment_methods(tenant_id, id);

create table if not exists public.online_order_corrections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  order_id uuid not null,
  sales_invoice_id uuid not null,
  operation_key text not null,
  expected_order_version bigint not null check (expected_order_version >= 0),
  request_lines jsonb not null,
  reason text not null,
  requested_amount numeric(12,2) not null
    check (requested_amount > 0 and requested_amount = trunc(requested_amount)),
  currency text not null default 'CLP' check (currency = 'CLP'),
  payment_method_id uuid not null,
  provider text not null check (provider in ('mercadopago', 'manual')),
  correction_intent text not null default 'return'
    constraint online_order_corrections_intent_check check (
    correction_intent in ('return', 'cancel_before_fulfillment')
  ),
  provider_payment_id text,
  provider_idempotency_key text not null,
  provider_state text not null default 'pending' check (
    provider_state in ('pending', 'succeeded', 'failed', 'unknown')
  ),
  processing_state text not null default 'provider_pending' check (
    processing_state in (
      'provider_pending', 'ready_to_apply', 'applied', 'action_required', 'rejected'
    )
  ),
  provider_refund_id text,
  provider_refund_status text,
  provider_refund_amount numeric(12,2),
  provider_refunded_at timestamptz,
  provider_evidence jsonb,
  sales_return_id uuid references public.sales_returns(id) on delete restrict,
  sales_credit_note_id uuid references public.sales_credit_notes(id) on delete restrict,
  sales_customer_refund_id uuid references public.sales_customer_refunds(id) on delete restrict,
  last_error_code text,
  last_error_message text,
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default clock_timestamp(),
  applied_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  version bigint not null default 0,
  unique (tenant_id, id),
  unique (tenant_id, operation_key),
  unique (tenant_id, provider_idempotency_key),
  constraint online_order_corrections_order_tenant_fkey
    foreign key (tenant_id, order_id)
    references public.online_orders(tenant_id, id) on delete restrict,
  constraint online_order_corrections_invoice_tenant_fkey
    foreign key (tenant_id, sales_invoice_id)
    references public.sales_invoices(tenant_id, id) on delete restrict,
  constraint online_order_corrections_payment_method_tenant_fkey
    foreign key (tenant_id, payment_method_id)
    references public.payment_methods(tenant_id, id) on delete restrict,
  check (jsonb_typeof(request_lines) = 'array' and jsonb_array_length(request_lines) > 0),
  check (length(btrim(operation_key)) between 8 and 180),
  check (length(btrim(provider_idempotency_key)) between 8 and 180),
  check (length(btrim(reason)) between 4 and 500),
  check (provider <> 'mercadopago' or nullif(btrim(provider_payment_id), '') is not null),
  check (
    (provider_state = 'succeeded'
      and provider_refund_id is not null
      and provider_refund_amount = requested_amount
      and provider_refunded_at is not null
      and provider_evidence is not null)
    or provider_state <> 'succeeded'
  ),
  check (
    (processing_state = 'applied'
      and sales_credit_note_id is not null
      and sales_customer_refund_id is not null
      and applied_at is not null)
    or processing_state <> 'applied'
  )
);

alter table public.online_order_corrections
  add column if not exists correction_intent text not null default 'return';
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.online_order_corrections'::regclass
      and conname = 'online_order_corrections_intent_check'
  ) then
    alter table public.online_order_corrections
      add constraint online_order_corrections_intent_check check (
        correction_intent in ('return', 'cancel_before_fulfillment')
      );
  end if;
end;
$$;

create index if not exists idx_online_order_corrections_order
  on public.online_order_corrections(tenant_id, order_id, requested_at desc, id desc);
create index if not exists idx_online_order_corrections_attention
  on public.online_order_corrections(tenant_id, processing_state, updated_at desc)
  where processing_state in ('provider_pending', 'ready_to_apply', 'action_required');
create unique index if not exists uq_online_order_corrections_mp_refund_evidence
  on public.online_order_corrections(provider_refund_id)
  where provider = 'mercadopago' and provider_state = 'succeeded'
    and provider_refund_id is not null;
create unique index if not exists uq_online_order_corrections_manual_refund_evidence
  on public.online_order_corrections(tenant_id, provider_refund_id)
  where provider = 'manual' and provider_state = 'succeeded'
    and provider_refund_id is not null;

create table if not exists public.online_order_correction_events (
  id bigint generated by default as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  correction_id uuid not null,
  order_id uuid not null,
  event_type text not null check (event_type in (
    'requested', 'provider_succeeded', 'provider_failed', 'provider_unknown',
    'apply_succeeded', 'apply_failed'
  )),
  actor_id uuid references auth.users(id) on delete set null,
  request_id text not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, correction_id, request_id),
  constraint online_order_correction_events_correction_tenant_fkey
    foreign key (tenant_id, correction_id)
    references public.online_order_corrections(tenant_id, id) on delete restrict,
  constraint online_order_correction_events_order_tenant_fkey
    foreign key (tenant_id, order_id)
    references public.online_orders(tenant_id, id) on delete restrict,
  check (jsonb_typeof(payload) = 'object'),
  check (length(btrim(request_id)) between 8 and 220)
);

create index if not exists idx_online_order_correction_events_order
  on public.online_order_correction_events(
    tenant_id, order_id, occurred_at desc, id desc
  );

alter table public.online_order_corrections enable row level security;
alter table public.online_order_correction_events enable row level security;

drop policy if exists online_order_corrections_staff_read
  on public.online_order_corrections;
create policy online_order_corrections_staff_read
  on public.online_order_corrections for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1 from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = online_order_corrections.tenant_id
        and profile.is_active is true
        and (
          profile.role in ('admin', 'manager', 'accountant', 'cashier')
          or coalesce(profile.permissions->'access_accounting', 'false'::jsonb)
               = 'true'::jsonb
        )
    )
  );

drop policy if exists online_order_correction_events_staff_read
  on public.online_order_correction_events;
create policy online_order_correction_events_staff_read
  on public.online_order_correction_events for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1 from public.user_profiles profile
      where profile.user_id = auth.uid()
        and profile.tenant_id = online_order_correction_events.tenant_id
        and profile.is_active is true
        and (
          profile.role in ('admin', 'manager', 'accountant', 'cashier')
          or coalesce(profile.permissions->'access_accounting', 'false'::jsonb)
               = 'true'::jsonb
        )
    )
  );

revoke all on public.online_order_corrections,
  public.online_order_correction_events from public, anon, authenticated, service_role;
grant select on public.online_order_corrections,
  public.online_order_correction_events to authenticated;

create or replace function public.online_order_correction_actor_allowed(
  p_tenant_id uuid
) returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.user_profiles profile
    where profile.user_id = auth.uid()
      and profile.tenant_id = p_tenant_id
      and profile.is_active is true
      and (
        profile.role in ('admin', 'manager', 'accountant')
        or coalesce(profile.permissions->'access_accounting', 'false'::jsonb)
             = 'true'::jsonb
      )
  );
$$;

revoke all on function public.online_order_correction_actor_allowed(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.prevent_online_order_correction_direct_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('app.online_order_correction_write', true) <> 'true' then
    raise exception 'Online order corrections are command-owned records'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Online order corrections cannot be deleted'
      using errcode = 'check_violation';
  end if;
  if new.tenant_id is distinct from old.tenant_id
     or new.order_id is distinct from old.order_id
     or new.sales_invoice_id is distinct from old.sales_invoice_id
     or new.operation_key is distinct from old.operation_key
     or new.expected_order_version is distinct from old.expected_order_version
     or new.request_lines is distinct from old.request_lines
     or new.reason is distinct from old.reason
     or new.requested_amount is distinct from old.requested_amount
     or new.currency is distinct from old.currency
     or new.payment_method_id is distinct from old.payment_method_id
     or new.provider is distinct from old.provider
     or new.correction_intent is distinct from old.correction_intent
     or new.provider_payment_id is distinct from old.provider_payment_id
     or new.provider_idempotency_key is distinct from old.provider_idempotency_key
     or new.requested_by is distinct from old.requested_by
     or new.requested_at is distinct from old.requested_at then
    raise exception 'Online order correction request snapshots are immutable'
      using errcode = 'check_violation';
  end if;
  new.version := old.version + 1;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists trg_online_order_corrections_command_owned
  on public.online_order_corrections;
create trigger trg_online_order_corrections_command_owned
  before update or delete on public.online_order_corrections
  for each row execute function public.prevent_online_order_correction_direct_mutation();

create or replace function public.prevent_online_order_correction_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Online order correction events are append-only'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_online_order_correction_events_immutable
  on public.online_order_correction_events;
create trigger trg_online_order_correction_events_immutable
  before update or delete on public.online_order_correction_events
  for each row execute function public.prevent_online_order_correction_event_mutation();

create or replace function public.append_online_order_correction_event(
  p_correction public.online_order_corrections,
  p_event_type text,
  p_request_id text,
  p_actor_id uuid,
  p_payload jsonb
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_id bigint;
begin
  insert into public.online_order_correction_events(
    tenant_id, correction_id, order_id, event_type, actor_id, request_id, payload
  ) values (
    p_correction.tenant_id, p_correction.id, p_correction.order_id,
    p_event_type, p_actor_id, p_request_id, coalesce(p_payload, '{}'::jsonb)
  ) on conflict (tenant_id, correction_id, request_id) do nothing
  returning id into v_id;
  if v_id is null then
    select event.id into v_id
    from public.online_order_correction_events event
    where event.tenant_id = p_correction.tenant_id
      and event.correction_id = p_correction.id
      and event.request_id = p_request_id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.append_online_order_correction_event(
  public.online_order_corrections, text, text, uuid, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.get_online_order_correction_preview(
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
  v_order public.online_orders%rowtype;
  v_lines jsonb;
  v_return_mode text;
  v_credit_mode text;
  v_refund_mode text;
begin
  select * into v_order from public.online_orders orders
  where orders.id = p_order_id and orders.tenant_id = v_tenant;
  if not found or not public.online_order_correction_actor_allowed(v_tenant) then
    raise exception 'Online order not found or access denied' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'line_index', balance.source_line_index,
    'product_id', balance.product_id,
    'product_name', balance.product_name,
    'product_sku', balance.product_sku,
    'remaining_quantity', balance.remaining_quantity,
    'remaining_net', balance.remaining_net,
    'remaining_tax', balance.remaining_tax,
    'remaining_total', balance.remaining_net + balance.remaining_tax,
    'is_service', coalesce((balance.line_snapshot->>'is_service')::boolean, false)
      or balance.product_id is null,
    'physical_return_allowed', balance.product_id is not null
      and not coalesce((balance.line_snapshot->>'is_service')::boolean, false)
  ) order by balance.source_line_index), '[]'::jsonb)
  into v_lines
  from public.sales_credit_note_line_balance_view balance
  where balance.tenant_id = v_tenant
    and balance.sales_invoice_id = v_order.sales_invoice_id
    and balance.remaining_quantity > 0
    and balance.remaining_net + balance.remaining_tax > 0;

  select coalesce(control_mode, 'disabled') into v_return_mode
  from public.sales_return_control_settings where tenant_id = v_tenant;
  if not found then v_return_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_credit_mode
  from public.sales_credit_note_control_settings where tenant_id = v_tenant;
  if not found then v_credit_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_refund_mode
  from public.sales_customer_refund_control_settings where tenant_id = v_tenant;
  if not found then v_refund_mode := 'disabled'; end if;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'order_version', v_order.version,
    'payment_status', v_order.payment_status,
    'payment_method', v_order.payment_method,
    'sales_invoice_id', v_order.sales_invoice_id,
    'lines', v_lines,
    'controls_ready', v_return_mode = 'enforce'
      and v_credit_mode = 'enforce' and v_refund_mode = 'enforce',
    'control_modes', jsonb_build_object(
      'sales_return', v_return_mode,
      'sales_credit_note', v_credit_mode,
      'sales_customer_refund', v_refund_mode
    )
  );
end;
$$;

revoke all on function public.get_online_order_correction_preview(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_online_order_correction_preview(uuid)
  to authenticated;

drop function if exists public.request_online_order_correction(
  uuid, bigint, jsonb, text, text
);
create or replace function public.request_online_order_correction(
  p_order_id uuid,
  p_expected_order_version bigint,
  p_lines jsonb,
  p_reason text,
  p_operation_key text,
  p_correction_intent text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
  v_actor uuid := auth.uid();
  v_order public.online_orders%rowtype;
  v_existing public.online_order_corrections%rowtype;
  v_correction public.online_order_corrections%rowtype;
  v_request jsonb;
  v_balance record;
  v_index integer;
  v_quantity integer;
  v_disposition text;
  v_net numeric;
  v_tax numeric;
  v_total numeric := 0;
  v_lines jsonb;
  v_replay_lines jsonb;
  v_existing_replay_lines jsonb;
  v_provider text;
  v_payment_method_id uuid;
  v_intent text := lower(btrim(coalesce(p_correction_intent, 'return')));
  v_prior_refund numeric;
  v_return_mode text;
  v_credit_mode text;
  v_refund_mode text;
  v_invoice public.sales_invoices%rowtype;
begin
  if v_actor is null or v_tenant is null
     or not public.online_order_correction_actor_allowed(v_tenant) then
    raise exception 'Online order not found or access denied' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_operation_key, '')), '') is null
     or length(btrim(p_operation_key)) not between 8 and 180
     or nullif(btrim(coalesce(p_reason, '')), '') is null
     or length(btrim(p_reason)) not between 4 and 500
     or v_intent not in ('return', 'cancel_before_fulfillment')
     or p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) = 0 then
    raise exception 'A valid operation key, reason and correction lines are required'
      using errcode = '22023';
  end if;

  select * into v_existing from public.online_order_corrections correction
  where correction.tenant_id = v_tenant
    and correction.operation_key = btrim(p_operation_key);
  if found then
    select coalesce(jsonb_agg(jsonb_build_object(
      'line_index', (line->>'line_index')::integer,
      'quantity', (line->>'quantity')::integer,
      'disposition', lower(btrim(coalesce(line->>'disposition', '')))
    ) order by (line->>'line_index')::integer), '[]'::jsonb)
    into v_replay_lines
    from jsonb_array_elements(p_lines) line;
    select coalesce(jsonb_agg(jsonb_build_object(
      'line_index', (line->>'line_index')::integer,
      'quantity', (line->>'credited_quantity')::integer,
      'disposition', line->>'disposition'
    ) order by (line->>'line_index')::integer), '[]'::jsonb)
    into v_existing_replay_lines
    from jsonb_array_elements(v_existing.request_lines) line;
    if v_existing.order_id is distinct from p_order_id
       or v_existing.expected_order_version is distinct from p_expected_order_version
       or v_existing.correction_intent is distinct from v_intent
       or v_existing.reason is distinct from btrim(p_reason)
       or v_existing_replay_lines is distinct from v_replay_lines then
      raise exception 'Correction operation key was reused with different immutable inputs'
        using errcode = '23000';
    end if;
    return to_jsonb(v_existing) || jsonb_build_object('replay', true);
  end if;

  select * into v_order from public.online_orders orders
  where orders.id = p_order_id and orders.tenant_id = v_tenant for update;
  if not found then raise exception 'Online order not found' using errcode = '23503'; end if;
  if v_order.version <> p_expected_order_version then
    raise exception 'Online order changed; reload before requesting a correction'
      using errcode = '40001';
  end if;
  if v_order.payment_status <> 'paid' or v_order.sales_invoice_id is null then
    raise exception 'A paid order with a linked ERP sale is required'
      using errcode = '23514';
  end if;
  if v_intent = 'cancel_before_fulfillment'
     and v_order.status not in ('pending', 'confirmed', 'processing', 'ready_for_pickup') then
    raise exception 'Only a pre-fulfillment order can be cancelled through this correction'
      using errcode = '23514';
  end if;
  select * into v_invoice from public.sales_invoices invoice
  where invoice.id = v_order.sales_invoice_id and invoice.tenant_id = v_tenant
  for update;
  if not found or lower(v_invoice.status) not in (
    'confirmed', 'paid', 'overdue', 'sent', 'enviado', 'enviada',
    'emitido', 'emitida', 'issued'
  ) then
    raise exception 'The linked ERP sale is not eligible for correction'
      using errcode = '23514';
  end if;
  select coalesce(control_mode, 'disabled') into v_return_mode
  from public.sales_return_control_settings where tenant_id = v_tenant;
  if not found then v_return_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_credit_mode
  from public.sales_credit_note_control_settings where tenant_id = v_tenant;
  if not found then v_credit_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_refund_mode
  from public.sales_customer_refund_control_settings where tenant_id = v_tenant;
  if not found then v_refund_mode := 'disabled'; end if;
  if v_return_mode <> 'enforce' or v_credit_mode <> 'enforce'
     or v_refund_mode <> 'enforce' then
    raise exception 'Sales correction controls are not active for this tenant'
      using errcode = '55000';
  end if;
  if exists (
    select 1 from public.online_order_corrections correction
    where correction.tenant_id = v_tenant and correction.order_id = v_order.id
      and correction.processing_state <> 'applied'
      and correction.processing_state <> 'rejected'
  ) then
    raise exception 'This order already has an unresolved correction'
      using errcode = '23514';
  end if;

  create temporary table if not exists pg_temp.online_order_correction_lines(
    line_index integer primary key,
    credited_quantity integer not null,
    disposition text not null,
    net_amount numeric not null,
    tax_amount numeric not null,
    is_service boolean not null
  ) on commit drop;
  truncate pg_temp.online_order_correction_lines;

  for v_request in select value from jsonb_array_elements(p_lines) loop
    v_index := nullif(v_request->>'line_index', '')::integer;
    v_quantity := nullif(v_request->>'quantity', '')::integer;
    v_disposition := lower(btrim(coalesce(v_request->>'disposition', '')));
    if v_index is null or v_quantity is null or v_quantity <= 0 then
      raise exception 'Every correction line requires a valid index and quantity'
        using errcode = '22023';
    end if;
    select * into v_balance from public.sales_credit_note_line_balance_view balance
    where balance.tenant_id = v_tenant
      and balance.sales_invoice_id = v_order.sales_invoice_id
      and balance.source_line_index = v_index
      and balance.remaining_quantity > 0;
    if not found or v_quantity > v_balance.remaining_quantity then
      raise exception 'Correction line exceeds the remaining invoice balance'
        using errcode = '23514';
    end if;
    if v_disposition not in ('restock', 'quarantine', 'scrap', 'financial_only') then
      raise exception 'Invalid correction disposition' using errcode = '22023';
    end if;
    if (coalesce((v_balance.line_snapshot->>'is_service')::boolean, false)
          or v_balance.product_id is null)
       and v_disposition <> 'financial_only' then
      raise exception 'Services can only receive a financial correction'
        using errcode = '23514';
    end if;
    v_net := public.clp_round(
      v_balance.remaining_net * v_quantity / v_balance.remaining_quantity
    );
    v_tax := public.clp_round(
      v_balance.remaining_tax * v_quantity / v_balance.remaining_quantity
    );
    if v_net + v_tax <= 0 then
      raise exception 'Correction line has no remaining monetary balance'
        using errcode = '23514';
    end if;
    insert into pg_temp.online_order_correction_lines values (
      v_index, v_quantity, v_disposition, v_net, v_tax,
      coalesce((v_balance.line_snapshot->>'is_service')::boolean, false)
        or v_balance.product_id is null
    );
    v_total := v_total + v_net + v_tax;
  end loop;

  select jsonb_agg(jsonb_build_object(
    'line_index', line_index,
    'credited_quantity', credited_quantity,
    'disposition', disposition,
    'net_amount', net_amount,
    'tax_amount', tax_amount,
    'is_service', is_service
  ) order by line_index) into v_lines
  from pg_temp.online_order_correction_lines;

  select payment.payment_method_id into v_payment_method_id
  from public.sales_payments payment
  join public.payment_methods method
    on method.id = payment.payment_method_id
   and method.tenant_id = payment.tenant_id
   and method.is_active is true
  join public.accounts account
    on account.id = method.account_id and account.tenant_id = method.tenant_id
  where payment.tenant_id = v_tenant
    and payment.invoice_id = v_order.sales_invoice_id
    and payment.deleted_at is null
  order by payment.date desc, payment.created_at desc limit 1;
  if v_payment_method_id is null then
    raise exception 'The ERP sale has no active refund payment method and account'
      using errcode = '23514';
  end if;
  select coalesce(sum(correction.requested_amount), 0) into v_prior_refund
  from public.online_order_corrections correction
  where correction.tenant_id = v_tenant and correction.order_id = v_order.id
    and correction.processing_state = 'applied';
  if coalesce(v_order.refund_amount, 0) <> v_prior_refund
     or v_prior_refund + v_total > v_order.total then
    raise exception 'Online order refund projection is not safe for this request'
      using errcode = '23514';
  end if;
  if v_intent = 'cancel_before_fulfillment'
     and v_prior_refund + v_total <> v_order.total then
    raise exception 'Cancelling a paid order requires refunding its full remaining total'
      using errcode = '23514';
  end if;
  v_provider := case when lower(coalesce(v_order.payment_method, '')) = 'mercadopago'
    then 'mercadopago' else 'manual' end;
  if v_provider = 'mercadopago'
     and nullif(btrim(coalesce(v_order.payment_reference, '')), '') is null then
    raise exception 'Mercado Pago payment identifier is missing'
      using errcode = '23514';
  end if;

  perform set_config('app.online_order_correction_write', 'true', true);
  insert into public.online_order_corrections(
    tenant_id, order_id, sales_invoice_id, operation_key,
    expected_order_version, request_lines, reason, requested_amount,
    payment_method_id, provider, correction_intent, provider_payment_id,
    provider_idempotency_key, requested_by
  ) values (
    v_tenant, v_order.id, v_order.sales_invoice_id, btrim(p_operation_key),
    p_expected_order_version, v_lines, btrim(p_reason), v_total,
    v_payment_method_id, v_provider, v_intent,
    case when v_provider = 'mercadopago' then btrim(v_order.payment_reference) end,
    'online-order-refund:' || gen_random_uuid()::text, v_actor
  ) returning * into v_correction;
  perform set_config('app.online_order_correction_write', '', true);

  perform public.append_online_order_correction_event(
    v_correction, 'requested', 'request:' || btrim(p_operation_key), v_actor,
    jsonb_build_object(
      'order_version', p_expected_order_version,
      'amount', v_total,
      'currency', 'CLP',
      'provider', v_provider,
      'correction_intent', v_intent,
      'lines', v_lines
    )
  );
  return to_jsonb(v_correction) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.online_order_correction_write', '', true);
  raise;
end;
$$;

revoke all on function public.request_online_order_correction(
  uuid, bigint, jsonb, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.request_online_order_correction(
  uuid, bigint, jsonb, text, text, text
) to authenticated;

-- Authorization and deterministic feasibility check used immediately before
-- the Edge worker is allowed to read provider credentials or move money.
-- The provider call is still a separate transaction, so any later drift is
-- preserved as action_required rather than hidden.
create or replace function public.authorize_online_order_refund_execution(
  p_correction_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
  v_correction public.online_order_corrections%rowtype;
  v_order public.online_orders%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_line jsonb;
  v_balance record;
  v_item jsonb;
  v_product public.products%rowtype;
  v_target record;
  v_required integer;
  v_capacity integer;
  v_prior_refund numeric;
  v_return_mode text;
  v_credit_mode text;
  v_refund_mode text;
begin
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id and correction.tenant_id = v_tenant
  for update;
  if not found or not public.online_order_correction_actor_allowed(v_tenant)
     then
    raise exception 'Correction not found or execution not authorized'
      using errcode = '42501';
  end if;
  if v_correction.processing_state = 'applied' then
    return to_jsonb(v_correction) || jsonb_build_object(
      'authorized', true, 'replay', true
    );
  end if;
  if v_correction.provider_state not in ('pending', 'failed', 'unknown', 'succeeded')
     or v_correction.processing_state not in (
       'provider_pending', 'ready_to_apply', 'action_required'
     ) then
    raise exception 'Correction is not executable' using errcode = '23514';
  end if;

  select * into v_order from public.online_orders orders
  where orders.id = v_correction.order_id and orders.tenant_id = v_tenant
  for update;
  select * into v_invoice from public.sales_invoices invoice
  where invoice.id = v_correction.sales_invoice_id and invoice.tenant_id = v_tenant
  for update;
  if v_order.id is null or v_invoice.id is null
     or v_order.sales_invoice_id is distinct from v_invoice.id
     or v_order.payment_reference is distinct from v_correction.provider_payment_id
     or lower(v_invoice.status) not in (
       'confirmed', 'paid', 'overdue', 'sent', 'enviado', 'enviada',
       'emitido', 'emitida', 'issued'
     ) then
    raise exception 'Order or ERP sale linkage is no longer correction-safe'
      using errcode = '23514';
  end if;

  select coalesce(control_mode, 'disabled') into v_return_mode
  from public.sales_return_control_settings where tenant_id = v_tenant;
  if not found then v_return_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_credit_mode
  from public.sales_credit_note_control_settings where tenant_id = v_tenant;
  if not found then v_credit_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_refund_mode
  from public.sales_customer_refund_control_settings where tenant_id = v_tenant;
  if not found then v_refund_mode := 'disabled'; end if;
  if v_return_mode <> 'enforce' or v_credit_mode <> 'enforce'
     or v_refund_mode <> 'enforce' then
    raise exception 'Sales correction controls are not active for this tenant'
      using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.payment_methods method
    join public.accounts account
      on account.id = method.account_id and account.tenant_id = method.tenant_id
    where method.id = v_correction.payment_method_id
      and method.tenant_id = v_tenant and method.is_active is true
  ) then
    raise exception 'Active refund payment method and account are required'
      using errcode = '23514';
  end if;

  select coalesce(sum(correction.requested_amount), 0) into v_prior_refund
  from public.online_order_corrections correction
  where correction.tenant_id = v_tenant and correction.order_id = v_order.id
    and correction.processing_state = 'applied'
    and correction.id <> v_correction.id;
  if coalesce(v_order.refund_amount, 0) <> v_prior_refund
     or v_prior_refund + v_correction.requested_amount > v_order.total then
    raise exception 'Online order refund projection changed before execution'
      using errcode = '23514';
  end if;
  if v_correction.correction_intent = 'cancel_before_fulfillment'
     and (
       v_order.status not in ('pending', 'confirmed', 'processing', 'ready_for_pickup')
       or v_prior_refund + v_correction.requested_amount <> v_order.total
     ) then
    raise exception 'Paid cancellation is no longer eligible for full correction'
      using errcode = '23514';
  end if;

  for v_line in select value
    from jsonb_array_elements(v_correction.request_lines)
  loop
    select * into v_balance
    from public.sales_credit_note_line_balance_view balance
    where balance.tenant_id = v_tenant
      and balance.sales_invoice_id = v_invoice.id
      and balance.source_line_index = (v_line->>'line_index')::integer
      and balance.remaining_quantity > 0;
    if not found
       or (v_line->>'credited_quantity')::integer > v_balance.remaining_quantity
       or (v_line->>'net_amount')::numeric is distinct from public.clp_round(
         v_balance.remaining_net * (v_line->>'credited_quantity')::integer
           / v_balance.remaining_quantity
       )
       or (v_line->>'tax_amount')::numeric is distinct from public.clp_round(
         v_balance.remaining_tax * (v_line->>'credited_quantity')::integer
           / v_balance.remaining_quantity
       ) then
      raise exception 'Correction lines changed before provider execution'
        using errcode = '23514';
    end if;
    if v_line->>'disposition' = 'financial_only' then
      continue;
    end if;

    v_item := v_invoice.items->((v_line->>'line_index')::integer);
    select * into v_product from public.products product
    where product.id = nullif(v_item->>'product_id', '')::uuid
      and product.tenant_id = v_tenant;
    if not found or coalesce(v_product.is_service, false) then
      raise exception 'Physical correction product is no longer eligible'
        using errcode = '23514';
    end if;
    if coalesce(v_product.is_set, false) and not exists (
      select 1 from public.product_set_components component
      where component.tenant_id = v_tenant
        and component.set_product_id = v_product.id
    ) then
      raise exception 'Physical return set has no component provenance'
        using errcode = '23514';
    end if;
    for v_target in
      select v_product.id product_id,
        (v_line->>'credited_quantity')::integer quantity
      where not coalesce(v_product.is_set, false)
      union all
      select component.component_product_id,
        (v_line->>'credited_quantity')::integer * component.quantity_in_set
      from public.product_set_components component
      where component.tenant_id = v_tenant
        and component.set_product_id = v_product.id
        and coalesce(v_product.is_set, false)
    loop
      v_required := v_target.quantity;
      select coalesce(sum(greatest(
        abs(movement.quantity)::integer - coalesce((
          select sum(mapping.quantity)::integer
          from public.sales_return_line_movements mapping
          join public.sales_returns header on header.id = mapping.sales_return_id
          where mapping.original_sale_movement_id = movement.id
            and header.status = 'posted'
        ), 0), 0
      )), 0)::integer into v_capacity
      from public.stock_movements movement
      where movement.tenant_id = v_tenant
        and movement.product_id = v_target.product_id
        and movement.quantity < 0
        and (
          movement.source_document_id = v_invoice.id
          or movement.reference = 'sales_invoice:' || v_invoice.id::text
        )
        and not exists (
          select 1 from public.stock_movements reversal
          where reversal.reversal_of_id = movement.id
            and reversal.movement_type = 'sales_invoice_reversal'
        );
      if v_capacity < v_required then
        raise exception 'Physical return cannot be matched to active sale stock movements'
          using errcode = '23514';
      end if;
      if v_line->>'disposition' = 'restock' and exists (
        select 1 from public.products product
        where product.id = v_target.product_id and product.tenant_id = v_tenant
          and coalesce(product.inventory_qty, 0)
              <> coalesce(product.stock_quantity, 0)
      ) then
        raise exception 'Product stock columns disagree; provider refund blocked'
          using errcode = '23514';
      end if;
    end loop;
  end loop;

  return to_jsonb(v_correction) || jsonb_build_object(
    'authorized', true, 'replay', false
  );
end;
$$;

revoke all on function public.authorize_online_order_refund_execution(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.authorize_online_order_refund_execution(uuid)
  to authenticated;

create or replace function public.record_online_order_refund_provider_result(
  p_correction_id uuid,
  p_result text,
  p_provider_refund_id text,
  p_provider_status text,
  p_amount numeric,
  p_currency text,
  p_refunded_at timestamptz,
  p_provider_evidence jsonb,
  p_request_id text,
  p_error_code text default null,
  p_error_message text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correction public.online_order_corrections%rowtype;
  v_result text := lower(btrim(coalesce(p_result, '')));
  v_evidence jsonb;
  v_event text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Provider result recorder is service-role only'
      using errcode = '42501';
  end if;
  if v_result not in ('succeeded', 'failed', 'unknown')
     or nullif(btrim(coalesce(p_request_id, '')), '') is null
     or length(btrim(p_request_id)) not between 8 and 220 then
    raise exception 'Invalid provider result envelope' using errcode = '22023';
  end if;
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id for update;
  if not found or v_correction.provider <> 'mercadopago' then
    raise exception 'Mercado Pago correction not found' using errcode = '23503';
  end if;
  if v_correction.processing_state = 'applied' then
    return to_jsonb(v_correction) || jsonb_build_object('replay', true);
  end if;
  if exists (
    select 1 from public.online_order_correction_events event
    where event.tenant_id = v_correction.tenant_id
      and event.correction_id = v_correction.id
      and event.request_id = btrim(p_request_id)
  ) then
    return to_jsonb(v_correction) || jsonb_build_object('replay', true);
  end if;
  if v_correction.provider_state = 'succeeded' then
    if v_result = 'succeeded'
       and v_correction.provider_refund_id = btrim(coalesce(p_provider_refund_id, ''))
       and v_correction.provider_refund_amount is not distinct from p_amount
       and lower(btrim(coalesce(p_provider_status, ''))) = 'approved' then
      return to_jsonb(v_correction) || jsonb_build_object('replay', true);
    end if;
    raise exception 'Provider refund success is terminal'
      using errcode = '23000';
  end if;
  v_evidence := jsonb_strip_nulls(jsonb_build_object(
    'id', p_provider_evidence->>'id',
    'payment_id', p_provider_evidence->>'payment_id',
    'status', p_provider_evidence->>'status',
    'amount', p_provider_evidence->'amount',
    'date_created', p_provider_evidence->>'date_created',
    'refund_mode', p_provider_evidence->>'refund_mode'
  ));
  if v_result = 'succeeded' then
    if nullif(btrim(coalesce(p_provider_refund_id, '')), '') is null
       or lower(btrim(coalesce(p_provider_status, ''))) <> 'approved'
       or p_amount is distinct from v_correction.requested_amount
       or upper(btrim(coalesce(p_currency, ''))) <> 'CLP'
       or p_refunded_at is null
       or p_refunded_at > clock_timestamp() + interval '5 minutes' then
      raise exception 'Provider success evidence does not match the correction'
        using errcode = '23514';
    end if;
    if jsonb_typeof(p_provider_evidence) <> 'object'
       or p_provider_evidence->>'id' is distinct from btrim(p_provider_refund_id)
       or p_provider_evidence->>'payment_id' is distinct from v_correction.provider_payment_id
       or lower(coalesce(p_provider_evidence->>'status', '')) <> 'approved'
       or (p_provider_evidence->>'amount')::numeric
            is distinct from v_correction.requested_amount then
      raise exception 'Provider payload does not prove the requested refund'
        using errcode = '23514';
    end if;
    v_event := 'provider_succeeded';
  elsif v_result = 'failed' then
    v_event := 'provider_failed';
  else
    v_event := 'provider_unknown';
  end if;

  perform set_config('app.online_order_correction_write', 'true', true);
  update public.online_order_corrections correction set
    provider_state = v_result,
    processing_state = case when v_result = 'succeeded'
      then 'ready_to_apply' else 'action_required' end,
    provider_refund_id = case when v_result = 'succeeded'
      then btrim(p_provider_refund_id) else correction.provider_refund_id end,
    provider_refund_status = nullif(btrim(coalesce(p_provider_status, '')), ''),
    provider_refund_amount = case when v_result = 'succeeded'
      then p_amount else correction.provider_refund_amount end,
    provider_refunded_at = case when v_result = 'succeeded'
      then p_refunded_at else correction.provider_refunded_at end,
    provider_evidence = case when v_result = 'succeeded'
      then v_evidence else correction.provider_evidence end,
    last_error_code = case when v_result = 'succeeded'
      then null else left(nullif(btrim(coalesce(p_error_code, '')), ''), 96) end,
    last_error_message = case when v_result = 'succeeded'
      then null else left(nullif(btrim(coalesce(p_error_message, '')), ''), 320) end
  where correction.id = v_correction.id returning * into v_correction;
  perform set_config('app.online_order_correction_write', '', true);
  perform public.append_online_order_correction_event(
    v_correction, v_event, btrim(p_request_id), v_correction.requested_by,
    jsonb_build_object(
      'provider_status', p_provider_status,
      'provider_refund_id', p_provider_refund_id,
      'amount', p_amount,
      'currency', p_currency,
      'error_code', p_error_code
    )
  );
  return to_jsonb(v_correction) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.online_order_correction_write', '', true);
  raise;
end;
$$;

revoke all on function public.record_online_order_refund_provider_result(
  uuid, text, text, text, numeric, text, timestamptz, jsonb, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_refund_provider_result(
  uuid, text, text, text, numeric, text, timestamptz, jsonb, text, text, text
) to service_role;

create or replace function public.record_manual_online_order_refund_evidence(
  p_correction_id uuid,
  p_reference text,
  p_refunded_at timestamptz,
  p_request_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
  v_actor uuid := auth.uid();
  v_correction public.online_order_corrections%rowtype;
begin
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id and correction.tenant_id = v_tenant for update;
  if not found or v_correction.provider <> 'manual'
     or not public.online_order_correction_actor_allowed(v_tenant) then
    raise exception 'Manual correction not found or access denied' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_reference, '')), '') is null
     or length(btrim(p_reference)) > 180
     or p_refunded_at is null
     or p_refunded_at > clock_timestamp() + interval '5 minutes'
     or nullif(btrim(coalesce(p_request_id, '')), '') is null then
    raise exception 'Verified refund reference and date are required'
      using errcode = '22023';
  end if;
  if v_correction.provider_state = 'succeeded' then
    if v_correction.provider_refund_id = btrim(p_reference) then
      return to_jsonb(v_correction) || jsonb_build_object('replay', true);
    end if;
    raise exception 'Verified manual refund evidence is terminal'
      using errcode = '23000';
  end if;
  perform set_config('app.online_order_correction_write', 'true', true);
  update public.online_order_corrections correction set
    provider_state = 'succeeded', processing_state = 'ready_to_apply',
    provider_refund_id = btrim(p_reference), provider_refund_status = 'verified',
    provider_refund_amount = correction.requested_amount,
    provider_refunded_at = p_refunded_at,
    provider_evidence = jsonb_build_object(
      'reference', btrim(p_reference), 'verified_by', v_actor,
      'verified_at', clock_timestamp()
    ), last_error_code = null, last_error_message = null
  where correction.id = v_correction.id returning * into v_correction;
  perform set_config('app.online_order_correction_write', '', true);
  perform public.append_online_order_correction_event(
    v_correction, 'provider_succeeded', btrim(p_request_id), v_actor,
    jsonb_build_object('reference', btrim(p_reference), 'amount', v_correction.requested_amount)
  );
  return to_jsonb(v_correction) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.online_order_correction_write', '', true);
  raise;
end;
$$;

revoke all on function public.record_manual_online_order_refund_evidence(
  uuid, text, timestamptz, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_manual_online_order_refund_evidence(
  uuid, text, timestamptz, text
) to authenticated;

create or replace function public.enqueue_partial_online_order_refund_email(
  p_correction_id uuid
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correction public.online_order_corrections%rowtype;
  v_order public.online_orders%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_recipient text;
  v_delivery_mode text := 'dry_run';
  v_state text := 'pending';
  v_suppression_reason text;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
  v_source_event_key text;
  v_idempotency_key text;
  v_outbox_id uuid;
begin
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id;
  if not found or v_correction.processing_state <> 'applied' then return null; end if;
  select * into v_order from public.online_orders orders
  where orders.id = v_correction.order_id
    and orders.tenant_id = v_correction.tenant_id;
  -- Full refunds already enqueue from the canonical payment_transition event.
  if not found or v_order.payment_status = 'refunded' then return null; end if;
  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  if v_recipient !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;
  select * into v_tenant from public.tenants where id = v_order.tenant_id;
  select * into v_settings from public.transactional_email_settings
  where tenant_id = v_order.tenant_id;
  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;
  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url, v_tenant.custom_domain
  );
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', item.product_name,
    'sku', item.product_sku,
    'quantity', item.quantity,
    'unitPrice', item.unit_price,
    'subtotal', item.subtotal
  ) order by item.created_at, item.id), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = v_order.id and item.tenant_id = v_order.tenant_id;
  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', 'refund_completed',
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case when v_tenant.logo_url ~* '^https://[^[:space:]]+$'
        then v_tenant.logo_url else null end,
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
      'refundedAmount', v_correction.requested_amount,
      'cumulativeRefundedAmount', v_order.refund_amount,
      'refundedAt', v_correction.provider_refunded_at,
      'partialRefund', true
    )),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'order_receipt',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pedido · No constituye documento tributario'
    )
  );
  v_source_event_key := 'online_order_correction:' || v_correction.id::text;
  v_idempotency_key := 'txn-email:v1:' || encode(extensions.digest(
    convert_to(
      v_correction.tenant_id::text || ':' || v_order.id::text || ':' ||
      v_source_event_key || ':refund_completed:' || v_recipient,
      'UTF8'
    ), 'sha256'
  ), 'hex');
  select suppression.reason into v_suppression_reason
  from public.transactional_email_suppressions suppression
  where suppression.tenant_id = v_order.tenant_id
    and suppression.email_sha256 = encode(
      extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'), 'hex'
    )
    and suppression.lifted_at is null
  order by suppression.suppressed_at desc limit 1;
  if v_suppression_reason is not null then v_state := 'suppressed'; end if;
  insert into public.transactional_email_outbox(
    tenant_id, order_id, order_event_id, source_event_key, message_kind,
    template_key, template_version, recipient_email, recipient_name,
    sender_name, sender_email, reply_to_email, subject, render_payload,
    idempotency_key, delivery_mode, state, suppression_reason
  ) values (
    v_order.tenant_id, v_order.id, null, v_source_event_key, 'refund_completed',
    'refund_completed', 1, v_recipient,
    nullif(btrim(v_order.customer_name), ''),
    nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    nullif(lower(btrim(v_settings.from_email)), ''),
    nullif(lower(btrim(v_settings.reply_to_email)), ''),
    format('Reembolso parcial completado · %s', v_order.order_number),
    v_payload, v_idempotency_key, v_delivery_mode, v_state,
    v_suppression_reason
  ) on conflict (idempotency_key) do nothing returning id into v_outbox_id;
  if v_outbox_id is null then
    select id into v_outbox_id from public.transactional_email_outbox
    where idempotency_key = v_idempotency_key;
  end if;
  return v_outbox_id;
end;
$$;

revoke all on function public.enqueue_partial_online_order_refund_email(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.apply_online_order_correction(
  p_correction_id uuid,
  p_request_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
  v_actor uuid := auth.uid();
  v_correction public.online_order_corrections%rowtype;
  v_order public.online_orders%rowtype;
  v_return_result jsonb;
  v_credit_result jsonb;
  v_refund_result jsonb;
  v_return_lines jsonb;
  v_credit_lines jsonb := '[]'::jsonb;
  v_line jsonb;
  v_return_line_id uuid;
  v_refund_total numeric;
  v_return_mode text;
  v_credit_mode text;
  v_refund_mode text;
begin
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id and correction.tenant_id = v_tenant for update;
  if not found or not public.online_order_correction_actor_allowed(v_tenant) then
    raise exception 'Correction not found or access denied' using errcode = '42501';
  end if;
  if v_correction.processing_state = 'applied' then
    return to_jsonb(v_correction) || jsonb_build_object('replay', true);
  end if;
  if v_correction.provider_state <> 'succeeded'
     or v_correction.processing_state not in ('ready_to_apply', 'action_required') then
    raise exception 'Verified provider refund evidence is required before applying effects'
      using errcode = '23514';
  end if;
  if nullif(btrim(coalesce(p_request_id, '')), '') is null
     or length(btrim(p_request_id)) not between 8 and 220 then
    raise exception 'Valid apply request identifier is required' using errcode = '22023';
  end if;
  select * into v_order from public.online_orders orders
  where orders.id = v_correction.order_id and orders.tenant_id = v_tenant for update;
  if not found or v_order.sales_invoice_id is distinct from v_correction.sales_invoice_id
     or v_order.payment_reference is distinct from v_correction.provider_payment_id
        and v_correction.provider = 'mercadopago' then
    raise exception 'Order payment or invoice linkage changed after refund request'
      using errcode = '23514';
  end if;

  select coalesce(control_mode, 'disabled') into v_return_mode
  from public.sales_return_control_settings where tenant_id = v_tenant;
  if not found then v_return_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_credit_mode
  from public.sales_credit_note_control_settings where tenant_id = v_tenant;
  if not found then v_credit_mode := 'disabled'; end if;
  select coalesce(control_mode, 'disabled') into v_refund_mode
  from public.sales_customer_refund_control_settings where tenant_id = v_tenant;
  if not found then v_refund_mode := 'disabled'; end if;
  if v_return_mode <> 'enforce' or v_credit_mode <> 'enforce'
     or v_refund_mode <> 'enforce' then
    raise exception 'Sales correction controls are not active for this tenant'
      using errcode = '55000';
  end if;

  select jsonb_agg(jsonb_build_object(
    'line_index', (line->>'line_index')::integer,
    'returned_quantity', (line->>'credited_quantity')::integer,
    'disposition', line->>'disposition'
  )) into v_return_lines
  from jsonb_array_elements(v_correction.request_lines) line
  where line->>'disposition' <> 'financial_only';

  if v_return_lines is not null then
    v_return_result := public.create_sales_return(
      v_correction.sales_invoice_id, v_return_lines,
      v_correction.provider_refunded_at, v_correction.reason,
      'Corrección de pedido online ' || v_order.order_number,
      v_correction.provider_idempotency_key || ':return'
    );
  end if;

  for v_line in select value from jsonb_array_elements(v_correction.request_lines) loop
    if v_line->>'disposition' = 'financial_only' then
      v_credit_lines := v_credit_lines || jsonb_build_array(jsonb_build_object(
        'line_index', (v_line->>'line_index')::integer,
        'credited_quantity', (v_line->>'credited_quantity')::integer,
        'disposition', 'financial_only',
        'net_amount', (v_line->>'net_amount')::numeric,
        'tax_amount', (v_line->>'tax_amount')::numeric
      ));
    else
      select line.id into v_return_line_id from public.sales_return_lines line
      where line.tenant_id = v_tenant
        and line.sales_return_id = (v_return_result->>'sales_return_id')::uuid
        and line.source_line_index = (v_line->>'line_index')::integer;
      if v_return_line_id is null then
        raise exception 'Physical return line linkage is incomplete'
          using errcode = '23514';
      end if;
      v_credit_lines := v_credit_lines || jsonb_build_array(jsonb_build_object(
        'line_index', (v_line->>'line_index')::integer,
        'credited_quantity', (v_line->>'credited_quantity')::integer,
        'disposition', 'sales_return',
        'sales_return_line_id', v_return_line_id,
        'net_amount', (v_line->>'net_amount')::numeric,
        'tax_amount', (v_line->>'tax_amount')::numeric
      ));
    end if;
  end loop;

  v_credit_result := public.create_sales_credit_note(
    v_correction.sales_invoice_id, v_credit_lines,
    v_correction.provider_refunded_at, 'online_order_refund',
    v_correction.reason, v_correction.provider_idempotency_key || ':credit'
  );
  v_refund_result := public.create_sales_customer_refund(
    (v_credit_result->>'sales_credit_note_id')::uuid,
    v_correction.provider_refunded_at, v_correction.payment_method_id,
    v_correction.requested_amount, v_correction.provider_refund_id,
    v_correction.reason, v_correction.provider_idempotency_key || ':settlement'
  );

  select coalesce(sum(correction.requested_amount), 0) + v_correction.requested_amount
    into v_refund_total
  from public.online_order_corrections correction
  where correction.tenant_id = v_tenant and correction.order_id = v_order.id
    and correction.processing_state = 'applied'
    and correction.id <> v_correction.id;
  if coalesce(v_order.refund_amount, 0)
     <> v_refund_total - v_correction.requested_amount then
    raise exception 'Online order refund projection does not match prior applied corrections'
      using errcode = '23514';
  end if;
  if v_refund_total > v_order.total then
    raise exception 'Applied refunds exceed the online order total'
      using errcode = '23514';
  end if;

  perform set_config(
    'app.online_order_operation_key',
    'correction:' || v_correction.provider_idempotency_key,
    true
  );
  update public.online_orders orders set
    refund_amount = v_refund_total,
    refunded_at = v_correction.provider_refunded_at,
    payment_status = case when v_refund_total = orders.total
      then 'refunded' else orders.payment_status end,
    status = case
      when v_correction.correction_intent = 'cancel_before_fulfillment'
        and v_refund_total = orders.total then 'cancelled'
      else orders.status
    end
  where orders.id = v_order.id and orders.tenant_id = v_tenant;

  perform set_config('app.online_order_correction_write', 'true', true);
  update public.online_order_corrections correction set
    processing_state = 'applied',
    sales_return_id = nullif(v_return_result->>'sales_return_id', '')::uuid,
    sales_credit_note_id = (v_credit_result->>'sales_credit_note_id')::uuid,
    sales_customer_refund_id = (v_refund_result->>'refund_id')::uuid,
    last_error_code = null, last_error_message = null,
    applied_by = v_actor, applied_at = clock_timestamp()
  where correction.id = v_correction.id returning * into v_correction;
  perform set_config('app.online_order_correction_write', '', true);
  perform public.append_online_order_correction_event(
    v_correction, 'apply_succeeded', btrim(p_request_id), v_actor,
    jsonb_build_object(
      'sales_return_id', v_correction.sales_return_id,
      'sales_credit_note_id', v_correction.sales_credit_note_id,
      'sales_customer_refund_id', v_correction.sales_customer_refund_id,
      'order_refund_total', v_refund_total,
      'correction_intent', v_correction.correction_intent,
      'order_payment_status', case when v_refund_total = v_order.total
        then 'refunded' else v_order.payment_status end
    )
  );
  if v_refund_total < v_order.total then
    perform public.enqueue_partial_online_order_refund_email(v_correction.id);
  end if;
  return to_jsonb(v_correction)
    || jsonb_build_object('replay', false, 'order_refund_total', v_refund_total);
exception when others then
  perform set_config('app.online_order_correction_write', '', true);
  raise;
end;
$$;

revoke all on function public.apply_online_order_correction(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.apply_online_order_correction(uuid, text)
  to authenticated;

create or replace function public.record_online_order_correction_apply_failure(
  p_correction_id uuid,
  p_request_id text,
  p_error_code text,
  p_error_message text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correction public.online_order_corrections%rowtype;
  v_service boolean := coalesce(auth.role(), '') = 'service_role';
begin
  select * into v_correction from public.online_order_corrections correction
  where correction.id = p_correction_id for update;
  if not found or (
    not v_service and (
      v_correction.tenant_id is distinct from public.user_tenant_id()
      or not public.online_order_correction_actor_allowed(v_correction.tenant_id)
    )
  ) then
    raise exception 'Correction not found or failure record not authorized'
      using errcode = '42501';
  end if;
  if v_correction.processing_state = 'applied' then
    return to_jsonb(v_correction) || jsonb_build_object('replay', true);
  end if;
  perform set_config('app.online_order_correction_write', 'true', true);
  update public.online_order_corrections correction set
    processing_state = 'action_required',
    last_error_code = left(coalesce(nullif(btrim(p_error_code), ''), 'apply_failed'), 96),
    last_error_message = left(coalesce(nullif(btrim(p_error_message), ''),
      'Internal correction effects could not be applied.'), 320)
  where correction.id = v_correction.id returning * into v_correction;
  perform set_config('app.online_order_correction_write', '', true);
  perform public.append_online_order_correction_event(
    v_correction, 'apply_failed', btrim(p_request_id),
    coalesce(auth.uid(), v_correction.requested_by),
    jsonb_build_object('error_code', v_correction.last_error_code)
  );
  return to_jsonb(v_correction) || jsonb_build_object('replay', false);
exception when others then
  perform set_config('app.online_order_correction_write', '', true);
  raise;
end;
$$;

revoke all on function public.record_online_order_correction_apply_failure(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_correction_apply_failure(
  uuid, text, text, text
) to authenticated, service_role;

create or replace function public.prevent_void_of_online_order_correction_artifact()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;
  if exists (
    select 1 from public.online_order_corrections correction
    where correction.tenant_id = old.tenant_id
      and correction.processing_state = 'applied'
      and (
        (tg_table_name = 'sales_returns' and correction.sales_return_id = old.id)
        or (tg_table_name = 'sales_credit_notes'
          and correction.sales_credit_note_id = old.id)
        or (tg_table_name = 'sales_customer_refunds'
          and correction.sales_customer_refund_id = old.id)
      )
  ) then
    raise exception 'Online-order correction artifacts require a canonical compensation workflow and cannot be voided directly'
      using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_online_correction_sales_return
  on public.sales_returns;
create trigger trg_protect_online_correction_sales_return
  before update of status or delete on public.sales_returns
  for each row execute function public.prevent_void_of_online_order_correction_artifact();
drop trigger if exists trg_protect_online_correction_credit_note
  on public.sales_credit_notes;
create trigger trg_protect_online_correction_credit_note
  before update of status or delete on public.sales_credit_notes
  for each row execute function public.prevent_void_of_online_order_correction_artifact();
drop trigger if exists trg_protect_online_correction_customer_refund
  on public.sales_customer_refunds;
create trigger trg_protect_online_correction_customer_refund
  before update of status or delete on public.sales_customer_refunds
  for each row execute function public.prevent_void_of_online_order_correction_artifact();

revoke all on function public.prevent_void_of_online_order_correction_artifact()
  from public, anon, authenticated, service_role;

create or replace view public.online_order_correction_status_view
with (security_invoker = true) as
select distinct on (correction.tenant_id, correction.order_id)
  correction.id correction_id,
  correction.tenant_id,
  correction.order_id,
  correction.sales_invoice_id,
  correction.requested_amount,
  correction.currency,
  correction.provider,
  correction.provider_state,
  correction.processing_state,
  correction.provider_refund_id,
  correction.sales_return_id,
  correction.sales_credit_note_id,
  correction.sales_customer_refund_id,
  correction.last_error_code,
  correction.last_error_message,
  correction.requested_by,
  correction.requested_at,
  correction.applied_by,
  correction.applied_at,
  correction.updated_at,
  correction.version,
  correction.correction_intent
from public.online_order_corrections correction
order by correction.tenant_id, correction.order_id,
  correction.requested_at desc, correction.id desc;

grant select on public.online_order_correction_status_view to authenticated;

comment on table public.online_order_corrections is
  'Replay-safe projection for online-order correction sagas. Provider money evidence precedes atomic internal stock/accounting compensation.';
comment on table public.online_order_correction_events is
  'Immutable audit trail for correction requests, provider outcomes and internal application attempts.';
comment on function public.apply_online_order_correction(uuid, text) is
  'Applies existing sales-return, credit-note and refund-accounting kernels atomically after independently committed external refund evidence.';

commit;
