-- Deployment status: NOT DEPLOYED.
-- Adds the payment-owned, replay-safe correction command used by the sales
-- payment detail form. The payment continues to settle accounts receivable
-- only; revenue, IVA and inventory remain owned by the invoice/source flow.
-- Recovery: roll the client back to read-only payment details, remove the
-- correction-command guard trigger, and revoke the two RPC grants. Preserve
-- this immutable event table and its accounting evidence; never drop history.
begin;

create table if not exists public.sales_payment_edit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payment_id uuid not null,
  invoice_id uuid not null
    references public.sales_invoices(id) on delete restrict,
  operation_key text not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  request_snapshot jsonb not null,
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  source text not null,
  source_managed boolean not null,
  financial_fields_changed boolean not null,
  before_snapshot jsonb not null,
  after_snapshot jsonb not null,
  trace_operation_id uuid not null,
  prior_journal_entry_id uuid not null,
  current_journal_entry_id uuid not null,
  response_snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, payment_id)
    references public.sales_payments(tenant_id, id) on delete restrict,
  foreign key (tenant_id, trace_operation_id)
    references public.inventory_accounting_operations(tenant_id, id)
    on delete restrict
);

comment on table public.sales_payment_edit_events is
  'Immutable tenant-scoped command receipts and before/after evidence for audited sales-payment corrections.';
comment on column public.sales_payment_edit_events.financial_fields_changed is
  'True when amount, payment date, or payment method changed and the receivable-settlement journal was superseded.';
comment on column public.sales_payment_edit_events.source_managed is
  'True for POS, quick-sale, ecommerce, online-order, or provider-owned payments; these commands may change notes only.';
comment on column public.sales_payment_edit_events.response_snapshot is
  'Exact successful RPC response used for committed-but-unacknowledged readback and replay.';

create index if not exists idx_sales_payment_edit_events_payment
  on public.sales_payment_edit_events(
    tenant_id, payment_id, created_at desc, id desc
  );
create index if not exists idx_sales_payment_edit_events_trace
  on public.sales_payment_edit_events(tenant_id, trace_operation_id);

alter table public.sales_payment_edit_events enable row level security;

drop policy if exists sales_payment_edit_events_select
  on public.sales_payment_edit_events;
create policy sales_payment_edit_events_select
  on public.sales_payment_edit_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.sales_payment_edit_events
  from public, anon, authenticated, service_role;
grant select on public.sales_payment_edit_events to authenticated;

create or replace function public.guard_sales_payment_edit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Sales payment edit events are immutable'
    using errcode = '55000';
end;
$$;

drop trigger if exists trg_sales_payment_edit_events_immutable
  on public.sales_payment_edit_events;
create trigger trg_sales_payment_edit_events_immutable
  before update or delete on public.sales_payment_edit_events
  for each row execute function public.guard_sales_payment_edit_event();

revoke all on function public.guard_sales_payment_edit_event()
  from public, anon, authenticated, service_role;

-- Authenticated clients must use the audited RPC for editable payment fields.
-- Server/provider flows run without an employee auth.uid() and retain their
-- existing ability to bind durable provider identity after settlement.
create or replace function public.guard_sales_payment_correction_command()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return NEW;
  end if;

  if NEW.id is distinct from OLD.id
     or NEW.tenant_id is distinct from OLD.tenant_id
     or NEW.invoice_id is distinct from OLD.invoice_id
     or NEW.invoice_reference is distinct from OLD.invoice_reference
     or NEW.idempotency_key is distinct from OLD.idempotency_key
     or NEW.tax_treatment is distinct from OLD.tax_treatment
     or NEW.net_amount is distinct from OLD.net_amount
     or NEW.iva_amount is distinct from OLD.iva_amount
     or NEW.deleted_at is distinct from OLD.deleted_at
     or NEW.deleted_by is distinct from OLD.deleted_by
     or NEW.created_at is distinct from OLD.created_at then
    raise exception 'Payment identity and server-owned tax fields are immutable'
      using errcode = 'check_violation';
  end if;

  if (
    NEW.payment_method_id is distinct from OLD.payment_method_id
    or NEW.amount is distinct from OLD.amount
    or NEW.date is distinct from OLD.date
    or NEW.reference is distinct from OLD.reference
    or NEW.notes is distinct from OLD.notes
  ) and current_setting('app.sales_payment_correction_command', true)
        is distinct from 'true' then
    raise exception 'Use the audited sales-payment correction command'
      using errcode = 'insufficient_privilege';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sales_payments_01_correction_command
  on public.sales_payments;
create trigger trg_sales_payments_01_correction_command
  before update on public.sales_payments
  for each row execute function public.guard_sales_payment_correction_command();

revoke all on function public.guard_sales_payment_correction_command()
  from public, anon, authenticated, service_role;

-- Historical payment methods may be deactivated after their payments post.
-- Preserve that method on metadata/amount/date corrections, but never permit a
-- correction to select a different inactive method.
create or replace function public.validate_sales_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
  v_net numeric(12,2);
begin
  if TG_OP = 'DELETE' then
    perform public.assert_sales_payment_access(OLD.tenant_id);
    return OLD;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de venta.';
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de venta asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;
  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception 'El pago no pertenece al mismo tenant que la factura de venta.';
  end if;

  perform public.assert_sales_payment_access(NEW.tenant_id);

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;
  NEW.invoice_reference := coalesce(
    nullif(btrim(coalesce(NEW.invoice_reference, '')), ''),
    v_invoice.invoice_number
  );

  -- The payment is cash settlement only. Tax and revenue stay invoice-owned;
  -- this row mirrors the whole-document classification for reporting.
  NEW.tax_treatment := v_invoice.tax_treatment;
  if v_invoice.tax_treatment = 'tax_included' then
    v_net := public.clp_round(v_amount / 1.19);
    NEW.net_amount := v_net;
    NEW.iva_amount := v_amount - v_net;
  else
    NEW.net_amount := v_amount;
    NEW.iva_amount := 0;
  end if;

  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if NEW.payment_method_id is null or not exists (
    select 1
      from public.payment_methods method
     where method.id = NEW.payment_method_id
       and method.tenant_id = NEW.tenant_id
       and (
         coalesce(method.is_active, true)
         or (
           TG_OP = 'UPDATE'
           and NEW.payment_method_id is not distinct from OLD.payment_method_id
           and current_setting(
             'app.sales_payment_correction_command',
             true
           ) = 'true'
         )
       )
  ) then
    raise exception 'Medio de pago no encontrado o inactivo para el tenant activo.';
  end if;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_existing_paid
    from public.sales_payments payment
   where payment.invoice_id = NEW.invoice_id
     and payment.tenant_id = NEW.tenant_id
     and payment.deleted_at is null
     and payment.id is distinct from NEW.id;

  v_remaining := public.clp_round(
    greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0)
  );
  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de venta. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

revoke all on function public.validate_sales_payment_integrity()
  from public, anon, authenticated, service_role;

create or replace function public.get_sales_payment_edit_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_active_profile_count integer;
  v_key text := nullif(btrim(p_operation_key), '');
  v_event public.sales_payment_edit_events%rowtype;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  if v_actor is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id
    into v_tenant
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  perform public.assert_sales_payment_access(v_tenant);

  if v_key is null or length(v_key) > 128 then
    raise exception 'A valid payment correction operation key is required';
  end if;

  select * into v_event
    from public.sales_payment_edit_events event
   where event.tenant_id = v_tenant
     and event.operation_key = v_key;

  if not found then
    return null;
  end if;

  return v_event.response_snapshot || jsonb_build_object('replayed', true);
end;
$$;

create or replace function public.correct_sales_payment(
  p_payment_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_key text,
  p_payment_method_id uuid,
  p_amount numeric,
  p_date timestamptz,
  p_reference text,
  p_notes text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_role text;
  v_permissions jsonb := '{}'::jsonb;
  v_active_profile_count integer;
  v_key text := nullif(btrim(p_operation_key), '');
  v_reference text := nullif(btrim(coalesce(p_reference, '')), '');
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_amount numeric := public.clp_round(p_amount);
  v_payload jsonb;
  v_payload_hash text;
  v_receipt public.sales_payment_edit_events%rowtype;
  v_before public.sales_payments%rowtype;
  v_saved public.sales_payments%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_source text;
  v_source_managed boolean;
  v_financial_changed boolean;
  v_reference_changed boolean;
  v_notes_changed boolean;
  v_prior_journal_count integer;
  v_prior_journal_id uuid;
  v_prior_journal_balanced boolean;
  v_current_journal_count integer;
  v_current_journal_id uuid;
  v_current_journal_balanced boolean;
  v_line_debit numeric;
  v_line_credit numeric;
  v_method_debit_count integer;
  v_receivable_credit_count integer;
  v_trace_operation_id uuid;
  v_stock_movement_count integer;
  v_expected_net numeric;
  v_expected_iva numeric;
  v_event_id uuid := gen_random_uuid();
  v_event_created_at timestamptz := clock_timestamp();
  v_event_snapshot jsonb;
  v_result jsonb;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  if v_actor is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id, profile.role,
         coalesce(profile.permissions, '{}'::jsonb)
    into v_tenant, v_role, v_permissions
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  perform public.assert_sales_payment_access(v_tenant);

  if v_key is null or length(v_key) > 128 then
    raise exception 'A valid payment correction operation key is required';
  end if;
  if p_payment_id is null or p_expected_updated_at is null then
    raise exception 'Payment id and expected updated_at are required';
  end if;
  if p_payment_method_id is null then
    raise exception 'Payment method is required';
  end if;
  if p_amount is null or v_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  if p_date is null then
    raise exception 'Payment date is required';
  end if;
  if v_reason is null or length(v_reason) < 3 or length(v_reason) > 1000 then
    raise exception 'A correction reason between 3 and 1000 characters is required';
  end if;
  if length(coalesce(v_reference, '')) > 512 then
    raise exception 'Payment reference allows at most 512 characters';
  end if;
  if length(coalesce(v_notes, '')) > 4000 then
    raise exception 'Payment notes allow at most 4000 characters';
  end if;

  v_payload := jsonb_build_object(
    'payment_id', p_payment_id,
    'expected_updated_at', p_expected_updated_at,
    'payment_method_id', p_payment_method_id,
    'amount_clp', v_amount,
    'date', p_date,
    'reference', v_reference,
    'notes', v_notes,
    'reason', v_reason
  );
  v_payload_hash := encode(
    extensions.digest(v_payload::text, 'sha256'),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':sales-payment-correction:' || v_key,
    0
  ));

  select * into v_receipt
    from public.sales_payment_edit_events event
   where event.tenant_id = v_tenant
     and event.operation_key = v_key;
  if found then
    if v_receipt.request_hash is distinct from v_payload_hash then
      raise exception 'Payment correction key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replayed', true);
  end if;

  select * into v_before
    from public.sales_payments payment
   where payment.id = p_payment_id
     and payment.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Payment not found for the active tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.updated_at is distinct from p_expected_updated_at then
    raise exception 'Payment was modified after this form was loaded'
      using errcode = 'serialization_failure';
  end if;
  if v_before.deleted_at is not null then
    raise exception 'Deleted payments cannot be corrected'
      using errcode = 'check_violation';
  end if;

  select * into v_invoice
    from public.sales_invoices invoice
   where invoice.id = v_before.invoice_id
     and invoice.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Payment invoice is missing or belongs to another tenant'
      using errcode = 'foreign_key_violation';
  end if;
  if lower(coalesce(v_invoice.status, '')) in (
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ) then
    raise exception 'Payments on cancelled invoices cannot be corrected'
      using errcode = 'check_violation';
  end if;
  if v_before.tax_treatment is distinct from v_invoice.tax_treatment then
    raise exception 'Payment tax classification requires accounting review before correction'
      using errcode = 'check_violation';
  end if;

  v_source := coalesce(nullif(btrim(v_invoice.source), ''), 'manual_sale');
  v_source_managed := v_source in ('pos', 'ecommerce', 'quick_sale')
    or exists (
      select 1
        from public.online_orders orders
       where orders.tenant_id = v_tenant
         and (
           orders.manual_payment_id = v_before.id
           or orders.sales_invoice_id = v_before.invoice_id
         )
    )
    or lower(coalesce(v_before.idempotency_key, ''))
         ~ '^(mercadopago|online_order|provider)[_:]';

  v_financial_changed :=
    p_payment_method_id is distinct from v_before.payment_method_id
    or v_amount is distinct from public.clp_round(v_before.amount)
    or p_date is distinct from v_before.date;
  v_reference_changed := v_reference is distinct from
    nullif(btrim(coalesce(v_before.reference, '')), '');
  v_notes_changed := v_notes is distinct from
    nullif(btrim(coalesce(v_before.notes, '')), '');

  if not v_financial_changed
     and not v_reference_changed
     and not v_notes_changed then
    raise exception 'Payment correction contains no changes'
      using errcode = 'check_violation';
  end if;

  if v_source_managed
     and (v_financial_changed or v_reference_changed) then
    raise exception 'Source-managed payments allow notes-only corrections; use the source correction workflow for financial or reference changes'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed
     and v_role not in ('admin', 'manager', 'accountant')
     and coalesce(v_permissions->'access_accounting', 'false'::jsonb)
           is distinct from 'true'::jsonb then
    raise exception 'Financial payment corrections require accounting authorization'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
      from public.payment_methods method
     where method.id = p_payment_method_id
       and method.tenant_id = v_tenant
       and (
         p_payment_method_id = v_before.payment_method_id
         or method.is_active is true
       )
  ) then
    raise exception 'Payment method is unavailable for the current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  select count(*)::integer,
         (array_agg(entry.id order by entry.created_at, entry.id))[1],
         coalesce(bool_and(
           public.clp_round(entry.total_debit)
             = public.clp_round(v_before.amount)
           and public.clp_round(entry.total_credit)
             = public.clp_round(v_before.amount)
           and lower(entry.status) = 'posted'
         ), false)
    into v_prior_journal_count, v_prior_journal_id,
         v_prior_journal_balanced
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'sales_payments'
     and entry.source_reference = v_before.id::text;

  if v_prior_journal_count <> 1 or not v_prior_journal_balanced then
    raise exception 'Payment current journal requires accounting review before correction'
      using errcode = 'check_violation';
  end if;

  perform set_config('app.sales_payment_correction_command', 'true', true);
  perform set_config('app.inventory_idempotency_key', v_key, true);
  perform set_config(
    'app.journal_supersession_reason',
    'sales_payment_audited_correction',
    true
  );

  update public.sales_payments payment
     set payment_method_id = p_payment_method_id,
         amount = v_amount,
         date = p_date,
         reference = v_reference,
         notes = v_notes,
         updated_at = clock_timestamp()
   where payment.id = v_before.id
     and payment.tenant_id = v_tenant
  returning * into v_saved;

  if v_saved.tenant_id is distinct from v_before.tenant_id
     or v_saved.invoice_id is distinct from v_before.invoice_id
     or v_saved.idempotency_key is distinct from v_before.idempotency_key
     or v_saved.created_at is distinct from v_before.created_at
     or v_saved.deleted_at is distinct from v_before.deleted_at
     or v_saved.deleted_by is distinct from v_before.deleted_by
     or v_saved.invoice_reference is distinct from coalesce(
       v_before.invoice_reference,
       v_invoice.invoice_number
     )
     or v_saved.tax_treatment is distinct from v_invoice.tax_treatment then
    raise exception 'Payment identity changed during correction'
      using errcode = 'check_violation';
  end if;

  if v_invoice.tax_treatment = 'tax_included' then
    v_expected_net := public.clp_round(v_saved.amount / 1.19);
    v_expected_iva := public.clp_round(v_saved.amount) - v_expected_net;
  else
    v_expected_net := public.clp_round(v_saved.amount);
    v_expected_iva := 0;
  end if;
  if public.clp_round(v_saved.net_amount) is distinct from v_expected_net
     or public.clp_round(v_saved.iva_amount) is distinct from v_expected_iva then
    raise exception 'Payment tax mirrors do not reconcile after correction'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer,
         (array_agg(entry.id order by entry.created_at, entry.id))[1],
         coalesce(bool_and(
           public.clp_round(entry.total_debit)
             = public.clp_round(v_saved.amount)
           and public.clp_round(entry.total_credit)
             = public.clp_round(v_saved.amount)
           and lower(entry.status) = 'posted'
         ), false)
    into v_current_journal_count, v_current_journal_id,
         v_current_journal_balanced
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'sales_payments'
     and entry.source_reference = v_saved.id::text;

  if v_current_journal_count <> 1 or not v_current_journal_balanced then
    raise exception 'Payment correction did not leave exactly one balanced current journal'
      using errcode = 'check_violation';
  end if;

  select public.clp_round(coalesce(sum(line.debit_amount), 0)),
         public.clp_round(coalesce(sum(line.credit_amount), 0)),
         count(*) filter (
           where line.account_id = method.account_id
             and public.clp_round(line.debit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.credit_amount) = 0
         )::integer,
         count(*) filter (
           where line.account_code = '1130'
             and public.clp_round(line.credit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.debit_amount) = 0
         )::integer
    into v_line_debit, v_line_credit, v_method_debit_count,
         v_receivable_credit_count
    from public.journal_lines line
    cross join public.payment_methods method
   where line.entry_id = v_current_journal_id
     and line.tenant_id = v_tenant
     and method.id = v_saved.payment_method_id
     and method.tenant_id = v_tenant;

  if v_line_debit is distinct from public.clp_round(v_saved.amount)
     or v_line_credit is distinct from public.clp_round(v_saved.amount)
     or v_method_debit_count <> 1
     or v_receivable_credit_count <> 1 then
    raise exception 'Payment journal lines do not reconcile to cash and accounts receivable'
      using errcode = 'check_violation';
  end if;

  select operation.id into v_trace_operation_id
    from public.inventory_accounting_operations operation
   where operation.tenant_id = v_tenant
     and operation.operation_key = format(
       'sales_payment:%s:update:%s',
       v_saved.id,
       v_key
     )
     and operation.document_type = 'sales_payment'
     and operation.document_id = v_saved.id
     and operation.action = 'update'
     and operation.outcome = 'completed';
  if not found then
    raise exception 'Completed payment correction trace was not recorded'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer into v_stock_movement_count
    from public.stock_movements movement
   where movement.tenant_id = v_tenant
     and movement.operation_id = v_trace_operation_id;
  if v_stock_movement_count <> 0 then
    raise exception 'Payment correction created an inventory movement'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed then
    if v_current_journal_id = v_prior_journal_id then
      raise exception 'Financial payment correction did not supersede its journal'
        using errcode = 'check_violation';
    end if;
    if not exists (
      select 1
        from public.journal_supersession_evidence evidence
       where evidence.tenant_id = v_tenant
         and evidence.journal_entry_id = v_prior_journal_id
         and evidence.operation_id = v_trace_operation_id
         and evidence.source_module = 'sales_payments'
         and evidence.source_reference = v_saved.id::text
         and evidence.captured_reason = 'sales_payment_audited_correction'
    ) then
      raise exception 'Superseded payment journal evidence was not preserved'
        using errcode = 'check_violation';
    end if;
  elsif v_current_journal_id is distinct from v_prior_journal_id then
    raise exception 'Metadata-only payment correction replaced its journal'
      using errcode = 'check_violation';
  end if;

  v_event_snapshot := jsonb_build_object(
    'id', v_event_id,
    'tenant_id', v_tenant,
    'payment_id', v_saved.id,
    'invoice_id', v_saved.invoice_id,
    'operation_key', v_key,
    'reason', v_reason,
    'source', v_source,
    'source_managed', v_source_managed,
    'financial_fields_changed', v_financial_changed,
    'trace_operation_id', v_trace_operation_id,
    'prior_journal_entry_id', v_prior_journal_id,
    'current_journal_entry_id', v_current_journal_id,
    'created_by', v_actor,
    'created_at', v_event_created_at
  );
  v_result := jsonb_build_object(
    'payment', to_jsonb(v_saved),
    'event', v_event_snapshot,
    'replayed', false
  );

  insert into public.sales_payment_edit_events (
    id, tenant_id, payment_id, invoice_id, operation_key,
    request_hash, request_snapshot, reason, source, source_managed,
    financial_fields_changed, before_snapshot, after_snapshot,
    trace_operation_id, prior_journal_entry_id, current_journal_entry_id,
    response_snapshot, created_by, created_at
  ) values (
    v_event_id, v_tenant, v_saved.id, v_saved.invoice_id, v_key,
    v_payload_hash, v_payload, v_reason, v_source, v_source_managed,
    v_financial_changed, to_jsonb(v_before), to_jsonb(v_saved),
    v_trace_operation_id, v_prior_journal_id, v_current_journal_id,
    v_result, v_actor, v_event_created_at
  );

  perform set_config('app.sales_payment_correction_command', '', true);
  perform set_config('app.inventory_idempotency_key', '', true);
  perform set_config('app.journal_supersession_reason', '', true);
  return v_result;
exception
  when others then
    perform set_config('app.sales_payment_correction_command', '', true);
    perform set_config('app.inventory_idempotency_key', '', true);
    perform set_config('app.journal_supersession_reason', '', true);
    raise;
end;
$$;

revoke all on function public.get_sales_payment_edit_operation(text)
  from public, anon, authenticated, service_role;
revoke all on function public.correct_sales_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.get_sales_payment_edit_operation(text)
  to authenticated;
grant execute on function public.correct_sales_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) to authenticated;

comment on function public.get_sales_payment_edit_operation(text) is
  'Reads the active tenant immutable correction receipt after a lost RPC acknowledgement; returns null when the key is unknown.';
comment on function public.correct_sales_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) is
  'Replay-safe optimistic sales-payment correction. Preserves invoice/payment identity, blocks source-owned financial edits, rebuilds and archives settlement journals when needed, and proves zero inventory effects.';

commit;
